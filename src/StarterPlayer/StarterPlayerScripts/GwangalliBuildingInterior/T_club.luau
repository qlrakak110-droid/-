--!strict
-- GwangalliBuildingInterior/T_club: CLUB OCEAN 광안 의 방 (Venues.luau 의 방, Scan.fitRoom).
--   clublounge   OCEAN SKY LOUNGE 2F (42x173): 창가 소파 묶음마다 러그 · 펜던트 · 사이드 테이블 램프, 창 사이 암체어 · 2인 테이블 ·
--                망원경, 커튼 (상호작용), 남쪽 DJ 코너 + 스피커 + 샴페인 셀러 + 칵테일 하이테이블, 북쪽 라이브러리 라운지 +
--                아트월 · VIP 호스트 데스크 (예약 태블릿), 슬랫 천장 · 라인 조명 · 무드 조명 (DJ 콘솔에서 바꿈)
--   rooftop      OCEAN ROOFTOP (54x148): 진짜 루프탑 바 (백바 · 라벨 병 · 탭 · 아이스웰 · POS · 메뉴 · 스툴 · 퍼걸러),
--                파라솔 하이테이블 · 레일 바 레지 · 망원경 · 카바나 커튼 (상호작용) · 랜턴 · 업라이트 · 난간 LED · DJ 코너 · 화분 · 흡연구역
--   hiphop       ROOM 2 · HIP-HOP (50x70): 그라피티 벽화 (플레이트 글자 · 드립 · 태그) · 스티커/포스터 벽 · 벽돌 · 무대 트러스 ·
--                바리케이드 · 모니터 스피커 · 사이퍼 드링크 레일 · 스니커/머치 벽 · 붐박스 · 네온 아트 · 코너 스피커
--   clubwc       여자 / 남자 화장실 (20x41): 파우더 카운터 · 할리우드 거울 · 라운지 코너 · 샹들리에 · 생리대 무료 함 (여) /
--                가림벽 · 그루밍 카운터 · 소변기 선반 · 센서 · 청소 카트 · 배플 천장 (남), 종이타월 · 휴지통 · 배수구 · 금연 ·
--                불법촬영 점검 · 청소 점검표 · 손 소독제 · 방향제 · 칸마다 휴지걸이 · 안내문 · 옷걸이 · 위생용품 수거함
-- 상호작용 (클라이언트 전용, 서버 행동 없음): 라운지 = 커튼 · 무드 조명 · VIP 예약 태블릿 · 망원경 / 루프탑 = 메뉴 넘기기 ·
--   카바나 커튼 · 망원경 · 조명 모드 / 힙합 = 붐박스 · MC 마이크(ON AIR) · 태그 남기기 / 화장실 = 거울 조명 · 종이타월 ·
--   향수(여) · 가글(남) / 복도 = 라인업 보기 · 정수기 · 휴대폰 충전 + 사이니지 화면 순환
--   clubcorridor 복도 (17x76): 가죽 징두리 · 사진 갤러리 + 픽처 라이트 · LED 라인 · 벤치 · 정수기 · 휴대폰 충전함 · 소화전 · AED ·
--                라인업 라이트박스 · 사이니지 화면 · 매달린 안내판 · 비상구 유도등 · CCTV
--
-- 맵 건물이 방 프레임(월드 축)에서 약 -0.86도 돌아가 있어서, 모든 소품은 '정렬 프레임' R.A (바닥 파트의 회전) 기준으로 짓고
-- 벽 안쪽 면은 맵에서 잰 값 (ROOMS) 을 씁니다.
-- 게임플레이 계약 (arcade_club.json / systems.json): ClubTable · ClubZone · ClubLight · ClubFloorTile · ClubNPC · ClubShowAnchor ·
--   ParadeRoute · 모든 Seat (소파 · 데이베드 · 바 스툴) · LEDScreen · DeskPanel · 무대 · DJ 데스크 · 턴테이블 · HipHopStrip ·
--   MovingHead · 바 카운터 · 문 은 숨기거나 옮기지 않음 (덧붙이기만). NPC 둘레 2, 통로 · 문 앞 · 테이블 위 · 좌석 위는 비움.
--   숨기는 것: ROOM 2 의 납작한 그라피티 판 3장 (Sign_OCEAN CREW / BUSAN 051 / HIPHOP 4 LIFE) → 같은 자리에 진짜 벽화.
--   움직이는 조명 · 레이저는 만들지 않음 (GwangalliClubPlus 담당).

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "clublounge", "rooftop", "hiphop", "clubwc", "clubcorridor" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
local _common = Common -- 공통 마감은 Common.run 이 이미 돌림 (여기서는 upgrades 만 켜 둠)

-- 작은 도구 ------------------------------------------------------------------------------------------
-- 거울: 반사율을 낮춘 은회색 유리 (밤에 반사가 하얗게 뜨지 않게)
local MIRROR = { c = Color3.fromRGB(88, 96, 106), m = Enum.Material.SmoothPlastic, t = 0, r = 0.1 }

local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
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
local function hi(K: any): boolean
	return K.detail == "high"
end
local function lowD(K: any): boolean
	return K.detail == "low"
end

-- 글자판 (dcf +Z = 보는 쪽). glow 가 있으면 빛나는 글자
local function txt(K: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3, bg: Color3?, font: Enum.Font?, glow: number?, o: any?): (BasePart, TextLabel)
	local op: any = { fg = fg, bg = bg, font = font or F.GothamBold, glow = glow, d = 0.02 }
	if o then
		for k, v in o do
			op[k] = v
		end
	end
	return K:text(name, w, h, dcf, s, op)
end

-- 위를 보는 글자판 (바닥 · 판 윗면): p 중심, 글자 위쪽 = up
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end

-- 표시면(dcf)에 붙는 원판 (축 = dcf Z)
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end

local function tween(p: BasePart?, goal: { [string]: any }, t: number?)
	if p and p.Parent then
		TweenService:Create(p, TweenInfo.new(t or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	end
end

-- 정렬 프레임 · 벽 ----------------------------------------------------------------------------------------
-- 맵에서 잰 벽 안쪽 면 (정렬 프레임). H = 천장 아래면 (nil = 하늘)
local ROOMS: { [string]: any } = {
	lounge2f = { x0 = -20.5, x1 = 20.0, z0 = -86.6, z1 = 86.0, H = 13.0, floors = { "LoungeFloor" } },
	rooftop = { x0 = -26.3, x1 = 26.3, z0 = -73.7, z1 = 73.7, H = 12.0, open = true, floors = { "TerraceDeck" } },
	hiphop = { x0 = -24.1, x1 = 24.5, z0 = -35.0, z1 = 35.0, H = 15.5, floors = { "PolishedConcrete" } },
	corridor = { x0 = -8.6, x1 = 8.4, z0 = -37.9, z1 = 38.1, H = 10.5, floors = { "CorridorFloor" } },
	wc_f = { x0 = -9.5, x1 = 9.5, z0 = -20.4, z1 = 20.2, H = 10.5, floors = { "Floor" } },
	wc_m = { x0 = -10.0, x1 = 10.0, z0 = -20.6, z1 = 20.0, H = 10.5, floors = { "Floor" } },
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

-- R = { K, V, A (회전만), x0 x1 z0 z1 (정렬 프레임 벽 안쪽 면), cx cz W D H }
local function makeRoom(K: any, V: any): any
	local spec = ROOMS[V.room or ""] or { x0 = V.x0, x1 = V.x1, z0 = V.z0, z1 = V.z1, H = V.H, floors = {} }
	local yaw: number? = nil
	for _, nm in spec.floors do
		for _, r in V.byName[nm] or {} do
			if r.part.Size.X * r.part.Size.Z > 50 then
				yaw = yawOf(r.lcf)
				break
			end
		end
		if yaw then
			break
		end
	end
	local y = yaw or -0.01505
	local R: any = { K = K, V = V, A = ANG(0, y, 0), yaw = y, npcs = {} }
	R.x0, R.x1, R.z0, R.z1 = spec.x0, spec.x1, spec.z0, spec.z1
	R.cx, R.cz = (R.x0 + R.x1) / 2, (R.z0 + R.z1) / 2
	R.W, R.D, R.H = R.x1 - R.x0, R.z1 - R.z0, spec.H or V.H
	R.open = spec.open == true
	K:note(string.format("aligned yaw=%.4f x %.2f..%.2f z %.2f..%.2f", y, R.x0, R.x1, R.z0, R.z1))
	return R
end

-- 정렬 프레임 → 방 프레임
local function at(R: any, x: number, z: number, yaw: number?, y: number?): CFrame
	return R.A * CF(x, y or 0, z) * ANG(0, yaw or 0, 0)
end
local function ap(R: any, x: number, y: number, z: number): Vector3
	return R.A * V3(x, y, z)
end
local function av(R: any, x: number, y: number, z: number): Vector3
	return R.A:VectorToWorldSpace(V3(x, y, z))
end
-- 벽 표시면 (dcf): 정렬 좌표 (x 또는 z), 높이 y, 벽에서 띄움 off
local function wallL(R: any, z: number, y: number, off: number?): CFrame
	return R.A * CFrame.fromMatrix(V3(R.x0 + (off or 0), y, z), V3(0, 0, -1), Vector3.yAxis, V3(1, 0, 0))
end
local function wallR(R: any, z: number, y: number, off: number?): CFrame
	return R.A * CFrame.fromMatrix(V3(R.x1 - (off or 0), y, z), V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
end
local function wallB(R: any, x: number, y: number, off: number?): CFrame
	return R.A * CFrame.fromMatrix(V3(x, y, R.z0 + (off or 0)), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1))
end
local function wallF(R: any, x: number, y: number, off: number?): CFrame
	return R.A * CFrame.fromMatrix(V3(x, y, R.z1 - (off or 0)), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1))
end
local WALLS = { left = wallL, right = wallR, back = wallB, front = wallF }
-- 임의의 수직면 dcf (정렬 좌표 점 p, 보는 쪽 방향 yaw: 0 = +Z 쪽을 봄)
local function face(R: any, x: number, y: number, z: number, yaw: number): CFrame
	return R.A * CF(x, y, z) * ANG(0, yaw, 0)
end

-- 정렬 프레임 상자 → keep (방 프레임 AABB)
-- (방 프레임 AABB 는 회전 때문에 길이 x 0.015 만큼 부풀어서, 긴 상자는 8 스터드 조각으로 나눔)
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

-- NPC 모형 (HumanoidRootPart 가 있는 모델) 둘레 2 비우기 (실제 게임의 Scan.keepouts 와 같은 폭)
local function npcKeeps(R: any)
	local V = R.V
	local rigs: { [Instance]: boolean } = {}
	for _, r in V.parts do
		if r.name == "HumanoidRootPart" and r.part.Parent then
			rigs[r.part.Parent :: Instance] = true
		end
	end
	for m in rigs do
		local mn: Vector3?, mx: Vector3? = nil, nil
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local a, b = Kit.laabb(V.cf:ToObjectSpace(d.CFrame), d.Size)
				mn = if mn then (mn :: Vector3):Min(a) else a
				mx = if mx then (mx :: Vector3):Max(b) else b
			end
		end
		if mn and mx then
			V:addKeep((mn :: Vector3) - V3(2, 0, 2), (mx :: Vector3) + V3(2, 0.5, 2), "npc")
			local ac = R.A:PointToObjectSpace(((mn :: Vector3) + (mx :: Vector3)) / 2)
			table.insert(R.npcs, { name = m.Name, c = ac })
		end
	end
end

-- 맵 파트 (V.parts 의 rec) 의 정렬 프레임 AABB
local function abox(R: any, rec: any): (Vector3, Vector3)
	return Kit.laabb(R.A:ToObjectSpace(rec.lcf), rec.part.Size)
end

-- 바닥 소품 자리 (정렬 프레임 벽 기준; Kit:spot 과 같지만 숨긴 맵 파트 · 바닥 스티커는 무시)
local function place(R: any, pcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local K, V = R.K, R.V
	local p = pad or 0
	local c = pcf * CF(0, size.Y / 2, 0)
	local mn, mx = Kit.laabb(c, size + V3(2 * p, 0, 2 * p))
	local amn, amx = Kit.laabb(R.A:ToObjectSpace(c), size)
	if amn.X < R.x0 - 0.05 or amx.X > R.x1 + 0.05 or amn.Z < R.z0 - 0.05 or amx.Z > R.z1 + 0.05 then
		R.why = "bounds"
		return false
	end
	local hk = K:hitsKeep(mn, mx)
	if hk then
		R.why = "keep " .. hk
		return false
	end
	-- 맵 가구: 정렬 프레임 AABB 끼리 비교 (긴 난간 · 벽이 방 프레임에서 부풀지 않게)
	local amnP, amxP = Kit.laabb(R.A:ToObjectSpace(c), size + V3(2 * p, 0, 2 * p))
	for _, s in V.solid do
		if not K.hidden[s.part] and not (s.size.Y < 0.15 and s.max.Y < 0.2) and Kit.overlap(mn, mx, s.min, s.max, 0.04) then
			if not s.amin then
				s.amin, s.amax = abox(R, s)
			end
			if Kit.overlap(amnP, amxP, s.amin, s.amax, 0.04) then
				R.why = "map " .. s.name
				return false
			end
		end
	end
	for _, r in K.reserved do
		if Kit.overlap(mn, mx, r.min, r.max, 0.02) then
			R.why = "reserved " .. tostring(r.kind)
			return false
		end
	end
	table.insert(K.reserved, { min = mn, max = mx, kind = kind or "prop" })
	return true
end
local function placeOr(R: any, pcf: CFrame, size: Vector3, pad: number?, what: string): boolean
	if place(R, pcf, size, pad, what) then
		return true
	end
	R.K:note("skip " .. what .. " (" .. tostring(R.why) .. ")")
	return false
end

-- 프롬프트
local function prompt(R: any, part: BasePart?, kind: string, spec: any, items: { any }?): ProximityPrompt?
	if not part or part.Parent == nil then
		return nil
	end
	if kind == "toggle" then
		return Interact.toggle(R.K, part, spec)
	elseif kind == "cycle" then
		return Interact.cycle(R.K, part, items or {}, spec)
	end
	return Interact.prompt(R.K, part, spec)
end

-- 숨기기 (장식용 맵 파트만: 태그 · 좌석 · 프롬프트 · 빛이 있는 건 절대 안 숨김)
local function safeHide(K: any, rec: any): boolean
	local p: BasePart = rec.part
	if p:IsA("Seat") or p:IsA("VehicleSeat") then
		return false
	end
	local okT, tags = pcall(function()
		return game:GetService("CollectionService"):GetTags(p)
	end)
	if okT and type(tags) == "table" then
		for _, t in tags do
			if string.sub(t, 1, 4) == "Club" then
				return false
			end
		end
	end
	for _, c in p:GetChildren() do
		if c:IsA("ProximityPrompt") or c:IsA("Light") then
			return false
		end
	end
	Scan.hide(K.hidden, p)
	return true
end

-- 공통 소형 소품 ------------------------------------------------------------------------------------------
-- 천장 설비 (정렬 좌표, 천장 아래면 R.H)
local function downlight(K: any, R: any, x: number, z: number, o: any?)
	local op: any = o or {}
	local y = op.y or R.H
	local d = op.dia or 0.62
	local lens: BasePart? = nil
	K:free(function()
		K:disc("DownlightTrim", d, 0.04, at(R, x, z, 0, y - 0.02), op.trim or Look.black)
		lens = K:disc("DownlightLens", d * 0.66, 0.03, at(R, x, z, 0, y - 0.04), op.glow or Look.lampWarm)
	end)
	if op.light and lens then
		K:light(lens :: BasePart, "SpotLight", { Face = Enum.NormalId.Bottom, Range = op.range or 16, Brightness = op.bright or 1.1, Angle = op.angle or 70, Color = op.color or Look.warmLight })
	end
	return lens
end
local function sprinkler(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("SprinklerRose", 0.3, 0.03, at(R, x, z, 0, y - 0.015), Look.black)
		K:vcyl("SprinklerBody", 0.18, 0.1, at(R, x, z, 0, y - 0.11), Look.brass)
		K:disc("SprinklerDeflector", 0.2, 0.02, at(R, x, z, 0, y - 0.2), Look.brass)
	end)
end
local function smoke(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("SmokeDetector", 0.55, 0.14, at(R, x, z, 0, y - 0.07), Look.white)
		K:disc("SmokeDetectorLED", 0.06, 0.02, at(R, x + 0.16, z, 0, y - 0.15), Look.ledRed)
	end)
end
local function cctv(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("CCTVBase", 0.66, 0.06, at(R, x, z, 0, y - 0.03), Look.black)
		K:ell("CCTVDome", V3(0.54, 0.5, 0.54), at(R, x, z, 0, y - 0.07), Look.with(Look.glassDark, { t = 0.1 }))
		K:disc("CCTVLED", 0.05, 0.02, at(R, x + 0.2, z, 0, y - 0.08), Look.ledRed)
	end)
end
local function ceilSpeaker(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("CeilSpeakerTrim", 1.0, 0.04, at(R, x, z, 0, y - 0.02), Look.black)
		K:disc("CeilSpeakerGrille", 0.84, 0.03, at(R, x, z, 0, y - 0.045), lk(rgb(40, 40, 44), M.DiamondPlate))
	end)
end
local function vent(K: any, R: any, x: number, z: number, s: number?)
	local y = R.H
	local w = s or 1.6
	K:free(function()
		K:box("VentFrame", V3(w, 0.05, w), at(R, x, z, 0, y - 0.025), Look.white)
		for i = -2, 2 do
			K:box("VentSlot", V3(w - 0.3, 0.03, 0.08), at(R, x, z + i * (w - 0.3) / 5, 0, y - 0.055), lk(rgb(60, 62, 66)))
		end
	end)
end

-- 안내문 (흰 판 + 색 머리띠 + 본문)
local function notice(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, head: Color3?, o: any?)
	local op: any = o or {}
	K:plate("NoticeBoard", w, h, 0.03, dcf, lk(op.bg or rgb(250, 250, 246)))
	local hh = math.min(h * 0.26, 0.6)
	K:plate("NoticeHead", w, hh, 0.035, dcf * CF(0, h / 2 - hh / 2, 0), lk(head or rgb(220, 40, 50)))
	txt(K, "NoticeTitle", w * 0.92, hh * 0.76, dcf * CF(0, h / 2 - hh / 2, 0.04), title, op.titleFg or WHITE, nil, F.GothamBlack)
	txt(K, "NoticeBody", w * 0.9, (h - hh) * 0.84, dcf * CF(0, -hh / 2, 0.04), body, op.fg or rgb(34, 34, 40), nil, op.font or F.GothamMedium, nil, { wrap = op.wrap })
end

-- 금연 픽토그램 (빨간 원 + 사선 + 담배)
local function noSmoking(K: any, dcf: CFrame, d: number, label: string?)
	K:plate("NoSmokeBoard", d + 0.3, d + (if label then 0.7 else 0.3), 0.03, dcf * CF(0, if label then -0.2 else 0, 0), Look.white)
	K:ring("NoSmokeRing", dcf * CF(0, 0, 0.05), d * 0.42, d * 0.1, 14, lk(rgb(210, 30, 34)))
	K:plate("NoSmokeCig", d * 0.5, d * 0.1, 0.02, dcf * CF(-d * 0.04, 0, 0.04), Look.of(60, 60, 60))
	K:plate("NoSmokeTip", d * 0.12, d * 0.1, 0.021, dcf * CF(d * 0.25, 0, 0.04), Look.of(230, 120, 40))
	K:plate("NoSmokeBar", d * 0.82, d * 0.09, 0.03, dcf * CF(0, 0, 0.05) * ANG(0, 0, PI / 4), lk(rgb(210, 30, 34)))
	if label then
		txt(K, "NoSmokeText", d + 0.2, 0.42, dcf * CF(0, -d / 2 - 0.32, 0.04), label, rgb(200, 30, 34), nil, F.GothamBlack)
	end
end

-- 픽처 라이트 (액자 위 황동 팔 + 빛나는 막대). dcf = 액자 윗변 가운데 벽 표면
local function pictureLight(K: any, dcf: CFrame, w: number, light: boolean?)
	K:plate("PicLightMount", 0.3, 0.22, 0.06, dcf * CF(0, 0.45, 0), Look.brass)
	K:bar("PicLightArm", (dcf * CF(0, 0.45, 0.05)).Position, (dcf * CF(0, 0.62, 0.5)).Position, 0.06, 0.06, Look.brass)
	local bar = K:box("PicLightHood", V3(w, 0.14, 0.22), dcf * CF(0, 0.62, 0.55) * ANG(math.rad(25), 0, 0), Look.brass)
	local lamp = K:box("PicLightLamp", V3(w - 0.1, 0.03, 0.12), dcf * CF(0, 0.54, 0.6) * ANG(math.rad(25), 0, 0), Look.lampWarm)
	if light then
		local aim = K:box("PicLightAim", V3(0.1, 0.1, 0.1), dcf * CF(0, 0.5, 0.62) * ANG(math.rad(-62), 0, 0), lk(rgb(30, 30, 30), nil, { t = 1 }))
		K:light(aim, "SpotLight", { Face = Enum.NormalId.Front, Range = 9, Brightness = 1.4, Angle = 70, Color = Look.warmLight })
	end
	return bar, lamp
end

-- 액자 (유리 없이: 프레임 4 + 매트 + 그림 블록). art = { {색, x, y, w, h} } (0..1)
-- DJ 프로필 사진 (듀오톤 배경 + 뒤 후광 + 헤드폰 낀 상반신 실루엣 + 림 라이트). dcf 중심, w x h (액자 안쪽)
local function djPortrait(K: any, dcf: CFrame, w: number, h: number, bgA: Color3, bgB: Color3, rim: Color3, skin: Color3)
	local iw, ih = w, h
	for k = 0, 2 do
		K:plate("PortraitBG", iw, ih / 3, 0.07, dcf * CF(0, -ih / 2 + ih * (k + 0.5) / 3, 0), lk(bgA:Lerp(bgB, k / 2)))
	end
	local hy = ih * 0.1
	local hcf = dcf * CF(0, hy, 0.075)
	wdisc(K, "PortraitHalo", ih * 0.62, 0.005, hcf, lk(rim:Lerp(bgB, 0.35), M.SmoothPlastic))
	-- 상반신 (아래 반을 꽉 채운 타원) + 림
	K:ell("PortraitShoulderRim", V3(iw * 0.72, ih * 0.5, 0.02), dcf * CF(iw * 0.015, -ih * 0.25 + 0.03, 0.082), lk(rim))
	K:ell("PortraitShoulders", V3(iw * 0.7, ih * 0.5, 0.02), dcf * CF(-iw * 0.01, -ih * 0.25, 0.086), lk(rgb(16, 14, 20)))
	K:plate("PortraitNeck", iw * 0.09, ih * 0.14, 0.012, dcf * CF(0, -ih * 0.02, 0.088), lk(skin:Lerp(BLACK, 0.55)))
	-- 머리 (림 + 얼굴 그림자) + 머리카락
	K:ell("PortraitHeadRim", V3(iw * 0.215, ih * 0.33, 0.02), hcf * CF(iw * 0.012, 0, 0.012), lk(rim))
	K:ell("PortraitHead", V3(iw * 0.2, ih * 0.32, 0.02), hcf * CF(-iw * 0.006, 0, 0.018), lk(skin:Lerp(BLACK, 0.45)))
	K:ell("PortraitHair", V3(iw * 0.22, ih * 0.14, 0.02), hcf * CF(-iw * 0.006, ih * 0.12, 0.024), lk(rgb(14, 12, 16)))
	-- 헤드폰 (밴드 + 이어컵 2)
	K:ring("PortraitPhonesBand", hcf * CF(0, 0, 0.03), iw * 0.13, 0.07, 6, lk(rgb(30, 30, 34)), 0, PI)
	for _, sx in { -1, 1 } do
		K:ell("PortraitPhonesCup", V3(iw * 0.07, ih * 0.13, 0.02), hcf * CF(sx * iw * 0.115, -ih * 0.02, 0.032), lk(rgb(26, 26, 30)))
	end
	K:ell("PortraitPhonesLED", V3(iw * 0.02, ih * 0.05, 0.02), hcf * CF(iw * 0.128, -ih * 0.02, 0.04), lk(rim))
end

local function artFrame(K: any, dcf: CFrame, w: number, h: number, art: { any }, frame: any?, mat: any?)
	local fr = frame or Look.black
	local b = 0.1
	K:plate("ArtMat", w, h, 0.06, dcf, mat or lk(rgb(240, 238, 232)))
	K:plate("ArtFrameT", w, b, 0.12, dcf * CF(0, h / 2 - b / 2, 0), fr)
	K:plate("ArtFrameB", w, b, 0.12, dcf * CF(0, -h / 2 + b / 2, 0), fr)
	K:plate("ArtFrameS", b, h - 2 * b, 0.12, dcf * CF(-w / 2 + b / 2, 0, 0), fr)
	K:plate("ArtFrameS", b, h - 2 * b, 0.12, dcf * CF(w / 2 - b / 2, 0, 0), fr)
	local iw, ih = w - 0.5, h - 0.5
	for i, a in art do
		K:plate("ArtBlock", iw * a[4], ih * a[5], 0.07 + i * 0.002, dcf * CF(-iw / 2 + iw * (a[2] + a[4] / 2), -ih / 2 + ih * (a[3] + a[5] / 2), 0), lk(a[1]))
	end
end

-- 천장 코브 (긴 LED 띠 + SurfaceLight 로 벽 · 바닥을 고르게 비춤). 정렬 좌표 a -> b (y 높이)
local function cove(K: any, R: any, ax: number, az: number, bx: number, bz: number, y: number, c: Color3, bright: number?, range: number?, light: boolean?)
	local p: BasePart? = nil
	K:free(function()
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local yaw = math.atan2(bx - ax, bz - az)
		local cf = at(R, (ax + bx) / 2, (az + bz) / 2, yaw, y)
		K:box("CoveChannel", V3(0.3, 0.12, len), cf * CF(0, 0.08, 0), Look.darkAlu)
		p = K:box("CoveLED", V3(0.16, 0.05, len - 0.1), cf, nl(c))
	end)
	if light ~= false and p then
		K:light(p :: BasePart, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = range or 12, Brightness = bright or 0.7, Angle = 160, Color = c })
	end
	return p
end

-- 세운 스툴 (바 · 하이테이블). pcf 바닥
local function barStool(K: any, pcf: CFrame, top: number, seat: any, frame: any?)
	local fr = frame or Look.blackMetal
	K:disc("StoolFoot", 1.05, 0.06, pcf * CF(0, 0.03, 0), fr)
	K:vcyl("StoolPole", top - 0.35, 0.16, pcf * CF(0, (top - 0.35) / 2 + 0.05, 0), fr)
	K:ring("StoolFootRing", pcf * CF(0, top * 0.36, 0) * ANG(PI / 2, 0, 0), 0.5, 0.07, 8, fr)
	K:disc("StoolSeat", 1.2, 0.24, pcf * CF(0, top - 0.12, 0), seat)
	if hi(K) then
		K:disc("StoolPiping", 1.23, 0.03, pcf * CF(0, top - 0.2, 0), lk(dk(seat.c, 0.4), seat.m))
	end
end

-- 하이 테이블 (원형 상판 + 기둥 + 원판 받침). pcf 바닥
local function highTable(K: any, pcf: CFrame, top: number, dia: number, topL: any, frame: any?)
	local fr = frame or Look.blackMetal
	K:disc("HiTableBase", dia * 0.6, 0.08, pcf * CF(0, 0.04, 0), fr)
	K:vcyl("HiTablePole", top - 0.2, 0.22, pcf * CF(0, (top - 0.2) / 2 + 0.06, 0), fr)
	K:disc("HiTableTop", dia, 0.12, pcf * CF(0, top - 0.06, 0), topL)
	K:disc("HiTableEdge", dia + 0.04, 0.05, pcf * CF(0, top - 0.13, 0), fr)
end

-- 휴지통 (스테인리스 원통 + 뚜껑). pcf 바닥
local function trashCan(K: any, pcf: CFrame, h: number, dia: number, label: string?, body: any?)
	local bl = body or Look.steel
	K:vcyl("BinBody", h - 0.2, dia, pcf * CF(0, (h - 0.2) / 2, 0), bl)
	K:ell("BinLid", V3(dia, 0.4, dia), pcf * CF(0, h - 0.2, 0), bl)
	K:box("BinFlap", V3(dia * 0.5, 0.18, 0.04), pcf * CF(0, h - 0.12, dia * 0.42) * ANG(math.rad(-25), 0, 0), Look.black)
	if label then
		txt(K, "BinLabel", dia * 0.7, 0.3, pcf * CF(0, h * 0.62, dia / 2 + 0.005), label, WHITE, rgb(40, 40, 44), F.GothamBold)
	end
end

-- 바닥 배수구 (스테인리스 사각 그레이팅)
local function floorDrain(K: any, R: any, x: number, z: number)
	K:free(function()
		K:box("DrainFrame", V3(0.9, 0.03, 0.9), at(R, x, z, 0, 0.015), Look.steel)
		for i = -2, 2 do
			K:box("DrainSlot", V3(0.66, 0.032, 0.06), at(R, x, z + i * 0.14, 0, 0.017), lk(rgb(30, 30, 32)))
		end
	end)
end

-- 큰 화분 (정렬 좌표)
local function plant(K: any, R: any, x: number, z: number, kind: string, h: number, dia: number?, pot: any?): boolean
	local pcf = at(R, x, z)
	if not placeOr(R, pcf, V3(dia or 1.5, h, dia or 1.5), 0, "plant") then
		return false
	end
	Props.floorPlant(K, pcf, { kind = kind, h = h, dia = dia or 1.5, pot = pot })
	return true
end

-- 매달린 양면 안내판 (정렬 x, z, 아래 높이 y, 폭 w, yaw (0 = 앞뒤가 ±z)). front / back = { title, sub, c, bg }
local function hangSign(K: any, R: any, x: number, z: number, y: number, w: number, h: number, yaw: number, front: any, back: any?)
	local base = at(R, x, z, yaw, y + h / 2)
	K:free(function()
		for _, sx in { -1, 1 } do
			local a = (base * CF(sx * (w / 2 - 0.4), h / 2, 0)).Position
			local b = a + av(R, 0, R.H - (y + h), 0)
			K:seg("HangSignRod", a, b, 0.05, Look.blackMetal)
		end
		K:box("HangSignBox", V3(w, h, 0.26), base, lk(front.bg or rgb(14, 14, 18)))
		K:box("HangSignEdge", V3(w + 0.06, 0.06, 0.3), base * CF(0, -h / 2, 0), nl(front.c))
		for i, s in { 1, -1 } do
			local d = base * CF(0, 0, s * 0.14) * (if s < 0 then ANG(0, PI, 0) else CFrame.new())
			local side = if i == 1 then front else (back or front)
			txt(K, "HangSignTitle", w * 0.92, h * (if side.sub then 0.52 else 0.7), d * CF(0, if side.sub then h * 0.13 else 0, 0), side.title, side.c, nil, F.GothamBlack, 1.5)
			if side.sub then
				txt(K, "HangSignSub", w * 0.88, h * 0.26, d * CF(0, -h * 0.28, 0), side.sub, WHITE, nil, F.GothamBold, 1.2)
			end
		end
	end)
end

-- 피난구 유도등 (초록 바탕 + 흰 달리는 사람 + 화살표). dcf 중심
local function exitLight(K: any, dcf: CFrame, w: number, arrow: string?)
	local h = w * 0.42
	K:plate("ExitLightBody", w, h, 0.18, dcf, Look.white)
	K:plate("ExitLightFace", w - 0.1, h - 0.1, 0.02, dcf * CF(0, 0, 0.18), nl(rgb(30, 190, 90)))
	txt(K, "ExitLightText", w * 0.86, h * 0.7, dcf * CF(0, 0, 0.205), (arrow or "") .. "🏃 비상구 EXIT", WHITE, nil, F.GothamBlack, 1.4)
end

-- 공통 스타일 ------------------------------------------------------------------------------------------
function T.style(V: any): any
	-- 앞면(+Z)은 가게 유리가 아니라 벽 · 난간: '창문' keep 를 걷어냄 (벽화 · 사이니지가 놓일 자리)
	local keep = {}
	for _, k in V.keep do
		if k.kind ~= "window" then
			table.insert(keep, k)
		end
	end
	V.keep = keep
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
		skip = { fixtures = true, floor = true, walls = true, ceiling = true },
	}
end

--=====================================================================================================
-- 복도 (clubcorridor) ----------------------------------------------------------------------------------
--=====================================================================================================
local function buildCorridor(K: any, V: any, R: any)
	local H = R.H
	local PURP = rgb(150, 60, 255)
	local CYAN = rgb(40, 220, 255)
	local leather = lk(rgb(34, 28, 42), M.Leather)
	-- 문 앞 · 통로
	keepBox(R, R.x0, -37.4, -4.1, -32.4, 7.5, "door") -- 비상구 (왼벽)
	keepBox(R, R.x0, -25.4, -4.1, -20.4, 8, "door") -- 여자 화장실
	keepBox(R, R.x0, -3.4, -4.1, 1.6, 8, "door") -- 남자 화장실
	keepBox(R, 3.9, -18.4, R.x1, -9.4, 8.5, "door") -- ROOM 2
	keepBox(R, R.x0, 33.6, -3.7, R.z1, 9, "door") -- 메인홀
	keepBox(R, -3.4, R.z0, 3.4, R.z1, 6.8, "lane")

	-- 가죽 징두리 (y 0.35..3.8) + 황동 캡 -------------------------------------------------------
	local function dado(wall: string, u0: number, u1: number)
		local wf = WALLS[wall]
		local n = math.max(1, math.floor((u1 - u0) / 2.9 + 0.5))
		local pw = (u1 - u0) / n
		for i = 1, n do
			local u = u0 + pw * (i - 0.5)
			K:plate("CorrDado", pw - 0.08, 3.4, 0.06, wf(R, u, 0.35 + 1.7, 0), leather)
			if hi(K) then
				K:plate("CorrDadoSeam", pw - 0.5, 0.04, 0.065, wf(R, u, 2.05, 0), lk(rgb(24, 20, 30), M.Leather))
			end
		end
		K:plate("CorrDadoCap", u1 - u0, 0.08, 0.1, wf(R, (u0 + u1) / 2, 3.82, 0), Look.brass)
		K:plate("CorrDadoLED", u1 - u0 - 0.1, 0.04, 0.11, wf(R, (u0 + u1) / 2, 3.74, 0), nl(rgb(255, 190, 130)))
		K:plate("CorrDadoShadow", u1 - u0, 0.3, 0.02, wf(R, (u0 + u1) / 2, 0.2, 0), lk(rgb(10, 10, 12)))
	end
	K:free(function()
		dado("left", -32.6, -25.2)
		dado("left", -20.6, -3.2)
		dado("left", 1.4, 21.0)
		dado("left", 32.4, 37.8)
		dado("right", -37.6, -18.2)
		dado("right", 24.4, 31.8)
		dado("back", -8.4, 8.1)
		dado("front", -4.0, 5.9)
	end)

	-- 세로 LED 라인 (벽 위쪽) ---------------------------------------------------------------------------
	local function ledLine(wall: string, u: number, y0: number, y1: number, c: Color3)
		local wf = WALLS[wall]
		K:plate("CorrLEDChannel", 0.22, y1 - y0 + 0.1, 0.04, wf(R, u, (y0 + y1) / 2, 0), Look.darkAlu)
		K:plate("CorrLEDLine", 0.1, y1 - y0, 0.06, wf(R, u, (y0 + y1) / 2, 0), nl(c))
	end
	K:free(function()
		for _, u in { -31.6, -26.2, 2.6, 8.55, 14.5, 20.5 } do
			ledLine("left", u, 4.1, 9.9, PURP)
		end
		for _, u in { -32.6, -28.4, -7.0, 8.2, 13.95 } do
			ledLine("right", u, 4.1, 9.9, PURP)
		end
	end)

	-- 왼벽 갤러리: 레지던트 DJ 사진 3점 + 픽처 라이트 + 캡션 -------------------------------------------------
	local GAL = {
		{ z = 5.55, cap = "DJ HAEWON · RESIDENT\nTECH HOUSE", dj = { rgb(60, 24, 110), rgb(230, 60, 160), rgb(80, 230, 255), rgb(236, 196, 170) }, art = { { rgb(40, 30, 70), 0, 0, 1, 1 }, { rgb(150, 60, 230), 0, 0, 1, 0.45 }, { rgb(255, 70, 170), 0.12, 0.45, 0.76, 0.05 }, { rgb(26, 22, 30), 0.38, 0.18, 0.24, 0.5 }, { rgb(230, 190, 160), 0.44, 0.66, 0.12, 0.14 }, { rgb(40, 220, 255), 0.05, 0.86, 0.3, 0.04 } } },
		{ z = 11.5, cap = "광안대교 · GWANGAN BRIDGE\n2025 NIGHT", art = { { rgb(20, 30, 70), 0, 0, 1, 1 }, { rgb(40, 80, 160), 0, 0, 1, 0.4 }, { rgb(255, 210, 120), 0, 0.42, 1, 0.03 }, { rgb(255, 210, 120), 0.18, 0.45, 0.02, 0.3 }, { rgb(255, 210, 120), 0.78, 0.45, 0.02, 0.3 }, { rgb(120, 200, 255), 0.0, 0.3, 1, 0.02 }, { rgb(255, 80, 160), 0.6, 0.8, 0.1, 0.08 } } },
		{ z = 17.5, cap = "SEAN WAVE · RESIDENT\nK-EDM", dj = { rgb(255, 120, 50), rgb(120, 20, 60), rgb(255, 230, 120), rgb(220, 180, 150) }, art = { { rgb(70, 26, 44), 0, 0, 1, 1 }, { rgb(255, 140, 60), 0, 0, 1, 0.3 }, { rgb(255, 60, 90), 0.0, 0.3, 1, 0.12 }, { rgb(20, 16, 22), 0.4, 0.15, 0.2, 0.55 }, { rgb(220, 180, 150), 0.45, 0.7, 0.1, 0.12 }, { rgb(255, 230, 120), 0.7, 0.75, 0.2, 0.2 } } },
	}
	for i, g in GAL do
		local d = wallL(R, g.z, 5.95, 0)
		if g.dj then
			artFrame(K, d, 4.6, 3.0, {}, Look.black, lk(rgb(236, 232, 224)))
			djPortrait(K, d, 4.1, 2.5, g.dj[1], g.dj[2], g.dj[3], g.dj[4])
		else
			artFrame(K, d, 4.6, 3.0, g.art, Look.black)
		end
		pictureLight(K, d * CF(0, 1.5, 0), 3.2, i <= 3)
		txt(K, "GalleryCaption", 1.7, 0.34, wallL(R, g.z + 1.4, 4.12, 0.11), g.cap, rgb(220, 200, 150), rgb(16, 14, 18), F.GothamMedium)
	end

	-- 오른벽: 벤치 + 라인업 라이트박스 + 정수기 + 분리수거 + 휴대폰 충전함 -----------------------------------------
	-- 벤치 (가죽 쿠션 + 블랙 받침 + 아래 간접등), 벽 쪽 등받이 패널
	do
		local z0, z1 = -7.6, 1.6
		local pcf = at(R, R.x1 - 0.8, (z0 + z1) / 2)
		if placeOr(R, pcf, V3(1.6, 2.0, z1 - z0), 0, "corridor bench") then
			K:box("BenchPlinth", V3(1.2, 0.5, z1 - z0 - 0.4), pcf * CF(0.1, 0.25, 0), Look.black)
			K:box("BenchGlow", V3(0.05, 0.05, z1 - z0 - 0.6), pcf * CF(-0.52, 0.06, 0), nl(PURP))
			K:box("BenchBase", V3(1.6, 0.25, z1 - z0), pcf * CF(0, 0.62, 0), Look.blackMetal)
			K:rbox("BenchCushion", V3(z1 - z0 - 0.1, 0.5, 1.5), 0.16, pcf * CF(0, 1.0, 0) * ANG(0, PI / 2, 0), leather)
			for i = 1, 3 do
				K:box("BenchTuft", V3(1.2, 0.03, 0.04), pcf * CF(0, 1.255, -(z1 - z0) / 2 + i * (z1 - z0) / 4), lk(rgb(20, 16, 26), M.Leather))
			end
		end
		-- 등받이 패널 (벽 부착, 가로 홈 3줄)
		local bd = wallR(R, (z0 + z1) / 2, 2.6, 0)
		K:plate("BenchBackPanel", z1 - z0, 1.9, 0.28, bd, leather)
		for j = -1, 1 do
			K:plate("BenchBackSeam", z1 - z0 - 0.2, 0.04, 0.29, bd * CF(0, j * 0.5, 0), lk(rgb(20, 16, 26), M.Leather))
		end
		K:plate("BenchBackCap", z1 - z0, 0.08, 0.32, bd * CF(0, 1.0, 0), Look.brass)
	end
	-- 라인업 라이트박스 (상호작용: 요일 넘기기)
	local LINEUP = {
		"THIS WEEK @ CLUB OCEAN\n\nTHU · LADIES NIGHT 22-24 FREE\nFRI · DJ HAEWON  TECH HOUSE 23:00\nSAT · SEAN WAVE  K-EDM 23:30",
		"FRI 10.23 · DJ HAEWON\n\nTECH HOUSE · 23:00 - 05:00\n입장 20,000원 (1 DRINK)\n테이블 예약 010-0510-0510",
		"SAT 10.24 · SEAN WAVE\n\nK-EDM · 23:30 - 06:00\n입장 30,000원 (1 DRINK)\nROOM 2 · HIP-HOP OPEN",
		"SUN 10.25 · OCEAN SUNDAY\n\nDEEP HOUSE · ROOFTOP 18:00\n하이볼 2+1 · 19:00 - 21:00\n2F SKY LOUNGE 예약제",
	}
	local lbLabel: TextLabel? = nil
	local lbFace: BasePart? = nil
	do
		local d = wallR(R, -3.0, 6.1, 0)
		K:plate("LineupBoxFrame", 7.0, 3.4, 0.3, d, Look.blackMetal)
		lbFace = K:plate("LineupBoxFace", 6.7, 3.1, 0.32, d, lk(rgb(16, 10, 30), M.Neon, { t = 0.25 }))
		K:plate("LineupBoxRule", 6.4, 0.05, 0.34, d * CF(0, 0.85, 0), nl(rgb(255, 70, 170)))
		local _, lab = txt(K, "LineupBoxText", 6.3, 2.8, d * CF(0, 0, 0.34), LINEUP[1], WHITE, nil, F.GothamBold, 1.6)
		lbLabel = lab
		if lbFace then
			K:light(lbFace :: BasePart, "SurfaceLight", { Face = Enum.NormalId.Back, Range = 9, Brightness = 0.8, Angle = 110, Color = rgb(190, 120, 255) })
		end
	end
	-- 정수기 (벽걸이) + 종이컵 + 분리수거함
	local waterCup: BasePart? = nil
	local waterFill: BasePart? = nil
	local waterStream: BasePart? = nil
	local waterBtn: BasePart? = nil
	do
		local zc = 4.6
		local d = wallR(R, zc, 3.7, 0)
		K:plate("WaterBody", 1.5, 2.9, 0.9, d, Look.steel)
		K:plate("WaterTopPanel", 1.36, 0.9, 0.92, d * CF(0, 0.85, 0), lk(rgb(30, 32, 36), M.Glass, { r = 0.1 }))
		waterBtn = wdisc(K, "WaterBtnCold", 0.26, 0.04, d * CF(-0.3, 0.85, 0.92), nl(rgb(60, 150, 255)))
		wdisc(K, "WaterBtnRoom", 0.26, 0.04, d * CF(0.3, 0.85, 0.92), nl(rgb(240, 240, 240)))
		txt(K, "WaterBtnText", 1.2, 0.22, d * CF(0, 0.55, 0.93), "냉수        정수", WHITE, nil, F.GothamBold, 1.1)
		K:plate("WaterRecess", 1.0, 1.1, 0.3, d * CF(0, -0.35, 0.62), lk(rgb(20, 20, 22)))
		K:vcyl("WaterNozzle", 0.2, 0.12, CF((d * CF(0, 0.12, 0.6)).Position) * R.A.Rotation, Look.chrome)
		K:plate("WaterTray", 1.1, 0.1, 0.55, d * CF(0, -1.0, 0.9), Look.steel)
		K:plate("WaterTrayGrill", 0.9, 0.02, 0.4, d * CF(0, -0.94, 0.95), lk(rgb(60, 60, 64), M.DiamondPlate))
		local cupBase = (d * CF(0, -0.9, 0.78)).Position
		waterCup = K:vcyl("WaterCup", 0.42, 0.3, CF(cupBase + V3(0, 0.21, 0)) * R.A.Rotation, lk(rgb(248, 248, 244), nil, { t = 1 }))
		waterFill = K:vcyl("WaterFill", 0.02, 0.26, CF(cupBase + V3(0, 0.03, 0)) * R.A.Rotation, lk(rgb(170, 210, 240), M.Glass, { t = 1 }))
		waterStream = K:vcyl("WaterStream", 0.62, 0.05, CF((d * CF(0, -0.26, 0.6)).Position) * R.A.Rotation, lk(rgb(200, 230, 255), M.Glass, { t = 1 }))
		-- 종이컵 디스펜서 (투명 통 + 컵 더미)
		local cd = wallR(R, zc + 1.15, 3.6, 0)
		K:plate("CupHolderBack", 0.42, 1.8, 0.04, cd, Look.steel)
		K:vcyl("CupTube", 1.6, 0.36, CF((cd * CF(0, 0, 0.26)).Position) * R.A.Rotation, gl(rgb(230, 236, 240), 0.55))
		K:vcyl("CupStack", 1.2, 0.3, CF((cd * CF(0, -0.15, 0.26)).Position) * R.A.Rotation, Look.paper)
		txt(K, "WaterSign", 1.9, 0.62, wallR(R, zc + 0.3, 5.55, 0.02), "무료 생수 · FREE WATER\n음주 후 물 한 잔", rgb(120, 220, 255), rgb(12, 14, 20), F.GothamBold, 1.3)
		-- 분리수거함 (일반 · 캔/병 · 컵)
		local bz = 7.5
		local bcf = at(R, R.x1 - 0.65, bz, PI / 2)
		if placeOr(R, bcf, V3(2.4, 2.6, 1.2), 0, "recycle bins") then
			local cols = { { "일반", rgb(60, 60, 64) }, { "캔·병", rgb(30, 110, 200) }, { "종이컵", rgb(40, 150, 80) } }
			for i, c in cols do
				local x = (i - 2) * 0.78
				K:box("RecycleBin", V3(0.74, 2.3, 1.1), bcf * CF(x, 1.15, 0), Look.steel)
				K:box("RecycleBinTop", V3(0.76, 0.12, 1.12), bcf * CF(x, 2.36, 0), lk(c[2]))
				K:box("RecycleSlot", V3(0.4, 0.04, 0.2), bcf * CF(x, 2.43, 0.15), Look.black)
				txt(K, "RecycleLabel", 0.66, 0.34, bcf * CF(x, 1.7, 0.555), c[1], WHITE, c[2], F.GothamBold)
			end
		end
	end
	-- 휴대폰 충전함 (벽걸이 사물함 8칸 + 결제 화면)
	local lockDoor: Model? = nil
	local lockLED: BasePart? = nil
	local lockLabel: TextLabel? = nil
	local lockPhone: BasePart? = nil
	do
		local zc = 11.6
		local d = wallR(R, zc, 4.3, 0)
		K:plate("ChargeBody", 3.8, 5.0, 0.9, d, lk(rgb(232, 232, 236)))
		K:plate("ChargeHeader", 3.8, 0.7, 0.92, d * CF(0, 2.15, 0), lk(rgb(20, 22, 30)))
		txt(K, "ChargeTitle", 3.5, 0.5, d * CF(0, 2.15, 0.93), "휴대폰 충전 · PHONE CHARGE", rgb(80, 230, 140), nil, F.GothamBlack, 1.5)
		K:plate("ChargeScreen", 1.1, 1.4, 0.94, d * CF(1.15, 0.95, 0), lk(rgb(16, 20, 30), M.Glass, { r = 0.1 }))
		local _, sl = txt(K, "ChargeScreenText", 1.0, 1.2, d * CF(1.15, 0.95, 0.95), "충전 대여\n1시간\n1,500원\n카드 · QR", rgb(150, 230, 255), nil, F.GothamBold, 1.4)
		lockLabel = sl
		K:plate("ChargeCardSlot", 0.6, 0.12, 0.95, d * CF(1.15, 0.0, 0), Look.black)
		-- 사물함 2열 x 4행
		for col = 0, 1 do
			for row = 0, 3 do
				local idx = row * 2 + col + 1
				local cx, cy = -1.25 + col * 1.0, 1.35 - row * 0.95
				local dd = d * CF(cx, cy, 0.9)
				local isUser = (idx == 3)
				local function doorParts()
					K:plate("LockerDoor", 0.92, 0.88, 0.05, dd, lk(rgb(210, 212, 218)))
					K:plate("LockerHandle", 0.06, 0.3, 0.05, dd * CF(0.36, 0, 0.05), Look.chrome)
					txt(K, "LockerNo", 0.3, 0.2, dd * CF(-0.28, 0.28, 0.055), string.format("%02d", idx), rgb(40, 40, 50), nil, F.GothamBold)
				end
				if isUser then
					lockDoor = K:group("ChargeLockerDoor", doorParts)
					lockPhone = K:box("LockerPhone", V3(0.36, 0.7, 0.06), dd * CF(0, -0.02, -0.25) * ANG(math.rad(-10), 0, 0), lk(rgb(20, 20, 24), nil, { t = 1 }))
					K:plate("LockerInside", 0.86, 0.82, 0.02, dd * CF(0, 0, -0.45), lk(rgb(40, 40, 44)))
				else
					doorParts()
				end
				local led = wdisc(K, "LockerLED", 0.1, 0.03, dd * CF(0.3, -0.32, 0.05), nl(if idx == 2 or idx == 6 then rgb(255, 170, 40) else rgb(60, 230, 120)))
				if isUser then
					lockLED = led
				end
			end
		end
	end
	-- 오른벽 안쪽: 옥내소화전 + 발신기 · AED · CLUB OCEAN 로고 패널 ----------------------------------------
	do
		local d = wallR(R, -34.8, 2.9, 0)
		K:plate("HydrantBox", 2.4, 4.6, 0.5, d, lk(rgb(196, 28, 30)))
		K:plate("HydrantDoor", 2.2, 4.4, 0.52, d, lk(rgb(210, 36, 36)))
		K:plate("HydrantWindow", 1.4, 1.2, 0.53, d * CF(0, 0.9, 0), gl(rgb(220, 230, 236), 0.5))
		K:plate("HydrantHandle", 0.1, 0.5, 0.58, d * CF(0.9, 0, 0), Look.chrome)
		txt(K, "HydrantText", 1.8, 0.7, d * CF(0, -0.6, 0.54), "소화전\nFIRE HOSE", WHITE, nil, F.GothamBlack)
		local tp = wallR(R, -34.8, 6.0, 0)
		K:plate("HydrantBellBox", 1.4, 1.1, 0.14, tp, lk(rgb(196, 28, 30)))
		wdisc(K, "HydrantLamp", 0.34, 0.06, tp * CF(0, 0.22, 0.14), nl(rgb(255, 40, 30)))
		wdisc(K, "HydrantButton", 0.26, 0.05, tp * CF(-0.35, -0.22, 0.14), Look.white)
		wdisc(K, "HydrantBell", 0.36, 0.08, tp * CF(0.35, -0.22, 0.14), Look.brass)
		txt(K, "HydrantBellText", 1.2, 0.16, tp * CF(0, -0.47, 0.15), "발신기 · 누르면 경보", WHITE, nil, F.GothamBold)
	end
	do
		local d = wallR(R, -30.55, 4.3, 0)
		K:plate("AEDBox", 1.7, 2.3, 0.45, d, Look.white)
		K:plate("AEDDoor", 1.5, 1.5, 0.47, d * CF(0, -0.25, 0), gl(rgb(220, 236, 230), 0.45))
		K:box("AEDUnit", V3(1.0, 0.9, 0.3), d * CF(0, -0.35, 0.22), lk(rgb(240, 200, 40)))
		K:plate("AEDHead", 1.7, 0.55, 0.47, d * CF(0, 0.88, 0), lk(rgb(30, 150, 80)))
		txt(K, "AEDText", 1.5, 0.45, d * CF(0, 0.88, 0.48), "♥ AED 자동심장충격기", WHITE, nil, F.GothamBlack)
		wdisc(K, "AEDLamp", 0.14, 0.03, d * CF(0.62, 0.45, 0.47), nl(rgb(60, 230, 120)))
	end
	do
		-- 로고 패널 (검은 유리 + 네온 원 + 파도)
		local d = wallR(R, -24.2, 5.8, 0)
		K:plate("LogoPanel", 5.6, 3.6, 0.1, d, lk(rgb(14, 14, 18)))
		K:plate("LogoPanelEdge", 5.7, 3.7, 0.06, d, Look.brass)
		K:ring("LogoRing", d * CF(-1.4, 0.15, 0.14), 1.1, 0.1, 18, nl(CYAN))
		for i = 0, 5 do
			local a0, a1 = -1.6 + i * 0.5, -1.6 + (i + 1) * 0.5
			K:seg("LogoWave", (d * CF(-1.4 + a0 * 0.62, 0.15 + math.sin(a0 * 3) * 0.18, 0.14)).Position, (d * CF(-1.4 + a1 * 0.62, 0.15 + math.sin(a1 * 3) * 0.18, 0.14)).Position, 0.08, nl(rgb(255, 70, 170)))
		end
		txt(K, "LogoText", 2.8, 1.4, d * CF(1.15, 0.15, 0.12), "CLUB\nOCEAN", WHITE, nil, F.GothamBlack, 1.8)
		txt(K, "LogoSub", 2.8, 0.36, d * CF(1.15, -1.25, 0.12), "GWANGALLI · SINCE 2019", rgb(170, 170, 190), nil, F.GothamMedium, 1.2)
	end
	-- 왼벽: 전신 거울 (비상구와 여자 화장실 사이) · 화장실 대기 벤치 ------------------------------------------
	do
		local d = wallL(R, -28.9, 3.9, 0)
		K:plate("FullMirrorFrame", 2.6, 6.2, 0.1, d, Look.blackMetal)
		K:plate("FullMirror", 2.3, 5.9, 0.12, d, MIRROR)
		K:plate("FullMirrorLED", 2.4, 0.06, 0.13, d * CF(0, 3.0, 0), nl(rgb(255, 230, 210)))
		K:plate("FullMirrorLED", 2.4, 0.06, 0.13, d * CF(0, -3.0, 0), nl(rgb(255, 230, 210)))
		txt(K, "MirrorDecal", 1.8, 0.32, d * CF(0, 2.5, 0.13), "오늘 밤도 멋져요 ✦", rgb(255, 220, 240), nil, F.GothamMedium, 1.2)
	end
	do
		local z0, z1 = -17.6, -7.0
		local pcf = at(R, R.x0 + 0.8, (z0 + z1) / 2)
		if placeOr(R, pcf, V3(1.6, 2.0, z1 - z0), 0, "queue bench") then
			K:box("QBenchBase", V3(1.3, 0.55, z1 - z0 - 0.4), pcf * CF(-0.05, 0.28, 0), Look.black)
			K:box("QBenchGlow", V3(0.05, 0.05, z1 - z0 - 0.6), pcf * CF(0.62, 0.06, 0), nl(PURP))
			K:rbox("QBenchSeat", V3(z1 - z0, 0.55, 1.6), 0.18, pcf * CF(0, 0.85, 0) * ANG(0, PI / 2, 0), leather)
		end
		K:plate("QBenchSign", 3.0, 0.5, 0.03, wallL(R, -12.3, 3.45, 0.07), lk(rgb(20, 18, 24)))
		txt(K, "QBenchSignText", 2.9, 0.4, wallL(R, -12.3, 3.45, 0.1), "화장실 대기 · RESTROOM QUEUE", rgb(255, 210, 120), nil, F.GothamBold, 1.1)
	end
	-- 뒷벽: 네온 아트 (달 + 파도 + 글자) --------------------------------------------------------------
	K:free(function()
		local d = wallB(R, 2.6, 6.2, 0)
		K:plate("NeonArtBacker", 10.0, 4.6, 0.08, d, lk(rgb(10, 10, 14)))
		K:plate("NeonArtFrame", 10.2, 0.08, 0.12, d * CF(0, 2.3, 0), Look.brass)
		K:plate("NeonArtFrame", 10.2, 0.08, 0.12, d * CF(0, -2.3, 0), Look.brass)
		K:ring("NeonMoon", d * CF(-3.2, 0.6, 0.12), 1.1, 0.12, 20, nl(rgb(255, 120, 200)))
		local prev: Vector3? = nil
		for i = 0, 14 do
			local x = -4.6 + i * 0.66
			local p = (d * CF(x, -1.15 + math.sin(i * 0.9) * 0.28, 0.12)).Position
			if prev then
				K:seg("NeonWave", prev, p, 0.1, nl(CYAN))
			end
			prev = p
		end
		local glowP = txt(K, "NeonArtText", 6.0, 1.5, d * CF(1.4, 0.65, 0.1), "BUSAN\nNEVER SLEEPS", rgb(255, 236, 200), nil, F.GothamBlack, 2.2)
		K:light(glowP, "PointLight", { Range = 12, Brightness = 0.9, Color = rgb(120, 180, 255) })
	end)
	plant(K, R, R.x1 - 1.1, R.z0 + 1.2, "snake", 4.4, 1.4, lk(rgb(30, 30, 34), M.Concrete))
	-- 앞벽 안쪽: 디지털 사이니지 (화면 순환) ---------------------------------------------------------------
	K:free(function()
		local d = wallF(R, 1.0, 6.0, 0)
		K:plate("SignageBody", 5.4, 3.2, 0.18, d, Look.black)
		local scr = K:plate("SignageScreen", 5.1, 2.9, 0.2, d, lk(rgb(30, 14, 60), M.Neon, { t = 0.1 }))
		local _, lab = txt(K, "SignageText", 4.8, 2.4, d * CF(0, 0, 0.21), "NOW PLAYING\nDJ HAEWON · TECH HOUSE", WHITE, nil, F.GothamBlack, 1.5)
		Interact.screenLoop(K, scr, lab, {
			{ c = rgb(30, 14, 60), text = "NOW PLAYING\nDJ HAEWON · TECH HOUSE" },
			{ c = rgb(10, 40, 70), text = "ROOFTOP OPEN\n하이볼 2+1 · 19:00-21:00" },
			{ c = rgb(60, 14, 30), text = "음주운전 NO!\n대리운전 · 택시 호출은 로비 데스크" },
			{ c = rgb(14, 50, 40), text = "분실물 보관 · 1F 로비\nLOST & FOUND" },
			{ c = rgb(40, 20, 70), text = "ROOM 2 · HIP-HOP\n오늘 밤 사이퍼 배틀 01:00" },
		}, 5)
		K:plate("SignageLogo", 0.5, 0.06, 0.19, d * CF(0, -1.56, 0), Look.chrome)
	end)
	-- 천장 ----------------------------------------------------------------------------------------------
	for _, z in { -34, -26, -18, -10, -2, 6, 14, 22, 30 } do
		for _, x in { -5.4, 5.2 } do
			downlight(K, R, x, z, {})
		end
	end
	-- 벽 쪽 코브 2줄 (가죽 징두리 · 사진을 고르게 비춤)
	cove(K, R, R.x0 + 1.0, R.z0 + 0.6, R.x0 + 1.0, R.z1 - 0.6, H - 0.12, rgb(255, 206, 160), 0, 0, false)
	cove(K, R, R.x1 - 1.0, R.z0 + 0.6, R.x1 - 1.0, R.z1 - 0.6, H - 0.12, rgb(255, 206, 160), 0, 0, false)
	-- 구역 조명 (정수기 · 충전함 / 소화전 · AED / 화장실 대기 벤치 · 거울)
	for _, p in { { 4.6, 6.5 }, { 4.8, -27.0 }, { -4.8, -16.0 } } do
		local a = K:box("CorrZoneLight", V3(0.1, 0.1, 0.1), at(R, p[1], p[2], 0, 8.6), lk(BLACK, nil, { t = 1 }))
		K:light(a, "PointLight", { Range = 13, Brightness = 0.85, Color = rgb(255, 206, 170) })
	end
	K:free(function()
		for _, x in { -2.3, 2.1 } do
			K:box("SlotDiffuser", V3(0.35, 0.04, R.D - 2), at(R, x, R.cz, 0, H - 0.02), lk(rgb(26, 26, 30)))
			K:box("SlotDiffuserGap", V3(0.12, 0.045, R.D - 2.2), at(R, x, R.cz, 0, H - 0.025), lk(rgb(6, 6, 8)))
		end
	end)
	for _, z in { -30, -14, 2, 18, 34 } do
		sprinkler(K, R, -3.6, z)
		sprinkler(K, R, 3.6, z + 8)
	end
	smoke(K, R, 3.6, -22)
	smoke(K, R, -3.6, 10)
	cctv(K, R, 6.4, -36.6)
	cctv(K, R, -6.0, 36.4)
	for _, z in { -24, 0, 24 } do
		ceilSpeaker(K, R, -3.6, z)
	end
	-- 매달린 안내판 + 피난 유도등
	hangSign(K, R, 0, 22.0, 7.6, 9.0, 1.4, 0, { title = "◀ 화장실 RESTROOM      ROOM 2 · HIP-HOP ▶", c = rgb(255, 220, 150) }, { title = "◀ MAIN HALL · 메인홀", c = rgb(120, 220, 255) })
	K:free(function()
		local d = at(R, 0, -26.0, 0, 8.4)
		K:seg("ExitGuideRod", (d * CF(-0.9, 0.5, 0)).Position, (d * CF(-0.9, H - 8.4, 0)).Position, 0.04, Look.blackMetal)
		K:seg("ExitGuideRod", (d * CF(0.9, 0.5, 0)).Position, (d * CF(0.9, H - 8.4, 0)).Position, 0.04, Look.blackMetal)
		exitLight(K, d, 2.4, "◀ ")
		exitLight(K, d * ANG(0, PI, 0), 2.4, "")
	end)
	-- 바닥 고보 (CLUB OCEAN 로고 빛 무늬)
	K:free(function()
		local p = ap(R, -0.2, 0.03, 29.5)
		txt(K, "FloorGobo", 4.2, 1.2, topCF(p, av(R, 0, 0, -1)), "CLUB OCEAN", rgb(190, 140, 255), nil, F.GothamBlack, 0.9, { d = 0.01 })
		K:ring("FloorGoboRing", CF(p) * R.A.Rotation * ANG(PI / 2, 0, 0), 2.6, 0.06, 24, lk(rgb(150, 100, 230), M.Neon, { t = 0.55 }))
	end)

	-- 상호작용 -----------------------------------------------------------------------------------------
	-- 1) 라인업 보기
	if lbFace then
		prompt(R, lbFace, "cycle", {
			action = "라인업 보기",
			object = "이번 주 라인업",
			on = function(_i, it)
				if lbLabel then
					lbLabel.Text = it
				end
			end,
		}, LINEUP)
	end
	-- 2) 정수기: 물 받기
	if waterBtn then
		local busy = false
		prompt(R, waterBtn, "prompt", {
			action = "물 받기",
			object = "무료 정수기",
			fn = function()
				if busy then
					return
				end
				busy = true
				if waterCup then
					(waterCup :: BasePart).Transparency = 0
				end
				if waterStream then
					(waterStream :: BasePart).Transparency = 0.35
				end
				if waterFill then
					local f = waterFill :: BasePart
					f.Transparency = 0.25
					local c0 = f.CFrame
					tween(f, { Size = V3(0.3, 0.26, 0.26), CFrame = c0 * CF(0.15, 0, 0) }, 1.4)
					task.delay(1.5, function()
						if waterStream then
							(waterStream :: BasePart).Transparency = 1
						end
					end)
					task.delay(4.5, function()
						f.Transparency = 1
						f.Size = V3(0.02, 0.26, 0.26)
						f.CFrame = c0
						if waterCup then
							(waterCup :: BasePart).Transparency = 1
						end
						busy = false
					end)
				else
					busy = false
				end
			end,
		})
	end
	-- 3) 휴대폰 충전함: 03번 칸 열고 충전
	if lockDoor and lockLED then
		local door = lockDoor :: Model
		local parts = {}
		for _, d in door:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, { p = d, cf = d.CFrame })
			end
		end
		local hingeL = R.V.cf * ((wallR(R, 11.6, 4.3, 0)) * CF(-1.71, 0.4, 0.95)).Position
		local axis = R.V.cf:VectorToWorldSpace(V3(0, 1, 0))
		local busy = false
		local function setOpen(o: boolean)
			local rot = CF(hingeL) * CFrame.fromAxisAngle(axis, if o then -1.7 else 0) * CF(-hingeL)
			for _, r in parts do
				tween(r.p, { CFrame = rot * r.cf }, 0.4)
			end
		end
		local trigger = parts[1] and parts[1].p or nil
		prompt(R, trigger, "prompt", {
			action = "휴대폰 충전",
			object = "충전함 03번",
			fn = function()
				if busy then
					return
				end
				busy = true
				setOpen(true)
				task.delay(0.6, function()
					if lockPhone then
						(lockPhone :: BasePart).Transparency = 0
					end
					setOpen(false)
					local led = lockLED :: BasePart
					led.Color = rgb(255, 170, 40)
					task.spawn(function()
						for pct = 10, 100, 15 do
							if lockLabel then
								(lockLabel :: TextLabel).Text = string.format("03번 충전 중\n%d%%\n\n잠금 완료", pct)
							end
							task.wait(0.8)
						end
						led.Color = rgb(60, 230, 120)
						if lockLabel then
							(lockLabel :: TextLabel).Text = "03번\n충전 완료\n100%\n찾아가세요"
						end
						task.wait(4)
						if lockLabel then
							(lockLabel :: TextLabel).Text = "충전 대여\n1시간\n1,500원\n카드 · QR"
						end
						if lockPhone then
							(lockPhone :: BasePart).Transparency = 1
						end
						busy = false
					end)
				end)
			end,
		})
	end
