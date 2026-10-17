--!strict
-- GwangalliBuildingInterior/T_clubmain: CLUB OCEAN 광안 의 앞쪽 (clublobby 로비 · clubtunnel 입장 터널 · clubmain 메인홀) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드) — 클럽은 기존 가구 리스킨 없음 (전부 false)
--   build(K, V, S) 유형별 디테일
--
-- 정렬 프레임: 클럽 건물은 방 프레임에서 약 -0.86도 돌아가 있어서 (벽이 60 스터드에 0.9 스터드 기움) 모든 파트는
-- 바닥 파트의 회전으로 만든 정렬 프레임 R.A 기준으로 짓습니다 (P = K 의 프록시: P:box(...) 의 cf 가 A 기준).
-- 맵 파트 위치는 전부 정렬 프레임으로 다시 재서 (R.find) 거기에 붙입니다.
--
--   clublobby  로비 (60x14): 입장료 계산대 (가격판 · 신분증 스캐너 · 팔찌 디스펜서 · QR · 게스트 리스트 태블릿 · CCTV 모니터 ·
--              무전기 충전기 · 금고) · 대기 줄 스탠션 · 소지품 검사대 · 팔찌 확인 포디움 + 메인홀 입구 스탠션 ·
--              포토월 (포토존 바닥 스티커 · 업라이트 · 폰 거치대 촬영) · 락커 32칸 (번호판 · 손잡이 · 키 밴드 · 열리는 119번) ·
--              이벤트 포스터 · 보조배터리 대여기 · 이용 안내 · 천장 CCTV · 스피커 · 스프링클러 · 감지기 · 레일 조명 · 걸레받이
--   clubtunnel 입장 터널 (10x20): LED 바 사이 블랙 미러 패널 · 천장 미러 · 킥 플레이트 · 고보 프로젝터 브랜드 투사 (순환) ·
--              코너 무드 라인 (색 바꾸기) · 입장 안내판 · CCTV · 스피커
--   clubmain   메인홀 (다듬기만): 메인 바 백바 라벨 병 (보드카 · 진 · 데킬라 · 위스키 · 샴페인) · 아이스웰 스쿱 · 글라스 랙 ·
--              POS · 음료 메뉴판 (시그니처 에이드 · 스파클링 · 목테일) · 바 매트 · 가니시 · 바 도구 · 테이블 번호 · 보틀 스탠드 ·
--              VIP 로프 · 계단 LED · 메자닌 샴페인 바 · 흡연실 내부 · DJ 부스 주변 (케이블 · 헤드폰 · 로드 케이스) ·
--              홀 화장실 디스펜서 · 직원 출입문 디테일
--
-- 게임플레이 계약 (arcade_club.json · systems.json): ClubLight / ClubFloorTile / ClubTable / ClubZone / ClubNPC / ClubShowAnchor /
--   ParadeRoute / Seat (BenchSeat · ClubGuestSeat) / ServePoint / DJ 부스 상판 · 프롬프트 / LED 월 · LEDScreen / 문 · ClubDoor 는
--   숨기지도 옮기지도 않음. 숨기는 것은 순수 장식만 (락커 몸체 · 번호판 · 문 1칸, 포토존 스티커, 메인 바 백바 병 75개).
--   LED 댄스 플로어 · 테이블 상판 · 통로 · 퍼레이드 길 · 천장 조명 리그 · LED 월 앞면 · 랭킹 보드 벽 · 바 캐노피 TV 자리는 비움.
--   움직이는 조명 · 레이저 · 스트로브 없음 (GwangalliClubPlus 담당). 불빛은 작은 고정 액센트만.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local T = {}
T.types = { "clublobby", "clubtunnel", "clubmain" }

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
local function nl(c: Color3, t: number?): { [string]: any }
	return { c = c, m = M.Neon, t = t or 0 }
end
local function gl(c: Color3?, t: number?): { [string]: any }
	return { c = c or rgb(220, 232, 238), m = M.Glass, t = t or 0.6, r = 0.12 }
end
local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end
local function hi(K: any): boolean
	return K.detail == "high"
end

-- 클럽 팔레트 (맵 색에 맞춤)
local CY = rgb(40, 220, 255) -- 오션 시안 (터널 · 천장 링)
local VI = rgb(150, 60, 255) -- 바이올렛 (코브 LED)
local PK = rgb(255, 60, 170) -- 마젠타 (포토존)
local AMB = rgb(236, 160, 80) -- 오닉스 앰버
local MATTE = lk(rgb(20, 20, 23))
local MATTE2 = lk(rgb(32, 32, 36))
-- 블랙 유광 (반사율은 아주 조금만: 유리 재질 + 반사는 하늘을 비춰 밝게 뜸)
local GLOSS = lk(rgb(9, 9, 11), M.SmoothPlastic, { r = 0.05 })
local BRASS = Look.brass
local CHROME = Look.chrome
local STEEL = Look.steel
local BMETAL = Look.blackMetal
local VELVET = lk(rgb(96, 14, 38), M.Fabric)
local PLASTIC_GREY = lk(rgb(92, 96, 104), M.Plastic)

-- 글자판 (dcf +Z = 보는 쪽). glow 가 있으면 빛나는 글자
local function txt(P: any, name: string, w: number, h: number, dcf: CFrame, s: string, fg: Color3, bg: Color3?, font: Enum.Font?, glow: number?, o: any?): (BasePart, TextLabel)
	local op: any = { fg = fg, bg = bg, font = font or F.GothamBold, glow = glow, d = 0.02 }
	if o then
		for k, v in o do
			op[k] = v
		end
	end
	return P:text(name, w, h, dcf, s, op)
end

-- 위를 보는 글자판 (바닥 · 판 윗면): p 중심, 글자 위쪽 = up
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end

