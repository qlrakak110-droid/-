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
--              포토월 (포토존 바닥 스티커 · 업라이트 · 폰 거치대 촬영) · 락커 32칸 (번호판 · 손잡이 · 키 밴드 · 열리는 107번) ·
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
local GLOSS = lk(rgb(8, 8, 10), M.Glass, { r = 0.25 })
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
	-- 안내판 (테이블 뒤 벽)
	lightbox(P, "BagRule", R.wall("back", cx + 1.0, 4.4, 0.0) * CF(0, 0, 0.0), 1.9, 1.0, "반입 금지", "외부 음식 · 음료 · 위험물 · 레이저 포인터", { titleH = 0.36, accent = rgb(255, 90, 90), frame = BMETAL })
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

-- 락커 32칸: 몸체 · 번호판을 우리 것으로 다시 짓고 (속이 빈 칸), 문마다 번호판 · 손잡이 · 키 (빈 칸엔 코일 키 밴드), 107번 열림
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
	local CARC = lk(rgb(28, 28, 32), M.Metal)
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
				openDoor = { door = door, led = led, x = x, y = y, n = n }
				continue
			end
			-- 번호판 (위 가운데) · 손잡이 (LED 아래) · 키 실린더
			local lx = if led then -(led.c.X - x) else -0.8 -- dcf X 는 -X 방향
			txt(P, "LockerNo", 0.62, 0.3, face * CF(0, dh / 2 - 0.32, 0.0), tostring(n), rgb(20, 20, 22), rgb(196, 198, 202), F.GothamBold)
			P:plate("LockerPull", 0.08, 0.62, 0.06, face * CF(lx, -0.32, 0), CHROME)
			wdisc(P, "LockerKeyLock", 0.16, 0.04, face * CF(lx, -0.82, 0), CHROME)
			if free and hi(K) then
				-- 꽂혀 있는 키 + 코일 밴드 (오션 블루)
				P:plate("LockerKey", 0.07, 0.22, 0.03, face * CF(lx, -0.82, 0.04), BRASS)
				P:cyl("KeyBandCoil", 0.24, 0.18, face * CF(lx, -1.0, 0.1), lk(CY, M.Plastic, { t = 0.15 }))
			end
		end
	end
	-- 이용 안내판 (락커 오른쪽 · 벽)
	local gx = (cx1 + R.xr) / 2
	if R.xr - cx1 > 1.8 then
		-- (앞 벽 전체에 'window' keep 이 잡혀 있음: 유리창이 아니라 벽이라 free 로 붙임)
		P:free(function()
			lightbox(P, "LockerGuide", R.wall("front", gx, 5.2, 0.0), math.min(2.2, R.xr - cx1 - 0.4), 3.2, "LOCKER\n이용 안내", "① 초록 불 칸을 고르세요\n② 키 밴드를 손목에\n③ 퇴장 시 키 반납\n\n1회 ₩2,000 · 계산대 결제\n키 분실 ₩10,000", { titleH = 0.9, accent = CY, frame = BMETAL })
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
			P:box("LockerInnerLED", V3(dw - 0.3, 0.03, 0.04), CF(x, y + dh / 2 - 0.12, zf + 0.25), nl(rgb(240, 245, 255)))
			P:seg("LockerHangerRod", V3(x - dw / 2 + 0.15, y + dh / 2 - 0.35, zf + depth * 0.55), V3(x + dw / 2 - 0.15, y + dh / 2 - 0.35, zf + depth * 0.55), 0.05, CHROME)
			txt(P, "LockerInnerSticker", 0.9, 0.5, CF(x, y - 0.1, zb - 0.07) * ANG(0, PI, 0), "No." .. tostring(n) .. "\n퇴장 시 키 반납", rgb(30, 30, 34), rgb(240, 240, 236), F.GothamBold)
			P:box("LockerHook", V3(0.06, 0.2, 0.18), CF(x + 0.6, y + 0.25, zb - 0.15), CHROME)
		end)
		local lx = if openDoor.led then -(openDoor.led.c.X - x) else -0.8
		local g = K:group("Locker" .. tostring(n), function()
			P:free(function()
				P:plate("LockerDoorNew", dw, dh, 0.08, face * CF(0, 0, -0.03), lk(d.part.Color, M.Metal))
				for k = 0, 3 do
					P:plate("LockerVent", dw * 0.5, 0.04, 0.09, face * CF(0, dh / 2 - 0.62 - k * 0.1, -0.03), lk(rgb(16, 16, 18)))
				end
				txt(P, "LockerNo", 0.62, 0.3, face * CF(0, dh / 2 - 0.32, 0.055), tostring(n), rgb(20, 20, 22), rgb(196, 198, 202), F.GothamBold)
				P:plate("LockerLED", 0.26, 0.16, 0.04, face * CF(lx, 0.1, 0.05), nl(rgb(60, 230, 120)))
				wdisc(P, "LockerKeyLock", 0.16, 0.04, face * CF(lx, -0.82, 0.05), CHROME)
				P:plate("LockerKey", 0.07, 0.22, 0.03, face * CF(lx, -0.82, 0.09), BRASS)
				P:cyl("KeyBandCoil", 0.24, 0.18, face * CF(lx, -1.0, 0.15), lk(CY, M.Plastic, { t = 0.15 }))
				P:plate("LockerHandle", 0.08, 0.62, 0.06, face * CF(lx, -0.32, 0.05), CHROME)
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
			wash(car.c.X, R.fz - 4.2, V3(car.c.X, 3.5, R.fz), 95, 1.5)
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
			if z > R.bz + 0.5 and z < R.fz - 0.5 then
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
			-- 투사 빛 (아주 옅은 빔)
			P:seg("GoboBeam", V3(cx, H - 0.8, pz - 0.5), V3(cx, 0.1, pz - 4.6), 0.9, lk(rgb(200, 240, 255), M.Neon, { t = 0.94 }))
		end)
		local tz = pz - 4.6
		P:free(function()
			P:disc("GoboSpot", 4.2, 0.012, CF(cx, 0.008, tz), lk(rgb(30, 60, 80), M.Neon, { t = 0.75 }))
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
	-- 5) 안내판 (터널 입구 · 로비 쪽 끝)
	table.insert(steps, { "signs", function()
		-- 입구 쪽 (현관 끝) 왼쪽 패널 위 안내
		local z1 = if #barsZ > 0 then (barsZ[#barsZ] + R.fz) / 2 else R.fz - 0.6
		local z0 = if #barsZ > 1 then (barsZ[1] + barsZ[2]) / 2 else R.bz + 1
		P:free(function()
			lightbox(P, "TunnelRules", R.wall("left", z0, 4.6, 0.04), 1.5, 2.6, "19+", "만 19세 이상\n신분증 필수\n\nDRESS CODE\n슬리퍼 · 트레이닝복\n입장 불가", { titleH = 0.8, accent = rgb(255, 80, 80), frame = BMETAL })
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

local function buildMain(K: any, V: any)
	local R = makeRoom(K, V)
	local _ = R
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