end

--=====================================================================================================
-- 화장실 (clubwc) -----------------------------------------------------------------------------------
--=====================================================================================================
-- 칸 안 소품: 휴지걸이 · 안내문 · 옷걸이 (+ 여자: 위생용품 수거함)
local function stallKit(K: any, R: any, xl: number, xr: number, zb: number, female: boolean)
	local cx = (xl + xr) / 2
	-- 휴지걸이 (오른쪽 칸막이, 변기 옆)
	local tp = face(R, xr - 0.08, 2.3, zb + 2.6, -PI / 2)
	K:plate("TPHolderBack", 0.7, 0.75, 0.05, tp, Look.chrome)
	K:cyl("TPRoll", 0.5, 0.48, tp * CF(0, -0.05, 0.3), Look.paper)
	K:plate("TPHood", 0.72, 0.08, 0.5, tp * CF(0, 0.33, 0), Look.chrome)
	-- 안내문 (뒷벽, 물탱크 위)
	local sd = wallB(R, cx, 4.6, 0)
	K:plate("StallSignBoard", 2.0, 0.9, 0.03, sd, Look.white)
	txt(K, "StallSignText", 1.9, 0.8, sd * CF(0, 0, 0.035), if female then "사용한 휴지는 변기에\n위생용품은 수거함에\n🚫 흡연 금지" else "사용한 휴지는 변기에\n물은 꼭 내려주세요\n🚫 흡연 금지", rgb(40, 40, 50), nil, F.GothamBold)
	-- 옷걸이 (뒷벽 위)
	local hk = wallB(R, cx + 1.4, 6.4, 0)
	K:plate("CoatHookBase", 0.2, 0.3, 0.04, hk, Look.chrome)
	K:bar("CoatHook", (hk * CF(0, 0, 0.04)).Position, (hk * CF(0, 0.12, 0.3)).Position, 0.06, 0.06, Look.chrome)
	if female then
		-- 위생용품 수거함 (왼쪽 칸막이 옆 작은 페달통)
		local pcf = at(R, xl + 0.7, zb + 0.9)
		K:free(function()
			K:box("SanitaryBin", V3(0.7, 1.1, 0.5), pcf * CF(0, 0.55, 0), Look.white)
			K:box("SanitaryBinLid", V3(0.72, 0.1, 0.52), pcf * CF(0, 1.14, 0), lk(rgb(230, 120, 170)))
			K:box("SanitaryBinPedal", V3(0.3, 0.05, 0.14), pcf * CF(0, 0.05, 0.3), Look.chrome)
		end)
	end
end

-- 할리우드 거울 (전구 둘레). dcf 중심, w x h
local function hollywoodMirror(K: any, dcf: CFrame, w: number, h: number, bulbs: { BasePart })
	K:plate("HMirrorFrame", w + 0.5, h + 0.5, 0.12, dcf, lk(rgb(244, 236, 230)))
	K:plate("HMirror", w, h, 0.14, dcf, MIRROR)
	local function bulb(x: number, y: number)
		K:vcyl("HBulbSocket", 0.12, 0.16, CF((dcf * CF(x, y, 0.16)).Position) * dcf.Rotation * ANG(PI / 2, 0, 0), Look.chrome)
		local b = K:ball("HBulb", 0.26, dcf * CF(x, y, 0.28), Look.lampWarm)
		table.insert(bulbs, b)
	end
	local nx = math.max(3, math.floor(w / 0.75))
	for i = 0, nx - 1 do
		local x = -w / 2 + (i + 0.5) * w / nx
		bulb(x, h / 2 + 0.12)
	end
	local ny = math.max(2, math.floor(h / 0.85))
	for j = 0, ny - 1 do
		local y = -h / 2 + (j + 0.5) * h / ny
		bulb(-w / 2 - 0.12, y)
		bulb(w / 2 + 0.12, y)
	end
end

-- 종이타월 디스펜서 (벽). dcf 중심. 반환: 뽑히는 타월 파트
local function towelDispenser(K: any, dcf: CFrame): (BasePart, BasePart)
	K:plate("TowelBody", 1.1, 1.5, 0.45, dcf, Look.steel)
	K:plate("TowelWindow", 0.5, 0.12, 0.46, dcf * CF(0, 0.3, 0), gl(rgb(200, 210, 220), 0.4))
	K:plate("TowelSlot", 0.8, 0.06, 0.46, dcf * CF(0, -0.68, 0), Look.black)
	txt(K, "TowelLabel", 0.8, 0.2, dcf * CF(0, 0.55, 0.47), "PAPER TOWEL", rgb(60, 60, 64), nil, F.GothamBold)
	local sheet = K:plate("TowelSheet", 0.7, 0.55, 0.02, dcf * CF(0, -0.98, 0.35), lk(rgb(240, 238, 230), nil, { t = 1 }))
	local lever = K:plate("TowelLever", 0.5, 0.18, 0.48, dcf * CF(0, -0.45, 0), Look.black)
	return sheet, lever
end