-- 표시면(dcf)에 붙는 원판 (축 = dcf Z)
local function wdisc(P: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return P:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end

-- 정렬 프레임 프록시 -----------------------------------------------------------------------------------
-- P 의 메서드는 K 와 같지만 cf / 점이 정렬 프레임 A 기준. 그 밖의 필드 · 메서드는 K 로 넘김 (Props 에 P 를 넘겨도 됨).
local function proxy(K: any, A: CFrame): any
	local P: any = setmetatable({}, {
		__index = function(_, k)
			local v = K[k]
			if type(v) == "function" then
				return function(_self: any, ...: any): ...any
					return v(K, ...)
				end
			end
			return v
		end,
	})
	function P:box(n: string, s: Vector3, c: CFrame, l: any?): BasePart
		return K:box(n, s, A * c, l)
	end
	function P:wedge(n: string, s: Vector3, c: CFrame, l: any?): BasePart
		return K:wedge(n, s, A * c, l)
	end
	function P:cyl(n: string, len: number, d: number, c: CFrame, l: any?): BasePart
		return K:cyl(n, len, d, A * c, l)
	end
	function P:vcyl(n: string, h: number, d: number, c: CFrame, l: any?): BasePart
		return K:vcyl(n, h, d, A * c, l)
	end
	function P:ball(n: string, d: number, c: CFrame, l: any?): BasePart
		return K:ball(n, d, A * c, l)
	end
	function P:ell(n: string, s: Vector3, c: CFrame, l: any?): BasePart
		return K:ell(n, s, A * c, l)
	end
	function P:seg(n: string, a: Vector3, b: Vector3, d: number, l: any?, e: number?): BasePart?
		return K:seg(n, A * a, A * b, d, l, e)
	end
	function P:bar(n: string, a: Vector3, b: Vector3, w: number, h: number, l: any?): BasePart?
		return K:bar(n, A * a, A * b, w, h, l)
	end
	function P:ring(n: string, f: CFrame, r: number, d: number, k: number, l: any?, a0: number?, a1: number?)
		return K:ring(n, A * f, r, d, k, l, a0, a1)
	end
	function P:rbox(n: string, s: Vector3, r: number, c: CFrame, l: any?)
		return K:rbox(n, s, r, A * c, l)
	end
	function P:slab(n: string, w: number, len: number, t: number, r: number, c: CFrame, l: any?)
		return K:slab(n, w, len, t, r, A * c, l)
	end
	function P:panel(n: string, w: number, h: number, d: number, r: number, c: CFrame, l: any?)
		return K:panel(n, w, h, d, r, A * c, l)
	end
	function P:disc(n: string, dia: number, t: number, c: CFrame, l: any?): BasePart
		return K:disc(n, dia, t, A * c, l)
	end
	function P:plate(n: string, w: number, h: number, d: number, c: CFrame, l: any?): BasePart
		return K:plate(n, w, h, d, A * c, l)
	end
	function P:text(n: string, w: number, h: number, c: CFrame, s: string, o: any?): (BasePart, TextLabel)
		return K:text(n, w, h, A * c, s, o)
	end
	function P:make(cls: string, n: string, s: Vector3, c: CFrame, l: any?, sh: Enum.PartType?): BasePart
		return K:make(cls, n, s, A * c, l, sh)
	end
	function P:spot(c: CFrame, s: Vector3, pad: number?, kind: string?): boolean
		return K:spot(A * c, s, pad, kind)
	end
	P.A = A
	return P
end

local FLOORS = { LobbyFloor = true, TunnelFloor = true, BlackGlossFloor = true }

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

-- 방 문맥: R = { K, V, A, P, find(name, under?) -> { {rec, mn, mx, c, s} }, wall(side, u, y, off) -> dcf, world(p), wdir(v) }
local function makeRoom(K: any, V: any): any
	local yaw = 0
	for _, r in V.parts do
		if FLOORS[r.name] then
			yaw = yawOf(r.lcf)
			break
		end
	end
	local A = ANG(0, yaw, 0)
	local R: any = { K = K, V = V, A = A, P = proxy(K, A), yaw = yaw }
	local cache: { [string]: any } = {}
	local function under(part: Instance, name: string): boolean
		local q = part.Parent
		local n = 0
		while q and q ~= V.model and n < 8 do
			if q.Name == name then
				return true
			end
			q = q.Parent
			n += 1
		end
		return false
	end
	-- 이름이 name 인 맵 파트들 (정렬 프레임 AABB). under = 조상 모델 이름 (선택)
	function R.find(name: string, anc: string?): { any }
		local key = name .. "|" .. (anc or "")
		if cache[key] then
			return cache[key]
		end
		local out = {}
		for _, r in V.parts do
			if r.name == name and (anc == nil or under(r.part, anc)) then
				local l = A:ToObjectSpace(r.lcf)
				local mn, mx = Scan.laabb(l, r.part.Size)
				table.insert(out, { rec = r, part = r.part, mn = mn, mx = mx, c = (mn + mx) / 2, s = mx - mn, lcf = l })
			end
		end
		cache[key] = out
		return out
	end
	function R.one(name: string, anc: string?): any?
		return R.find(name, anc)[1]
	end
	-- 이름이 prefix 로 시작하는 맵 파트들
	function R.findPrefix(prefix: string, anc: string?): { any }
		local out = {}
		for _, r in V.parts do
			if string.sub(r.name, 1, #prefix) == prefix and (anc == nil or under(r.part, anc)) then
				local l = A:ToObjectSpace(r.lcf)
				local mn, mx = Scan.laabb(l, r.part.Size)
				table.insert(out, { rec = r, part = r.part, mn = mn, mx = mx, c = (mn + mx) / 2, s = mx - mn, lcf = l })
			end
		end
		return out
	end
	-- 벽 표시면 dcf (정렬 프레임). u = 벽을 따라가는 실제 좌표 (front/back = x, left/right = z), off = 벽에서 띄움
	function R.wall(side: string, u: number, y: number, off: number?): CFrame
		local o = off or 0
		if side == "left" then
			return CFrame.fromMatrix(V3(R.xl + o, y, u), V3(0, 0, -1), Vector3.yAxis, V3(1, 0, 0))
		elseif side == "right" then
			return CFrame.fromMatrix(V3(R.xr - o, y, u), V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
		elseif side == "front" then
			return CFrame.fromMatrix(V3(u, y, R.fz - o), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1))
		else
			return CFrame.fromMatrix(V3(u, y, R.bz + o), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1))
		end
	end
	function R.world(p: Vector3): Vector3
		return K.cf * (A * p)
	end
	function R.wdir(v: Vector3): Vector3
		return K.cf:VectorToWorldSpace(A:VectorToWorldSpace(v))
	end
	function R.hide(part: BasePart)
		Scan.hide(K.hidden, part)
	end
	-- 정렬 프레임 상자 (mn..mx) 와 겹치는 맵 파트 이름 (ignore[name] = true 는 뺌). 없으면 nil
	function R.blocked(mn: Vector3, mx: Vector3, ignore: { [string]: boolean }?, only: { [string]: boolean }?): string?
		for _, r in V.parts do
			if not (ignore and ignore[r.name]) and (only == nil or only[r.name]) and r.part.Transparency < 0.95 then
				local l = A:ToObjectSpace(r.lcf)
				local a, b = Scan.laabb(l, r.part.Size)
				if a.X < mx.X and b.X > mn.X and a.Y < mx.Y and b.Y > mn.Y and a.Z < mx.Z and b.Z > mn.Z then
					return r.name
				end
			end
		end
		return nil
	end
	return R
end

-- 공용 소품 (정렬 프레임 P 로) ------------------------------------------------------------------------------

-- 천장 매입 스피커 (원형 그릴)
local function ceilSpeaker(P: any, x: number, z: number, H: number)
	P:disc("CeilSpeakerRim", 1.05, 0.04, CF(x, H - 0.02, z), MATTE2)
	P:disc("CeilSpeakerGrille", 0.9, 0.05, CF(x, H - 0.03, z), lk(rgb(26, 26, 28), M.DiamondPlate))
end

-- 벽걸이 박스 스피커 (브래킷): dcf = 벽 표면, 위쪽 모서리에 아래로 기울여 매닮
local function wallSpeaker(P: any, dcf: CFrame, s: number)
	P:plate("SpkBracket", 0.3, 0.5 * s, 0.35 * s, dcf, BMETAL)
	local body = dcf * CF(0, -0.05 * s, 0.75 * s) * ANG(-0.25, 0, 0)
	P:box("SpkCabinet", V3(1.0 * s, 1.5 * s, 0.9 * s), body, MATTE)
	P:box("SpkGrille", V3(0.92 * s, 1.42 * s, 0.03), body * CF(0, 0, 0.46 * s), lk(rgb(30, 30, 33), M.DiamondPlate))
	P:plate("SpkLogo", 0.3 * s, 0.06 * s, 0.01, body * CF(0, -0.58 * s, 0.475 * s), CHROME)
end

-- 크롬 스탠션 (바닥 원판 + 기둥 + 꼭지). pcf = 바닥. 반환: 로프 고리 높이의 점
local function stanchion(P: any, pcf: CFrame, h: number?, look: any?): Vector3
	local hh = h or 3.1
	local L = look or CHROME
	P:disc("StanchionBase", 0.85, 0.08, pcf * CF(0, 0.04, 0), L)
	P:disc("StanchionBaseRubber", 0.8, 0.02, pcf * CF(0, 0.01, 0), Look.rubber)
	P:vcyl("StanchionPost", hh - 0.15, 0.14, pcf * CF(0, 0.08 + (hh - 0.15) / 2, 0), L)
	P:ball("StanchionFinial", 0.24, pcf * CF(0, hh, 0), L)
	P:vcyl("StanchionHook", 0.08, 0.2, pcf * CF(0, hh - 0.3, 0), L)
	return (pcf * CF(0, hh - 0.32, 0)).Position
end

-- 두 고리 사이 늘어진 벨벳 로프 (중간 sag)
local function rope(P: any, a: Vector3, b: Vector3, sag: number, look: any?)
	local L = look or VELVET
	local m = (a + b) / 2 - V3(0, sag, 0)
	local q1 = a:Lerp(m, 0.5) - V3(0, sag * 0.25, 0)
	local q2 = m:Lerp(b, 0.5) - V3(0, sag * 0.25, 0)
	P:seg("VelvetRope", a, q1, 0.16, L, 0.08)
	P:seg("VelvetRope", q1, m, 0.16, L, 0.08)
	P:seg("VelvetRope", m, q2, 0.16, L, 0.08)
	P:seg("VelvetRope", q2, b, 0.16, L, 0.08)
	P:vcyl("RopeEnd", 0.18, 0.2, CF(a + V3(0, -0.02, 0)), BRASS)
	P:vcyl("RopeEnd", 0.18, 0.2, CF(b + V3(0, -0.02, 0)), BRASS)
end

-- 라이트박스 액자 (벽): dcf 중심, w x h, 테두리 brass, 안은 빛나는 판 + 글자 (title 큰 글, body 작은 글)
local function lightbox(P: any, name: string, dcf: CFrame, w: number, h: number, title: string, body: string?, o: any?)
	local op: any = o or {}
	local bg: Color3 = op.bg or rgb(12, 12, 16)
	local acc: Color3 = op.accent or CY
	local fg: Color3 = op.fg or rgb(242, 240, 236)
	P:plate(name .. "Frame", w + 0.12, h + 0.12, 0.1, dcf, op.frame or BRASS)
	P:plate(name .. "Face", w, h, 0.12, dcf, lk(bg))
	local th = op.titleH or math.min(h * 0.28, 1.1)
	txt(P, name .. "Title", w * 0.9, th, dcf * CF(0, h / 2 - th / 2 - 0.12, 0.125), title, acc, nil, op.titleFont or F.GothamBlack, 1.4)
	if body then
		local bh = h - th - 0.36
		txt(P, name .. "Body", w * 0.88, bh, dcf * CF(0, -h / 2 + bh / 2 + 0.14, 0.125), body, fg, nil, op.bodyFont or F.GothamMedium, 1.15, { wrap = op.wrap })
	end
	if op.art then
		for _, a in op.art do
			P:plate(name .. "Art", a[4] * w, a[5] * h, 0.125, dcf * CF((a[2] - 0.5) * w + a[4] * w / 2, (a[3] - 0.5) * h + a[5] * h / 2, 0), lk(a[1]))
		end
	end
end

-- 작은 아크릴 L 스탠드 안내판 (카운터 위). pcf = 판 바닥 가운데 (윗면), +Z = 읽는 쪽
local function acrylicStand(P: any, pcf: CFrame, w: number, h: number, s: string, fg: Color3, bg: Color3)
	P:box("AcrylicBase", V3(w + 0.06, 0.04, 0.32), pcf * CF(0, 0.02, 0), gl(rgb(235, 240, 245), 0.45))
	local face = pcf * CF(0, 0.04 + h / 2, -0.06) * ANG(-0.18, 0, 0)
	P:box("AcrylicFace", V3(w + 0.06, h + 0.06, 0.03), face, gl(rgb(235, 240, 245), 0.55))
	txt(P, "AcrylicText", w, h, face * CF(0, 0, 0.016), s, fg, bg, F.GothamBold)
end

-- 블랙 걸레받이 + 브라스 라인 (벽 아래, 구간마다): side, u0..u1
local function skirting(P: any, R: any, side: string, u0: number, u1: number)
	if u1 - u0 < 0.4 then
		return
	end
	local u = (u0 + u1) / 2
	local w = u1 - u0
	local dcf = R.wall(side, u, 0.2, 0.0)
	P:plate("Skirting", w, 0.4, 0.06, dcf, GLOSS)
	P:plate("SkirtingLine", w, 0.04, 0.07, dcf * CF(0, 0.2, 0), BRASS)
end

-- 참고: P:disc 원판의 법선 = 파트 X 축 → 원판에 붙인 SpotLight 는 Face = Left (아래 / 앞을 비춤)
-- 바닥 소품 자리 확인 (정렬 프레임). 실패하면 note 남김
local function ov(amn: Vector3, amx: Vector3, bmn: Vector3, bmx: Vector3): boolean
	return amn.X < bmx.X - 0.04 and amx.X > bmn.X + 0.04 and amn.Y < bmx.Y - 0.04 and amx.Y > bmn.Y + 0.04 and amn.Z < bmx.Z - 0.04 and amx.Z > bmn.Z + 0.04
end
local function spotOK(P: any, pcf: CFrame, size: Vector3, pad: number?, what: string): boolean
	-- 바닥 인레이 (높이 0.1) 는 장애물이 아님: 0.12 위에서 잼
	local lift = 0.12
	local ok = P:spot(pcf * CF(0, lift, 0), size - V3(0, lift, 0), pad or 0)
	if not ok then
		-- 무엇에 걸렸는지 (로그용)
		local pd = pad or 0
		local mn, mx = Scan.laabb(P.A * pcf * CF(0, lift + (size.Y - lift) / 2, 0), size - V3(0, lift, 0) + V3(2 * pd, 0, 2 * pd))
		local why = "bounds"
		for _, k in P.V.keep do
			if ov(mn, mx, k.min, k.max) then
				why = "keep " .. tostring(k.kind)
				break
			end
		end
		if why == "bounds" then
			for _, r in P.V.solid do
				if ov(mn, mx, r.min, r.max) then
					why = "solid " .. tostring(r.name)
					break
				end
			end
		end
		if why == "bounds" then
			for _, r in P.reserved do
				if ov(mn, mx, r.min, r.max) then
					why = "reserved " .. tostring(r.kind)
					break
				end
			end
		end
		P:note("no spot: " .. what .. " (" .. why .. ")")
	end
	return ok
end

-- CCTV 화면 같은 순환 화면: label 과 frames(text) 를 period 마다
local function loopText(K: any, label: TextLabel?, frames: { string }, period: number)
	if not label then
		return
	end
	local fr = {}
	for _, s in frames do
		table.insert(fr, { text = s })
	end
	Interact.screenLoop(K, nil, label, fr, period)
end

-- 로컬 플레이어 팔찌 시각 (읽기만)
local function wristbandText(): string
	local lp = Players.LocalPlayer
	if not lp then
		return "팔찌 확인 불가"
	end
	local untilT: any = lp:GetAttribute("ClubOceanWristbandUntil")
	local has: any = lp:GetAttribute("ClubOceanWristband")
	if type(untilT) == "number" and untilT > os.time() then
		local t: any = os.date("!*t", untilT + 9 * 3600)
		return string.format("✓ 팔찌 확인 완료\n%02d:%02d 까지 재입장 무료", t.hour, t.min)
	elseif has == true then
		return "✓ 팔찌 확인 완료\n즐거운 밤 되세요!"
	end
	return "팔찌가 없어요\n입장료 계산대에서 결제 후 입장"
end

-- 플래시 (포토월): 빛나는 판을 잠깐 켜고 불빛을 펄스
local function flash(part: BasePart?, light: Light?)
	if part and part.Parent then
		part.Transparency = 0
		TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
	end
	if light then
		light.Enabled = true
		local l: any = light
		l.Brightness = 6
		TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
		task.delay(0.55, function()
			light.Enabled = false
		end)
	end
end

------------------------------------------------------------------------------------------------------------
-- 로비 --------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

local function lobbyWalls(R: any)
	R.fz, R.bz, R.xl, R.xr = 6.77, -7.23, -30.0, 30.0
	local fr = {}
	for _, f in R.find("LobbyWall") do
		if f.s.Y > 5 then
			table.insert(fr, f.mn.Z)
		end
	end
	if #fr > 0 then
		local s = 0
		for _, z in fr do
			s += z
		end
		R.fz = s / #fr
	end
	for _, f in R.find("VelvetWall") do
		if f.c.X < 0 then
			R.xl = f.mx.X
		else
			R.xr = f.mn.X
		end
	end
	local pf = R.one("Partition_Front")
	if pf then
		R.bz = pf.mx.Z
		R.doorX0, R.doorX1 = pf.mn.X, pf.mx.X
	else
		R.doorX0, R.doorX1 = 6.0, 15.2
	end
	R.H = R.V.H
end

-- 천장: CCTV · 감지기 · 스프링클러 · 스피커 · 포토월 레일 조명
local function lobbyCeiling(R: any)
	local P, K = R.P, R.K
	local H = R.H
	local ring = R.one("CeilingRing")
	local rx, rz, rr = 0, -0.5, 4.6
	if ring then
		rx, rz, rr = ring.c.X, ring.c.Z, ring.s.X / 2 + 0.5
	end
	local function free(x: number, z: number): boolean
		return (V3(x - rx, 0, z - rz)).Magnitude > rr
	end
	P:free(function()
		for _, x in { -26, -17, -9, 9, 17, 25 } do
			if free(x, -1.5) then
				Props.sprinkler(P, x, -1.5)
			end
		end
		Props.smokeDetector(P, -12, 2.5)
		Props.smokeDetector(P, 13, -3.5)
		Props.cctv(P, -27.5, -6.0)
		Props.cctv(P, 27.5, 5.2)
		Props.cctv(P, 6.2, 5.6)
		for _, x in { -20, 20 } do
			ceilSpeaker(P, x, -4.2, H)
		end
	end)
	-- 포토월 레일 조명 (뒤 배경판을 비춤)
	local sr = R.one("StepAndRepeat")
	if sr then
		local x0, x1 = sr.mn.X + 1.2, sr.mx.X - 1.2
		local zr = sr.mn.Z - 3.6
		P:free(function()
			P:box("TrackRail", V3(x1 - x0, 0.12, 0.16), CF((x0 + x1) / 2, H - 0.06, zr), BMETAL)
			local n = 3
			local host: BasePart? = nil
			for i = 0, n - 1 do
				local x = x0 + 0.6 + (x1 - x0 - 1.2) * i / (n - 1)
				P:vcyl("TrackStem", 0.3, 0.06, CF(x, H - 0.27, zr), BMETAL)
				local head = CFrame.lookAt(V3(x, H - 0.6, zr), V3(x * 0.92 + (sr.c.X) * 0.08, 4.8, sr.mn.Z))
				P:box("TrackHead", V3(0.32, 0.32, 0.6), head, BMETAL)
				local lens = P:box("TrackLens", V3(0.24, 0.24, 0.02), head * CF(0, 0, -0.31), nl(rgb(255, 236, 210)))
				if i == 1 then
					host = lens
				end
			end
			if host then
				K:light(host, "SpotLight", { Face = Enum.NormalId.Front, Angle = 70, Range = 16, Brightness = 2.2, Color = rgb(255, 232, 210) })
			end
		end)
	end
end

-- 입장료 계산대
local function lobbyCashier(R: any)
	local P, K = R.P, R.K
	local top = R.one("CounterTop", "Cashier_입장료")
	local body = R.one("CashierCounter")
	if not (top and body) then
		return
	end
	local ty = top.mx.Y
	local gx1 = top.mx.X -- 손님 쪽 끝
	local glass = R.find("GlassPartition", "Cashier_입장료")
	local px = body.c.X
	for _, g in glass do
		if g.s.Y > 3 then
			px = g.c.X
		end
	end
	local gx = (px + gx1) / 2 + 0.05 -- 손님 쪽 가운데
	local sx = (top.mn.X + px) / 2 - 0.05 -- 직원 쪽 가운데
	local z0, z1 = top.mn.Z, top.mx.Z
	-- 손님 쪽 -------------------------------------------------------------------------------------------
	-- 신분증 스캐너 (창구 옆)
	local zs = z0 + (z1 - z0) * 0.62
	P:rbox("IDScannerBody", V3(0.62, 0.2, 0.7), 0.06, CF(gx - 0.1, ty + 0.1, zs) * ANG(0, PI / 2, 0), PLASTIC_GREY)
	P:box("IDScannerGlass", V3(0.46, 0.02, 0.52), CF(gx - 0.1, ty + 0.205, zs), lk(rgb(80, 255, 160), M.Neon, { t = 0.35 }))
	P:box("IDScannerLED", V3(0.06, 0.03, 0.06), CF(gx + 0.22, ty + 0.2, zs + 0.24), nl(rgb(60, 255, 120)))
	txt(P, "IDScannerLabel", 0.5, 0.12, topCF(V3(gx + 0.26, ty + 0.205, zs), V3(1, 0, 0)), "ID SCAN", rgb(230, 230, 230), nil, F.GothamBold)
	-- 신분증 필수 안내 스탠드
	acrylicStand(P, CF(gx + 0.05, ty, z0 + 0.7) * ANG(0, PI / 2, 0), 1.25, 0.82, "신분증 필수\n2008년생부터 출입 불가\n외국인 여권 지참", rgb(255, 255, 255), rgb(150, 20, 40))
	-- QR · 페이 결제 판
	do
		local qcf = CF(gx + 0.15, ty, z1 - 0.6) * ANG(0, PI / 2, 0)
		P:box("QRStandBase", V3(0.56, 0.04, 0.3), qcf * CF(0, 0.02, 0), MATTE)
		local face = qcf * CF(0, 0.42, -0.04) * ANG(-0.2, 0, 0)
		P:box("QRStandFace", V3(0.56, 0.74, 0.03), face, Look.plasticWhite)
		local qr = face * CF(0, 0.08, 0.017)
		P:box("QRCodeBG", V3(0.4, 0.4, 0.005), qr, lk(WHITE))
		for i, q in { { -0.13, 0.13 }, { 0.13, 0.13 }, { -0.13, -0.13 } } do
			P:box("QRFinder", V3(0.1, 0.1, 0.008), qr * CF(q[1], q[2], 0.002), lk(rgb(16, 16, 18)))
			local _ = i
		end
		for i = 1, 7 do
			P:box("QRDot", V3(0.045, 0.045, 0.008), qr * CF(-0.05 + rnd(7, i) * 0.17, -0.12 + rnd(9, i) * 0.22, 0.002), lk(rgb(16, 16, 18)))
		end
		txt(P, "QRText", 0.5, 0.14, face * CF(0, -0.25, 0.018), "카드 · 페이 · 계좌이체", rgb(30, 30, 34), nil, F.GothamBold)
	end
	-- 오늘의 팔찌 색 견본
	do
		local wcf = CF(gx + 0.2, ty, z0 + 2.0) * ANG(0, PI / 2, 0)
		P:box("BandSampleBox", V3(0.6, 0.34, 0.4), wcf * CF(0, 0.17, 0), gl(rgb(230, 240, 250), 0.5))
		P:box("BandSample", V3(0.44, 0.06, 0.24), wcf * CF(0, 0.12, 0), nl(CY))
		txt(P, "BandSampleText", 0.58, 0.16, wcf * CF(0, 0.26, 0.205), "TODAY ● BLUE", CY, nil, F.GothamBold, 1.2)
	end
	-- 직원 쪽 ---------------------------------------------------------------------------------------------
	-- 팔찌 디스펜서 + 롤
	do
		local dz = z0 + 0.9
		P:box("BandDispenser", V3(0.55, 0.45, 0.6), CF(sx, ty + 0.225, dz), MATTE2)
		P:cyl("BandRoll", 0.42, 0.42, CF(sx, ty + 0.3, dz) * ANG(0, PI / 2, 0), nl(dk(CY, 0.25)))
		P:box("BandStrip", V3(0.3, 0.02, 0.5), CF(sx + 0.38, ty + 0.06, dz), lk(CY, M.SmoothPlastic))
	end
	-- UV 스탬프 + 인주
	P:box("StampPad", V3(0.4, 0.06, 0.3), CF(sx, ty + 0.03, z0 + 2.0), lk(rgb(40, 40, 120)))
	P:vcyl("UVStamp", 0.36, 0.16, CF(sx + 0.05, ty + 0.18, z0 + 2.45), lk(rgb(120, 60, 200), M.Plastic))
	P:ball("UVStampKnob", 0.16, CF(sx + 0.05, ty + 0.38, z0 + 2.45), lk(rgb(120, 60, 200), M.Plastic))
	-- 게스트 리스트 태블릿 (스탠드)
	do
		local tcf = CF(sx + 0.05, ty, z1 - 0.9) * ANG(0, -PI / 2, 0)
		P:box("TabletStand", V3(0.4, 0.04, 0.3), tcf * CF(0, 0.02, 0), BMETAL)
		local face = tcf * CF(0, 0.42, 0) * ANG(-0.35, 0, 0)
		P:box("TabletBody", V3(0.95, 0.68, 0.05), face, lk(rgb(24, 24, 26)))
		local _, lbl = txt(P, "TabletScreen", 0.86, 0.6, face * CF(0, 0, 0.027), "GUEST LIST\n이지은 +2 ✓\n박민수 +1\n김하늘 · G2", rgb(220, 240, 255), rgb(18, 34, 60), F.GothamMedium, 1.1)
		loopText(K, lbl, { "GUEST LIST\n이지은 +2 ✓\n박민수 +1\n김하늘 · G2", "GUEST LIST\n정유진 +3\n최도윤 · B4 ✓\n한서준 +1", "오늘 입장 186명\n테이블 예약 23\n대기 4팀" }, 6)
	end
	-- 영수증 묶음
	P:box("ReceiptStack", V3(0.32, 0.08, 0.5), CF(sx - 0.1, ty + 0.04, z0 + 3.3) * ANG(0, 0.2, 0), Look.paper)
	-- 뒤 데스크: CCTV 모니터 · 금고 · 무전기 충전기 · 바인더
	local bd = R.one("BackDesk")
	if bd then
		local by = bd.mx.Y
		local bx = bd.c.X + 0.2
		local mz = bd.mn.Z + 0.75
		P:box("MonitorFoot", V3(0.5, 0.04, 0.4), CF(bx, by + 0.02, mz), BMETAL)
		P:box("MonitorNeck", V3(0.08, 0.5, 0.08), CF(bx - 0.05, by + 0.27, mz), BMETAL)
		local face = CF(bx + 0.02, by + 0.95, mz) * ANG(0, PI / 2, 0) * ANG(-0.05, 0, 0)
		P:box("CCTVMonitor", V3(1.36, 0.82, 0.06), face, lk(rgb(16, 16, 18)))
		local q = { { -0.32, 0.19, rgb(40, 60, 70) }, { 0.32, 0.19, rgb(54, 46, 70) }, { -0.32, -0.19, rgb(30, 50, 44) }, { 0.32, -0.19, rgb(60, 50, 40) } }
		for _, s in q do
			P:box("CCTVFeed", V3(0.6, 0.35, 0.01), face * CF(s[1], s[2], 0.032), lk(s[3], M.Neon, { t = 0.25 }))
		end
		local _, lbl = txt(P, "CCTVOverlay", 1.24, 0.72, face * CF(0, 0, 0.04), "CAM01 입구      CAM02 터널\n\n\nCAM03 로비      CAM04 메인홀", rgb(230, 255, 230), nil, F.Code, 1.2)
		loopText(K, lbl, {
			"CAM01 입구      CAM02 터널\n\n\nCAM03 로비      CAM04 메인홀",
			"CAM05 메인바    CAM06 VIP\n\n\nCAM07 메자닌    CAM08 흡연실",
			"CAM09 2F 라운지 CAM10 옥상\n\n\nCAM11 ROOM 2   CAM12 복도",
		}, 5)
		-- 금고
		P:box("CashSafe", V3(0.9, 0.8, 0.8), CF(bx - 0.1, by + 0.4, bd.mx.Z - 0.7), lk(rgb(36, 38, 42), M.Metal))
		P:vcyl("SafeDial", 0.05, 0.22, CF(bx + 0.37, by + 0.48, bd.mx.Z - 0.7) * ANG(0, 0, PI / 2), CHROME)
		P:box("SafeHandle", V3(0.05, 0.05, 0.3), CF(bx + 0.37, by + 0.25, bd.mx.Z - 0.7), CHROME)
		-- 무전기 충전 독 + 무전기 3
		local rz = bd.mx.Z - 1.8
		P:box("RadioDock", V3(0.5, 0.15, 0.9), CF(bx, by + 0.075, rz), MATTE2)
		for i = -1, 1 do
			P:box("Radio", V3(0.18, 0.55, 0.12), CF(bx, by + 0.42, rz + i * 0.27), lk(rgb(26, 26, 28), M.Plastic))
			P:vcyl("RadioAntenna", 0.3, 0.04, CF(bx - 0.03, by + 0.84, rz + i * 0.27 + 0.03), lk(rgb(26, 26, 28)))
			P:box("RadioLED", V3(0.02, 0.04, 0.04), CF(bx + 0.1, by + 0.64, rz + i * 0.27), nl(if i == 0 then rgb(255, 60, 50) else rgb(60, 230, 120)))
		end
		-- 바인더
		for i = 0, 2 do
			P:box("Binder", V3(0.7, 0.85, 0.16), CF(bx - 0.15, by + 0.43, mz + 0.8 + i * 0.18), lk(({ rgb(30, 30, 34), rgb(120, 20, 40), rgb(30, 30, 34) })[i + 1]))
		end
	end
	-- 가격판 (왼쪽 벽, 팔찌 보드 옆 넓은 쪽)
	local wb = R.one("WristbandBoard")
	local zA, zB = R.bz + 0.2, R.fz - 0.2
	if wb then
		local lo = { R.bz + 0.25, wb.mn.Z - 0.25 }
		local up = { wb.mx.Z + 0.25, R.fz - 0.25 }
		if up[2] - up[1] >= lo[2] - lo[1] then
			zA, zB = up[1], up[2]
		else
			zA, zB = lo[1], lo[2]
		end
	end
	-- 반대쪽 좁은 벽 (데스크 위): 사업자등록증 · 영업신고증 액자 (계산대 손님 쪽에서 보이는 높이)
	if wb then
		local lo0, lo1 = R.bz + 0.25, wb.mn.Z - 0.25
		local up0, up1 = wb.mx.Z + 0.25, R.fz - 0.25
		local c0, c1 = lo0, lo1
		if math.abs((zA + zB) / 2 - (lo0 + lo1) / 2) < 0.5 then
			c0, c1 = up0, up1
		end
		if c1 - c0 > 1.4 then
			P:free(function()
				Props.license(P, R.wall("left", (c0 + c1) / 2, 6.7, 0.0), "CLUB OCEAN 광안\n대표 오OO\n617-81-24680")
				Props.frame(P, R.wall("left", (c0 + c1) / 2, 4.75, 0.0), 1.2, 1.6, { frame = Look.goldMetal, text = "영업신고증\n\n유흥주점영업\nCLUB OCEAN 광안\n\n부산광역시 수영구청장", fg = rgb(40, 40, 40), textH = 0.9, border = 0.06, depth = 0.05 })
			end)
		end
	end
	local pw = math.min(3.0, zB - zA)
	if pw > 1.6 then
		local dcf = R.wall("left", (zA + zB) / 2, 5.3, 0.0)
		lightbox(P, "PriceBoard", dcf, pw, 4.6, "ADMISSION\n입장료", "일 ~ 목 기본 입장\n₩30,000 (1 DRINK)\n\n금 · 토 · 공휴일 전날\n₩50,000 (1 DRINK)\n\nVIP 테이블 ₩300,000~\n보틀 서비스 ₩150,000~\n\n팔찌 착용 시 재입장 무료", { titleH = 1.0, accent = CY })
	end
	-- 대기 줄 스탠션 (창구 앞, 카운터와 나란히)
	local qx = gx1 + 3.4
	local pts = {}
	for i, z in { z0 - 0.4, (z0 + top.c.Z) / 2 - 0.6, top.c.Z - 1.75 } do
		local pcf = CF(qx, 0, z)
		if spotOK(P, pcf, V3(0.9, 3.2, 0.9), 0.05, "queue post " .. i) then
			table.insert(pts, stanchion(P, pcf))
		else
			table.insert(pts, false)
		end
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		if a and b then
			rope(P, a, b, 0.42)
		end
	end
	if pts[1] then
		-- 첫 기둥 위 안내판 (사인 홀더)
		local p1: Vector3 = pts[1]
		local s = CF(p1.X, p1.Y + 0.75, p1.Z) * ANG(0, PI / 2, 0)
		P:box("SignHolder", V3(1.3, 0.9, 0.05), s * ANG(-0.15, 0, 0), BMETAL)
		txt(P, "QueueSign", 1.2, 0.8, s * ANG(-0.15, 0, 0) * CF(0, 0, 0.03), "QUEUE\n대기 줄 · 입장료", rgb(255, 255, 255), rgb(20, 20, 24), F.GothamBold, 1.1)
		txt(P, "QueueSignB", 1.2, 0.8, s * ANG(0, PI, 0) * ANG(-0.15, 0, 0) * CF(0, 0, 0.03), "QUEUE\n대기 줄 · 입장료", rgb(255, 255, 255), rgb(20, 20, 24), F.GothamBold, 1.1)
		P:vcyl("SignHolderStem", 0.4, 0.06, CF(p1.X, p1.Y + 0.25, p1.Z), BMETAL)
	end
	-- 대기선 (바닥 스티커)
	P:box("WaitLine", V3(2.6, 0.02, 0.12), CF(gx1 + 1.5, 0.01, top.c.Z - 1.85), lk(rgb(240, 200, 60)))
	txt(P, "WaitLineText", 2.4, 0.4, topCF(V3(gx1 + 1.5, 0.022, top.c.Z - 2.15), V3(0, 0, 1)), "WAIT HERE · 대기선", rgb(240, 200, 60), nil, F.GothamBold)
	-- 계산대 위 따뜻한 불빛
	local lh = R.one("CashierLightHost")
	if lh then
		local bulb = P:disc("CashierDownlight", 0.6, 0.04, CF(gx1 - 1.0, R.H - 0.02, top.c.Z), nl(rgb(255, 226, 190)))
		K:light(bulb, "SpotLight", { Face = Enum.NormalId.Left, Angle = 80, Range = 14, Brightness = 1.6, Color = rgb(255, 222, 186) })
		P:disc("CashierDownlightTrim", 0.72, 0.03, CF(gx1 - 1.0, R.H - 0.015, top.c.Z), BRASS)
	end
end

-- 소지품 검사대 (CLUB OCEAN 간판 아래)
local function lobbyBagCheck(R: any)
	local P = R.P
	local sign = R.one("Sign_CLUB OCEAN")
	local cx = -14.6
	if sign then
		cx = sign.c.X + 3.4
	end
	local w, d, h = 4.2, 1.7, 3.0
	local zc = R.bz + 0.05 + d / 2
	local pcf = CF(cx, 0, zc)
	if not spotOK(P, pcf, V3(w, h, d), 0.0, "bag check table") then
		return
	end
	-- 접이식 블랙 테이블 + 스커트
	P:box("BagTableTop", V3(w, 0.12, d), CF(cx, h - 0.06, zc), MATTE)
	P:box("BagTableSkirt", V3(w, 2.4, 0.04), CF(cx, h - 1.3, zc + d / 2 - 0.02), lk(rgb(18, 18, 22), M.Fabric))
	P:box("BagTableSkirtSide", V3(0.04, 2.4, d), CF(cx - w / 2 + 0.02, h - 1.3, zc), lk(rgb(18, 18, 22), M.Fabric))
	P:box("BagTableSkirtSide", V3(0.04, 2.4, d), CF(cx + w / 2 - 0.02, h - 1.3, zc), lk(rgb(18, 18, 22), M.Fabric))
	for _, sx in { -1, 1 } do
		P:vcyl("BagTableLeg", h - 0.12, 0.12, CF(cx + sx * (w / 2 - 0.25), (h - 0.12) / 2, zc - d / 2 + 0.25), BMETAL)
	end
	txt(P, "BagCheckSkirtText", 3.4, 0.9, CF(cx, 1.55, zc + d / 2 + 0.002), "BAG CHECK · 소지품 검사", rgb(255, 255, 255), nil, F.GothamBlack, 1.0)
	-- 회색 플라스틱 바구니 3개 (하나엔 폰 · 지갑 · 열쇠)
	for i, tx in { -1.35, 0.0 } do
		local t = CF(cx + tx, h, zc + 0.1)
		P:box("TrayBottom", V3(1.2, 0.04, 0.9), t * CF(0, 0.02, 0), PLASTIC_GREY)
		P:box("TrayWall", V3(1.2, 0.26, 0.05), t * CF(0, 0.13, 0.43), PLASTIC_GREY)
		P:box("TrayWall", V3(1.2, 0.26, 0.05), t * CF(0, 0.13, -0.43), PLASTIC_GREY)
		P:box("TrayWall", V3(0.05, 0.26, 0.9), t * CF(0.58, 0.13, 0), PLASTIC_GREY)
		P:box("TrayWall", V3(0.05, 0.26, 0.9), t * CF(-0.58, 0.13, 0), PLASTIC_GREY)
		if i == 1 then
			P:box("PhoneInTray", V3(0.3, 0.03, 0.6), t * CF(-0.2, 0.06, 0) * ANG(0, 0.3, 0), lk(rgb(20, 20, 24)))
			P:box("WalletInTray", V3(0.4, 0.06, 0.3), t * CF(0.25, 0.07, -0.15), Look.leatherBrown)
			P:box("KeysInTray", V3(0.2, 0.02, 0.08), t * CF(0.25, 0.05, 0.22), CHROME)
		end
	end
	-- 금속 탐지봉 (노랑 손잡이) · 손전등
	local wz = zc - 0.2
	P:box("WandHandle", V3(0.12, 0.12, 0.6), CF(cx + 1.25, h + 0.06, wz) * ANG(0, 0.4, 0), lk(rgb(240, 196, 30), M.Plastic))
	P:box("WandHead", V3(0.2, 0.06, 0.9), CF(cx + 1.25, h + 0.04, wz) * ANG(0, 0.4, 0) * CF(0, 0, -0.72), lk(rgb(24, 24, 26), M.Plastic))
	P:cyl("Flashlight", 0.6, 0.1, CF(cx + 1.4, h + 0.05, zc + 0.5) * ANG(0, 0.2, 0), BMETAL)
	-- 귀마개 무료 통
	P:vcyl("EarplugJar", 0.36, 0.34, CF(cx + 1.75, h + 0.18, zc + 0.35), gl(rgb(240, 250, 255), 0.35))
	for i = 1, 5 do
		P:ball("Earplug", 0.07, CF(cx + 1.7 + rnd(3, i) * 0.12, h + 0.1 + rnd(4, i) * 0.06, zc + 0.3 + rnd(5, i) * 0.1), lk(({ rgb(255, 140, 40), rgb(255, 230, 60), rgb(90, 200, 255) })[i % 3 + 1]))
	end
	-- 반입 금지 안내 (테이블 위 아크릴 스탠드, 줄 서는 쪽을 봄)
	acrylicStand(P, CF(cx - 1.4, h, zc - 0.66), 1.2, 0.8, "반입 금지\n외부 음식 · 음료\n위험물 · 레이저 포인터", rgb(255, 255, 255), rgb(170, 24, 30))
end

-- 메인홀 입구: 팔찌 확인 포디움 + 스탠션 + 로프
local function lobbyHallDoor(R: any)
	local P, K = R.P, R.K
	local x0, x1 = R.doorX0, R.doorX1
	local zp = R.bz + 0.95
	-- 포디움 (문 왼쪽)
	local px = x0 - 2.15
	local pcf = CF(px, 0, zp)
	if spotOK(P, pcf, V3(1.9, 3.9, 1.3), 0.0, "wristband podium") then
		P:box("PodiumPlinth", V3(1.7, 0.2, 1.1), CF(px, 0.1, zp), BRASS)
		P:box("PodiumBody", V3(1.5, 3.1, 0.9), CF(px, 1.75, zp), MATTE)
		P:box("PodiumFrontGlow", V3(1.3, 2.4, 0.02), CF(px, 1.8, zp + 0.46), nl(dk(CY, 0.35), 0.15))
		txt(P, "PodiumFrontText", 1.2, 1.4, CF(px, 2.0, zp + 0.475), "WRIST\nBAND\n팔찌 확인", rgb(255, 255, 255), nil, F.GothamBlack, 1.3)
		local slope = CF(px, 3.38, zp + 0.05) * ANG(-0.35, 0, 0)
		P:box("PodiumTop", V3(1.7, 0.1, 1.2), slope, BRASS)
		P:box("PodiumTopPad", V3(1.5, 0.02, 1.0), slope * CF(0, 0.06, 0), lk(rgb(26, 26, 30), M.Leather))
		-- 태블릿 (팔찌 확인 화면)
		local tcf = slope * CF(0.1, 0.09, 0.05)
		P:box("PodiumTablet", V3(0.95, 0.04, 0.68), tcf, lk(rgb(22, 22, 24)))
		local scr, lbl = txt(P, "PodiumTabletScreen", 0.86, 0.6, tcf * CF(0, 0.025, 0) * ANG(-PI / 2, 0, 0), "WRISTBAND\n팔찌를 보여 주세요", rgb(220, 250, 255), rgb(10, 40, 60), F.GothamBold, 1.3)
		-- UV 손전등
		P:cyl("UVLight", 0.55, 0.1, slope * CF(-0.55, 0.1, -0.2) * ANG(0, 0.5, 0), BMETAL)
		P:disc("UVLens", 0.09, 0.02, slope * CF(-0.55, 0.1, -0.2) * ANG(0, 0.5, 0) * CF(0.28, 0, 0) * ANG(0, 0, PI / 2), nl(rgb(150, 60, 255)))
		local led = P:box("PodiumLEDLine", V3(1.5, 0.05, 0.05), CF(px, 0.24, zp + 0.47), nl(CY))
		K:light(led, "PointLight", { Range = 7, Brightness = 0.9, Color = CY })
		-- 상호작용: 팔찌 확인 (읽기만: 내 ClubOceanWristbandUntil)
		Interact.prompt(K, scr, {
			action = "팔찌 확인",
			object = "입장 팔찌",
			fn = function()
				if lbl and lbl.Parent then
					lbl.Text = wristbandText()
					task.delay(6, function()
						if lbl.Parent then
							lbl.Text = "WRISTBAND\n팔찌를 보여 주세요"
						end
					end)
				end
			end,
		})
	end
	-- 문 양옆 스탠션 (로프는 오른쪽 기둥에서 벽 고리로 걸어 둠 = 열린 상태)
	local zs = R.bz + 0.75
	local a, b
	if spotOK(P, CF(x0 - 0.55, 0, zs), V3(0.9, 3.2, 0.9), 0.0, "door post L") then
		a = stanchion(P, CF(x0 - 0.55, 0, zs), 3.1, BRASS)
	end
	if spotOK(P, CF(x1 + 0.55, 0, zs), V3(0.9, 3.2, 0.9), 0.0, "door post R") then
		b = stanchion(P, CF(x1 + 0.55, 0, zs), 3.1, BRASS)
	end
	if b then
		local hook = V3(x1 + 0.55, b.Y, R.bz + 0.06)
		P:box("WallRopeHook", V3(0.2, 0.2, 0.12), CF(hook + V3(0, 0, 0.06)), BRASS)
		rope(P, b, hook, 0.25)
	end
	if a then
		local hook = V3(x0 - 0.55, a.Y, R.bz + 0.06)
		P:box("WallRopeHook", V3(0.2, 0.2, 0.12), CF(hook + V3(0, 0, 0.06)), BRASS)
		rope(P, a, hook, 0.25)
	end
	-- 물품보관 안내 (문 오른쪽 벽, 눈높이)
	P:free(function()
		lightbox(P, "CoatWay", R.wall("back", x1 + 1.35, 6.4, 0.0), 1.6, 1.3, "COAT CHECK", "물품보관 ₩3,000\n입장 후 왼쪽 ↰", { titleH = 0.38, accent = rgb(255, 200, 90), frame = BMETAL })
	end)
	-- 문틀 브라스 몰딩 + 문 위 시안 라인
	P:free(function()
		P:plate("DoorJambTrim", 0.16, 9.4, 0.08, R.wall("back", x0 - 0.08, 4.7, 0.0), BRASS)
		P:plate("DoorJambTrim", 0.16, 9.4, 0.08, R.wall("back", x1 + 0.08, 4.7, 0.0), BRASS)
	end)
end

-- 포토월: 포토존 스티커 (원래 스티커 대신) · 업라이트 · 폰 촬영 (플래시)
local function lobbyPhoto(R: any)
	local P, K = R.P, R.K
	local sr = R.one("StepAndRepeat")
	if not sr then
		return
	end
	local mark = R.one("PhotoMark")
	local mx, mz = sr.c.X, sr.mn.Z - 1.9
	if mark then
		mx, mz = mark.c.X, mark.c.Z
		R.hide(mark.part)
	end
	-- 원형 포토존 스티커 + 발자국
	P:free(function()
		P:disc("PhotoZoneSticker", 2.9, 0.02, CF(mx, 0.012, mz), lk(rgb(20, 20, 24)))
		P:disc("PhotoZoneRing", 3.1, 0.016, CF(mx, 0.01, mz), lk(PK))
		txt(P, "PhotoZoneText", 2.3, 0.55, topCF(V3(mx, 0.024, mz - 0.75), V3(0, 0, -1)), "PHOTO ZONE · 포토존", PK, nil, F.GothamBlack)
		for _, s in { -1, 1 } do
			P:ell("Footprint", V3(0.32, 0.01, 0.62), CF(mx + s * 0.33, 0.025, mz + 0.25) * ANG(0, s * 0.08, 0), lk(rgb(240, 240, 240)))
			P:ell("FootprintHeel", V3(0.26, 0.01, 0.3), CF(mx + s * 0.33, 0.025, mz + 0.7), lk(rgb(240, 240, 240)))
		end
	end)
	-- 배경 아래 업라이트 (바닥 캔 조명, 벽에 붙임)
	for _, ux in { sr.mn.X + 0.8, sr.mx.X - 0.8 } do
		local pcf = CF(ux, 0, sr.mn.Z - 0.5)
		if spotOK(P, pcf, V3(0.6, 0.5, 0.6), 0, "uplight") then
			P:vcyl("UplightCan", 0.42, 0.5, CF(ux, 0.21, sr.mn.Z - 0.5), BMETAL)
			P:disc("UplightLens", 0.38, 0.02, CF(ux, 0.43, sr.mn.Z - 0.5), nl(rgb(255, 120, 200)))
			P:box("UplightGlow", V3(0.6, 3.2, 0.02), CF(ux, 1.8, sr.mn.Z - 0.02), nl(PK, 0.82))
		end
	end
	-- 링라이트 폰 (거치대 위 폰 화면) + 플래시판
	local holder = R.one("PhoneHolder")
	local ring = R.one("RingLight")
	if holder and ring then
		local hp = holder.c
		-- 폰은 거치대에 세로로, 화면이 사진 찍는 사람 쪽(-Z), 카메라가 포토월 쪽(+Z)
		local pcf = CF(hp.X, hp.Y, hp.Z - 0.05)
		P:box("PhonePhoto", V3(0.34, 0.66, 0.04), pcf, lk(rgb(18, 18, 20)))
		local scr, lbl = txt(P, "PhonePhotoScreen", 0.3, 0.6, pcf * CF(0, 0, -0.022) * ANG(0, PI, 0), "📷\n포토월", rgb(255, 255, 255), rgb(30, 24, 40), F.GothamBold, 1.4)
		P:disc("PhoneCamLens", 0.07, 0.02, pcf * CF(0.08, 0.24, 0.03) * ANG(PI / 2, 0, 0), lk(rgb(10, 10, 12), M.Glass))
		local fl = P:disc("RingFlash", ring.s.X * 0.62, 0.03, CF(ring.c.X, ring.c.Y, ring.c.Z + 0.12) * ANG(PI / 2, 0, 0), lk(rgb(255, 255, 255), M.Neon, { t = 1 }))
		local flight = K:light(fl, "PointLight", { Range = 18, Brightness = 0, Color = rgb(255, 250, 244) })
		if flight then
			flight.Enabled = false
		end
		Interact.prompt(K, scr, {
			action = "포토월 촬영",
			object = "링라이트 폰",
			sound = "rbxasset://sounds/electronicpingshort.wav",
			fn = function(n)
				local count = { "3", "2", "1" }
				task.spawn(function()
					for _, c in count do
						if lbl.Parent then
							lbl.Text = c
						end
						task.wait(0.45)
					end
					flash(fl, flight)
					if lbl.Parent then
						lbl.Text = string.format("찰칵!\n#CLUBOCEAN\n%d장", n)
					end
					task.wait(3)
					if lbl.Parent then
						lbl.Text = "📷\n포토월"
					end
				end)
			end,
		})
	end
	-- 배경판 위 'tag us' 안내 아크릴 (작게, 배경판 오른쪽 아래)
	txt(P, "PhotoTagText", 2.6, 0.5, CF(sr.mx.X - 1.6, 1.0, sr.mn.Z - 0.02) * ANG(0, PI, 0), "📸 #CLUBOCEAN 태그하면 웰컴 음료 1잔", rgb(255, 255, 255), rgb(150, 20, 90), F.GothamBold, 1.1)
end

-- 락커 32칸: 몸체 · 번호판을 우리 것으로 다시 짓고 (속이 빈 칸), 문마다 번호판 · 손잡이 · 키 (빈 칸엔 코일 키 밴드), 119번 열림
-- 락커 문 앞면 (문 위에 덧댐): 새틴 그라파이트 판 (문보다 작게 = 줄눈) · 브라스 번호판 · RFID 리더 (상태 LED) ·
-- 세로 손잡이 홈 · 통풍 슬롯 · 빈 칸엔 팔찌 키 (코일 밴드 + 태그) 를 고리에. face = 문 앞면 dcf (+X = 보는 사람 오른쪽 = 경첩 반대가 왼쪽)
local LOCKER_FACE = lk(rgb(84, 86, 92), M.Metal)
local LOCKER_READER = lk(rgb(14, 14, 16), M.SmoothPlastic, { r = 0.08 })
local function lockerFace(P: any, K: any, face: CFrame, dw: number, dh: number, n: number, free: boolean, detail: boolean, z0: number?)
	local f = face * CF(0, 0, z0 or 0)
	local hw = dw / 2
	P:plate("LockerFace", dw - 0.1, dh - 0.1, 0.03, f, LOCKER_FACE)
	local d = 0.03
	-- 번호판 (위 가운데)
	txt(P, "LockerNo", 0.52, 0.24, f * CF(0, dh / 2 - 0.3, d), tostring(n), rgb(34, 26, 14), nil, F.GothamBold, nil, { look = BRASS })
	-- RFID 리더 (열리는 쪽 = 보는 사람 왼쪽, 손잡이 홈 안쪽)
	local rx = -hw + 0.58
	P:plate("LockerReader", 0.4, 0.66, 0.02, f * CF(rx, 0.02, d), LOCKER_READER)
	P:plate("LockerLED", 0.24, 0.07, 0.012, f * CF(rx, 0.24, d + 0.02), nl(if free then rgb(60, 230, 120) else rgb(255, 60, 50)))
	txt(P, "LockerTap", 0.32, 0.3, f * CF(rx, -0.08, d + 0.021), "TAP\n))))", rgb(110, 200, 235), nil, F.GothamBold, 0.6)
	-- 손잡이 홈 (세로, 문 모서리)
	P:plate("LockerPull", 0.1, 0.9, 0.012, f * CF(-hw + 0.17, 0.0, d), lk(rgb(12, 12, 14)))
	P:plate("LockerPullLip", 0.03, 0.9, 0.02, f * CF(-hw + 0.235, 0.0, d), CHROME)
	if detail then
		for k = 0, 2 do
			P:plate("LockerVent", dw * 0.42, 0.035, 0.008, f * CF(0.18, -dh / 2 + 0.28 + k * 0.1, d), lk(rgb(16, 16, 18)))
		end
	end
	if free then
		-- 빈 칸: 리더 아래 고리에 걸린 팔찌 키 (코일 밴드 정면 = 고리 모양 + 번호 태그)
		local by = -0.48
		P:plate("KeyHook", 0.05, 0.12, 0.08, f * CF(rx, by + 0.12, d), CHROME)
		P:cyl("KeyBand", 0.06, 0.34, f * CF(rx, by - 0.08, d + 0.06) * ANG(0, PI / 2, 0), lk(CY, M.Plastic, { t = 0.1 }))
		P:cyl("KeyBandHole", 0.08, 0.22, f * CF(rx, by - 0.08, d + 0.06) * ANG(0, PI / 2, 0), LOCKER_FACE)
		if detail then
			txt(P, "KeyFob", 0.16, 0.16, f * CF(rx, by - 0.3, d + 0.1), tostring(n), rgb(240, 240, 240), rgb(16, 60, 86), F.GothamBold)
		end
	end
	local _ = K
end

local function lobbyLockers(R: any)
	local P, K = R.P, R.K
	local car = R.one("LockerCarcass")
	local doors = R.find("LockerDoor")
	if not car or #doors == 0 then
		return
	end
	local leds = R.find("KeypadLED")
	-- 열 · 행 (정렬 프레임 중심)
	local xs, ys = {}, {}
	local function addU(t: { number }, v: number)
		for _, u in t do
			if math.abs(u - v) < 0.4 then
				return
			end
		end
		table.insert(t, v)
	end
	for _, d in doors do
		addU(xs, d.c.X)
		addU(ys, d.c.Y)
	end
	table.sort(xs, function(a, b)
		return a > b
	end)
	table.sort(ys, function(a, b)
		return a > b
	end)
	local zf = doors[1].mn.Z -- 문 앞면
	local dw, dh = doors[1].s.X, doors[1].s.Y
	-- 몸체 숨기고 속 빈 몸체 다시 (뒤판 · 위 · 아래 · 옆 · 칸막이)
	R.hide(car.part)
	local num = R.one("LockerNumbers")
	if num then
		R.hide(num.part)
	end
	local cx0, cx1, cy1 = car.mn.X, car.mx.X, car.mx.Y
	local zb = math.min(car.mx.Z, R.fz)
	local depth = zb - zf
	local CARC = lk(rgb(92, 94, 100), M.Metal) -- 헤어라인 프레임 (문 사이 줄눈이 보이게)
	P:free(function()
		P:box("LockerBack", V3(cx1 - cx0, cy1, 0.06), CF((cx0 + cx1) / 2, cy1 / 2, zb - 0.03), lk(rgb(20, 20, 23)))
		P:box("LockerTop", V3(cx1 - cx0, 0.1, depth), CF((cx0 + cx1) / 2, cy1 - 0.05, zf + depth / 2), CARC)
		P:box("LockerPlinth", V3(cx1 - cx0, 0.45, depth), CF((cx0 + cx1) / 2, 0.225, zf + depth / 2 + 0.02), lk(rgb(16, 16, 18)))
		P:box("LockerKickLED", V3(cx1 - cx0 - 0.2, 0.04, 0.04), CF((cx0 + cx1) / 2, 0.3, zf - 0.0), nl(CY))
		P:box("LockerSide", V3(0.1, cy1, depth), CF(cx0 + 0.05, cy1 / 2, zf + depth / 2), CARC)
		P:box("LockerSide", V3(0.1, cy1, depth), CF(cx1 - 0.05, cy1 / 2, zf + depth / 2), CARC)
		for i = 1, #xs - 1 do
			local x = (xs[i] + xs[i + 1]) / 2
			P:box("LockerDivider", V3(0.08, cy1 - 0.55, depth), CF(x, 0.45 + (cy1 - 0.55) / 2, zf + depth / 2), CARC)
		end
		for j = 1, #ys - 1 do
			local y = (ys[j] + ys[j + 1]) / 2
			P:box("LockerShelf", V3(cx1 - cx0 - 0.2, 0.08, depth), CF((cx0 + cx1) / 2, y, zf + depth / 2), CARC)
		end
		-- 칸 줄눈 LED (선반 앞 모서리, 은은한 시안): 어두운 로비에서 락커 격자가 보이게
		for j = 1, #ys - 1 do
			local y = (ys[j] + ys[j + 1]) / 2
			P:box("LockerShelfLED", V3(cx1 - cx0 - 0.3, 0.025, 0.025), CF((cx0 + cx1) / 2, y, zf - 0.03), nl(dk(CY, 0.45)))
		end
		P:box("LockerTopLED", V3(cx1 - cx0 - 0.1, 0.04, 0.04), CF((cx0 + cx1) / 2, cy1 - 0.12, zf - 0.03), nl(CY))
		-- 맨 아래 칸 아래 받침
		P:box("LockerShelf", V3(cx1 - cx0 - 0.2, 0.08, depth), CF((cx0 + cx1) / 2, ys[#ys] - dh / 2 - 0.05, zf + depth / 2), CARC)
	end)
	-- 문마다 디테일
	local openCol, openRow = math.min(3, #xs), math.min(3, #ys)
	local openDoor: any = nil
	for j, y in ys do
		for i, x in xs do
			local n = 100 + (j - 1) * #xs + i
			-- 이 칸의 문 · LED
			local door: any = nil
			for _, d in doors do
				if math.abs(d.c.X - x) < 0.4 and math.abs(d.c.Y - y) < 0.4 then
					door = d
				end
			end
			local led: any = nil
			for _, l in leds do
				if math.abs(l.c.X - (x + 0.8)) < 0.5 and math.abs(l.c.Y - y) < 0.5 then
					led = l
				end
			end
			local free = led ~= nil and led.part.Color.G > led.part.Color.R
			local face = CFrame.fromMatrix(V3(x, y, zf), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1)) -- dcf (보는 쪽 = -Z)
			if i == openCol and j == openRow and door then
				openDoor = { door = door, led = led, x = x, y = y, n = n, i = i, j = j }
				continue
			end
			if led then
				R.hide(led.part) -- 리더기 패널의 우리 LED 로 바꿈 (같은 색 = 같은 상태)
			end
			lockerFace(P, K, face, dw, dh, n, free, hi(K))
		end
	end
	-- 이용 안내판 (락커 오른쪽 · 벽)
	local gx = (cx1 + R.xr) / 2
	if R.xr - cx1 > 1.8 then
		-- (앞 벽 전체에 'window' keep 이 잡혀 있음: 유리창이 아니라 벽이라 free 로 붙임)
		P:free(function()
			lightbox(P, "LockerGuide", R.wall("front", gx, 5.2, 0.0), math.min(2.2, R.xr - cx1 - 0.4), 3.2, "LOCKER\n이용 안내", "① 초록 불 칸을 고르세요\n② 팔찌 키를 리더기에 태그\n③ 퇴장 시 팔찌 키 반납\n\n1회 ₩2,000 · 계산대 결제\n팔찌 키 분실 ₩10,000", { titleH = 0.9, accent = CY, frame = BMETAL })
		end)
	end
	-- 열리는 락커 (원래 문 · LED 숨김 → 우리 문)
	if openDoor then
		local d = openDoor.door
		R.hide(d.part)
		if openDoor.led then
			R.hide(openDoor.led.part)
		end
		local x, y, n = openDoor.x, openDoor.y, openDoor.n
		local face = CFrame.fromMatrix(V3(x, y, zf), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1))
		-- 칸 속: 조명 띠 · 옷걸이 봉 · 스티커
		P:free(function()
			-- 칸 위 선반 아랫면 · 양옆 칸막이 (몸체를 다시 지은 위치와 같은 식)
			local oi, oj = openDoor.i, openDoor.j
			local shelfY = if oj > 1 then (ys[oj - 1] + ys[oj]) / 2 - 0.04 else cy1 - 0.1
			local xA = if oi < #xs then (xs[oi] + xs[oi + 1]) / 2 + 0.04 else cx0 + 0.1
			local xB = if oi > 1 then (xs[oi - 1] + xs[oi]) / 2 - 0.04 else cx1 - 0.1
			P:box("LockerInnerLED", V3(dw - 0.3, 0.03, 0.04), CF(x, shelfY - 0.015, zf + 0.25), nl(rgb(240, 245, 255)))
			P:seg("LockerHangerRod", V3(xA, shelfY - 0.3, zf + depth * 0.55), V3(xB, shelfY - 0.3, zf + depth * 0.55), 0.05, CHROME)
			txt(P, "LockerInnerSticker", 0.9, 0.5, CF(x, y - 0.1, zb - 0.07) * ANG(0, PI, 0), "No." .. tostring(n) .. "\n퇴장 시 팔찌 키 반납", rgb(30, 30, 34), rgb(240, 240, 236), F.GothamBold)
			P:box("LockerHook", V3(0.06, 0.2, 0.18), CF(x + 0.6, y + 0.25, zb - 0.15), CHROME)
		end)
		local g = K:group("Locker" .. tostring(n), function()
			P:free(function()
				P:plate("LockerDoorNew", dw, dh, 0.08, face * CF(0, 0, -0.03), lk(d.part.Color, M.Metal))
				lockerFace(P, K, face, dw, dh, n, true, true, 0.05)
			end)
		end)
		-- 경첩: 보는 사람 오른쪽 = -X 쪽 모서리 → 문 바깥(-Z)으로 열림 (+Y 축 회전)
		local hinge = R.world(V3(x - dw / 2, y, zf - 0.03))
		Interact.swing(K, g, hinge, R.wdir(Vector3.yAxis), 1.9, { object = "보관함 " .. tostring(n), openText = "보관함 열기", closeText = "보관함 닫기" })
	end
end

-- 오른쪽: 이벤트 포스터 · 보조배터리 대여기 · 소화기 · 안내
local function lobbyRight(R: any)
	local P, K = R.P, R.K
	-- 뒤 벽 (메인홀 문 오른쪽) 이벤트 포스터 3 (라이트박스)
	local x0 = R.doorX1 + 1.6
	local x1 = R.xr - 0.6
	-- 오른쪽 구석 화분 잎 앞으로 포스터가 가려지지 않게
	for _, lv in R.find("Leaves") do
		if lv.mn.Z < R.bz + 1.5 and lv.mn.X - 0.3 < x1 then
			x1 = lv.mn.X - 0.3
		end
	end
	local posters = {
		{ "10.17 SAT", "K-EDM NIGHT\nDJ SEAN WAVE\n23:30 ~", rgb(255, 60, 170), { { rgb(60, 10, 70), 0, 0, 1, 0.55 }, { rgb(255, 60, 170), 0.12, 0.06, 0.76, 0.03 } } },
		{ "10.23 FRI", "TECH HOUSE\nDJ HAEWON\n23:00 ~", rgb(40, 220, 255), { { rgb(6, 40, 70), 0, 0, 1, 0.55 }, { rgb(40, 220, 255), 0.12, 0.06, 0.76, 0.03 } } },
		{ "10.31 SAT", "HALLOWEEN\n코스튬 입장\n₩10,000 할인", rgb(255, 150, 40), { { rgb(60, 26, 6), 0, 0, 1, 0.55 }, { rgb(255, 150, 40), 0.12, 0.06, 0.76, 0.03 } } },
	}
	local n = #posters
	local pw = math.min(2.6, (x1 - x0) / n - 0.5)
	if pw > 1.5 then
		for i, p in posters do
			local u = x0 + (x1 - x0) * (i - 0.5) / n
			lightbox(P, "EventPoster", R.wall("back", u, 5.6, 0.0), pw, 3.8, p[1], p[2], { titleH = 0.6, accent = p[3], art = p[4], frame = BMETAL })
			P:plate("PosterSpotGlow", pw + 0.5, 0.05, 0.03, R.wall("back", u, 7.68, 0.0), nl(p[3]))
		end
		P:free(function()
			txt(P, "NowShowingTitle", 6.0, 0.55, R.wall("back", (x0 + x1) / 2, 8.25, 0.02), "UPCOMING · 이번 주 라인업", rgb(240, 240, 240), nil, F.GothamBlack, 1.2)
		end)
	end
	-- 보조배터리 대여기 (오른쪽 벽, 앞쪽 끝)
	local bench = R.one("BenchBase")
	local zk = R.fz - 1.0
	if bench then
		zk = math.min(R.fz - 0.9, (bench.mx.Z + R.fz) / 2)
	end
	local kd = R.wall("right", zk, 3.9, 0.0)
	P:free(function()
		P:plate("ChargeKioskBody", 1.3, 2.2, 0.5, kd, lk(rgb(240, 240, 236), M.Plastic))
		P:plate("ChargeKioskTop", 1.3, 0.5, 0.52, kd * CF(0, 0.85, 0), lk(rgb(255, 196, 30), M.Plastic))
		txt(P, "ChargeKioskBrand", 1.2, 0.4, kd * CF(0, 0.86, 0.522), "보조배터리 대여", rgb(30, 30, 30), nil, F.GothamBlack)
		local _, lbl = txt(P, "ChargeKioskScreen", 0.9, 0.6, kd * CF(0, 0.25, 0.505), "대여 ₩3,000\nQR 스캔", rgb(255, 255, 255), rgb(20, 60, 120), F.GothamBold, 1.3)
		loopText(K, lbl, { "대여 ₩3,000\nQR 스캔", "남은 배터리\n6 / 8", "C · 8핀 · 5핀\n케이블 내장" }, 4)
		for k = 0, 3 do
			for s = 0, 1 do
				local slot = kd * CF(-0.3 + s * 0.6, -0.3 - k * 0.2, 0.505)
				P:plate("BatterySlot", 0.5, 0.15, 0.02, slot, lk(rgb(30, 30, 34)))
				P:plate("BatteryLED", 0.06, 0.06, 0.03, slot * CF(0.2, 0, 0), nl(if (k + s) % 4 == 3 then rgb(255, 60, 50) else rgb(60, 230, 120)))
			end
		end
	end)
	-- 소화기 (계산대 뒤 직원 구역 구석 · 뒤 벽)
	local fx = R.xl + 0.5
	local fz = R.bz + 0.32
	if spotOK(P, CF(fx, 0, fz), V3(0.55, 2.4, 0.55), 0, "extinguisher") then
		P:vcyl("ExtinguisherBody", 1.5, 0.42, CF(fx, 0.95, fz), lk(rgb(200, 24, 28)))
		P:ball("ExtinguisherTop", 0.42, CF(fx, 1.7, fz), lk(rgb(200, 24, 28)))
		P:box("ExtinguisherValve", V3(0.14, 0.22, 0.14), CF(fx, 1.95, fz), BMETAL)
		P:box("ExtinguisherLever", V3(0.36, 0.05, 0.08), CF(fx + 0.08, 2.08, fz), BMETAL)
		P:seg("ExtinguisherHose", V3(fx + 0.07, 1.95, fz), V3(fx + 0.2, 1.1, fz + 0.1), 0.06, BMETAL)
		P:box("ExtinguisherLabel", V3(0.3, 0.5, 0.02), CF(fx, 1.0, fz + 0.21), lk(WHITE))
		P:free(function()
			txt(P, "ExtinguisherSign", 0.9, 0.4, R.wall("back", fx + 0.1, 2.7, 0.0), "소화기", rgb(255, 255, 255), rgb(200, 24, 28), F.GothamBlack)
		end)
	end
end

-- 걸레받이 (앞 · 뒤 벽, 막힌 곳 빼고)
-- 벽 패널 (뒤 벽: 블랙 래커 패널 + 브라스 줄눈) · 천장 핀 스폿 · 벽 워시 조명 · 오른쪽 벨벳 벽 브라켓 등
local function lobbyFinish(R: any)
	local P, K = R.P, R.K
	local H = R.H
	-- 뒤 벽 줄눈 (2.4 간격, 간판 · 문 · 소지품 검사 안내판 피함)
	local skip = {}
	for _, n in { "Sign_CLUB OCEAN", "Sign_TABLE · BAR · DJ ▶" } do
		local f = R.one(n)
		if f then
			table.insert(skip, { f.mn.X - 0.1, f.mx.X + 0.1, f.mn.Y - 0.1, f.mx.Y + 0.1 })
		end
	end
	P:free(function()
		local x = R.xl + 2.4
		while x < R.xr - 1.0 do
			if not (x > R.doorX0 - 0.6 and x < R.doorX1 + 0.6) then
				-- 간판과 겹치는 높이는 잘라서
				local y0, y1 = 0.42, H - 0.7
				local cuts = { { y0, y1 } }
				for _, sk in skip do
					if x > sk[1] and x < sk[2] then
						cuts = { { y0, sk[3] }, { sk[4], y1 } }
					end
				end
				for _, c in cuts do
					if c[2] - c[1] > 0.3 then
						P:plate("WallReveal", 0.05, c[2] - c[1], 0.03, R.wall("back", x, (c[1] + c[2]) / 2, 0.0), BRASS)
					end
				end
			end
			x += 2.4
		end
		-- 천장 핀 스폿 (작은 매입 다운라이트 두 줄)
		local ring = R.one("CeilingRing")
		local rx, rz, rr = 0, -0.5, 4.8
		if ring then
			rx, rz, rr = ring.c.X, ring.c.Z, ring.s.X / 2 + 0.6
		end
		for _, z in { R.bz + 2.2, R.fz - 2.6 } do
			local xx = R.xl + 3.5
			while xx < R.xr - 3 do
				if (V3(xx - rx, 0, z - rz)).Magnitude > rr then
					P:disc("PinSpotTrim", 0.42, 0.03, CF(xx, H - 0.015, z), BRASS)
					P:disc("PinSpot", 0.26, 0.04, CF(xx, H - 0.03, z), nl(rgb(255, 228, 196)))
				end
				xx += 5.0
			end
		end
	end)
	-- 바닥 가운데 브라스 메달리온 (인레이 사각 안, 천장 링 아래)
	local inl = R.one("InlayField")
	if inl then
		P:free(function()
			P:disc("FloorMedallionRing", 5.2, 0.014, CF(inl.c.X, inl.mx.Y + 0.007, inl.c.Z), BRASS)
			P:disc("FloorMedallion", 4.9, 0.018, CF(inl.c.X, inl.mx.Y + 0.009, inl.c.Z), lk(rgb(16, 16, 18), M.Marble))
			P:disc("FloorMedallionInner", 2.2, 0.022, CF(inl.c.X, inl.mx.Y + 0.011, inl.c.Z), BRASS)
			P:disc("FloorMedallionCore", 2.0, 0.026, CF(inl.c.X, inl.mx.Y + 0.013, inl.c.Z), lk(rgb(16, 16, 18), M.Marble))
			txt(P, "FloorMedallionText", 1.8, 0.7, topCF(V3(inl.c.X, inl.mx.Y + 0.03, inl.c.Z), V3(0, 0, -1)), "CLUB\nOCEAN", rgb(214, 180, 104), nil, F.GothamBlack)
			txt(P, "FloorMedallionSub", 3.6, 0.36, topCF(V3(inl.c.X, inl.mx.Y + 0.03, inl.c.Z + 1.65), V3(0, 0, -1)), "광안 · GWANGALLI · EST. 2026", rgb(214, 180, 104), nil, F.GothamBold)
		end)
	end
	-- 벽 워시 조명 (락커 · 소지품 검사 · 포스터): 천장 핀 스폿에서 아래로
	local function wash(x: number, z: number, at: Vector3, angle: number, br: number)
		local head = CFrame.lookAt(V3(x, H - 0.25, z), at)
		local lens = P:box("WashLens", V3(0.3, 0.3, 0.05), head, nl(rgb(255, 232, 205)))
		P:box("WashCan", V3(0.42, 0.42, 0.3), head * CF(0, 0, 0.17), BMETAL)
		K:light(lens, "SpotLight", { Face = Enum.NormalId.Front, Angle = angle, Range = 15, Brightness = br, Color = rgb(255, 228, 200) })
	end
	P:free(function()
		local car = R.one("LockerCarcass")
		if car then
			wash(car.c.X, R.fz - 4.6, V3(car.c.X, 3.2, R.fz), 100, 2.6)
		end
		local sign = R.one("Sign_CLUB OCEAN")
		if sign then
			wash(sign.c.X + 2.0, R.bz + 3.4, V3(sign.c.X + 2.0, 2.4, R.bz), 85, 1.3)
		end
		wash(R.doorX1 + 7.5, R.bz + 3.6, V3(R.doorX1 + 7.5, 4.5, R.bz), 90, 1.2)
	end)
	-- 오른쪽 벨벳 벽: 브라스 브라켓 등 2 (TONIGHT 간판 양옆)
	local tn = R.one("Sign_TONIGHT · 오늘 밤")
	if tn then
		for _, z in { tn.mn.Z - 0.6, tn.mx.Z + 0.6 } do
			local inLeaves = false
			for _, lv in R.find("Leaves") do
				if z > lv.mn.Z - 0.3 and z < lv.mx.Z + 0.3 and lv.mx.X > R.xr - 1.2 and lv.mx.Y > 6.4 and lv.mn.Y < 7.8 then
					inLeaves = true
				end
			end
			if z > R.bz + 0.5 and z < R.fz - 0.5 and not inLeaves then
				local d = R.wall("right", z, 7.1, 0.0)
				P:free(function()
					P:plate("SconceBack", 0.3, 0.9, 0.06, d, BRASS)
					P:cyl("SconceArm", 0.4, 0.06, d * CF(0, 0, 0.25) * ANG(0, PI / 2, 0), BRASS)
					P:vcyl("SconceShade", 0.7, 0.42, d * CF(0, 0.1, 0.45), lk(rgb(255, 214, 160), M.Neon, { t = 0.2 }))
					P:disc("SconceCap", 0.46, 0.04, d * CF(0, 0.47, 0.45), BRASS)
				end)
			end
		end
	end
end

local function lobbySkirting(R: any)
	local P = R.P
	P:free(function()
		-- 뒤 벽: 왼쪽 끝 ~ 문, 문 ~ 오른쪽 끝
		skirting(P, R, "back", R.xl, R.doorX0 - 0.2)
		skirting(P, R, "back", R.doorX1 + 0.2, R.xr)
		-- 앞 벽: 터널 입구 양옆 (포토월 · 락커 앞은 빼고)
		local sr = R.one("StepAndRepeat")
		local car = R.one("LockerCarcass")
		local a = if sr then sr.mn.X else -6.2
		skirting(P, R, "front", R.xl, a)
		local b = if car then car.mx.X else 6.2
		skirting(P, R, "front", b, R.xr)
	end)
end

local function buildLobby(K: any, V: any)
	local R = makeRoom(K, V)
	lobbyWalls(R)
	local steps = {
		{ "ceiling", lobbyCeiling },
		{ "cashier", lobbyCashier },
		{ "bagcheck", lobbyBagCheck },
		{ "halldoor", lobbyHallDoor },
		{ "photo", lobbyPhoto },
		{ "lockers", lobbyLockers },
		{ "right", lobbyRight },
		{ "skirting", lobbySkirting },
		{ "finish", lobbyFinish },
	}
	for _, s in steps do
		local ok, err = pcall(s[2], R)
		if not ok then
			K:note("lobby." .. s[1] .. " error: " .. tostring(err))
		end
	end
end

------------------------------------------------------------------------------------------------------------
-- 입장 터널 ----------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

local function buildTunnel(K: any, V: any)
	local R = makeRoom(K, V)
	local P = R.P
	R.xl, R.xr, R.fz, R.bz = -5.05, 4.95, 9.8, -9.8
	for _, f in R.find("TunnelWall") do
		if f.c.X < 0 then
			R.xl = f.mx.X
		else
			R.xr = f.mn.X
		end
	end
	local fl = R.one("TunnelFloor")
	if fl then
		R.bz, R.fz = fl.mn.Z, fl.mx.Z
	end
	local ce = R.one("TunnelCeiling")
	local H = if ce then ce.mn.Y else V.H
	R.H = H
	local cx = (R.xl + R.xr) / 2
	-- LED 바 위치 (벽 바 = 세로, 천장 바 = 가로)
	local barsZ = {}
	for _, f in R.find("TunnelLED") do
		if f.s.Y > 5 and f.c.X < cx then
			table.insert(barsZ, f.c.Z)
		end
	end
	table.sort(barsZ)
	local steps = {}
	-- 1) 벽: LED 바 사이 블랙 미러 패널 + 아래 헤어라인 킥 플레이트
	table.insert(steps, { "walls", function()
		P:free(function()
			local edges = { R.bz }
			for _, z in barsZ do
				table.insert(edges, z)
			end
			table.insert(edges, R.fz)
			for i = 1, #edges - 1 do
				local a, b = edges[i] + (if i == 1 then 0.05 else 0.14), edges[i + 1] - (if i == #edges - 1 then 0.05 else 0.14)
				if b - a > 0.5 then
					local zc, w = (a + b) / 2, b - a
					for _, side in { "left", "right" } do
						local d = R.wall(side, zc, 0, 0.0)
						P:plate("TunnelMirror", w, H - 1.3, 0.035, d * CF(0, 0.75 + (H - 1.3) / 2, 0), GLOSS)
						P:plate("TunnelMirrorEdge", w, 0.03, 0.04, d * CF(0, 0.73, 0), BRASS)
					end
				end
			end
			for _, side in { "left", "right" } do
				local d = R.wall(side, (R.bz + R.fz) / 2, 0, 0.0)
				P:plate("TunnelKick", R.fz - R.bz - 0.1, 0.7, 0.025, d * CF(0, 0.36, 0), Look.brushed)
			end
			-- 천장: 천장 바 사이 미러 패널
			for i = 1, #edges - 1 do
				local a, b = edges[i] + 0.22, edges[i + 1] - 0.22
				if b - a > 0.5 then
					P:box("TunnelCeilMirror", V3(R.xr - R.xl - 0.3, 0.03, b - a), CF(cx, H - 0.03, (a + b) / 2), GLOSS)
				end
			end
		end)
	end })
	-- 2) 코너 무드 라인 (천장-벽 모서리, 우리 네온 · 색 바꾸기 상호작용)
	local mood: { BasePart } = {}
	table.insert(steps, { "mood", function()
		P:free(function()
			for _, x in { R.xl + 0.14, R.xr - 0.12 } do
				table.insert(mood, P:box("TunnelMoodLine", V3(0.06, 0.06, R.fz - R.bz - 0.3), CF(x, H - 0.16, (R.bz + R.fz) / 2), nl(VI)))
			end
		end)
	end })
	-- 3) 고보 프로젝터 + 바닥 브랜드 투사 (순환)
	table.insert(steps, { "gobo", function()
		local pz = R.fz - 4.2
		P:free(function()
			P:box("GoboMount", V3(0.4, 0.3, 0.4), CF(cx, H - 0.15, pz), BMETAL)
			local head = CF(cx, H - 0.62, pz) * ANG(-1.25, 0, 0)
			P:box("GoboBody", V3(0.55, 0.55, 0.9), head, MATTE2)
			local lens = P:disc("GoboLens", 0.3, 0.03, head * CF(0, 0, -0.46) * ANG(PI / 2, 0, 0), nl(rgb(240, 250, 255)))
			K:light(lens, "SpotLight", { Face = Enum.NormalId.Left, Angle = 40, Range = 14, Brightness = 1.4, Color = rgb(190, 235, 255) })
			P:cyl("GoboFin", 0.5, 0.12, head * CF(0, 0.3, 0.1) * ANG(0, PI / 2, 0), BMETAL)
		end)
		local tz = pz - 4.6
		P:free(function()
			P:disc("GoboSpot", 4.2, 0.012, CF(cx, 0.008, tz), lk(rgb(20, 50, 70), M.Neon, { t = 0.9 }))
		end)
		local _, lbl = txt(P, "GoboText", 3.6, 1.5, topCF(V3(cx, 0.02, tz), V3(0, 0, -1)), "CLUB OCEAN\n광안 · GWANGALLI", rgb(170, 240, 255), nil, F.GothamBlack, 1.6)
		loopText(K, lbl, { "CLUB OCEAN\n광안 · GWANGALLI", "WELCOME\n오늘 밤, 광안리에서", "SAT 10.17\nK-EDM NIGHT", "▼ LOBBY\n입장료 · 팔찌" }, 3.5)
	end })
	-- 4) 천장 설비: CCTV · 스프링클러 · 감지기 · 벽 스피커
	table.insert(steps, { "ceiling", function()
		P:free(function()
			Props.cctv(P, R.xr - 0.8, R.bz + 1.0)
			Props.cctv(P, R.xl + 0.8, R.fz - 1.0)
			Props.smokeDetector(P, cx, 0.0)
			for _, z in { -6.0, 2.0 } do
				Props.sprinkler(P, cx + 2.2, z)
			end
		end)
		local spk = { { "left", R.fz - 2.0 }, { "right", R.bz + 2.0 } }
		for _, s in spk do
			local d = R.wall(s[1], s[2], H - 0.9, 0.0)
			P:free(function()
				wallSpeaker(P, d, 0.75)
			end)
		end
	end })
	-- 4a) 바닥: 양 끝 스테인리스 문턱 띠 + 가운데 포토 스팟 스티커 (무드 라인과 짝)
	table.insert(steps, { "floor", function()
		P:free(function()
			for _, z in { R.bz + 0.12, R.fz - 0.12 } do
				P:box("TunnelThreshold", V3(R.xr - R.xl - 0.2, 0.025, 0.24), CF(cx, 0.012, z), Look.brushed)
			end
			local sz = (R.bz + R.fz) / 2 - 3.8 -- 고보 투사 원 (가운데 앞쪽) 과 안 겹치게
			P:disc("TunnelPhotoSpot", 1.8, 0.012, CF(cx, 0.008, sz), lk(rgb(14, 14, 18)))
			P:disc("TunnelPhotoSpotRing", 1.95, 0.01, CF(cx, 0.006, sz), lk(VI))
			txt(P, "TunnelPhotoSpotText", 1.5, 0.5, topCF(V3(cx, 0.02, sz), V3(0, 0, -1)), "📸 TUNNEL\nPHOTO SPOT", rgb(220, 200, 255), nil, F.GothamBlack, 1.1)
		end)
	end })
	-- 4b) 통로 유도등 (벽 아래, 초록 · 화살표는 출구 = 현관 쪽)
	table.insert(steps, { "guide", function()
		P:free(function()
			for k, i in { 2, 5, 8 } do
				if barsZ[i] and barsZ[i + 1] then
					local zc = (barsZ[i] + barsZ[i + 1]) / 2
					for _, side in { "left", "right" } do
						local d = R.wall(side, zc, 1.15, 0.035)
						P:plate("GuideLightBox", 0.75, 0.38, 0.1, d, lk(rgb(230, 232, 228), M.Plastic))
						local arrow = if side == "left" then "◀ EXIT" else "EXIT ▶"
						txt(P, "GuideLight", 0.66, 0.3, d * CF(0, 0, 0.102), "🏃 " .. arrow, rgb(255, 255, 255), rgb(20, 150, 70), F.GothamBold, 1.2)
					end
				end
				local _ = k
			end
		end)
	end })
	-- 5) 안내판 (터널 입구 · 로비 쪽 끝)
	table.insert(steps, { "signs", function()
		-- 입구 쪽 (현관 끝) 왼쪽 패널 위 안내
		local z1 = if #barsZ > 0 then (barsZ[#barsZ] + R.fz) / 2 else R.fz - 0.6
		local z0 = if #barsZ > 1 then (barsZ[1] + barsZ[2]) / 2 else R.bz + 1
		P:free(function()
			lightbox(P, "TunnelRules", R.wall("left", z0, 4.6, 0.04), 1.5, 2.6, "19+", "2007년생부터 입장\n신분증 필수\n\nDRESS CODE\n슬리퍼 · 트레이닝복\n입장 불가", { titleH = 0.8, accent = rgb(255, 80, 80), frame = BMETAL })
			lightbox(P, "TunnelCCTV", R.wall("right", z0, 4.6, 0.04), 1.5, 2.6, "CCTV", "24시간 녹화 중\n\n촬영은 로비\n포토월에서 📸", { titleH = 0.8, accent = CY, frame = BMETAL })
			txt(P, "TunnelWelcome", 1.6, 0.5, R.wall("right", z1, 5.0, 0.04), "WELCOME ▶", rgb(220, 250, 255), nil, F.GothamBlack, 1.4)
		end)
	end })
	for _, s in steps do
		local ok, err = pcall(s[2])
		if not ok then
			K:note("tunnel." .. s[1] .. " error: " .. tostring(err))
		end
	end
	-- 상호작용: 무드 라인 색 바꾸기 (로비 쪽 끝 벽의 작은 터치 패널)
	local ok, err = pcall(function()
		local z0 = if #barsZ > 1 then (barsZ[1] + barsZ[2]) / 2 else R.bz + 1
		local d = R.wall("right", z0, 1.9, 0.04)
		local panel: BasePart? = nil
		P:free(function()
			P:plate("MoodPanelBack", 0.7, 0.5, 0.05, d, BMETAL)
			panel = P:plate("MoodPanel", 0.6, 0.4, 0.06, d, lk(rgb(16, 30, 44), M.Glass, { r = 0.1 }))
			txt(P, "MoodPanelText", 0.56, 0.36, d * CF(0, 0, 0.062), "PHOTO\nMOOD", CY, nil, F.GothamBold, 1.4)
		end)
		local cols = { VI, CY, PK, rgb(255, 196, 80), rgb(255, 255, 255) }
		if panel then
			Interact.cycle(K, panel, cols, {
				action = "터널 무드 색 바꾸기",
				object = "포토 무드 라인",
				start = 1,
				on = function(_i, c)
					for _, p in mood do
						if p.Parent then
							TweenService:Create(p, TweenInfo.new(0.5), { Color = c }):Play()
						end
					end
				end,
			})
		end
	end)
	if not ok then
		K:note("tunnel.mood prompt error: " .. tostring(err))
	end
