--!strict
-- GwangalliBuildingInterior/T_club: CLUB OCEAN 광안 의 방 (Venues.luau 의 방, Scan.fitRoom).
--   clublounge   OCEAN SKY LOUNGE 2F (42x173): 창가 소파 묶음마다 러그 · 펜던트 · 사이드 테이블 램프, 창 사이 암체어 · 2인 테이블 ·
--                망원경, 커튼 (상호작용), 남쪽 DJ 코너 + 스피커 + 샴페인 셀러 + 칵테일 하이테이블, 북쪽 라이브러리 라운지 +
--                아트월 · VIP 호스트 데스크 (예약 태블릿), 슬랫 천장 · 라인 조명 · 무드 조명 (DJ 콘솔에서 바꿈)
--   rooftop      OCEAN ROOFTOP (54x148): 진짜 루프탑 바 (백바 · 라벨 병 · 탭 · 아이스웰 · POS · 메뉴 · 스툴 · 퍼걸러),
--                파라솔 하이테이블 · 레일 바 레지 · 망원경 · 카바나 커튼 (상호작용) · 랜턴 · 업라이트 · 난간 LED · DJ 코너 · 화분 · 흡연구역
--   hiphop       ROOM 2 · HIP-HOP (50x70): 그라피티 벽화 (플레이트 글자 · 드립 · 태그) · 스티커/포스터 벽 · 벽돌 · 무대 트러스 ·
--                바리케이드 · 모니터 스피커 · 사이퍼 드링크 레일 · 스니커/머치 벽 · 붐박스 · 네온 아트 · 코너 스피커
--   clubwc       여자 / 남자 화장실 (20x41): 파우더 카운터 · 할리우드 거울 · 라운지 코너 · 샹들리에 (여) / 가림벽 · 그루밍 카운터 ·
--                청소 카트 · 배플 천장 (남), 종이타월 · 휴지통 · 배수구 · 안내문 · 칸마다 휴지걸이 · 위생용품 수거함
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
local _ = Common

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
local function keepBox(R: any, x0: number, z0: number, x1: number, z1: number, y1: number, kind: string, y0: number?)
	local yb = y0 or 0.1
	local c = R.A * CF((x0 + x1) / 2, (yb + y1) / 2, (z0 + z1) / 2)
	local mn, mx = Kit.laabb(c, V3(math.abs(x1 - x0), y1 - yb, math.abs(z1 - z0)))
	R.V:addKeep(mn, mx, kind)
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
	for _, s in V.solid do
		if not K.hidden[s.part] and not (s.size.Y < 0.15 and s.max.Y < 0.2) and Kit.overlap(mn, mx, s.min, s.max, 0.04) then
			R.why = "map " .. s.name
			return false
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
		{ z = 5.55, cap = "DJ HAEWON · RESIDENT\nTECH HOUSE", art = { { rgb(16, 14, 30), 0, 0, 1, 1 }, { rgb(90, 30, 160), 0, 0, 1, 0.45 }, { rgb(255, 70, 170), 0.12, 0.45, 0.76, 0.05 }, { rgb(26, 22, 30), 0.38, 0.18, 0.24, 0.5 }, { rgb(230, 190, 160), 0.44, 0.66, 0.12, 0.14 }, { rgb(40, 220, 255), 0.05, 0.86, 0.3, 0.04 } } },
		{ z = 11.5, cap = "광안대교 · GWANGAN BRIDGE\n2025 NIGHT", art = { { rgb(8, 12, 30), 0, 0, 1, 1 }, { rgb(20, 40, 90), 0, 0, 1, 0.4 }, { rgb(255, 210, 120), 0, 0.42, 1, 0.03 }, { rgb(255, 210, 120), 0.18, 0.45, 0.02, 0.3 }, { rgb(255, 210, 120), 0.78, 0.45, 0.02, 0.3 }, { rgb(120, 200, 255), 0.0, 0.3, 1, 0.02 }, { rgb(255, 80, 160), 0.6, 0.8, 0.1, 0.08 } } },
		{ z = 17.5, cap = "SEAN WAVE · RESIDENT\nK-EDM", art = { { rgb(30, 10, 20), 0, 0, 1, 1 }, { rgb(255, 120, 40), 0, 0, 1, 0.3 }, { rgb(255, 60, 90), 0.0, 0.3, 1, 0.12 }, { rgb(20, 16, 22), 0.4, 0.15, 0.2, 0.55 }, { rgb(220, 180, 150), 0.45, 0.7, 0.1, 0.12 }, { rgb(255, 230, 120), 0.7, 0.75, 0.2, 0.2 } } },
	}
	for i, g in GAL do
		local d = wallL(R, g.z, 5.95, 0)
		Props.frame(K, d, 4.6, 3.0, { frame = Look.black, mat = lk(rgb(240, 238, 232)), art = g.art, depth = 0.12, border = 0.1 })
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
		K:plate("LogoPanel", 5.6, 3.6, 0.1, d, lk(rgb(14, 14, 18), M.Glass, { r = 0.15 }))
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
		K:plate("FullMirror", 2.3, 5.9, 0.12, d, Look.mirror)
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
	local dl = 0
	for _, z in { -34, -26, -18, -10, -2, 6, 14, 22, 30 } do
		for _, x in { -5.4, 5.2 } do
			dl += 1
			local withL = (z == 30 and x < 0) or (z == -2 and x > 0)
			downlight(K, R, x, z, { light = withL, range = 14, bright = 1.0, angle = 60 })
		end
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
	K:plate("HMirror", w, h, 0.14, dcf, Look.mirror)
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

local function buildRestroom(K: any, V: any, R: any)
	local female = V.room == "wc_f"
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
			K:plate("FullMirror", 2.4, 6.1, 0.1, d, Look.mirror)
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
			Props.frame(K, wallF(R, scx, 6.2, 0), 4.0, 2.6, { frame = Look.goldMetal, mat = lk(rgb(250, 244, 240)), depth = 0.1, art = {
				{ rgb(250, 232, 236), 0, 0, 1, 1 }, { rgb(255, 150, 190), 0.1, 0.15, 0.45, 0.6 }, { rgb(230, 90, 140), 0.45, 0.35, 0.4, 0.5 }, { rgb(255, 214, 120), 0.62, 0.12, 0.2, 0.2 }, { rgb(40, 30, 40), 0.2, 0.82, 0.6, 0.03 },
			} })
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
			local d = wallL(R, -1.1, 5.4, 0)
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
			K:plate("GroomMirror", glen - 0.4, 3.0, 0.05, md, Look.mirror)
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
	-- 바닥 배수구 2
	floorDrain(K, R, 2.2, -6.6)
	floorDrain(K, R, 3.4, 9.0)
	-- 천장: 다운라이트 · 배기구 · 감지기 · 스프링클러 · 스피커 · 네온 코브 ------------------------------------
	for i, z in { -0.4, 5.6, 11.6 } do
		downlight(K, R, vanX - 0.4, z, { light = i ~= 2, range = 12, bright = 0.9, angle = 70, glow = Look.lampNeutral, color = rgb(255, 236, 220) })
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
			downlight(K, R, x0 + 1.8, z, { light = z == -3.6, range = 11, bright = 0.8, angle = 70 })
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
function T.build(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	npcKeeps(R)
	if V.type == "clubcorridor" then
		buildCorridor(K, V, R)
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