-- 맵의 네모 위생도기 (소변기 · 세면볼 · 물 · 수전 · 비누 · 둥근 거울 · 핸드드라이어) 를 숨기고 같은 자리에 진짜 모양으로
-- (맵 파트는 충돌이 그대로 남으니 새 모양은 같은 부피 안에 짓고 충돌 없음)
local CHINA = { c = Color3.fromRGB(240, 240, 236), m = Enum.Material.SmoothPlastic, r = 0.06 }
local function rebuildWCFixtures(K: any, R: any, female: boolean): { BasePart }
	local V = R.V
	local mirrors: { BasePart } = {}
	local function each(name: string, fn: (mn: Vector3, mx: Vector3) -> ())
		for _, r in V.byName[name] or {} do
			local mn, mx = abox(R, r)
			if mx.X > R.x0 - 0.5 and mn.X < R.x1 + 0.5 and safeHide(K, r) then
				K:free(function()
					fn(mn, mx)
				end)
			end
		end
	end
	-- 벽 쪽 (+1 = 왼벽 x0 에 붙음, -1 = 오른벽 x1)
	local function side(mn: Vector3, mx: Vector3): (number, number)
		if math.abs(mn.X - R.x0) < math.abs(mx.X - R.x1) then
			return 1, mn.X
		end
		return -1, mx.X
	end
	-- 벽걸이 소변기: 벽에 반쯤 묻힌 타원 몸통 + 앞으로 열린 볼 + 뒤판 + 바닥 쪽 배수 커버
	each("Urinal", function(mn, mx)
		local s, wx = side(mn, mx)
		local d, h, w = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
		local cz, yc = (mn.Z + mx.Z) / 2, (mn.Y + mx.Y) / 2
		K:box("UrinalBack", V3(0.1, h - 0.1, w - 0.3), at(R, wx + s * 0.05, cz, 0, yc + 0.05), CHINA)
		K:ell("UrinalBody", V3(2 * (d - 0.05), h, w - 0.1), at(R, wx, cz, 0, yc), CHINA)
		K:ell("UrinalBowl", V3(2 * (d - 0.2), h * 0.66, w * 0.66), at(R, wx + s * 0.18, cz, 0, yc - h * 0.06), lk(rgb(206, 210, 210)))
		K:ell("UrinalLip", V3(2 * (d - 0.06), 0.3, w * 0.8), at(R, wx, cz, 0, mn.Y + h * 0.2), CHINA)
	end)
	-- 세면볼 (원형 베슬) + 물 + 배수구
	each("VesselSink", function(mn, mx)
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		local dia = math.min(mx.X - mn.X, mx.Z - mn.Z)
		local h = mx.Y - mn.Y
		K:vcyl("VesselFoot", 0.18, dia * 0.6, at(R, cx, cz, 0, mn.Y + 0.09), CHINA)
		K:vcyl("VesselLow", h * 0.35, dia * 0.86, at(R, cx, cz, 0, mn.Y + 0.1 + h * 0.175), CHINA)
		K:vcyl("VesselBowl", h * 0.55, dia, at(R, cx, cz, 0, mn.Y + h * 0.45 + h * 0.275), CHINA)
		K:disc("VesselInner", dia - 0.18, 0.02, at(R, cx, cz, 0, mx.Y + 0.01), lk(rgb(198, 204, 208)))
		K:disc("VesselDrain", 0.26, 0.02, at(R, cx, cz, 0, mx.Y + 0.025), Look.chrome)
	end)
	each("BasinWater", function() end)
	-- 벽 수전: 로제트 + 길게 나온 스파우트 + 아래로 꺾인 끝 + 레버
	each("WallTap", function(mn, mx)
		local s, wx = side(mn, mx)
		local cz, yc = (mn.Z + mx.Z) / 2, (mn.Y + mx.Y) / 2
		local len = mx.X - mn.X
		K:cyl("TapRosette", 0.06, 0.42, at(R, wx + s * 0.03, cz, 0, yc), Look.chrome)
		K:cyl("TapSpout", len - 0.05, 0.13, at(R, wx + s * (len / 2), cz, 0, yc), Look.chrome)
		K:vcyl("TapNozzle", 0.2, 0.14, at(R, wx + s * (len - 0.07), cz, 0, yc - 0.08), Look.chrome)
		K:cyl("TapLeverHub", 0.12, 0.16, at(R, wx + s * 0.1, cz, 0, yc + 0.42), Look.chrome)
		K:box("TapLever", V3(0.36, 0.05, 0.08), at(R, wx + s * 0.28, cz, 0, yc + 0.46) * ANG(0, 0, s * 0.35), Look.chrome)
	end)
	-- 비누 디스펜서: 호박색 유리병 + 크롬 펌프
	each("SoapDispenser", function(mn, mx)
		local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
		K:vcyl("SoapBottle", 0.42, 0.26, at(R, cx - 0.05, cz, 0, mn.Y + 0.21), lk(rgb(120, 70, 30), M.Glass, { t = 0.15 }))
		K:vcyl("SoapCollar", 0.06, 0.16, at(R, cx - 0.05, cz, 0, mn.Y + 0.45), Look.chrome)
		K:vcyl("SoapPump", 0.12, 0.1, at(R, cx - 0.05, cz, 0, mn.Y + 0.54), Look.chrome)
		K:box("SoapNozzle", V3(0.2, 0.05, 0.05), at(R, cx - 0.15, cz, 0, mn.Y + 0.6), Look.chrome)
		txt(K, "SoapLabel", 0.2, 0.12, face(R, cx - 0.05, mn.Y + 0.22, cz, -PI / 2) * CF(0, 0, 0.13), "HAND\nWASH", rgb(240, 230, 210), nil, F.GothamBold)
	end)
	-- 둥근 거울 (맵 유리는 밤에 하얗게 떠서) → 은회색 거울 원판, 후광 네온은 그대로
	each("RoundMirror", function(mn, mx)
		local s, wx = side(mn, mx)
		local cz, yc = (mn.Z + mx.Z) / 2, (mn.Y + mx.Y) / 2
		local dia = math.min(mx.Y - mn.Y, mx.Z - mn.Z)
		local front = if s == 1 then mx.X else mn.X
		local _ = wx
		local dcf = R.A * CFrame.fromMatrix(V3(front, yc, cz), V3(0, 0, -s), Vector3.yAxis, V3(s, 0, 0))
		local m = wdisc(K, "RoundMirrorFace", dia, 0.08, dcf * CF(0, 0, -0.06), MIRROR)
		table.insert(mirrors, m)
		K:ell("RoundMirrorSheen", V3(dia * 0.5, dia * 0.12, 0.02), dcf * CF(-dia * 0.12, dia * 0.22, 0.03) * ANG(0, 0, 0.6), lk(rgb(150, 160, 172), M.SmoothPlastic, { t = 0.55 }))
	end)
	-- 핸드드라이어 (한국 공중화장실의 위에서 손 넣는 '제트 타올' 형)
	each("HandDryer", function(mn, mx)
		local s, wx = side(mn, mx)
		local d, h, w = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
		local cz = (mn.Z + mx.Z) / 2
		local function blk(nm: string, y0: number, y1: number, dd: number, look: any)
			K:rbox(nm, V3(w, y1 - y0, dd), 0.12, at(R, wx + s * dd / 2, cz, PI / 2, (y0 + y1) / 2), look)
		end
		local body = lk(rgb(236, 238, 240))
		blk("JetTowelLower", mn.Y, mn.Y + h * 0.55, d, body)
		blk("JetTowelUpper", mn.Y + h * 0.8, mx.Y, d * 0.55, body)
		K:box("JetTowelBack", V3(0.06, h * 0.3, w - 0.1), at(R, wx + s * 0.03, cz, 0, mn.Y + h * 0.68), lk(rgb(30, 32, 36)))
		K:box("JetTowelSlot", V3(d * 0.6, 0.04, w - 0.3), at(R, wx + s * (d * 0.45), cz, 0, mn.Y + h * 0.55 + 0.02), lk(rgb(40, 44, 50)))
		K:box("JetTowelLED", V3(0.02, 0.05, w * 0.5), at(R, wx + s * (d + 0.01), cz, 0, mn.Y + h * 0.45), nl(rgb(60, 170, 255)))
		txt(K, "JetTowelLabel", w * 0.8, 0.22, R.A * CFrame.fromMatrix(V3(wx + s * (d + 0.015), mn.Y + h * 0.3, cz), V3(0, 0, -s), Vector3.yAxis, V3(s, 0, 0)), "JET TOWEL · 손을 넣으세요", rgb(60, 70, 90), nil, F.GothamBold)
	end)
	-- 소변기 칸막이 (맵 그대로): 앞 모서리 헤어라인 마감 + 윗면 캡 (밤에 칸막이 윤곽이 보이게)
	for _, r in V.byName.UrinalDivider or {} do
		local mn, mx = abox(R, r)
		local s = if math.abs(mn.X - R.x0) < math.abs(mx.X - R.x1) then 1 else -1
		local fx = if s == 1 then mx.X else mn.X
		local cz = (mn.Z + mx.Z) / 2
		K:free(function()
			K:box("DividerEdge", V3(0.1, mx.Y - mn.Y, (mx.Z - mn.Z) + 0.06), at(R, fx + s * 0.05, cz, 0, (mn.Y + mx.Y) / 2), Look.brushed)
			K:box("DividerCap", V3(mx.X - mn.X, 0.06, (mx.Z - mn.Z) + 0.06), at(R, (mn.X + mx.X) / 2, cz, 0, mx.Y + 0.03), Look.brushed)
		end)
	end
	local _ = female
	return mirrors
end

local function buildRestroom(K: any, V: any, R: any)
	local female = V.room == "wc_f"
	rebuildWCFixtures(K, R, female)
	local ACC = if female then rgb(255, 60, 170) else rgb(60, 140, 255)
	local ACC2 = if female then rgb(255, 180, 210) else rgb(150, 210, 255)
	local tileL = lk(rgb(36, 34, 40), M.CeramicTiles)
	local marbleD = lk(rgb(26, 24, 30), M.Marble)
	local x0, x1, z0, z1 = R.x0, R.x1, R.z0, R.z1
	local H = R.H
	-- 비울 곳 (칸 앞 · 입구 · 세면대 앞 · 소변기 앞)
	local doorX0 = if female then -0.5 else -1.0
	local doorX1 = if female then 3.5 else 3.0
	keepBox(R, x0, -12.3 + (z0 + 20.4) * 0, x1, -8.4, 8, "stall")
	keepBox(R, doorX0 - 0.5, z1 - 4.4, doorX1 + 0.5, z1, 8, "door")
	local vanX = if female then 6.9 else 7.4
	keepBox(R, vanX - 2.4, -3.8, vanX, 14.8, 6.5, "sink")
	if not female then
		keepBox(R, x0, -10.5, -6.6, 8.3, 6.5, "urinal")
	end
	-- 가운데 통로 (입구 -> 칸)
	keepBox(R, doorX0 + 0.3, -8.4, vanX - 2.4, z1 - 4.4, 6.5, "lane")

	local bulbs: { BasePart } = {}
	local mirrorLights: { Light } = {}
	-- 칸 안 소품 -------------------------------------------------------------------------------------
	local stalls = if female then { { -9.5, -3.15 }, { -3.15, 3.15 }, { 3.15, 9.5 } } else { { -3.9, 2.8 }, { 3.1, 10.0 } }
	for _, s in stalls do
		stallKit(K, R, s[1], s[2], z0, female)
	end
	-- 칸 위 벽 (y 8.3 위): 간판 띠 + 간접등
	K:plate("StallFascia", x1 - (if female then x0 else -4.0), 1.9, 0.08, wallB(R, ((if female then x0 else -4.0) + x1) / 2, 9.35, 0), tileL)
	K:plate("StallFasciaLED", x1 - (if female then x0 else -4.0) - 0.2, 0.06, 0.12, wallB(R, ((if female then x0 else -4.0) + x1) / 2, 8.45, 0), nl(ACC))
	txt(K, "StallFasciaText", 6, 0.9, wallB(R, (if female then 0 else 3.0), 9.4, 0.1), if female then "POWDER ROOM ♡" else "GENTLEMEN", ACC2, nil, F.GothamBlack, 1.6)

	-- 왼벽 / 앞벽 마감 (대리석 징두리 + 짙은 타일 + 네온 띠) --------------------------------------------------
	local function cladLeftRaw(za: number, zb: number)
		K:plate("WCWainscot", zb - za, 3.3, 0.06, wallL(R, (za + zb) / 2, 0.05 + 1.65, 0), marbleD)
		K:plate("WCTile", zb - za, 6.6, 0.05, wallL(R, (za + zb) / 2, 3.4 + 3.3, 0), tileL)
		K:plate("WCNeonCap", zb - za, 0.07, 0.1, wallL(R, (za + zb) / 2, 3.4, 0), nl(ACC))
		if hi(K) then
			-- 타일 줄눈 (가로 4줄)
			for j = 1, 4 do
				K:plate("WCGrout", zb - za, 0.03, 0.055, wallL(R, (za + zb) / 2, 3.4 + j * 1.32, 0), lk(rgb(56, 54, 60)))
			end
		end
	end
	local function cladLeft(za: number, zb: number)
		K:free(function()
			cladLeftRaw(za, zb)
		end)
	end

	local amenity: BasePart? = nil
	local mouthCup: BasePart? = nil
	local puff: BasePart? = nil
	local mirrorToggle: BasePart? = nil
	if female then
		-- 왼벽 전체 마감 (칸 앞 ~ 앞벽)
		cladLeft(-12.2, -7.4)
		cladLeft(9.4, 20.1)
		-- 파우더 카운터 (왼벽, z -7..9) -----------------------------------------------------------------
		local cz0, cz1 = -7.2, 9.2
		local len = cz1 - cz0
		local ccz = (cz0 + cz1) / 2
		local base = at(R, x0 + 0.9, ccz)
		K:free(function()
			K:box("PowderPlinth", V3(1.5, 0.22, len - 0.2), base * CF(0.1, 0.11, 0), Look.black)
			K:box("PowderBody", V3(1.8, 2.2, len), base * CF(0, 0.22 + 1.1, 0), lk(rgb(40, 30, 38), M.Wood))
			K:box("PowderTop", V3(2.1, 0.16, len + 0.2), base * CF(0.15, 2.5, 0), lk(rgb(236, 230, 226), M.Marble))
			K:box("PowderUnderLED", V3(0.05, 0.05, len - 0.4), base * CF(1.08, 2.36, 0), nl(ACC))
			-- 서랍 3칸 + 황동 손잡이
			for i = 0, 2 do
				local zc = cz0 + len * (i + 0.5) / 3 - ccz
				K:box("PowderDrawer", V3(0.05, 0.75, len / 3 - 0.3), base * CF(0.92, 1.95, zc), lk(rgb(52, 40, 48), M.Wood))
				K:box("PowderDrawerPull", V3(0.08, 0.06, 0.9), base * CF(0.97, 1.95, zc), Look.brass)
				K:box("PowderKnee", V3(0.04, 1.2, len / 3 - 0.3), base * CF(0.91, 0.95, zc), lk(rgb(30, 22, 28), M.Wood))
			end
			-- 대리석 백스플래시 + 거울 위 타일
			K:plate("PowderSplash", len + 0.2, 0.9, 0.08, wallL(R, ccz, 3.0, 0), lk(rgb(236, 230, 226), M.Marble))
			K:plate("WCTile", len + 0.2, 3.3, 0.05, wallL(R, ccz, 8.65, 0), tileL)
			K:plate("WCTile", len + 0.2, 3.5, 0.04, wallL(R, ccz, 5.2, 0), lk(rgb(30, 28, 34), M.CeramicTiles))
		end)
		-- 할리우드 거울 3 + 조명
		for i = 0, 2 do
			local zc = cz0 + len * (i + 0.5) / 3
			hollywoodMirror(K, wallL(R, zc, 5.25, 0.08), 3.4, 2.9, bulbs)
		end
		-- 거울 조명 (가운데 거울 앞 PointLight 2)
		do
			local a = K:box("PowderLightA", V3(0.1, 0.1, 0.1), at(R, x0 + 1.4, cz0 + len / 6, 0, 6.9), lk(BLACK, nil, { t = 1 }))
			local b = K:box("PowderLightB", V3(0.1, 0.1, 0.1), at(R, x0 + 1.4, cz0 + len * 5 / 6, 0, 6.9), lk(BLACK, nil, { t = 1 }))
			local l1 = K:light(a, "PointLight", { Range = 9, Brightness = 0.9, Color = rgb(255, 214, 180) })
			local l2 = K:light(b, "PointLight", { Range = 9, Brightness = 0.9, Color = rgb(255, 214, 180) })
			if l1 then
				table.insert(mirrorLights, l1)
			end
			if l2 then
				table.insert(mirrorLights, l2)
			end
		end
		-- 카운터 위: 어메니티 트레이 · 화장솜 · 면봉 · 티슈 · 꽃 · 향수 · 헤어 드라이어 거치대
		local topY = 2.58
		for i = 0, 2 do
			local zc = cz0 + len * (i + 0.5) / 3
			local tcf = at(R, x0 + 0.55, zc + 1.0, 0, topY)
			K:box("AmenityTray", V3(0.6, 0.06, 1.1), tcf * CF(0, 0.03, 0), lk(rgb(200, 170, 110), M.Metal))
			K:vcyl("AmenityJar", 0.45, 0.32, tcf * CF(0, 0.29, -0.3), gl(rgb(240, 240, 240), 0.4))
			K:vcyl("AmenityCotton", 0.3, 0.26, tcf * CF(0, 0.23, -0.3), Look.white)
			K:vcyl("AmenityBottle", 0.6, 0.18, tcf * CF(0.05, 0.36, 0.05), lk(rgb(250, 230, 240)))
			K:vcyl("AmenityPump", 0.12, 0.06, tcf * CF(0.05, 0.72, 0.05), Look.chrome)
			K:vcyl("AmenityBottle", 0.5, 0.18, tcf * CF(-0.1, 0.31, 0.35), lk(rgb(60, 50, 70)))
			if i == 1 then
				-- 향수 (상호작용) + 뿌림 안개
				amenity = K:box("PerfumeBottle", V3(0.3, 0.42, 0.24), at(R, x0 + 0.6, zc - 1.0, 0, topY + 0.21), gl(rgb(255, 200, 220), 0.25))
				K:vcyl("PerfumeCap", 0.16, 0.14, at(R, x0 + 0.6, zc - 1.0, 0, topY + 0.5), Look.goldMetal)
				puff = K:ball("PerfumeMist", 0.5, at(R, x0 + 1.4, zc - 1.0, 0, topY + 1.4), lk(rgb(255, 230, 240), M.Glass, { t = 1 }))
			else
				K:box("TissueBox", V3(0.5, 0.36, 0.8), at(R, x0 + 0.55, zc - 1.0, 0, topY + 0.18), lk(rgb(240, 220, 228)))
				K:box("TissuePuff", V3(0.18, 0.14, 0.3), at(R, x0 + 0.55, zc - 1.0, 0, topY + 0.43), Look.paper)
			end
		end
		do
			-- 꽃병 (카운터 끝)
			local fcf = at(R, x0 + 0.5, cz1 - 0.5, 0, topY)
			K:vcyl("Vase", 0.9, 0.36, fcf * CF(0, 0.45, 0), gl(rgb(230, 240, 236), 0.35))
			for k = 0, 4 do
				local a = k * 2 * PI / 5
				K:seg("FlowerStem", (fcf * CF(0, 0.8, 0)).Position, (fcf * CF(math.cos(a) * 0.28, 1.5 + (k % 2) * 0.2, math.sin(a) * 0.28)).Position, 0.04, Look.leafDark)
				K:ball("FlowerHead", 0.3, fcf * CF(math.cos(a) * 0.3, 1.55 + (k % 2) * 0.2, math.sin(a) * 0.3), lk(if k % 2 == 0 then rgb(255, 150, 190) else rgb(250, 246, 240)))
			end
			-- 헤어 드라이어 벽 거치대
			local hd = wallL(R, cz1 - 1.6, 3.9, 0.08)
			K:plate("DryerHolder", 0.5, 0.6, 0.3, hd, Look.chrome)
			K:cyl("HairDryer", 0.7, 0.36, hd * CF(0, 0.1, 0.5) * ANG(0, PI / 2, 0), lk(rgb(240, 236, 240)))
			K:box("HairDryerGrip", V3(0.18, 0.6, 0.18), hd * CF(0, -0.25, 0.55), lk(rgb(240, 236, 240)))
		end
		-- 벨벳 스툴 3
		for i = 0, 2 do
			local zc = cz0 + len * (i + 0.5) / 3
			local pcf = at(R, x0 + 2.7, zc)
			if placeOr(R, pcf, V3(1.4, 2.1, 1.4), 0, "powder stool") then
				K:disc("PStoolBase", 1.0, 0.06, pcf * CF(0, 0.03, 0), Look.goldMetal)
				K:vcyl("PStoolPole", 1.5, 0.12, pcf * CF(0, 0.8, 0), Look.goldMetal)
				K:ell("PStoolSeat", V3(1.3, 0.5, 1.3), pcf * CF(0, 1.85, 0), lk(rgb(220, 120, 160), M.Fabric))
				K:disc("PStoolPiping", 1.2, 0.06, pcf * CF(0, 1.66, 0), Look.goldMetal)
			end
		end
		-- 전신 거울 (왼벽 z 11..14, LED 테두리)
		do
			local d = wallL(R, 12.6, 3.8, 0.08)
			K:plate("FullMirrorFrame", 2.7, 6.4, 0.08, d, Look.goldMetal)
			K:plate("FullMirror", 2.4, 6.1, 0.1, d, MIRROR)
			for _, sx in { -1, 1 } do
				K:plate("FullMirrorLED", 0.07, 6.0, 0.11, d * CF(sx * 1.3, 0, 0), nl(ACC2))
			end
		end
		-- 라운지 코너 (앞벽 왼쪽): 러브시트 + 사이드 테이블 램프 + 화분 + 액자 ---------------------------------
		do
			local sx0, sx1 = -8.0, -3.8
			local scx = (sx0 + sx1) / 2
			local pcf = at(R, scx, z1 - 1.35, PI)
			if placeOr(R, pcf, V3(sx1 - sx0, 3.8, 2.2), 0, "loveseat") then
				local velvet = lk(rgb(200, 90, 140), M.Fabric)
				K:box("LoveseatPlinth", V3(sx1 - sx0 - 0.4, 0.3, 1.8), pcf * CF(0, 0.15, 0), Look.goldMetal)
				K:rbox("LoveseatSeat", V3(sx1 - sx0 - 0.3, 0.7, 2.0), 0.2, pcf * CF(0, 0.65, 0.05), velvet)
				K:rbox("LoveseatBack", V3(sx1 - sx0 - 0.3, 2.0, 0.6), 0.25, pcf * CF(0, 1.9, -0.75), velvet)
				for _, ax in { -1, 1 } do
					K:rbox("LoveseatArm", V3(0.5, 1.4, 2.1), 0.2, pcf * CF(ax * ((sx1 - sx0) / 2 - 0.1), 1.0, 0), velvet)
				end
				for k = -1, 1, 2 do
					K:ell("LoveseatPillow", V3(1.0, 0.9, 0.3), pcf * CF(k * 0.8, 1.6, -0.35) * ANG(math.rad(-12), 0, 0), lk(rgb(250, 230, 236), M.Fabric))
				end
			end
			local tcf = at(R, x0 + 0.85, z1 - 1.35)
			if placeOr(R, tcf, V3(1.2, 3.2, 1.2), 0, "side table") then
				K:disc("SideTableBase", 0.8, 0.06, tcf * CF(0, 0.03, 0), Look.goldMetal)
				K:vcyl("SideTablePole", 1.8, 0.1, tcf * CF(0, 0.95, 0), Look.goldMetal)
				K:disc("SideTableTop", 1.1, 0.08, tcf * CF(0, 1.9, 0), lk(rgb(236, 230, 226), M.Marble))
				K:vcyl("LampBase", 0.5, 0.3, tcf * CF(0, 2.19, 0), Look.goldMetal)
				local shade = K:vcyl("LampShade", 0.5, 0.7, tcf * CF(0, 2.75, 0), lk(rgb(255, 226, 200), M.Neon, { t = 0.15 }))
				K:light(shade, "PointLight", { Range = 8, Brightness = 0.7, Color = rgb(255, 200, 170) })
			end
			plant(K, R, -2.85, z1 - 1.3, "snake", 4.6, 1.2, lk(rgb(240, 236, 230), M.Concrete))
			-- 러브시트 위 액자 (핑크 추상화)
			artFrame(K, wallF(R, scx, 6.2, 0), 4.0, 2.6, {
				{ rgb(250, 232, 236), 0, 0, 1, 1 }, { rgb(255, 150, 190), 0.1, 0.15, 0.45, 0.6 }, { rgb(230, 90, 140), 0.45, 0.35, 0.4, 0.5 }, { rgb(255, 214, 120), 0.62, 0.12, 0.2, 0.2 }, { rgb(40, 30, 40), 0.2, 0.82, 0.6, 0.03 },
			}, Look.goldMetal, lk(rgb(250, 244, 240)))
			-- 맵의 '오늘도 예뻐 ♡' 판은 문 위 빈 공간까지 걸쳐 떠 있고 액자와 겹쳐서 → 숨기고 문 왼쪽 벽 위에 네온 글씨로
			for _, r in V.byName["Sign_오늘도 예뻐 ♡"] or {} do
				safeHide(K, r)
			end
			K:free(function()
				local nd = wallF(R, -5.0, 8.95, 0)
				K:plate("PrettyNeonBacker", 7.8, 1.5, 0.05, nd, lk(rgb(20, 14, 20), M.SmoothPlastic, { t = 0.4 }))
				txt(K, "PrettyNeon", 7.4, 1.25, nd * CF(0, 0, 0.07), "오늘도 예뻐 ♡", rgb(255, 120, 200), nil, F.GothamBlack, 2.4)
				K:plate("PrettyNeonLine", 7.0, 0.06, 0.08, nd * CF(0, -0.72, 0), nl(ACC))
			end)
		end
		-- 샹들리에 (가운데) + 바닥 대리석 메달리온 --------------------------------------------------------------
		do
			local cx, cz = 1.6, 2.4
			K:free(function()
				local top = ap(R, cx, H, cz)
				K:disc("ChandCanopy", 0.9, 0.12, at(R, cx, cz, 0, H - 0.06), Look.goldMetal)
				K:seg("ChandRod", top - V3(0, 0.1, 0), ap(R, cx, 8.4, cz), 0.08, Look.goldMetal)
				for k = 0, 3 do
					local a = k * PI / 2 + PI / 4
					K:seg("ChandWire", ap(R, cx, 8.4, cz), ap(R, cx + math.cos(a) * 1.7, 7.9, cz + math.sin(a) * 1.7), 0.03, Look.goldMetal)
				end
				K:ring("ChandRingOuter", at(R, cx, cz, 0, 7.9) * ANG(PI / 2, 0, 0), 1.75, 0.14, 20, nl(ACC2))
				K:ring("ChandRingInner", at(R, cx, cz, 0, 7.55) * ANG(PI / 2, 0, 0), 1.05, 0.1, 14, Look.goldMetal)
				for k = 0, (if hi(K) then 13 else 7) do
					local a = k * 2 * PI / (if hi(K) then 14 else 8)
					local r = if k % 2 == 0 then 1.75 else 1.05
					local yb = if k % 2 == 0 then 7.9 else 7.55
					local drop = 0.5 + (k % 3) * 0.25
					K:seg("ChandCrystalWire", ap(R, cx + math.cos(a) * r, yb, cz + math.sin(a) * r), ap(R, cx + math.cos(a) * r, yb - drop, cz + math.sin(a) * r), 0.02, Look.chrome)
					K:ell("ChandCrystal", V3(0.18, 0.32, 0.18), at(R, cx + math.cos(a) * r, cz + math.sin(a) * r, 0, yb - drop - 0.12), gl(rgb(255, 240, 250), 0.25))
				end
				local core = K:ball("ChandCore", 0.6, at(R, cx, cz, 0, 7.75), Look.lampWarm)
				K:light(core, "PointLight", { Range = 16, Brightness = 0.9, Color = rgb(255, 196, 210) })
				-- 메달리온
				K:disc("MedallionOuter", 6.2, 0.02, at(R, cx, cz, 0, 0.012), lk(rgb(24, 22, 26), M.Marble))
				K:disc("MedallionRing", 5.4, 0.024, at(R, cx, cz, 0, 0.014), Look.goldMetal)
				K:disc("MedallionInner", 5.1, 0.026, at(R, cx, cz, 0, 0.016), lk(rgb(236, 230, 226), M.Marble))
				K:disc("MedallionCore", 2.2, 0.028, at(R, cx, cz, 0, 0.018), lk(rgb(220, 120, 160), M.Marble))
			end)
		end
		mirrorToggle = bulbs[6]
	else
		-- 남자 화장실 -------------------------------------------------------------------------------------
		cladLeft(-20.5, -10.6)
		cladLeft(8.6, 19.9)
		-- 소변기 위 안내문 (한 걸음 더 가까이)
		K:free(function()
			local d = wallL(R, -1.1, 6.75, 0)
			K:plate("UrinalSignBoard", 15.0, 0.8, 0.04, d, lk(rgb(18, 18, 22)))
			txt(K, "UrinalSign", 14.6, 0.6, d * CF(0, 0, 0.045), "한 걸음 더 가까이 ·  남자가 흘리지 말아야 할 것은 눈물만이 아닙니다", ACC2, nil, F.GothamBold, 1.3)
			K:plate("UrinalSignLED", 15.0, 0.05, 0.08, d * CF(0, -0.45, 0), nl(ACC))
		end)
		-- 가림벽 (입구에서 소변기가 안 보이게) + 그루밍 카운터 ---------------------------------------------------
		local px0, px1 = x0, -4.6
		local pz = 12.2
		K:free(function()
			local pc = at(R, (px0 + px1) / 2, pz + 0.25)
			K:box("PrivacyWall", V3(px1 - px0, 7.4, 0.5), pc * CF(0, 3.7, 0), tileL)
			K:box("PrivacyCap", V3(px1 - px0 + 0.04, 0.12, 0.6), pc * CF(0, 7.46, 0), Look.brushed)
			K:box("PrivacyLED", V3(0.06, 7.2, 0.06), pc * CF((px1 - px0) / 2 + 0.02, 3.7, 0), nl(ACC))
			K:box("PrivacyBase", V3(px1 - px0, 0.3, 0.56), pc * CF(0, 0.15, 0), Look.black)
		end)
		-- 가림벽 뒤 (소변기 쪽): 행사 포스터 광고판
		do
			local d = face(R, (px0 + px1) / 2, 5.2, pz - 0.02, PI)
			K:plate("AdFrame", 3.4, 4.4, 0.06, d, Look.alu)
			K:plate("AdFace", 3.2, 4.2, 0.08, d, lk(rgb(30, 14, 50), M.Neon, { t = 0.3 }))
			txt(K, "AdTitle", 3.0, 1.2, d * CF(0, 1.1, 0.09), "SAT\nSEAN WAVE", WHITE, nil, F.GothamBlack, 1.4)
			txt(K, "AdSub", 3.0, 1.2, d * CF(0, -0.9, 0.09), "K-EDM 23:30\n입장 30,000원\nROOM 2 HIP-HOP OPEN", rgb(255, 200, 120), nil, F.GothamBold, 1.2)
		end
		-- 그루밍 카운터 (가림벽 앞 +z 쪽, 서서 쓰는 높이 3.4)
		local gz = pz + 0.5
		do
			local gcx = (px0 + px1) / 2
			local glen = px1 - px0 - 0.6
			local gb = at(R, gcx, gz + 0.85)
			K:free(function()
				K:box("GroomBody", V3(glen, 3.1, 1.6), gb * CF(0, 0.2 + 1.55, 0), lk(rgb(30, 26, 24), M.Wood))
				K:box("GroomPlinth", V3(glen - 0.2, 0.2, 1.4), gb * CF(0, 0.1, -0.05), Look.black)
				K:box("GroomTop", V3(glen + 0.2, 0.16, 1.8), gb * CF(0, 3.38, 0.05), marbleD)
				K:box("GroomUnderLED", V3(glen - 0.3, 0.05, 0.05), gb * CF(0, 3.24, 0.92), nl(ACC))
				for i = -1, 1 do
					K:box("GroomFlute", V3(0.06, 2.8, 0.04), gb * CF(i * glen / 3, 1.7, 0.81), lk(rgb(20, 18, 16), M.Wood))
				end
			end)
			-- 거울 (가림벽 앞면) + 둥근 LED 후광
			local md = face(R, gcx, 5.4, pz + 0.5, 0)
			K:plate("GroomMirror", glen - 0.4, 3.0, 0.05, md, MIRROR)
			local halo = K:plate("GroomHalo", glen - 0.2, 0.07, 0.06, md * CF(0, 1.56, 0), nl(ACC2))
			K:plate("GroomHalo", glen - 0.2, 0.07, 0.06, md * CF(0, -1.56, 0), nl(ACC2))
			table.insert(bulbs, halo)
			local lp = K:box("GroomLight", V3(0.1, 0.1, 0.1), at(R, gcx, gz + 2.4, 0, 6.6), lk(BLACK, nil, { t = 1 }))
			local l1 = K:light(lp, "PointLight", { Range = 9, Brightness = 0.9, Color = rgb(220, 236, 255) })
			if l1 then
				table.insert(mirrorLights, l1)
			end
			mirrorToggle = halo
			-- 카운터 위 소품: 왁스 · 빗 · 구강청결제 + 종이컵 · 면봉 · 티슈 · 로션
			local topY = 3.46
			local tcf = at(R, gcx, gz + 0.85, 0, topY)
			K:box("GroomTray", V3(2.2, 0.05, 0.8), tcf * CF(-1.0, 0.025, -0.2), lk(rgb(40, 40, 44), M.Metal))
			for k = 0, 2 do
				K:vcyl("HairWax", 0.22, 0.4, tcf * CF(-1.7 + k * 0.5, 0.16, -0.2), lk(if k == 1 then rgb(30, 30, 34) else rgb(200, 200, 204), M.Metal))
			end
			K:vcyl("CombCup", 0.6, 0.3, tcf * CF(-0.4, 0.33, -0.25), gl(rgb(220, 230, 236), 0.4))
			for k = -1, 1 do
				K:box("Comb", V3(0.05, 0.6, 0.12), tcf * CF(-0.4 + k * 0.06, 0.62, -0.25) * ANG(0, 0, k * 0.15), Look.black)
			end
			-- 구강청결제 디스펜서 (상호작용)
			amenity = K:box("MouthwashBody", V3(0.5, 1.0, 0.5), tcf * CF(0.6, 0.5, -0.3), lk(rgb(240, 240, 244)))
			K:box("MouthwashTank", V3(0.4, 0.5, 0.42), tcf * CF(0.6, 0.75, -0.28), lk(rgb(60, 160, 220), M.Glass, { t = 0.3 }))
			K:box("MouthwashButton", V3(0.3, 0.12, 0.1), tcf * CF(0.6, 0.35, -0.03), Look.chrome)
			txt(K, "MouthwashLabel", 0.46, 0.14, tcf * CF(0.6, 0.15, -0.045), "가그린", rgb(30, 90, 160), nil, F.GothamBold)
			mouthCup = K:vcyl("MouthwashCup", 0.3, 0.24, tcf * CF(0.6, 0.15, 0.15), lk(rgb(80, 170, 230), M.Glass, { t = 1 }))
			K:vcyl("CupStack", 0.7, 0.26, tcf * CF(1.1, 0.35, -0.3), Look.paper)
			K:vcyl("SwabJar", 0.45, 0.3, tcf * CF(1.55, 0.23, -0.3), gl(rgb(236, 240, 240), 0.4))
			K:box("TissueBox", V3(0.8, 0.36, 0.5), tcf * CF(-1.5, 0.18, 0.35), lk(rgb(40, 44, 54)))
			K:box("TissuePuff", V3(0.3, 0.14, 0.18), tcf * CF(-1.5, 0.43, 0.35), Look.paper)
			K:vcyl("LotionPump", 0.55, 0.2, tcf * CF(1.9, 0.28, 0.25), lk(rgb(30, 34, 40)))
			K:vcyl("LotionNozzle", 0.1, 0.06, tcf * CF(1.9, 0.6, 0.25), Look.chrome)
		end
		-- 청소도구함 문 (왼벽 안쪽 모서리) + 청소 카트 ------------------------------------------------------
		do
			local d = wallL(R, -18.0, 3.6, 0)
			K:plate("JanitorDoorFrame", 3.4, 7.4, 0.1, d, Look.brushed)
			K:plate("JanitorDoor", 3.1, 7.1, 0.14, d * CF(0, -0.05, 0), lk(rgb(40, 40, 46)))
			K:plate("JanitorDoorHandle", 0.12, 0.7, 0.2, d * CF(-1.2, -0.3, 0), Look.chrome)
			txt(K, "JanitorDoorSign", 2.2, 0.5, d * CF(0, 1.6, 0.15), "STAFF ONLY · 청소도구함", WHITE, rgb(20, 20, 24), F.GothamBold)
			local pcf = at(R, -7.6, z0 + 1.1, 0)
			if placeOr(R, pcf, V3(3.6, 4.2, 2.0), 0, "cleaning cart") then
				local grey = lk(rgb(120, 124, 130))
				K:box("CartShelfLow", V3(3.0, 0.1, 1.6), pcf * CF(0, 0.6, 0), grey)
				K:box("CartShelfTop", V3(3.0, 0.1, 1.6), pcf * CF(0, 3.2, 0), grey)
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						K:vcyl("CartPost", 2.7, 0.12, pcf * CF(sx * 1.42, 1.9, sz * 0.72), grey)
						K:disc("CartWheel", 0.35, 0.12, pcf * CF(sx * 1.3, 0.18, sz * 0.62) * ANG(0, 0, PI / 2), Look.black)
					end
				end
				K:vcyl("MopBucket", 1.0, 1.0, pcf * CF(-0.75, 1.15, 0), lk(rgb(240, 200, 30)))
				K:box("MopWringer", V3(0.9, 0.4, 0.5), pcf * CF(-0.75, 1.8, 0), lk(rgb(240, 200, 30)))
				K:seg("MopHandle", ap(R, -8.35, 0.8, z0 + 1.1), ap(R, -8.9, 4.4, z0 + 1.3), 0.1, lk(rgb(30, 120, 210)))
				K:box("TrashBag", V3(1.0, 1.8, 1.2), pcf * CF(0.9, 1.6, 0), lk(rgb(20, 20, 22), M.Plastic))
				K:vcyl("SprayBottle", 0.6, 0.22, pcf * CF(-0.9, 3.55, -0.3), lk(rgb(60, 140, 220), M.Plastic))
				K:vcyl("SprayBottle", 0.6, 0.22, pcf * CF(-0.5, 3.55, -0.3), lk(rgb(90, 200, 90), M.Plastic))
				for k = 0, 3 do
					K:cyl("SpareRoll", 0.42, 0.42, pcf * CF(0.3 + (k % 2) * 0.45, 3.46 + math.floor(k / 2) * 0.42, 0.25), Look.paper)
				end
				-- 접힌 '청소 중' 표지판 (카트 옆에 기대 놓음)
				local sd = at(R, -5.3, z0 + 0.6, 0, 1.3) * ANG(math.rad(-8), 0, 0)
				K:box("WetSign", V3(1.1, 2.6, 0.12), sd, lk(rgb(250, 210, 30), M.Plastic))
				txt(K, "WetSignText", 1.0, 1.4, sd * CF(0, 0.2, 0.065), "청소 중\n⚠\n미끄럼 주의", BLACK, nil, F.GothamBlack)
			end
		end
		-- 배플 천장 (가운데: 검은 루버 + 파란 LED)
		K:free(function()
			for i = 0, 5 do
				local z = -5.5 + i * 2.6
				K:box("CeilBaffle", V3(9.0, 0.7, 0.35), at(R, -1.8, z, 0, H - 0.4), lk(rgb(22, 22, 26), M.Wood))
				local led = K:box("CeilBaffleLED", V3(8.8, 0.04, 0.12), at(R, -1.8, z, 0, H - 0.77), nl(ACC2))
				if i == 2 then
					K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 12, Brightness = 0.8, Angle = 140, Color = rgb(170, 210, 255) })
				end
			end
		end)
	end

	-- 세면대 쪽: 종이타월 + 휴지통 + 안내문 · 세면대 위 티슈 · 꽃 -------------------------------------------
	local towelZ = if female then 15.3 else 15.15
	local sheet, lever = towelDispenser(K, wallR(R, towelZ, 5.0, 0))
	txt(K, "TowelNotice", 1.6, 0.42, wallR(R, towelZ, 6.25, 0.02), "손 닦은 휴지는 휴지통에", rgb(40, 40, 46), rgb(246, 246, 242), F.GothamBold)
	do
		local pcf = at(R, x1 - 0.55, towelZ)
		K:free(function()
			trashCan(K, pcf, 2.4, 0.95, nil, Look.steel)
		end)
	end
	K:box("VanityTissue", V3(0.5, 0.34, 0.8), at(R, x1 - 0.6, 2.9, 0, 3.37), lk(rgb(30, 30, 34)))
	K:box("VanityTissuePuff", V3(0.18, 0.12, 0.28), at(R, x1 - 0.6, 2.9, 0, 3.6), Look.paper)
	K:vcyl("VanityBudVase", 0.6, 0.22, at(R, x1 - 0.55, 8.9, 0, 3.5), gl(rgb(230, 240, 236), 0.3))
	K:seg("VanityBudStem", ap(R, x1 - 0.55, 3.6, 8.9), ap(R, x1 - 0.6, 4.4, 8.85), 0.04, Look.leafDark)
	K:ball("VanityBud", 0.26, at(R, x1 - 0.6, 8.85, 0, 4.45), lk(ACC2))
	-- 입구 안쪽 안내 (앞벽 안쪽, 문 오른쪽): 금연 · 불법촬영 점검 · 청소 점검표 --------------------------------
	do
		local ux = doorX1 + 1.4
		noSmoking(K, wallF(R, ux, 5.8, 0), 0.9, "흡연 금지")
		local sd = wallF(R, ux, 4.2, 0)
		K:plate("SafeSticker", 1.3, 0.9, 0.02, sd, lk(rgb(30, 90, 190)))
		txt(K, "SafeStickerText", 1.2, 0.8, sd * CF(0, 0, 0.025), "불법촬영\n점검 완료 ✓\n수영구청 2026.10", WHITE, nil, F.GothamBold)
		local cd = wallF(R, ux + 1.8, 4.9, 0)
		K:plate("ChecklistClip", 1.3, 1.8, 0.04, cd, lk(rgb(120, 86, 50), M.Wood))
		K:plate("ChecklistPaper", 1.15, 1.5, 0.05, cd * CF(0, -0.1, 0), Look.paper)
		K:plate("ChecklistClamp", 0.6, 0.16, 0.08, cd * CF(0, 0.82, 0), Look.chrome)
		txt(K, "ChecklistText", 1.05, 1.36, cd * CF(0, -0.12, 0.055), "청소 점검표\n20:00 ✓ 김\n22:00 ✓ 김\n00:00 ✓ 박\n02:00 ✓ 박\n04:00", rgb(40, 40, 60), nil, F.GothamMedium)
	end
	-- 작은 벽 설비: 손 소독제 · 방향제 (+ 여: 생리대 무료 디스펜서, 남: 소변기 센서 · 탈취 패드 · 앞벽 네온) --------------
	K:free(function()
		local sd = wallF(R, if female then 8.4 else 8.0, 3.7, 0)
		K:plate("SanitizerBack", 0.5, 0.9, 0.06, sd, Look.white)
		K:plate("SanitizerBody", 0.42, 0.6, 0.3, sd * CF(0, 0.05, 0.06), lk(rgb(240, 240, 244)))
		K:plate("SanitizerWindow", 0.2, 0.25, 0.32, sd * CF(0, 0.12, 0.06), lk(rgb(120, 200, 230), M.Glass, { t = 0.2 }))
		K:plate("SanitizerNozzle", 0.12, 0.08, 0.36, sd * CF(0, -0.27, 0.06), Look.chrome)
		txt(K, "SanitizerLabel", 0.5, 0.18, sd * CF(0, -0.6, 0.02), "손 소독제", rgb(30, 90, 160), Look.white.c, F.GothamBold)
		local ad = wallR(R, -10.8, 7.6, 0)
		K:plate("AirFreshener", 0.6, 0.8, 0.28, ad, lk(rgb(244, 244, 240)))
		wdisc(K, "AirFreshenerLED", 0.08, 0.02, ad * CF(0.18, 0.26, 0.28), nl(rgb(60, 230, 120)))
		K:plate("AirFreshenerGrill", 0.4, 0.12, 0.29, ad * CF(0, -0.2, 0), lk(rgb(180, 180, 184)))
		if female then
			local pd = wallF(R, 8.6, 5.6, 0)
			K:plate("PadDispenser", 1.1, 1.5, 0.4, pd, lk(rgb(250, 236, 242)))
			K:plate("PadDispenserHead", 1.1, 0.4, 0.42, pd * CF(0, 0.55, 0), lk(rgb(230, 120, 160)))
			txt(K, "PadDispenserText", 1.0, 0.32, pd * CF(0, 0.55, 0.43), "생리대 무료", WHITE, nil, F.GothamBlack)
			K:plate("PadDispenserSlot", 0.6, 0.1, 0.43, pd * CF(0, -0.45, 0), Look.black)
			txt(K, "PadDispenserSub", 1.0, 0.36, pd * CF(0, 0.0, 0.43), "FREE · 1인 1개\n버튼을 누르세요", rgb(120, 60, 80), nil, F.GothamMedium)
		else
			-- 소변기마다 센서 + 탈취 패드
			for _, z in { -8.6, -3.6, 1.4, 6.4 } do
				local sd2 = wallL(R, z, 4.85, 0)
				K:plate("UrinalSensor", 0.6, 0.36, 0.12, sd2, lk(rgb(232, 232, 236)))
				wdisc(K, "UrinalSensorEye", 0.14, 0.02, sd2 * CF(0, 0, 0.12), lk(rgb(30, 30, 34), M.Glass))
				wdisc(K, "UrinalSensorLED", 0.05, 0.02, sd2 * CF(0.2, 0.08, 0.12), nl(rgb(255, 40, 40)))
			end
			-- 소변기 위 폰 · 잔 선반 (클럽 화장실 필수)
			for ui, uz in { -8.6, -3.6, 1.4, 6.4 } do
				local ld = wallL(R, uz, 4.6, 0)
				K:box("UrinalLedge", V3(3.8, 0.1, 0.55), ld * CF(0, 0, 0.275), lk(rgb(26, 24, 30), M.Marble))
				K:box("UrinalLedgeLED", V3(3.7, 0.03, 0.04), ld * CF(0, -0.07, 0.53), nl(ACC))
				if ui == 2 then
					K:box("LedgePhone", V3(0.4, 0.04, 0.22), ld * CF(-1.2, 0.07, 0.3) * ANG(0, 0.2, 0), lk(rgb(20, 20, 24)))
				elseif ui == 3 then
					K:vcyl("LedgeCup", 0.5, 0.3, ld * CF(1.2, 0.3, 0.3), gl(rgb(230, 236, 240), 0.5))
					K:vcyl("LedgeCupDrink", 0.3, 0.26, ld * CF(1.2, 0.2, 0.3), lk(rgb(220, 140, 40), M.Glass, { t = 0.2 }))
				end
			end
			-- 앞벽 왼쪽 (입구 옆): GENTLEMEN 네온 + 사진 2
			local nd = wallF(R, -5.6, 7.6, 0)
			K:plate("GentsNeonBacker", 6.4, 1.3, 0.05, nd, lk(rgb(14, 16, 20)))
			txt(K, "GentsNeon", 6.0, 1.0, nd * CF(0, 0, 0.07), "GENTLEMEN · 남자", ACC2, nil, F.GothamBlack, 2.2)
			artFrame(K, wallF(R, -3.6, 4.6, 0.06), 2.6, 3.0, { { rgb(20, 22, 30), 0, 0, 1, 1 }, { rgb(200, 200, 210), 0.2, 0.15, 0.6, 0.5 }, { rgb(60, 140, 255), 0.0, 0.75, 1, 0.04 } }, Look.blackMetal)
			artFrame(K, wallF(R, -7.6, 4.6, 0.06), 2.6, 3.0, { { rgb(230, 228, 220), 0, 0, 1, 1 }, { rgb(30, 30, 34), 0.3, 0.1, 0.4, 0.7 }, { rgb(200, 40, 50), 0.38, 0.62, 0.24, 0.1 } }, Look.blackMetal)
		end
	end)
	-- 바닥 배수구 2
	floorDrain(K, R, 2.2, -6.6)
	floorDrain(K, R, 3.4, 9.0)
	-- 천장: 다운라이트 · 배기구 · 감지기 · 스프링클러 · 스피커 · 네온 코브 ------------------------------------
	for i, z in { -0.4, 5.6, 11.6 } do
		downlight(K, R, vanX - 0.4, z, { light = i == 2, range = 12, bright = 0.9, angle = 80, glow = Look.lampNeutral, color = rgb(255, 236, 220) })
	end
	-- 칸 앞 코브 (칸 문 · 칸막이를 비춤)
	cove(K, R, (if female then x0 else -4.0) + 0.6, -10.4, x1 - 0.6, -10.4, H - 0.1, rgb(255, 226, 200), 0, 0, false)
	if not female then
		-- 소변기 · 청소 코너 쪽 왼벽 코브
		cove(K, R, x0 + 0.9, z0 + 0.8, x0 + 0.9, 11.6, H - 0.1, rgb(220, 232, 255), 0, 0, false)
	end
	-- 구역 조명 (칸 앞 + 남: 소변기 · 청소 코너)
	local zones = { { if female then 0.0 else 3.0, -10.0, rgb(255, 226, 200) } }
	if not female then
		table.insert(zones, { -6.6, -1.0, rgb(220, 232, 255) })
		table.insert(zones, { -7.0, -16.5, rgb(255, 236, 214) })
	end
	for _, zl in zones do
		local a = K:box("WCZoneLight", V3(0.1, 0.1, 0.1), at(R, zl[1], zl[2], 0, H - 1.6), lk(BLACK, nil, { t = 1 }))
		K:light(a, "PointLight", { Range = 12, Brightness = 0.8, Color = zl[3] })
	end
	for _, s in stalls do
		downlight(K, R, (s[1] + s[2]) / 2, z0 + 4.0, { light = (s[1] > 0 and s[2] > 6), range = 11, bright = 0.7 })
	end
	if female then
		for _, z in { -4.3, 1.0, 6.3 } do
			downlight(K, R, x0 + 2.6, z, {})
		end
	else
		for _, z in { -8.6, -3.6, 1.4, 6.4 } do
			downlight(K, R, x0 + 2.4, z, {})
		end
	end
	vent(K, R, if female then 2.0 else 3.6, 14.4, 1.6)
	vent(K, R, if female then -5.0 else 2.4, -8.0, 1.6)
	smoke(K, R, if female then -4.5 else 4.0, if female then 12.0 else -6.0)
	sprinkler(K, R, -3.0, -2.0)
	sprinkler(K, R, 4.6, 6.0)
	sprinkler(K, R, -3.0, 14.5)
	ceilSpeaker(K, R, if female then -4.5 else 4.4, if female then -2.5 else 4.0)
	K:free(function()
		-- 천장 가장자리 네온 코브 (왼벽 · 앞벽)
		K:box("CoveLEDLeft", V3(0.08, 0.08, (z1 - z0) - 1.0), at(R, x0 + 0.08, R.cz, 0, H - 0.25), nl(ACC))
		K:box("CoveLEDFront", V3((x1 - x0) - 1.0, 0.08, 0.08), at(R, R.cx, z1 - 0.08, 0, H - 0.25), nl(ACC))
	end)

	-- 상호작용 ---------------------------------------------------------------------------------------
	-- 1) 거울 조명 켜기/끄기
	if mirrorToggle then
		local cols = {}
		for _, b in bulbs do
			cols[b] = b.Color
		end
		prompt(R, mirrorToggle, "toggle", {
			object = if female then "할리우드 거울 조명" else "그루밍 거울 조명",
			onText = "거울 조명 끄기",
			offText = "거울 조명 켜기",
			state = true,
			on = function(s: boolean)
				for _, b in bulbs do
					if b.Parent then
						b.Material = if s then M.Neon else M.SmoothPlastic
						b.Color = if s then cols[b] else (cols[b] :: Color3):Lerp(rgb(120, 120, 120), 0.6)
					end
				end
				for _, l in mirrorLights do
					l.Enabled = s
				end
			end,
		})
	end
	-- 2) 종이타월 뽑기
	do
		local busy = false
		local c0 = sheet.CFrame
		prompt(R, lever, "prompt", {
			action = "종이타월 뽑기",
			object = "페이퍼 타월",
			fn = function()
				if busy then
					return
				end
				busy = true
				sheet.Transparency = 0
				sheet.CFrame = c0 * CF(0, 0.3, 0)
				tween(sheet, { CFrame = c0 }, 0.35)
				task.delay(3, function()
					sheet.Transparency = 1
					busy = false
				end)
			end,
		})
	end
	-- 3) 향수 뿌리기 (여) / 구강청결제 (남)
	if female and amenity and puff then
		local mist = puff :: BasePart
		local s0 = mist.Size
		prompt(R, amenity, "prompt", {
			action = "향수 뿌리기",
			object = "파우더룸 향수",
			fn = function()
				mist.Transparency = 0.55
				mist.Size = s0
				tween(mist, { Size = s0 * 3.2, Transparency = 1 }, 1.6)
			end,
		})
	elseif amenity and mouthCup then
		local cup = mouthCup :: BasePart
		prompt(R, amenity, "prompt", {
			action = "가글 받기",
			object = "구강청결제",
			fn = function()
				cup.Transparency = 0.2
				task.delay(4, function()
					cup.Transparency = 1
				end)
			end,
		})
	end