end

------------------------------------------------------------------------------------------------------------
-- 메인홀 (다듬기) -----------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

-- dcf 를 방향 dir (수평 단위) 으로: +Z = dir (보는 쪽), +X = 보는 사람 오른쪽
local function faceCF(p: Vector3, dir: Vector3): CFrame
	local up = Vector3.yAxis
	return CFrame.fromMatrix(p, (-dir):Cross(up), up, dir)
end

-- 라벨 병 종류 (UI 이름은 '음료': 브랜드 이름 없음)
local BOTTLE_KINDS: { [string]: any } = {
	vodka = { name = "Vodka", body = lk(rgb(226, 236, 242), M.Glass, { t = 0.3 }), label = lk(rgb(244, 246, 250)), cap = CHROME },
	gin = { name = "Gin", body = lk(rgb(110, 186, 196), M.Glass, { t = 0.3 }), label = lk(rgb(236, 228, 208)), cap = lk(rgb(24, 44, 34)), sq = true },
	tequila = { name = "Tequila", body = lk(rgb(236, 216, 168), M.Glass, { t = 0.25 }), label = lk(rgb(196, 40, 40)), cap = lk(rgb(150, 110, 70), M.Wood), squat = true },
	whisky = { name = "Whisky", body = lk(rgb(176, 98, 30), M.Glass, { t = 0.2 }), label = lk(rgb(22, 22, 24)), cap = BRASS, sq = true },
	champ = { name = "Champagne", body = lk(rgb(24, 58, 34), M.Glass, { t = 0.1 }), label = lk(rgb(240, 232, 210)), cap = lk(rgb(214, 180, 96), M.Foil), foil = true },
	liqueur = { name = "Liqueur", body = lk(rgb(60, 128, 44), M.Glass, { t = 0.25 }), label = lk(rgb(240, 200, 60)), cap = lk(rgb(20, 20, 22)) },
	rum = { name = "Rum", body = lk(rgb(124, 62, 22), M.Glass, { t = 0.2 }), label = lk(rgb(236, 226, 196)), cap = lk(rgb(170, 30, 30)) },
	rose = { name = "Rose", body = lk(rgb(232, 150, 150), M.Glass, { t = 0.25 }), label = lk(rgb(250, 240, 236)), cap = lk(rgb(230, 190, 200), M.Foil), foil = true },
	black = { name = "Black", body = lk(rgb(20, 20, 22), M.Glass, { t = 0.05 }), label = lk(rgb(200, 170, 90)), cap = lk(rgb(20, 20, 22), M.Foil), foil = true },
}

-- 라벨 병: base = 바닥 가운데, H 전체 높이, D 지름, kd 종류, dir = 라벨 쪽, lite = 어깨 생략 (파트 절약)
local function bottle(P: any, base: Vector3, H: number, D: number, kd: any, dir: Vector3, lite: boolean?)
	local bh = H * (if kd.squat then 0.5 else 0.58)
	local bw = if kd.squat then D * 1.05 else D
	local sqw = bw * 0.86
	if kd.sq then
		P:box("Bottle" .. kd.name, V3(sqw, bh, sqw), CF(base + V3(0, bh / 2, 0)), kd.body)
	else
		P:vcyl("Bottle" .. kd.name, bh, bw, CF(base + V3(0, bh / 2, 0)), kd.body)
	end
	if not lite then
		local sw = if kd.sq then sqw else bw
		P:ell("BottleShoulder", V3(sw, H * 0.16, sw), CF(base + V3(0, bh, 0)), kd.body)
	end
	local nd = D * (if kd.foil then 0.36 else 0.3)
	local nh = H * 0.94 - bh
	P:vcyl("BottleNeck", nh, nd, CF(base + V3(0, bh + nh / 2, 0)), kd.body)
	if kd.foil then
		P:vcyl("BottleFoil", H * 0.2, nd * 1.15, CF(base + V3(0, H * 0.88, 0)), kd.cap)
	else
		P:vcyl("BottleCap", H * 0.08, nd * 1.25, CF(base + V3(0, H * 0.95, 0)), kd.cap)
	end
	local off = (if kd.sq then sqw * 0.5 else bw * 0.5) + 0.006
	P:box("BottleLabel", V3(bw * 0.7, bh * 0.46, 0.012), faceCF(base + V3(0, bh * 0.48, 0) + dir * off, dir), kd.label)