end

--=====================================================================================================
-- ROOM 2 · HIP-HOP (hiphop) --------------------------------------------------------------------------
--=====================================================================================================
-- 그라피티 한 점: dcf 가운데, w x h. pal = { fill, edge, out, hl, bg = { ... } }, o = { tags, crown, arrow, sub }
local function graffiti(K: any, dcf: CFrame, w: number, h: number, word: string, pal: any, seed: number, o: any?)
	local op: any = o or {}
	local z = 0.02
	-- 1) 바탕 스프레이 구름 (겹친 타원)
	if op.base ~= false then
		K:plate("GraffitiBase", w * 0.98, h * 0.9, 0.02, dcf, lk(pal.base or dk(pal.bg[1], 0.55)))
	end
	for i = 1, (if lowD(K) then 3 else 6) do
		local cw = w * (0.3 + 0.32 * rnd(seed, i))
		local ch = h * (0.42 + 0.36 * rnd(seed, i + 10))
		local cx = (rnd(seed, i + 20) - 0.5) * w * 0.66
		local cy = (rnd(seed, i + 30) - 0.5) * h * 0.4
		K:ell("SprayCloud", V3(cw, ch, 0.02), dcf * CF(cx, cy, z + 0.01 + i * 0.003), lk(pal.bg[(i % #pal.bg) + 1]))
	end
	-- 2) 글자: 그림자 (3D 블록) + 흰 외곽 + 채움
	local tw, th = w * 0.92, h * (op.wordH or 0.56)
	local ty = op.wordY or h * 0.04
	local far = { maxDist = 150, d = 0.01 }
	txt(K, "GraffitiShadow", tw, th, dcf * CF(0.22, ty - 0.24, 0.05), word, pal.out, nil, F.LuckiestGuy, nil, far)
	txt(K, "GraffitiOutline", tw * 1.04, th * 1.06, dcf * CF(0, ty, 0.085), word, pal.edge or WHITE, nil, F.LuckiestGuy, 0.9, far)
	txt(K, "GraffitiFill", tw, th, dcf * CF(0, ty, 0.12), word, pal.fill, nil, F.LuckiestGuy, op.glow or 1.15, far)
	-- 3) 흘러내림 (드립)
	local nd = if lowD(K) then 3 else 7
	for i = 1, nd do
		local x = (rnd(seed, i + 40) - 0.5) * tw * 0.86
		local len = h * (0.1 + 0.22 * rnd(seed, i + 50))
		local y0 = ty - th * 0.36
		K:plate("GraffitiDrip", 0.1, len, 0.02, dcf * CF(x, y0 - len / 2, 0.1), nl(dk(pal.fill, 0.25)))
		K:ell("GraffitiDripEnd", V3(0.17, 0.22, 0.05), dcf * CF(x, y0 - len, 0.11), nl(dk(pal.fill, 0.25)))
	end
	-- 4) 반짝이 (하이라이트 획 + 4각 별)
	for i = 1, 3 do
		local x = (rnd(seed, i + 60) - 0.5) * tw * 0.8
		K:plate("GraffitiShine", 0.55, 0.09, 0.02, dcf * CF(x, ty + th * 0.18, 0.14) * ANG(0, 0, 0.45), nl(pal.hl or WHITE))
	end
	for i = 1, (if lowD(K) then 1 else 3) do
		local x = (rnd(seed, i + 70) - 0.5) * w * 0.9
		local y = (rnd(seed, i + 80) - 0.2) * h * 0.5
		local s = 0.35 + rnd(seed, i + 90) * 0.4
		K:plate("GraffitiStar", s, 0.08, 0.02, dcf * CF(x, y, 0.14), nl(WHITE))
		K:plate("GraffitiStar", 0.08, s, 0.02, dcf * CF(x, y, 0.14), nl(WHITE))
	end
	-- 5) 태그 (작은 손글씨)
	for i, t in op.tags or {} do
		local x = (rnd(seed, i + 100) - 0.5) * w * 0.8
		local y = -h * 0.36 + (rnd(seed, i + 110) - 0.5) * h * 0.14
		local c = ({ WHITE, rgb(255, 230, 60), rgb(60, 230, 255), rgb(255, 90, 180), rgb(140, 255, 120) })[(i + seed) % 5 + 1]
		txt(K, "GraffitiTag", w * 0.28, h * 0.13, dcf * CF(x, y, 0.15) * ANG(0, 0, (rnd(seed, i + 120) - 0.5) * 0.3), t, c, nil, F.PermanentMarker, 1.0, far)
	end
	if op.sub then
		txt(K, "GraffitiSub", w * 0.6, h * 0.14, dcf * CF(w * 0.12, ty + th * 0.55, 0.15) * ANG(0, 0, 0.06), op.sub, op.subC or rgb(255, 236, 90), nil, F.PermanentMarker, 1.1, far)
	end
	if op.crown then
		txt(K, "GraffitiCrown", h * 0.36, h * 0.3, dcf * CF(-tw * 0.36, ty + th * 0.52, 0.15) * ANG(0, 0, 0.2), "♛", rgb(255, 214, 60), nil, F.GothamBlack, 1.2, far)
	end
	if op.arrow then
		local a = dcf * CF(tw * 0.38, -h * 0.32, 0.1)
		K:plate("GraffitiArrow", w * 0.18, 0.18, 0.02, a, lk(pal.edge or WHITE))
		K:plate("GraffitiArrowHead", 0.42, 0.42, 0.02, a * CF(w * 0.09 + 0.05, 0, 0.005) * ANG(0, 0, PI / 4), lk(pal.edge or WHITE))
	end
end

local GPAL = {
	pink = { fill = rgb(255, 70, 170), edge = WHITE, out = rgb(30, 8, 40), hl = rgb(255, 220, 240), bg = { rgb(60, 220, 255), rgb(110, 60, 230), rgb(255, 200, 40) } },
	lime = { fill = rgb(150, 255, 60), edge = rgb(20, 20, 24), out = rgb(10, 60, 40), hl = WHITE, bg = { rgb(255, 120, 30), rgb(250, 60, 90), rgb(255, 220, 60) } },
	cyan = { fill = rgb(60, 230, 255), edge = WHITE, out = rgb(10, 20, 60), hl = WHITE, bg = { rgb(255, 60, 140), rgb(255, 170, 40), rgb(120, 60, 255) } },
	gold = { fill = rgb(255, 210, 50), edge = rgb(30, 20, 10), out = rgb(120, 40, 10), hl = WHITE, bg = { rgb(220, 40, 60), rgb(30, 30, 40), rgb(255, 120, 40) } },
	purple = { fill = rgb(170, 90, 255), edge = WHITE, out = rgb(20, 10, 30), hl = rgb(240, 220, 255), bg = { rgb(40, 220, 160), rgb(255, 80, 120), rgb(40, 120, 255) } },
}