end

-- LED 얼음 바스켓 + 병 (카운터 위): pcf = 바닥 가운데
local function iceBucket(P: any, pcf: CFrame, kd: any, glow: Color3)
	P:vcyl("IceBucketBody", 0.75, 0.82, pcf * CF(0, 0.375, 0), lk(glow, M.Neon, { t = 0.35 }))
	P:vcyl("IceBucketRim", 0.06, 0.9, pcf * CF(0, 0.75, 0), CHROME)
	P:vcyl("IceBucketIce", 0.06, 0.74, pcf * CF(0, 0.66, 0), lk(rgb(225, 240, 250), M.Ice, { t = 0.2 }))
	local p = (pcf * CF(0.08, 0.2, 0) * ANG(0, 0, -0.25)).Position
	bottle(P, p, 1.25, 0.32, kd, (pcf.LookVector * -1), true)
end

-- 플루트 잔 (스템 + 볼)
local function flute(P: any, pcf: CFrame)
	P:disc("FluteFoot", 0.16, 0.015, pcf * CF(0, 0.008, 0), gl(rgb(235, 245, 250), 0.45))
	P:vcyl("FluteStem", 0.22, 0.025, pcf * CF(0, 0.12, 0), gl(rgb(235, 245, 250), 0.45))
	P:vcyl("FluteBowl", 0.32, 0.11, pcf * CF(0, 0.39, 0), gl(rgb(240, 225, 170), 0.45))
end

-- 헤드폰 (훅에 걸림): p = 훅 점, dir = 바깥쪽
local function headphones(P: any, p: Vector3, dir: Vector3)
	local f = faceCF(p, dir)
	P:box("HeadphoneHook", V3(0.06, 0.06, 0.22), f * CF(0, 0, 0.11), CHROME)
	P:ring("HeadphoneBand", f * CF(0, -0.32, 0.22), 0.3, 0.07, 5, lk(rgb(24, 24, 26), M.Plastic), 0.15, PI - 0.15)
	for _, s in { -1, 1 } do
		P:cyl("HeadphoneCup", 0.14, 0.32, f * CF(s * 0.3, -0.4, 0.22), lk(rgb(30, 30, 32), M.Plastic))
		P:cyl("HeadphonePad", 0.04, 0.28, f * CF(s * 0.22, -0.4, 0.22), lk(rgb(60, 20, 20), M.Leather))
	end
end

-- 로드 케이스 (플라이트 케이스): pcf = 바닥 가운데, size, label
local function roadCase(P: any, pcf: CFrame, size: Vector3, label: string?)
	local s = size
	P:box("RoadCase", s, pcf * CF(0, s.Y / 2, 0), lk(rgb(28, 28, 30), M.Plastic))
	local AL = lk(rgb(190, 192, 196), M.Metal)
	for _, y in { 0.04, s.Y - 0.04 } do
		P:box("CaseEdge", V3(s.X + 0.02, 0.08, 0.06), pcf * CF(0, y, s.Z / 2), AL)
		P:box("CaseEdge", V3(s.X + 0.02, 0.08, 0.06), pcf * CF(0, y, -s.Z / 2), AL)
	end
	for _, sx in { -1, 1 } do
		P:box("CaseLatch", V3(0.16, 0.12, 0.04), pcf * CF(sx * s.X * 0.32, s.Y * 0.7, s.Z / 2 + 0.02), CHROME)
		P:ball("CaseCorner", 0.14, pcf * CF(sx * s.X / 2, s.Y, s.Z / 2), AL)
	end
	if label then
		txt(P, "CaseStencil", s.X * 0.7, s.Y * 0.3, pcf * CF(0, s.Y * 0.38, s.Z / 2 + 0.01), label, rgb(235, 235, 235), nil, F.Arcade)
	end
end

-- 메인홀 문맥: 벽은 쓰지 않음 (벽 소품은 맵 파트 기준으로 붙임)
local function mainBar(R: any)
	local P, K = R.P, R.K
	local bl = R.one("GantryBacklight")
	local bx = if bl then bl.c.X else -3.95
	-- 1) 백바 병 75 (원래 무지 유리 원통) -> 라벨 병 (층마다 종류)
	local tiers = {
		{ "champ", "rose", "liqueur", "champ", "black" },
		{ "vodka", "gin", "tequila", "vodka", "gin" },
		{ "whisky", "rum", "whisky", "liqueur", "whisky" },
	}
	local bottles = R.find("Bottle", "BarDetail")
	for i, b in bottles do
		R.hide(b.part)
		local D = math.min(b.s.X, b.s.Z)
		local H = b.s.Y
		local dir = if b.c.X >= bx then V3(1, 0, 0) else V3(-1, 0, 0)
		local tier = if b.mn.Y < 5.4 then 1 elseif b.mn.Y < 7.4 then 2 else 3
		local list = tiers[tier]
		local kd = BOTTLE_KINDS[list[(i % #list) + 1]]
		-- 숨긴 원래 병과 같은 자리 (바텐더 keep 안이어도 그대로)
		P:free(function()
			bottle(P, V3(b.c.X, b.mn.Y, b.c.Z), H, D, kd, dir, not hi(K))
		end)
	end
	-- 2) 유리 선반 앞 모서리 LED (양쪽) + 백바 불빛
	P:free(function()
		for _, sh in R.find("GlassShelf", "MainBar") do
			for _, sx in { -1, 1 } do
				P:box("ShelfEdgeLED", V3(0.04, 0.04, sh.s.Z - 0.1), CF(sh.c.X + sx * (sh.s.X / 2 - 0.02), sh.mn.Y - 0.03, sh.c.Z), nl(rgb(255, 214, 160)))
			end
		end
		local gb = R.one("GantryBase")
		if gb then
			for _, sx in { -1, 1 } do
				P:box("ShelfEdgeLED", V3(0.04, 0.04, gb.s.Z - 0.2), CF(gb.c.X + sx * (gb.s.X / 2 + 0.01), gb.mx.Y - 0.05, gb.c.Z), nl(rgb(255, 214, 160)))
			end
		end
	end)
	local gc = R.one("GantryCanopy")
	if gc then
		local lamp = P:box("GantryLamp", V3(0.3, 0.05, gc.s.Z - 1.0), CF(gc.c.X, gc.mn.Y - 0.03, gc.c.Z), nl(rgb(255, 222, 180)))
		K:light(lamp, "PointLight", { Range = 11, Brightness = 1.1, Color = rgb(255, 214, 170) })
	end
	-- 3) 스피드레일 병 → 푸어 스파우트
	for _, b in R.find("SpeedRailBottle") do
		local top = V3(b.c.X, b.mx.Y, b.c.Z)
		P:free(function()
			P:vcyl("PourCollar", 0.08, 0.13, CF(top + V3(0, 0.04, 0)), lk(rgb(20, 20, 22), M.Rubber))
			P:seg("PourSpout", top + V3(0, 0.07, 0), top + V3(0, 0.27, 0.1), 0.035, CHROME)
		end)
	end
	-- 4) 아이스웰 스쿱 · 바 도구 (드립 트레이 위)
	P:free(function()
		for i, w in R.find("IceWell") do
			local p = V3(w.c.X, w.mx.Y + 0.08, w.c.Z + (if i % 2 == 0 then 1.2 else -1.2))
			P:cyl("IceScoop", 0.42, 0.24, CF(p) * ANG(0, PI / 2, 0) * ANG(0, 0, 0.35), CHROME)
			P:seg("IceScoopHandle", p + V3(0, 0.05, 0.21), p + V3(0, 0.12, 0.55), 0.06, lk(rgb(20, 20, 22), M.Plastic))
		end
		for _, d in R.find("DripTray") do
			local y = d.mx.Y + 0.01
			local x = d.c.X
			-- 지거 (이중) · 바 스푼 · 스트레이너 · 머들러
			P:vcyl("Jigger", 0.14, 0.12, CF(x, y + 0.07, d.mn.Z + 0.4), CHROME)
			P:vcyl("Jigger", 0.12, 0.1, CF(x, y + 0.2, d.mn.Z + 0.4), CHROME)
			P:seg("BarSpoon", V3(x - 0.15, y + 0.02, d.mn.Z + 0.75), V3(x + 0.1, y + 0.02, d.mn.Z + 1.85), 0.03, CHROME)
			P:disc("Strainer", 0.26, 0.02, CF(x + 0.2, y + 0.01, d.mx.Z - 0.6), CHROME)
			P:seg("StrainerHandle", V3(x + 0.2, y + 0.01, d.mx.Z - 0.6), V3(x + 0.2, y + 0.01, d.mx.Z - 0.22), 0.04, CHROME)
			P:seg("Muddler", V3(x - 0.2, y + 0.03, d.mx.Z - 0.9), V3(x - 0.2, y + 0.03, d.mx.Z - 0.25), 0.07, Look.walnut)
		end
	end)
	-- 4b) 언더바 위 글라스 랙 (아이스웰 두 칸 사이, 스피드레일 병 뒤): 회색 식기세척 랙 + 엎어 둔 잔 3 x 4
	P:free(function()
		for _, u in R.find("UnderBarStation") do
			local wells = {}
			for _, w in R.find("IceWell") do
				if math.abs(w.c.X - u.c.X) < 0.8 then
					table.insert(wells, w)
				end
			end
			if #wells >= 2 then
				table.sort(wells, function(a, b)
					return a.c.Z < b.c.Z
				end)
				local z0, z1 = wells[1].mx.Z + 0.1, wells[2].mn.Z - 0.1
				-- 스피드레일 = 바텐더 통로 쪽 (게이트리 쪽). 랙은 그 반대 (손님 쪽) 으로 붙임
				local away = if u.c.X < bx then -1 else 1
				local rw, rd = 1.15, math.min(1.9, z1 - z0)
				local rx = u.c.X + away * 0.12
				local rzc = (z0 + z1) / 2
				-- 바텐더 NPC 팔이 언더바 위로 나와 있는 칸은 비움 (NPC 는 애니메이션)
				local LIMBS = { ["Right Arm"] = true, ["Left Arm"] = true, Torso = true, Head = true, RightHand = true, LeftHand = true, RightLowerArm = true, LeftLowerArm = true }
				if R.blocked(V3(rx - rw / 2 - 0.25, u.mx.Y - 0.2, rzc - rd / 2 - 0.25), V3(rx + rw / 2 + 0.25, u.mx.Y + 1.4, rzc + rd / 2 + 0.25), nil, LIMBS) then
					rd = 0
				end
				if rd > 1.2 then
					-- 바 상판 안쪽 끝 (상판 아래로 들어가지 않게) 과 스피드레일 병 사이
					local rz = (z0 + z1) / 2
					local y = u.mx.Y
					local RACK = lk(rgb(58, 60, 64), M.Plastic)
					P:box("GlassRackBase", V3(rw, 0.04, rd), CF(rx, y + 0.02, rz), RACK)
					for _, sz in { -1, 1 } do
						P:box("GlassRackWall", V3(rw, 0.3, 0.04), CF(rx, y + 0.15, rz + sz * (rd / 2 - 0.02)), RACK)
						P:box("GlassRackWall", V3(0.04, 0.3, rd), CF(rx + sz * (rw / 2 - 0.02), y + 0.15, rz), RACK)
					end
					P:box("GlassRackBar", V3(0.03, 0.22, rd - 0.08), CF(rx, y + 0.11, rz), RACK)
					for k = 1, 3 do
						P:box("GlassRackBar", V3(rw - 0.08, 0.22, 0.03), CF(rx, y + 0.11, rz - rd / 2 + rd * k / 4), RACK)
					end
					if hi(K) then
						for a = 0, 1 do
							for b = 0, 3 do
								local gx = rx - rw / 4 + a * rw / 2
								local gz = rz - rd / 2 + rd * (b + 0.5) / 4
								if (a + b) % 3 ~= 2 then
									-- 엎어 둔 록 글라스 (두꺼운 바닥이 위)
									P:vcyl("RackGlass", 0.3, 0.3, CF(gx, y + 0.19, gz), gl(rgb(225, 238, 245), 0.55))
									P:disc("RackGlassBase", 0.3, 0.04, CF(gx, y + 0.35, gz), gl(rgb(210, 228, 238), 0.35))
								end
							end
						end
					end
				end
			end
		end
	end)
	-- 5) 바 상판: 서비스 고무 매트 (바텐더 쪽 가장자리) · 테이블 메뉴 스탠드 · POS 하나 더
	local tops = R.find("BarTop", nil)
	local mc = V3(0, 0, 0)
	for _, t in tops do
		mc += t.c
	end
	if #tops > 0 then
		mc /= #tops
	end
	local stands: { BasePart } = {}
	for _, t in tops do
		local long = t.s.Z > t.s.X
		local inward = if long then V3(math.sign(mc.X - t.c.X), 0, 0) else V3(0, 0, math.sign(mc.Z - t.c.Z))
		local y = t.mx.Y
		-- 고무 매트 (안쪽 가장자리)
		local mp = t.c + inward * ((if long then t.s.X else t.s.Z) / 2 - 0.55)
		P:free(function()
			if long then
				P:box("BarServiceMat", V3(0.8, 0.03, 3.2), CF(mp.X, y + 0.015, mp.Z), lk(rgb(16, 16, 18), M.Rubber))
			else
				P:box("BarServiceMat", V3(3.2, 0.03, 0.8), CF(mp.X, y + 0.015, mp.Z), lk(rgb(16, 16, 18), M.Rubber))
			end
			-- 메뉴 스탠드 (손님 쪽을 봄, 바깥 가장자리 · 모서리 가까이)
			local outward = -inward
			local along = if long then V3(0, 0, 1) else V3(1, 0, 0)
			local sp = t.c + outward * ((if long then t.s.X else t.s.Z) / 2 - 0.5) + along * ((if long then t.s.Z else t.s.X) / 2 - 1.6) * (if long then -1 else 1)
			local f = faceCF(V3(sp.X, y, sp.Z), outward)
			P:box("MenuStandBase", V3(0.7, 0.04, 0.3), f * CF(0, 0.02, 0), gl(rgb(235, 240, 245), 0.4))
			local face = f * CF(0, 0.52, -0.04) * ANG(-0.16, 0, 0)
			local pl = P:box("MenuStandFace", V3(0.72, 0.96, 0.03), face, gl(rgb(235, 240, 245), 0.5))
			txt(P, "MenuStandText", 0.66, 0.9, face * CF(0, 0, 0.016), "SIGNATURE\n오션 블루 에이드 9,000\n자몽 스파클링 9,000\n패션후르츠 목테일 10,000\n\n보틀 주문은 테이블에서", rgb(240, 240, 240), rgb(14, 22, 36), F.GothamMedium, 1.1)
			table.insert(stands, pl)
		end)
	end
	-- POS 하나 더 (원래 POS 반대쪽 모서리)
	local pos = R.one("POSScreen")
	if pos and #tops > 0 then
		local px = mc.X - (pos.c.X - mc.X)
		local pz = mc.Z - (pos.c.Z - mc.Z)
		local dir = V3(math.sign(mc.X - px), 0, 0)
		P:free(function()
			P:vcyl("POSPole", 0.5, 0.1, CF(px, pos.mn.Y - 0.25, pz), BMETAL)
			local f = faceCF(V3(px, pos.c.Y, pz), dir) * ANG(-0.2, 0, 0)
			P:box("POSScreen2Body", V3(1.4, 1.0, 0.08), f, lk(rgb(18, 18, 20)))
			local _, lbl = txt(P, "POSScreen2", 1.3, 0.9, f * CF(0, 0, 0.042), "ORDER #214\n에이드 x2 · 목테일 x1\n₩28,000", rgb(230, 245, 255), rgb(20, 40, 70), F.GothamBold, 1.2)
			loopText(K, lbl, { "ORDER #214\n에이드 x2 · 목테일 x1\n₩28,000", "ORDER #215\n스파클링 x3\n₩27,000", "TABLE B4\n보틀 서비스 준비\n퍼레이드 대기" }, 5)
			-- 손님용 카드 단말기 (POS 옆, 바깥 쪽)
			P:box("CardTerminalBar", V3(0.36, 0.14, 0.6), CF(px - dir.X * 0.9, (tops[1].mx.Y) + 0.07, pz) * ANG(-0.2, 0, 0), lk(rgb(24, 24, 26)))
			P:box("CardTerminalScreen", V3(0.28, 0.01, 0.24), CF(px - dir.X * 0.9, (tops[1].mx.Y) + 0.145, pz - 0.12), nl(rgb(60, 140, 255)))
		end)
	end
	-- 6) 백바 양 끝 음료 메뉴판 (게이트리 캐노피 아래, 짧은 변 손님 쪽을 봄)
	local menuPages = {
		{ "SIGNATURE · 시그니처", { { "오션 블루 에이드", "9,000" }, { "광안 선셋 에이드", "9,000" }, { "자몽 스파클링", "9,000" }, { "패션후르츠 목테일", "10,000" }, { "모히또 목테일", "10,000" }, { "에너지 드링크", "7,000" } } },
		{ "SPARKLING · 스파클링", { { "샴페인 1병", "150,000" }, { "VIP 보틀 퍼레이드", "300,000" }, { "생일 축하 보틀", "250,000" }, { "스파클링 주스 1병", "60,000" }, { "탄산수 · 토닉", "4,000" }, { "생수", "3,000" } } },
		{ "MOCKTAIL · 목테일", { { "버진 모히또", "10,000" }, { "피치 아이스티", "8,000" }, { "블루 레모네이드", "9,000" }, { "망고 스무디", "10,000" }, { "콜라 · 사이다", "4,000" }, { "웰컴 음료 (입장)", "FREE" } } },
	}
	local menuLabels: { TextLabel } = {}
	if gc then
		for k, z in { gc.mn.Z - 0.03, gc.mx.Z + 0.03 } do
			local dir = if k == 1 then V3(0, 0, -1) else V3(0, 0, 1)
			local f = faceCF(V3(gc.c.X, gc.mn.Y - 1.45, z), dir)
			local pg = menuPages[k]
			P:free(function()
				P:plate("BarMenuFrame", 3.3, 2.7, 0.08, f, BRASS)
				P:plate("BarMenuFace", 3.16, 2.56, 0.1, f, lk(rgb(10, 12, 18)))
				local _, tl = txt(P, "BarMenuTitle", 3.0, 0.42, f * CF(0, 1.02, 0.105), pg[1], CY, nil, F.GothamBlack, 1.4)
				table.insert(menuLabels, tl)
				local lines = {}
				for _, it in pg[2] do
					table.insert(lines, it[1] .. "  ·  " .. it[2])
				end
				local _, bl2 = txt(P, "BarMenuBody", 2.9, 1.9, f * CF(0, -0.22, 0.105), table.concat(lines, "\n"), rgb(240, 236, 228), nil, F.GothamMedium, 1.2)
				table.insert(menuLabels, bl2)
				P:seg("BarMenuRod", V3(gc.c.X - 1.3, gc.mn.Y, z), V3(gc.c.X - 1.3, gc.mn.Y - 0.12, z), 0.04, BRASS)
				P:seg("BarMenuRod", V3(gc.c.X + 1.3, gc.mn.Y, z), V3(gc.c.X + 1.3, gc.mn.Y - 0.12, z), 0.04, BRASS)
			end)
		end
	end
	-- 상호작용: 메뉴 넘기기 (모서리 메뉴 스탠드 중 서버 프롬프트 자리에서 먼 것)
	local function pageText(i: number): (string, string)
		local pg = menuPages[i]
		local lines = {}
		for _, it in pg[2] do
			table.insert(lines, it[1] .. "  ·  " .. it[2])
		end
		return pg[1], table.concat(lines, "\n")
	end
	for _, st in stands do
		local lp = K.V.cf:PointToObjectSpace(st.Position)
		if Interact.canPrompt(K, lp) then
			Interact.cycle(K, st, { 1, 2, 3 }, {
				action = "메뉴 넘기기",
				object = "음료 메뉴",
				start = 1,
				on = function(_i, page)
					-- 백바 메뉴판 두 개를 같은 페이지로 (+ 다음 페이지)
					local t1, b1 = pageText(page)
					local t2, b2 = pageText(page % 3 + 1)
					local vals = { t1, b1, t2, b2 }
					for j, l in menuLabels do
						if l.Parent and vals[j] then
							l.Text = vals[j]
						end
					end
				end,
			})
			break
		end
	end