-- 와이어 박스 트러스 (두 점 사이, 단면 s): 코드 4 + 지그재그 레이싱
local function truss(K: any, a: Vector3, b: Vector3, s: number, look: any)
	local v = b - a
	local len = v.Magnitude
	local d = v / len
	local up = if math.abs(d.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local x = d:Cross(up).Unit
	local y = x:Cross(d).Unit
	local hs = s / 2
	local corners = { x * hs + y * hs, x * hs - y * hs, -x * hs - y * hs, -x * hs + y * hs }
	for _, c in corners do
		K:seg("TrussChord", a + c, b + c, 0.12, look)
	end
	local n = math.max(2, math.floor(len / s + 0.5))
	for i = 0, n - 1 do
		local p0 = a + d * (len * i / n)
		local p1 = a + d * (len * (i + 1) / n)
		for k = 1, 4 do
			local c0, c1 = corners[k], corners[k % 4 + 1]
			if (i + k) % 2 == 0 then
				K:seg("TrussLace", p0 + c0, p1 + c1, 0.06, look)
			else
				K:seg("TrussLace", p0 + c1, p1 + c0, 0.06, look)
			end
		end
	end
end

local function buildHipHop(K: any, V: any, R: any)
	local H = R.H
	local x0, x1, z0, z1 = R.x0, R.x1, R.z0, R.z1
	local brick = lk(rgb(124, 58, 42), M.Brick)
	local steelT = lk(rgb(40, 40, 44), M.Metal)
	-- 비울 곳
	keepBox(R, -7.0, -5.5, 6.0, 7.5, 8, "cypher")
	keepBox(R, -5.0, 29.5, 4.0, z1, 8.5, "door")
	keepBox(R, -4.5, 7.5, 3.5, 29.5, 6.8, "lane")
	keepBox(R, -12.0, -20.8, 12.0, -7.0, 7, "dancefloor")
	keepBox(R, -12.0, 2.5, -9.0, 27.5, 6.5, "bar front")
	keepBox(R, 11.0, -12.0, 14.8, 33.5, 6.5, "lane")

	-- 납작한 그라피티 판 3장 숨기고 같은 자리에 진짜 벽화 ------------------------------------------------
	local boards = { { "Sign_HIPHOP 4 LIFE", "HIPHOP 4 LIFE", GPAL.pink, { "OCEAN", "KRS", "051" }, "since 2019" }, { "Sign_BUSAN 051", "BUSAN 051", GPAL.cyan, { "광안", "SEOMYEON", "ONE" }, "부산 사나이" }, { "Sign_OCEAN CREW", "OCEAN CREW", GPAL.gold, { "DJ HWN", "B-BOY", "★" }, "all city" } }
	K:free(function()
		for i, b in boards do
			local zc = ({ -5.0, 11.0, 27.0 })[i]
			local rec = V.byName[b[1]] and V.byName[b[1]][1]
			if rec then
				local mn, mx = abox(R, rec)
				zc = (mn.Z + mx.Z) / 2
				safeHide(K, rec)
			end
			local d = wallR(R, zc, 9.0, 0.02)
			graffiti(K, d, 14.0, 5.6, b[2], b[3], 17 + i * 13, { tags = b[4], sub = b[5], crown = i == 3, arrow = i == 2 })
		end
	end)
	-- 벽돌 + 큰 벽화: 뒷벽 양옆 · 앞벽 왼쪽 ------------------------------------------------------------
	K:free(function()
		-- 뒷벽 왼쪽 (x -24.1..-11.4)
		K:plate("BrickVeneer", 12.6, H, 0.1, wallB(R, -17.75, H / 2, 0), brick)
		K:plate("BrickVeneer", 12.9, H, 0.1, wallB(R, 17.95, H / 2, 0), brick)
		graffiti(K, wallB(R, -19.7, 10.4, 0.1), 8.4, 6.2, "KING\nOF 051", GPAL.purple, 91, { crown = true, tags = { "RIP", "BSN" }, wordH = 0.7 })
		graffiti(K, wallB(R, 19.9, 10.4, 0.1), 8.4, 6.2, "CYPHER\nCITY", GPAL.lime, 57, { tags = { "MC", "DJ", "B" }, wordH = 0.7, arrow = true })
		-- 앞벽 왼쪽 (입구 왼쪽)
		K:plate("BrickVeneer", 19.0, H, 0.1, wallF(R, -14.6, H / 2, 0), brick)
		graffiti(K, wallF(R, -14.6, 6.4, 0.1), 17.0, 7.6, "ROOM 2", GPAL.pink, 33, { sub = "HIP-HOP · R&B · TRAP", tags = { "광안리", "OCEAN", "2026", "BBOY" }, crown = true })
	end)

	-- 스티커 · 포스터 벽 (왼쪽 벽돌벽 무대 옆, y 0.6..7.2) ------------------------------------------------------
	local POSTERS = {
		{ "BUSAN\nCYPHER\nVOL.12", rgb(255, 214, 40), rgb(20, 20, 20) },
		{ "051\nBATTLE\nSAT 01:00", rgb(230, 40, 50), WHITE },
		{ "SHOW ME\nTHE\nOCEAN", rgb(30, 30, 34), rgb(255, 214, 40) },
		{ "B-BOY\n1on1\n상금 100만원", rgb(40, 120, 230), WHITE },
		{ "TRAP\nNIGHT\nFRI", rgb(140, 60, 220), WHITE },
		{ "R&B\nSLOW JAM\nSUN", rgb(250, 120, 160), rgb(30, 10, 20) },
		{ "OCEAN\nCREW\nRECRUIT", rgb(240, 240, 232), rgb(20, 20, 20) },
		{ "DJ HWN\nb2b\nSEAN", rgb(255, 120, 30), rgb(20, 20, 20) },
	}
	K:free(function()
		for i, p in POSTERS do
			local col = (i - 1) % 4
			local row = math.floor((i - 1) / 4)
			local zc = -32.6 + col * 3.6 + (rnd(5, i) - 0.5) * 0.4
			local yc = 5.4 - row * 2.95 + (rnd(6, i) - 0.5) * 0.3
			local d = wallL(R, zc, yc, 0.01 + i * 0.004) * ANG(0, 0, (rnd(7, i) - 0.5) * 0.12)
			K:plate("Poster", 2.8, 2.6, 0.02, d, lk(p[2]))
			txt(K, "PosterText", 2.5, 2.2, d * CF(0, 0.05, 0.022), p[1], p[3], nil, if i % 2 == 0 then F.Bangers else F.GothamBlack)
			if hi(K) then
				K:plate("PosterTape", 0.6, 0.18, 0.024, d * CF(-1.1, 1.25, 0.002) * ANG(0, 0, 0.6), lk(rgb(230, 224, 200), nil, { t = 0.2 }))
			end
		end
		-- 스티커 폭탄
		local STK = { "051", "OCEAN", "★", "KRS", "BSN", "♛", "LOVE", "부산", "B-BOY", "WAVE" }
		local SC = { rgb(255, 230, 60), rgb(255, 80, 160), rgb(60, 220, 255), WHITE, rgb(140, 255, 100), rgb(255, 120, 40) }
		for i = 1, (if hi(K) then 22 else 10) do
			local zc = -34.0 + rnd(11, i) * 15.5
			local yc = 0.9 + rnd(12, i) * 6.0
			local w = 0.5 + rnd(13, i) * 0.6
			local d = wallL(R, zc, yc, 0.06) * ANG(0, 0, (rnd(14, i) - 0.5) * 1.2)
			local c = SC[(i % #SC) + 1]
			if i % 3 == 0 then
				K:disc("StickerRound", w, 0.012, d * CF(0, 0, 0.006) * ANG(PI / 2, 0, 0), lk(c))
			else
				K:plate("Sticker", w, w * 0.6, 0.012, d, lk(c))
			end
			if i % 2 == 0 then
				txt(K, "StickerText", w * 0.9, w * 0.45, d * CF(0, 0, 0.014), STK[(i % #STK) + 1], if c == WHITE then BLACK else rgb(20, 20, 24), nil, F.GothamBlack)
			end
		end
	end)

	-- 무대: 스커트 · 가장자리 테이프 · 계단 · 모니터 · 마이크 · 레코드 상자 ----------------------------------------
	local stageY = 2.5
	K:free(function()
		K:plate("StageSkirt", 17.8, 1.9, 0.04, face(R, 0, 1.5, -23.0, 0), lk(rgb(16, 16, 18), M.Fabric))
		txt(K, "StageSkirtText", 9.0, 1.0, face(R, 0, 1.5, -22.96, 0), "ROOM 2 · HIP-HOP", rgb(255, 170, 60), nil, F.GothamBlack, 1.2)
		K:box("StageEdgeTape", V3(18.0, 0.02, 0.12), at(R, 0, -23.08, 0, stageY + 0.01), lk(rgb(240, 240, 236)))
		-- 바닥 경고 띠 (무대 앞 노랑-검정)
		for i = 0, 17 do
			K:box("HazardTape", V3(1.0, 0.012, 0.32), at(R, -8.5 + i, -22.75, 0, 0.006), lk(if i % 2 == 0 then rgb(250, 210, 30) else rgb(20, 20, 20)))
		end
	end)
	-- 옆 계단 (무대 오른쪽)
	do
		local pcf = at(R, 9.9, -32.4, 0)
		if placeOr(R, pcf, V3(1.8, 2.5, 3.0), 0, "stage steps") then
			for i = 0, 2 do
				local hgt = (i + 1) * 0.8
				K:box("StageStep", V3(0.6, hgt, 3.0), at(R, 10.5 - i * 0.6, -32.4, 0, hgt / 2), steelT)
				K:box("StageStepNose", V3(0.08, 0.04, 3.0), at(R, 10.78 - i * 0.6, -32.4, 0, hgt + 0.02), lk(rgb(250, 210, 30)))
			end
			K:seg("StepRailPost", ap(R, 10.6, 0.8, -33.75), ap(R, 10.6, 3.8, -33.75), 0.1, Look.blackMetal)
			K:seg("StepRailPost", ap(R, 9.3, 2.4, -33.75), ap(R, 9.3, 5.4, -33.75), 0.1, Look.blackMetal)
			K:seg("StepRail", ap(R, 10.6, 3.8, -33.75), ap(R, 9.3, 5.4, -33.75), 0.1, Look.blackMetal)
		end
	end
	-- 모니터 스피커 2 (무대 위, DJ 쪽을 봄)
	for _, sx in { -1, 1 } do
		local m = at(R, sx * 6.6, -23.9, 0, stageY)
		K:free(function()
			K:wedge("StageMonitor", V3(1.8, 1.0, 1.3), m * CF(0, 0.5, 0), lk(rgb(22, 22, 24)))
			K:box("StageMonitorGrille", V3(1.6, 0.04, 1.5), m * CF(0, 0.52, -0.02) * ANG(-math.atan2(1.0, 1.3), 0, 0), lk(rgb(40, 40, 44), M.DiamondPlate))
		end)
	end
	-- MC 마이크 스탠드 (상호작용: ON AIR)
	local micLED: BasePart? = nil
	do
		local m = at(R, -4.2, -24.2, 0, stageY)
		K:free(function()
			K:disc("MicBase", 0.9, 0.06, m * CF(0, 0.03, 0), Look.blackMetal)
			K:vcyl("MicPole", 3.0, 0.08, m * CF(0, 1.55, 0), Look.blackMetal)
			K:seg("MicBoom", (m * CF(0, 3.0, 0)).Position, (m * CF(0, 3.5, -0.9)).Position, 0.06, Look.blackMetal)
			K:vcyl("MicBody", 0.5, 0.14, m * CF(0, 3.45, -1.05) * ANG(math.rad(-50), 0, 0), Look.black)
			K:ball("MicGrille", 0.24, m * CF(0, 3.62, -1.22), lk(rgb(150, 150, 156), M.DiamondPlate))
			micLED = K:ball("MicLED", 0.07, m * CF(0.08, 3.4, -1.0), lk(rgb(60, 60, 60)))
		end)
	end
	-- 레코드 상자 (무대 위 DJ 데스크 옆)
	for _, sx in { -1, 1 } do
		local c = at(R, sx * 7.0, -27.6, sx * 0.2, stageY)
		K:free(function()
			for k = 0, 1 do
				local cc = c * CF(0, k * 1.05, 0)
				K:box("CrateBody", V3(1.3, 1.0, 1.3), cc * CF(0, 0.5, 0), lk(if k == 0 then rgb(230, 60, 40) else rgb(30, 110, 200), M.Plastic))
				K:box("CrateHole", V3(1.32, 0.3, 0.7), cc * CF(0, 0.62, 0), lk(rgb(10, 10, 12)))
				for r = 0, 5 do
					K:box("Record", V3(1.05, 1.05, 0.03), cc * CF(0, 0.75, -0.5 + r * 0.18), lk(if r % 3 == 0 then rgb(250, 240, 220) else rgb(16, 16, 18)))
				end
			end
		end)
	end
	-- 무대 앞 트러스 (기둥 2 + 가로) + 고정 파 캔 6 + ON AIR 박스
	local onAir: BasePart? = nil
	do
		local zt = -22.4
		local okL = place(R, at(R, -10.3, zt), V3(1.1, 11.8, 1.1), 0, "truss L")
		local okR = place(R, at(R, 10.3, zt), V3(1.1, 11.8, 1.1), 0, "truss R")
		if okL and okR then
			K:free(function()
				for _, sx in { -1, 1 } do
					K:box("TrussBasePlate", V3(1.4, 0.1, 1.4), at(R, sx * 10.3, zt, 0, 0.05), steelT)
					truss(K, ap(R, sx * 10.3, 0.1, zt), ap(R, sx * 10.3, 11.4, zt), 0.9, steelT)
				end
				truss(K, ap(R, -10.75, 11.4, zt), ap(R, 10.75, 11.4, zt), 0.9, steelT)
				for i = 0, 5 do
					local x = -7.5 + i * 3.0
					local p = at(R, x, zt, 0, 10.7)
					K:box("ParClamp", V3(0.2, 0.3, 0.2), p * CF(0, 0.35, 0), Look.blackMetal)
					K:cyl("ParCan", 0.9, 0.62, p * CF(0, 0, -0.1) * ANG(math.rad(-35), 0, 0) * ANG(0, PI / 2, 0), Look.black)
					K:disc("ParLens", 0.5, 0.03, p * CF(0, -0.27, -0.48) * ANG(math.rad(-35), 0, 0) * ANG(PI / 2, 0, 0), nl(({ rgb(255, 60, 40), rgb(255, 170, 30), rgb(255, 60, 160), rgb(60, 140, 255), rgb(255, 170, 30), rgb(255, 60, 40) })[i + 1]))
				end
				-- 무대 워시 (고정 스포트, 트러스 가운데에서 DJ 데스크로)
				local wash = K:box("StageWashAim", V3(0.1, 0.1, 0.1), at(R, 0, zt, 0, 10.6), lk(BLACK, nil, { t = 1 }))
				wash.CFrame = R.V.cf * CFrame.lookAt(ap(R, 0, 10.6, zt), ap(R, 0, 3.0, -28.0))
				K:light(wash, "SpotLight", { Face = Enum.NormalId.Front, Range = 18, Brightness = 1.4, Angle = 70, Color = rgb(255, 214, 180) })
				local ob = at(R, 0, zt + 0.6, 0, 9.8)
				K:seg("OnAirRod", (ob * CF(-0.9, 0.5, 0)).Position, (ob * CF(-0.9, 1.15, 0)).Position, 0.04, Look.blackMetal)
				K:seg("OnAirRod", (ob * CF(0.9, 0.5, 0)).Position, (ob * CF(0.9, 1.15, 0)).Position, 0.04, Look.blackMetal)
				K:box("OnAirBox", V3(2.6, 1.0, 0.3), ob, Look.black)
				onAir = K:box("OnAirFace", V3(2.4, 0.8, 0.02), ob * CF(0, 0, 0.16), lk(rgb(60, 20, 20)))
				txt(K, "OnAirText", 2.3, 0.7, ob * CF(0, 0, 0.18), "ON AIR", rgb(255, 230, 230), nil, F.GothamBlack, 1.4)
			end)
		end
	end
	-- 크라우드 바리케이드 (무대 앞, 자전거 거치대식 4칸)
	do
		local zb = -21.3
		for i = 0, 3 do
			local xc = -6.75 + i * 4.5
			local pcf = at(R, xc, zb)
			if place(R, pcf, V3(4.4, 3.6, 0.7), 0, "barrier") then
				local alu = Look.alu
				for _, sx in { -1, 1 } do
					K:seg("BarrierPost", ap(R, xc + sx * 2.15, 0.25, zb), ap(R, xc + sx * 2.15, 3.5, zb), 0.12, alu)
					K:box("BarrierFoot", V3(0.1, 0.06, 0.95), pcf * CF(sx * 2.15, 0.03, 0), alu)
				end
				K:seg("BarrierTop", ap(R, xc - 2.15, 3.5, zb), ap(R, xc + 2.15, 3.5, zb), 0.1, alu)
				K:seg("BarrierBottom", ap(R, xc - 2.15, 0.5, zb), ap(R, xc + 2.15, 0.5, zb), 0.08, alu)
				for k = 1, (if hi(K) then 8 else 4) do
					local xx = xc - 2.15 + k * 4.3 / (if hi(K) then 9 else 5)
					K:seg("BarrierBar", ap(R, xx, 0.5, zb), ap(R, xx, 3.5, zb), 0.05, alu)
				end
				if i == 1 or i == 2 then
					txt(K, "BarrierSign", 1.6, 0.5, face(R, xc, 2.6, zb + 0.06, 0), "무대 접근 금지", rgb(255, 230, 60), rgb(20, 20, 20), F.GothamBlack)
				end
			end
		end
	end

	-- 사이퍼 링 둘레 드링크 레일 (대각선 4구간, 통로 4방향 열림) -------------------------------------------------
	do
		local cx, cz, rad = -0.5, 1.0, 10.0
		local wood = lk(rgb(60, 44, 32), M.Wood)
		for _, arc in { { 18, 56 }, { 124, 162 }, { 200, 231 }, { 309, 340 } } do
			local a0, a1 = math.rad(arc[1]), math.rad(arc[2])
			local mid = (a0 + a1) / 2
			local pm = at(R, cx + math.cos(mid) * rad, cz + math.sin(mid) * rad)
			if place(R, pm, V3(2.0, 3.8, 2.0), 0, "rail mid") then
				K.freeDepth += 1
				local n = 5
				for k = 0, n - 1 do
					local t0 = a0 + (a1 - a0) * k / n
					local t1 = a0 + (a1 - a0) * (k + 1) / n
					local pa = ap(R, cx + math.cos(t0) * rad, 3.55, cz + math.sin(t0) * rad)
					local pb = ap(R, cx + math.cos(t1) * rad, 3.55, cz + math.sin(t1) * rad)
					K:bar("RailLedge", pa, pb, 1.0, 0.12, wood)
					K:bar("RailLedgeLED", pa - V3(0, 0.1, 0), pb - V3(0, 0.1, 0), 0.06, 0.04, nl(rgb(255, 150, 40)))
				end
				for _, t in { a0 + 0.05, mid, a1 - 0.05 } do
					local px, pz = cx + math.cos(t) * rad, cz + math.sin(t) * rad
					K:seg("RailPost", ap(R, px, 0.06, pz), ap(R, px, 3.48, pz), 0.14, Look.blackMetal)
					K:disc("RailFoot", 0.7, 0.06, at(R, px, pz, 0, 0.03), Look.blackMetal)
				end
				-- 발 받침 링 (바 레일 느낌)
				local fa = ap(R, cx + math.cos(a0 + 0.05) * (rad + 0.2), 0.7, cz + math.sin(a0 + 0.05) * (rad + 0.2))
				local fb = ap(R, cx + math.cos(a1 - 0.05) * (rad + 0.2), 0.7, cz + math.sin(a1 - 0.05) * (rad + 0.2))
				K:seg("RailFootBar", fa, fb, 0.08, Look.brass)
				K.freeDepth -= 1
			end
		end
	end

	-- 무대 왼쪽 앞: 드럼통 하이테이블 2 + 스툴 ---------------------------------------------------------------
	for i, zc in { -31.0, -25.5 } do
		local pcf = at(R, -19.6, zc)
		if placeOr(R, pcf, V3(2.4, 3.6, 2.4), 0.2, "barrel table") then
			local col = if i == 1 then rgb(40, 90, 160) else rgb(190, 40, 40)
			K:vcyl("BarrelBody", 3.0, 1.9, pcf * CF(0, 1.5, 0), lk(col, M.Metal))
			for _, y in { 0.6, 2.4 } do
				K:vcyl("BarrelRib", 0.1, 1.96, pcf * CF(0, y, 0), lk(dk(col, 0.3), M.Metal))
			end
			K:disc("BarrelTop", 2.4, 0.12, pcf * CF(0, 3.06, 0), lk(rgb(56, 40, 30), M.Wood))
			txt(K, "BarrelStencil", 1.2, 0.6, at(R, -19.6, zc + 0.96, 0, 1.5), "OCEAN\n051", WHITE, nil, F.GothamBlack)
			for k, a in { 0.6, 2.6 } do
				local sp = at(R, -19.6 + math.cos(a) * 1.9, zc + math.sin(a) * 1.9)
				if place(R, sp, V3(1.2, 2.8, 1.2), 0, "barrel stool") then
					barStool(K, sp, 2.6, lk(if k == 1 then rgb(30, 30, 32) else rgb(200, 40, 40), M.Leather))
				end
			end
		end
	end
	-- 벽돌벽 드링크 선반 (HIP-HOP 네온 아래)
	K:free(function()
		local d0 = wallL(R, -10.0, 3.6, 0)
		K:box("WallLedge", V3(13.0, 0.14, 1.0), d0 * CF(0, 0, 0.5), lk(rgb(60, 44, 32), M.Wood))
		K:box("WallLedgeLED", V3(12.8, 0.04, 0.06), d0 * CF(0, -0.1, 0.95), nl(rgb(255, 150, 40)))
		for k = -2, 2 do
			K:bar("WallLedgeBracket", (d0 * CF(k * 3.0, -0.8, 0.02)).Position, (d0 * CF(k * 3.0, -0.07, 0.85)).Position, 0.08, 0.08, Look.blackMetal)
		end
	end)

	-- 스니커 · 머치 벽 (오른벽 무대 쪽 z -34..-14) ----------------------------------------------------------------
	do
		local zc = -24.0
		K:free(function()
			local d = wallR(R, zc, 5.0, 0)
			K:plate("MerchBack", 19.0, 8.6, 0.08, d, lk(rgb(20, 20, 22), M.Slate))
			K:plate("MerchHeader", 9.0, 1.2, 0.12, d * CF(0, 4.9, 0), Look.black)
			txt(K, "MerchHeaderText", 8.6, 1.0, d * CF(0, 4.9, 0.13), "OCEAN CREW · SNEAKER & MERCH", rgb(150, 255, 80), nil, F.GothamBlack, 1.6)
			-- 선반 3단 (LED 모서리) + 스니커
			local SNK = { { rgb(240, 240, 236), rgb(220, 40, 50) }, { rgb(20, 20, 22), rgb(240, 240, 240) }, { rgb(250, 210, 40), rgb(30, 30, 30) }, { rgb(60, 140, 230), WHITE }, { rgb(240, 120, 160), WHITE }, { rgb(100, 200, 90), rgb(20, 20, 20) } }
			for row = 0, 2 do
				local y = 1.3 + row * 2.3
				local sd = d * CF(-4.2, y - 5.0, 0)
				K:box("MerchShelf", V3(9.0, 0.1, 1.1), sd * CF(0, 0, 0.6), gl(rgb(220, 230, 236), 0.45))
				local led = K:box("MerchShelfLED", V3(8.9, 0.04, 0.05), sd * CF(0, -0.06, 1.13), nl(rgb(230, 240, 255)))
				if row == 2 then
					K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 10, Brightness = 1.3, Angle = 170, Color = rgb(220, 236, 255) })
				end
				for k = 0, 3 do
					local c = SNK[((row * 4 + k) % #SNK) + 1]
					local s = sd * CF(-3.3 + k * 2.2, 0.05, 0.6) * ANG(0, (if k % 2 == 0 then 0.35 else -0.35), 0)
					K:box("SneakerSole", V3(0.5, 0.16, 1.2), s * CF(0, 0.08, 0), lk(rgb(245, 245, 240)))
					K:box("SneakerUpper", V3(0.48, 0.42, 0.9), s * CF(0, 0.37, -0.1), lk(c[1]))
					K:ell("SneakerToe", V3(0.48, 0.34, 0.5), s * CF(0, 0.3, 0.38), lk(c[1]))
					K:box("SneakerCollar", V3(0.5, 0.2, 0.36), s * CF(0, 0.62, -0.38), lk(c[2]))
					K:plate("SneakerStripe", 0.6, 0.1, 0.01, s * CF(0.245, 0.36, 0) * ANG(0, PI / 2, 0) * ANG(0, 0, 0.3), lk(c[2]))
				end
				txt(K, "MerchPrice", 1.6, 0.26, sd * CF(3.6, -0.22, 1.16), ({ "₩ 159,000", "₩ 189,000", "₩ 129,000" })[row + 1], WHITE, rgb(20, 20, 20), F.GothamBold)
			end
			-- 모자 6 (고리)
			for k = 0, 5 do
				local hd = d * CF(2.4 + (k % 3) * 1.4, 2.2 - math.floor(k / 3) * 1.5, 0)
				K:bar("CapHook", (hd * CF(0, 0, 0.02)).Position, (hd * CF(0, 0.05, 0.4)).Position, 0.05, 0.05, Look.chrome)
				local cc = ({ rgb(20, 20, 22), rgb(220, 40, 50), rgb(240, 240, 236), rgb(40, 90, 180), rgb(250, 200, 40), rgb(60, 60, 64) })[k + 1]
				K:ell("CapCrown", V3(0.9, 0.55, 0.9), hd * CF(0, -0.15, 0.5), lk(cc, M.Fabric))
				K:box("CapBrim", V3(0.8, 0.05, 0.55), hd * CF(0, -0.38, 0.95) * ANG(math.rad(10), 0, 0), lk(cc, M.Fabric))
				K:plate("CapLogo", 0.3, 0.18, 0.01, hd * CF(0, -0.05, 0.94), lk(WHITE))
			end
			-- 액자 티셔츠 2
			for k = 0, 1 do
				local fd = d * CF(4.7 + k * 3.4 - 2.3, -2.8, 0)
				K:plate("TeeFrame", 2.8, 2.6, 0.1, fd, Look.black)
				K:plate("TeeFrameBack", 2.6, 2.4, 0.11, fd, lk(rgb(230, 228, 220)))
				local tc = if k == 0 then rgb(20, 20, 22) else rgb(240, 240, 236)
				K:plate("TeeBody", 1.3, 1.6, 0.12, fd * CF(0, -0.15, 0), lk(tc, M.Fabric))
				K:plate("TeeSleeve", 0.6, 0.5, 0.12, fd * CF(-0.85, 0.4, 0) * ANG(0, 0, 0.5), lk(tc, M.Fabric))
				K:plate("TeeSleeve", 0.6, 0.5, 0.12, fd * CF(0.85, 0.4, 0) * ANG(0, 0, -0.5), lk(tc, M.Fabric))
				txt(K, "TeePrint", 1.1, 0.6, fd * CF(0, 0.0, 0.13), "OCEAN\nCREW", if k == 0 then rgb(255, 210, 50) else rgb(220, 40, 60), nil, F.LuckiestGuy)
				txt(K, "TeePrice", 1.4, 0.24, fd * CF(0, -1.05, 0.12), "OCEAN TEE ₩ 39,000", rgb(30, 30, 30), nil, F.GothamBold)
			end
		end)
		-- 바닥: 스니커 전시 큐브 (아크릴)
		local pcf = at(R, 20.6, -18.6)
		if placeOr(R, pcf, V3(1.8, 4.6, 1.8), 0.2, "sneaker plinth") then
			K:box("PlinthBody", V3(1.6, 3.0, 1.6), pcf * CF(0, 1.5, 0), Look.white)
			K:box("PlinthLED", V3(1.62, 0.06, 1.62), pcf * CF(0, 3.0, 0), nl(rgb(150, 255, 80)))
			K:box("PlinthCube", V3(1.4, 1.4, 1.4), pcf * CF(0, 3.75, 0), gl(rgb(230, 240, 244), 0.75))
			local s = pcf * CF(0, 3.06, 0) * ANG(0, 0.6, 0)
			K:box("SneakerSole", V3(0.5, 0.16, 1.2), s * CF(0, 0.08, 0), lk(rgb(245, 245, 240)))
			K:box("SneakerUpper", V3(0.48, 0.42, 0.9), s * CF(0, 0.37, -0.1), lk(rgb(220, 40, 50)))
			K:ell("SneakerToe", V3(0.48, 0.34, 0.5), s * CF(0, 0.3, 0.38), lk(rgb(220, 40, 50)))
			txt(K, "PlinthTag", 1.2, 0.4, at(R, 20.6, -17.79, 0, 2.2), "LIMITED\n₩ 329,000", WHITE, rgb(20, 20, 20), F.GothamBold)
		end
	end
	-- 붐박스 (로드 케이스 위, 상호작용: 틀기)
	local eq: { BasePart } = {}
	local boomOn = false
	do
		local pcf = at(R, 21.2, -31.6, -PI / 2)
		if placeOr(R, pcf, V3(4.2, 5.0, 2.4), 0, "road case") then
			K:box("RoadCase", V3(4.0, 2.4, 2.2), pcf * CF(0, 1.2, 0), lk(rgb(30, 30, 32), M.DiamondPlate))
			for _, sy in { 0.05, 2.35 } do
				K:box("RoadCaseEdge", V3(4.04, 0.1, 2.24), pcf * CF(0, sy, 0), Look.alu)
			end
			for _, sx in { -1, 1 } do
				K:box("RoadCaseCorner", V3(0.12, 2.4, 0.12), pcf * CF(sx * 1.98, 1.2, 1.08), Look.chrome)
				K:box("RoadCaseHandle", V3(0.8, 0.12, 0.08), pcf * CF(sx * 1.1, 1.5, 1.13), Look.chrome)
			end
			txt(K, "RoadCaseStencil", 2.4, 0.5, pcf * CF(0, 0.8, 1.11), "OCEAN CREW · FRAGILE", WHITE, nil, F.GothamBlack)
			local b = pcf * CF(0, 2.4, 0)
			K:box("BoomBody", V3(3.4, 1.8, 0.9), b * CF(0, 0.9, 0), lk(rgb(190, 192, 196), M.Metal))
			K:box("BoomFront", V3(3.3, 1.7, 0.04), b * CF(0, 0.9, 0.46), lk(rgb(40, 40, 44)))
			for _, sx in { -1, 1 } do
				K:disc("BoomSpeaker", 1.1, 0.06, b * CF(sx * 1.05, 0.85, 0.49) * ANG(PI / 2, 0, 0), lk(rgb(20, 20, 22), M.DiamondPlate))
				K:disc("BoomSpeakerRim", 1.2, 0.04, b * CF(sx * 1.05, 0.85, 0.47) * ANG(PI / 2, 0, 0), Look.chrome)
				K:disc("BoomTweeter", 0.3, 0.06, b * CF(sx * 1.05, 1.55, 0.49) * ANG(PI / 2, 0, 0), Look.chrome)
			end
			K:box("BoomDeck", V3(0.9, 0.6, 0.06), b * CF(0, 1.1, 0.49), lk(rgb(20, 20, 24), M.Glass))
			K:box("BoomTape", V3(0.6, 0.35, 0.02), b * CF(0, 1.1, 0.52), lk(rgb(240, 200, 60)))
			for k = 0, 4 do
				local led = K:box("BoomEQ", V3(0.1, 0.2, 0.03), b * CF(-0.3 + k * 0.15, 0.55, 0.5), lk(rgb(40, 40, 40)))
				table.insert(eq, led)
			end
			K:bar("BoomHandle", (b * CF(-1.3, 1.8, 0)).Position, (b * CF(-1.1, 2.3, 0)).Position, 0.12, 0.12, Look.chrome)
			K:bar("BoomHandle", (b * CF(1.3, 1.8, 0)).Position, (b * CF(1.1, 2.3, 0)).Position, 0.12, 0.12, Look.chrome)
			K:bar("BoomHandleTop", (b * CF(-1.1, 2.3, 0)).Position, (b * CF(1.1, 2.3, 0)).Position, 0.12, 0.12, Look.chrome)
			K:cyl("BoomAntenna", 2.0, 0.04, b * CF(0.6, 2.2, -0.3) * ANG(0, 0, 1.2), Look.chrome)
		end
	end

	-- 앞벽 오른쪽: 스티커 벽 + 액자 LP + 네온 051 + 태그 판 (상호작용) ----------------------------------------------
	local tagLabel: TextLabel? = nil
	local tagPart: BasePart? = nil
	K:free(function()
		local d = wallF(R, 12.2, 5.2, 0)
		K:plate("TagWall", 15.0, 8.0, 0.06, d, lk(rgb(30, 30, 34), M.Concrete))
		-- LP 액자 6 (레코드 + 커버)
		local COVERS = { rgb(220, 40, 50), rgb(250, 210, 40), rgb(40, 120, 230), rgb(30, 30, 30), rgb(240, 120, 170), rgb(100, 200, 90) }
		for k = 0, 5 do
			local fd = d * CF(-5.8 + (k % 3) * 2.4, 2.4 - math.floor(k / 3) * 2.4, 0.06)
			K:plate("LPFrame", 2.1, 2.1, 0.08, fd, Look.black)
			K:plate("LPCover", 1.8, 1.8, 0.09, fd, lk(COVERS[k + 1]))
			wdisc(K, "LPRecord", 1.5, 0.02, fd * CF(0.25, 0, 0.09), lk(rgb(16, 16, 18)))
			wdisc(K, "LPLabel", 0.5, 0.025, fd * CF(0.25, 0, 0.09), lk(lt(COVERS[k + 1], 0.4)))
		end
		-- 태그 판 (상호작용: 내 태그 남기기)
		local td = d * CF(3.2, 0.6, 0.06)
		tagPart = K:plate("TagBoard", 7.6, 5.4, 0.04, td, lk(rgb(240, 238, 230), M.Concrete))
		for i = 1, 9 do
			local x = (rnd(41, i) - 0.5) * 6.6
			local y = (rnd(42, i) - 0.5) * 4.4
			txt(K, "OldTag", 1.8, 0.6, td * CF(x, y, 0.05) * ANG(0, 0, (rnd(43, i) - 0.5) * 0.6), ({ "JIN", "HAE.", "051!", "MINO", "BUSAN", "SOO", "KRS", "★WAVE", "광안" })[i], ({ rgb(20, 20, 24), rgb(220, 40, 60), rgb(40, 100, 220), rgb(30, 140, 60) })[(i % 4) + 1], nil, F.PermanentMarker)
		end
		local _, lab = txt(K, "MyTag", 5.2, 1.4, td * CF(0, -0.4, 0.07) * ANG(0, 0, 0.08), "", rgb(255, 60, 160), nil, F.PermanentMarker)
		tagLabel = lab
		txt(K, "TagBoardTitle", 6.0, 0.5, td * CF(0, 2.4, 0.06), "TAG WALL · 너의 이름을 남겨", rgb(20, 20, 24), nil, F.GothamBlack)
		-- 스프레이 캔 3 (선반)
		local sh = d * CF(3.2, -2.55, 0.06)
		K:box("SprayShelf", V3(5.0, 0.1, 0.7), sh * CF(0, 0, 0.35), lk(rgb(60, 44, 32), M.Wood))
		for k = 0, 4 do
			local c = ({ rgb(255, 60, 160), rgb(60, 220, 255), rgb(255, 210, 40), rgb(140, 255, 80), WHITE })[k + 1]
			K:vcyl("SprayCan", 0.9, 0.32, CF((sh * CF(-1.8 + k * 0.9, 0.5, 0.35)).Position) * R.A.Rotation, lk(c, M.Metal))
			K:vcyl("SprayCap", 0.16, 0.26, CF((sh * CF(-1.8 + k * 0.9, 1.03, 0.35)).Position) * R.A.Rotation, Look.white)
		end
		-- 네온 '051' + 왕관 (벽 위쪽)
		local nd = d * CF(-1.0, 5.3, 0.06)
		txt(K, "Neon051", 5.0, 2.2, nd, "051", rgb(255, 60, 160), nil, F.LuckiestGuy, 2.4)
		txt(K, "NeonCrown", 2.0, 1.6, nd * CF(4.0, 0.4, 0) * ANG(0, 0, -0.15), "♛", rgb(255, 214, 60), nil, F.GothamBlack, 2.4)
	end)
	-- 왼벽 끝 (바 뒤쪽 z 27.5..34.5): 네온 스프레이캔 + STAY REAL
	K:free(function()
		local d = wallL(R, 31.0, 7.0, 0)
		K:plate("NeonPanel", 6.4, 5.0, 0.06, d, lk(rgb(16, 16, 20)))
		local cn = d * CF(-1.6, -0.2, 0.08)
		local pts = { { -0.5, -1.6 }, { 0.5, -1.6 }, { 0.5, 1.0 }, { 0.2, 1.4 }, { -0.2, 1.4 }, { -0.5, 1.0 }, { -0.5, -1.6 } }
		for k = 1, #pts - 1 do
			K:seg("NeonCan", (cn * CF(pts[k][1], pts[k][2], 0)).Position, (cn * CF(pts[k + 1][1], pts[k + 1][2], 0)).Position, 0.1, nl(rgb(60, 230, 255)))
		end
		K:seg("NeonCanNozzle", (cn * CF(0, 1.4, 0)).Position, (cn * CF(0, 1.75, 0)).Position, 0.12, nl(rgb(60, 230, 255)))
		for k = 0, 4 do
			local a = -0.5 + k * 0.25
			K:seg("NeonSpray", (cn * CF(0.25, 1.75, 0)).Position, (cn * CF(1.0 + k * 0.1, 1.75 + math.sin(a) * 1.2, 0)).Position, 0.06, nl(rgb(255, 60, 160)))
		end
		txt(K, "NeonStayReal", 3.0, 2.4, d * CF(1.5, 0, 0.08), "STAY\nREAL", rgb(255, 230, 90), nil, F.LuckiestGuy, 2.2)
	end)

	-- 바: 앞면 골강판 · 매달린 메뉴판 · 케이지 펜던트 --------------------------------------------------------------
	K:free(function()
		local fz0, fz1 = 3.1, 26.9
		local fd = face(R, -15.98, 2.0, (fz0 + fz1) / 2, PI / 2)
		K:plate("BarFrontClad", fz1 - fz0, 2.9, 0.04, fd, lk(rgb(70, 72, 76), M.DiamondPlate))
		K:plate("BarFrontTrim", fz1 - fz0, 0.1, 0.06, fd * CF(0, 1.45, 0), Look.blackMetal)
		txt(K, "BarFrontText", 10.0, 1.4, fd * CF(0, 0.2, 0.05), "ROOM 2 BAR", rgb(255, 170, 60), nil, F.LuckiestGuy, 1.3)
		-- 매달린 메뉴판 (손님 쪽 +x 를 봄)
		local md = face(R, -17.2, 9.6, 15.0, PI / 2)
		K:plate("BarMenuBoard", 7.0, 2.6, 0.12, md, Look.black)
		for _, sx in { -1, 1 } do
			K:seg("BarMenuChain", (md * CF(sx * 3.0, 1.3, 0.06)).Position, (md * CF(sx * 3.0, H - 9.6, 0.06)).Position, 0.04, Look.chrome)
		end
		txt(K, "BarMenuTitle", 6.6, 0.55, md * CF(0, 0.92, 0.13), "ROOM 2 · DRINKS", rgb(255, 170, 60), nil, F.GothamBlack, 1.5)
		txt(K, "BarMenuL", 3.2, 1.6, md * CF(-1.65, -0.35, 0.13), "소주 6,000\n카스 · 테라 8,000\n하이볼 12,000\n잭콕 14,000", WHITE, nil, F.GothamBold, 1.3, { align = "Left" })
		txt(K, "BarMenuR", 3.2, 1.6, md * CF(1.65, -0.35, 0.13), "예거밤 13,000\n데킬라 샷 9,000\n칵테일 15,000\n논알콜 7,000", WHITE, nil, F.GothamBold, 1.3, { align = "Left" })
	end)
	local function cage(px: number, pz: number, drop: number, light: boolean)
		K:free(function()
			local top = ap(R, px, H, pz)
			K:disc("CageCanopy", 0.5, 0.08, at(R, px, pz, 0, H - 0.04), Look.blackMetal)
			K:seg("CageCord", top, ap(R, px, H - drop + 0.6, pz), 0.04, Look.black)
			local c = at(R, px, pz, 0, H - drop)
			K:vcyl("CageCap", 0.3, 0.42, c * CF(0, 0.55, 0), Look.blackMetal)
			K:ring("CageRing", c * CF(0, 0.0, 0) * ANG(PI / 2, 0, 0), 0.42, 0.05, 8, Look.blackMetal)
			for k = 0, 3 do
				local a = k * PI / 2
				K:seg("CageWire", (c * CF(math.cos(a) * 0.2, 0.45, math.sin(a) * 0.2)).Position, (c * CF(math.cos(a) * 0.42, -0.2, math.sin(a) * 0.42)).Position, 0.035, Look.blackMetal)
			end
			local b = K:ell("CageBulb", V3(0.36, 0.5, 0.36), c * CF(0, 0.05, 0), Look.lampWarm)
			if light then
				K:light(b, "PointLight", { Range = 14, Brightness = 0.9, Color = rgb(255, 190, 120) })
			end
		end)
	end
	for i, z in { 6.0, 12.0, 18.0, 24.0 } do
		cage(-15.0, z, 4.2, i == 2)
	end
	for i, z in { -5.0, 11.0, 27.0 } do
		cage(16.8, z, 4.8, i == 2)
	end

	-- 앞쪽 모서리 스피커 (천장 브래킷, 방 가운데를 향함) --------------------------------------------------------------
	for _, sx in { -1, 1 } do
		local px, pz = sx * 21.6, 32.6
		K:free(function()
			local s = at(R, px, pz, 0, 11.2) * ANG(0, math.atan2(px, pz), 0)
			K:seg("SpkBracket", ap(R, px, H, pz), ap(R, px, 12.6, pz), 0.12, Look.blackMetal)
			local body = s * ANG(math.rad(-12), 0, 0)
			K:box("CornerSpeaker", V3(1.8, 2.8, 1.6), body, lk(rgb(22, 22, 24)))
			K:box("CornerSpeakerGrille", V3(1.7, 2.7, 0.04), body * CF(0, 0, -0.81), lk(rgb(44, 44, 48), M.DiamondPlate))
			K:disc("CornerWoofer", 1.2, 0.04, body * CF(0, -0.45, -0.84) * ANG(PI / 2, 0, 0), lk(rgb(30, 30, 32)))
			K:disc("CornerHorn", 0.5, 0.04, body * CF(0, 0.85, -0.84) * ANG(PI / 2, 0, 0), lk(rgb(30, 30, 32)))
			K:box("SpkYoke", V3(2.0, 0.12, 0.2), body * CF(0, 1.45, 0), Look.blackMetal)
		end)
	end

	-- 천장: 케이블 트레이 · 스프링클러 배관 (빨강) · 감지기 · 비상구 유도등 ---------------------------------------------
	K:free(function()
		for _, x in { -19.0, 19.0 } do
			K:box("CableTray", V3(1.2, 0.12, R.D - 4), at(R, x, R.cz, 0, H - 0.9), lk(rgb(150, 152, 156), M.Metal))
			K:box("CableTrayLip", V3(0.06, 0.3, R.D - 4), at(R, x - 0.6, R.cz, 0, H - 0.78), lk(rgb(150, 152, 156), M.Metal))
			K:box("CableTrayLip", V3(0.06, 0.3, R.D - 4), at(R, x + 0.6, R.cz, 0, H - 0.78), lk(rgb(150, 152, 156), M.Metal))
			K:box("CableBundle", V3(0.8, 0.22, R.D - 4.2), at(R, x, R.cz, 0, H - 0.73), lk(rgb(20, 20, 22), M.Rubber))
			for k = 0, 6 do
				local z = z0 + 4 + k * 10
				K:seg("TrayHanger", ap(R, x - 0.6, H, z), ap(R, x - 0.6, H - 0.95, z), 0.05, Look.blackMetal)
				K:seg("TrayHanger", ap(R, x + 0.6, H, z), ap(R, x + 0.6, H - 0.95, z), 0.05, Look.blackMetal)
			end
		end
		K:seg("SprinklerMain", ap(R, 4.0, H - 0.5, z0 + 1), ap(R, 4.0, H - 0.5, z1 - 1), 0.28, lk(rgb(190, 30, 30), M.Metal))
		for k = 0, 7 do
			local z = z0 + 5 + k * 8.5
			K:seg("SprinklerDrop", ap(R, 4.0, H - 0.5, z), ap(R, 4.0, H - 1.3, z), 0.1, lk(rgb(190, 30, 30), M.Metal))
			K:disc("SprinklerHead", 0.22, 0.05, at(R, 4.0, z, 0, H - 1.35), Look.brass)
			K:seg("PipeHanger", ap(R, 4.0, H, z + 2), ap(R, 4.0, H - 0.5, z + 2), 0.04, Look.blackMetal)
		end
	end)
	for _, p in { { -6.0, -14.0 }, { 8.0, 18.0 } } do
		smoke(K, R, p[1], p[2])
	end
	cctv(K, R, -20.5, 31.5)
	cctv(K, R, 20.5, -31.5)
	K:free(function()
		exitLight(K, wallF(R, -0.5, 9.4, 0.02), 2.4, "")
		-- 소화기 (입구 오른쪽 벽)
		local ex = at(R, -5.6, z1 - 0.45)
		K:box("ExtStand", V3(0.9, 0.12, 0.9), ex * CF(0, 0.06, 0), lk(rgb(180, 30, 30)))
		K:vcyl("ExtBody", 1.5, 0.62, ex * CF(0, 0.87, 0), lk(rgb(200, 24, 28)))
		K:ell("ExtDome", V3(0.62, 0.3, 0.62), ex * CF(0, 1.62, 0), lk(rgb(200, 24, 28)))
		K:box("ExtHandle", V3(0.5, 0.06, 0.12), ex * CF(0.08, 1.95, 0), Look.black)
		txt(K, "ExtSign", 1.2, 0.5, wallF(R, -5.6, 3.0, 0.12), "소화기", WHITE, rgb(200, 24, 28), F.GothamBlack)
	end)
	-- 바닥 스텐실 (입구 안쪽)
	K:free(function()
		txt(K, "FloorStencil", 7.0, 1.6, topCF(ap(R, -0.5, 0.02, 31.0), av(R, 0, 0, -1)), "WELCOME TO THE CYPHER", rgb(220, 220, 214), nil, F.GothamBlack, nil, { d = 0.01 })
	end)
	-- 벽화 조명 (색 PointLight)
	do
		local a = K:box("MuralLightA", V3(0.1, 0.1, 0.1), at(R, -14.0, 31.0, 0, 9.0), lk(BLACK, nil, { t = 1 }))
		K:light(a, "PointLight", { Range = 16, Brightness = 0.9, Color = rgb(255, 120, 200) })
		local b = K:box("MuralLightB", V3(0.1, 0.1, 0.1), at(R, 21.0, 11.0, 0, 11.0), lk(BLACK, nil, { t = 1 }))
		K:light(b, "PointLight", { Range = 18, Brightness = 0.8, Color = rgb(150, 200, 255) })
		local c = K:box("MuralLightC", V3(0.1, 0.1, 0.1), at(R, -18.0, -31.0, 0, 11.0), lk(BLACK, nil, { t = 1 }))
		K:light(c, "PointLight", { Range = 14, Brightness = 0.8, Color = rgb(200, 140, 255) })
	end

	-- 상호작용 ---------------------------------------------------------------------------------------
	-- 1) 붐박스 틀기 (EQ 애니메이션)
	if #eq > 0 then
		local cols = { rgb(60, 230, 120), rgb(60, 230, 120), rgb(250, 220, 40), rgb(255, 120, 40), rgb(255, 40, 60) }
		prompt(R, eq[3], "toggle", {
			object = "붐박스",
			onText = "음악 끄기",
			offText = "붐박스 틀기",
			state = false,
			on = function(s: boolean)
				boomOn = s
				if not s then
					for _, p in eq do
						p.Material = M.SmoothPlastic
						p.Color = rgb(40, 40, 40)
					end
				end
			end,
		})
		Interact.anim(K, function(t: number)
			if not boomOn then
				return
			end
			for k, p in eq do
				local lvl = 0.5 + 0.5 * math.sin(t * 9 + k * 1.7)
				p.Material = if lvl > 0.35 then M.Neon else M.SmoothPlastic
				p.Color = if lvl > 0.35 then cols[k] else rgb(40, 40, 40)
			end
		end)
	end
	-- 2) MC 마이크 (ON AIR)
	if micLED then
		prompt(R, micLED, "toggle", {
			object = "MC 마이크",
			onText = "마이크 내려놓기",
			offText = "마이크 잡기",
			state = false,
			on = function(s: boolean)
				local m = micLED :: BasePart
				m.Material = if s then M.Neon else M.SmoothPlastic
				m.Color = if s then rgb(255, 40, 40) else rgb(60, 60, 60)
				if onAir then
					(onAir :: BasePart).Material = if s then M.Neon else M.SmoothPlastic
					;(onAir :: BasePart).Color = if s then rgb(230, 30, 40) else rgb(60, 20, 20)
				end
			end,
		})
	end
	-- 3) 태그 남기기 (내 이름 + 색 바꾸기)
	if tagPart and tagLabel then
		local Players = game:GetService("Players")
		local lp = Players.LocalPlayer
		local nm = "GUEST"
		if lp then
			local okN, dn = pcall(function()
				return (lp :: any).DisplayName
			end)
			nm = if okN and type(dn) == "string" and dn ~= "" then dn else lp.Name
		end
		local tags = { nm .. " WAS HERE ✌", nm .. " × OCEAN", "051 ♥ " .. nm, nm .. " 다녀감 ★" }
		local tcols = { rgb(255, 60, 160), rgb(40, 180, 255), rgb(255, 170, 30), rgb(40, 200, 90) }
		prompt(R, tagPart, "cycle", {
			action = "태그 남기기",
			object = "TAG WALL",
			start = 0,
			on = function(i, it)
				local l = tagLabel :: TextLabel
				l.Text = it
				l.TextColor3 = tcols[(i - 1) % #tcols + 1]
			end,
		}, tags)
	end
end

--=====================================================================================================
-- OCEAN SKY LOUNGE 2F (clublounge) -------------------------------------------------------------------
--=====================================================================================================
-- 라운지 암체어 (통 의자): pcf 바닥, +Z = 앉은 사람이 보는 쪽
local function armchair(K: any, pcf: CFrame, fab: any, legs: any?)
	local lg = legs or Look.brass
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:seg("ArmchairLeg", (pcf * CF(sx * 0.95, 0.5, sz * 0.85)).Position, (pcf * CF(sx * 1.05, 0.02, sz * 0.95)).Position, 0.1, lg)
		end
	end
	-- 둥근 모서리는 보이는 윗변만 원통 하나로 (rbox 6파트 대신 2파트)
	local cush = lk(lt(fab.c, 0.08), fab.m)
	K:box("ArmchairBase", V3(2.4, 0.5, 2.3), pcf * CF(0, 0.75, 0), fab)
	K:box("ArmchairCushion", V3(1.9, 0.3, 1.75), pcf * CF(0, 1.13, 0.05), cush)
	K:cyl("ArmchairCushionNose", 1.9, 0.34, pcf * CF(0, 1.13, 0.93), cush)
	local back = pcf * CF(0, 1.62, -0.95) * ANG(math.rad(-8), 0, 0)
	K:box("ArmchairBack", V3(2.4, 1.45, 0.45), back, fab)
	K:cyl("ArmchairBackRoll", 2.4, 0.45, back * CF(0, 0.72, 0), fab)
	for _, sx in { -1, 1 } do
		K:box("ArmchairArm", V3(0.36, 0.72, 2.2), pcf * CF(sx * 1.08, 1.26, 0), fab)
		K:cyl("ArmchairArmRoll", 2.2, 0.36, pcf * CF(sx * 1.08, 1.62, 0) * ANG(0, PI / 2, 0), fab)
	end
	K:ell("ArmchairPillow", V3(1.0, 0.8, 0.28), pcf * CF(0.25, 1.75, -0.6) * ANG(math.rad(-15), 0.25, 0), lk(rgb(232, 222, 204), M.Fabric))
end

-- 사이드 테이블 + 테이블 램프. pcf 바닥. 반환 램프 갓
local function sideLamp(K: any, pcf: CFrame, topL: any, shadeC: Color3?): BasePart
	K:disc("SideTblBase", 0.9, 0.05, pcf * CF(0, 0.03, 0), Look.brass)
	K:vcyl("SideTblStem", 1.8, 0.12, pcf * CF(0, 0.95, 0), Look.brass)
	K:disc("SideTblTop", 1.3, 0.08, pcf * CF(0, 1.9, 0), topL)
	K:ell("LampBase", V3(0.5, 0.6, 0.5), pcf * CF(0, 2.25, 0), lk(rgb(30, 60, 80), M.Glass, { t = 0.1 }))
	K:vcyl("LampStem", 0.5, 0.06, pcf * CF(0, 2.75, 0), Look.brass)
	local shade = K:vcyl("LampShade", 0.55, 0.8, pcf * CF(0, 3.2, 0), lk(shadeC or rgb(255, 222, 180), M.Neon, { t = 0.12 }))
	K:disc("LampShadeTop", 0.7, 0.03, pcf * CF(0, 3.48, 0), lk(rgb(240, 230, 210)))
	return shade
end

-- 커튼 묶음 (창가, 접힌 주름 5): 정렬 x (창 쪽 면), z 중심, 높이
local function curtainStack(K: any, R: any, x: number, z: number, h: number, fab: any)
	-- 묶어 둔 드레이프: 얇은 주름 7개가 물결 (앞뒤로 엇갈림) + 바닥에 살짝 끌리는 밑단 + 천 타이백
	K:free(function()
		local fold = lk(dk(fab.c, 0.12), fab.m)
		for i = -3, 3 do
			local zz = z + i * 0.19
			local xx = x + 0.36 + (if i % 2 == 0 then 0 else 0.11)
			K:vcyl("CurtainFold", h - 0.1, 0.24, at(R, xx, zz, 0, h / 2 + 0.1), if i % 2 == 0 then fab else fold)
		end
		K:box("CurtainHeader", V3(0.5, 0.3, 1.5), at(R, x + 0.42, z, 0, h - 0.1), fold)
		K:box("CurtainTieBack", V3(0.62, 0.16, 1.5), at(R, x + 0.42, z, 0, 3.4), lk(dk(fab.c, 0.35), M.Fabric))
		K:box("CurtainTieHook", V3(0.2, 0.2, 0.2), at(R, x + 0.1, z + 0.85, 0, 3.4), Look.brass)
	end)
end

local function buildLounge(K: any, V: any, R: any)
	local H = R.H
	local x0, x1, z0, z1 = R.x0, R.x1, R.z0, R.z1
	local WARM = rgb(255, 204, 150)
	local walnut = lk(rgb(70, 48, 34), M.Wood)
	local velvetBlue = lk(rgb(36, 54, 86), M.Fabric)
	local velvetCream = lk(rgb(214, 200, 178), M.Fabric)
	local velvetRust = lk(rgb(150, 70, 48), M.Fabric)
	local marbleW = lk(rgb(232, 228, 220), M.Marble)
	local brassL = Look.brass
	-- 비울 곳 ------------------------------------------------------------------------------------------
	keepBox(R, -6.0, z0, 4.0, z0 + 5.0, 9, "door") -- 테라스 문
	keepBox(R, -4.8, z0, 3.0, 68.0, 6.8, "aisle") -- 긴 통로
	keepBox(R, 3.0, -18.0, 8.6, 28.0, 6.5, "bar") -- 바 스툴 앞
	keepBox(R, x0, 64.0, -8.6, z1, 8, "stair") -- 계단 도착
	keepBox(R, -9.0, 60.0, 3.0, 68.0, 7, "stair")
	-- 맵에서 소파 묶음 · 낮은 테이블 위치 읽기 (정렬 z)
	local groups = {}
	for _, r in V.byName.Plinth or {} do
		local mn, mx = abox(R, r)
		if mx.X < 0 and mx.Z - mn.Z > 8 then
			table.insert(groups, { z0 = mn.Z - 0.2, z1 = mx.Z + 0.2, back = mx.X })
		end
	end
	if #groups == 0 then
		for _, g in { { -77, -63 }, { -49, -35 }, { -21, -7 }, { 7, 21 }, { 35, 49 } } do
			table.insert(groups, { z0 = g[1], z1 = g[2], back = -5.6 })
		end
	end
	table.sort(groups, function(a, b)
		return a.z0 < b.z0
	end)
	local tables = {}
	for _, r in V.byName.LowTable or {} do
		local mn, mx = abox(R, r)
		table.insert(tables, { c = (mn + mx) / 2, mn = mn, mx = mx })
	end

	-- 천장: 창가 월넛 판재 천장 · 통로 라인 조명 · 다운라이트 · 설비 ----------------------------------------------
	K:free(function()
		local segs = 6
		local za, zb = z0 + 0.4, 67.6
		for i = 0, segs - 1 do
			local s0 = za + (zb - za) * i / segs
			local s1 = za + (zb - za) * (i + 1) / segs
			K:box("SlatCeiling", V3(12.0, 0.22, s1 - s0 - 0.12), at(R, -11.5, (s0 + s1) / 2, 0, H - 0.36), lk(rgb(78, 54, 38), M.WoodPlanks))
		end
		K:box("SlatCeilingEdge", V3(0.08, 0.5, zb - za), at(R, -5.46, (za + zb) / 2, 0, H - 0.25), Look.brass)
		-- 통로 라인 조명 2줄 (얇은 슬롯)
		for _, x in { -1.2, 6.2 } do
			K:box("SlotLightChannel", V3(0.4, 0.06, z1 - z0 - 3), at(R, x, R.cz, 0, H - 0.03), Look.black)
		end
	end)
	local slotA = cove(K, R, -1.2, z0 + 1.5, -1.2, z1 - 1.5, H - 0.07, WARM, 0.55, 13)
	local slotB = cove(K, R, 6.2, z0 + 1.5, 6.2, z1 - 1.5, H - 0.07, WARM, 0, 0, false)
	local winCove = cove(K, R, -19.2, z0 + 1.5, -19.2, 67.0, H - 0.5, rgb(255, 196, 140), 0.6, 14)
	local moodParts: { BasePart } = {}
	for _, p in { slotA, slotB } do
		if p then
			table.insert(moodParts, p)
		end
	end
	-- 창 아래 바닥 LED (유리 따라 은은하게)
	K:free(function()
		local p = K:box("WindowFloorLED", V3(0.1, 0.05, 151), at(R, x0 + 0.25, -9.5, 0, 0.03), nl(rgb(255, 196, 140)))
		table.insert(moodParts, p)
	end)
	for _, z in { -78, -60, -42, -24, 34, 46, 58 } do
		for _, x in { 9.0, 15.0 } do
			downlight(K, R, x, z, {})
		end
	end
	for z = -80, 60, 14 do
		sprinkler(K, R, -11.5, z + 3)
		sprinkler(K, R, 2.0, z + 10)
		sprinkler(K, R, 13.0, z + 3)
	end
	for _, z in { -70, -30, 10, 50 } do
		smoke(K, R, 2.0, z)
	end
	cctv(K, R, 18.5, -84.0)
	cctv(K, R, -7.5, 62.0)
	for _, z in { -60, -20, 20, 56 } do
		ceilSpeaker(K, R, 2.0, z + 3)
	end

	-- 커튼 (창 기둥 위치) + 레일 + 시어 커튼 (상호작용) ---------------------------------------------------------
	local curtainFab = lk(rgb(138, 118, 102), M.Fabric)
	local sheers: { BasePart } = {}
	local stackZ = {}
	do
		local seen = {}
		for _, g in groups do
			for _, b in { g.z0, g.z1 } do
				local m = 3 + 6 * math.floor((b - 3) / 6 + 0.5)
				if not seen[m] and m > z0 + 2 and m < 66 then
					seen[m] = true
					table.insert(stackZ, m)
				end
			end
		end
		table.sort(stackZ)
	end
	K:free(function()
		K:box("CurtainTrack", V3(0.16, 0.12, 152), at(R, x0 + 0.55, -9.5, 0, H - 0.6), Look.blackMetal)
		for _, z in stackZ do
			curtainStack(K, R, x0, z, H - 0.7, curtainFab)
		end
		for i = 1, #stackZ - 1 do
			local a, b = stackZ[i] + 0.9, stackZ[i + 1] - 0.9
			if b - a > 1 then
				local sp = K:box("SheerCurtain", V3(0.05, H - 1.0, b - a), at(R, x0 + 0.75, (a + b) / 2, 0, (H - 1.0) / 2 + 0.1), lk(rgb(240, 234, 222), M.Fabric, { t = 1 }))
				table.insert(sheers, sp)
			end
		end
	end)

	-- 소파 묶음: 러그 · 끝 사이드 램프 · 펜던트 3 -----------------------------------------------------------------
	local lampShades: { BasePart } = {}
	local RUGS = { rgb(150, 120, 92), rgb(70, 82, 104), rgb(128, 74, 60), rgb(70, 92, 84), rgb(140, 116, 96) }
	for gi, g in groups do
		local gz = (g.z0 + g.z1) / 2
		local len = g.z1 - g.z0
		K:free(function()
			local rc = RUGS[(gi - 1) % #RUGS + 1]
			K:box("LoungeRug", V3(11.6, 0.03, len + 3.0), at(R, -10.9, gz, 0, 0.015), lk(rc, M.Fabric))
			K:box("LoungeRugBorder", V3(12.0, 0.025, len + 3.4), at(R, -10.9, gz, 0, 0.012), lk(dk(rc, 0.45), M.Fabric))
		end)
		-- 소파 양 끝 사이드 램프
		for _, zz in { g.z0 - 1.2, g.z1 + 1.2 } do
			local pcf = at(R, -7.6, zz)
			if place(R, pcf, V3(1.3, 3.6, 1.3), 0, "sofa side lamp") then
				local sh = sideLamp(K, pcf, marbleW)
				table.insert(lampShades, sh)
			end
		end
		-- 낮은 테이블 위 펜던트 3 (유리 구, 높이 다르게)
		local tz = gz
		for _, t in tables do
			if t.c.Z > g.z0 - 2 and t.c.Z < g.z1 + 2 then
				tz = t.c.Z
			end
		end
		K:free(function()
			for k = -1, 1 do
				local px, pz = -13.0 + k * 0.4, tz + k * 2.3
				local drop = 4.6 + (k + 1) % 2 * 1.2
				local top = ap(R, px, H - 0.48, pz)
				K:disc("PendantCanopy", 0.45, 0.06, at(R, px, pz, 0, H - 0.5), brassL)
				K:seg("PendantCord", top, ap(R, px, H - 0.5 - drop + 0.9, pz), 0.035, Look.black)
				K:ball("PendantGlobe", 1.1, at(R, px, pz, 0, H - 0.5 - drop + 0.4), lk(rgb(255, 236, 214), M.Glass, { t = 0.35 }))
				K:ball("PendantBulb", 0.38, at(R, px, pz, 0, H - 0.5 - drop + 0.4), Look.lampWarm)
				K:vcyl("PendantCap", 0.18, 0.3, at(R, px, pz, 0, H - 0.5 - drop + 0.98), brassL)
			end
		end)
	end

	-- 창 사이 공간 (소파 묶음 사이): 암체어 · 2인 테이블 · 망원경 · 셰이즈 롱 -----------------------------------------
	local gaps = {}
	for i = 1, #groups - 1 do
		table.insert(gaps, { z0 = groups[i].z1 + 2.2, z1 = groups[i + 1].z0 - 2.2 })
	end
	local scope: Model? = nil
	local scopePivot: Vector3? = nil
	local scopeLabel: TextLabel? = nil
	local lampToggle: BasePart? = nil
	for gi, g in gaps do
		local gz = (g.z0 + g.z1) / 2
		local kind = (gi - 1) % 4
		if kind == 0 or kind == 2 then
			-- 암체어 2 (창을 비스듬히 보며 마주) + 램프 테이블 + 둥근 러그
			K:free(function()
				K:disc("GapRug", 7.6, 0.03, at(R, -14.0, gz, 0, 0.015), lk(if kind == 0 then rgb(196, 182, 160) else rgb(84, 96, 120), M.Fabric))
			end)
			local fab = if kind == 0 then velvetBlue else velvetRust
			for _, s in { -1, 1 } do
				local yaw = math.atan2(-6, -s * 2.0)
				local pcf = at(R, -13.4, gz + s * 2.0, yaw)
				if placeOr(R, pcf, V3(2.6, 3.0, 2.6), 0, "gap armchair") then
					armchair(K, pcf, fab)
				end
			end
			local tcf = at(R, -16.6, gz)
			if placeOr(R, tcf, V3(1.3, 3.6, 1.3), 0, "gap lamp table") then
				local sh = sideLamp(K, tcf, walnut)
				table.insert(lampShades, sh)
				if not lampToggle then
					lampToggle = sh
				end
			end
		elseif kind == 1 then
			-- 창가 2인 칵테일 테이블 + 통 의자 2 + 망원경
			local tcf = at(R, -15.4, gz - 0.8)
			if placeOr(R, tcf, V3(2.2, 2.8, 2.2), 0.2, "two-top") then
				K:disc("TwoTopBase", 1.2, 0.06, tcf * CF(0, 0.03, 0), brassL)
				K:vcyl("TwoTopStem", 2.4, 0.16, tcf * CF(0, 1.25, 0), brassL)
				K:disc("TwoTopTop", 2.0, 0.1, tcf * CF(0, 2.5, 0), marbleW)
				K:vcyl("TwoTopCandle", 0.3, 0.22, tcf * CF(0.3, 2.7, 0.2), gl(rgb(255, 230, 200), 0.3))
				K:ball("TwoTopFlame", 0.12, tcf * CF(0.3, 2.85, 0.2), Look.lampWarm)
				K:box("TwoTopMenu", V3(0.5, 0.6, 0.06), tcf * CF(-0.3, 2.85, -0.3) * ANG(math.rad(-12), 0.4, 0), lk(rgb(30, 26, 22)))
				for _, s in { -1, 1 } do
					local pcf = at(R, -15.4, gz - 0.8 + s * 2.1, if s > 0 then PI else 0)
					if place(R, pcf, V3(2.2, 2.6, 2.0), 0, "two-top chair") then
						K:vcyl("TubChairBase", 0.5, 1.4, pcf * CF(0, 0.25, 0), brassL)
						K:rbox("TubChairSeat", V3(1.9, 0.6, 1.8), 0.25, pcf * CF(0, 0.9, 0), velvetCream)
						K:rbox("TubChairBack", V3(2.0, 1.4, 0.4), 0.18, pcf * CF(0, 1.6, -0.75) * ANG(math.rad(-10), 0, 0), velvetCream)
						K:rbox("TubChairArm", V3(0.3, 0.7, 1.4), 0.12, pcf * CF(-0.95, 1.4, -0.1), velvetCream)
						K:rbox("TubChairArm", V3(0.3, 0.7, 1.4), 0.12, pcf * CF(0.95, 1.4, -0.1), velvetCream)
					end
				end
			end
			-- 망원경 (삼각대 + 경통): 창을 향함
			if not scope then
				local scf = at(R, -18.6, gz + 3.4)
				if placeOr(R, scf, V3(1.8, 5.2, 1.8), 0, "telescope") then
					for k = 0, 2 do
						local a = k * 2 * PI / 3
						K:seg("ScopeLeg", (scf * CF(0, 3.4, 0)).Position, (scf * CF(math.cos(a) * 0.75, 0.02, math.sin(a) * 0.75)).Position, 0.08, Look.blackMetal)
					end
					K:vcyl("ScopeHub", 0.3, 0.3, scf * CF(0, 3.5, 0), Look.blackMetal)
					scopePivot = (scf * CF(0, 3.75, 0)).Position
					scope = K:group("LoungeTelescope", function()
						local bc = scf * CF(0, 3.85, 0) * ANG(0, PI / 2 - 0.35, 0) * ANG(math.rad(4), 0, 0)
						K:cyl("ScopeTube", 2.0, 0.42, bc * CF(0, 0, 0) * ANG(0, PI / 2, 0), lk(rgb(230, 230, 226)))
						K:cyl("ScopeHood", 0.4, 0.52, bc * CF(0, 0, -1.1) * ANG(0, PI / 2, 0), Look.black)
						K:cyl("ScopeEye", 0.5, 0.16, bc * CF(0, 0, 1.2) * ANG(0, PI / 2, 0), Look.black)
						K:disc("ScopeLens", 0.4, 0.02, bc * CF(0, 0, -1.31) * ANG(PI / 2, 0, 0), lk(rgb(80, 120, 160), M.Glass, { r = 0.3 }))
					end)
					local _, lab = txt(K, "ScopeInfo", 1.6, 0.9, at(R, -18.6, gz + 3.4, PI / 2, 1.6) * CF(0, 0, 0.5), "광안대교 VIEW\n야경 조명 20:00-24:00", rgb(255, 230, 190), rgb(20, 20, 24), F.GothamBold, 1.2)
					scopeLabel = lab
					K:box("ScopeInfoStand", V3(0.08, 1.2, 0.08), at(R, -18.6, gz + 3.4, 0, 0.6) * CF(0.5, 0, 0.5), Look.blackMetal)
				end
			end
		else
			-- 셰이즈 롱 (창을 따라 누운 소파) + 플로어 램프
			local pcf = at(R, -16.0, gz, -PI / 2)
			if placeOr(R, pcf, V3(6.4, 3.2, 2.6), 0, "chaise") then
				K:box("ChaisePlinth", V3(6.0, 0.3, 2.2), pcf * CF(0, 0.15, 0), brassL)
				K:rbox("ChaiseBase", V3(6.2, 0.7, 2.4), 0.2, pcf * CF(0, 0.65, 0), velvetCream)
				K:rbox("ChaiseBack", V3(2.0, 1.6, 2.4), 0.3, pcf * CF(-2.2, 1.6, 0) * ANG(0, 0, -0.5), velvetCream)
				K:ell("ChaisePillow", V3(0.5, 0.9, 1.4), pcf * CF(-1.5, 1.45, 0) * ANG(0, 0, -0.4), lk(rgb(150, 70, 48), M.Fabric))
				K:box("ChaiseThrow", V3(1.8, 0.06, 2.42), pcf * CF(1.6, 1.02, 0), lk(rgb(60, 70, 90), M.Fabric))
			end
			local fcf = at(R, -12.0, gz - 3.0)
			if placeOr(R, fcf, V3(1.2, 6.4, 1.2), 0, "floor lamp") then
				K:disc("FloorLampBase", 1.0, 0.08, fcf * CF(0, 0.04, 0), Look.blackMetal)
				K:seg("FloorLampPole", (fcf * CF(0, 0.1, 0)).Position, (fcf * CF(0, 5.6, 0)).Position, 0.08, brassL)
				local sh = K:vcyl("FloorLampShade", 0.8, 1.2, fcf * CF(0, 5.8, 0), lk(rgb(255, 222, 180), M.Neon, { t = 0.12 }))
				table.insert(lampShades, sh)
			end
		end
	end

	-- 남쪽 존 (테라스 문 ~ 바): DJ 코너 · 샴페인 셀러 · 칵테일 하이테이블 -------------------------------------------
	local djFront: BasePart? = nil
	local mixer: BasePart? = nil
	do
		local zc = z0 + 3.8 -- 부스 앞면 z
		local xc = 10.0
		local b = at(R, xc, zc)
		if placeOr(R, b, V3(7.6, 4.0, 2.0), 0, "dj booth") then
			K:box("DJBoothBody", V3(7.2, 3.3, 1.6), b * CF(0, 1.65, 0), Look.black)
			djFront = K:box("DJBoothLED", V3(6.9, 0.12, 0.05), b * CF(0, 2.9, 0.82), nl(rgb(80, 150, 255)))
			table.insert(moodParts, djFront :: BasePart)
			for k = 0, 9 do
				K:box("DJBoothFin", V3(0.08, 2.6, 0.12), b * CF(-3.24 + k * 0.72, 1.5, 0.82), lk(rgb(200, 170, 110), M.Metal))
			end
			txt(K, "DJBoothLogo", 3.6, 0.6, b * CF(0, 1.5, 0.9), "OCEAN SKY · LIVE", rgb(255, 230, 200), nil, F.GothamBlack, 1.2)
			K:box("DJBoothTop", V3(7.4, 0.12, 1.9), b * CF(0, 3.36, -0.1), walnut)
			local top = b * CF(0, 3.42, -0.3)
			for _, sx in { -1, 1 } do
				K:box("CDJ", V3(1.3, 0.24, 1.5), top * CF(sx * 1.55, 0.12, 0), lk(rgb(24, 24, 26)))
				K:disc("CDJWheel", 0.95, 0.05, top * CF(sx * 1.55, 0.27, 0.15), lk(rgb(60, 62, 66), M.Metal))
				K:disc("CDJRing", 1.0, 0.03, top * CF(sx * 1.55, 0.26, 0.15), nl(rgb(255, 200, 120)))
				K:box("CDJScreen", V3(0.8, 0.02, 0.35), top * CF(sx * 1.55, 0.25, -0.5), nl(rgb(60, 140, 255)))
			end
			mixer = K:box("DJMixer", V3(1.1, 0.26, 1.4), top * CF(0, 0.13, 0), lk(rgb(30, 30, 32)))
			for k = 0, 3 do
				K:box("MixerFader", V3(0.06, 0.04, 0.4), top * CF(-0.36 + k * 0.24, 0.28, 0.3), Look.chrome)
				for j = 0, 2 do
					K:disc("MixerKnob", 0.12, 0.06, top * CF(-0.36 + k * 0.24, 0.29, -0.3 + j * 0.2), lk(if j == 0 then rgb(255, 120, 40) else rgb(200, 200, 204)))
				end
			end
			K:box("LaptopBase", V3(1.2, 0.04, 0.85), top * CF(-2.8, 0.3, -0.2), Look.alu)
			K:box("LaptopLid", V3(1.2, 0.8, 0.03), top * CF(-2.8, 0.7, -0.62) * ANG(math.rad(-15), 0, 0), Look.alu)
			K:box("LaptopScreen", V3(1.1, 0.7, 0.01), top * CF(-2.8, 0.7, -0.6) * ANG(math.rad(-15), 0, 0), nl(rgb(40, 60, 110)))
			K:ring("DJHeadphones", top * CF(2.8, 0.3, 0.1) * ANG(PI / 2, 0, 0), 0.32, 0.07, 8, Look.black, 0, PI)
			-- 레코드 상자 (부스 뒤 DJ 쪽 바닥)
			for k = 0, 5 do
				K:box("VinylSleeve", V3(1.0, 1.0, 0.04), b * CF(2.6, 0.6, -2.4 + k * 0.18) * ANG(0, 0, 0.05 * k), lk(({ rgb(220, 60, 40), rgb(30, 30, 30), rgb(240, 200, 60), rgb(40, 110, 200), rgb(240, 240, 232), rgb(30, 30, 30) })[k + 1]))
			end
			K:box("VinylRack", V3(1.2, 0.5, 1.3), b * CF(2.6, 0.25, -2.0), walnut)
			-- 무대 조명 (DJ 위 고정)
			local djl = K:box("DJLightAnchor", V3(0.1, 0.1, 0.1), b * CF(0, 7.5, -0.8), lk(BLACK, nil, { t = 1 }))
			K:light(djl, "PointLight", { Range = 13, Brightness = 0.9, Color = rgb(120, 140, 255) })
		end
		-- 스탠드 스피커 2
		for _, sx in { -1, 1 } do
			local sc = at(R, xc + sx * 4.75, zc + 0.2)
			if placeOr(R, sc, V3(1.6, 6.2, 1.6), 0, "speaker stand") then
				for k = 0, 2 do
					local a = k * 2 * PI / 3 + PI / 6
					K:seg("SpkStandLeg", (sc * CF(0, 1.2, 0)).Position, (sc * CF(math.cos(a) * 0.75, 0.02, math.sin(a) * 0.75)).Position, 0.07, Look.blackMetal)
				end
				K:vcyl("SpkStandPole", 3.0, 0.12, sc * CF(0, 2.6, 0), Look.blackMetal)
				local body = sc * CF(0, 4.85, 0) * ANG(0, -sx * 0.3, 0)
				K:box("StandSpeaker", V3(1.4, 2.2, 1.2), body, lk(rgb(24, 24, 26)))
				K:box("StandSpeakerGrille", V3(1.3, 2.1, 0.03), body * CF(0, 0, 0.61), lk(rgb(46, 46, 50), M.DiamondPlate))
				K:disc("StandSpeakerCone", 0.9, 0.03, body * CF(0, -0.35, 0.63) * ANG(PI / 2, 0, 0), lk(rgb(30, 30, 32)))
			end
		end
	end
	-- 샴페인 · 와인 셀러 (오른벽, 네온 사인 아래)
	do
		local units = { -64.0, -58.4, -52.8, -47.2, -41.6 }
		local cellarLED: BasePart? = nil
		K:free(function()
			for ui, zc in units do
				local d = wallR(R, zc, 0, 0)
				local u = d * CF(0, 3.2, 1.2)
				-- 속이 빈 캐비닛 (뒤판 · 옆판 · 위 · 아래): 유리문 너머로 병이 보이게
				K:box("CellarBack", V3(5.4, 6.4, 0.12), u * CF(0, 0, -1.14), walnut)
				for _, sx in { -1, 1 } do
					K:box("CellarSide", V3(0.14, 6.4, 2.28), u * CF(sx * 2.63, 0, 0.06), walnut)
				end
				K:box("CellarTop", V3(5.4, 0.3, 2.28), u * CF(0, 3.05, 0.06), walnut)
				K:box("CellarFloor", V3(5.12, 0.3, 2.28), u * CF(0, -3.05, 0.06), walnut)
				K:box("CellarMullion", V3(0.12, 5.8, 0.14), u * CF(0, 0.1, 1.15), lk(rgb(30, 26, 24), M.Metal))
				K:box("CellarInner", V3(4.9, 5.7, 0.05), u * CF(0, 0.05, -1.05), lk(rgb(190, 120, 60), M.Neon, { t = 0.25 }))
				for row = 0, 4 do
					local y = -2.3 + row * 1.15
					K:box("CellarShelf", V3(4.8, 0.06, 1.9), u * CF(0, y, -0.05), lk(rgb(90, 64, 44), M.Wood))
					local n = if hi(K) then 4 else 3
					for k = 0, n - 1 do
						local bx = -1.9 + k * 3.8 / math.max(1, n - 1)
						local champ = (ui + row) % 2 == 0
						local bc = if champ then rgb(30, 60, 40) else rgb(70, 20, 30)
						local bcf = u * CF(bx, y + 0.24, -0.05)
						K:cyl("CellarBottle", 1.4, 0.36, bcf * ANG(0, PI / 2, 0), lk(bc, M.Glass, { t = 0.15 }))
						K:cyl("CellarFoil", 0.3, 0.2, bcf * CF(0, 0, 0.8) * ANG(0, PI / 2, 0), lk(if champ then rgb(214, 180, 90) else rgb(150, 30, 40), M.Metal))
					end
				end
				-- 유리문 2 + 손잡이
				for _, sx in { -1, 1 } do
					-- 문틀 (테두리만) + 유리
					local fl = lk(rgb(30, 26, 24), M.Metal)
					for _, dy in { -2.85, 2.85 } do
						K:box("CellarDoorRail", V3(2.5, 0.14, 0.08), u * CF(sx * 1.3, 0.1 + dy, 1.22), fl)
					end
					K:box("CellarDoorStile", V3(0.12, 5.8, 0.08), u * CF(sx * 2.5, 0.1, 1.22), fl)
					K:box("CellarDoorGlass", V3(2.3, 5.5, 0.03), u * CF(sx * 1.3, 0.1, 1.24), lk(rgb(200, 214, 214), M.Glass, { t = 0.88, r = 0.08 }))
					K:box("CellarHandle", V3(0.06, 1.6, 0.1), u * CF(sx * 0.15, 0.3, 1.32), brassL)
				end
				K:box("CellarKick", V3(5.4, 0.3, 0.06), u * CF(0, -3.05, 1.2), Look.black)
				K:box("CellarDisplay", V3(0.9, 0.35, 0.04), u * CF(1.8, 2.85, 1.25), lk(rgb(16, 16, 18)))
				txt(K, "CellarTemp", 0.8, 0.3, u * CF(1.8, 2.85, 1.28), if ui % 2 == 0 then "8°C" else "12°C", rgb(120, 200, 255), nil, F.Code, 1.4)
				local led = K:box("CellarLED", V3(4.7, 0.05, 0.08), u * CF(0, 2.75, 0.85), Look.lampWarm)
				if ui == 3 then
					cellarLED = led
				end
			end
			-- 셀러 위 명판
			txt(K, "CellarPlaque", 8.0, 0.5, wallR(R, -52.8, 6.75, 2.45), "CHAMPAGNE & WINE CELLAR · 셀러 보관 와인은 테이블 오더로", rgb(220, 196, 140), nil, F.GothamMedium)
		end)
		local _ = cellarLED
		-- 남쪽 존 오른벽 코브 (셀러 · 하이테이블 · DJ 쪽을 고르게)
		cove(K, R, 16.6, z0 + 1.5, 16.6, -19.0, H - 0.1, WARM, 0.6, 13)
	end
	-- 하이테이블 존 러그 + 샴페인 아이스 버킷 아일랜드 + 라운지 포드 2
	K:free(function()
		K:box("SouthRug", V3(13.6, 0.03, 46.0), at(R, 9.6, -56.0, 0, 0.015), lk(rgb(58, 46, 40), M.Fabric))
		K:box("SouthRugField", V3(12.4, 0.032, 44.8), at(R, 9.6, -56.0, 0, 0.016), lk(rgb(96, 74, 58), M.Fabric))
		for k = -5, 5 do
			K:box("SouthRugLine", V3(12.2, 0.034, 0.12), at(R, 9.6, -56.0 + k * 4.0, 0, 0.017), lk(rgb(150, 120, 80), M.Fabric))
		end
	end)
	do
		local icf = at(R, 6.2, -56.0)
		if placeOr(R, icf, V3(2.6, 4.2, 4.2), 0.2, "champagne island") then
			K:box("ChampIslandBody", V3(2.4, 2.8, 4.0), icf * CF(0, 1.4, 0), walnut)
			K:box("ChampIslandTop", V3(2.6, 0.12, 4.2), icf * CF(0, 2.86, 0), marbleW)
			K:box("ChampIslandLED", V3(2.5, 0.05, 4.1), icf * CF(0, 0.1, 0), nl(WARM))
			for k = -1, 1 do
				local b = icf * CF(0, 2.92, k * 1.3)
				K:vcyl("IceBucket", 0.9, 0.8, b * CF(0, 0.45, 0), Look.steel)
				K:vcyl("IceBucketIce", 0.06, 0.7, b * CF(0, 0.86, 0), lk(rgb(236, 244, 250), M.Ice))
				K:seg("ChampBottle", (b * CF(0.05, 0.5, 0)).Position, (b * CF(0.25, 1.6, 0.1)).Position, 0.32, lk(rgb(30, 60, 40), M.Glass, { t = 0.1 }))
				K:seg("ChampFoil", (b * CF(0.25, 1.6, 0.1)).Position, (b * CF(0.3, 1.95, 0.12)).Position, 0.16, lk(rgb(214, 180, 90), M.Metal))
			end
			txt(K, "ChampIslandTag", 1.9, 0.4, at(R, 7.52, -56.0, PI / 2, 2.1), "CHAMPAGNE BTL 280,000~", rgb(230, 200, 130), nil, F.GothamMedium)
		end
		for _, pz in { -68.0, -44.0 } do
			for _, s in { -1, 1 } do
				local pcf = at(R, 6.0, pz + s * 1.9, if s > 0 then PI else 0)
				if placeOr(R, pcf, V3(2.6, 3.0, 2.6), 0, "south pod chair") then
					armchair(K, pcf, if s > 0 then velvetCream else velvetBlue)
				end
			end
			local tcf = at(R, 4.0, pz)
			if placeOr(R, tcf, V3(1.3, 3.6, 1.3), 0, "south pod lamp") then
				local sh = sideLamp(K, tcf, marbleW)
				table.insert(lampShades, sh)
			end
		end
	end
	-- 칵테일 하이테이블 4 + 스툴 + 위 펜던트
	for i, zc in { -74.0, -62.0, -50.0, -38.0 } do
		local xc = 12.2
		local pcf = at(R, xc, zc)
		if placeOr(R, pcf, V3(2.6, 3.8, 2.6), 0.2, "high table") then
			highTable(K, pcf, 3.5, 2.4, marbleW, brassL)
			-- 셀러 위 네온 간판 (맵, z -55.6..-36.4) 앞 테이블은 펜던트 대신 무선 버섯 램프 (간판을 가리지 않게)
			local underSign = zc > -57 and zc < -35
			if underSign then
				K:disc("CordlessLampFoot", 0.5, 0.05, pcf * CF(0.35, 3.58, 0.2), brassL)
				K:vcyl("CordlessLampStem", 0.7, 0.1, pcf * CF(0.35, 3.95, 0.2), brassL)
				local cap = K:ell("CordlessLampShade", V3(0.95, 0.5, 0.95), pcf * CF(0.35, 4.4, 0.2), lk(rgb(255, 214, 160), M.Neon, { t = 0.1 }))
				K:ell("CordlessLampTop", V3(1.0, 0.36, 1.0), pcf * CF(0.35, 4.52, 0.2), brassL)
				table.insert(lampShades, cap)
			else
				K:vcyl("HiTableCandle", 0.32, 0.22, pcf * CF(0, 3.72, 0), gl(rgb(255, 230, 200), 0.3))
				K:ball("HiTableFlame", 0.12, pcf * CF(0, 3.9, 0), Look.lampWarm)
			end
			for k, a in { 0.4, 2.5, 4.4 } do
				local sp = at(R, xc + math.cos(a) * 2.0, zc + math.sin(a) * 2.0)
				if place(R, sp, V3(1.2, 2.9, 1.2), 0, "high stool") then
					barStool(K, sp, 2.75, if k == 2 then velvetBlue else lk(rgb(40, 34, 30), M.Leather), brassL)
				end
			end
			-- 펜던트 (황동 돔)
			K:free(function()
				if underSign then
					return
				end
				local px, pz = xc, zc
				K:disc("HTPendantCanopy", 0.5, 0.06, at(R, px, pz, 0, H - 0.04), brassL)
				K:seg("HTPendantCord", ap(R, px, H - 0.08, pz), ap(R, px, 7.6, pz), 0.04, Look.black)
				K:ell("HTPendantDome", V3(1.6, 1.0, 1.6), at(R, px, pz, 0, 7.35), brassL)
				local dif = K:disc("HTPendantDiffuser", 1.4, 0.03, at(R, px, pz, 0, 6.9), Look.lampWarm)
				if i == 2 then
					K:light(dif, "PointLight", { Range = 16, Brightness = 0.9, Color = WARM })
				end
			end)
		end
	end

	-- 북쪽 존: 라이브러리 라운지 (크레덴자 · 아트월 · 소파 · 암체어 · 커피 테이블 · 플로어 램프) · VIP 호스트 데스크 -----------
	do
		-- 크레덴자 (오른벽)
		local cz0, cz1 = 30.0, 60.0
		K:free(function()
			local d = wallR(R, (cz0 + cz1) / 2, 0, 0)
			local u = d * CF(0, 1.6, 0.9)
			K:box("Credenza", V3(cz1 - cz0, 3.2, 1.8), u, walnut)
			K:box("CredenzaTop", V3(cz1 - cz0 + 0.2, 0.12, 2.0), u * CF(0, 1.66, 0.05), marbleW)
			K:box("CredenzaKick", V3(cz1 - cz0 - 0.4, 0.3, 0.05), u * CF(0, -1.45, 0.88), Look.black)
			for k = 0, 9 do
				local x = -(cz1 - cz0) / 2 + (k + 0.5) * (cz1 - cz0) / 10
				K:box("CredenzaDoor", V3((cz1 - cz0) / 10 - 0.1, 2.6, 0.05), u * CF(x, 0.1, 0.92), lk(rgb(84, 58, 40), M.Wood))
				K:box("CredenzaPull", V3(0.05, 0.6, 0.06), u * CF(x + 1.1, 0.3, 0.96), brassL)
			end
			-- 위 소품: 책 · 꽃병 · LP · 턴테이블 · 위스키 디캔터
			local top = d * CF(0, 3.28, 1.0)
			Props.row(K, top * CF(-11.0, 0, 0) * ANG(0, 0, 0), 4.0, "books", { colors = { rgb(120, 40, 36), rgb(30, 50, 80), rgb(200, 180, 140), rgb(40, 70, 50), rgb(20, 20, 22) }, seed = 3 })
			K:box("Bookend", V3(0.1, 0.9, 0.6), top * CF(-8.8, 0.45, 0), brassL)
			K:vcyl("CredVase", 1.4, 0.7, top * CF(-6.0, 0.7, 0), lk(rgb(30, 60, 80), M.Glass, { t = 0.05 }))
			for k = 0, 2 do
				K:seg("CredBranch", (top * CF(-6.0, 1.3, 0)).Position, (top * CF(-6.0 + (k - 1) * 0.6, 3.0 + k * 0.2, (k - 1) * 0.3)).Position, 0.05, lk(rgb(90, 70, 50), M.Wood))
			end
			K:box("Turntable", V3(1.6, 0.3, 1.3), top * CF(-1.5, 0.15, 0), walnut)
			K:disc("TurntablePlatter", 1.1, 0.05, top * CF(-1.7, 0.33, 0), lk(rgb(20, 20, 22)))
			K:seg("TurntableArm", (top * CF(-0.9, 0.38, -0.4)).Position, (top * CF(-1.4, 0.38, 0.2)).Position, 0.04, Look.chrome)
			for k = 0, 4 do
				K:box("LPSleeve", V3(0.04, 1.0, 1.0), top * CF(0.4 + k * 0.1, 0.5, 0), lk(({ rgb(240, 200, 60), rgb(30, 30, 30), rgb(200, 60, 50), rgb(60, 120, 200), rgb(240, 240, 230) })[k + 1]))
			end
			K:box("WhiskyTray", V3(2.0, 0.05, 1.0), top * CF(4.5, 0.03, 0), brassL)
			K:vcyl("Decanter", 0.8, 0.5, top * CF(4.0, 0.45, 0), lk(rgb(160, 90, 30), M.Glass, { t = 0.3 }))
			K:ball("DecanterStopper", 0.24, top * CF(4.0, 0.95, 0), gl(rgb(230, 230, 230), 0.3))
			for k = 0, 1 do
				K:vcyl("Tumbler", 0.32, 0.3, top * CF(4.8 + k * 0.45, 0.21, 0.1), gl(rgb(230, 236, 240), 0.5))
			end
			K:ell("CredSculpture", V3(0.8, 1.6, 0.8), top * CF(9.0, 0.8, 0), lk(rgb(232, 228, 220), M.Marble))
			K:ell("CredSculpture", V3(0.6, 1.0, 0.6), top * CF(9.6, 0.5, 0.1), lk(rgb(30, 30, 32), M.Marble))
			-- 아트월: 광안대교 야경 대형 그림 + 양옆 작은 그림 2
			artFrame(K, wallR(R, 45.0, 7.6, 0), 12.0, 5.2, {
				{ rgb(10, 14, 34), 0, 0, 1, 1 }, { rgb(20, 34, 70), 0, 0, 1, 0.45 }, { rgb(255, 200, 120), 0, 0.46, 1, 0.025 },
				{ rgb(255, 200, 120), 0.2, 0.48, 0.012, 0.32 }, { rgb(255, 200, 120), 0.62, 0.48, 0.012, 0.32 },
				{ rgb(120, 200, 255), 0, 0.3, 1, 0.012 }, { rgb(255, 120, 200), 0.05, 0.6, 0.3, 0.008 }, { rgb(255, 240, 200), 0.8, 0.82, 0.06, 0.1 },
				{ rgb(40, 60, 110), 0, 0.12, 1, 0.08 }, { rgb(255, 180, 90), 0.0, 0.47, 0.2, 0.01 },
			}, brassL)
			artFrame(K, wallR(R, 34.2, 7.0, 0), 3.6, 4.4, { { rgb(214, 200, 178), 0, 0, 1, 1 }, { rgb(150, 70, 48), 0.15, 0.1, 0.5, 0.55 }, { rgb(36, 54, 86), 0.4, 0.4, 0.45, 0.5 } }, brassL)
			artFrame(K, wallR(R, 55.8, 7.0, 0), 3.6, 4.4, { { rgb(232, 228, 220), 0, 0, 1, 1 }, { rgb(30, 30, 32), 0.2, 0.2, 0.6, 0.06 }, { rgb(200, 160, 90), 0.45, 0.3, 0.1, 0.5 }, { rgb(36, 54, 86), 0.1, 0.65, 0.8, 0.2 } }, brassL)
			-- 그림 조명 바 (긴 픽처 라이트)
			pictureLight(K, wallR(R, 45.0, 7.6 + 2.6, 0), 9.0, false)
		end)
		do
			local aim = K:box("ArtWashAim", V3(0.1, 0.1, 0.1), at(R, 14.0, 45.0, 0, 11.8), lk(BLACK, nil, { t = 1 }))
			aim.CFrame = R.V.cf * CFrame.lookAt(ap(R, 14.0, 11.8, 45.0), ap(R, 20.0, 7.0, 45.0))
			K:light(aim, "SpotLight", { Face = Enum.NormalId.Front, Range = 14, Brightness = 1.2, Angle = 55, Color = WARM })
		end
		-- 러그 + 소파 (크레덴자 앞, -x 를 봄) + 암체어 2 + 커피 테이블 + 플로어 램프
		K:free(function()
			K:box("LibraryRug", V3(12.0, 0.03, 17.0), at(R, 10.6, 45.0, 0, 0.015), lk(rgb(120, 96, 76), M.Fabric))
			K:box("LibraryRugField", V3(10.6, 0.032, 15.6), at(R, 10.6, 45.0, 0, 0.016), lk(rgb(168, 146, 120), M.Fabric))
		end)
		local scf = at(R, 15.0, 45.0, -PI / 2)
		if placeOr(R, scf, V3(9.0, 3.4, 3.0), 0, "library sofa") then
			K:box("LSofaPlinth", V3(8.6, 0.3, 2.6), scf * CF(0, 0.15, 0), Look.black)
			K:rbox("LSofaBase", V3(8.8, 0.8, 2.8), 0.2, scf * CF(0, 0.7, 0), velvetBlue)
			K:rbox("LSofaBack", V3(8.8, 1.7, 0.6), 0.25, scf * CF(0, 1.75, -1.1), velvetBlue)
			for _, sx in { -1, 1 } do
				K:rbox("LSofaArm", V3(0.5, 1.4, 2.8), 0.2, scf * CF(sx * 4.2, 1.15, 0), velvetBlue)
			end
			for k = -1, 1 do
				K:rbox("LSofaCushion", V3(2.6, 0.35, 2.1), 0.15, scf * CF(k * 2.65, 1.25, 0.2), lk(rgb(46, 64, 98), M.Fabric))
			end
			K:ell("LSofaPillow", V3(1.0, 0.9, 0.3), scf * CF(-3.0, 1.85, -0.6) * ANG(math.rad(-15), 0, 0.1), velvetRust)
			K:ell("LSofaPillow", V3(1.0, 0.9, 0.3), scf * CF(3.0, 1.85, -0.6) * ANG(math.rad(-15), 0, -0.1), velvetCream)
		end
		local tcf = at(R, 10.4, 45.0)
		if placeOr(R, tcf, V3(3.4, 1.6, 5.0), 0, "coffee table") then
			K:slab("CoffeeTop", 3.2, 4.8, 0.14, 0.6, tcf * CF(0, 1.35, 0), marbleW)
			K:box("CoffeeBase", V3(2.4, 1.2, 4.0), tcf * CF(0, 0.65, 0), walnut)
			Props.row(K, tcf * CF(-0.6, 1.42, -1.2) * ANG(0, PI / 2, 0), 1.4, "books", { colors = { rgb(30, 30, 32), rgb(200, 180, 140) }, seed = 5, n = 3 })
			K:vcyl("CoffeeBowl", 0.3, 1.1, tcf * CF(0.3, 1.57, 1.0), brassL)
		end
		for _, zc in { 41.0, 49.0 } do
			local pcf = at(R, 6.0, zc, PI / 2)
			if placeOr(R, pcf, V3(2.6, 3.0, 2.6), 0, "library armchair") then
				armchair(K, pcf, velvetRust)
			end
		end
		local fcf = at(R, 16.6, 38.4)
		if placeOr(R, fcf, V3(1.4, 6.4, 1.4), 0, "library floor lamp") then
			K:disc("ArcLampBase", 1.0, 0.1, fcf * CF(0, 0.05, 0), lk(rgb(232, 228, 220), M.Marble))
			K:seg("ArcLampPole", (fcf * CF(0, 0.1, 0)).Position, (fcf * CF(0, 5.9, 0)).Position, 0.08, brassL)
			local sh = K:vcyl("ArcLampShade", 0.9, 1.3, fcf * CF(0, 5.9, 0), lk(rgb(255, 222, 180), M.Neon, { t = 0.12 }))
			K:light(sh, "PointLight", { Range = 13, Brightness = 0.8, Color = WARM })
			table.insert(lampShades, sh)
		end
		-- 화분 (라운지 북쪽)
		plant(K, R, 6.4, 33.0, "monstera", 5.4, 1.6, lk(rgb(40, 38, 36), M.Concrete))
	end
	-- VIP 호스트 데스크 (계단 도착 지점 옆) + 예약 태블릿 (상호작용)
	local tabletLabel: TextLabel? = nil
	local tablet: BasePart? = nil
	do
		local hcf = at(R, 6.0, 63.4, -PI / 2)
		if placeOr(R, hcf, V3(3.4, 4.6, 1.8), 0, "host desk") then
			K:box("HostDeskBody", V3(3.2, 3.6, 1.4), hcf * CF(0, 1.8, 0), walnut)
			K:box("HostDeskFront", V3(3.0, 3.2, 0.05), hcf * CF(0, 1.8, 0.72), lk(rgb(200, 170, 110), M.Metal))
			for k = 0, 6 do
				K:box("HostDeskFlute", V3(0.06, 3.0, 0.06), hcf * CF(-1.35 + k * 0.45, 1.8, 0.76), lk(rgb(150, 120, 70), M.Metal))
			end
			K:box("HostDeskTop", V3(3.4, 0.1, 1.6), hcf * CF(0, 3.65, 0), marbleW)
			txt(K, "HostDeskSign", 2.6, 0.5, hcf * CF(0, 2.8, 0.8), "VIP HOST · RESERVATION", rgb(40, 30, 20), nil, F.GothamBlack)
			local tcf2 = hcf * CF(0.4, 3.7, -0.1)
			K:box("TabletStand", V3(0.3, 0.5, 0.3), tcf2 * CF(0, 0.25, 0), Look.alu)
			tablet = K:box("Tablet", V3(1.2, 0.85, 0.06), tcf2 * CF(0, 0.75, 0.05) * ANG(math.rad(-25), 0, 0), lk(rgb(20, 20, 24)))
			local _, lab = txt(K, "TabletScreen", 1.1, 0.75, tcf2 * CF(0, 0.75, 0.085) * ANG(math.rad(-25), 0, 0), "OCEAN SKY LOUNGE\n오늘의 예약 12건", rgb(220, 236, 255), rgb(20, 40, 80), F.GothamBold, 1.3)
			tabletLabel = lab
			K:box("ReservBook", V3(0.9, 0.12, 1.1), hcf * CF(-0.9, 3.76, 0.1) * ANG(0, 0.2, 0), lk(rgb(30, 30, 34), M.Leather))
			K:vcyl("HostLampBase", 0.5, 0.25, hcf * CF(-1.3, 3.95, -0.3), brassL)
			local hl = K:ell("HostLampShade", V3(0.6, 0.45, 0.6), hcf * CF(-1.3, 4.35, -0.3), Look.lampWarm)
			K:light(hl, "PointLight", { Range = 9, Brightness = 0.7, Color = WARM })
		end
		-- 안내 스탠드 (계단 쪽을 봄)
		local scf = at(R, -7.5, 58.6, 0)
		if placeOr(R, scf, V3(1.4, 5.0, 1.0), 0, "welcome stand") then
			K:disc("WelcomeBase", 1.0, 0.08, scf * CF(0, 0.04, 0), brassL)
			K:vcyl("WelcomePole", 3.0, 0.08, scf * CF(0, 1.55, 0), brassL)
			K:box("WelcomeBoard", V3(1.6, 2.2, 0.08), scf * CF(0, 3.9, 0) * ANG(math.rad(-6), 0, 0), lk(rgb(20, 20, 22)))
			txt(K, "WelcomeText", 1.45, 2.0, scf * CF(0, 3.9, 0.05) * ANG(math.rad(-6), 0, 0), "WELCOME TO\nOCEAN SKY\nLOUNGE\n\n2F · VIP\n칵테일 18,000~\n샴페인 BTL 280,000~", rgb(240, 220, 180), nil, F.GothamBold, 1.1)
		end
	end
	-- 바 백바 병 (맵: 네모 유리 상자 149개) 위에 목 + 마개를 얹어 진짜 술병 실루엣으로 (각진 위스키 병처럼 보임)
	K:free(function()
		local CAPS = { rgb(24, 22, 20), rgb(196, 160, 80), rgb(120, 24, 30), rgb(190, 192, 196), rgb(24, 22, 20), rgb(40, 60, 40) }
		for i, r in V.byName.Bottle or {} do
			local mn, mx = abox(R, r)
			local w = math.min(mx.X - mn.X, mx.Z - mn.Z)
			if w > 0.2 and w < 0.9 and mx.Y - mn.Y > 0.6 then
				local c = (mn + mx) / 2
				local nh = 0.3 + (i % 3) * 0.08
				K:vcyl("BottleNeck", nh, 0.16, at(R, c.X, c.Z, 0, mx.Y + nh / 2), lk(CAPS[i % #CAPS + 1], if i % 4 == 1 then M.Metal else M.SmoothPlastic))
			end
		end
	end)
	-- 오른벽 남쪽 (DJ 와 셀러 사이) 작은 액자 · 바 끝 메뉴 스탠드 --------------------------------------------------
	K:free(function()
		artFrame(K, wallR(R, -74.0, 6.6, 0), 4.0, 5.0, { { rgb(16, 20, 40), 0, 0, 1, 1 }, { rgb(80, 150, 255), 0.1, 0.4, 0.8, 0.05 }, { rgb(255, 120, 200), 0.3, 0.55, 0.4, 0.05 }, { rgb(240, 240, 255), 0.45, 0.7, 0.1, 0.15 } }, brassL)
		Props.menuBoard(K, wallR(R, -26.5, 6.0, 0), 4.6, 4.0, "SIGNATURE COCKTAILS", {
			{ "광안 선셋 하이볼", "16,000" }, { "OCEAN BLUE 마티니", "19,000" }, { "유자 모히또", "17,000" }, { "블랙 오션 올드패션드", "22,000" }, { "논알콜 스파클링", "12,000" }, { "샴페인 GLASS", "28,000" },
		}, { bg = rgb(18, 16, 14), fg = rgb(240, 228, 206), accent = rgb(214, 180, 110), frame = brassL, cols = 1, glow = 1.15 })
	end)

	-- 상호작용 ---------------------------------------------------------------------------------------
	-- 1) 커튼 치기 / 걷기 (시어 커튼)
	if #sheers > 0 then
		local trig: BasePart? = nil
		K:free(function()
			local mid = stackZ[math.max(1, math.floor(#stackZ / 2))]
			trig = K:box("CurtainPull", V3(0.12, 1.6, 0.12), at(R, x0 + 1.0, mid + 1.0, 0, 3.8), brassL)
			K:ball("CurtainPullKnob", 0.22, at(R, x0 + 1.0, mid + 1.0, 0, 2.95), brassL)
		end)
		prompt(R, trig, "toggle", {
			object = "창가 시어 커튼",
			onText = "커튼 걷기",
			offText = "커튼 치기",
			state = false,
			on = function(s: boolean)
				for _, p in sheers do
					tween(p, { Transparency = if s then 0.45 else 1 }, 0.8)
				end
			end,
		})
	end
	-- 2) DJ 콘솔: 무드 조명 바꾸기
	if mixer then
		local MOODS = {
			{ "CHAMPAGNE", rgb(255, 204, 150) },
			{ "OCEAN BLUE", rgb(80, 160, 255) },
			{ "SUNSET", rgb(255, 120, 80) },
			{ "MIDNIGHT", rgb(150, 90, 255) },
		}
		local lights: { Light } = {}
		for _, p in moodParts do
			for _, c in p:GetChildren() do
				if c:IsA("Light") then
					table.insert(lights, c)
				end
			end
		end
		prompt(R, mixer, "cycle", {
			action = "무드 조명 바꾸기",
			object = "DJ 콘솔",
			on = function(_i, it)
				for _, p in moodParts do
					if p.Parent then
						tween(p, { Color = it[2] }, 0.6)
					end
				end
				for _, l in lights do
					(l :: any).Color = it[2]
				end
			end,
		}, MOODS)
	end
	-- 3) VIP 예약 태블릿
	if tablet and tabletLabel then
		local PAGES = {
			"OCEAN SKY LOUNGE\n오늘의 예약 12건",
			"21:00  김** 님 · 4명\n창가 3번 소파 · 샴페인",
			"22:30  이** 님 · 2명\n2인 테이블 · 생일 케이크",
			"23:30  박** 님 · 6명\n라이브러리 라운지",
			"대기 3팀 · 예상 20분\n워크인 문의는 호스트에게",
		}
		prompt(R, tablet, "cycle", {
			action = "예약 확인",
			object = "VIP 호스트 태블릿",
			on = function(_i, it)
				(tabletLabel :: TextLabel).Text = it
			end,
		}, PAGES)
	end
	-- 4) 망원경: 광안대교 쪽으로 돌려 보기
	if scope and scopePivot then
		local parts = {}
		for _, d in (scope :: Model):GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, { p = d, cf = d.CFrame })
			end
		end
		local pivot = R.V.cf * (scopePivot :: Vector3)
		local step = 0
		local INFO = { "광안대교 VIEW\n야경 조명 20:00-24:00", "광안대교 · 7.4km\n복층 현수교 · 2003", "수영만 요트 경기장\n마린시티 스카이라인", "광안리 해수욕장\n드론쇼 토요일 20:00" }
		prompt(R, parts[1] and parts[1].p or nil, "prompt", {
			action = "망원경 보기",
			object = "오션뷰 망원경",
			fn = function()
				step = step % 4 + 1
				local rot = CF(pivot) * CFrame.fromAxisAngle(R.V.cf:VectorToWorldSpace(V3(0, 1, 0)), (step - 1) * 0.28 - 0.42) * CF(-pivot)
				for _, r in parts do
					tween(r.p, { CFrame = rot * r.cf }, 0.6)
				end
				if scopeLabel then
					(scopeLabel :: TextLabel).Text = INFO[step]
				end
			end,
		})
	end
	local _lamp = lampToggle
end

--=====================================================================================================
-- OCEAN ROOFTOP (rooftop) ---------------------------------------------------------------------------
--=====================================================================================================
-- 삼각형 판 (꼭짓점 A, 밑변 B-C, 방 프레임 점): A 에서 BC 로 내린 수선의 발 M 으로 나눈 직각 쐐기 2개
local function triPanel(K: any, name: string, A: Vector3, B: Vector3, C: Vector3, t: number, look: any)
	local bc = C - B
	local L = bc.Magnitude
	if L < 1e-3 then
		return
	end
	local u = bc / L
	local M = B + u * (A - B):Dot(u)
	local up = A - M
	local h = up.Magnitude
	if h < 1e-3 then
		return
	end
	local Y = up / h
	for _, P in { B, C } do
		local leg = P - M
		local d = leg.Magnitude
		if d > 1e-3 then
			local Z = -leg / d
			local X = Y:Cross(Z)
			local pos = M + Y * (h / 2) - Z * (d / 2)
			K:make("WedgePart", name, V3(t, h, d), CFrame.fromMatrix(pos, X, Y, Z), look)
		end
	end
end

-- 파라솔 (8각 캔버스 판 + 살 8 + 가장자리 전구 8). 정렬 x, z, 반지름, 높이
local function parasol(K: any, R: any, x: number, z: number, r: number, h: number, c: Color3, bulbs: { BasePart }?)
	local base = at(R, x, z)
	K:disc("ParasolBase", 1.4, 0.3, base * CF(0, 0.15, 0), lk(rgb(40, 40, 42), M.Concrete))
	K:vcyl("ParasolPole", h - 0.2, 0.18, base * CF(0, (h - 0.2) / 2 + 0.25, 0), lk(rgb(220, 214, 200), M.Wood))
	local apex = (base * CF(0, h + 0.35, 0)).Position
	for k = 0, 7 do
		local a0, a1 = k * PI / 4, (k + 1) * PI / 4
		local p0 = (base * CF(math.cos(a0) * r, h - 0.45, math.sin(a0) * r)).Position
		local p1 = (base * CF(math.cos(a1) * r, h - 0.45, math.sin(a1) * r)).Position
		triPanel(K, "ParasolPanel", apex, p0, p1, 0.04, lk(if k % 2 == 0 then c else lt(c, 0.12), M.Fabric))
	end
	K:ball("ParasolFinial", 0.3, base * CF(0, h + 0.4, 0), lk(rgb(220, 214, 200), M.Wood))
	for k = 0, 7 do
		local a = k * PI / 4
		K:seg("ParasolRib", (base * CF(0, h - 0.9, 0)).Position, (base * CF(math.cos(a) * r * 0.97, h - 0.5, math.sin(a) * r * 0.97)).Position, 0.06, lk(rgb(220, 214, 200), M.Wood))
		local b = K:ball("ParasolBulb", 0.22, base * CF(math.cos(a + PI / 8) * r * 0.82, h - 0.75, math.sin(a + PI / 8) * r * 0.82), Look.lampWarm)
		if bulbs then
			table.insert(bulbs, b)
		end
	end
	K:ring("ParasolValance", base * CF(0, h - 0.55, 0) * ANG(PI / 2, 0, 0), r * 0.97, 0.12, 8, lk(rgb(240, 236, 226), M.Fabric))
end

-- 바닥 랜턴 (검은 철 + 유리 + 촛불 빛). pcf 바닥
local function lantern(K: any, pcf: CFrame, h: number, glows: { BasePart }?)
	local w = h * 0.42
	K:box("LanternBase", V3(w + 0.1, 0.12, w + 0.1), pcf * CF(0, 0.06, 0), Look.blackMetal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K:box("LanternPost", V3(0.07, h * 0.78, 0.07), pcf * CF(sx * w / 2, 0.12 + h * 0.39, sz * w / 2), Look.blackMetal)
		end
	end
	K:box("LanternGlass", V3(w - 0.05, h * 0.74, w - 0.05), pcf * CF(0, 0.14 + h * 0.37, 0), gl(rgb(255, 236, 210), 0.65))
	local g = K:vcyl("LanternCandle", h * 0.28, w * 0.4, pcf * CF(0, 0.12 + h * 0.14, 0), Look.lampWarm)
	if glows then
		table.insert(glows, g)
	end
	K:wedge("LanternRoofA", V3(w + 0.2, h * 0.14, (w + 0.2) / 2), pcf * CF(0, 0.12 + h * 0.85, -(w + 0.2) / 4) * ANG(0, PI, 0), Look.blackMetal)
	K:wedge("LanternRoofB", V3(w + 0.2, h * 0.14, (w + 0.2) / 2), pcf * CF(0, 0.12 + h * 0.85, (w + 0.2) / 4), Look.blackMetal)
	K:ring("LanternHandle", pcf * CF(0, 0.12 + h * 0.95, 0), w * 0.3, 0.05, 6, Look.blackMetal, 0, PI)
end

local function buildRooftop(K: any, V: any, R: any)
	local x0, x1, z0, z1 = R.x0, R.x1, R.z0, R.z1
	local WARM = rgb(255, 204, 150)
	local teak = lk(rgb(150, 104, 64), M.Wood)
	local whiteWood = lk(rgb(232, 226, 214), M.Wood)
	local rope = lk(rgb(214, 196, 160), M.Fabric)
	local cushion = lk(rgb(232, 226, 212), M.Fabric)
	-- 비울 곳 ------------------------------------------------------------------------------------------
	keepBox(R, 19.5, 49.5, 25.0, 59.5, 9, "door") -- 라운지 문
	keepBox(R, 3.0, 49.5, 19.5, 59.5, 6.8, "lane") -- 문 -> 가운데 산책로
	keepBox(R, -7.0, -46.0, 3.0, 70.0, 6.8, "promenade") -- 가운데 산책로 (히터 줄)
	keepBox(R, 3.0, -46.0, 14.8, -41.0, 6.5, "lane") -- 산책로 -> 바
	keepBox(R, 10.5, -70.0, 13.6, -45.0, 6.5, "bar front")
	keepBox(R, -15.6, -38.0, -13.6, 63.0, 6.5, "daybed front")
	-- 데이베드 · 소파 위치 (맵에서)
	local daybeds = {}
	for _, r in V.byName.DaybedBase or {} do
		local mn, mx = abox(R, r)
		table.insert(daybeds, { x0 = mn.X, x1 = mx.X, z0 = mn.Z, z1 = mx.Z })
	end
	table.sort(daybeds, function(a, b)
		return a.z0 < b.z0
	end)

	local moodParts: { BasePart } = {}
	local glows: { BasePart } = {}

	-- 1) 루프탑 바: 퍼걸러 · 백바 2 + 헤더 선반 · 탭 · POS · 아이스웰 · 스툴 · 메뉴 ------------------------------------
	local bz0, bz1 = -67.5, -47.5
	do
		-- 퍼걸러 기둥 4 + 보 + 살
		local px0, px1 = 15.7, 25.9
		local pz0, pz1 = bz0 - 2.6, bz1 + 2.6
		local okP = true
		for _, p in { { px0, pz0 }, { px0, pz1 }, { px1, pz0 }, { px1, pz1 } } do
			if not place(R, at(R, p[1], p[2]), V3(0.5, 9.6, 0.5), 0, "pergola post") then
				okP = false
				K:note("pergola post blocked " .. tostring(R.why))
			end
		end
		if okP then
			K:free(function()
				for _, p in { { px0, pz0 }, { px0, pz1 }, { px1, pz0 }, { px1, pz1 } } do
					K:box("PergolaPost", V3(0.45, 9.6, 0.45), at(R, p[1], p[2], 0, 4.8), teak)
					K:box("PergolaFoot", V3(0.7, 0.2, 0.7), at(R, p[1], p[2], 0, 0.1), Look.blackMetal)
				end
				for _, x in { px0, px1 } do
					K:box("PergolaBeam", V3(0.4, 0.7, pz1 - pz0 + 1.0), at(R, x, (pz0 + pz1) / 2, 0, 9.85), teak)
				end
				for k = 0, 12 do
					local z = pz0 - 0.2 + k * (pz1 - pz0 + 0.4) / 12
					K:box("PergolaSlat", V3(px1 - px0 + 1.0, 0.35, 0.22), at(R, (px0 + px1) / 2, z, 0, 10.35), teak)
				end
			end)
			-- 펜던트 3 (바 위, 퍼걸러에 매달림)
			K:free(function()
				for k = 0, 2 do
					local z = bz0 + 3.5 + k * 6.5
					local px = 19.0
					K:seg("BarPendantCord", ap(R, px, 10.2, z), ap(R, px, 8.6, z), 0.04, Look.black)
					K:vcyl("BarPendantShade", 0.7, 1.0, at(R, px, z, 0, 8.25), lk(rgb(40, 40, 42), M.Metal))
					local b = K:ell("BarPendantBulb", V3(0.4, 0.5, 0.4), at(R, px, z, 0, 7.85), Look.lampWarm)
					if k == 1 then
						K:light(b, "PointLight", { Range = 16, Brightness = 1.0, Color = WARM })
					end
				end
			end)
		end
		-- 바 앞면 라탄 패널 (카운터 앞 x 16.0)
		K:free(function()
			local fd = face(R, 15.98, 2.0, (bz0 + bz1) / 2, -PI / 2)
			K:plate("BarFrontRattan", bz1 - bz0 - 0.2, 3.0, 0.04, fd, lk(rgb(196, 160, 110), M.Fabric))
			for k = 0, 9 do
				K:plate("BarFrontRib", 0.12, 3.0, 0.06, fd * CF(-(bz1 - bz0) / 2 + 1.0 + k * 2.0, 0, 0), teak)
			end
		end)
		-- 백바 구간 2 (바텐더 자리 비움): z -67.4..-61.6 , -53.4..-47.6
		local backL: BasePart? = nil
		for si, seg in { { -67.4, -61.6 }, { -53.4, -47.6 } } do
			local zc = (seg[1] + seg[2]) / 2
			local len = seg[2] - seg[1]
			local u = at(R, 25.55, zc)
			if placeOr(R, u, V3(1.4, 7.6, len), 0, "back bar") then
				K:box("BackBarBody", V3(1.3, 3.3, len), u * CF(0, 1.65, 0), lk(rgb(40, 34, 30), M.Wood))
				K:box("BackBarTop", V3(1.4, 0.1, len + 0.1), u * CF(0, 3.35, 0), Look.steel)
				for k = 0, 2 do
					K:box("BackBarDoor", V3(0.05, 2.7, len / 3 - 0.12), u * CF(-0.66, 1.75, -len / 2 + (k + 0.5) * len / 3), lk(rgb(56, 46, 40), M.Wood))
				end
				-- 위 유리 선반 2 + 라벨 병
				for row = 0, 1 do
					local y = 4.6 + row * 1.5
					K:box("BackBarShelf", V3(1.0, 0.06, len), u * CF(0.1, y, 0), gl(rgb(220, 230, 236), 0.4))
					local n = math.floor(len / 0.55)
					for k = 0, n - 1 do
						local bzz = -len / 2 + (k + 0.5) * len / n
						local hgt = 0.9 + rnd(si * 7 + row, k) * 0.3
						local col = ({ rgb(120, 70, 30), rgb(30, 90, 50), rgb(200, 200, 210), rgb(90, 30, 20), rgb(220, 170, 60), rgb(40, 40, 60) })[(k + row + si) % 6 + 1]
						local bc = u * CF(0.05, y + 0.03, bzz)
						K:vcyl("BackBarBottle", hgt * 0.65, 0.32, bc * CF(0, hgt * 0.33, 0), lk(col, M.Glass, { t = 0.2 }))
						K:vcyl("BackBarNeck", hgt * 0.3, 0.12, bc * CF(0, hgt * 0.8, 0), lk(col, M.Glass, { t = 0.2 }))
						if hi(K) then
							K:plate("BackBarLabel", 0.22, 0.24, 0.01, face(R, 25.6 - 0.17, y + 0.03 + hgt * 0.3, zc + bzz, -PI / 2), lk(rgb(240, 232, 214)))
						end
					end
				end
				K:box("BackBarBack", V3(0.08, 4.2, len), u * CF(0.62, 5.45, 0), lk(rgb(30, 26, 22), M.Wood))
				local led = K:box("BackBarLED", V3(0.05, 3.8, 0.06), u * CF(0.55, 5.4, -len / 2 + 0.1), Look.lampWarm)
				K:box("BackBarLED", V3(0.05, 3.8, 0.06), u * CF(0.55, 5.4, len / 2 - 0.1), Look.lampWarm)
				if si == 1 then
					backL = led
				end
				local tcf = u * CF(-0.1, 3.4, 0)
				if si == 1 then
					-- 생맥주 탭 타워 3
					K:box("TapTower", V3(0.4, 1.4, 1.8), tcf * CF(0, 0.7, 0), Look.chrome)
					for k = -1, 1 do
						K:box("TapHandle", V3(0.14, 0.9, 0.14), tcf * CF(-0.3, 1.25, k * 0.55), lk(({ rgb(240, 200, 40), rgb(30, 120, 60), rgb(200, 40, 40) })[k + 2]))
						K:box("TapSpout", V3(0.25, 0.08, 0.08), tcf * CF(-0.3, 0.8, k * 0.55), Look.chrome)
					end
					txt(K, "TapLabel", 1.8, 0.34, face(R, 24.86, 2.9, zc, -PI / 2), "생맥주 · 수제 IPA · 하이볼", WHITE, rgb(20, 20, 20), F.GothamBold)
					K:box("GlassRack", V3(1.0, 0.4, 1.8), tcf * CF(0, 0.2, 2.0), Look.steel)
					for k = 0, 5 do
						K:vcyl("RackGlass", 0.5, 0.3, tcf * CF(-0.25 + (k % 2) * 0.5, 0.65, 1.4 + math.floor(k / 2) * 0.5), gl(rgb(230, 236, 240), 0.55))
					end
				else
					-- POS + 영수증 프린터 + 카드 단말기
					K:box("POSStand", V3(0.3, 0.6, 0.3), tcf * CF(0, 0.3, -1.6), Look.alu)
					K:box("POSScreen", V3(0.08, 0.9, 1.3), tcf * CF(-0.1, 0.95, -1.6) * ANG(0, 0, 0.25), lk(rgb(20, 20, 24)))
					K:box("POSDisplay", V3(0.02, 0.8, 1.2), tcf * CF(-0.15, 0.95, -1.6) * ANG(0, 0, 0.25), nl(rgb(60, 140, 220)))
					K:box("ReceiptPrinter", V3(0.6, 0.45, 0.6), tcf * CF(0, 0.22, -0.7), lk(rgb(40, 40, 44)))
					K:box("CardTerminal", V3(0.4, 0.14, 0.7), tcf * CF(0, 0.07, 0.1), lk(rgb(40, 40, 44)))
					K:vcyl("TipJar", 0.6, 0.42, tcf * CF(0, 0.3, 1.0), gl(rgb(230, 240, 240), 0.5))
					K:box("CitrusTray", V3(0.8, 0.12, 1.4), tcf * CF(0, 0.06, 2.1), Look.steel)
					for k = 0, 3 do
						K:ball("Lime", 0.3, tcf * CF(-0.2 + (k % 2) * 0.35, 0.25, 1.7 + math.floor(k / 2) * 0.5), lk(if k % 2 == 0 then rgb(120, 190, 60) else rgb(250, 210, 40)))
					end
				end
			end
		end
		if backL then
			K:light(backL :: BasePart, "SurfaceLight", { Face = Enum.NormalId.Left, Range = 8, Brightness = 0.9, Angle = 150, Color = WARM })
		end
		-- 헤더 선반 (바텐더 머리 위, 두 백바 사이 전체) + 간판
		K:free(function()
			local hz = (bz0 + bz1) / 2
			local h = at(R, 25.55, hz, 0, 6.8)
			K:box("BackBarHeader", V3(1.3, 0.9, 19.8), h, lk(rgb(30, 26, 22), M.Wood))
			K:box("BackBarHeaderLED", V3(0.05, 0.06, 19.6), h * CF(-0.66, -0.4, 0), nl(WARM))
			txt(K, "BackBarSign", 9.0, 0.7, face(R, 24.88, 6.85, hz, -PI / 2), "OCEAN ROOFTOP BAR · 광안리", rgb(255, 214, 160), nil, F.GothamBlack, 1.6)
		end)
		-- 아이스웰 + 스피드레일 (카운터 안쪽 끝)
		K:free(function()
			for _, zc in { -64.5, -50.0 } do
				local ic = at(R, 22.55, zc, 0, 2.9)
				K:box("IceWell", V3(1.1, 1.0, 3.0), ic, Look.steel)
				K:box("IceWellIce", V3(0.9, 0.05, 2.8), ic * CF(0, 0.48, 0), lk(rgb(236, 244, 250), M.Ice))
				K:box("SpeedRail", V3(0.3, 0.5, 3.0), ic * CF(0.7, -0.25, 0), Look.steel)
				for k = 0, 4 do
					K:vcyl("RailBottle", 1.0, 0.28, ic * CF(0.7, 0.25, -1.2 + k * 0.6), lk(({ rgb(220, 220, 230), rgb(140, 80, 30), rgb(30, 90, 50) })[k % 3 + 1], M.Glass, { t = 0.2 }))
				end
			end
		end)
		-- 스툴 6 (카운터 앞)
		for k = 0, 5 do
			local z = bz0 + 1.6 + k * 3.35
			local sp = at(R, 14.6, z)
			if place(R, sp, V3(1.2, 3.0, 1.2), 0, "bar stool") then
				barStool(K, sp, 2.8, lk(rgb(196, 160, 110), M.Fabric), teak)
			end
		end
		-- 바 위 매달린 라이트박스 메뉴 (장식) + 바닥 메뉴 스탠드 (상호작용)
		K:free(function()
			local md = face(R, 15.55, 8.6, (bz0 + bz1) / 2, -PI / 2)
			K:plate("HangMenuBox", 6.0, 1.6, 0.3, md, Look.black)
			txt(K, "HangMenuText", 5.7, 1.3, md * CF(0, 0, 0.31), "HIGHBALL 13,000 · DRAFT 9,000 · COCKTAIL 16,000", rgb(255, 230, 190), nil, F.GothamBold, 1.5)
			for _, sx in { -1, 1 } do
				K:seg("HangMenuChain", (md * CF(sx * 2.6, 0.8, 0.15)).Position, ap(R, 15.7, 9.5, (bz0 + bz1) / 2 + sx * 2.6), 0.04, Look.chrome)
			end
		end)
	end
	local menuLabel: TextLabel? = nil
	local menuPart: BasePart? = nil
	do
		local mx, mz = 4.6, -39.4
		local scf = at(R, mx, mz, 0)
		if placeOr(R, scf, V3(2.0, 4.6, 1.6), 0, "menu stand") then
			K:box("MenuStandFootA", V3(1.8, 0.1, 0.12), scf * CF(0, 0.05, -0.6), Look.blackMetal)
			K:box("MenuStandFootB", V3(1.8, 0.1, 0.12), scf * CF(0, 0.05, 0.6), Look.blackMetal)
			for _, sx in { -1, 1 } do
				K:seg("MenuStandLeg", ap(R, mx - sx * 0.85, 0.1, mz + 0.6), ap(R, mx - sx * 0.85, 4.2, mz), 0.08, teak)
				K:seg("MenuStandLeg", ap(R, mx - sx * 0.85, 0.1, mz - 0.6), ap(R, mx - sx * 0.85, 4.2, mz), 0.08, teak)
			end
			menuPart = K:box("MenuStandBoard", V3(1.7, 3.0, 0.08), scf * CF(0, 2.3, 0.3) * ANG(math.rad(10), 0, 0), lk(rgb(26, 30, 28)))
			local _, lab = txt(K, "MenuStandText", 1.55, 2.8, scf * CF(0, 2.3, 0.35) * ANG(math.rad(10), 0, 0), "TODAY'S BAR\n\n하이볼 2+1\n19:00 - 21:00\n\n← 메뉴 넘기기", rgb(250, 246, 236), nil, F.PermanentMarker)
			menuLabel = lab
		end
	end

	-- 2) DJ 코너 (동쪽 끝 가운데): 플라이트 케이스 부스 + 스탠드 스피커 2 + 서브 ----------------------------------------
	local djKnob: BasePart? = nil
	do
		local xc, zc = -4.0, z0 + 4.4
		local b = at(R, xc, zc)
		if placeOr(R, b, V3(7.4, 4.2, 2.2), 0, "rooftop dj") then
			K:box("RTDJCase", V3(7.0, 3.2, 1.8), b * CF(0, 1.6, 0), lk(rgb(26, 26, 28), M.DiamondPlate))
			for _, y in { 0.06, 3.14 } do
				K:box("RTDJEdge", V3(7.04, 0.1, 1.84), b * CF(0, y, 0), Look.alu)
			end
			for _, sx in { -1, 1 } do
				K:box("RTDJCorner", V3(0.14, 3.2, 0.14), b * CF(sx * 3.45, 1.6, 0.86), Look.chrome)
			end
			local led = K:box("RTDJLED", V3(6.6, 0.1, 0.05), b * CF(0, 2.6, 0.92), nl(rgb(60, 200, 255)))
			table.insert(moodParts, led)
			txt(K, "RTDJText", 4.4, 0.8, b * CF(0, 1.5, 0.92), "OCEAN ROOFTOP · SUNSET SESSION", rgb(255, 230, 200), nil, F.GothamBlack, 1.3)
			local top = b * CF(0, 3.25, -0.2)
			for _, sx in { -1, 1 } do
				K:box("RTCDJ", V3(1.3, 0.24, 1.5), top * CF(sx * 1.6, 0.12, 0), lk(rgb(24, 24, 26)))
				K:disc("RTCDJWheel", 0.95, 0.05, top * CF(sx * 1.6, 0.27, 0.15), lk(rgb(60, 62, 66), M.Metal))
			end
			djKnob = K:box("RTMixer", V3(1.1, 0.26, 1.4), top * CF(0, 0.13, 0), lk(rgb(30, 30, 32)))
			for k = 0, 3 do
				K:box("RTFader", V3(0.06, 0.04, 0.4), top * CF(-0.36 + k * 0.24, 0.28, 0.3), Look.chrome)
			end
			K:box("RTLaptop", V3(1.2, 0.8, 0.03), top * CF(2.9, 0.7, -0.4) * ANG(math.rad(-15), 0, 0), Look.alu)
			local djl = K:box("RTDJLight", V3(0.1, 0.1, 0.1), b * CF(0, 6.5, 1.5), lk(BLACK, nil, { t = 1 }))
			K:light(djl, "PointLight", { Range = 14, Brightness = 0.9, Color = rgb(120, 160, 255) })
		end
		for _, sx in { -1, 1 } do
			local sc = at(R, xc + sx * 4.8, zc + 0.4)
			if placeOr(R, sc, V3(1.8, 6.4, 1.8), 0, "rooftop speaker") then
				K:box("RTSub", V3(1.7, 1.6, 1.7), sc * CF(0, 0.8, 0), lk(rgb(24, 24, 26)))
				K:disc("RTSubCone", 1.2, 0.04, sc * CF(0, 0.8, 0.87) * ANG(PI / 2, 0, 0), lk(rgb(40, 40, 44), M.DiamondPlate))
				K:vcyl("RTSpkPole", 2.2, 0.12, sc * CF(0, 2.7, 0), Look.blackMetal)
				local body = sc * CF(0, 4.9, 0) * ANG(0, -sx * 0.25, 0)
				K:box("RTTop", V3(1.4, 2.2, 1.2), body, lk(rgb(24, 24, 26)))
				K:box("RTTopGrille", V3(1.3, 2.1, 0.03), body * CF(0, 0, 0.61), lk(rgb(46, 46, 50), M.DiamondPlate))
			end
		end
	end

	-- 3) 데이베드 카바나 (기둥 4 + 지붕 천 + 묶은 커튼) + 랜턴 ------------------------------------------------------
	local cabanaCurtains: { BasePart } = {}
	for di, d in daybeds do
		local cx0, cx1 = d.x0 - 0.45, d.x1 + 0.45
		local cz0, cz1 = d.z0 - 0.45, d.z1 + 0.45
		local ok = true
		for _, p in { { cx0, cz0 }, { cx0, cz1 }, { cx1, cz0 }, { cx1, cz1 } } do
			if not place(R, at(R, p[1], p[2]), V3(0.36, 8.4, 0.36), 0, "cabana post") then
				ok = false
			end
		end
		if ok then
			K:free(function()
				for _, p in { { cx0, cz0 }, { cx0, cz1 }, { cx1, cz0 }, { cx1, cz1 } } do
					K:box("CabanaPost", V3(0.32, 8.4, 0.32), at(R, p[1], p[2], 0, 4.2), whiteWood)
				end
				for _, z in { cz0, cz1 } do
					K:box("CabanaBeam", V3(cx1 - cx0 + 0.3, 0.3, 0.3), at(R, (cx0 + cx1) / 2, z, 0, 8.35), whiteWood)
				end
				for _, x in { cx0, cx1 } do
					K:box("CabanaBeam", V3(0.3, 0.3, cz1 - cz0 + 0.3), at(R, x, (cz0 + cz1) / 2, 0, 8.35), whiteWood)
				end
				K:box("CabanaRoof", V3(cx1 - cx0, 0.06, cz1 - cz0), at(R, (cx0 + cx1) / 2, (cz0 + cz1) / 2, 0, 8.55), lk(rgb(246, 242, 232), M.Fabric))
				K:box("CabanaValance", V3(cx1 - cx0 + 0.4, 0.6, 0.06), at(R, (cx0 + cx1) / 2, cz1 + 0.15, 0, 8.1), lk(rgb(246, 242, 232), M.Fabric))
				K:box("CabanaValance", V3(cx1 - cx0 + 0.4, 0.6, 0.06), at(R, (cx0 + cx1) / 2, cz0 - 0.15, 0, 8.1), lk(rgb(246, 242, 232), M.Fabric))
				-- 묶은 커튼 (기둥마다)
				for _, p in { { cx0, cz0 }, { cx0, cz1 }, { cx1, cz0 }, { cx1, cz1 } } do
					K:ell("CabanaDrape", V3(0.7, 7.6, 0.7), at(R, p[1] + (if p[1] > -20 then -0.35 else 0.35), p[2], 0, 4.3), lk(rgb(246, 242, 232), M.Fabric, { t = 0.1 }))
					K:box("CabanaTie", V3(0.75, 0.12, 0.75), at(R, p[1] + (if p[1] > -20 then -0.35 else 0.35), p[2], 0, 3.4), rope)
				end
				-- 앞 커튼 (닫힘 상태, 처음엔 안 보임)
				if di == 3 then
					for _, z in { cz0 + (cz1 - cz0) * 0.25, cz0 + (cz1 - cz0) * 0.75 } do
						local cp = K:box("CabanaCurtain", V3(0.06, 7.8, (cz1 - cz0) / 2 - 0.1), at(R, cx1 - 0.05, z, 0, 4.2), lk(rgb(246, 242, 232), M.Fabric, { t = 1 }))
						table.insert(cabanaCurtains, cp)
					end
				end
			end)
		end
		-- 랜턴 2 (데이베드 앞 모서리)
		for _, z in { d.z0 + 0.6, d.z1 - 0.6 } do
			local lc = at(R, d.x1 + 0.7, z)
			if place(R, lc, V3(1.0, 2.2, 1.0), 0, "lantern") then
				lantern(K, lc, 2.0, glows)
			end
		end
		-- 사이드 테이블 (데이베드 바다 쪽 끝 사이, 쿠션 톤)
	end
	-- 랜턴 빛 (가운데 카바나)
	if glows[5] then
		K:light(glows[5], "PointLight", { Range = 12, Brightness = 0.8, Color = WARM })
	end

	-- 4) 바다 쪽 난간: 데이베드 사이마다 레일 바 레지 + 스툴 2, 망원경 1 ---------------------------------------------
	local binoc: Model? = nil
	local binocPivot: Vector3? = nil
	local binocLabel: TextLabel? = nil
	for i = 1, #daybeds - 1 do
		local g0, g1 = daybeds[i].z1 + 1.4, daybeds[i + 1].z0 - 1.4
		local gz = (g0 + g1) / 2
		-- 레지 (난간 안쪽 브래킷)
		K:free(function()
			local lz0, lz1 = g0 + 0.4, g1 - 0.4
			if i == 2 then
				lz1 = gz - 1.2
			end
			local lc = at(R, x0 + 0.55, (lz0 + lz1) / 2, 0, 3.5)
			K:box("RailLedgeTop", V3(1.1, 0.14, lz1 - lz0), lc, teak)
			K:box("RailLedgeLED", V3(0.05, 0.05, lz1 - lz0 - 0.2), lc * CF(0.5, -0.1, 0), nl(WARM))
			for k = 0, 2 do
				local z = lz0 + 0.4 + k * (lz1 - lz0 - 0.8) / 2
				K:bar("RailLedgeBracket", ap(R, x0 + 0.1, 2.4, z), ap(R, x0 + 0.95, 3.42, z), 0.08, 0.08, Look.blackMetal)
			end
		end)
		local nst = if i == 2 then 1 else 2
		for k = 1, nst do
			local z = if nst == 1 then gz - 3.0 else gz + (k - 1.5) * 3.0
			local sp = at(R, x0 + 1.9, z)
			if place(R, sp, V3(1.2, 3.0, 1.2), 0, "rail stool") then
				barStool(K, sp, 2.75, cushion, teak)
			end
		end
		if i == 2 and not binoc then
			-- 동전 망원경 (광안리 해변 그 노랑 망원경)
			local bc = at(R, x0 + 1.3, gz + 2.2)
			if placeOr(R, bc, V3(1.6, 5.4, 1.6), 0, "binoculars") then
				K:disc("BinoBase", 1.3, 0.12, bc * CF(0, 0.06, 0), lk(rgb(40, 120, 130), M.Metal))
				K:vcyl("BinoPost", 3.4, 0.36, bc * CF(0, 1.8, 0), lk(rgb(40, 120, 130), M.Metal))
				K:box("BinoCoinBox", V3(0.6, 0.7, 0.5), bc * CF(0.32, 3.0, 0), lk(rgb(40, 120, 130), M.Metal))
				txt(K, "BinoCoinText", 0.5, 0.3, face(R, x0 + 1.63, 3.05, gz + 2.2, PI / 2), "500원", WHITE, nil, F.GothamBlack)
				binocPivot = (bc * CF(0, 3.9, 0)).Position
				binoc = K:group("RooftopBinoculars", function()
					local hcf = bc * CF(0, 4.1, 0) * ANG(0, -PI / 2 - 0.35, 0)
					K:box("BinoHead", V3(1.3, 0.7, 0.9), hcf, lk(rgb(250, 200, 40), M.Metal))
					for _, sx in { -1, 1 } do
						K:cyl("BinoTube", 0.9, 0.42, hcf * CF(sx * 0.35, 0.05, -0.75) * ANG(0, PI / 2, 0), lk(rgb(250, 200, 40), M.Metal))
						K:disc("BinoLens", 0.34, 0.02, hcf * CF(sx * 0.35, 0.05, -1.21) * ANG(PI / 2, 0, 0), lk(rgb(60, 90, 120), M.Glass, { r = 0.3 }))
						K:cyl("BinoEye", 0.3, 0.26, hcf * CF(sx * 0.3, 0.05, 0.55) * ANG(0, PI / 2, 0), Look.black)
					end
					K:box("BinoVisor", V3(1.2, 0.3, 0.2), hcf * CF(0, 0.3, 0.55), Look.black)
				end)
				local _, lab = txt(K, "BinoInfo", 1.6, 0.8, face(R, x0 + 1.25, 1.9, gz + 3.0, 0), "광안대교 VIEW\n500원 · 2분", rgb(30, 40, 50), rgb(250, 200, 40), F.GothamBold)
				binocLabel = lab
			end
		end
		-- 난간 안전 안내판
		if i == 1 or i == 3 then
			K:free(function()
				local sd = face(R, x0 + 0.08, 2.2, gz + 4.6, PI / 2)
				K:plate("RailSafetySign", 1.6, 0.9, 0.02, sd, lk(rgb(250, 210, 30)))
				txt(K, "RailSafetyText", 1.5, 0.8, sd * CF(0, 0, 0.022), "⚠ 난간에 기대거나\n올라가지 마세요", BLACK, nil, F.GothamBlack)
			end)
		end
	end

	-- 5) 가운데: 파라솔 하이테이블 · 라운지 세트 · 아웃도어 러그 --------------------------------------------------------
	local parasolBulbs: { BasePart } = {}
	local function hiSet(xc: number, zc: number, col: Color3, withLight: boolean)
		local pcf = at(R, xc, zc)
		if not placeOr(R, pcf, V3(2.6, 9.0, 2.6), 0.2, "parasol table") then
			return
		end
		K:free(function()
			parasol(K, R, xc, zc, 4.0, 8.2, col, parasolBulbs)
		end)
		K:box("HiTableRing", V3(0.1, 0.1, 0.1), pcf * CF(0, 3.6, 0), lk(BLACK, nil, { t = 1 }))
		K:disc("HiTableTopTeak", 2.6, 0.12, pcf * CF(0, 3.5, 0), teak)
		K:disc("HiTableApron", 2.3, 0.2, pcf * CF(0, 3.34, 0), lk(rgb(30, 30, 32), M.Metal))
		for k = 0, 3 do
			local a = k * PI / 2 + PI / 4
			K:seg("HiTableLeg", (pcf * CF(math.cos(a) * 0.9, 3.3, math.sin(a) * 0.9)).Position, (pcf * CF(math.cos(a) * 1.15, 0.02, math.sin(a) * 1.15)).Position, 0.1, lk(rgb(30, 30, 32), M.Metal))
		end
		K:vcyl("HiTableLanternGlass", 0.5, 0.36, pcf * CF(0.5, 3.81, 0.3), gl(rgb(255, 236, 210), 0.5))
		local g = K:vcyl("HiTableCandle", 0.2, 0.16, pcf * CF(0.5, 3.66, 0.3), Look.lampWarm)
		if withLight then
			K:light(g, "PointLight", { Range = 12, Brightness = 0.8, Color = WARM })
		end
		for k, a in { 0.3, 1.9, 3.5, 5.0 } do
			local sp = at(R, xc + math.cos(a) * 2.1, zc + math.sin(a) * 2.1)
			if place(R, sp, V3(1.2, 3.0, 1.2), 0, "parasol stool") then
				barStool(K, sp, 2.75, if k % 2 == 0 then cushion else lk(rgb(40, 90, 120), M.Fabric), teak)
			end
		end
	end
	hiSet(9.0, -32.0, rgb(240, 236, 226), true)
	hiSet(9.5, 15.0, rgb(40, 90, 120), true)
	-- 라운지 세트 (파라솔 + 낮은 의자 2 + 사이드 테이블)
	local function loungeSet(xc: number, zc: number, col: Color3)
		local pcf = at(R, xc, zc)
		if not placeOr(R, pcf, V3(1.6, 9.0, 1.6), 0, "lounge parasol") then
			return
		end
		K:free(function()
			parasol(K, R, xc, zc, 4.2, 8.0, col, parasolBulbs)
		end)
		for _, s in { -1, 1 } do
			local ccf = at(R, xc + 0.6, zc + s * 2.2, if s > 0 then PI else 0)
			if place(R, ccf, V3(2.4, 2.8, 2.4), 0, "lounge chair") then
				K:box("RTChairFrame", V3(2.2, 0.5, 2.2), ccf * CF(0, 0.5, 0), teak)
				for _, sx in { -1, 1 } do
					K:box("RTChairArm", V3(0.25, 1.0, 2.2), ccf * CF(sx * 1.0, 1.0, 0), teak)
				end
				K:rbox("RTChairCushion", V3(1.8, 0.4, 2.0), 0.15, ccf * CF(0, 0.95, 0.05), cushion)
				K:rbox("RTChairBack", V3(1.9, 1.3, 0.35), 0.15, ccf * CF(0, 1.65, -0.85) * ANG(math.rad(-12), 0, 0), cushion)
				K:ell("RTChairPillow", V3(0.9, 0.75, 0.25), ccf * CF(0.2, 1.65, -0.55) * ANG(math.rad(-15), 0.2, 0), lk(rgb(40, 90, 120), M.Fabric))
			end
		end
		local tcf = at(R, xc + 2.2, zc)
		if place(R, tcf, V3(1.4, 1.8, 1.4), 0, "lounge side table") then
			K:disc("RTSideTop", 1.3, 0.1, tcf * CF(0, 1.5, 0), teak)
			K:vcyl("RTSideBody", 1.45, 1.0, tcf * CF(0, 0.73, 0), lk(rgb(200, 190, 170), M.Concrete))
			K:vcyl("RTSideGlass", 0.5, 0.26, tcf * CF(0.2, 1.8, 0.2), gl(rgb(250, 180, 80), 0.3))
		end
	end
	loungeSet(8.5, 1.0, rgb(214, 120, 70))
	loungeSet(8.0, 29.0, rgb(240, 236, 226))
	-- 아웃도어 러그 (소파 묶음 아래)
	K:free(function()
		for _, zc in { -18.0, 45.5 } do
			K:box("OutdoorRug", V3(15.0, 0.03, 9.5), at(R, 9.0, zc, 0, 0.015), lk(rgb(196, 186, 166), M.Fabric))
			for k = -3, 3 do
				K:box("OutdoorRugStripe", V3(0.25, 0.032, 9.3), at(R, 9.0 + k * 2.0, zc, 0, 0.016), lk(rgb(40, 90, 120), M.Fabric))
			end
		end
	end)

	-- 6) 북쪽 난간: 긴 화단 (그라스) + 업라이트 -------------------------------------------------------------------
	for _, seg in { { -33.0, -21.0 }, { -17.5, 4.5 }, { 8.5, 30.5 } } do
		local zc = (seg[1] + seg[2]) / 2
		local len = seg[2] - seg[1]
		local pcf = at(R, x1 - 1.3, zc)
		if placeOr(R, pcf, V3(1.8, 3.6, len), 0, "rail planter") then
			K:box("RailPlanter", V3(1.6, 1.6, len), pcf * CF(0, 0.8, 0), lk(rgb(44, 44, 46), M.Metal))
			K:box("RailPlanterSoil", V3(1.4, 0.06, len - 0.2), pcf * CF(0, 1.55, 0), Look.soil)
			K:box("RailPlanterLED", V3(0.05, 0.05, len - 0.3), pcf * CF(-0.82, 0.12, 0), nl(rgb(60, 200, 255)))
			local n = math.floor(len / 1.1)
			for k = 0, n - 1 do
				local z = -len / 2 + (k + 0.5) * len / n
				local hgt = 1.4 + rnd(77, k + seg[1]) * 1.0
				K:ell("GrassClump", V3(1.0, hgt, 1.0), pcf * CF((rnd(78, k) - 0.5) * 0.3, 1.55 + hgt * 0.4, z), lk(if k % 3 == 0 then rgb(150, 160, 100) else rgb(96, 130, 74), M.Grass))
			end
		end
	end
	-- 모서리 화분 업라이트 (야자수 비춤)
	for _, p in { { -22.0, -66.4 }, { 22.0, -34.0 }, { -22.0, 66.4 } } do
		K:free(function()
			local u = at(R, p[1], p[2], 0, 0)
			K:box("UplightBody", V3(0.5, 0.4, 0.5), u * CF(0, 0.2, 0), Look.blackMetal)
			K:disc("UplightLens", 0.4, 0.03, u * CF(0, 0.42, 0), Look.lampWarm)
		end)
	end
	-- 화분 야자수: 맵의 네모 줄기 + 납작한 잎 판 7장을 숨기고, 마디진 줄기 + 아치형 잎 9장 (워싱턴야자) 으로 다시
	do
		local trunks = {}
		for _, r in V.byName.PalmTrunk or {} do
			local mn, mx = abox(R, r)
			table.insert(trunks, { c = (mn + mx) / 2, y0 = mn.Y, y1 = mx.Y })
			safeHide(K, r)
		end
		for _, r in V.byName.PalmLeaf or {} do
			safeHide(K, r)
		end
		local bark = { lk(rgb(104, 82, 62), M.Wood), lk(rgb(84, 66, 50), M.Wood) }
		local leafA, leafB = lk(rgb(64, 112, 52), M.LeafyGrass), lk(rgb(84, 132, 60), M.LeafyGrass)
		for ti, t in trunks do
			K:free(function()
				local top = t.y1 - 0.4
				local lean = V3(math.cos(ti * 1.7) * 0.35, 0, math.sin(ti * 1.7) * 0.35)
				local n = 6
				local prev = ap(R, t.c.X, t.y0, t.c.Z)
				for k = 1, n do
					local f = k / n
					local p = ap(R, t.c.X, t.y0 + (top - t.y0) * f, t.c.Z) + R.A:VectorToWorldSpace(lean * f * f)
					K:seg("PalmTrunkSeg", prev, p, 0.95 - 0.3 * f, bark[k % 2 + 1], 0.06)
					prev = p
				end
				K:ball("PalmCrownBoot", 1.15, CF(prev), lk(rgb(110, 92, 60), M.Grass))
				for k = 0, 8 do
					local a = k * 2 * PI / 9 + ti * 0.4
					local dir = R.A:VectorToWorldSpace(V3(math.cos(a), 0, math.sin(a)))
					local up = Vector3.yAxis
					local L = 3.6 + (k % 3) * 0.4
					local pts = { prev, prev + dir * (L * 0.3) + up * 0.75, prev + dir * (L * 0.65) + up * 0.55, prev + dir * L - up * (0.5 + (k % 2) * 0.4) }
					local look = if k % 2 == 0 then leafA else leafB
					for j = 1, 3 do
						K:bar("PalmFrond", pts[j], pts[j + 1], ({ 0.5, 1.15, 0.8 })[j], 0.06, look)
					end
				end
			end)
		end
	end

	-- 7) 유리 난간 LED (바닥 레일 안쪽 전체) ---------------------------------------------------------------------
	K:free(function()
		local a = K:box("RailLEDSouth", V3(0.06, 0.05, z1 - z0 - 1.0), at(R, x0 + 0.1, R.cz, 0, 0.36), nl(rgb(60, 200, 255)))
		local b = K:box("RailLEDNorth", V3(0.06, 0.05, 104), at(R, x1 - 0.1, -20.6, 0, 0.36), nl(rgb(60, 200, 255)))
		local c = K:box("RailLEDEast", V3(x1 - x0 - 1.0, 0.05, 0.06), at(R, R.cx, z0 + 0.1, 0, 0.36), nl(rgb(60, 200, 255)))
		local d = K:box("RailLEDWest", V3(x1 - x0 - 2.0, 0.05, 0.06), at(R, R.cx - 0.5, z1 - 0.1, 0, 0.36), nl(rgb(60, 200, 255)))
		for _, p in { a, b, c, d } do
			table.insert(moodParts, p)
		end
	end)

	-- 8) 흡연구역 (서쪽 남쪽 모서리) · 금연 안내 · 라운지 문 옆 안내 ------------------------------------------------------
	do
		local scf = at(R, -16.6, 69.4)
		if placeOr(R, scf, V3(1.2, 3.0, 1.2), 0, "ashtray") then
			K:vcyl("AshtrayBody", 2.6, 0.9, scf * CF(0, 1.3, 0), Look.steel)
			K:disc("AshtraySand", 0.8, 0.05, scf * CF(0, 2.62, 0), lk(rgb(200, 190, 160), M.Sand))
			K:disc("AshtrayRim", 0.95, 0.06, scf * CF(0, 2.6, 0), Look.chrome)
		end
		local pcf = at(R, -13.2, 70.6)
		if placeOr(R, pcf, V3(1.8, 6.0, 0.6), 0, "smoking sign") then
			K:vcyl("SmokeSignPole", 4.6, 0.12, pcf * CF(0, 2.3, 0), Look.blackMetal)
			K:disc("SmokeSignBase", 0.9, 0.08, pcf * CF(0, 0.04, 0), Look.blackMetal)
			local sd = pcf * CF(0, 4.9, 0.08)
			K:plate("SmokeSignBoard", 1.8, 1.3, 0.04, sd, lk(rgb(30, 140, 80)))
			txt(K, "SmokeSignText", 1.7, 1.2, sd * CF(0, 0, 0.045), "흡연구역\nSMOKING AREA\n꽁초는 재떨이에", WHITE, nil, F.GothamBlack)
			local sl = K:box("SmokeAreaLight", V3(0.1, 0.1, 0.1), pcf * CF(0, 5.8, 0.6), lk(BLACK, nil, { t = 1 }))
			K:light(sl, "PointLight", { Range = 10, Brightness = 0.6, Color = WARM })
		end
		K:free(function()
			noSmoking(K, face(R, 24.9, 5.2, 48.6, -PI / 2), 1.0, "루프탑 금연 · 흡연구역 이용")
			local nd = face(R, 24.9, 3.4, 61.4, -PI / 2)
			K:plate("RTHoursBoard", 2.0, 1.4, 0.03, nd, lk(rgb(20, 20, 22)))
			txt(K, "RTHoursText", 1.9, 1.3, nd * CF(0, 0, 0.035), "OCEAN ROOFTOP\nOPEN 18:00 - 02:00\n우천 시 2F 라운지", rgb(255, 230, 190), nil, F.GothamBold, 1.2)
		end)
	end
	-- 바닥 조명 문구 (라운지 문 앞)
	K:free(function()
		txt(K, "DeckWelcome", 6.0, 1.2, topCF(ap(R, 14.0, 0.03, 54.5), av(R, 1, 0, 0)), "OCEAN ROOFTOP", rgb(255, 214, 160), nil, F.GothamBlack, 0.8, { d = 0.01 })
	end)

	-- 상호작용 ---------------------------------------------------------------------------------------
	-- 1) 메뉴 넘기기
	if menuPart and menuLabel then
		local PAGES = {
			"HIGHBALL\n\n짐빔 하이볼 13,000\n산토리 가쿠 15,000\n유자 하이볼 14,000\n\n← 넘기기",
			"BEER\n\n생맥주 500 9,000\n수제 IPA 11,000\n코로나 9,000\n\n← 넘기기",
			"COCKTAIL\n\n광안 선셋 16,000\n모히또 15,000\n아페롤 스프리츠 17,000\n\n← 넘기기",
			"NON-ALC · 안주\n\n제로 하이볼 9,000\n레몬에이드 8,000\n나쵸 · 감자튀김 15,000\n\n← 넘기기",
		}
		prompt(R, menuPart, "cycle", {
			action = "메뉴 넘기기",
			object = "루프탑 바 메뉴",
			start = 0,
			on = function(_i, it)
				(menuLabel :: TextLabel).Text = it
			end,
		}, PAGES)
	end
	-- 2) 카바나 커튼
	if #cabanaCurtains > 0 then
		prompt(R, cabanaCurtains[1], "toggle", {
			object = "카바나 커튼",
			onText = "커튼 열기",
			offText = "커튼 치기",
			state = false,
			on = function(s: boolean)
				for _, p in cabanaCurtains do
					tween(p, { Transparency = if s then 0.15 else 1 }, 0.6)
				end
			end,
		})
	end
	-- 3) 망원경
	if binoc and binocPivot then
		local parts = {}
		for _, d in (binoc :: Model):GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, { p = d, cf = d.CFrame })
			end
		end
		local pivot = R.V.cf * (binocPivot :: Vector3)
		local step = 0
		local INFO = { "광안대교 VIEW\n500원 · 2분", "광안대교 · 7.4km\n야경 20:00-24:00", "이기대 해안 산책로\n오륙도 방향", "광안리 드론쇼\n토요일 20:00 · 22:00" }
		prompt(R, parts[1] and parts[1].p or nil, "prompt", {
			action = "망원경 보기",
			object = "광안리 망원경",
			fn = function()
				step = step % 4 + 1
				local rot = CF(pivot) * CFrame.fromAxisAngle(R.V.cf:VectorToWorldSpace(V3(0, 1, 0)), (step - 1) * 0.3 - 0.45) * CF(-pivot)
				for _, r in parts do
					tween(r.p, { CFrame = rot * r.cf }, 0.6)
				end
				if binocLabel then
					(binocLabel :: TextLabel).Text = INFO[step]
				end
			end,
		})
	end
	-- 4) DJ: 조명 모드 (난간 LED · DJ 부스 · 랜턴 · 파라솔 전구)
	if djKnob then
		local MODES = {
			{ "OCEAN", rgb(60, 200, 255), rgb(255, 200, 140) },
			{ "SUNSET", rgb(255, 120, 60), rgb(255, 170, 90) },
			{ "PARTY", rgb(255, 60, 170), rgb(180, 120, 255) },
			{ "CALM", rgb(255, 214, 160), rgb(255, 226, 190) },
		}
		prompt(R, djKnob, "cycle", {
			action = "조명 모드",
			object = "루프탑 DJ 콘솔",
			on = function(_i, it)
				for _, p in moodParts do
					tween(p, { Color = it[2] }, 0.6)
				end
				for _, p in parasolBulbs do
					tween(p, { Color = it[3] }, 0.6)
				end
				for _, p in glows do
					tween(p, { Color = it[3] }, 0.6)
				end
			end,
		}, MODES)
	end
end

--=====================================================================================================
function T.build(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	npcKeeps(R)
	if V.type == "clubcorridor" then
		buildCorridor(K, V, R)
	elseif V.type == "hiphop" then
		buildHipHop(K, V, R)
	elseif V.type == "clublounge" then
		buildLounge(K, V, R)
	elseif V.type == "rooftop" then
		buildRooftop(K, V, R)
	elseif V.type == "clubwc" then
		buildRestroom(K, V, R)
	end
	-- 막힌 파트 요약 (로그)
	local cnt: { [string]: number } = {}
	for _, g in K.ghosts do
		cnt[g.Name] = (cnt[g.Name] or 0) + 1
	end
	local list = {}
	for n, c in cnt do
		table.insert(list, n .. "x" .. c)
	end
	table.sort(list)
	if #list > 0 then
		K:note("ghosts: " .. table.concat(list, " "))
	end
end

return T