end

-- 서비스 스테이션 (보틀 서비스 백바) 병 63 → 라벨 병 (가벼운 버전)
local function mainServiceStation(R: any)
	local P = R.P
	local list = { "champ", "vodka", "champ", "whisky", "rose", "black", "gin", "champ" }
	for i, b in R.find("Bottle", "ServiceStation") do
		R.hide(b.part)
		local kd = BOTTLE_KINDS[list[(i % #list) + 1]]
		P:free(function()
			bottle(P, V3(b.c.X, b.mn.Y, b.c.Z), b.s.Y, math.min(b.s.X, b.s.Z), kd, V3(-1, 0, 0), true)
		end)
	end
end

-- DJ 부스 주변: 케이블 · 스테이지 박스 · 헤드폰 · 로드 케이스 · 수건 · 물 · DJ ONLY
local function mainDJ(R: any)
	local P = R.P
	local deck = R.one("BoothDeck")
	local desk = R.one("DJDesk")
	if not (deck and desk) then
		return
	end
	local dy = deck.mx.Y
	-- NPC 자리 (DJ · MC) 피하기
	local npcs = {}
	for _, h in R.find("HumanoidRootPart") do
		local n = h.part.Parent and h.part.Parent.Name or ""
		if string.sub(n, 1, 3) == "DJ_" or string.sub(n, 1, 3) == "MC_" then
			table.insert(npcs, h)
		end
	end
	local function clearOfNPC(x0: number, x1: number): boolean
		for _, h in npcs do
			if h.mx.X + 0.3 > x0 and h.mn.X - 0.3 < x1 then
				return false
			end
		end
		return true
	end
	local zb = desk.mn.Z -- 책상 뒤 (DJ 쪽)
	P:free(function()
		-- 케이블 (책상 뒷면 → 바닥 → 스테이지 박스)
		local sbx = desk.mn.X - 0.6
		local sbz = deck.mn.Z + 0.55
		P:box("StageBox", V3(0.8, 0.45, 0.6), CF(sbx, dy + 0.225, sbz), lk(rgb(60, 62, 66), M.Metal))
		P:plate("StageBoxJacks", 0.7, 0.3, 0.02, faceCF(V3(sbx, dy + 0.24, sbz + 0.3), V3(0, 0, 1)), lk(rgb(20, 20, 22)))
		local cx = { -6.1, -4.8, -3.2, -1.6, -0.4, 1.1 }
		for i, x0 in cx do
			local x = math.clamp(x0, desk.mn.X + 0.3, desk.mx.X - 0.3)
			local a = V3(x, desk.mx.Y - 0.25, zb - 0.04)
			local b = V3(x, dy + 0.04, zb - 0.06 - i * 0.05)
			local c = V3(sbx + 0.2, dy + 0.04, sbz + 0.2 + i * 0.03)
			local col = if i % 2 == 0 then lk(rgb(20, 20, 22), M.Rubber) else lk(rgb(36, 36, 40), M.Rubber)
			P:seg("DJCable", a, b, 0.05, col)
			P:seg("DJCable", b, c, 0.05, col)
		end
		-- 모니터 스피커 케이블
		for _, m in R.find("MonitorStand") do
			P:seg("MonitorCable", V3(m.c.X, dy + 0.04, m.c.Z), V3(sbx, dy + 0.04, sbz), 0.05, lk(rgb(20, 20, 22), M.Rubber))
		end
		-- 헤드폰 (책상 왼쪽 옆면 훅)
		headphones(P, V3(desk.mn.X - 0.02, desk.mx.Y - 0.35, desk.c.Z), V3(-1, 0, 0))
		-- 로드 케이스 (데크 양 끝, 뒤 난간 쪽)
		local L = { x0 = deck.mn.X + 0.35, x1 = deck.mn.X + 2.15 }
		if clearOfNPC(L.x0, L.x1) and R.blocked(V3(L.x0 - 0.05, dy + 0.05, deck.mn.Z + 0.55), V3(L.x1 + 0.05, dy + 1.95, deck.mn.Z + 1.5), { BoothDeck = true, BoothPlatform = true, BoothEdgeTrim = true, BoothLED = true, BoothGlassRail = true, RailCap = true, RailLED = true }) == nil then
			roadCase(P, faceCF(V3((L.x0 + L.x1) / 2, dy, deck.mn.Z + 0.95), V3(0, 0, 1)), V3(1.8, 1.3, 1.1), "OCEAN SOUND")
			roadCase(P, faceCF(V3((L.x0 + L.x1) / 2, dy + 1.3, deck.mn.Z + 0.95), V3(0, 0, 1)), V3(1.6, 0.6, 1.0), "FX · RACK 2")
		end
		local Rr = { x0 = deck.mx.X - 2.15, x1 = deck.mx.X - 0.35 }
		-- 데크 위 맵 장비 (헤이저 등) 와 겹치면 안쪽으로 옮김, 그래도 겹치면 생략
		local deckIgnore = { BoothDeck = true, BoothPlatform = true, BoothEdgeTrim = true, BoothLED = true, BoothGlassRail = true, RailCap = true, RailLED = true }
		local function caseFree(x0: number, x1: number): boolean
			return R.blocked(V3(x0 - 0.05, dy + 0.05, deck.mn.Z + 0.55), V3(x1 + 0.05, dy + 1.9, deck.mn.Z + 2.3), deckIgnore) == nil
		end
		if not caseFree(Rr.x0, Rr.x1) then
			for _, h in R.find("Hazer") do
				if h.mx.Y > dy and h.mn.Y < dy + 2 and h.mn.X - 2.1 > desk.mx.X + 0.2 then
					Rr = { x0 = h.mn.X - 2.1, x1 = h.mn.X - 0.3 }
				end
			end
		end
		if clearOfNPC(Rr.x0, Rr.x1) and caseFree(Rr.x0, Rr.x1) then
			local rx = (Rr.x0 + Rr.x1) / 2
			roadCase(P, faceCF(V3(rx, dy, deck.mn.Z + 0.95), V3(0, 0, 1)), V3(1.8, 1.3, 1.1), "CLUB OCEAN · DJ")
			-- 수건 · 생수 · 레코드 가방
			P:box("DJTowel", V3(0.9, 0.06, 0.7), CF(rx - 0.3, dy + 1.33, deck.mn.Z + 0.95) * ANG(0, 0.2, 0), lk(rgb(240, 240, 236), M.Fabric))
			P:box("DJTowelDrape", V3(0.9, 0.5, 0.05), CF(rx - 0.3, dy + 1.1, deck.mn.Z + 1.52) * ANG(0, 0.2, 0), lk(rgb(240, 240, 236), M.Fabric))
			P:vcyl("DJWater", 0.5, 0.18, CF(rx + 0.45, dy + 1.55, deck.mn.Z + 0.8), gl(rgb(200, 230, 255), 0.4))
			P:vcyl("DJWaterCap", 0.06, 0.12, CF(rx + 0.45, dy + 1.83, deck.mn.Z + 0.8), lk(rgb(40, 120, 220)))
			P:box("RecordBag", V3(1.2, 0.9, 0.5), CF(rx, dy + 0.45, deck.mn.Z + 2.0), lk(rgb(30, 30, 34), M.Fabric))
			P:box("RecordBagFlap", V3(1.22, 0.4, 0.06), CF(rx, dy + 0.72, deck.mn.Z + 2.26), lk(rgb(40, 40, 46), M.Fabric))
		end
		-- 부스 계단 위 'DJ ONLY' 판 (뒤 난간 끝)
		local steps = R.find("BoothStep")
		if #steps > 0 then
			local sx0 = math.huge
			for _, s in steps do
				sx0 = math.min(sx0, s.mn.X)
			end
			local px, pz = sx0 - 0.15, deck.mn.Z - 0.03
			local best: any = nil
			for _, r in R.find("BoothGlassRail") do
				if r.s.X > 3 and r.mx.X <= sx0 + 0.2 and (best == nil or r.mx.X > best.mx.X) then
					best = r
				end
			end
			if best then
				px, pz = best.mx.X - 0.75, best.mn.Z - 0.005
			end
			local f = faceCF(V3(px, dy + 1.6, pz), V3(0, 0, -1))
			P:plate("DJOnlyPlate", 1.1, 0.5, 0.04, f, BMETAL)
			txt(P, "DJOnlyText", 1.0, 0.42, f * CF(0, 0, 0.042), "DJ · STAFF ONLY", rgb(255, 210, 60), nil, F.GothamBlack, 1.2)
		end
	end)
end

-- VIP 단상: 계단 브라스 노싱 + 챌면 LED · 스탠션 위 RESERVED 판 · 단상 명판
local function mainVIP(R: any)
	local P = R.P
	P:free(function()
		for _, s in R.find("VIPStep") do
			-- 단상 쪽 반대 (홀 쪽, +Z) 가 앞
			local fz = s.mx.Z
			local w = s.s.X
			P:box("VIPStepNosing", V3(w, 0.05, 0.12), CF(s.c.X, s.mx.Y - 0.02, fz - 0.06), BRASS)
			local n = math.max(2, math.floor(w / 1.4))
			for i = 1, n do
				local x = s.mn.X + w * (i - 0.5) / n
				P:box("VIPRiserLED", V3(0.3, 0.1, 0.03), CF(x, s.mn.Y + s.s.Y * 0.45, fz + 0.01), nl(rgb(255, 214, 140)))
			end
		end
		local posts = R.find("StanchionFinial", "VIPPlatform")
		table.sort(posts, function(a, b)
			return a.c.X < b.c.X
		end)
		for i, p in posts do
			if i == 1 or i == #posts or i % 3 == 0 then
				local top = V3(p.c.X, p.mx.Y, p.c.Z)
				P:vcyl("ReservedStem", 0.3, 0.05, CF(top + V3(0, 0.15, 0)), BRASS)
				local f = faceCF(top + V3(0, 0.62, 0), V3(0, 0, 1)) * ANG(-0.12, 0, 0)
				P:box("ReservedPlate", V3(1.0, 0.6, 0.04), f, BRASS)
				txt(P, "ReservedText", 0.92, 0.52, f * CF(0, 0, 0.021), "RESERVED\nVIP 예약석", rgb(20, 18, 14), rgb(214, 184, 110), F.GothamBold)
				txt(P, "ReservedTextB", 0.92, 0.52, f * ANG(0, PI, 0) * CF(0, 0, 0.021), "RESERVED\nVIP 예약석", rgb(20, 18, 14), rgb(214, 184, 110), F.GothamBold)
			end
		end
		-- 단상 앞면 명판 (가장 넓은 PlatformBody 앞)
		local best: any = nil
		for _, b in R.find("PlatformBody") do
			if not best or b.s.X > best.s.X then
				best = b
			end
		end
		if best then
			local f = faceCF(V3(best.c.X, best.mx.Y - 0.2, best.mx.Z + 0.01), V3(0, 0, 1))
			txt(P, "VIPPlaque", 3.2, 0.3, f, "VIP  ·  G1 — G4  ·  RESERVATION ONLY", rgb(226, 196, 120), nil, F.GothamBold, 1.1)
		end
	end)
end

-- 메자닌 샴페인 바
local function mainChampagne(R: any)
	local P, K = R.P, R.K
	local top = R.one("MezzBarTop")
	local glow = R.one("BackGlow", "MezzChampagneBar")
	if not top then
		return
	end
	local list = { "champ", "champ", "rose", "black", "champ", "rose" }
	for i, b in R.find("Bottle", "MezzChampagneBar") do
		R.hide(b.part)
		P:free(function()
			bottle(P, V3(b.c.X, b.mn.Y, b.c.Z), b.s.Y, math.min(b.s.X, b.s.Z), BOTTLE_KINDS[list[(i % #list) + 1]], V3(0, 0, -1), not hi(K))
		end)
	end
	local y = top.mx.Y
	local zf = top.mn.Z -- 손님 쪽
	P:free(function()
		-- LED 얼음 바스켓 2 + 플루트 6 (트레이) + POS 태블릿 + 메뉴 스탠드
		iceBucket(P, faceCF(V3(top.mn.X + 1.6, y, top.c.Z), V3(0, 0, -1)), BOTTLE_KINDS.champ, rgb(255, 196, 90))
		iceBucket(P, faceCF(V3(top.mx.X - 1.6, y, top.c.Z), V3(0, 0, -1)), BOTTLE_KINDS.rose, rgb(255, 120, 190))
		local tx = top.c.X - 1.4
		P:slab("FluteTray", 1.3, 0.9, 0.04, 0.12, CF(tx, y + 0.02, top.c.Z - 0.2), CHROME)
		for i = 0, 5 do
			flute(P, CF(tx - 0.42 + (i % 3) * 0.42, y + 0.04, top.c.Z - 0.42 + (i // 3) * 0.42))
		end
		local f = faceCF(V3(top.c.X + 1.6, y, top.mx.Z - 0.5), V3(0, 0, 1)) * ANG(-0.5, 0, 0)
		P:box("ChampPOS", V3(0.9, 0.62, 0.05), f * CF(0, 0.32, 0), lk(rgb(20, 20, 22)))
		txt(P, "ChampPOSScreen", 0.82, 0.54, f * CF(0, 0.32, 0.026), "M2 · 샴페인 x2\nVIP 퍼레이드 준비", rgb(230, 240, 255), rgb(30, 24, 50), F.GothamBold, 1.1)
		acrylicStand(P, faceCF(V3(top.c.X + 0.2, y, zf + 0.35), V3(0, 0, -1)), 1.0, 0.7, "CHAMPAGNE\n1병 150,000\n퍼레이드 300,000", rgb(255, 230, 170), rgb(20, 16, 10))
		-- 손님 쪽 발 받침 브라스 레일
		local cnt = R.one("MezzBarCounter")
		if cnt then
			local rz = cnt.mn.Z - 0.35
			P:seg("ChampFootRail", V3(cnt.mn.X + 0.4, 12.5 + 0.7, rz), V3(cnt.mx.X - 0.4, 12.5 + 0.7, rz), 0.14, BRASS)
			for _, x in { cnt.mn.X + 0.8, cnt.c.X, cnt.mx.X - 0.8 } do
				P:seg("ChampRailBracket", V3(x, 12.5 + 0.7, rz), V3(x, 12.5 + 0.9, cnt.mn.Z), 0.07, BRASS)
			end
		end
		-- 네온 'CHAMPAGNE' (선반 위 백글로 앞)
		if glow then
			local f2 = faceCF(V3(glow.c.X, glow.mx.Y - 0.75, glow.mn.Z - 0.02), V3(0, 0, -1))
			P:plate("ChampSignBack", 6.4, 1.1, 0.06, f2, lk(rgb(12, 10, 8)))
			txt(P, "ChampSign", 6.0, 0.95, f2 * CF(0, 0, 0.065), "CHAMPAGNE · 샴페인 바", rgb(255, 222, 150), nil, F.GothamBlack, 1.8)
		end
	end)
	local lamp = P:box("ChampLamp", V3(4, 0.05, 0.3), CF(top.c.X, top.mx.Y + 4.6, top.c.Z), nl(rgb(255, 220, 170)))
	if lamp then
		P:free(function()
			P:seg("ChampLampRod", V3(top.c.X - 1.8, top.mx.Y + 4.62, top.c.Z), V3(top.c.X - 1.8, 25.4, top.c.Z), 0.04, BMETAL)
			P:seg("ChampLampRod", V3(top.c.X + 1.8, top.mx.Y + 4.62, top.c.Z), V3(top.c.X + 1.8, 25.4, top.c.Z), 0.04, BMETAL)
			P:box("ChampLampBody", V3(4.1, 0.16, 0.36), CF(top.c.X, top.mx.Y + 4.7, top.c.Z), BRASS)
		end)
		K:light(lamp, "SpotLight", { Face = Enum.NormalId.Bottom, Angle = 90, Range = 10, Brightness = 1.4, Color = rgb(255, 214, 170) })
	end
end

-- 흡연실: 환풍기 팬 (켜기/끄기) · 공기청정기 · 꽁초 · 안내 · 불빛
local function mainSmoking(R: any)
	local P, K = R.P, R.K
	local fl = R.one("SmokeFloor")
	local hood = R.one("ExtractorHood")
	if not (fl and hood) then
		return
	end
	local fy = fl.mx.Y
	-- 안쪽 벽 (메자닌 끝 칸막이 = Partition_Front 앞면): 흡연실 바닥은 벽 밑까지 깔려 있어서 바닥 끝이 아님
	local farZ = fl.mx.Z
	for _, w in R.find("Partition_Front") do
		if w.mn.X < fl.mx.X and w.mx.X > fl.mn.X and w.mn.Z < farZ then
			farZ = w.mn.Z
		end
	end
	local blades: { BasePart } = {}
	local hub: BasePart? = nil
	P:free(function()
		-- 후드 아래 팬 그릴 + 날개 + 덕트
		local hy = hood.mn.Y
		P:disc("ExtractorRing", 2.3, 0.08, CF(hood.c.X, hy - 0.04, hood.c.Z), STEEL)
		P:disc("ExtractorBack", 2.1, 0.03, CF(hood.c.X, hy - 0.02, hood.c.Z), lk(rgb(16, 16, 18)))
		for i = 0, 3 do
			local a = i * PI / 2
			table.insert(blades, P:box("ExtractorBlade", V3(0.95, 0.03, 0.32), CF(hood.c.X, hy - 0.1, hood.c.Z) * ANG(0, a, 0) * CF(0.5, 0, 0) * ANG(0.25, 0, 0), STEEL))
		end
		hub = P:disc("ExtractorHub", 0.36, 0.08, CF(hood.c.X, hy - 0.12, hood.c.Z), CHROME)
		for i = -3, 3 do
			P:box("ExtractorGrille", V3(2.1, 0.03, 0.04), CF(hood.c.X, hy - 0.16, hood.c.Z + i * 0.28), STEEL)
		end
		P:vcyl("ExtractorDuct", 25.4 - hood.mx.Y, 1.2, CF(hood.c.X, (hood.mx.Y + 25.4) / 2, hood.c.Z), lk(rgb(150, 152, 156), M.Metal))
		-- 재떨이 위 모래 + 꽁초
		for _, t in R.find("AshtrayTop") do
			P:disc("AshtraySand", t.s.X * 0.8, 0.03, CF(t.c.X, t.mx.Y + 0.01, t.c.Z), lk(rgb(200, 190, 170), M.Sand))
			for i = 1, 4 do
				local p = V3(t.c.X + (rnd(11, i) - 0.5) * t.s.X * 0.6, t.mx.Y + 0.04, t.c.Z + (rnd(13, i) - 0.5) * t.s.X * 0.6)
				P:cyl("CigButt", 0.22, 0.06, CF(p) * ANG(0, rnd(17, i) * PI, 0), lk(if i % 2 == 0 then rgb(236, 230, 220) else rgb(214, 160, 90)))
			end
		end
		-- 공기청정기 (안쪽 벽 · 유리 쪽 구석: 벽 앞면에서 띄움)
		local px, pz = fl.mx.X - 0.9, farZ - 0.55
		P:rbox("AirPurifier", V3(0.9, 3.4, 0.9), 0.2, CF(px, fy + 1.7, pz), lk(rgb(240, 240, 238), M.Plastic))
		P:disc("AirPurifierTop", 0.75, 0.04, CF(px, fy + 3.42, pz), lk(rgb(60, 62, 66)))
		P:box("AirPurifierLED", V3(0.3, 0.06, 0.02), faceCF(V3(px, fy + 2.9, pz - 0.46), V3(0, 0, -1)), nl(rgb(60, 160, 255)))
		txt(P, "AirPurifierLabel", 0.7, 0.2, faceCF(V3(px, fy + 2.6, pz - 0.461), V3(0, 0, -1)), "공기청정 · 강", rgb(40, 40, 44), nil, F.GothamBold)
	end)
	-- 안내판: 안쪽 (뒤 벽 = +Z 칸막이 쪽 유리 위가 아니라 벤치 위 벽)
	local bench = R.one("SmokeBench")
	P:free(function()
		-- 안쪽 벽 (+Z, 보는 쪽 = -Z): 세로 줄눈 불연 패널 · 안내 라이트박스 · 전기 라이터 · 꽁초 수거함 · 하부 배기 그릴
		local wx0, wx1 = fl.mn.X + 1.2, fl.mx.X - 0.45
		local cx = (wx0 + wx1) / 2
		local function farF(x: number, y: number): CFrame
			return faceCF(V3(x, y, farZ - 0.01), V3(0, 0, -1))
		end
		P:plate("SmokeWallPanel", wx1 - wx0, 7.6, 0.03, farF(cx, fy + 3.95), lk(rgb(46, 48, 52), M.Concrete))
		local x = wx0 + 1.2
		while x < wx1 - 0.6 do
			P:plate("SmokeWallJoint", 0.04, 7.6, 0.045, farF(x, fy + 3.95), lk(rgb(24, 24, 26)))
			x += 1.2
		end
		lightbox(P, "SmokeRule", farF(cx - 0.4, fy + 5.6) * CF(0, 0, 0.04), 3.6, 1.7, "SMOKING ROOM · 흡연실", "음료 · 잔 반입 금지 · 꽁초는 재떨이에\n문은 꼭 닫아 주세요 · 1회 10분 이내", { titleH = 0.48, accent = rgb(255, 200, 80), frame = BMETAL })
		-- 전기 라이터 (벽부형: 버튼을 누르면 코일이 달아오름)
		local lf = farF(cx + 2.1, fy + 3.7) * CF(0, 0, 0.04)
		P:plate("WallLighter", 0.62, 0.9, 0.22, lf, STEEL)
		P:plate("WallLighterSlot", 0.34, 0.2, 0.012, lf * CF(0, -0.18, 0.22), lk(rgb(16, 16, 18)))
		P:plate("WallLighterCoil", 0.22, 0.06, 0.016, lf * CF(0, -0.2, 0.222), nl(rgb(255, 110, 30)))
		P:plate("WallLighterButton", 0.2, 0.2, 0.05, lf * CF(0, 0.2, 0.22), lk(rgb(200, 30, 30), M.SmoothPlastic))
		txt(P, "WallLighterLabel", 0.56, 0.16, lf * CF(0, 0.39, 0.222), "전기 라이터", rgb(30, 30, 34), nil, F.GothamBold)
		-- 꽁초 수거함 (스테인리스, 위 투입구)
		local bf = farF(wx0 + 1.35, fy + 2.4) * CF(0, 0, 0.04)
		P:plate("ButtBin", 0.8, 1.4, 0.36, bf, STEEL)
		P:plate("ButtBinTop", 0.8, 0.06, 0.4, bf * CF(0, 0.7, 0), lk(rgb(30, 30, 32), M.Metal))
		P:plate("ButtBinSlot", 0.5, 0.08, 0.012, bf * CF(0, 0.52, 0.36), lk(rgb(10, 10, 12)))
		txt(P, "ButtBinLabel", 0.7, 0.36, bf * CF(0, 0.05, 0.362), "꽁초 수거함\n불씨 확인", rgb(255, 255, 255), rgb(170, 24, 30), F.GothamBold)
		-- 하부 배기 그릴 (바닥 쪽 공기 흡입)
		local gf = farF(cx - 0.4, fy + 0.62) * CF(0, 0, 0.04)
		P:plate("ExhaustGrille", 3.0, 0.7, 0.05, gf, STEEL)
		for k = 0, 4 do
			P:plate("ExhaustSlat", 2.8, 0.05, 0.06, gf * CF(0, -0.24 + k * 0.12, 0.0), lk(rgb(20, 20, 22)))
		end
		-- 바깥 (유리문 옆 유리 바깥면): 흡연실 외 흡연 금지
		local door = R.one("SmokeDoor")
		for _, g in R.find("SmokeGlass") do
			if g.s.X > 5 then
				-- 메자닌 통로 쪽 긴 유리 (-Z 면) 바깥, 입구 쪽 끝
				local f = faceCF(V3(g.mx.X - 1.3, fy + 4.6, g.mn.Z - 0.01), V3(0, 0, -1))
				P:plate("NoSmokeSticker", 1.6, 1.6, 0.01, f, lk(rgb(250, 250, 250)))
				P:ring("NoSmokeRing", f * CF(0, 0.15, 0.015), 0.55, 0.12, 8, lk(rgb(220, 30, 30)))
				P:plate("NoSmokeBar", 1.1, 0.12, 0.012, f * CF(0, 0.15, 0.01) * ANG(0, 0, -PI / 4), lk(rgb(220, 30, 30)))
				P:plate("NoSmokeCig", 0.7, 0.14, 0.011, f * CF(0, 0.15, 0.008), lk(rgb(60, 60, 60)))
				txt(P, "NoSmokeText", 1.5, 0.36, f * CF(0, -0.58, 0.012), "흡연실 외 흡연 금지\n(전자담배 포함)", rgb(200, 20, 20), nil, F.GothamBlack)
				break
			end
		end
		local _ = door
		-- 열감지기 (흡연실은 연기 감지기 대신)
		P:disc("HeatDetector", 0.5, 0.12, CF(fl.c.X + 2.5, R.one("SmokeCeiling") and R.one("SmokeCeiling").mn.Y - 0.06 or fy + 8, fl.c.Z - 2.5), lk(rgb(240, 240, 236)))
	end)
	-- 불빛 + 상호작용 (환풍기 스위치: 벤치 위 벽)
	local lightP = P:box("SmokeLampDiffuser", V3(3.0, 0.04, 0.4), CF(fl.c.X, (R.one("SmokeCeiling") and R.one("SmokeCeiling").mn.Y or fy + 8.2) - 0.03, fl.c.Z + 3.0), nl(rgb(236, 244, 255)))
	K:light(lightP, "PointLight", { Range = 10, Brightness = 0.8, Color = rgb(230, 240, 255) })
	local sw: BasePart? = nil
	P:free(function()
		-- 벤치 위 벽 (안내판 옆): 벤치에 앉거나 서서 닿는 높이
		local f = faceCF(V3(fl.mx.X - 2.0, fy + 3.6, farZ - 0.06), V3(0, 0, -1))
		P:plate("FanSwitchPlate", 0.5, 0.8, 0.05, f, lk(rgb(236, 236, 232)))
		sw = P:plate("FanSwitch", 0.22, 0.34, 0.08, f * CF(0, 0.08, 0), lk(rgb(220, 220, 216)))
		P:plate("FanSwitchLED", 0.08, 0.08, 0.06, f * CF(0, -0.25, 0), nl(rgb(60, 230, 120)))
		txt(P, "FanSwitchLabel", 0.5, 0.18, f * CF(0, 0.55, 0.01), "환풍기", rgb(240, 240, 240), nil, F.GothamBold, 1.1)
	end)
	local on = true
	local base = {}
	for _, b in blades do
		table.insert(base, { p = b, cf = b.CFrame })
	end
	local center = R.world(V3(hood.c.X, hood.mn.Y - 0.1, hood.c.Z))
	local ang = 0
	Interact.anim(K, function(_t, dt)
		if not on then
			return
		end
		ang += dt * 9
		local rot = CFrame.new(center) * CFrame.fromAxisAngle(R.wdir(Vector3.yAxis), ang) * CFrame.new(-center)
		for _, b in base do
			if b.p.Parent then
				b.p.CFrame = rot * b.cf
			end
		end
	end)
	if sw then
		Interact.toggle(K, sw, {
			object = "흡연실 환풍기",
			state = true,
			onText = "환풍기 끄기",
			offText = "환풍기 켜기",
			on = function(st)
				on = st
			end,
		})
	end
	local _ = hub
end

-- 직원 출입문 · 비상구: 카드 리더 · 도어 클로저 · 킥 플레이트 · 스티커 · 소화기 · 비상등
local function mainStaffDoor(R: any)
	local P = R.P
	local dw = R.one("DarkDoorway")
	local leaf = R.one("StaffDoorLeaf_Open")
	local frame = R.one("DoorFrame", "StaffDoor_관계자외출입금지")
	P:free(function()
		if dw then
			local wx = dw.mn.X -- 벽 앞면 (홀 쪽)
			-- 카드 리더 (문 +Z 쪽 옆)
			local f = faceCF(V3(wx - 0.02, 3.9, dw.mx.Z + 0.9), V3(-1, 0, 0))
			P:plate("CardReader", 0.42, 0.7, 0.08, f, lk(rgb(24, 24, 26)))
			P:plate("CardReaderPad", 0.32, 0.3, 0.09, f * CF(0, -0.08, 0), lk(rgb(40, 40, 44)))
			P:plate("CardReaderLED", 0.08, 0.05, 0.1, f * CF(0, 0.22, 0), nl(rgb(255, 60, 50)))
			-- 인터폰
			local f2 = faceCF(V3(wx - 0.02, 4.4, dw.mx.Z + 1.7), V3(-1, 0, 0))
			P:plate("Intercom", 0.5, 0.8, 0.06, f2, lk(rgb(200, 200, 204), M.Metal))
			P:plate("IntercomGrille", 0.3, 0.2, 0.07, f2 * CF(0, 0.15, 0), lk(rgb(40, 40, 44), M.DiamondPlate))
			P:plate("IntercomButton", 0.14, 0.14, 0.08, f2 * CF(0, -0.18, 0), CHROME)
			-- 바닥 노란 주의 띠 (문턱)
			P:box("StaffDoorStripe", V3(0.25, 0.015, dw.s.Z), CF(wx - 0.3, 0.008, dw.c.Z), lk(rgb(240, 200, 30)))
			txt(P, "StaffDoorFloorText", dw.s.Z * 0.9, 0.45, topCF(V3(wx - 0.75, 0.018, dw.c.Z), V3(1, 0, 0)), "STAFF ONLY", rgb(240, 200, 30), nil, F.GothamBlack)
		end
		if dw then
			local lampP = P:box("StaffDoorLamp", V3(0.5, 0.12, 0.9), CF(dw.mn.X - 0.4, 9.2, dw.c.Z), BMETAL)
			local lens = P:box("StaffDoorLampLens", V3(0.4, 0.02, 0.8), CF(dw.mn.X - 0.4, 9.13, dw.c.Z), nl(rgb(255, 236, 214)))
			R.K:light(lens, "PointLight", { Range = 10, Brightness = 1.1, Color = rgb(255, 232, 210) })
			local _ = lampP
		end
		if frame then
			-- 도어 클로저 (프레임 위)
			P:box("DoorCloser", V3(0.3, 0.3, 1.1), CF(frame.mn.X - 0.15, frame.mn.Y - 0.2, frame.mn.Z + 0.9), lk(rgb(170, 172, 176), M.Metal))
		end
		if leaf then
			-- 문짝 (+Z 면 = 문 안쪽 통로 쪽) 킥 플레이트 · 미는 판 · 스티커
			local z = leaf.mx.Z + 0.005
			local f = faceCF(V3(leaf.c.X, 0.45, z), V3(0, 0, 1))
			P:plate("KickPlate", leaf.s.X - 0.3, 0.8, 0.02, f, STEEL)
			local f2 = faceCF(V3(leaf.c.X, 0.45, leaf.mn.Z - 0.005), V3(0, 0, -1))
			P:plate("KickPlate", leaf.s.X - 0.3, 0.8, 0.02, f2, STEEL)
			P:plate("PushPlate", 0.4, 1.2, 0.02, faceCF(V3(leaf.mn.X + 0.6, 3.9, leaf.mn.Z - 0.005), V3(0, 0, -1)), STEEL)
			txt(P, "LeafSticker", 1.6, 0.9, faceCF(V3(leaf.c.X, 5.2, leaf.mn.Z - 0.01), V3(0, 0, -1)), "관계자 외\n출입금지", rgb(255, 255, 255), rgb(190, 20, 30), F.GothamBlack)
			P:box("DoorCloserArm", V3(1.4, 0.08, 0.08), CF(leaf.mn.X + 0.9, leaf.mx.Y - 0.25, leaf.c.Z), lk(rgb(170, 172, 176), M.Metal))
		end
		-- 비상구 문틀: 비상등 (2구) + 안내
		local eh = R.one("ExitDoorHead")
		if eh then
			local f = faceCF(V3(eh.mn.X - 0.02, eh.mx.Y + 0.9, eh.c.Z), V3(-1, 0, 0))
			P:plate("EmergencyLampBox", 1.4, 0.45, 0.3, f, lk(rgb(240, 240, 236), M.Plastic))
			for _, s in { -1, 1 } do
				P:box("EmergencyLampHead", V3(0.3, 0.3, 0.4), f * CF(s * 0.5, -0.05, 0.45) * ANG(0.3, s * 0.3, 0), lk(rgb(230, 230, 226), M.Plastic))
			end
			P:plate("EmergencyLampLED", 0.12, 0.06, 0.31, f * CF(0, 0.1, 0), nl(rgb(60, 230, 120)))
			txt(P, "ExitNotice", 1.6, 0.6, faceCF(V3(eh.mn.X - 0.02, 4.6, eh.mn.Z - 0.8), V3(-1, 0, 0)), "비상구\n물건 적치 금지", rgb(255, 255, 255), rgb(30, 140, 70), F.GothamBold)
		end
	end)
	-- 소화기 (직원문 +Z 옆 · 비상구 옆) : 바닥 자리 확인
	local function ext(x: number, z: number, what: string)
		if spotOK(P, CF(x, 0, z), V3(0.55, 2.4, 0.55), 0, what) then
			P:vcyl("ExtinguisherBody", 1.5, 0.42, CF(x, 0.95, z), lk(rgb(200, 24, 28)))
			P:ball("ExtinguisherTop", 0.42, CF(x, 1.7, z), lk(rgb(200, 24, 28)))
			P:box("ExtinguisherValve", V3(0.14, 0.22, 0.14), CF(x, 1.95, z), BMETAL)
			P:seg("ExtinguisherHose", V3(x, 1.95, z + 0.07), V3(x - 0.1, 1.1, z + 0.2), 0.06, BMETAL)
			P:box("ExtinguisherLabel", V3(0.02, 0.5, 0.3), CF(x - 0.21, 1.0, z), lk(WHITE))
		end
	end
	if dw then
		ext(dw.mn.X - 0.35, dw.mx.Z + 2.7, "staff extinguisher")
	end
	local eh = R.one("ExitDoorHead")
	if eh then
		ext(eh.mn.X - 0.35, eh.mn.Z - 0.6, "exit extinguisher")
	end
end

-- 물품보관소: 코트마다 옷걸이 고리 + 번호표, 카운터 위 번호표 묶음 · 호출벨
local function mainCoatCheck(R: any)
	local P, K = R.P, R.K
	local coats = R.find("Coat", "CoatCheck_물품보관")
	table.sort(coats, function(a, b)
		if math.abs(a.c.Z - b.c.Z) > 1 then
			return a.c.Z < b.c.Z
		end
		return a.c.X > b.c.X
	end)
	P:free(function()
		for i, c in coats do
			local top = V3(c.c.X, c.mx.Y, c.c.Z)
			P:seg("CoatHanger", top + V3(0, -0.02, -0.6), top + V3(0, -0.02, 0.6), 0.05, lk(rgb(30, 30, 32), M.Plastic))
			if hi(K) then
				P:box("CoatHangerHook", V3(0.04, 0.3, 0.04), CF(top + V3(0, 0.13, 0)), CHROME)
			end
			-- 번호표 (카운터 쪽 = +X 면)
			local f = faceCF(V3(c.mx.X + 0.01, c.mx.Y - 0.55, c.c.Z + 0.35), V3(1, 0, 0))
			txt(P, "CoatTag", 0.22, 0.3, f, string.format("%02d", i), rgb(20, 20, 22), rgb(240, 236, 220), F.GothamBold)
			P:seg("CoatTagString", top + V3(0.21, -0.05, 0.35), top + V3(0.21, -0.4, 0.35), 0.015, lk(rgb(240, 236, 220)))
		end
		-- 옷걸이 봉 위 천장 라인 조명 (따뜻한 LED 바: 어두운 보관소에서 옷이 보이게) + 봉 끝 브래킷
		for _, rl in R.find("HangerRail", "CoatCheck_물품보관") do
			P:box("CoatLineLightHousing", V3(rl.s.X - 0.4, 0.12, 0.42), CF(rl.c.X, 11.38, rl.c.Z), BMETAL)
			P:box("CoatLineLight", V3(rl.s.X - 0.6, 0.03, 0.26), CF(rl.c.X, 11.31, rl.c.Z), nl(rgb(255, 222, 180)))
			for _, sx in { -1, 1 } do
				P:seg("CoatRailDrop", V3(rl.c.X + sx * (rl.s.X / 2 - 0.3), rl.mx.Y, rl.c.Z), V3(rl.c.X + sx * (rl.s.X / 2 - 0.3), 11.32, rl.c.Z), 0.06, CHROME)
			end
		end
		local ct = R.one("CounterTop", "CoatCheck_물품보관")
		if ct then
			local y = ct.mx.Y
			-- 번호표 묶음 (갈고리) · 호출벨 · 결제 단말기
			P:box("TicketSpikeBase", V3(0.3, 0.04, 0.3), CF(ct.c.X - 0.2, y + 0.02, ct.mn.Z + 0.8), BMETAL)
			P:vcyl("TicketSpike", 0.5, 0.03, CF(ct.c.X - 0.2, y + 0.29, ct.mn.Z + 0.8), CHROME)
			for i = 0, 4 do
				P:box("TicketStub", V3(0.3, 0.01, 0.42), CF(ct.c.X - 0.2, y + 0.06 + i * 0.03, ct.mn.Z + 0.8) * ANG(0, i * 0.3, 0), lk(rgb(240, 200, 60)))
			end
			P:disc("DeskBellBase", 0.34, 0.04, CF(ct.c.X + 0.2, y + 0.02, ct.c.Z), lk(rgb(20, 20, 22)))
			P:ell("DeskBellDome", V3(0.3, 0.2, 0.3), CF(ct.c.X + 0.2, y + 0.06, ct.c.Z), CHROME)
			P:box("CoatCardTerminal", V3(0.36, 0.14, 0.6), CF(ct.c.X, y + 0.07, ct.mx.Z - 0.9) * ANG(0, 0, 0.2), lk(rgb(24, 24, 26)))
			acrylicStand(P, faceCF(V3(ct.mx.X - 0.3, y, ct.c.Z - 1.2), V3(1, 0, 0)), 1.0, 0.7, "COAT CHECK\n1벌 ₩3,000\n번호표 분실 주의", rgb(255, 255, 255), rgb(20, 20, 24))
			local lamp = P:disc("CoatLamp", 0.7, 0.05, CF(ct.c.X - 1.5, 11.45, ct.c.Z), nl(rgb(255, 228, 196)))
			K:light(lamp, "SpotLight", { Face = Enum.NormalId.Left, Angle = 95, Range = 12, Brightness = 1.2, Color = rgb(255, 226, 196) })
		end
	end)
end

-- 홀 화장실 (HallRooms 여 · 남): 방 상자 밖까지 이어져서 모델에서 직접 읽음
local function restroomParts(R: any, name: string): { [string]: { any } }
	local out: { [string]: { any } } = {}
	local hr = R.V.model:FindFirstChild("HallRooms", true)
	local m = hr and hr:FindFirstChild(name)
	if not m then
		return out
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local l = R.A:ToObjectSpace(R.V.cf:ToObjectSpace(d.CFrame))
			local mn, mx = Scan.laabb(l, d.Size)
			local t = out[d.Name]
			if not t then
				t = {}
				out[d.Name] = t
			end
			table.insert(t, { part = d, mn = mn, mx = mx, c = (mn + mx) / 2, s = mx - mn })
		end
	end
	return out
end

-- 종이타월 디스펜서 (벽): dcf 표면. 반환: 타월 파트 (상호작용용)
local function towelDispenser(P: any, f: CFrame): BasePart
	P:plate("TowelDispenser", 1.1, 1.4, 0.42, f, lk(rgb(236, 236, 232), M.Plastic))
	P:plate("TowelDispenserWindow", 0.5, 0.18, 0.43, f * CF(0, 0.35, 0), lk(rgb(60, 70, 80), M.Glass, { t = 0.3 }))
	txt(P, "TowelDispenserLabel", 0.8, 0.16, f * CF(0, 0.05, 0.432), "PAPER TOWEL", rgb(120, 120, 124), nil, F.GothamBold)
	return P:plate("TowelSheet", 0.7, 0.36, 0.02, f * CF(0, -0.82, 0.3), lk(rgb(250, 250, 246), M.Fabric))
end

-- 화장지 홀더 (벽): 롤 + 덮개
local function tissueHolder(P: any, f: CFrame)
	P:plate("TissueHolderBack", 0.5, 0.3, 0.04, f, CHROME)
	P:cyl("TissueRoll", 0.42, 0.36, f * CF(0, -0.12, 0.22), lk(rgb(250, 250, 248), M.Fabric))
	P:plate("TissueHolderLid", 0.5, 0.06, 0.4, f * CF(0, 0.1, 0), CHROME)
end

-- 휴지통 (바닥, 페달식): pcf
local function trashBin(P: any, pcf: CFrame, h: number, d: number)
	P:vcyl("TrashBin", h, d, pcf * CF(0, h / 2, 0), STEEL)
	P:vcyl("TrashBinLid", 0.08, d + 0.04, pcf * CF(0, h + 0.04, 0), STEEL)
	P:box("TrashPedal", V3(0.3, 0.06, 0.2), pcf * CF(0, 0.06, -d / 2 - 0.08), BMETAL)
end

local function mainRestrooms(R: any)
	local P, K = R.P, R.K
	local towels: { BasePart } = {}
	local function one(t: { [string]: { any } }, n: string): any?
		return t[n] and t[n][1]
	end
	-- 여자 화장실 ------------------------------------------------------------------------------------------
	local W = restroomParts(R, "여자화장실")
	local wv = one(W, "VanityCounter")
	if wv then
		local walls = W.Wall or {}
		local west = math.huge
		for _, w in walls do
			if w.s.X < 1 and w.c.X < wv.c.X then
				west = math.min(west, w.mx.X)
			end
		end
		if west == math.huge then
			west = wv.mn.X - 4
		end
		local back = wv.mn.Z
		P:free(function()
			-- 화장대 서쪽 끝 옆: 종이타월 (뒤 벽) + 휴지통 (바닥)
			local tx = (west + wv.mn.X) / 2
			table.insert(towels, towelDispenser(P, faceCF(V3(tx, 5.0, back + 0.0), V3(0, 0, 1))))
			trashBin(P, faceCF(V3(tx, 0, back + 0.55), V3(0, 0, 1)), 2.0, 0.8)
			txt(P, "TowelNotice", 1.6, 0.5, faceCF(V3(tx, 6.7, back + 0.01), V3(0, 0, 1)), "종이타월은 휴지통에\n한 장이면 충분해요", rgb(255, 255, 255), rgb(150, 20, 70), F.GothamBold)
			-- 화장대 위: 어메니티 트레이 (가그린 · 헤어 · 면봉)
			local ay = wv.mx.Y
			local ax = wv.mn.X + 0.9
			P:slab("AmenityTray", 0.9, 1.3, 0.05, 0.1, CF(ax, ay + 0.025, wv.c.Z - 0.3), lk(rgb(30, 30, 32)))
			P:vcyl("Mouthwash", 0.6, 0.3, CF(ax - 0.2, ay + 0.35, wv.c.Z - 0.6), lk(rgb(60, 170, 220), M.Glass, { t = 0.3 }))
			P:vcyl("MouthwashCap", 0.1, 0.18, CF(ax - 0.2, ay + 0.7, wv.c.Z - 0.6), lk(WHITE))
			P:vcyl("CupStack", 0.4, 0.2, CF(ax + 0.2, ay + 0.25, wv.c.Z - 0.6), lk(rgb(250, 250, 250)))
			P:vcyl("HairSpray", 0.55, 0.16, CF(ax - 0.2, ay + 0.3, wv.c.Z), lk(rgb(200, 60, 120), M.Metal))
			P:vcyl("CottonJar", 0.3, 0.26, CF(ax + 0.2, ay + 0.2, wv.c.Z), gl(rgb(240, 250, 255), 0.3))
			-- 'CCTV 없음' 안내 (서쪽 벽)
			txt(P, "PrivacyNotice", 1.4, 0.45, faceCF(V3(west + 0.02, 5.6, back + 2.4), V3(1, 0, 0)), "화장실 내부 CCTV 없음\n불법촬영 점검 완료 ✓", rgb(255, 255, 255), rgb(20, 70, 120), F.GothamBold)
		end)
		-- 칸마다: 화장지 홀더 · 위생함 · 문 안쪽 옷걸이 고리 · 안내
		for _, b in W.ToiletBowl or {} do
			local zc = b.c.Z
			P:free(function()
				tissueHolder(P, faceCF(V3(b.mn.X - 0.2, 2.6, zc - 1.36), V3(0, 0, 1)))
				P:box("SanitaryBin", V3(0.5, 1.0, 0.7), CF(b.mn.X - 0.9, 0.5, zc + 1.0), lk(rgb(236, 220, 230), M.Plastic))
				P:box("SanitaryBinLid", V3(0.52, 0.06, 0.72), CF(b.mn.X - 0.9, 1.03, zc + 1.0), lk(rgb(220, 200, 214), M.Plastic))
				txt(P, "StallNotice", 1.2, 0.5, faceCF(V3(b.mx.X + 0.35, 5.2, zc), V3(-1, 0, 0)), "화장지는 변기에\n생리대는 위생함에", rgb(40, 40, 44), rgb(244, 240, 236), F.GothamBold)
			end)
		end
		for _, d in W.StallDoor or {} do
			P:free(function()
				P:box("StallHook", V3(0.2, 0.08, 0.08), CF(d.mx.X + 0.1, 6.0, d.c.Z), CHROME)
				P:box("StallHookTip", V3(0.06, 0.18, 0.06), CF(d.mx.X + 0.18, 6.08, d.c.Z), CHROME)
			end)
		end
		local lamp = P:disc("WCLampW", 0.8, 0.05, CF(wv.c.X - 3.5, 10.85, wv.c.Z + 3.5), nl(rgb(255, 232, 214)))
		K:light(lamp, "PointLight", { Range = 16, Brightness = 1.6, Color = rgb(255, 222, 226) })
	end
	-- 남자 화장실 ------------------------------------------------------------------------------------------
	local Mn = restroomParts(R, "남자화장실")
	local mv = one(Mn, "VanityCounter")
	if mv then
		local fz = mv.mn.Z -- 거울 벽 (홀 쪽 벽 안쪽 면)
		P:free(function()
			-- 화장대 동쪽 끝 옆: 종이타월 + 휴지통
			local tx = mv.mx.X + 1.0
			table.insert(towels, towelDispenser(P, faceCF(V3(tx, 5.0, fz), V3(0, 0, 1))))
			trashBin(P, faceCF(V3(tx, 0, fz + 0.55), V3(0, 0, 1)), 2.0, 0.8)
			txt(P, "TowelNotice", 1.6, 0.5, faceCF(V3(tx, 6.7, fz + 0.01), V3(0, 0, 1)), "종이타월은 휴지통에\n한 장이면 충분해요", rgb(255, 255, 255), rgb(20, 70, 140), F.GothamBold)
			-- 소변기: 센서 · 방향제 매트 · 그 유명한 문구
			local urs = Mn.Urinal or {}
			for _, u in urs do
				local wz = u.mx.Z
				P:plate("UrinalSensor", 0.4, 0.3, 0.12, faceCF(V3(u.c.X, u.mx.Y + 0.45, wz), V3(0, 0, -1)), CHROME)
				P:plate("UrinalSensorEye", 0.1, 0.06, 0.13, faceCF(V3(u.c.X, u.mx.Y + 0.4, wz), V3(0, 0, -1)), lk(rgb(30, 10, 10), M.Glass))
				P:box("UrinalScreen", V3(0.8, 0.04, 0.6), CF(u.c.X, u.mn.Y + 0.25, u.c.Z - 0.1), lk(rgb(80, 200, 220), M.Plastic))
			end
			if #urs > 0 then
				local ux0, ux1 = math.huge, -math.huge
				for _, u in urs do
					ux0 = math.min(ux0, u.mn.X)
					ux1 = math.max(ux1, u.mx.X)
				end
				txt(P, "UrinalNotice", math.min(5, ux1 - ux0), 0.5, faceCF(V3((ux0 + ux1) / 2, 7.3, urs[1].mx.Z - 0.01), V3(0, 0, -1)), "남자가 흘리지 말아야 할 것은 눈물만이 아닙니다 · 한 걸음 더 가까이", rgb(240, 240, 240), rgb(20, 24, 30), F.GothamBold)
			end
			-- 바닥 배수구
			local dx, dz = (mv.mx.X + (Mn.StallDoor and Mn.StallDoor[1] and Mn.StallDoor[1].mn.X or mv.mx.X + 6)) / 2, mv.mx.Z + 2.2
			local dy = 0.1
			for _, fl in Mn.Floor or {} do
				if dx > fl.mn.X and dx < fl.mx.X and dz > fl.mn.Z and dz < fl.mx.Z then
					dy = fl.mx.Y
				end
			end
			P:box("FloorDrain", V3(0.6, 0.015, 0.6), CF(dx, dy + 0.006, dz), STEEL)
		end)
		local part = one(Mn, "StallPartition")
		for _, b in Mn.ToiletBowl or {} do
			P:free(function()
				if part then
					local up = b.c.Z > part.c.Z
					local z = if up then part.mx.Z + 0.02 else part.mn.Z - 0.02
					tissueHolder(P, faceCF(V3(b.mn.X - 0.2, 2.6, z), V3(0, 0, if up then 1 else -1)))
				end
				txt(P, "StallNotice", 1.2, 0.5, faceCF(V3(b.mx.X + 0.35, 5.2, b.c.Z), V3(-1, 0, 0)), "화장지는 변기에\n물은 꼭 내려 주세요", rgb(40, 40, 44), rgb(244, 240, 236), F.GothamBold)
			end)
		end
		for _, d in Mn.StallDoor or {} do
			P:free(function()
				P:box("StallHook", V3(0.2, 0.08, 0.08), CF(d.mx.X + 0.1, 6.0, d.c.Z), CHROME)
			end)
		end
		local lamp = P:disc("WCLampM", 0.8, 0.05, CF(mv.c.X, 10.65, mv.c.Z + 4.0), nl(rgb(236, 244, 255)))
		K:light(lamp, "PointLight", { Range = 16, Brightness = 1.6, Color = rgb(226, 238, 255) })
	end
	-- 상호작용: 종이타월 뽑기 (한 장 쏙 나왔다 사라짐)
	for _, t in towels do
		local base = t.CFrame
		Interact.prompt(K, t, {
			action = "종이타월 뽑기",
			object = "페이퍼 타월",
			sound = "rbxasset://sounds/swoosh.wav",
			fn = function()
				if not t.Parent then
					return
				end
				t.CFrame = base
				t.Transparency = 0
				local down = base * CFrame.new(0, -0.9, 0.15)
				TweenService:Create(t, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = down }):Play()
				task.delay(1.6, function()
					if t.Parent then
						TweenService:Create(t, TweenInfo.new(0.4), { Transparency = 1 }):Play()
						task.delay(0.6, function()
							if t.Parent then
								t.CFrame = base
								t.Transparency = 0
							end
						end)
					end
				end)
			end,
		})
	end
end

-- 보틀 서비스 스탠드 (크롬 받침 + LED 바스켓 + 냅킨): 샴페인 캐비닛 · 샴페인 타워 옆 · VIP 테이블 끝 중 빈 곳
local function mainBottleStands(R: any)
	local P = R.P
	local plats = R.find("PlatformTop")
	local function floorY(x: number, z: number): number
		for _, pt in plats do
			if x > pt.mn.X and x < pt.mx.X and z > pt.mn.Z and z < pt.mx.Z then
				return pt.mx.Y
			end
		end
		return 0
	end
	local cands = {}
	local cab = R.one("ChampagneCabinet")
	if not cab then
		local l = R.findPrefix("Cabinet", "ChampagneCabinet")
		cab = l[1]
	end
	local cabs = R.findPrefix("", "ChampagneCabinet")
	if #cabs > 0 then
		local mn, mx = cabs[1].mn, cabs[1].mx
		for _, c in cabs do
			mn = mn:Min(c.mn)
			mx = mx:Max(c.mx)
		end
		local cx, cz = (mn.X + mx.X) / 2, mx.Z
		table.insert(cands, V3(mn.X - 0.8, 0, cz + 0.6))
		table.insert(cands, V3(mx.X + 0.8, 0, cz + 0.6))
		table.insert(cands, V3(cx - 1.4, 0, cz + 1.0))
	end
	local tow = R.findPrefix("", "ChampagneTower")
	if #tow > 0 then
		local mn, mx = tow[1].mn, tow[1].mx
		for _, c in tow do
			mn = mn:Min(c.mn)
			mx = mx:Max(c.mx)
		end
		table.insert(cands, V3(mx.X + 0.9, 0, (mn.Z + mx.Z) / 2))
		table.insert(cands, V3((mn.X + mx.X) / 2, 0, mx.Z + 0.9))
	end
	for _, t in R.find("MarbleTop") do
		local tm = t.part.Parent
		local tn = if tm then tm.Name else ""
		if string.sub(tn, 1, 7) == "Table_G" then
			table.insert(cands, V3(t.c.X - t.s.X / 2 - 0.6, 0, t.mx.Z + 1.0))
			table.insert(cands, V3(t.c.X + t.s.X / 2 + 0.6, 0, t.mx.Z + 1.0))
		end
	end
	local n = 0
	for _, c in cands do
		if n >= 3 then
			break
		end
		local y = floorY(c.X, c.Z)
		local pcf = CF(c.X, y, c.Z)
		if spotOK(P, pcf, V3(1.0, 3.9, 1.0), 0.05, "bottle stand") then
			n += 1
			P:disc("StandBase", 0.95, 0.06, pcf * CF(0, 0.03, 0), CHROME)
			P:vcyl("StandPole", 2.3, 0.1, pcf * CF(0, 1.2, 0), CHROME)
			P:ring("StandRing", pcf * CF(0, 2.38, 0) * ANG(PI / 2, 0, 0), 0.44, 0.06, 8, CHROME)
			iceBucket(P, faceCF((pcf * CF(0, 2.3, 0)).Position, V3(0, 0, 1)), BOTTLE_KINDS[if n % 2 == 0 then "rose" else "champ"], if n % 2 == 0 then rgb(255, 110, 190) else rgb(90, 200, 255))
			P:box("StandNapkin", V3(0.5, 0.6, 0.02), pcf * CF(0.43, 2.55, 0.0) * ANG(0, PI / 2, 0.08), lk(rgb(250, 250, 248), M.Fabric))
		end
	end
	local _ = cab
end

-- 생수 무료 스테이션 (여자 화장실 앞 벽의 홀 쪽 면, 문 오른쪽 · 비상구 가기 전): 벽걸이 정수기 + 컵 디스펜서 + 컵 수거함, '물 한 잔'
local function mainWater(R: any)
	local P, K = R.P, R.K
	local Wr = restroomParts(R, "여자화장실")
	local wall: any = nil
	for _, w in Wr.Wall or {} do
		if w.s.X > 8 and (not wall or w.mx.Z > wall.mx.Z) then
			wall = w
		end
	end
	if not wall then
		return
	end
	local x = math.min(wall.mn.X + 2.0, R.wallR - 1.5)
	-- NPC 가 서 있으면 건너뜀
	for _, h in R.find("HumanoidRootPart") do
		if math.abs(h.c.X - x) < 2.2 and h.c.Z > wall.mx.Z - 0.5 and h.c.Z < wall.mx.Z + 2.0 then
			P:note("water station: NPC in front, skipped")
			return
		end
	end
	local f = faceCF(V3(x, 4.2, wall.mx.Z + 0.005), V3(0, 0, 1))
	local cup: BasePart? = nil
	P:free(function()
		P:plate("WaterBack", 2.6, 4.4, 0.06, f * CF(0, 0.6, 0), lk(rgb(18, 40, 60)))
		P:plate("WaterBackRim", 2.7, 0.06, 0.08, f * CF(0, 2.82, 0), nl(CY))
		txt(P, "WaterTitle", 2.4, 0.6, f * CF(0, 2.35, 0.07), "FREE WATER · 생수 무료", rgb(220, 250, 255), nil, F.GothamBlack, 1.4)
		-- 정수기 본체 (벽걸이)
		P:plate("WaterUnit", 1.1, 1.8, 0.7, f * CF(-0.4, 0.4, 0), lk(rgb(236, 238, 240), M.Plastic))
		P:plate("WaterUnitPanel", 0.8, 0.4, 0.71, f * CF(-0.4, 0.95, 0), lk(rgb(30, 34, 40)))
		P:plate("WaterUnitLED", 0.12, 0.08, 0.72, f * CF(-0.6, 0.95, 0), nl(rgb(60, 160, 255)))
		P:plate("WaterUnitLED", 0.12, 0.08, 0.72, f * CF(-0.2, 0.95, 0), nl(rgb(255, 80, 60)))
		P:plate("WaterNozzleBlock", 0.4, 0.2, 0.9, f * CF(-0.4, 0.2, 0), CHROME)
		P:plate("WaterDripTray", 0.9, 0.08, 0.95, f * CF(-0.4, -0.75, 0), lk(rgb(40, 40, 44), M.DiamondPlate))
		cup = P:vcyl("WaterCup", 0.32, 0.26, (f * CF(-0.4, -0.55, 0.62)) * ANG(-PI / 2, 0, 0) * ANG(PI / 2, 0, 0), lk(rgb(250, 250, 250), M.Plastic, { t = 1 }))
		-- 컵 디스펜서 (세로 통) + 수거함
		P:plate("CupTube", 0.36, 1.6, 0.36, f * CF(0.55, 0.4, 0), gl(rgb(235, 240, 245), 0.4))
		P:vcyl("CupStackW", 1.3, 0.28, CF((f * CF(0.55, 0.35, 0.18)).Position), lk(rgb(250, 250, 250)))
		P:plate("CupBin", 0.6, 0.9, 0.5, f * CF(0.55, -1.0, 0), STEEL)
		P:plate("CupBinSlot", 0.4, 0.08, 0.51, f * CF(0.55, -0.68, 0), lk(rgb(10, 10, 12)))
		txt(P, "WaterNote", 2.2, 0.32, f * CF(0, -1.65, 0.07), "다 마신 컵은 수거함에 · 과음 주의", rgb(200, 230, 255), nil, F.GothamBold, 1.2)
	end)
	if cup then
		local c: BasePart = cup
		Interact.prompt(K, c.Parent and P:plate("WaterButton", 0.24, 0.18, 0.74, f * CF(-0.4, 0.62, 0), lk(rgb(60, 160, 255), M.Neon)) or c, {
			action = "물 한 잔",
			object = "생수 무료",
			sound = "rbxasset://sounds/electronicpingshort.wav",
			fn = function()
				if not c.Parent then
					return
				end
				c.Transparency = 0
				task.delay(4, function()
					if c.Parent then
						TweenService:Create(c, TweenInfo.new(0.5), { Transparency = 1 }):Play()
					end
				end)
			end,
		})
	end
end

local function buildMain(K: any, V: any)
	local R = makeRoom(K, V)
	-- 긴 벽 안쪽 면 (정렬 프레임)
	R.wallL, R.wallR = -35.0, 34.4
	local bl, br = 0, 0
	for _, w in R.find("MainWall_Left") do
		if w.s.Z > bl then
			bl = w.s.Z
			R.wallL = w.mx.X
		end
	end
	for _, w in R.find("MainWall_Right") do
		if w.s.Z > br then
			br = w.s.Z
			R.wallR = w.mn.X
		end
	end
	local steps = {
		{ "bar", mainBar },
		{ "service", mainServiceStation },
		{ "dj", mainDJ },
		{ "vip", mainVIP },
		{ "champagne", mainChampagne },
		{ "smoking", mainSmoking },
		{ "staffdoor", mainStaffDoor },
		{ "coatcheck", mainCoatCheck },
		{ "restrooms", mainRestrooms },
		{ "stands", mainBottleStands },
		{ "water", mainWater },
	}
	for _, s in steps do
		local ok, err = pcall(s[2], R)
		if not ok then
			K:note("main." .. s[1] .. " error: " .. tostring(err))
		end
	end
end

------------------------------------------------------------------------------------------------------------

function T.style(V: any): any
	-- 클럽은 모든 기존 가구가 게임플레이 (좌석 · 테이블 · 바) → 리스킨 없음, 공통 마감 없음 (전부 이 모듈이 정렬 프레임으로 지음)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true, floor = true, walls = true, ceiling = true } }
end

function T.build(K: any, V: any, S: any)
	if V.type == "clublobby" then
		buildLobby(K, V)
	elseif V.type == "clubtunnel" then
		buildTunnel(K, V)
	elseif V.type == "clubmain" then
		buildMain(K, V)
	end
end

return T
