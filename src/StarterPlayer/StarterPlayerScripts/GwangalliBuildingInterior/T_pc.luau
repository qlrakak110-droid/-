--!strict
-- GwangalliBuildingInterior/T_pc: 광안 PC방 (광안타워 1F) 큰 시설 방 3개 실내 (Venues.luau 의 방, Scan.fitRoom).
--   pcbang  앞 구역: 자동문 · 키오스크 · 카운터(POS · 좌석 현황 · 단말기) · 주방(라면 조리기 · 전자레인지 · 주문 현황) ·
--           음료 냉장고 · 과자/컵라면 진열 · 셀프바(정수기 · 얼음 · 컵 · 국물 버리는 곳) · 흡연실(자동 문 · 공기청정기 ·
--           재떨이 · 스탠딩 선반 · 반투명 띠) · 대기 벤치 · 캡슐 뽑기 · 기어 진열장 · 천장 RGB · 행잉 사인
--   pchall  48석 홀: PCStation 은 안 건드림 (Seat · Keyboard · MonitorScreen · AislePos · ServePos). 칸막이 위 좌석 번호판 ·
--           헤드셋 걸이 · 직원 호출 버튼 · 의자 5발 베이스 · 열(A~F) 행잉 존 사인 + 통로 쪽 엔드캡 · 흡음 패널 벽 · 포스터 ·
--           흡음 배플 천장 + RGB · 두 번째 스파이럴 덕트 · 케이블 트레이 · 통로 러너 · 유도등 · 공기청정기 · RGB 조명 모드
--   pcback  뒤 띠: 라운지(소파 · TV · 루버 벽 · 펜던트) · 자판기 2 · 개인 보관함 + 휴대폰 충전함 · 프린터 · 분리수거 ·
--           화장실 문틀 · 손소독기 · 광안대교 네온 · 이용 안내 · 옥내소화전
-- 맵 건물은 방 프레임보다 0.375° 돌아가 있고 바닥 윗면이 0.1 낮음 -> measure() 가 실제 벽 · 바닥 · 천장을 재서
-- K.cf 를 건물 축 프레임으로 바꿔 둠 (이후 모든 좌표 = 건물 축, y = 실제 바닥 위 높이).
-- 상호작용 (클라이언트 전용): 흡연실 자동 문 (다가가면 열림) · 공기청정기 켜기/끄기 · 음료 냉장고 문 · 홀 RGB 조명 모드 ·
--   라운지 TV 채널 · 보관함 문. 애니메이션: 키오스크 안내 화면 · 실시간 좌석 현황 (PCUser 속성 읽기) · 주문 현황 ·
--   라면 김 · 공기청정기 팬 · 홀 RGB 숨쉬기 · 자판기 버튼.

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "pcbang", "pchall", "pcback" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
local YA = Vector3.yAxis

-- 색 (PC방 존 · RGB)
local C = {
	cyan = rgb(40, 236, 240),
	magenta = rgb(255, 60, 170),
	purple = rgb(160, 80, 255),
	blue = rgb(50, 150, 255),
	green = rgb(60, 240, 130),
	amber = rgb(255, 176, 40),
	red = rgb(255, 48, 60),
	white = rgb(246, 246, 250),
	ink = rgb(26, 26, 30),
	panel = rgb(30, 31, 36),
	felt = rgb(62, 64, 72),
	felt2 = rgb(48, 52, 66),
	exitGreen = rgb(0, 150, 80),
}

-- 작은 도구 ------------------------------------------------------------------------------------------------
local function lk(c: Color3, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c, m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
local function neon(c: Color3, t: number?): { [string]: any }
	return { c = c, m = M.Neon, t = t or 0 }
end
local function glassL(c: Color3?, t: number?): { [string]: any }
	return { c = c or rgb(214, 228, 234), m = M.Glass, t = t or 0.6, r = 0.12 }
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
-- 표시면 프레임 (점 p, 보는 쪽 법선 n)
local function faceCF(p: Vector3, n: Vector3): CFrame
	return CFrame.fromMatrix(p, YA:Cross(n).Unit, YA, n)
end
-- 소품 프레임 (원점 p, +Z = n)
local function facing(p: Vector3, n: Vector3): CFrame
	return CFrame.lookAt(p, p - n)
end
-- 표시면에 붙는 원판 (축 = dcf Z)
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end
local function hi(K: any): boolean
	return K.detail == "high"
end
local function lowD(K: any): boolean
	return K.detail == "low"
end
local function recs(V: any, name: string): { any }
	return V.byName[name] or {}
end
local function hide(K: any, r: any)
	if r and r.part then
		Scan.hide(K.hidden, r.part)
	end
end

-- 건물 축 프레임 · 실제 벽/바닥/천장 재기 -------------------------------------------------------------
local AX = {
	back = { u = V3(1, 0, 0), n = V3(0, 0, 1) },
	left = { u = V3(0, 0, -1), n = V3(1, 0, 0) },
	right = { u = V3(0, 0, 1), n = V3(-1, 0, 0) },
	front = { u = V3(-1, 0, 0), n = V3(0, 0, -1) },
}

local function measure(K: any, V: any)
	local P: any = { a = 0, fy = 0, ceil = V.H, has = {} }
	-- 1) 건물 회전 (큰 맵 파트의 X 축)
	local best = 0
	for _, r in V.parts do
		local s = r.part.Size
		local big = math.max(s.X, s.Z)
		if big > best and (s.Y > 6 or s.X * s.Z > 150) then
			local x = r.lcf.XVector
			if math.abs(x.Y) < 0.05 then
				local a = math.atan2(-x.Z, x.X)
				a = (a + PI / 4) % (PI / 2) - PI / 4
				if math.abs(a) < 0.06 then
					best = big
					P.a = a
				end
			end
		end
	end
	local R = ANG(0, P.a, 0)
	local Ri = R:Inverse()
	-- 2) 벽 · 바닥 · 천장 (모델 전체를 읽기만)
	local floors, ceils, walls = {}, {}, {}
	for _, d in V.model:GetDescendants() do
		if d:IsA("BasePart") then
			local lcf = Ri * V.cf:ToObjectSpace(d.CFrame)
			local mn, mx = Kit.laabb(lcf, d.Size)
			local ex = mx - mn
			if mx.X > V.x0 - 3 and mn.X < V.x1 + 3 and mx.Z > V.z0 - 3 and mn.Z < V.z1 + 3 and mx.Y > -3 and mn.Y < V.H + 3 then
				if ex.Y < 1.2 and ex.X * ex.Z > 150 then
					if mn.X < 0 and mx.X > 0 and mn.Z < 0 and mx.Z > 0 then
						if mx.Y < 1 and mx.Y > -1 then
							table.insert(floors, mx.Y)
						elseif mn.Y > 8 and mn.Y < V.H + 2 then
							table.insert(ceils, mn.Y)
						end
					end
				elseif ex.Y > 6 and math.min(ex.X, ex.Z) < 2.2 and math.max(ex.X, ex.Z) > 8 and d.Material ~= M.Glass and d.Transparency < 0.5 and mn.Y < 1.5 then
					table.insert(walls, { mn = mn, mx = mx })
				end
			end
		end
	end
	local fy = 0
	if #floors > 0 then
		fy = -math.huge
		for _, y in floors do
			fy = math.max(fy, y)
		end
	end
	local cy = V.H
	if #ceils > 0 then
		cy = math.huge
		for _, y in ceils do
			cy = math.min(cy, y)
		end
	end
	P.fy = fy
	P.ceil = cy - fy
	local xl, xr, zb, zf = nil, nil, nil, nil
	for _, w in walls do
		local zOver = w.mx.Z > V.z0 + 1 and w.mn.Z < V.z1 - 1 and (w.mx.Z - w.mn.Z) > 8
		local xOver = w.mx.X > V.x0 + 1 and w.mn.X < V.x1 - 1 and (w.mx.X - w.mn.X) > 8
		if zOver and w.mx.X < V.x0 + 1.0 and w.mx.X > V.x0 - 1.5 then
			xl = math.max(xl or -math.huge, w.mx.X)
		end
		if zOver and w.mn.X > V.x1 - 1.0 and w.mn.X < V.x1 + 1.5 then
			xr = math.min(xr or math.huge, w.mn.X)
		end
		if xOver and w.mx.Z < V.z0 + 1.0 and w.mx.Z > V.z0 - 1.5 then
			zb = math.max(zb or -math.huge, w.mx.Z)
		end
		if xOver and w.mn.Z > V.z1 - 1.0 and w.mn.Z < V.z1 + 1.5 then
			zf = math.min(zf or math.huge, w.mn.Z)
		end
	end
	P.has = { left = xl ~= nil, right = xr ~= nil, back = zb ~= nil, front = zf ~= nil }
	P.xl, P.xr, P.zb, P.zf = xl or V.x0, xr or V.x1, zb or V.z0, zf or V.z1
	P.T = CF(0, fy, 0) * R
	P.Ti = P.T:Inverse()
	K.cf = V.cf * P.T -- 이후 K 로 만드는 모든 파트 = 건물 축 프레임
	K.pc = P
	K:note(string.format("pc frame a=%.4f fy=%.2f ceil=%.2f xl=%.2f xr=%.2f zb=%.2f", P.a, fy, P.ceil, P.xl, P.xr, P.zb))
end

-- 맵 기록 -> 건물 축 AABB
local function mb(K: any, r: any): (Vector3, Vector3, Vector3)
	local mn, mx = Kit.laabb(K.pc.Ti * r.lcf, r.part.Size)
	return mn, mx, (mn + mx) / 2
end

-- 벽 표시면 프레임 (건물 축). u = 벽 가운데 기준 보는 사람 오른쪽, y = 바닥 위, off = 벽에서
local function W(K: any, wn: string, u: number, y: number, off: number?): CFrame
	local P = K.pc
	local ax = AX[wn]
	local o = if wn == "back" then V3(0, 0, P.zb) elseif wn == "front" then V3(0, 0, P.zf) elseif wn == "left" then V3(P.xl, 0, 0) else V3(P.xr, 0, 0)
	return CFrame.fromMatrix(o + ax.u * u + V3(0, y, 0) + ax.n * (off or 0), ax.u, YA, ax.n)
end

local function useWall(K: any, wn: string, a: number, b: number, y0: number, y1: number)
	K.wallUsed = K.wallUsed or {}
	table.insert(K.wallUsed, { w = wn, a = a, b = b, y0 = y0, y1 = y1 })
end

-- 벽면 빈 구간 (V:spans - K.wallUsed)
local function freeSpans(K: any, wn: string, y0: number, y1: number, depth: number?): { { number } }
	local out = {}
	for _, s in K.V:spans(wn, y0, y1, depth or 1.0) do
		local segs = { { s[1], s[2] } }
		for _, u in K.wallUsed or {} do
			if u.w == wn and u.y1 > y0 and u.y0 < y1 then
				local nxt = {}
				for _, g in segs do
					if u.b <= g[1] or u.a >= g[2] then
						table.insert(nxt, g)
					else
						if u.a > g[1] then
							table.insert(nxt, { g[1], u.a })
						end
						if u.b < g[2] then
							table.insert(nxt, { u.b, g[2] })
						end
					end
				end
				segs = nxt
			end
		end
		for _, g in segs do
			if g[2] - g[1] > 0.5 then
				table.insert(out, g)
			end
		end
	end
	return out
end

-- u0..u1 (y0..y1) 가 통째로 비었나?
local function wallFree(K: any, wn: string, u0: number, u1: number, y0: number, y1: number): boolean
	for _, s in freeSpans(K, wn, y0, y1, 1.0) do
		if s[1] <= u0 + 0.01 and s[2] >= u1 - 0.01 then
			return true
		end
	end
	return false
end

-- keep 추가 (건물 축 좌표 ≈ 방 프레임: 0.2 스터드 이내)
local function keepBox(V: any, x0: number, z0: number, x1: number, z1: number, y1: number?, kind: string?)
	V:addKeep(V3(math.min(x0, x1), 0.1, math.min(z0, z1)), V3(math.max(x0, x1), y1 or 6.5, math.max(z0, z1)), kind or "pclane")
end
local function keepLane(V: any, a: Vector3, b: Vector3, w: number, kind: string?)
	local len = (b - a).Magnitude
	local n = math.max(1, math.ceil(len / 1.2))
	local h = w / 2
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		V:addKeep(V3(p.X - h, 0.1, p.Z - h), V3(p.X + h, 6.5, p.Z + h), kind or "pclane")
	end
end

-- 우리 프롬프트를 둘 수 있나 (서버 앵커 · 게임 포인트 · PC 키보드에서 7 스터드)
local function promptOK(K: any, part: BasePart?): boolean
	if not part or part.Parent == nil then
		return false
	end
	local lp = K.V.cf:PointToObjectSpace(part.Position)
	local function far(c: Vector3): boolean
		local d = c - lp
		return Vector3.new(d.X, 0, d.Z).Magnitude >= 7
	end
	for _, r in K.V.points do
		if not far(r.c) then
			return false
		end
	end
	for _, nm in { "Keyboard", "Spot_pc_counter", "BoardFace", "HotWater", "WaterPurifier", "CounterTop" } do
		for _, r in recs(K.V, nm) do
			if not far(r.c) then
				return false
			end
		end
	end
	return true
end

-- 자리 확인 + 실패 기록
local function spotN(K: any, lcf: CFrame, size: Vector3, pad: number?, what: string?): boolean
	-- Kit:spot 는 방 프레임(V.solid · keep · 방 상자)과 비교하므로 건물 축 -> 방 프레임으로 바꾸고,
	-- 0.375° 회전 오차(벽 끝에서 0.2)만큼 가로 · 세로를 줄여 확인
	local s2 = V3(math.max(0.3, size.X - 0.4), size.Y, math.max(0.3, size.Z - 0.4))
	local lc = K.pc.T * lcf
	local ok = K:spot(lc, s2, pad)
	if not ok then
		local V = K.V
		local mn, mx = Kit.laabb(lc * CF(0, s2.Y / 2, 0), s2 + V3(2 * (pad or 0), 0, 2 * (pad or 0)))
		local why = "bounds"
		local kk = K:hitsKeep(mn, mx)
		if kk then
			why = "keep:" .. kk
		else
			for _, so in V.solid do
				if Kit.overlap(mn, mx, so.min, so.max, 0.04) then
					why = "solid:" .. so.name
					break
				end
			end
			for _, r in K.reserved do
				if Kit.overlap(mn, mx, r.min, r.max, 0.02) then
					why = "reserved:" .. tostring(r.kind)
				end
			end
		end
		K:note("spot blocked " .. tostring(what or "?") .. string.format(" @%.1f,%.1f ", lcf.X, lcf.Z) .. why)
	end
	return ok
end

-- 공통 소품 -------------------------------------------------------------------------------------------------

-- 안내문 (흰 판 + 색 머리띠 + 본문)
local function notice(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, accent: Color3, o: any?)
	local oo: any = o or {}
	K:plate("NoticeBack", w + 0.1, h + 0.1, 0.03, dcf, lk(oo.frame or rgb(24, 24, 28)))
	K:plate("Notice", w, h, 0.045, dcf, lk(oo.bg or rgb(248, 248, 244)))
	local hh = math.min(h * 0.24, 0.75)
	K:plate("NoticeBand", w, hh, 0.05, dcf * CF(0, h / 2 - hh / 2, 0), lk(accent))
	K:text("NoticeTitle", w * 0.92, hh * 0.78, dcf * CF(0, h / 2 - hh / 2, 0.05), title, { fg = oo.titleFg or WHITE, font = F.GothamBlack })
	K:text("NoticeBody", w * 0.88, (h - hh) * 0.84, dcf * CF(0, -hh / 2, 0.05), body, { fg = oo.fg or rgb(30, 30, 34), font = F.GothamMedium, align = oo.align })
end

-- 라이트박스 (한 면) : 검은 테 + 면 + 네온 테두리 + 글자
local function lightbox(K: any, dcf: CFrame, w: number, h: number, text: string, fg: Color3, bg: Color3, edge: Color3?, o: any?)
	local oo: any = o or {}
	K:plate("LightboxFrame", w + 0.14, h + 0.14, 0.2, dcf, Look.blackMetal)
	local face = K:plate("LightboxFace", w, h, 0.22, dcf, lk(bg))
	if edge then
		K:plate("LightboxEdge", w, 0.05, 0.235, dcf * CF(0, h / 2 - 0.025, 0), neon(edge))
		K:plate("LightboxEdge", w, 0.05, 0.235, dcf * CF(0, -h / 2 + 0.025, 0), neon(edge))
	end
	local p, l = K:text("LightboxText", w * (oo.tw or 0.92), h * (oo.th or 0.8), dcf * CF(0, oo.ty or 0, 0.225), text, { fg = fg, glow = oo.glow or 1.5, font = oo.font or F.GothamBlack, align = oo.align })
	return face, p, l
end

-- 게임 포스터 (색 블록 키아트 + 제목 + 부제)
local function poster(K: any, dcf: CFrame, w: number, h: number, spec: any)
	local fr = Look.blackMetal
	K:plate("PosterBack", w, h, 0.06, dcf, lk(spec.bg))
	local b = 0.09
	K:plate("PosterFrame", w + 0.08, b, 0.1, dcf * CF(0, h / 2, 0), fr)
	K:plate("PosterFrame", w + 0.08, b, 0.1, dcf * CF(0, -h / 2, 0), fr)
	K:plate("PosterFrame", b, h, 0.1, dcf * CF(-w / 2, 0, 0), fr)
	K:plate("PosterFrame", b, h, 0.1, dcf * CF(w / 2, 0, 0), fr)
	for i, a in spec.art or {} do
		local c: Color3 = a[1]
		local look = if a[7] then neon(c) else lk(c)
		K:plate("PosterArt", w * a[4], h * a[5], 0.065 + i * 0.002, dcf * CF(-w / 2 + w * a[2], -h / 2 + h * a[3], 0) * ANG(0, 0, math.rad(a[6] or 0)), look)
	end
	if spec.title then
		K:text("PosterTitle", w * 0.9, h * (spec.titleH or 0.16), dcf * CF(0, h * (spec.titleY or 0.3), 0.1), spec.title, { fg = spec.tc or WHITE, glow = 1.4, font = spec.font or F.Michroma })
	end
	if spec.sub then
		K:text("PosterSub", w * 0.86, h * (spec.subH or 0.12), dcf * CF(0, h * (spec.subY or -0.36), 0.1), spec.sub, { fg = spec.sc or rgb(230, 230, 236), glow = 1.1, font = F.GothamBold })
	end
	K:plate("PosterGlass", w - 0.02, h - 0.02, 0.012, dcf * CF(0, 0, 0.11), { c = rgb(230, 236, 240), m = M.Glass, t = 0.9, r = 0.18 })
end

-- 벽걸이 스피커
local function speaker(K: any, dcf: CFrame, tilt: number?)
	local c = dcf * CF(0, 0, 0.45) * ANG(math.rad(-(tilt or 12)), 0, 0)
	K:plate("SpeakerBracket", 0.3, 0.6, 0.45, dcf, Look.blackMetal)
	K:panel("Speaker", 0.9, 1.5, 0.8, 0.12, c * CF(0, 0, -0.4), lk(rgb(24, 24, 27), M.SmoothPlastic))
	K:plate("SpeakerGrille", 0.84, 1.3, 0.02, c * CF(0, 0, 0.4), lk(rgb(40, 40, 44), M.DiamondPlate))
	K:plate("SpeakerLogo", 0.24, 0.05, 0.01, c * CF(0, -0.5, 0.425), Look.chrome)
end

-- 천장 설비 (실제 천장 아래면에 붙음)
local function sprinkler(K: any, x: number, z: number)
	local y = K.pc.ceil
	K:free(function()
		K:disc("SprinklerRose", 0.3, 0.03, CF(x, y - 0.015, z), Look.white)
		K:vcyl("SprinklerBody", 0.16, 0.08, CF(x, y - 0.1, z), Look.brass)
		K:disc("SprinklerDeflector", 0.2, 0.02, CF(x, y - 0.19, z), Look.brass)
	end)
end
local function detector(K: any, x: number, z: number)
	local y = K.pc.ceil
	K:free(function()
		K:disc("SmokeDetector", 0.55, 0.14, CF(x, y - 0.07, z), Look.white)
		K:disc("SmokeDetectorLED", 0.06, 0.02, CF(x + 0.16, y - 0.15, z), Look.ledRed)
	end)
end
local function dome(K: any, x: number, z: number)
	local y = K.pc.ceil
	K:free(function()
		K:disc("CCTVBase", 0.62, 0.06, CF(x, y - 0.03, z), Look.white)
		K:ell("CCTVDome", V3(0.5, 0.5, 0.5), CF(x, y - 0.06, z), Look.with(Look.glassDark, { t = 0.15 }))
	end)
end
local function ceilSpeaker(K: any, x: number, z: number)
	local y = K.pc.ceil
	K:free(function()
		K:disc("CeilSpeakerTrim", 0.9, 0.04, CF(x, y - 0.02, z), Look.white)
		K:disc("CeilSpeakerGrille", 0.78, 0.03, CF(x, y - 0.045, z), lk(rgb(220, 220, 220), M.DiamondPlate))
	end)
end

-- 통로 유도등 (벽 아래, 초록 바탕 + 화살표)
local function guideLight(K: any, dcf: CFrame, txt: string)
	K:plate("GuideLightBox", 1.0, 0.5, 0.12, dcf, lk(rgb(230, 232, 228)))
	K:text("GuideLight", 0.9, 0.4, dcf * CF(0, 0, 0.125), txt, { fg = WHITE, bg = C.exitGreen, glow = 1.6, font = F.GothamBlack, d = 0.02 })
end

-- 벽걸이 소화기 + 표지
local function extinguisher(K: any, dcf: CFrame)
	K:text("ExtSign", 0.9, 0.5, dcf * CF(0, 3.4, 0), "소화기", { fg = WHITE, bg = rgb(200, 28, 32), font = F.GothamBlack, d = 0.03 })
	local base = dcf * CF(0, 0, 0.36)
	K:plate("ExtBracket", 0.5, 0.7, 0.06, dcf * CF(0, 1.6, 0), Look.blackMetal)
	local p = base.Position
	local up = CFrame.fromMatrix(V3(p.X, 0, p.Z), dcf.XVector, YA, dcf.ZVector)
	K:vcyl("ExtBody", 1.5, 0.6, up * CF(0, 0.2 + 0.75, 0), lk(rgb(200, 24, 28)))
	K:ell("ExtDome", V3(0.6, 0.3, 0.6), up * CF(0, 1.7, 0), lk(rgb(200, 24, 28)))
	K:vcyl("ExtNeck", 0.16, 0.2, up * CF(0, 1.88, 0), Look.black)
	K:box("ExtHandle", V3(0.5, 0.06, 0.12), up * CF(0.06, 2.02, 0) * ANG(0, 0, -0.2), Look.black)
	K:ball("ExtGauge", 0.17, up * CF(0, 1.9, 0.12), Look.white)
	K:seg("ExtHose", (up * CF(-0.05, 1.88, -0.1)).Position, (up * CF(-0.28, 0.7, 0.2)).Position, 0.08, Look.black)
	K:box("ExtFoot", V3(0.8, 0.2, 0.8), up * CF(0, 0.1, 0), lk(rgb(170, 26, 30)))
	K:text("ExtLabel", 0.42, 0.5, up * CF(0, 1.0, 0.305), "ABC\n분말", { fg = WHITE, bg = rgb(40, 40, 40), d = 0.01, free = true })
end

-- 두 면 행잉 사인 (천장에서 봉 2개). c = 가운데, n = 앞면 법선(수평), w x h
local function hangSign(K: any, c: Vector3, n: Vector3, w: number, h: number, front: string, back: string?, fg: Color3, edge: Color3, o: any?)
	local oo: any = o or {}
	local x = YA:Cross(n).Unit
	local base = CFrame.fromMatrix(c, x, YA, n)
	local box = K:box("HangSignBox", V3(w, h, 0.3), base, lk(oo.bg or rgb(16, 16, 20)))
	if oo.light then
		K:light(box, "PointLight", { Range = oo.range or 11, Brightness = oo.bright or 0.45, Color = edge })
	end
	K:box("HangSignEdge", V3(w + 0.04, 0.06, 0.34), base * CF(0, h / 2 - 0.03, 0), neon(edge))
	K:box("HangSignEdge", V3(w + 0.04, 0.06, 0.34), base * CF(0, -h / 2 + 0.03, 0), neon(edge))
	local l1, l2
	_, l1 = K:text("HangSignText", w * 0.94, h * 0.72, base * CF(0, 0, 0.15), front, { fg = fg, glow = 1.6, font = oo.font or F.GothamBlack })
	if back then
		_, l2 = K:text("HangSignText", w * 0.94, h * 0.72, base * CF(0, 0, -0.15) * ANG(0, PI, 0), back, { fg = fg, glow = 1.6, font = oo.font or F.GothamBlack })
	end
	for _, sx in { -1, 1 } do
		local p = base * V3(sx * (w / 2 - 0.5), h / 2, 0)
		K:seg("HangSignRod", p, V3(p.X, K.pc.ceil, p.Z), 0.06, Look.blackMetal)
		K:disc("HangSignCap", 0.22, 0.04, CF(p.X, K.pc.ceil - 0.02, p.Z), Look.blackMetal)
	end
	return l1, l2
end

-- 음료 (냉장고 · 자판기 진열): pcf = 바닥 가운데, kind
local DRINKS = {
	{ "pet", rgb(150, 20, 24), rgb(200, 30, 36), rgb(220, 30, 40) }, -- 콜라
	{ "pet", rgb(30, 120, 60), rgb(40, 160, 80), rgb(40, 160, 80) }, -- 사이다
	{ "can", rgb(240, 120, 20), rgb(30, 30, 30), rgb(200, 200, 204) }, -- 핫식스
	{ "can", rgb(20, 20, 22), rgb(120, 230, 60), rgb(180, 180, 184) }, -- 에너지 음료
	{ "pet", rgb(220, 236, 250), rgb(30, 90, 200), rgb(30, 90, 200) }, -- 이온 음료
	{ "pet", rgb(200, 226, 240), rgb(60, 150, 230), rgb(40, 110, 220) }, -- 생수
	{ "can", rgb(120, 70, 40), rgb(230, 210, 180), rgb(200, 200, 204) }, -- 캔커피
	{ "can", rgb(40, 90, 200), rgb(220, 220, 228), rgb(200, 200, 204) }, -- 탄산
}
local function drink(K: any, pcf: CFrame, kind: number, scale: number?)
	local s = scale or 1
	local d = DRINKS[(kind - 1) % #DRINKS + 1]
	if d[1] == "can" then
		local h, dia = 0.5 * s, 0.27 * s
		K:vcyl("DrinkCan", h, dia, pcf * CF(0, h / 2, 0), lk(d[2], M.Metal))
		K:vcyl("DrinkBand", h * 0.42, dia + 0.01, pcf * CF(0, h * 0.5, 0), lk(d[3]))
		if hi(K) then
			K:vcyl("DrinkTop", 0.03, dia * 0.86, pcf * CF(0, h + 0.015, 0), lk(d[4], M.Metal))
		end
	else
		local h, dia = 0.62 * s, 0.3 * s
		K:vcyl("DrinkPet", h, dia, pcf * CF(0, h / 2, 0), { c = d[2], m = M.Glass, t = 0.25, r = 0.1 })
		K:vcyl("DrinkLabel", h * 0.32, dia + 0.01, pcf * CF(0, h * 0.45, 0), lk(d[3]))
		K:vcyl("DrinkNeck", 0.16 * s, dia * 0.5, pcf * CF(0, h + 0.08 * s, 0), { c = d[2], m = M.Glass, t = 0.25 })
		K:vcyl("DrinkCap", 0.07 * s, dia * 0.44, pcf * CF(0, h + 0.19 * s, 0), lk(d[4]))
	end
end

-- 컵라면 · 사발면
local CUPS = {
	{ rgb(210, 30, 36), rgb(250, 246, 236) }, -- 신라면
	{ rgb(240, 130, 30), rgb(250, 240, 220) }, -- 진라면
	{ rgb(26, 26, 28), rgb(240, 200, 40) }, -- 짜장
	{ rgb(30, 30, 30), rgb(230, 40, 40) }, -- 불닭
	{ rgb(250, 248, 242), rgb(200, 40, 40) }, -- 육개장
	{ rgb(40, 80, 170), rgb(250, 246, 236) }, -- 우동
}
local function cupNoodle(K: any, pcf: CFrame, kind: number, bowl: boolean?)
	local c = CUPS[(kind - 1) % #CUPS + 1]
	if bowl then
		K:vcyl("CupBowl", 0.4, 0.8, pcf * CF(0, 0.2, 0), lk(c[2]))
		K:vcyl("CupBowlBand", 0.2, 0.82, pcf * CF(0, 0.22, 0), lk(c[1]))
		K:disc("CupLid", 0.84, 0.03, pcf * CF(0, 0.415, 0), lk(lt(c[1], 0.15)))
	else
		K:vcyl("Cup", 0.72, 0.58, pcf * CF(0, 0.36, 0), lk(c[1]))
		K:vcyl("CupBand", 0.22, 0.6, pcf * CF(0, 0.4, 0), lk(c[2]))
		K:disc("CupLid", 0.62, 0.03, pcf * CF(0, 0.735, 0), Look.of(214, 214, 210, M.Foil))
	end
end

-- 실시간 좌석 수 (PCStation 모델의 PCUser 속성 읽기)
local function pcModels(V: any): { Model }
	local out = {}
	for _, d in V.model:GetDescendants() do
		if d:IsA("Model") and string.match(d.Name, "^PC_%d+$") then
			table.insert(out, d)
		end
	end
	return out
end
local function usedSeats(list: { Model }): number
	local n = 0
	for _, m in list do
		local u = m:GetAttribute("PCUser")
		if type(u) == "number" and u ~= 0 then
			n += 1
		end
	end
	return n
end

-- 문 · 뚜껑을 TweenService 로 돌림 (자동문 · 프롬프트 공용): parts 기본 자세 저장
local function rotor(model: Model, hingeW: Vector3, axis: Vector3)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { p = d, cf = d.CFrame })
		end
	end
	return function(angle: number, dur: number?)
		local rot = CFrame.new(hingeW) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-hingeW)
		for _, r in parts do
			if r.p.Parent then
				TweenService:Create(r.p, TweenInfo.new(dur or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = rot * r.cf }):Play()
			end
		end
	end
end

-- 로컬 플레이어가 월드 점 p 에서 r 안에 있나
local function playerNear(p: Vector3, r: number): boolean
	local ok, res = pcall(function()
		local plr = Players.LocalPlayer
		local ch = plr and plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return (hrp.Position - p).Magnitude < r
		end
		return false
	end)
	return ok and res == true
end

-- 바닥 · 벽 마감 공용 ---------------------------------------------------------------------------------------
-- 흡음 패널 벽: 빈 구간마다 패브릭 패널 + 사이 홈 + 위 RGB 채널 + 걸레받이. RGB 파트는 K.pc.rgb 에 등록
local function acousticWall(K: any, wn: string, o: any?)
	local oo: any = o or {}
	local y0, y1 = oo.y0 or 0.6, oo.y1 or 8.6
	local pw = oo.pw or 2.3
	for _, s in freeSpans(K, wn, y0, y1, 1.0) do
		local len = s[2] - s[1]
		local n = math.max(1, math.floor(len / pw + 0.5))
		local step = len / n
		for i = 1, n do
			local u = s[1] + step * (i - 0.5)
			local alt = (i + math.floor(s[1])) % 3 == 0
			K:plate("AcousticPanel", step - 0.14, y1 - y0, 0.12, W(K, wn, u, (y0 + y1) / 2, 0.02), lk(if alt then C.felt2 else C.felt, M.Fabric))
			if hi(K) and (i % 2 == 0) then
				-- 패널 가운데 가는 홈 (흡음 슬롯)
				K:plate("AcousticGroove", 0.05, (y1 - y0) * 0.86, 0.125, W(K, wn, u, (y0 + y1) / 2, 0.02), lk(rgb(20, 20, 24)))
			end
		end
	end
	-- RGB 채널 (패널 위)
	for _, s in freeSpans(K, wn, y1 + 0.1, y1 + 0.5, 1.0) do
		local p = K:plate("WallRGB", s[2] - s[1], 0.08, 0.06, W(K, wn, (s[1] + s[2]) / 2, y1 + 0.3, 0.02), neon(oo.rgb or C.cyan))
		if p.Parent then
			table.insert(K.pc.rgb, { p = p, c = oo.rgb or C.cyan, x = p.Position.X, z = p.Position.Z })
		end
		K:plate("WallRGBChannel", s[2] - s[1], 0.2, 0.04, W(K, wn, (s[1] + s[2]) / 2, y1 + 0.3, 0.0), Look.blackMetal)
	end
	-- 걸레받이 (검은 금속)
	for _, s in freeSpans(K, wn, 0.12, 0.55, 0.6) do
		K:plate("Baseboard", s[2] - s[1], 0.45, 0.06, W(K, wn, (s[1] + s[2]) / 2, 0.36, 0.0), Look.blackMetal)
	end
end

-- 카펫 타일 줄눈 (홀 · 뒤 띠)
local function carpetSeams(K: any, x0: number, x1: number, z0: number, z1: number, step: number, look: any)
	K:free(function()
		local x = x0 + step
		while x < x1 - 0.2 do
			K:box("CarpetSeam", V3(0.04, 0.012, z1 - z0), CF(x, 0.006, (z0 + z1) / 2), look)
			x += step
		end
		local z = z0 + step
		while z < z1 - 0.2 do
			K:box("CarpetSeam", V3(x1 - x0, 0.012, 0.04), CF((x0 + x1) / 2, 0.006, z), look)
			z += step
		end
	end)
end

------------------------------------------------------------------------------------------------------------
-- 1) 앞 구역 (pcbang) -----------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

-- 동선 keep: 알바 배달 동선 (HomeCF -> Way1 -> Way2 -> Way3), 입구 -> 홀 통로, 셀프바 · 흡연실 · 카운터 손님 자리
local function frontKeeps(K: any, V: any)
	local P = K.pc
	local function loc(x: number, z: number): Vector3
		local p = P.Ti * V.cf:PointToObjectSpace(Vector3.new(x, V.cf.Y, z))
		return V3(p.X, 0, p.Z)
	end
	local home, w1, w2, w3 = loc(94.4, 278.9), loc(94.2, 271.1), loc(108.8, 271.2), loc(120.7, 292.0)
	keepLane(V, home, w1, 3.0, "clerk")
	keepLane(V, w1, w2, 3.0, "clerk")
	keepLane(V, w2, w3, 3.0, "clerk")
	local dx = if V.door then V.door.x else 9.8
	keepLane(V, V3(dx, 0, 6.4), V3(-2.2, 0, V.z0 - 0.5), 5.6, "walk")
	keepLane(V, V3(4.5, 0, 7.5), V3(-25.6, 0, 7.5), 3.6, "walk") -- 셀프바 쪽 통로
	keepLane(V, V3(-2.5, 0, -6.2), V3(-14.0, 0, -6.2), 3.4, "walk") -- 흡연실 입구
	K.pc.lanes = { home = home, w1 = w1, w2 = w2, w3 = w3 }
end

-- 주방 칸막이 + 조리대 위 장비 + 선반 + 주문 현황 + 등록증
local function frontKitchen(K: any, V: any)
	local P = K.pc
	local cab = recs(V, "BackCabinet")[1]
	if not cab then
		return
	end
	local cmn, cmx = mb(K, cab)
	local top = cmx.Y
	local xr = P.xr
	local x0 = cmn.X
	local zW = cmn.Z - 0.04 -- 칸막이 앞면 (주방 쪽)
	local th = 0.3
	local len = xr - x0
	local cx = (x0 + xr) / 2
	local H = P.ceil
	K:free(function()
		-- 칸막이 몸체 (바닥 ~ 천장)
		K:box("KitchenWall", V3(len, H, th), CF(cx, H / 2, zW - th / 2), lk(rgb(44, 45, 52)))
		-- 주방 쪽: 백 스플래시 타일 (조리대 위 ~ 6.6)
		local fc = faceCF(V3(cx, 0, zW), V3(0, 0, 1))
		local t0, t1 = top, 6.6
		K:plate("KitchenTile", len - 0.05, t1 - t0, 0.03, fc * CF(0, (t0 + t1) / 2, 0), Look.tileWhite)
		local rows = math.floor((t1 - t0) / 0.42)
		for i = 1, rows do
			K:plate("KitchenGrout", len - 0.05, 0.025, 0.035, fc * CF(0, t0 + i * 0.42, 0), Look.of(196, 196, 192))
		end
		if hi(K) then
			for i = 1, math.floor(len / 0.84) do
				local u = -len / 2 + i * 0.84
				K:plate("KitchenGrout", 0.025, t1 - t0, 0.035, fc * CF(u, (t0 + t1) / 2, 0), Look.of(196, 196, 192))
			end
		end
		K:plate("KitchenTrim", len - 0.05, 0.08, 0.05, fc * CF(0, t1 + 0.04, 0), Look.steel)
		-- 홀 쪽 면: 검은 패널 + RGB 띠 + 먹거리 메뉴판
		local bc = faceCF(V3(cx, 0, zW - th), V3(0, 0, -1))
		K:plate("KitchenWallBack", len - 0.05, H - 0.1, 0.02, bc * CF(0, H / 2, 0), lk(rgb(22, 22, 26)))
		local strip = K:plate("KitchenWallRGB", len - 0.3, 0.07, 0.04, bc * CF(0, 9.6, 0.02), neon(C.magenta))
		table.insert(P.rgb, { p = strip, c = C.magenta, x = 0, z = 0 })
		-- 홀 쪽 먹거리 메뉴판 (주문 가능한 메뉴 = VenueLife pcbang 메뉴와 같은 가격)
		local mw, mh = math.min(len - 0.8, 6.4), 3.7
		local mc = bc * CF(0, 6.2, 0.04)
		K:plate("FoodMenuFrame", mw + 0.18, mh + 0.18, 0.16, mc, Look.blackMetal)
		K:plate("FoodMenuFace", mw, mh, 0.18, mc, lk(rgb(20, 20, 24)))
		K:text("FoodMenuTitle", mw * 0.9, 0.62, mc * CF(0, mh / 2 - 0.42, 0.185), "광안 PC방 먹거리", { fg = C.amber, glow = 1.6, font = F.GothamBlack })
		K:plate("FoodMenuRule", mw * 0.9, 0.04, 0.19, mc * CF(0, mh / 2 - 0.8, 0), neon(C.amber))
		local items = {
			{ "컵라면", "3,500원", "ramen" },
			{ "짜파게티", "4,000원", "jjapa" },
			{ "핫도그", "2,500원", "hotdog" },
			{ "탄산음료", "1,500원", "soda" },
		}
		local tw = mw / 4
		for i, it in items do
			local u = -mw / 2 + tw * (i - 0.5)
			local tc = mc * CF(u, 0.1, 0.18)
			-- 음식 '사진' (색 블록 그림)
			K:plate("FoodPhotoBg", tw - 0.22, 1.5, 0.012, tc * CF(0, 0.35, 0), lk(rgb(250, 238, 214)))
			local k3 = it[3]
			if k3 == "ramen" then
				K:plate("FoodBowl", 1.0, 0.5, 0.02, tc * CF(0, 0.05, 0.012), lk(rgb(200, 40, 36)))
				K:plate("FoodSoup", 1.1, 0.16, 0.024, tc * CF(0, 0.32, 0.012), lk(rgb(220, 90, 40)))
				K:plate("FoodNoodle", 0.7, 0.12, 0.026, tc * CF(0, 0.4, 0.012), lk(rgb(246, 214, 120)))
				K:plate("FoodEgg", 0.24, 0.16, 0.028, tc * CF(0.2, 0.45, 0.012), lk(rgb(255, 236, 160)))
			elseif k3 == "jjapa" then
				K:plate("FoodBowl", 1.1, 0.4, 0.02, tc * CF(0, 0.05, 0.012), lk(rgb(240, 240, 236)))
				K:plate("FoodSauce", 0.95, 0.38, 0.024, tc * CF(0, 0.38, 0.012), lk(rgb(50, 30, 18)))
				K:plate("FoodCucumber", 0.3, 0.06, 0.028, tc * CF(0.1, 0.55, 0.012) * ANG(0, 0, 0.3), lk(rgb(90, 160, 60)))
			elseif k3 == "hotdog" then
				K:plate("FoodBun", 1.2, 0.34, 0.02, tc * CF(0, 0.3, 0.012) * ANG(0, 0, 0.2), lk(rgb(214, 150, 70)))
				K:plate("FoodSausage", 1.0, 0.16, 0.024, tc * CF(0, 0.36, 0.012) * ANG(0, 0, 0.2), lk(rgb(170, 60, 40)))
				K:plate("FoodKetchup", 0.8, 0.04, 0.028, tc * CF(0, 0.42, 0.012) * ANG(0, 0, 0.2), lk(rgb(220, 30, 30)))
				K:plate("FoodMustard", 0.7, 0.03, 0.03, tc * CF(0.02, 0.38, 0.012) * ANG(0, 0, 0.16), lk(rgb(240, 200, 30)))
			else
				K:plate("FoodCup", 0.55, 0.95, 0.02, tc * CF(0, 0.3, 0.012), lk(rgb(200, 30, 40)))
				K:plate("FoodCupLid", 0.62, 0.08, 0.024, tc * CF(0, 0.8, 0.012), lk(rgb(240, 240, 240)))
				K:plate("FoodStraw", 0.06, 0.5, 0.026, tc * CF(0.1, 1.0, 0.012) * ANG(0, 0, -0.2), lk(rgb(30, 30, 30)))
			end
			K:text("FoodName", tw - 0.25, 0.42, tc * CF(0, -0.75, 0.01), it[1], { fg = WHITE, glow = 1.4, font = F.GothamBold })
			K:text("FoodPrice", tw - 0.4, 0.38, tc * CF(0, -1.18, 0.01), it[2], { fg = C.amber, glow = 1.5, font = F.GothamBlack })
		end
		K:text("FoodMenuFoot", mw * 0.9, 0.3, mc * CF(0, -mh / 2 + 0.22, 0.185), "모니터 하단 메뉴 → 음식 주문 · 자리로 가져다 드려요", { fg = rgb(200, 200, 210), glow = 1.1, font = F.GothamMedium })
	end)

	-- 조리대 위: 맵의 상자 조리기 · 냄비 · 라면 박스 숨기고 다시
	for _, nm in { "RamenCooker", "CookerDisplay", "RamenPot", "RamenStock" } do
		for _, r in recs(V, nm) do
			hide(K, r)
		end
	end
	local zc = (cmn.Z + cmx.Z) / 2
	local zf = cmx.Z
	K:free(function()
		-- 2구 자동 라면 조리기 (스테인리스 몸체 + 인덕션 + 냄비 + 타이머)
		local ck = CF(24.9, top, zc)
		local bw, bd, bh = 2.6, cmx.Z - cmn.Z - 0.15, 1.15
		K:box("CookerBody", V3(bw, bh, bd), ck * CF(0, bh / 2, 0), Look.steel)
		K:box("CookerTop", V3(bw - 0.06, 0.05, bd - 0.06), ck * CF(0, bh + 0.025, 0), lk(rgb(16, 16, 18), M.Glass, { r = 0.2 }))
		local fp = faceCF(V3(24.9, top, zf - 0.07), V3(0, 0, 1))
		K:plate("CookerPanel", bw - 0.2, 0.6, 0.03, fp * CF(0, 0.55, 0), lk(rgb(20, 20, 22)))
		for i, sx in { -0.62, 0.62 } do
			local _, lab = K:text("CookerTimer", 0.6, 0.28, fp * CF(sx - 0.12, 0.6, 0.035), if i == 1 then "03:30" else "02:10", { fg = rgb(255, 50, 40), bg = rgb(30, 6, 6), glow = 2, font = F.RobotoMono, d = 0.02 })
			P.timers = P.timers or {}
			table.insert(P.timers, { l = lab, s = if i == 1 then 210 else 130 })
			wdisc(K, "CookerBtn", 0.16, 0.03, fp * CF(sx + 0.32, 0.6, 0.03), lk(rgb(220, 220, 220)))
			wdisc(K, "CookerBtnLED", 0.07, 0.035, fp * CF(sx + 0.32, 0.6, 0.03), neon(if i == 1 then C.green else C.amber))
		end
		K:text("CookerLabel", 1.6, 0.16, fp * CF(0, 0.15, 0.03), "자동 라면 조리기", { fg = rgb(220, 220, 220), font = F.GothamBold, d = 0.01 })
		for i, sx in { -0.65, 0.65 } do
			local pc = ck * CF(sx, bh + 0.05, 0)
			K:disc("InductionRing", 0.95, 0.012, pc * CF(0, 0.006, 0), neon(rgb(255, 60, 40), 0.55))
			K:vcyl("RamenPotBody", 0.42, 0.86, pc * CF(0, 0.23, 0), Look.brushed)
			K:vcyl("RamenPotRim", 0.04, 0.9, pc * CF(0, 0.44, 0), Look.steel)
			K:bar("RamenPotHandle", (pc * CF(0.45, 0.36, 0)).Position, (pc * CF(0.9, 0.38, 0)).Position, 0.08, 0.06, Look.black)
			if i == 1 then
				K:disc("RamenSoup", 0.8, 0.02, pc * CF(0, 0.4, 0), lk(rgb(214, 80, 34)))
				K:ell("RamenNoodle", V3(0.5, 0.06, 0.42), pc * CF(-0.05, 0.415, 0.02), lk(rgb(246, 210, 120)))
				K:disc("RamenEgg", 0.2, 0.03, pc * CF(0.18, 0.42, -0.1), lk(rgb(255, 230, 150)))
				K:box("RamenScallion", V3(0.16, 0.02, 0.05), pc * CF(-0.2, 0.425, -0.15), lk(rgb(80, 160, 60)))
				-- 김 (애니메이션)
				P.steam = P.steam or {}
				for j = 1, 3 do
					local s = K:ell("RamenSteam", V3(0.34, 0.5, 0.34), pc * CF((j - 2) * 0.12, 0.8 + j * 0.25, 0), { c = rgb(240, 240, 240), m = M.SmoothPlastic, t = 0.75 })
					table.insert(P.steam, { p = s, cf = s.CFrame, k = j })
				end
			else
				K:disc("RamenPotLid", 0.88, 0.04, pc * CF(0, 0.47, 0), Look.steel)
				K:vcyl("RamenPotKnob", 0.08, 0.16, pc * CF(0, 0.53, 0), Look.black)
			end
		end
		-- 컵라면 박스 + 컵 (조리대 왼쪽 끝)
		local bx = CF(x0 + 0.75, top, zc)
		K:box("NoodleCarton", V3(1.1, 0.8, bd * 0.9), bx * CF(0, 0.4, 0), Look.kraft)
		K:plate("NoodleCartonPrint", 0.8, 0.3, 0.01, faceCF((bx * V3(0, 0.45, bd * 0.45)), V3(0, 0, 1)), lk(rgb(200, 30, 36)))
		for j = 0, 2 do
			cupNoodle(K, bx * CF(-0.2 + (j % 2) * 0.38, 0.8 + 0.0, -0.05 + j * 0.05), j + 1)
		end
		-- 온수기 (맵 HotWater 는 그대로) 앞에 물받이 + 경고
		for _, r in recs(V, "HotWater") do
			local hmn, hmx, hc = mb(K, r)
			K:box("HotWaterTray", V3(1.0, 0.06, 0.5), CF(hc.X, top + 0.03, hmx.Z + 0.22), Look.steel)
			K:text("HotWaterWarn", 0.9, 0.3, faceCF(V3(hc.X, hmx.Y - 0.5, hmx.Z + 0.005), V3(0, 0, 1)), "뜨거운 물 주의", { fg = WHITE, bg = rgb(200, 30, 30), font = F.GothamBold, d = 0.01 })
		end
	end)
	-- 칸막이 주방 쪽: 스테인리스 선반 (전자레인지 · 용기 · 소스) + 아래 작업등
	K:free(function()
		local sy = 6.95
		local sh = faceCF(V3(cx, sy, zW), V3(0, 0, 1))
		local slen = len - 0.6
		K:box("KitchenShelf", V3(slen, 0.08, 1.0), sh * CF(0, 0, 0.5), Look.steel)
		for _, sx in { -1, 1 } do
			K:bar("KitchenShelfBracket", (sh * CF(sx * (slen / 2 - 0.4), -0.6, 0.02)).Position, (sh * CF(sx * (slen / 2 - 0.4), -0.05, 0.8)).Position, 0.06, 0.06, Look.steel)
		end
		local task = K:plate("KitchenTaskLED", slen - 0.4, 0.05, 0.03, sh * CF(0, -0.07, 0.75) * ANG(-PI / 2, 0, 0), Look.lampNeutral)
		K:light(task, "SurfaceLight", { Face = Enum.NormalId.Back, Range = 7, Brightness = 0.7, Angle = 120, Color = Look.neutralLight })
		local sx0 = -slen / 2
		-- 전자레인지
		local mw = sh * CF(sx0 + 1.1, 0.04, 0.5)
		K:box("Microwave", V3(1.8, 1.05, 0.9), mw * CF(0, 0.525, 0), lk(rgb(232, 232, 228)))
		K:plate("MicrowaveDoor", 1.2, 0.85, 0.02, faceCF((mw * V3(-0.22, 0.525, 0.45)), V3(0, 0, 1)), lk(rgb(30, 32, 36), M.Glass, { r = 0.15 }))
		K:plate("MicrowavePanel", 0.4, 0.85, 0.02, faceCF((mw * V3(0.62, 0.525, 0.45)), V3(0, 0, 1)), lk(rgb(60, 60, 64)))
		K:text("MicrowaveLCD", 0.3, 0.14, faceCF((mw * V3(0.62, 0.8, 0.475)), V3(0, 0, 1)), "0:45", { fg = C.green, bg = rgb(10, 20, 10), glow = 1.6, font = F.RobotoMono, d = 0.01 })
		-- 일회용 용기 · 접시 탑 · 소스
		local ux = sx0 + 2.4
		for j = 0, 1 do
			K:vcyl("BowlStack", 0.7, 0.62, sh * CF(ux + j * 0.7, 0.04 + 0.35, 0.45), Look.white)
		end
		K:vcyl("Ketchup", 0.55, 0.24, sh * CF(ux + 1.55, 0.04 + 0.275, 0.4), lk(rgb(210, 30, 30)))
		K:vcyl("KetchupCap", 0.12, 0.12, sh * CF(ux + 1.55, 0.04 + 0.61, 0.4), Look.white)
		K:vcyl("Mustard", 0.55, 0.24, sh * CF(ux + 1.85, 0.04 + 0.275, 0.4), lk(rgb(240, 196, 30)))
		K:vcyl("MustardCap", 0.12, 0.12, sh * CF(ux + 1.85, 0.04 + 0.61, 0.4), lk(rgb(200, 30, 30)))
		for j = 0, 3 do
			K:box("TrayStack", V3(1.1, 0.04, 0.8), sh * CF(ux + 2.8, 0.06 + j * 0.05, 0.5), lk(rgb(30, 30, 34)))
		end
		-- 주문 현황 모니터 (애니메이션)
		local oc = faceCF(V3(cx - 0.9, 9.1, zW + 0.04), V3(0, 0, 1))
		K:plate("OrderScreenBody", 3.3, 1.9, 0.1, oc, Look.black)
		local scr = K:plate("OrderScreen", 3.12, 1.72, 0.02, oc * CF(0, 0, 0.1), lk(rgb(14, 18, 30)))
		local _, ol = K:text("OrderScreenText", 3.0, 1.6, oc * CF(0, 0, 0.125), "주문 현황\n조리중  17번 컵라면\n완료  05번 짜파게티", { fg = WHITE, glow = 1.4, font = F.GothamBold, align = "Left" })
		P.orderLabel = ol
		P.orderScreen = scr
		-- 등록증 액자 2 (사업자등록증 · 인터넷컴퓨터게임시설제공업 등록증)
		local lc = faceCF(V3(xr - 1.0, 9.1, zW + 0.02), V3(0, 0, 1))
		Props.frame(K, lc * CF(-0.55, 0, 0), 0.95, 1.3, { frame = Look.goldMetal, text = "사업자등록증\n\n광안 PC방\n\n국세청", fg = rgb(40, 40, 40), border = 0.05, depth = 0.05 })
		Props.frame(K, lc * CF(0.55, 0, 0), 0.95, 1.3, { frame = Look.goldMetal, text = "인터넷컴퓨터\n게임시설제공업\n등록증\n\n부산 수영구청", fg = rgb(40, 40, 40), border = 0.05, depth = 0.05 })
	end)
	-- 직원 바닥 매트 (높이 0.03, 동선 keep 과 상관없음)
	K:free(function()
		local ctr = recs(V, "CounterBody")[1]
		if ctr then
			local _, kmx = mb(K, ctr)
			K:box("StaffMat", V3(3.2, 0.03, 11.0), CF(kmx.X + 1.8, 0.015, -1.2), lk(rgb(36, 36, 38), M.Rubber))
			K:box("StaffMatEdge", V3(3.3, 0.02, 11.1), CF(kmx.X + 1.8, 0.01, -1.2), lk(rgb(200, 160, 30), M.Rubber))
		end
	end)
end

-- 음료 냉장고 · 과자 선반 (맵 상자 음료/과자 숨기고 라벨 · 뚜껑 있는 상품으로)
local function frontStock(K: any, V: any)
	local P = K.pc
	-- 냉장고 음료
	local bottles = {}
	for _, r in recs(V, "Bottle") do
		local mn, mx, c = mb(K, r)
		if c.X > 24 then
			table.insert(bottles, { r = r, mn = mn, mx = mx, c = c })
		end
	end
	table.sort(bottles, function(a, b)
		if math.abs(a.mn.Y - b.mn.Y) > 0.3 then
			return a.mn.Y < b.mn.Y
		end
		return a.c.Z < b.c.Z
	end)
	K:free(function()
		for i, b in bottles do
			hide(K, b.r)
			local shelfI = math.floor((b.mn.Y - 0.5) / 1.5)
			local kind = ({ 6, 1, 3, 5 })[(shelfI % 4) + 1]
			if (i % 5) == 0 then
				kind = ({ 2, 2, 4, 7 })[(shelfI % 4) + 1]
			end
			drink(K, CF(b.c.X + 0.02, b.mn.Y + 0.01, b.c.Z), kind, 1.15)
		end
		-- 냉장고 상단 광고판
		for _, r in recs(V, "Body") do
			local mn, mx, c = mb(K, r)
			if c.X > 24 and mx.Y > 7 and r.part.Parent and r.part.Parent.Name == "Fridge" then
				lightbox(K, faceCF(V3(mn.X - 0.01, (mn.Y + mx.Y) / 2, c.Z), V3(-1, 0, 0)), mx.Z - mn.Z - 0.3, mx.Y - mn.Y - 0.2, "COLD DRINKS · 음료 1,500원~", WHITE, rgb(190, 24, 34), nil, { glow = 1.6 })
			end
		end
	end)
	-- 과자 · 컵라면 선반
	local boards = {}
	for _, r in recs(V, "Board") do
		local mn, mx = mb(K, r)
		if mn.X > 26 then
			table.insert(boards, { mn = mn, mx = mx })
		end
	end
	table.sort(boards, function(a, b)
		return a.mn.Y < b.mn.Y
	end)
	for _, r in recs(V, "Product") do
		local _, _, c = mb(K, r)
		if c.X > 26 then
			hide(K, r)
		end
	end
	K:free(function()
		for bi, b in boards do
			local y = b.mx.Y
			local fx = b.mn.X + 0.55 -- 앞쪽 줄 가운데 x
			local z0, z1 = b.mn.Z + 0.1, b.mx.Z - 0.1
			local len = z1 - z0
			if bi == 1 then
				local n = math.floor(len / 0.88)
				for j = 1, n do
					local z = z0 + len * (j - 0.5) / n
					cupNoodle(K, CF(fx, y, z), 4 + (j % 3), true)
					cupNoodle(K, CF(fx, y + 0.43, z), 4 + (j % 3), true)
				end
			elseif bi == 2 then
				local n = math.floor(len / 0.66)
				for j = 1, n do
					cupNoodle(K, CF(fx, y, z0 + len * (j - 0.5) / n), j)
				end
			elseif bi == 3 then
				local bags = { rgb(220, 40, 40), rgb(40, 110, 220), rgb(250, 200, 40), rgb(240, 130, 30), rgb(200, 160, 60), rgb(150, 30, 40) }
				local n = math.floor(len / 1.02)
				for j = 1, n do
					local z = z0 + len * (j - 0.5) / n
					local c = bags[(j - 1) % #bags + 1]
					if j == n then
						-- 프링글스 통
						K:vcyl("ChipTube", 1.1, 0.42, CF(fx, y + 0.55, z - 0.2), lk(rgb(200, 30, 30)))
						K:vcyl("ChipTube", 1.1, 0.42, CF(fx, y + 0.55, z + 0.25), lk(rgb(40, 150, 60)))
						K:vcyl("ChipTubeLid", 0.06, 0.44, CF(fx, y + 1.13, z - 0.2), Look.of(240, 240, 240, M.Plastic))
					else
						local bag = CF(fx + 0.05, y + 0.58, z) * ANG(0, 0, math.rad(-8))
						K:box("SnackBag", V3(0.34, 1.12, 0.9), bag, lk(c, M.Foil))
						K:box("SnackBagCrimp", V3(0.36, 0.08, 0.92), bag * CF(0, 0.56, 0), lk(dk(c, 0.2), M.Foil))
						K:plate("SnackBagWindow", 0.5, 0.32, 0.01, faceCF((bag * V3(-0.17, -0.1, 0)), V3(-1, 0, 0)), lk(rgb(250, 240, 200)))
					end
				end
			elseif bi == 4 then
				local boxes = { rgb(200, 30, 40), rgb(110, 50, 140), rgb(220, 60, 50), rgb(250, 200, 60), rgb(30, 120, 200) }
				local n = math.floor(len / 0.95)
				for j = 1, n do
					local z = z0 + len * (j - 0.5) / n
					local c = boxes[(j - 1) % #boxes + 1]
					local h = 0.55 + rnd(17, j) * 0.3
					K:box("SnackBox", V3(0.7, h, 0.85), CF(fx + 0.1, y + h / 2, z), lk(c))
					K:plate("SnackBoxLabel", 0.55, h * 0.36, 0.01, faceCF(V3(fx - 0.25, y + h * 0.55, z), V3(-1, 0, 0)), lk(lt(c, 0.7)))
				end
			end
		end
		-- 가격표 (PriceRail 앞면)
		local tags = { "사발면 1,800 · 육개장 1,800 · 튀김우동 1,800", "컵라면 1,500 · 짜장범벅 1,500 · 불닭 1,800", "과자 1,800~2,500 · 프링글스 3,500", "초코파이 · 몽쉘 1,000 · 젤리 1,200" }
		local rails = {}
		for _, r in recs(V, "PriceRail") do
			local mn, mx = mb(K, r)
			if mn.X > 26 then
				table.insert(rails, { mn = mn, mx = mx })
			end
		end
		table.sort(rails, function(a, b)
			return a.mn.Y < b.mn.Y
		end)
		for i, r in rails do
			K:text("PriceTag", (r.mx.Z - r.mn.Z) - 0.4, (r.mx.Y - r.mn.Y) * 0.9, faceCF(V3(r.mn.X - 0.01, (r.mn.Y + r.mx.Y) / 2, (r.mn.Z + r.mx.Z) / 2), V3(-1, 0, 0)), tags[i] or "", { fg = rgb(30, 30, 30), bg = rgb(255, 226, 60), font = F.GothamBold, d = 0.015 })
		end
	end)
end

-- 카운터: 앞면 클래딩 (검정 유광 + RGB 사선 + COUNTER 네온) · 끝면 요금 라이트박스 · 상판 위 POS · 좌석 현황 · 단말기
local function frontCounter(K: any, V: any)
	local P = K.pc
	local body = recs(V, "CounterBody")[1]
	local topR = recs(V, "CounterTop")[1]
	if not body or not topR then
		return
	end
	local bmn, bmx = mb(K, body)
	local tmn, tmx = mb(K, topR)
	for _, nm in { "CounterFrontSign", "CounterLED", "POSMonitor", "POSStand", "CardTerminal", "ReceiptPrinter", "CallBell" } do
		for _, r in recs(V, nm) do
			hide(K, r)
		end
	end
	local fx = bmn.X - 0.005
	local z0, z1 = bmn.Z, bmx.Z
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	local fh = tmn.Y - 0.02
	local fc = faceCF(V3(fx, 0, cz), V3(-1, 0, 0)) -- 손님 쪽 (+X = 보는 사람 오른쪽 = -Z 방향)
	K:free(function()
		local gloss = lk(rgb(16, 16, 20), M.SmoothPlastic, { r = 0.06 })
		K:plate("CounterKick", len, 0.4, 0.02, fc * CF(0, 0.2, 0), lk(rgb(12, 12, 14), M.Rubber))
		K:plate("CounterSkin", len, fh - 0.45, 0.06, fc * CF(0, 0.45 + (fh - 0.45) / 2, 0), gloss)
		local kick = K:plate("CounterKickLED", len - 0.1, 0.05, 0.08, fc * CF(0, 0.44, 0), neon(C.cyan))
		K:light(kick, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 5, Brightness = 0.8, Angle = 150, Color = C.cyan })
		table.insert(P.rgb, { p = kick, c = C.cyan, x = 0, z = 0 })
		K:plate("CounterTopLED", len - 0.2, 0.05, 0.04, fc * CF(0, fh - 0.05, 0.02), neon(C.magenta))
		-- RGB 사선 (양 끝)
		for _, side in { -1, 1 } do
			for j = 0, 2 do
				local u = side * (len / 2 - 1.0 - j * 0.42)
				local c = if j == 1 then C.magenta else C.cyan
				local p = K:plate("CounterSlash", 0.09, 2.2, 0.075, fc * CF(u, 0.45 + (fh - 0.45) / 2, 0.0) * ANG(0, 0, math.rad(side * 32)), neon(c))
				table.insert(P.rgb, { p = p, c = c, x = 0, z = 0 })
			end
		end
		-- COUNTER 네온 + 부제 + PC 배지
		K:text("CounterNeon", 4.6, 0.95, fc * CF(0.4, 2.3, 0.07), "COUNTER", { fg = C.cyan, glow = 2.2, font = F.Michroma })
		K:text("CounterSub", 5.6, 0.42, fc * CF(0.4, 1.45, 0.07), "회원 충전 · 음식 주문 · 분실물 문의", { fg = rgb(230, 230, 240), glow = 1.3, font = F.GothamBold })
		K:panel("CounterBadge", 1.0, 1.0, 0.05, 0.18, fc * CF(-2.6, 2.0, 0.06), neon(C.magenta))
		K:text("CounterBadgeText", 0.8, 0.6, fc * CF(-2.6, 2.0, 0.115), "PC", { fg = WHITE, font = F.GothamBlack })
		-- 끝면 (입구 쪽 +Z): 요금 라이트박스
		local ec = faceCF(V3((bmn.X + bmx.X) / 2, 0, z1 + 0.005), V3(0, 0, 1))
		local ew = bmx.X - bmn.X
		K:plate("CounterEndSkin", ew, fh, 0.05, ec * CF(0, fh / 2, 0), gloss)
		lightbox(K, ec * CF(0, 1.95, 0.05), ew - 0.5, 2.0, "1시간 1,000원\n회원 900원 · 야간 정액 5,000원", WHITE, rgb(20, 20, 26), C.cyan, { th = 0.75, font = F.GothamBold })
		-- 끝면 (홀 쪽 -Z)
		local bc2 = faceCF(V3((bmn.X + bmx.X) / 2, 0, z0 - 0.005), V3(0, 0, -1))
		K:plate("CounterEndSkin", ew, fh, 0.05, bc2 * CF(0, fh / 2, 0), gloss)
		K:plate("CounterEndLED", 0.06, fh - 0.6, 0.07, bc2 * CF(-ew / 2 + 0.2, fh / 2, 0), neon(C.magenta))
		K:text("CounterEndText", ew - 0.8, 0.5, bc2 * CF(0.1, fh - 0.7, 0.06), "COUNTER >", { fg = C.magenta, glow = 1.6, font = F.Michroma })
		-- 상판 앞 모서리 크롬
		K:box("CounterEdgeTrim", V3(0.04, 0.12, tmx.Z - tmn.Z), CF(tmn.X - 0.02, tmx.Y - 0.08, (tmn.Z + tmx.Z) / 2), Look.chrome)
	end)
	-- 상판 위 (픽업 자리 z < -5.6 근처는 비움)
	local ty = tmx.Y
	K:free(function()
		-- 손님용 좌석 현황 디스플레이 (손님 쪽 -X)
		local dp = CF(19.6, ty, 0.6)
		K:disc("SeatDispBase", 0.8, 0.06, dp * CF(0, 0.03, 0), Look.blackMetal)
		K:vcyl("SeatDispNeck", 0.9, 0.12, dp * CF(0, 0.5, 0), Look.blackMetal)
		local sc = faceCF((dp * V3(-0.08, 1.55, 0)), V3(-1, 0, 0)) * ANG(math.rad(-8), 0, 0)
		K:plate("SeatDispBezel", 2.0, 1.25, 0.08, sc, Look.black)
		K:plate("SeatDispScreen", 1.88, 1.13, 0.02, sc * CF(0, 0, 0.08), lk(rgb(10, 16, 30)))
		local _, sl = K:text("SeatDispText", 1.8, 1.05, sc * CF(0, 0, 0.105), "좌석 현황\n사용 0 · 빈자리 48", { fg = WHITE, glow = 1.6, font = F.GothamBold })
		P.seatLabels = P.seatLabels or {}
		table.insert(P.seatLabels, { l = sl, fmt = "좌석 현황\n사용 %d · 빈자리 %d" })
		-- 직원용 POS (직원 쪽 +X)
		local pp = CF(21.5, ty, -0.6)
		K:box("POSBase", V3(0.9, 0.1, 0.8), pp * CF(0, 0.05, 0), Look.blackMetal)
		K:bar("POSArm", (pp * CF(0, 0.1, 0)).Position, (pp * CF(-0.15, 0.9, 0)).Position, 0.16, 0.1, Look.blackMetal)
		local pc = faceCF((pp * V3(-0.15, 1.2, 0)), V3(1, 0, 0)) * ANG(math.rad(-14), 0, 0)
		K:plate("POSBezel", 1.7, 1.15, 0.08, pc, Look.black)
		K:plate("POSScreen", 1.58, 1.03, 0.02, pc * CF(0, 0, 0.08), lk(rgb(16, 22, 40)))
		local cols = { C.blue, C.green, C.amber, C.magenta, C.purple, C.cyan }
		for i = 0, 5 do
			local gx, gy = (i % 3) - 1, if i < 3 then 0.18 else -0.25
			K:plate("POSTile", 0.44, 0.34, 0.012, pc * CF(gx * 0.5, gy, 0.1), neon(dk(cols[i + 1], 0.35)))
		end
		K:text("POSHeader", 1.5, 0.2, pc * CF(0, 0.42, 0.11), "광안 PC방 POS · 좌석 · 주문 · 충전", { fg = WHITE, glow = 1.3, font = F.GothamBold })
		-- 카드 단말기 · 영수증 프린터 · 벨 · 아크릴 안내 · 무료 충전 · 소품
		Props.cardTerminal(K, facing(V3(19.25, ty, -2.7), V3(-1, 0, 0)))
		Props.receiptPrinter(K, facing(V3(21.4, ty, -3.6), V3(1, 0, 0)))
		Props.bell(K, CF(19.0, ty, 3.6))
		Props.menuStand(K, facing(V3(19.0, ty, 4.8), V3(-1, 0, 0)), "신규회원\n1시간 무료\n\n휴대폰 인증")
		local cb = CF(19.25, ty, -4.55)
		K:box("ChargeBox", V3(0.62, 0.36, 0.7), cb * CF(0, 0.18, 0), lk(rgb(24, 24, 28)))
		K:text("ChargeBoxLabel", 0.58, 0.2, faceCF((cb * V3(-0.315, 0.2, 0)), V3(-1, 0, 0)), "무료 충전", { fg = C.green, glow = 1.4, font = F.GothamBold, d = 0.01 })
		for j, c in { rgb(240, 240, 240), rgb(30, 30, 30), rgb(240, 240, 240) } do
			local a = cb * V3(-0.2, 0.36, -0.25 + j * 0.13)
			K:seg("ChargeCable", a, a + V3(-0.35, 0.02, 0.02 * j), 0.05, lk(c))
			K:seg("ChargeCable", a + V3(-0.35, 0.02, 0.02 * j), V3(tmn.X - 0.05, ty - 0.7 - j * 0.15, a.Z), 0.05, lk(c))
		end
		local gp = CF(19.3, ty, 2.25)
		K:box("GumTray", V3(0.7, 0.12, 0.9), gp * CF(0, 0.06, 0), Look.acrylicWhite)
		for j = 0, 3 do
			K:box("GumPack", V3(0.14, 0.32, 0.18), gp * CF(-0.15 + (j % 2) * 0.3, 0.28, -0.25 + j * 0.16), lk(({ rgb(30, 160, 80), rgb(40, 110, 220), rgb(220, 50, 60), rgb(250, 200, 40) })[j + 1]))
		end
		K:text("GumTag", 0.6, 0.16, faceCF((gp * V3(-0.36, 0.16, 0)), V3(-1, 0, 0)), "껌 · 사탕 1,000원", { fg = rgb(30, 30, 30), bg = rgb(255, 230, 70), d = 0.01 })
	end)
end

-- 키오스크 (맵 상자 키오스크 숨기고 같은 자리에 세로형 터치 키오스크)
local function frontKiosk(K: any, V: any)
	local P = K.pc
	local base = recs(V, "KioskBase")[1]
	local head = recs(V, "KioskHead")[1]
	if not base then
		return
	end
	local mn, mx, c = mb(K, base)
	for _, nm in { "KioskBase", "KioskPedestal", "KioskHead", "KioskCardSlot" } do
		for _, r in recs(V, nm) do
			hide(K, r)
		end
	end
	-- 앞 방향: 카드 슬롯 쪽 (없으면 +Z)
	local n = V3(0, 0, 1)
	local slot = recs(V, "KioskCardSlot")[1]
	if slot and head then
		local _, _, sc = mb(K, slot)
		local _, _, hc = mb(K, head)
		n = if sc.Z >= hc.Z then V3(0, 0, 1) else V3(0, 0, -1)
	end
	local pc = facing(V3(c.X, 0, c.Z), n)
	local white = lk(rgb(240, 240, 242))
	K:free(function()
		K:slab("KioskFoot", 2.3, 1.6, 0.14, 0.3, pc * CF(0, 0.07, 0), lk(rgb(60, 62, 68), M.Metal))
		K:rbox("KioskBody", V3(3.3, 1.7, 0.9), 0.2, pc * CF(0, 0.14 + 1.65, 0) * ANG(0, 0, PI / 2), white)
		local fp = pc * CF(0, 0, 0.455)
		K:plate("KioskInset", 1.3, 2.4, 0.02, fp * CF(0, 1.75, 0), lk(rgb(26, 26, 30)))
		K:plate("KioskReceipt", 0.7, 0.06, 0.03, fp * CF(0, 2.6, 0.02), lk(rgb(8, 8, 8)))
		K:plate("KioskBill", 0.8, 0.3, 0.05, fp * CF(0, 2.1, 0.02), lk(rgb(50, 52, 58)))
		K:plate("KioskBillLED", 0.5, 0.04, 0.06, fp * CF(0, 2.2, 0.02), neon(C.green))
		K:plate("KioskQR", 0.42, 0.3, 0.05, fp * CF(-0.3, 1.5, 0.02), lk(rgb(10, 10, 12), M.Glass))
		K:plate("KioskQRWin", 0.3, 0.06, 0.06, fp * CF(-0.3, 1.5, 0.02), neon(C.red, 0.3))
		K:plate("KioskNFC", 0.42, 0.42, 0.05, fp * CF(0.32, 1.5, 0.02), lk(rgb(60, 60, 66)))
		K:text("KioskNFCText", 0.36, 0.14, fp * CF(0.32, 1.5, 0.075), "))) 터치", { fg = C.cyan, glow = 1.2, d = 0.01 })
		K:plate("KioskCash", 0.9, 0.08, 0.04, fp * CF(0, 0.9, 0.02), lk(rgb(8, 8, 8)))
		K:text("KioskCashLabel", 0.9, 0.18, fp * CF(0, 0.72, 0.03), "카드 · 현금 · QR", { fg = rgb(200, 200, 210), font = F.GothamBold, d = 0.01 })
		-- 카드 받침 선반
		K:box("KioskLedge", V3(1.6, 0.1, 0.5), pc * CF(0, 3.42, 0.55) * ANG(math.rad(-8), 0, 0), white)
		K:plate("KioskICSlot", 0.6, 0.05, 0.02, faceCF((pc * V3(0.35, 3.3, 0.81)), n), lk(rgb(8, 8, 8)))
		-- 화면 (기울어진 32인치 세로)
		local sc = pc * CF(0, 5.35, 0.2) * ANG(math.rad(-9), 0, 0)
		K:panel("KioskHeadShell", 2.4, 3.9, 0.36, 0.16, sc * CF(0, 0, -0.18), white)
		local scr = K:plate("KioskScreen", 2.1, 3.5, 0.02, sc * CF(0, 0, 0.18), lk(rgb(12, 20, 44)))
		K:plate("KioskScreenBar", 2.1, 0.5, 0.025, sc * CF(0, 1.5, 0.18), neon(dk(C.magenta, 0.25)))
		K:text("KioskScreenHead", 1.9, 0.38, sc * CF(0, 1.5, 0.21), "광안 PC방", { fg = WHITE, glow = 1.5, font = F.GothamBlack })
		local _, lab = K:text("KioskScreenText", 1.9, 2.7, sc * CF(0, -0.25, 0.205), "무인 요금 충전\n\n화면을 터치해 주세요", { fg = WHITE, glow = 1.4, font = F.GothamBold })
		K:light(scr, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 7, Brightness = 0.5, Angle = 120, Color = rgb(170, 190, 255) })
		-- 머리 간판
		K:box("KioskTop", V3(2.4, 0.5, 0.42), pc * CF(0, 7.55, 0.05), lk(rgb(20, 20, 24)))
		K:text("KioskTopText", 2.2, 0.38, faceCF((pc * V3(0, 7.55, 0.265)), n), "무인 요금 충전 KIOSK", { fg = C.cyan, glow = 1.8, font = F.GothamBlack })
		K:box("KioskTopLED", V3(2.4, 0.04, 0.44), pc * CF(0, 7.29, 0.05), neon(C.cyan))
		-- 옆면 마젠타 줄
		for _, sx in { -1, 1 } do
			K:box("KioskSideLED", V3(0.04, 2.9, 0.1), pc * CF(sx * 0.86, 1.85, 0.3), neon(C.magenta))
		end
		-- 안내 화면 순환 (프롬프트 없음: 카운터 주문 지점과 가까움)
		local pcs = pcModels(V)
		local pages = {
			{ "무인 요금 충전\n\n화면을 터치해 주세요", rgb(12, 20, 44) },
			{ "요금 안내\n\n1시간 1,000원\n회원 900원\n10시간 9,000원\n야간 정액 5,000원", rgb(18, 14, 40) },
			{ "좌석 현황\n\n빈자리 %d석 / %d석\n일반석 · FPS 존 · 프리미엄", rgb(10, 30, 36) },
			{ "신규 회원 가입\n\n휴대폰 인증 1분\n가입 즉시 1시간 무료", rgb(36, 12, 30) },
		}
		local last = -1
		Interact.anim(K, function(t)
			local i = math.floor(t / 5) % #pages + 1
			if i == last then
				return
			end
			last = i
			local pg = pages[i]
			if lab.Parent then
				if i == 3 then
					local tot = math.max(#pcs, 48)
					lab.Text = string.format(pg[1], tot - usedSeats(pcs), tot)
				else
					lab.Text = pg[1]
				end
			end
			if scr.Parent then
				scr.Color = pg[2]
			end
		end)
	end)
	K:reserve(V3(mn.X - 0.4, 0, mn.Z - 0.4), V3(mx.X + 0.4, 8, mx.Z + 0.4), "kiosk")
end

-- 셀프바 (정수기 · 얼음 · 수납장 앞면 · 국물 싱크 · 컵 디스펜서 · 안내 · SELF BAR 네온)
local function frontSelfBar(K: any, V: any)
	local P = K.pc
	local cab = recs(V, "SelfBarCabinet")[1]
	if not cab then
		return
	end
	local cmn, cmx = mb(K, cab)
	local fxC = cmx.X + 0.005
	K:free(function()
		-- 수납장 앞면: 문 2짝 + 손잡이 + 걸레받이 + 상판 모서리
		local cz = (cmn.Z + cmx.Z) / 2
		local dl = cmx.Z - cmn.Z
		local fc = faceCF(V3(fxC, 0, cz), V3(1, 0, 0))
		K:plate("SelfCabKick", dl, 0.35, 0.02, fc * CF(0, 0.175, 0), lk(rgb(30, 30, 32)))
		for _, side in { -1, 1 } do
			local u = side * dl / 4
			K:plate("SelfCabDoor", dl / 2 - 0.08, cmx.Y - 0.55, 0.04, fc * CF(u, 0.35 + (cmx.Y - 0.55) / 2, 0), lk(rgb(232, 228, 220)))
			K:plate("SelfCabHandle", 0.05, 0.8, 0.07, fc * CF(u - side * (dl / 4 - 0.25), cmx.Y - 0.8, 0.04), Look.brushed)
		end
		K:box("SelfCabEdge", V3(0.06, 0.08, dl), CF(cmx.X + 0.02, cmx.Y - 0.04, cz), Look.steel)
		-- 정수기 앞면
		for _, r in recs(V, "WaterPurifier") do
			local wmn, wmx, wc = mb(K, r)
			local pf = faceCF(V3(wmx.X + 0.005, 0, wc.Z), V3(1, 0, 0))
			local ww = wmx.Z - wmn.Z
			K:plate("PurifierPanel", ww - 0.2, 0.55, 0.03, pf * CF(0, wmx.Y - 0.55, 0), lk(rgb(24, 26, 30), M.Glass, { r = 0.15 }))
			for i, c in { C.blue, WHITE, C.red } do
				wdisc(K, "PurifierLED", 0.12, 0.035, pf * CF(-0.4 + (i - 1) * 0.4, wmx.Y - 0.47, 0.03), neon(c))
			end
			K:text("PurifierLabel", ww - 0.4, 0.16, pf * CF(0, wmx.Y - 0.68, 0.04), "냉수   정수   온수", { fg = rgb(220, 220, 230), glow = 1.1, font = F.GothamBold, d = 0.01 })
			K:plate("PurifierTapHousing", 1.0, 0.36, 0.26, pf * CF(0, wmn.Y + 1.45, 0), lk(rgb(40, 40, 44)))
			for _, sz in { -0.25, 0.25 } do
				K:vcyl("PurifierNozzle", 0.16, 0.08, CF(wmx.X + 0.18, wmn.Y + 1.2, wc.Z + sz), Look.chrome)
			end
			K:box("PurifierTray", V3(0.55, 0.06, 1.2), CF(wmx.X + 0.2, wmn.Y + 0.06, wc.Z), Look.steel)
			K:text("PurifierHot", 0.5, 0.2, pf * CF(0.55, wmn.Y + 1.85, 0.03), "온수 주의", { fg = WHITE, bg = rgb(200, 30, 30), font = F.GothamBold, d = 0.01 })
		end
		-- 제빙기 앞면
		for _, r in recs(V, "IceDispenser") do
			local imn, imx, ic = mb(K, r)
			local pf = faceCF(V3(imx.X + 0.005, 0, ic.Z), V3(1, 0, 0))
			K:plate("IcePanel", imx.Z - imn.Z - 0.2, 0.4, 0.03, pf * CF(0, imx.Y - 0.4, 0), lk(rgb(30, 60, 100)))
			K:text("IceLabel", 1.0, 0.22, pf * CF(0, imx.Y - 0.4, 0.035), "ICE · 얼음", { fg = WHITE, glow = 1.2, font = F.GothamBlack, d = 0.01 })
			K:plate("IceChute", 0.55, 0.45, 0.32, pf * CF(0, imn.Y + 1.0, 0), lk(rgb(40, 40, 44)))
			K:plate("IcePaddle", 0.4, 0.5, 0.06, pf * CF(0, imn.Y + 0.55, 0.12), Look.steel)
			K:box("IceTray", V3(0.5, 0.06, 1.0), CF(imx.X + 0.2, imn.Y + 0.06, ic.Z), Look.steel)
		end
		-- 분리수거장 위: 라면 국물 버리는 싱크
		for _, r in recs(V, "RecycleCabinet") do
			local rmn, rmx, rc = mb(K, r)
			local sy = rmx.Y
			local sw, sd = rmx.X - rmn.X - 0.3, rmx.Z - rmn.Z - 0.3
			local s0 = CF(rc.X, sy, rc.Z)
			K:box("SoupSinkRim", V3(sw, 0.08, 0.12), s0 * CF(0, 0.04, -sd / 2 + 0.06), Look.steel)
			K:box("SoupSinkRim", V3(sw, 0.08, 0.12), s0 * CF(0, 0.04, sd / 2 - 0.06), Look.steel)
			K:box("SoupSinkRim", V3(0.12, 0.08, sd), s0 * CF(-sw / 2 + 0.06, 0.04, 0), Look.steel)
			K:box("SoupSinkRim", V3(0.12, 0.08, sd), s0 * CF(sw / 2 - 0.06, 0.04, 0), Look.steel)
			K:box("SoupSinkBasin", V3(sw - 0.2, 0.03, sd - 0.2), s0 * CF(0, 0.02, 0), lk(rgb(60, 62, 66), M.Metal))
			K:box("SoupSinkMesh", V3(sw - 0.5, 0.02, sd - 0.5), s0 * CF(0, 0.05, 0), lk(rgb(150, 152, 156), M.DiamondPlate))
			K:disc("SoupSinkDrain", 0.3, 0.02, s0 * CF(0, 0.065, 0), lk(rgb(30, 30, 32), M.Metal))
		end
	end)
	-- 왼쪽 벽: 컵 디스펜서 2 · 작은 선반 (냅킨 · 물티슈) · 안내 · SELF BAR 네온
	local rec = recs(V, "RecycleCabinet")[1]
	local zA = if rec then (select(1, mb(K, rec))).Z else cmn.Z - 2
	K:free(function()
		-- 왼쪽 벽 u = -z
		for i, z in { zA + 0.45, zA + 1.05 } do
			local d = W(K, "left", -z, 5.3, 0)
			K:plate("CupTubeBracket", 0.5, 0.3, 0.12, d * CF(0, 0.85, 0), Look.steel)
			K:plate("CupTubeBracket", 0.5, 0.3, 0.12, d * CF(0, -0.85, 0), Look.steel)
			local p = d * V3(0, 0, 0.36)
			K:vcyl("CupTube", 2.0, 0.44, CF(p), { c = rgb(220, 232, 236), m = M.Glass, t = 0.55 })
			K:vcyl("CupStack", 1.6, 0.36, CF(p + V3(0, 0.1, 0)), Look.paper)
			K:vcyl("CupTubeCap", 0.1, 0.48, CF(p + V3(0, 1.0, 0)), Look.steel)
			K:vcyl("CupTubeMouth", 0.12, 0.48, CF(p - V3(0, 1.0, 0)), Look.steel)
		end
		local sd = W(K, "left", -(zA + 1.75), 4.6, 0)
		Props.shelf(K, sd, 0.9, { depth = 0.7, look = Look.steel, bracket = Look.steel, thick = 0.06 })
		local at = sd * CF(0, 0.03, 0.35)
		K:box("NapkinBox", V3(0.5, 0.36, 0.34), at * CF(0.12, 0.18, 0), lk(rgb(240, 238, 232)))
		K:box("NapkinTissue", V3(0.2, 0.1, 0.12), at * CF(0.12, 0.41, 0), Look.paper)
		K:box("WetTissue", V3(0.3, 0.22, 0.42), at * CF(-0.25, 0.11, 0), lk(rgb(60, 160, 220)))
		-- 수저통 (나무젓가락 · 포크)
		local ct = at * CF(0.12, 0.0, -0.05) * CF(0, 0, 0)
		local _ = ct
		local hc = (at * CF(-0.05, 0, 0.22)).Position
		K:vcyl("CutleryCup", 0.4, 0.26, CF(hc + V3(0, 0.2, 0)), Look.steel)
		for j = 0, 4 do
			local a2 = j * 1.26
			local tip = hc + V3(math.cos(a2) * 0.06, 0.62 + (j % 2) * 0.06, math.sin(a2) * 0.06)
			K:seg("Chopstick", hc + V3(math.cos(a2) * 0.04, 0.05, math.sin(a2) * 0.04), tip, 0.035, if j % 2 == 0 then Look.birch else Look.white)
		end
		notice(K, W(K, "left", -(zA + 1.0), 7.5, 0), 1.6, 1.3, "셀프바 이용 안내", "다 드신 컵라면은\n국물은 싱크에 · 용기는 분리수거\n감사합니다 :)", rgb(0, 150, 200))
		-- SELF BAR 네온 (맵 Sign_셀프바 위)
		local sb = recs(V, "Sign_셀프바 · 물 · 얼음")[1]
		local sz = if sb then (select(3, mb(K, sb))).Z else (cmn.Z + cmx.Z) / 2
		local nz = math.min(sz, 9.2 - 1.6)
		local np = Props.neonSign(K, W(K, "left", -nz, 8.85, 0.02), 3.0, 0.8, "SELF BAR", C.cyan, { font = F.GothamBlack })
		if np then
			table.insert(P.rgb, { p = np, c = C.cyan, x = 0, z = 0, text = true })
		end
	end)
end

-- 왼쪽 앞 (흡연실 앞 유리 따라): 캡슐 뽑기 · 음료 냉장고(문 열기) · 대기 벤치 · 게이밍 기어 진열장 · 화단 · 우산꽂이
local function frontLobby(K: any, V: any)
	local P = K.pc
	local zG = 3.0
	for _, r in recs(V, "SmokingRoomGlass") do
		local mn, mx = mb(K, r)
		if mx.X - mn.X > 3 and mn.Z > 0 then
			zG = math.max(zG, mx.Z)
		end
	end
	local z0 = zG + 0.12
	-- 캡슐 뽑기 3대
	for i = 0, 2 do
		local x = -25.4 + i * 1.3
		local pcf = facing(V3(x, 0, z0 + 0.6), V3(0, 0, 1))
		if spotN(K, pcf, V3(1.2, 4.8, 1.2), 0.02) then
			local cols = { C.magenta, C.cyan, C.amber }
			local col = cols[i + 1]
			K:box("GachaBase", V3(1.15, 2.2, 1.1), pcf * CF(0, 1.1, 0), lk(dk(col, 0.25)))
			K:box("GachaGlobe", V3(1.05, 1.5, 1.0), pcf * CF(0, 2.95, 0), glassL(rgb(230, 240, 245), 0.6))
			for j = 0, 7 do
				local a = j * 0.8
				K:ball("GachaCapsule", 0.3, pcf * CF(math.cos(a) * 0.3, 2.35 + (j % 3) * 0.28, math.sin(a) * 0.28), lk(({ rgb(240, 80, 80), rgb(80, 180, 240), rgb(250, 220, 60), rgb(120, 220, 120) })[(j % 4) + 1], M.Plastic))
			end
			K:box("GachaTop", V3(1.15, 0.5, 1.1), pcf * CF(0, 3.95, 0), lk(col))
			K:text("GachaTopText", 1.0, 0.36, pcf * CF(0, 3.95, 0.555), if i == 1 then "게임 캐릭터" else "랜덤 피규어", { fg = WHITE, glow = 1.4, font = F.GothamBlack, d = 0.01 })
			wdisc(K, "GachaKnob", 0.45, 0.12, pcf * CF(0, 1.45, 0.55), Look.chrome)
			K:plate("GachaChute", 0.45, 0.35, 0.08, pcf * CF(0, 0.7, 0.55), lk(rgb(30, 30, 34)))
			K:text("GachaPrice", 0.7, 0.22, pcf * CF(0, 1.95, 0.555), "1회 2,000원", { fg = WHITE, bg = rgb(30, 30, 34), d = 0.01 })
		end
	end
	-- 음료 쇼케이스 (문 열기)
	local fz = z0 + 1.15
	local fcf = facing(V3(-20.9, 0, fz), V3(0, 0, 1))
	if spotN(K, fcf * CF(0, 0, -0.05), V3(2.8, 6.7, 2.2), 0.02) then
		local out = Props.showcaseFridge(K, fcf, { doors = 1, doorW = 2.5, h = 6.6, d = 2.1, header = "핫식스 · 콜라 · 이온음료", headerBg = rgb(200, 28, 36), shelves = 5 })
		local d = out.doors[1]
		if d then
			local hinge: any = d:GetAttribute("Hinge")
			local handle = d:FindFirstChild("FridgeDoorHandle", true) :: BasePart?
			if typeof(hinge) == "Vector3" and promptOK(K, handle) then
				Interact.swing(K, d, hinge, YA, -math.rad(100), { object = "음료 냉장고", openText = "문 열기", closeText = "문 닫기" })
			end
		end
		K:text("FridgePay", 1.7, 0.75, faceCF(fcf * V3(1.405, 4.2, -0.05), V3(1, 0, 0)), "꺼낸 음료는\n카운터에서 계산", { fg = WHITE, bg = rgb(200, 28, 36), font = F.GothamBold, d = 0.02 })
	end
	-- 대기 벤치 (가죽 쿠션 + 아래 RGB)
	local bcf = facing(V3(-16.0, 0, z0 + 0.8), V3(0, 0, 1))
	if spotN(K, bcf, V3(5.6, 3.6, 1.6), 0.02) then
		K:box("BenchBase", V3(5.4, 1.1, 1.4), bcf * CF(0, 0.6, 0), lk(rgb(26, 26, 30)))
		local led = K:box("BenchLED", V3(5.3, 0.05, 1.3), bcf * CF(0, 0.06, 0), neon(C.purple))
		table.insert(P.rgb, { p = led, c = C.purple, x = 0, z = 0 })
		for i = 0, 2 do
			K:slab("BenchCushion", 1.75, 1.4, 0.32, 0.12, bcf * CF(-1.8 + i * 1.8, 1.31, 0.02), Look.leatherBlack)
			K:rbox("BenchBack", V3(1.75, 1.7, 0.32), 0.14, bcf * CF(-1.8 + i * 1.8, 2.35, -0.5) * ANG(math.rad(-8), 0, 0), Look.leatherBlack)
		end
		K:box("BenchBackFrame", V3(5.4, 1.9, 0.12), bcf * CF(0, 2.3, -0.72), lk(rgb(26, 26, 30)))
	end
	-- 게이밍 기어 진열장 (유리장 + 키보드 · 마우스 · 헤드셋)
	local gcf = facing(V3(-11.9, 0, z0 + 0.7), V3(0, 0, 1))
	if spotN(K, gcf, V3(2.4, 3.8, 1.4), 0.02) then
		K:box("GearCaseBase", V3(2.3, 1.2, 1.3), gcf * CF(0, 0.6, 0), lk(rgb(24, 24, 28)))
		K:box("GearCaseGlass", V3(2.3, 2.3, 1.3), gcf * CF(0, 2.35, 0), glassL(rgb(220, 234, 240), 0.75))
		K:box("GearCaseTop", V3(2.34, 0.1, 1.34), gcf * CF(0, 3.55, 0), lk(rgb(24, 24, 28)))
		K:box("GearShelf", V3(2.2, 0.04, 1.2), gcf * CF(0, 2.3, 0), glassL(nil, 0.5))
		local gl = K:box("GearCaseLight", V3(2.2, 0.04, 0.08), gcf * CF(0, 3.47, 0.5), Look.lampCool)
		-- 키보드 2 (RGB)
		for j = 0, 1 do
			local kc = gcf * CF(-0.4 + j * 0.0, 1.22 + j * 1.1, 0.1) * ANG(math.rad(10), 0, 0)
			K:box("GearKeyboard", V3(1.6, 0.08, 0.55), kc, lk(rgb(20, 20, 22)))
			K:box("GearKeyRGB", V3(1.5, 0.02, 0.45), kc * CF(0, 0.05, 0), neon(if j == 0 then C.cyan else C.magenta, 0.2))
		end
		K:ell("GearMouse", V3(0.24, 0.12, 0.38), gcf * CF(0.75, 1.28, 0.1), lk(rgb(30, 30, 34)))
		K:ell("GearMouse", V3(0.24, 0.12, 0.38), gcf * CF(0.75, 2.38, 0.1), lk(rgb(240, 240, 240)))
		-- 헤드셋 스탠드
		local hs = gcf * CF(0.65, 2.32, -0.25)
		K:vcyl("HeadsetStand", 0.7, 0.08, hs * CF(0, 0.35, 0), Look.blackMetal)
		K:ring("GearHeadsetBand", hs * CF(0, 0.75, 0), 0.3, 0.07, 6, lk(rgb(20, 20, 22)), 0, PI)
		for _, sx in { -1, 1 } do
			K:ell("GearHeadsetCup", V3(0.14, 0.38, 0.32), hs * CF(sx * 0.3, 0.7, 0), lk(rgb(30, 30, 34), M.Fabric))
		end
		K:text("GearCaseLabel", 2.1, 0.4, gcf * CF(0, 0.75, 0.655), "전 좌석 기계식 키보드 · 240Hz", { fg = C.cyan, glow = 1.5, font = F.GothamBold, d = 0.01 })
	end
	-- 앞 유리 아래 화단 (높이 1.6, 창 keep 아래)
	K:free(function()
		local zw = P.zf
		local wz = (V.z1 - 0.62)
		local x0, x1 = -25.4, 1.4
		local pl = CF((x0 + x1) / 2, 0, wz)
		K:box("WindowPlanter", V3(x1 - x0, 1.3, 0.8), pl * CF(0, 0.65, 0), lk(rgb(30, 30, 34)))
		K:box("WindowPlanterCap", V3(x1 - x0 + 0.08, 0.06, 0.88), pl * CF(0, 1.33, 0), Look.blackMetal)
		K:box("WindowPlanterGrass", V3(x1 - x0 - 0.1, 0.06, 0.7), pl * CF(0, 1.36, 0), Look.leafDark)
		local n = math.floor((x1 - x0) / 1.2)
		for i = 1, n do
			local x = x0 + (x1 - x0) * (i - 0.5) / n - (x0 + x1) / 2
			for j = 0, 2 do
				local a = j * 2.1 + i
				K:ell("PlanterLeaf", V3(0.16, 1.2 + (j % 2) * 0.4, 0.06), pl * CF(x + math.cos(a) * 0.12, 1.9 + (j % 2) * 0.2, math.sin(a) * 0.12) * ANG(0, a, math.rad(8)), if j % 2 == 0 then Look.leaf else Look.leafDark)
			end
		end
		local _ = zw
		K:reserve(V3(x0, 0, wz - 0.45), V3(x1, 3, wz + 0.45), "planter")
	end)
	-- 우산꽂이 (입구 왼쪽)
	local dxL = if V.door then V.door.x - (V.door.w or 8) / 2 - 2.6 else 2.0
	local ucf = CF(dxL, 0, V.z1 - 1.3)
	if spotN(K, ucf, V3(0.9, 2.8, 0.9), 0) then
		K:vcyl("UmbrellaStand", 1.6, 0.8, ucf * CF(0, 0.8, 0), Look.brushed)
		K:vcyl("UmbrellaStandRim", 0.06, 0.84, ucf * CF(0, 1.6, 0), Look.steel)
		for j, c in { rgb(30, 60, 120), rgb(20, 20, 22) } do
			local a = ucf * V3((j - 1.5) * 0.2, 0.2, 0.05)
			K:seg("UmbrellaShaft", a, a + V3(0.04 * j, 2.3, 0.0), 0.08, lk(c, M.Fabric))
			K:ring("UmbrellaHandle", CFrame.fromMatrix(a + V3(0.04 * j + 0.1, 2.35, 0), V3(1, 0, 0), YA, V3(0, 0, 1)), 0.1, 0.05, 4, Look.black, 0, PI)
		end
	end
end

-- 흡연실: 반투명 띠 · 자동 문 · 재떨이 · 스탠딩 선반 · 공기청정기(켜기/끄기) · 안내 · 열 감지기
local function frontSmoking(K: any, V: any)
	local P = K.pc
	local glass = recs(V, "SmokingRoomGlass")
	if #glass == 0 then
		return
	end
	-- 방 경계
	local rmn, rmx = V3(math.huge, 0, math.huge), V3(-math.huge, 0, -math.huge)
	for _, r in glass do
		local mn, mx = mb(K, r)
		rmn = rmn:Min(mn)
		rmx = rmx:Max(mx)
	end
	local rc = (rmn + rmx) / 2
	-- 1) 반투명 띠 (유리 바깥면, 높이 3.2..4.9) + 앞 띠에 글자
	K:free(function()
		for _, r in glass do
			local mn, mx, c = mb(K, r)
			local ex = mx - mn
			local n: Vector3
			local p: Vector3
			local w: number
			if ex.X > ex.Z then
				n = if c.Z > rc.Z then V3(0, 0, 1) else V3(0, 0, -1)
				p = V3(c.X, 4.05, if n.Z > 0 then mx.Z + 0.01 else mn.Z - 0.01)
				w = ex.X - 0.15
			else
				n = if c.X > rc.X then V3(1, 0, 0) else V3(-1, 0, 0)
				p = V3(if n.X > 0 then mx.X + 0.01 else mn.X - 0.01, 4.05, c.Z)
				w = ex.Z - 0.15
			end
			local d = faceCF(p, n)
			K:plate("FrostBand", w, 1.7, 0.01, d, { c = rgb(236, 240, 242), m = M.Glass, t = 0.3 })
			K:plate("FrostLine", w, 0.05, 0.014, d * CF(0, 0.95, 0), lk(rgb(200, 210, 214)))
			if ex.X > ex.Z and n.Z > 0 then
				K:text("FrostText", math.min(w - 0.4, 3.6), 0.5, d * CF(0, 0, 0.015), "SMOKING ROOM · 흡연실", { fg = rgb(60, 70, 76), font = F.GothamBlack, d = 0.005 })
			end
		end
	end)
	-- 2) 맵의 가짜 문(고정 유리 위에 겹친 판) 숨기고, 실제 열린 칸에 자동 유리문
	for _, r in recs(V, "SmokingRoomDoor") do
		hide(K, r)
	end
	for _, r in recs(V, "DoorHandle") do
		local _, _, c = mb(K, r)
		if c.X > rc.X + 5 and c.X < rmx.X + 0.6 and c.Z > rmn.Z and c.Z < rmx.Z then
			hide(K, r)
		end
	end
	-- 오른쪽(+X) 유리 줄에서 가장 넓은 틈 찾기
	local side = {}
	for _, r in glass do
		local mn, mx = mb(K, r)
		if mx.Z - mn.Z > mx.X - mn.X and mn.X > rc.X then
			table.insert(side, { mn.Z, mx.Z })
		end
	end
	table.sort(side, function(a, b)
		return a[1] < b[1]
	end)
	local g0, g1 = nil, nil
	local cur = rmn.Z
	for _, s in side do
		if s[1] - cur > 2.5 and (not g0 or s[1] - cur > (g1 - g0)) then
			g0, g1 = cur, s[1]
		end
		cur = math.max(cur, s[2])
	end
	local xg = rmx.X - 0.12
	if g0 and g1 then
		local m0, m1 = g0 + 0.12, g1 - 0.12
		local dw = m1 - m0
		local dh = 8.6
		local door = K:group("SmokingDoor", function()
			K:free(function()
				local dc = CF(xg, dh / 2 + 0.1, (m0 + m1) / 2)
				K:box("SmokeDoorStileA", V3(0.16, dh, 0.16), dc * CF(0, 0, -dw / 2 + 0.08), Look.darkAlu)
				K:box("SmokeDoorStileB", V3(0.16, dh, 0.16), dc * CF(0, 0, dw / 2 - 0.08), Look.darkAlu)
				K:box("SmokeDoorRail", V3(0.16, 0.2, dw), dc * CF(0, dh / 2 - 0.1, 0), Look.darkAlu)
				K:box("SmokeDoorRail", V3(0.16, 0.5, dw), dc * CF(0, -dh / 2 + 0.25, 0), Look.darkAlu)
				K:box("SmokeDoorGlass", V3(0.05, dh - 0.7, dw - 0.3), dc * CF(0, 0.15, 0), glassL(rgb(200, 220, 228), 0.62))
				K:box("SmokeDoorFrost", V3(0.06, 1.7, dw - 0.3), dc * CF(0, 4.05 - dh / 2 - 0.1, 0), { c = rgb(236, 240, 242), m = M.Glass, t = 0.3 })
				K:box("SmokeDoorHandle", V3(0.08, 1.8, 0.08), dc * CF(0.2, -0.3, dw / 2 - 0.4), Look.chrome)
				K:box("SmokeDoorHandle", V3(0.08, 1.8, 0.08), dc * CF(-0.2, -0.3, dw / 2 - 0.4), Look.chrome)
				K:box("SmokeDoorHandleBar", V3(0.48, 0.06, 0.06), dc * CF(0, 0.5, dw / 2 - 0.4), Look.chrome)
				K:box("SmokeDoorHandleBar", V3(0.48, 0.06, 0.06), dc * CF(0, -1.1, dw / 2 - 0.4), Look.chrome)
				K:text("SmokeDoorPull", 0.7, 0.28, faceCF(dc * V3(0.04, 1.0, dw / 2 - 0.5), V3(1, 0, 0)), "당기세요", { fg = WHITE, bg = rgb(30, 30, 34), d = 0.01 })
				-- 도어 클로저
				K:box("DoorCloser", V3(0.22, 0.24, 1.0), dc * CF(0.2, dh / 2 - 0.35, -dw / 2 + 0.7), Look.darkAlu)
				K:box("DoorCloserArm", V3(0.08, 0.06, 0.9), dc * CF(0.32, dh / 2 - 0.2, -dw / 2 + 0.75), Look.darkAlu)
			end)
		end)
		local hingeW = K.cf * V3(xg, 0, m0)
		local swing = rotor(door, hingeW, YA)
		local cW = K.cf * V3(xg, 3, (m0 + m1) / 2)
		local open = false
		local lastNear = -100
		Interact.anim(K, function(t)
			local near = playerNear(cW, 6.5)
			if near then
				lastNear = t
			end
			local want = near or (t - lastNear) < 1.5
			if want ~= open then
				open = want
				swing(if open then math.rad(92) else 0, if open then 0.55 else 0.9)
				if open then
					Interact.click(door:FindFirstChildWhichIsA("BasePart", true) :: BasePart, "rbxasset://sounds/clickfast.wav")
				end
			end
		end)
		keepBox(V, xg - 4.2, m0 - 0.4, xg + 4.2, m1 + 0.4, 9, "door")
	end
	-- 3) 재떨이 스탠드 (맵 원통 숨기고 같은 자리)
	local stands = recs(V, "AshtrayStand")
	for _, r in stands do
		hide(K, r)
	end
	for _, r in recs(V, "AshtrayTop") do
		hide(K, r)
	end
	K:free(function()
		for i, r in stands do
			local mn, mx, c = mb(K, r)
			local b = CF(c.X, 0, c.Z)
			K:vcyl("AshBinFoot", 0.12, 1.4, b * CF(0, 0.06, 0), lk(rgb(30, 30, 32), M.Metal))
			K:vcyl("AshBinBody", 2.9, 1.15, b * CF(0, 0.12 + 1.45, 0), Look.brushed)
			K:vcyl("AshBinBand", 0.18, 1.18, b * CF(0, 2.2, 0), lk(rgb(30, 30, 32), M.Metal))
			K:vcyl("AshBinRim", 0.1, 1.25, b * CF(0, 3.07, 0), Look.steel)
			K:disc("AshBinGrill", 1.0, 0.02, b * CF(0, 3.1, 0), lk(rgb(40, 40, 42), M.DiamondPlate))
			K:disc("AshBinSand", 0.62, 0.02, b * CF(0, 3.115, 0), lk(rgb(200, 186, 150), M.Sand))
			for j = 0, 2 do
				K:cyl("CigButt", 0.22, 0.05, b * CF(-0.1 + j * 0.1, 3.14, 0.05 * j) * ANG(0, j * 1.3, 0), lk(rgb(240, 200, 150)))
			end
			K:text("AshBinLabel", 0.7, 0.22, faceCF(b * V3(0, 2.2, 0.6), V3(0, 0, 1)), "꽁초는 여기에", { fg = WHITE, bg = rgb(30, 30, 32), d = 0.01 })
			local _ = mn
			local _2 = mx
			local _3 = i
		end
	end)
	-- 4) 스탠딩 선반 (뒤 유리 안쪽 따라) + 작은 재떨이
	local zB = rmn.Z + 0.25
	K:free(function()
		local x0, x1 = rmn.X + 2.0, rmx.X - 0.6
		local lc = CF((x0 + x1) / 2, 3.55, zB + 0.45)
		K:box("SmokeLedge", V3(x1 - x0, 0.12, 0.9), lc, lk(rgb(40, 40, 44)))
		K:box("SmokeLedgeEdge", V3(x1 - x0, 0.16, 0.05), lc * CF(0, -0.02, 0.45), Look.brushed)
		local n = math.max(2, math.floor((x1 - x0) / 4))
		for i = 0, n do
			local x = -(x1 - x0) / 2 + 0.3 + (x1 - x0 - 0.6) * i / n
			K:box("SmokeLedgeLeg", V3(0.12, 3.5, 0.12), lc * CF(x, -1.78, -0.25), Look.blackMetal)
		end
		for i = 0, 2 do
			local x = -(x1 - x0) / 2 + (x1 - x0) * (i + 0.5) / 3
			K:disc("SmallAshtray", 0.5, 0.1, lc * CF(x, 0.11, 0.05), Look.steel)
			K:disc("SmallAshtrayIn", 0.36, 0.02, lc * CF(x, 0.165, 0.05), lk(rgb(60, 60, 62)))
		end
	end)
	-- 5) 공기청정기 (벽걸이, 켜기/끄기 + 팬 회전)
	local ap = recs(V, "AirPurifier")[1]
	if ap then
		local amn, amx, ac = mb(K, ap)
		hide(K, ap)
		local nx = if ac.X < rc.X then 1 else -1
		local fxp = if nx > 0 then amn.X else amx.X
		local d = faceCF(V3(fxp, ac.Y, ac.Z), V3(nx, 0, 0))
		local ww, hh, dd = amx.Z - amn.Z, amx.Y - amn.Y, amx.X - amn.X
		local fanParts = {}
		local leds = {}
		local disp
		K:free(function()
			K:panel("PurifierShell", ww, hh, dd, 0.3, d, lk(rgb(240, 240, 238)))
			local f = d * CF(0, 0, dd + 0.005)
			K:plate("PurifierFace", ww - 0.3, hh - 0.3, 0.02, f, lk(rgb(226, 228, 228)))
			K:ring("PurifierRing", f * CF(0, 0.25, 0.03), 0.95, 0.12, 14, lk(rgb(200, 202, 204)))
			K:disc("PurifierGrille", 1.8, 0.02, f * CF(0, 0.25, 0.02) * ANG(PI / 2, 0, 0), lk(rgb(60, 62, 66), M.DiamondPlate))
			for i = 0, 4 do
				local a = i * 2 * PI / 5
				local blade = K:box("PurifierBlade", V3(0.75, 0.22, 0.02), f * CF(0, 0.25, 0.05) * ANG(0, 0, a) * CF(0.4, 0, 0) * ANG(0.35, 0, 0), lk(rgb(90, 92, 98)))
				table.insert(fanParts, blade)
			end
			table.insert(fanParts, K:disc("PurifierHub", 0.3, 0.04, f * CF(0, 0.25, 0.06) * ANG(PI / 2, 0, 0), lk(rgb(220, 220, 222))))
			local ledRing = K:ring("PurifierLED", f * CF(0, 0.25, 0.05), 1.05, 0.05, 12, neon(C.blue))
			for _, p in ledRing do
				table.insert(leds, p)
			end
			K:plate("PurifierDispBack", 1.6, 0.42, 0.02, f * CF(0, -hh / 2 + 0.5, 0.0), lk(rgb(16, 18, 22)))
			local _, l = K:text("PurifierDisp", 1.5, 0.34, f * CF(0, -hh / 2 + 0.5, 0.025), "PM2.5  18㎍  보통", { fg = C.blue, glow = 1.6, font = F.GothamBold, d = 0.01 })
			disp = l
			K:text("PurifierBrand", 1.6, 0.2, f * CF(0, hh / 2 - 0.28, 0.02), "흡연실 전용 공기청정기", { fg = rgb(70, 70, 76), font = F.GothamBold, d = 0.01 })
		end)
		-- 팬 회전 (팬 축 = 벽 법선)
		local base = {}
		local axisW = (K.cf * d).ZVector
		local centerW = (K.cf * d * CF(0, 0.25, dd + 0.05)).Position
		for _, p in fanParts do
			table.insert(base, { p = p, cf = p.CFrame })
		end
		local on = true
		local ang = 0
		Interact.anim(K, function(_t, dt)
			if not on then
				return
			end
			ang += (dt or 0.1) * 9
			local rot = CFrame.new(centerW) * CFrame.fromAxisAngle(axisW, ang) * CFrame.new(-centerW)
			for _, b in base do
				if b.p.Parent then
					b.p.CFrame = rot * b.cf
				end
			end
		end)
		local tgt = leds[1] or fanParts[1]
		if tgt and promptOK(K, tgt) then
			Interact.toggle(K, tgt, {
				object = "공기청정기",
				state = true,
				onText = "끄기",
				offText = "켜기",
				on = function(s: boolean)
					on = s
					for _, p in leds do
						p.Material = if s then M.Neon else M.SmoothPlastic
						p.Color = if s then C.blue else rgb(120, 120, 124)
					end
					if disp and disp.Parent then
						disp.Text = if s then "PM2.5  18㎍  보통" else "OFF"
						disp.TextColor3 = if s then C.blue else rgb(120, 120, 124)
					end
				end,
			})
		end
		-- 이용 수칙 (공기청정기 옆 같은 벽)
		local nz = if ac.Z + ww / 2 + 1.0 < rmx.Z - 1.0 then ac.Z + ww / 2 + 0.9 else ac.Z - ww / 2 - 0.9
		local wn = if nx > 0 then "left" else "right"
		local u = if wn == "left" then -nz else nz
		notice(K, W(K, wn, u, 6.2, 0.01), 1.5, 2.0, "흡연실 이용 수칙", "일반 · 전자담배\n모두 이곳에서\n\n꽁초는 재떨이에\n문은 꼭 닫아주세요", rgb(120, 120, 128))
	end
	-- 6) 천장: 열 감지기 + 스피커 없음 (흡연실), 칸막이 위 바닥 LED 없음
	local bulk = recs(V, "SmokingRoomBulkhead")[1]
	if bulk then
		local bmn = mb(K, bulk)
		K:free(function()
			K:disc("HeatDetector", 0.5, 0.12, CF(rc.X + 4, bmn.Y - 0.06, rc.Z - 3), Look.white)
			K:disc("HeatDetectorLED", 0.06, 0.02, CF(rc.X + 4.15, bmn.Y - 0.13, rc.Z - 3), Look.ledRed)
		end)
	end
end

-- 앞 천장: RGB 라인 · 행잉 사인 (PC ZONE · COUNTER) · 비상구 유도등 · CCTV · 스피커 · 스프링클러 · 감지기
local function frontCeiling(K: any, V: any)
	local P = K.pc
	local H = P.ceil
	local yL = H - 0.13 -- TBar 아래면에 붙음
	K:free(function()
		local lines = {
			{ V3(-9.4, yL, 5.6), V3(17.0, yL, 5.6), C.cyan },
			{ V3(-9.4, yL, -10.4), V3(17.0, yL, -10.4), C.magenta },
			{ V3(-9.4, yL, -10.4), V3(-9.4, yL, 5.6), C.purple },
		}
		for _, l in lines do
			local p = K:bar("CeilRGB", l[1], l[2], 0.12, 0.06, neon(l[3]))
			if p then
				table.insert(P.rgb, { p = p, c = l[3], x = 0, z = 0 })
			end
		end
	end)
	-- 홀 들어가는 곳 행잉 사인 (앞: PC ZONE, 뒤: 출구 · 카운터)
	hangSign(K, V3(0.6, 8.9, V.z0 + 0.9), V3(0, 0, 1), 7.6, 1.35, "PC ZONE ▶  일반석 · FPS 존 · 프리미엄", "◀ 출입구 · 카운터 · 흡연실", WHITE, C.magenta, { font = F.GothamBlack })
	-- 카운터 블레이드 사인 (입구 쪽을 봄)
	local body = recs(V, "CounterBody")[1]
	if body then
		local bmn, bmx = mb(K, body)
		hangSign(K, V3((bmn.X + bmx.X) / 2, 8.9, bmx.Z + 1.6), V3(0, 0, 1), 3.6, 1.0, "COUNTER · 카운터", "COUNTER · 카운터", C.cyan, C.cyan, { font = F.GothamBlack })
	end
	-- 비상구 유도등 (자동문 위 안쪽)
	if V.door then
		K:free(function()
			local d = faceCF(V3(V.door.x, H - 0.55, V.z1 - 0.65), V3(0, 0, -1))
			K:box("ExitSignBox", V3(2.2, 0.62, 0.22), d * CF(0, 0, -0.11), lk(rgb(236, 236, 232)))
			K:text("ExitSignText", 2.05, 0.5, d, "← 비상구 EXIT", { fg = WHITE, bg = C.exitGreen, glow = 1.8, font = F.GothamBlack, d = 0.02 })
			K:seg("ExitSignRod", d * V3(0, 0.3, -0.11), V3(V.door.x, H, V.z1 - 0.76), 0.06, Look.blackMetal)
		end)
	end
	-- CCTV (입구) · 천장 스피커 · 스프링클러 · 감지기
	dome(K, (V.door and V.door.x or 9) - 6, V.z1 - 2.2)
	for _, p in { { -2, 3.5 }, { 12, -6 }, { -20, 6.5 } } do
		ceilSpeaker(K, p[1], p[2])
	end
	for _, p in { { -6, 7.5 }, { 2, -8.5 }, { 10, 4.2 }, { -2.0, -1.0 }, { 14.6, 8.2 }, { 24.5, 4.0 }, { 24.5, -6.5 } } do
		sprinkler(K, p[1], p[2])
	end
	detector(K, 6, -8.6)
	detector(K, -4.5, 7.6)
	-- 셀프바 쪽 벽 스피커 + 앞 왼쪽 벽 위 유도등
	K:free(function()
		speaker(K, W(K, "left", -5.0, 9.7, 0), 14)
	end)
end

------------------------------------------------------------------------------------------------------------
-- 2) 홀 (pchall) ----------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

-- PC 자리 모음 (모델별 맵 파트 기록)
local function stations(K: any, V: any): { any }
	local by: { [Instance]: any } = {}
	local list = {}
	for _, r in V.parts do
		local m = r.part.Parent
		if m and m:IsA("Model") and string.match(m.Name, "^PC_%d+$") then
			local s = by[m]
			if not s then
				s = { model = m, name = m.Name, num = tonumber(string.match(m.Name, "%d+")) or 0, p = {} }
				by[m] = s
				table.insert(list, s)
			end
			if not s.p[r.name] then
				s.p[r.name] = r
			end
		end
	end
	table.sort(list, function(a, b)
		return a.num < b.num
	end)
	return list
end

-- 존: 행 쌍 (앞 · 가운데 · 뒤) -> 이름 · 색
local ZONES = {
	{ name = "일반석", sub = "165Hz · 27인치", c = C.cyan },
	{ name = "FPS 존", sub = "240Hz · 게이밍 기어", c = C.purple },
	{ name = "프리미엄석", sub = "360Hz · QHD · 넓은 자리", c = C.magenta },
}
local ROWS = { "A", "B", "C", "D", "E", "F" }

local function hallKeeps(K: any, V: any, st: { any })
	-- 가운데 통로 (왼쪽 블록 끝 ~ 오른쪽 블록 시작)
	local lMax, rMin = -math.huge, math.huge
	for _, r in recs(V, "DeskTop") do
		local mn, mx = mb(K, r)
		if mx.X < 0 then
			lMax = math.max(lMax, mx.X)
		else
			rMin = math.min(rMin, mn.X)
		end
	end
	if lMax > -math.huge and rMin < math.huge then
		keepBox(V, lMax + 0.25, V.z0, rMin - 0.25, V.z1, 6.5, "aisle")
		K.pc.aisle = { lMax, rMin }
	end
	-- 의자 뒤 ServePos 통로 (의자 등받이 바깥 3)
	for _, s in st do
		local seat, back = s.p.Seat, s.p.ChairBack
		if seat and back then
			local smn, smx, sc = mb(K, seat)
			local bmn, bmx, bc = mb(K, back)
			local dir = if bc.Z > sc.Z then 1 else -1
			local z0 = if dir > 0 then bmx.Z else bmn.Z
			keepBox(V, smn.X - 2.5, z0, smx.X + 2.5, z0 + dir * 3.2, 6.5, "serve")
		end
	end
	-- 양 옆 통로
	local P = K.pc
	local dx0, dx1 = math.huge, -math.huge
	for _, r in recs(V, "DeskTop") do
		local mn, mx = mb(K, r)
		dx0 = math.min(dx0, mn.X)
		dx1 = math.max(dx1, mx.X)
	end
	if dx0 < math.huge then
		keepBox(V, P.xl + 1.1, V.z0, dx0 - 0.2, V.z1, 6.5, "aisle")
		keepBox(V, dx1 + 0.2, V.z0, P.xr - 2.4, V.z1, 6.5, "aisle")
		P.desk = { dx0, dx1 }
	end
	-- 책상 위 (아무것도 안 올림)
	for _, r in recs(V, "DeskTop") do
		local mn, mx = mb(K, r)
		V:addKeep(V3(mn.X, mx.Y - 0.02, mn.Z), V3(mx.X, mx.Y + 2.6, mx.Z), "desk")
	end
end

-- 자리 디테일: 칸막이 위 좌석 번호판 · 헤드셋 걸이 · 호출 버튼 · 5발 베이스
local function hallStations(K: any, V: any, st: { any })
	local P = K.pc
	-- 칸막이 목록
	local divs = {}
	for _, r in recs(V, "Divider") do
		local mn, mx, c = mb(K, r)
		table.insert(divs, { mn = mn, mx = mx, c = c })
	end
	local rgbTop = {}
	for _, r in recs(V, "DividerRGB") do
		local _, mx, c = mb(K, r)
		table.insert(rgbTop, { y = mx.Y, c = c })
	end
	local function zoneOf(num: number): any
		local pair = math.floor((num - 1) / 16) + 1
		return ZONES[math.clamp(pair, 1, 3)]
	end
	local detail = K.detail
	K:free(function()
		for _, s in st do
			local bez, seat = s.p.MonitorBezel, s.p.Seat
			if not (bez and seat) then
				continue
			end
			local bmn, bmx, bc = mb(K, bez)
			local _, _, sc = mb(K, seat)
			local n = if sc.Z > bc.Z then V3(0, 0, 1) else V3(0, 0, -1)
			local z = zoneOf(s.num)
			-- 가장 가까운 칸막이
			local dv = nil
			for _, d in divs do
				if bc.X > d.mn.X and bc.X < d.mx.X and (not dv or math.abs(d.c.Z - bc.Z) < math.abs(dv.c.Z - bc.Z)) then
					dv = d
				end
			end
			if dv then
				local topY = dv.mx.Y + 0.1
				for _, rt in rgbTop do
					if math.abs(rt.c.Z - dv.c.Z) < 0.5 and math.abs(rt.c.X - dv.c.X) < 3 then
						topY = math.max(topY, rt.y)
					end
				end
				-- 좌석 번호판 (칸막이 위, 자리 쪽을 봄)
				local fz = dv.c.Z + n.Z * 0.075
				local pd = faceCF(V3(bc.X, topY + 0.34, fz), n)
				K:text("SeatNumber", 1.05, 0.62, pd * CF(0, 0, -0.07), string.format("%02d", s.num), { fg = z.c, bg = rgb(14, 14, 18), glow = 1.7, font = F.Michroma, d = 0.14 })
				if detail ~= "low" then
					local ul = K:box("SeatNumberLED", V3(1.05, 0.04, 0.14), CF(bc.X, topY + 0.67, fz), neon(z.c))
					table.insert(P.rgb, { p = ul, c = z.c, x = bc.X, z = fz })
				end
				-- 호출 버튼 판 (헤드셋 반대쪽, 칸막이 면)
				local band = s.p.HeadsetBand
				local hsx = if band then (select(3, mb(K, band))).X else bmx.X
				local sgn = if hsx > bc.X then 1 else -1
				local faceZ = if n.Z > 0 then dv.mx.Z + 0.005 else dv.mn.Z - 0.005
				local cx = bc.X - sgn * ((bmx.X - bmn.X) / 2 + 0.5)
				local cd = faceCF(V3(cx, 3.45, faceZ), n)
				K:plate("CallPanel", 0.55, 0.55, 0.04, cd, lk(rgb(18, 18, 22)))
				wdisc(K, "CallButton", 0.26, 0.05, cd * CF(0, 0.07, 0.04), lk(rgb(220, 36, 40)))
				if detail == "high" then
					K:plate("CallUSB", 0.16, 0.06, 0.05, cd * CF(-0.12, -0.17, 0.04), lk(rgb(40, 40, 46)))
					K:plate("CallUSB", 0.16, 0.06, 0.05, cd * CF(0.12, -0.17, 0.04), lk(rgb(40, 40, 46)))
				end
			end
			-- 헤드셋 걸이 (모니터 위 모서리에서 헤드밴드까지)
			local band = s.p.HeadsetBand
			if band then
				local hmn, hmx, hc = mb(K, band)
				local sgn = if hc.X > bc.X then 1 else -1
				local edge = if sgn > 0 then bmx.X else bmn.X
				local y = math.max(bmx.Y, hmx.Y) + 0.04
				local zc = hc.Z
				K:box("HeadsetHookClamp", V3(0.3, 0.12, 0.3), CF(edge - sgn * 0.12, y, (bmn.Z + bmx.Z) / 2), lk(rgb(20, 20, 24)))
				K:bar("HeadsetHook", V3(edge - sgn * 0.05, y, zc), V3(hc.X + sgn * 0.14, y, zc), 0.08, 0.07, lk(rgb(20, 20, 24)))
				if detail ~= "low" then
					K:bar("HeadsetHookLip", V3(hc.X + sgn * 0.14, y, zc), V3(hc.X + sgn * 0.14, y + 0.16, zc), 0.07, 0.07, lk(rgb(20, 20, 24)))
				end
				local _ = hmn
			end
			-- 의자 5발 베이스 (맵 원판 위)
			local gas, cbase = s.p.GasLift, s.p.ChairBase
			if gas and cbase and detail ~= "low" then
				local _, gmx, gc = mb(K, gas)
				local cmn, cmx, cc = mb(K, cbase)
				local r0 = (cmx.X - cmn.X) / 2 + 0.05
				local yb = cmx.Y
				local hub = V3(gc.X, yb + 0.12, gc.Z)
				K:vcyl("ChairHub", 0.18, 0.32, CF(hub), lk(rgb(30, 30, 34), M.Metal))
				for i = 0, 4 do
					local a = i * 2 * PI / 5 + 0.3
					local tip = V3(cc.X + math.cos(a) * r0, yb + 0.06, cc.Z + math.sin(a) * r0)
					K:bar("ChairStar", hub, tip, 0.16, 0.1, lk(rgb(26, 26, 30), M.Metal))
					if detail == "high" then
						K:ball("ChairCaster", 0.24, CF(tip.X, 0.12, tip.Z), lk(rgb(20, 20, 22), M.Rubber))
					end
				end
				local _ = gmx
			end
		end
	end)
end

-- 열 엔드캡 (가운데 통로 쪽 끝) + 행잉 존 사인
local function hallRows(K: any, V: any)
	local P = K.pc
	local divs = {}
	for _, r in recs(V, "Divider") do
		local mn, mx, c = mb(K, r)
		table.insert(divs, { mn = mn, mx = mx, c = c })
	end
	table.sort(divs, function(a, b)
		if math.abs(a.c.Z - b.c.Z) > 3 then
			return a.c.Z > b.c.Z -- 앞(입구 쪽 +Z)부터
		end
		return a.c.X < b.c.X
	end)
	for i, d in divs do
		local pair = math.floor((i - 1) / 2) + 1
		local z = ZONES[math.clamp(pair, 1, 3)]
		local row = ROWS[i] or "?"
		local n0 = (i - 1) * 8 + 1
		local label = string.format("%s열 · %s  %02d–%02d", row, z.name, n0, n0 + 7)
		-- 행잉 존 사인 (칸막이 위, 앞뒤 두 면)
		local l1, l2 = hangSign(K, V3(d.c.X, 8.15, d.c.Z), V3(0, 0, 1), 7.4, 1.25, label, label, WHITE, z.c, { font = F.GothamBlack, light = true, range = 12, bright = 0.4 })
		local _ = l1
		local _2 = l2
		-- 존 사인 아래 RGB 막대 등록
		-- 통로 쪽 끝 (책상 쌍의 z 범위)
		local dz0, dz1 = math.huge, -math.huge
		for _, r in recs(V, "DeskTop") do
			local mn, mx = mb(K, r)
			if math.abs((mn.X + mx.X) / 2 - d.c.X) < 3 and math.abs((mn.Z + mx.Z) / 2 - d.c.Z) < 3.5 then
				dz0 = math.min(dz0, mn.Z)
				dz1 = math.max(dz1, mx.Z)
			end
		end
		if dz0 < math.huge then
			local aisleSide = if d.c.X < 0 then 1 else -1 -- 왼쪽 블록은 +X 끝, 오른쪽 블록은 -X 끝
			local ex = if aisleSide > 0 then d.mx.X else d.mn.X
			for _, nm in { "DeskSide", "RowTag", "DeskTop" } do
				for _, r in recs(V, nm) do
					local mn, mx, c = mb(K, r)
					if math.abs(c.Z - d.c.Z) < 3.6 and math.abs(c.X - (if aisleSide > 0 then d.mx.X else d.mn.X)) < 1.2 then
						ex = if aisleSide > 0 then math.max(ex, mx.X) else math.min(ex, mn.X)
					end
				end
			end
			ex += aisleSide * 0.02
			local cz = (dz0 + dz1) / 2
			local w = dz1 - dz0
			local ec = faceCF(V3(ex, 0, cz), V3(aisleSide, 0, 0))
			K:free(function()
				if aisleSide > 0 then
					-- RowTag 가 없는 쪽: 엔드캡 패널 전체
					K:plate("EndCap", w, 5.4, 0.06, ec * CF(0, 2.75, 0), lk(rgb(18, 18, 22)))
					local e1 = K:plate("EndCapEdge", 0.08, 5.4, 0.08, ec * CF(-w / 2 + 0.06, 2.75, 0), neon(z.c))
					local e2 = K:plate("EndCapEdge", 0.08, 5.4, 0.08, ec * CF(w / 2 - 0.06, 2.75, 0), neon(z.c))
					table.insert(P.rgb, { p = e1, c = z.c, x = ex, z = cz })
					table.insert(P.rgb, { p = e2, c = z.c, x = ex, z = cz })
					K:text("EndCapRow", w * 0.7, 1.6, ec * CF(0, 3.7, 0.07), row .. "열", { fg = z.c, glow = 1.8, font = F.GothamBlack })
					K:text("EndCapZone", w * 0.86, 0.6, ec * CF(0, 2.3, 0.07), z.name, { fg = WHITE, glow = 1.4, font = F.GothamBlack })
					K:text("EndCapSeats", w * 0.8, 0.44, ec * CF(0, 1.6, 0.07), string.format("%02d - %02d", n0, n0 + 7), { fg = rgb(210, 210, 220), glow = 1.2, font = F.Michroma })
					K:text("EndCapSub", w * 0.86, 0.34, ec * CF(0, 0.95, 0.07), z.sub, { fg = rgb(170, 170, 186), glow = 1.1, font = F.GothamBold })
				else
					-- RowTag 있는 쪽: 아래에 존 띠만
					K:plate("EndCapBand", w - 0.2, 0.9, 0.06, ec * CF(0, 0.9, 0), lk(rgb(18, 18, 22)))
					K:text("EndCapZone", w * 0.8, 0.5, ec * CF(0, 1.0, 0.07), z.name .. "  " .. string.format("%02d–%02d", n0, n0 + 7), { fg = z.c, glow = 1.6, font = F.GothamBlack })
					local e = K:plate("EndCapEdge", w - 0.2, 0.05, 0.08, ec * CF(0, 0.47, 0), neon(z.c))
					table.insert(P.rgb, { p = e, c = z.c, x = ex, z = cz })
				end
			end)
		end
	end
end

-- 홀 벽 (흡음 패널 · 포스터 · 안내 · 유도등 · 소화기 · 스피커 · RGB 조명 패널)
local function hallWalls(K: any, V: any)
	local P = K.pc
	-- 포스터 자리 (맵 표지판 · 화면 · LED 막대 사이 빈 칸에서 고름)
	local posters = {
		left = {
			{ z = 23.8, w = 3.3, h = 5.6, spec = { bg = rgb(16, 10, 34), title = "NIGHT\nRACER", titleH = 0.26, titleY = 0.27, sub = "광안대교 나이트 레이서\n랭킹전 시즌 3", subH = 0.14, subY = -0.34, tc = C.cyan, art = {
				{ rgb(255, 60, 170), 0.5, 0.56, 0.9, 0.02, -8, true }, { rgb(40, 236, 240), 0.5, 0.5, 0.9, 0.015, -8, true },
				{ rgb(60, 30, 90), 0.5, 0.22, 1.0, 0.18, 0 }, { rgb(240, 240, 255), 0.18, 0.42, 0.04, 0.34, 0 }, { rgb(240, 240, 255), 0.82, 0.42, 0.04, 0.34, 0 },
				{ rgb(255, 180, 40), 0.5, 0.06, 0.5, 0.05, 0, true } } } },
			{ z = 10.5, w = 4.4, h = 6.0, spec = { bg = rgb(36, 8, 10), title = "RAID", titleH = 0.2, titleY = 0.32, sub = "신규 레이드 오픈\n파티원 모집 중", tc = rgb(255, 120, 60), art = {
				{ rgb(120, 20, 20), 0.5, 0.45, 0.8, 0.5, 0 }, { rgb(255, 90, 40), 0.5, 0.5, 0.3, 0.3, 45, true }, { rgb(30, 10, 10), 0.5, 0.5, 0.18, 0.18, 45 },
				{ rgb(255, 200, 80), 0.22, 0.2, 0.05, 0.4, 20 }, { rgb(255, 200, 80), 0.78, 0.2, 0.05, 0.4, -20 } } } },
			{ z = -13.3, w = 8.6, h = 5.2, spec = { bg = rgb(8, 14, 30), title = "광안리 PC방 리그", titleH = 0.2, titleY = 0.28, sub = "SEASON 3 결승 · 토요일 20:00\n우승 상금 50만원 · 카운터 접수", subH = 0.16, subY = -0.3, tc = WHITE, font = F.GothamBlack, art = {
				{ rgb(40, 150, 255), 0.5, 0.08, 1.0, 0.05, 0, true }, { rgb(255, 60, 170), 0.5, 0.96, 1.0, 0.03, 0, true },
				{ rgb(255, 200, 60), 0.12, 0.52, 0.12, 0.4, 0 }, { rgb(255, 230, 120), 0.12, 0.76, 0.18, 0.06, 0 }, { rgb(30, 50, 90), 0.88, 0.5, 0.14, 0.5, 0 } } } },
			{ z = -24.9, w = 4.0, h = 6.0, spec = { bg = rgb(10, 26, 16), title = "BATTLE\nROYALE", titleH = 0.24, titleY = 0.27, sub = "스쿼드 모드 · 최후의 1팀", tc = rgb(120, 255, 140), art = {
				{ rgb(40, 90, 50), 0.5, 0.3, 1.0, 0.4, 0 }, { rgb(240, 240, 220), 0.5, 0.5, 0.36, 0.36, 0 }, { rgb(10, 26, 16), 0.5, 0.5, 0.3, 0.3, 0 },
				{ rgb(255, 80, 60), 0.5, 0.5, 0.06, 0.06, 0, true } } } },
		},
		right = {
			{ z = 17.5, w = 7.2, h = 5.0, spec = { bg = rgb(20, 8, 36), title = "FPS 존 · 240Hz", titleH = 0.2, titleY = 0.26, sub = "0.03초의 차이\n전 좌석 게이밍 마우스 · 기계식 키보드", subH = 0.16, tc = C.purple, font = F.GothamBlack, art = {
				{ rgb(160, 80, 255), 0.5, 0.52, 0.06, 0.3, 0, true }, { rgb(160, 80, 255), 0.5, 0.52, 0.3, 0.04, 0, true },
				{ rgb(70, 30, 110), 0.5, 0.52, 0.22, 0.38, 0 } } } },
			{ z = -21.0, w = 7.2, h = 5.0, spec = { bg = rgb(36, 6, 24), title = "PREMIUM", titleH = 0.2, titleY = 0.28, sub = "360Hz · QHD · 넓은 데스크\n프리미엄석 시간당 1,500원", subH = 0.16, tc = C.magenta, font = F.Michroma, art = {
				{ rgb(255, 60, 170), 0.5, 0.08, 1.0, 0.04, 0, true }, { rgb(90, 20, 60), 0.3, 0.5, 0.3, 0.3, 0 }, { rgb(255, 210, 120), 0.7, 0.5, 0.2, 0.2, 45 } } } },
		},
	}
	for _, wn in { "left", "right" } do
		for _, ps in posters[wn] do
			local u = if wn == "left" then -ps.z else ps.z
			local u0, u1 = u - ps.w / 2 - 0.1, u + ps.w / 2 + 0.1
			local y0 = 1.6
			if wallFree(K, wn, u0, u1, y0, y0 + ps.h) then
				poster(K, W(K, wn, u, y0 + ps.h / 2, 0.02), ps.w, ps.h, ps.spec)
				useWall(K, wn, u0, u1, 0.6, 8.6)
			else
				K:note("poster skipped " .. wn .. " " .. tostring(ps.z))
			end
		end
	end
	-- RGB 조명 패널 (오른쪽 벽, 입구 쪽) + 안내문 + 소화기 + 유도등
	local ctlU = 24.8
	if wallFree(K, "right", ctlU - 0.8, ctlU + 0.8, 3.6, 5.6) then
		local d = W(K, "right", ctlU, 4.6, 0.02)
		K:plate("RGBPanelBack", 1.1, 1.4, 0.06, d, lk(rgb(20, 20, 24)))
		local glassP = K:plate("RGBPanel", 0.95, 0.8, 0.02, d * CF(0, 0.15, 0.06), lk(rgb(10, 10, 14), M.Glass, { r = 0.2 }))
		local modeCols = { C.cyan, C.red, C.blue, C.amber, WHITE }
		for i = 1, 5 do
			wdisc(K, "RGBPanelBtn", 0.14, 0.03, d * CF(-0.36 + (i - 1) * 0.18, -0.42, 0.06), neon(modeCols[i]))
		end
		local _, ml = K:text("RGBPanelText", 0.85, 0.6, d * CF(0, 0.15, 0.085), "RGB 조명\n기본", { fg = WHITE, glow = 1.5, font = F.GothamBold })
		P.modeLabel = ml
		useWall(K, "right", ctlU - 0.8, ctlU + 0.8, 3.0, 6.0)
		P.modePanel = glassP
	end
	-- 안내문들
	local notes = {
		{ "right", 1.3, 2.5, 2.4, "PC방 이용 안내", "자리 비움 30분 초과 시 자동 종료\n외부 음식 반입 금지\n귀중품은 직접 보관해 주세요\n소란 · 흡연 시 이용 제한", rgb(40, 110, 220) },
		{ "left", -4.4, 2.2, 2.6, "금연 구역", "홀 전체 금연\n전자담배 포함\n흡연은 입구 쪽 흡연실에서", rgb(200, 30, 40) },
	}
	for _, nt in notes do
		local wn, u, w, h = nt[1], nt[2], nt[3], nt[4]
		if wallFree(K, wn, u - w / 2 - 0.1, u + w / 2 + 0.1, 3.8, 3.8 + h) then
			notice(K, W(K, wn, u, 3.8 + h / 2, 0.02), w, h, nt[5], nt[6], nt[7])
			useWall(K, wn, u - w / 2 - 0.1, u + w / 2 + 0.1, 0.6, 8.6)
		end
	end
	-- 소화기 (양쪽 벽 1개씩)
	for _, e in { { "right", -8.9 }, { "left", -19.6 } } do
		local wn, u = e[1], e[2]
		if wallFree(K, wn, u - 0.6, u + 0.6, 0.6, 4.4) then
			extinguisher(K, W(K, wn, u, 0, 0.02))
			useWall(K, wn, u - 0.6, u + 0.6, 0.6, 8.6)
		end
	end
	-- 흡음 패널 (남은 빈 칸)
	acousticWall(K, "left", { rgb = C.cyan })
	acousticWall(K, "right", { rgb = C.magenta })
	-- 유도등 (아래, 출구 쪽 화살표: 앞쪽은 입구, 뒤쪽은 비상구)
	for _, wn in { "left", "right" } do
		for _, z in { 20, 5, -10, -22 } do
			local u = if wn == "left" then -z else z
			local toFront = z > -2
			-- 보는 사람 오른쪽(+u) 이 앞(+Z)인 벽: right
			local rightIsFront = wn == "right"
			local arrow = if toFront == rightIsFront then "비상구 →" else "← 비상구"
			K:free(function()
				guideLight(K, W(K, wn, u, 1.25, 0.14), arrow)
			end)
		end
	end
	-- 벽 스피커 (네 귀퉁이)
	K:free(function()
		for _, sp in { { "left", -25 }, { "left", 25 }, { "right", -25 }, { "right", 25 } } do
			speaker(K, W(K, sp[1], sp[2], 9.6, 0.02), 16)
		end
	end)
end

-- 홀 천장: 흡음 배플 + RGB · 두 번째 스파이럴 덕트 · 케이블 트레이 · CCTV · 스프링클러 · 감지기
local function hallCeiling(K: any, V: any)
	local P = K.pc
	local H = P.ceil
	-- 피할 것: 천장 LED 가로줄 · LightHolder · 덕트
	local crossZ = {}
	for _, r in recs(V, "CeilingLED") do
		local mn, mx, c = mb(K, r)
		if mx.X - mn.X > 30 then
			table.insert(crossZ, c.Z)
		end
	end
	table.sort(crossZ)
	local holders = {}
	for _, r in recs(V, "LightHolder") do
		local _, _, c = mb(K, r)
		table.insert(holders, c)
	end
	local duct = recs(V, "SpiralDuct")[1]
	local ductX, ductY, ductD = 24.5, 9.85, 1.9
	if duct then
		local mn, mx, c = mb(K, duct)
		ductX, ductY, ductD = c.X, c.Y, math.min(mx.Y - mn.Y, 2.4)
	end
	-- 두 번째 덕트 (왼쪽, 거울 위치) + 마디 + 행거 + 디퓨저
	local lx = -ductX
	K:free(function()
		local z0, z1 = V.z0 + 0.1, V.z1 - 0.1
		K:cyl("SpiralDuctL", z1 - z0, ductD, CF(lx, ductY, (z0 + z1) / 2) * ANG(0, PI / 2, 0), lk(rgb(40, 40, 44), M.Metal))
		local step = if hi(K) then 2.6 else 5.2
		local z = z0 + 1
		while z < z1 do
			K:cyl("SpiralSeam", 0.08, ductD + 0.06, CF(lx, ductY, z) * ANG(0, PI / 2, 0), lk(rgb(60, 60, 64), M.Metal))
			z += step
		end
		z = z0 + 3
		while z < z1 do
			K:box("DuctStrap", V3(0.1, H - ductY, 0.1), CF(lx - ductD / 2 - 0.05, (H + ductY) / 2, z), Look.blackMetal)
			K:box("DuctStrap", V3(0.1, H - ductY, 0.1), CF(lx + ductD / 2 + 0.05, (H + ductY) / 2, z), Look.blackMetal)
			z += 9
		end
		for _, ez in { z0, z1 } do
			K:disc("DuctEndCap", ductD + 0.04, 0.08, CF(lx, ductY, ez) * ANG(PI / 2, 0, 0), lk(rgb(30, 30, 34), M.Metal))
		end
		for _, zz in { 16, -2, -18 } do
			K:box("DuctDiffuser", V3(1.5, 0.12, 1.5), CF(lx, ductY - ductD / 2 - 0.02, zz), lk(rgb(140, 144, 148), M.DiamondPlate))
		end
	end)
	-- 케이블 트레이 (가운데 통로 왼쪽 위, 앞뒤로 길게)
	local aisle = P.aisle or { -6.2, 1.6 }
	-- 가운데 천장 LED 세로줄 x
	local midX = -2.4
	for _, r in recs(V, "CeilingLED") do
		local mn, mx, c = mb(K, r)
		if mx.Z - mn.Z > 30 and math.abs(c.X) < 8 then
			midX = c.X
		end
	end
	local tx = midX + 2.2
	K:free(function()
		local z0, z1 = V.z0 + 0.1, V.z1 - 0.1
		local ty = H - 0.95
		local cz = (z0 + z1) / 2
		local len = z1 - z0
		for _, sx in { -0.45, 0.45 } do
			K:box("CableTrayRail", V3(0.06, 0.28, len), CF(tx + sx, ty, cz), lk(rgb(150, 154, 158), M.Metal))
		end
		local rs = if hi(K) then 1.6 else 3.2
		local z = z0 + 0.5
		while z < z1 do
			K:box("CableTrayRung", V3(0.9, 0.05, 0.08), CF(tx, ty - 0.12, z), lk(rgb(150, 154, 158), M.Metal))
			z += rs
		end
		for i, c in { rgb(40, 90, 200), rgb(70, 70, 76), rgb(230, 200, 40), rgb(60, 60, 64) } do
			K:cyl("TrayCable", len, 0.12, CF(tx - 0.27 + (i - 1) * 0.18, ty - 0.03, cz) * ANG(0, PI / 2, 0), lk(c))
		end
		z = z0 + 2
		while z < z1 do
			for _, sx in { -0.45, 0.45 } do
				K:box("CableTrayRod", V3(0.05, H - ty, 0.05), CF(tx + sx, (H + ty) / 2, z), Look.blackMetal)
			end
			z += 8
		end
	end)
	-- 흡음 배플 (가로줄 사이 칸마다, 블록별)
	local edges = { V.z0 }
	for _, z in crossZ do
		table.insert(edges, z)
	end
	table.insert(edges, V.z1)
	local xA0, xA1 = lx + ductD / 2 + 0.5, midX - 0.7
	local xB0, xB1 = tx + 0.9, ductX - ductD / 2 - 0.5
	local bays = {}
	for i = 1, #edges - 1 do
		local a, b = edges[i], edges[i + 1]
		local n = math.floor((b - a - 1.2) / 2.6)
		for j = 1, n do
			local z = a + (b - a) * j / (n + 1)
			local ok = true
			for _, h in holders do
				if math.abs(h.Z - z) < 0.9 then
					ok = false
				end
			end
			if ok then
				table.insert(bays, z)
			end
		end
	end
	K:free(function()
		local y1 = H - 0.25
		local y0 = y1 - 1.25
		-- 존 색 (앞 = 일반석 · 가운데 = FPS · 뒤 = 프리미엄)
		local function zc(z: number): Color3
			if #crossZ >= 2 and z < crossZ[1] then
				return C.magenta
			elseif #crossZ >= 2 and z < crossZ[#crossZ] then
				return C.purple
			end
			return C.cyan
		end
		for bi, z in bays do
			for _, xr in { { xA0, xA1 }, { xB0, xB1 } } do
				local len = xr[2] - xr[1]
				if len > 2 then
					local cx = (xr[1] + xr[2]) / 2
					K:box("CeilBaffle", V3(len, y1 - y0, 0.22), CF(cx, (y0 + y1) / 2, z), lk(if bi % 2 == 0 then rgb(46, 47, 54) else rgb(58, 60, 68), M.Fabric))
					K:box("CeilBaffleCap", V3(len + 0.02, 0.05, 0.26), CF(cx, y0 + 0.02, z), Look.blackMetal)
					if not lowD(K) then
						for _, sx in { -0.35, 0.35 } do
							K:seg("BaffleWire", V3(cx + sx * len, y1, z), V3(cx + sx * len, H, z), 0.03, Look.blackMetal)
						end
					end
					if bi % 2 == 1 then
						local c = dk(zc(z), 0.35)
						local led = K:box("CeilBaffleLED", V3(len - 0.1, 0.04, 0.06), CF(cx, y0 - 0.02, z), neon(c))
						table.insert(P.rgb, { p = led, c = c, x = cx, z = z, baffle = true })
					end
				end
			end
		end
	end)
	-- CCTV · 스프링클러 (덕트 · 배플 피해서) · 감지기
	dome(K, V.x0 + 2.0, V.z0 + 2.0)
	dome(K, V.x1 - 2.5, V.z1 - 2.0)
	for _, z in { 20, 7, -7, -20 } do
		for _, x in { -14, 9 } do
			local zz = z
			for _, bz in bays do
				if math.abs(bz - zz) < 0.5 then
					zz += 0.9
				end
			end
			K:free(function()
				K:vcyl("SprinklerDrop", H - 9.6, 0.1, CF(x, (H + 9.6) / 2 + 0.1, zz), lk(rgb(200, 40, 40), M.Metal))
				K:disc("SprinklerDeflector", 0.24, 0.03, CF(x, 9.62, zz), Look.brass)
				K:vcyl("SprinklerBody", 0.16, 0.08, CF(x, 9.72, zz), Look.brass)
			end)
		end
	end
	for _, p in { { -14, 0 }, { 9, -12 }, { 9, 12 } } do
		detector(K, p[1], p[2])
	end
	P.baffles = bays
end

-- 홀 바닥: 가운데 통로 러너 + 네온 가이드 · 카펫 줄눈
local function hallFloor(K: any, V: any)
	local P = K.pc
	local aisle = P.aisle
	K:free(function()
		if aisle then
			local x0, x1 = aisle[1] + 0.3, aisle[2] - 0.3
			K:box("AisleRunner", V3(x1 - x0, 0.02, V.D - 0.1), CF((x0 + x1) / 2, 0.012, (V.z0 + V.z1) / 2), lk(rgb(30, 31, 36), M.Carpet))
			for _, x in { x0 + 0.12, x1 - 0.12 } do
				local p = K:box("AisleGuide", V3(0.08, 0.02, V.D - 0.2), CF(x, 0.025, (V.z0 + V.z1) / 2), neon(C.cyan, 0.25))
				table.insert(P.rgb, { p = p, c = C.cyan, x = x, z = 0 })
			end
		end
	end)
	carpetSeams(K, P.xl, P.xr, V.z0, V.z1, 3.3, lk(rgb(46, 48, 53), M.Carpet))
end

-- 공기청정기 (바닥, 오른쪽 통로 벽 쪽)
local function floorPurifier(K: any, x: number, z: number, n: Vector3): boolean
	local pcf = facing(V3(x, 0, z), n)
	if not spotN(K, pcf, V3(1.7, 4.8, 1.7), 0.05) then
		return false
	end
	K:rbox("TowerPurifier", V3(4.4, 1.5, 1.5), 0.45, pcf * CF(0, 2.25, 0) * ANG(0, 0, PI / 2), lk(rgb(236, 236, 234)))
	K:box("TowerPurifierGrille", V3(1.2, 2.6, 0.04), pcf * CF(0, 1.8, 0.76), lk(rgb(180, 182, 186), M.DiamondPlate))
	K:disc("TowerPurifierTop", 1.2, 0.05, pcf * CF(0, 4.47, 0), lk(rgb(60, 62, 66), M.DiamondPlate))
	local ring = K:box("TowerPurifierLED", V3(0.9, 0.05, 0.04), pcf * CF(0, 3.7, 0.76), neon(C.blue))
	K:text("TowerPurifierDisp", 0.7, 0.24, faceCF(pcf * V3(0, 3.95, 0.765), n), "공기 좋음", { fg = C.blue, glow = 1.4, font = F.GothamBold, d = 0.01 })
	local _ = ring
	return true
end

-- RGB 조명 모드 (홀): 모드별 색 계산 + 패널 프롬프트
local MODES = { "기본", "레이드", "오션", "무지개", "집중" }
local function rgbAnim(K: any, V: any, withPrompt: boolean)
	local P = K.pc
	local mode = 1
	local function hsv(h: number): Color3
		return Color3.fromHSV(h % 1, 0.85, 1)
	end
	Interact.anim(K, function(t)
		for _, r in P.rgb do
			local p = r.p
			if p.Parent then
				local c: Color3 = r.c
				if mode == 1 then
					local br = 0.82 + 0.18 * math.sin(t * 1.2 + (r.z or 0) * 0.15)
					c = r.c:Lerp(BLACK, 1 - br)
				elseif mode == 2 then
					local br = 0.55 + 0.45 * math.abs(math.sin(t * 2.4))
					c = rgb(255, 40, 30):Lerp(BLACK, 1 - br)
				elseif mode == 3 then
					c = C.blue:Lerp(C.cyan, 0.5 + 0.5 * math.sin(t * 1.5 + (r.z or 0) * 0.2))
				elseif mode == 4 then
					c = hsv(t * 0.12 + ((r.z or 0) + (r.x or 0)) * 0.012)
				else
					c = rgb(150, 150, 160)
				end
				if r.text then
					local g = p:FindFirstChildWhichIsA("SurfaceGui")
					local l = g and g:FindFirstChildWhichIsA("TextLabel")
					if l then
						l.TextColor3 = c
					end
				else
					p.Color = c
				end
			end
		end
	end)
	if withPrompt and P.modePanel and promptOK(K, P.modePanel) then
		Interact.cycle(K, P.modePanel, MODES, {
			action = "조명 모드 바꾸기",
			object = "RGB 조명",
			on = function(i: number, name: string)
				mode = i
				if P.modeLabel and P.modeLabel.Parent then
					P.modeLabel.Text = "RGB 조명\n" .. name
				end
			end,
		})
	end
end

------------------------------------------------------------------------------------------------------------
-- 3) 뒤 띠 (pcback) -------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

local function backKeeps(K: any, V: any)
	local P = K.pc
	-- 마지막 줄 의자 뒤 ServePos (방 앞쪽 띠) 전체 폭
	keepBox(V, V.x0, V.z1 - 3.4, V.x1, V.z1 + 0.5, 6.5, "serve")
	-- 홀 가운데 통로 연장 -> 화장실 · 비상구
	keepLane(V, V3(-2.2, 0, V.z1), V3(-2.2, 0, 2.0), 5.0, "walk")
	keepLane(V, V3(-2.2, 0, 2.0), V3(12.0, 0, -5.8), 4.0, "walk")
	keepLane(V, V3(-2.2, 0, 2.0), V3(-25.3, 0, 2.0), 4.0, "walk")
	keepLane(V, V3(-25.3, 0, 2.0), V3(-25.3, 0, -5.6), 4.0, "walk")
	for _, nm in { "RestroomDoor", "ExitDoor" } do
		for _, r in recs(V, nm) do
			local mn, mx = mb(K, r)
			keepBox(V, mn.X - 0.5, P.zb, mx.X + 0.5, P.zb + 4.2, 8.5, "door")
		end
	end
	for _, r in recs(V, "PrinterTable") do
		local mn, mx = mb(K, r)
		keepBox(V, mn.X - 0.2, mx.Z, mx.X + 0.2, mx.Z + 3.0, 6.5, "use")
	end
end

-- 라운지 (루버 벽 + TV + 소파 + 테이블 + 빈백 + 러그 + 펜던트 + 플로어 램프 + 화분)
local function backLounge(K: any, V: any)
	local P = K.pc
	local zb = P.zb
	local x0, x1 = -19.8, -6.4
	local cx = (x0 + x1) / 2
	-- 루버 벽 (따뜻한 월넛 + 뒤 간접등)
	if wallFree(K, "back", x0, x1, 0.5, 9.4) then
		K:free(function()
			local len, hh = x1 - x0, 9.0
			local c = W(K, "back", cx, 0.45 + hh / 2, 0.0)
			K:plate("LoungeLouverBack", len, hh, 0.04, c, lk(rgb(26, 22, 20)))
			local pitch = 0.42
			local n = math.floor(len / pitch)
			for i = 0, n - 1 do
				K:plate("LoungeSlat", pitch * 0.55, hh, 0.16, c * CF(-len / 2 + pitch * (i + 0.5), 0, 0.04), Look.walnut)
			end
			local glow = K:plate("LoungeCove", len - 0.2, 0.06, 0.05, c * CF(0, hh / 2 + 0.1, 0.12), Look.lampWarm)
			K:light(glow, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 0.7, Angle = 150, Color = Look.warmLight })
		end)
		useWall(K, "back", x0, x1, 0.4, 9.6)
	end
	-- TV (채널 바꾸기)
	local tvW = 6.6
	local tvD = W(K, "back", cx, 6.2, 0.2)
	local scr = Props.tv(K, tvD, tvW, { on = true, screen = rgb(20, 40, 80) })
	local _, tvLabel = K:text("TVText", tvW * 0.92, tvW * 9 / 16 * 0.62, tvD * CF(0, 0, 0.27), "LIVE · 광안리 PC방 리그 결승\n2세트 진행 중", { fg = WHITE, glow = 1.5, font = F.GothamBlack })
	local channels = {
		{ "LIVE · 광안리 PC방 리그 결승\n2세트 진행 중", rgb(20, 40, 80) },
		{ "e스포츠 중계\n하이라이트 · 결승 1세트", rgb(60, 14, 50) },
		{ "신작 게임 트레일러\nCOMING SOON", rgb(14, 50, 30) },
		{ "광고 · 신규회원 1시간 무료\n카운터 · 키오스크에서 가입", rgb(70, 40, 10) },
		{ "광안리 날씨 · 맑음 22°C\n광안대교 야경 생중계", rgb(10, 30, 60) },
	}
	if scr and scr.Parent and promptOK(K, scr) then
		Interact.cycle(K, scr, channels, {
			action = "채널 바꾸기",
			object = "라운지 TV",
			on = function(_i: number, ch: any)
				if scr.Parent then
					scr.Color = ch[2]
				end
				if tvLabel.Parent then
					tvLabel.Text = ch[1]
				end
			end,
		})
	end
	K:free(function()
		K:light(scr, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 9, Brightness = 0.6, Angle = 120, Color = rgb(150, 170, 255) })
	end)
	-- LOUNGE 네온 (루버 위)
	K:free(function()
		Props.neonSign(K, W(K, "back", cx + 4.6, 9.7, 0.22), 2.6, 0.7, "LOUNGE", C.amber, { font = F.Michroma, light = false })
		K:text("LoungeKo", 1.6, 0.4, W(K, "back", cx - 4.6, 9.7, 0.22), "휴게실", { fg = lt(C.amber, 0.2), glow = 1.8, font = F.GothamBlack })
	end)
	-- 소파 (벽 쪽, 3인)
	local sofa = facing(V3(cx, 0, zb + 1.45), V3(0, 0, 1))
	if spotN(K, sofa, V3(9.4, 3.8, 2.6), 0) then
		local fab = lk(rgb(64, 66, 72), M.Fabric)
		local fab2 = lk(rgb(54, 56, 62), M.Fabric)
		K:box("SofaPlinth", V3(9.2, 0.25, 2.4), sofa * CF(0, 0.125, 0), lk(rgb(30, 30, 32)))
		K:box("SofaBase", V3(9.2, 1.0, 2.4), sofa * CF(0, 0.75, 0), fab2)
		for i = 0, 2 do
			K:slab("SofaCushion", 2.75, 1.9, 0.5, 0.18, sofa * CF(-2.85 + i * 2.85, 1.5, 0.2), fab)
			K:rbox("SofaBackCushion", V3(2.75, 2.0, 0.6), 0.26, sofa * CF(-2.85 + i * 2.85, 2.55, -0.72) * ANG(math.rad(-10), 0, 0), fab)
		end
		for _, sx in { -1, 1 } do
			K:rbox("SofaArm", V3(0.5, 2.2, 2.4), 0.2, sofa * CF(sx * 4.85, 1.1, 0), fab2)
		end
		K:box("SofaBack", V3(9.2, 2.6, 0.4), sofa * CF(0, 2.0, -1.0), fab2)
		-- 쿠션 2
		K:ell("SofaPillow", V3(1.0, 0.95, 0.35), sofa * CF(-3.6, 2.25, -0.45) * ANG(math.rad(-12), 0.2, 0), lk(C.amber, M.Fabric))
		K:ell("SofaPillow", V3(1.0, 0.95, 0.35), sofa * CF(3.6, 2.25, -0.45) * ANG(math.rad(-12), -0.2, 0), lk(rgb(40, 120, 160), M.Fabric))
	end
	-- 러그 + 낮은 테이블 + 빈백 2
	K:free(function()
		K:box("LoungeRug", V3(11.5, 0.03, 6.2), CF(cx, 0.015, zb + 4.6), lk(rgb(86, 80, 74), M.Fabric))
		K:box("LoungeRugBorder", V3(11.8, 0.02, 6.5), CF(cx, 0.01, zb + 4.6), lk(rgb(40, 38, 36), M.Fabric))
	end)
	local tbl = CF(cx, 0, zb + 4.5)
	if spotN(K, tbl, V3(4.4, 1.5, 1.9), 0) then
		K:slab("LoungeTableTop", 4.2, 1.7, 0.12, 0.3, tbl * CF(0, 1.3, 0), Look.walnut)
		K:box("LoungeTableShelf", V3(3.8, 0.08, 1.3), tbl * CF(0, 0.4, 0), lk(rgb(30, 30, 32)))
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:box("LoungeTableLeg", V3(0.1, 1.24, 0.1), tbl * CF(sx * 1.9, 0.62, sz * 0.66), Look.blackMetal)
			end
		end
		-- 테이블 위: 게임 잡지 · 리모컨 · 음료
		K:box("Magazine", V3(0.9, 0.04, 1.2), tbl * CF(-1.0, 1.38, 0) * ANG(0, 0.2, 0), lk(rgb(220, 60, 60)))
		K:box("Magazine", V3(0.9, 0.04, 1.2), tbl * CF(-0.9, 1.42, 0.05) * ANG(0, -0.15, 0), lk(rgb(40, 140, 220)))
		K:box("Remote", V3(0.2, 0.06, 0.7), tbl * CF(0.6, 1.39, 0.1) * ANG(0, 0.4, 0), lk(rgb(24, 24, 26)))
		drink(K, tbl * CF(1.4, 1.36, -0.2), 3, 0.9)
	end
	for i, bx in { cx - 4.0, cx + 4.0 } do
		local bb = facing(V3(bx, 0, zb + 6.6), V3(0, 0, -1))
		if spotN(K, bb, V3(2.2, 2.2, 2.2), 0) then
			local c = if i == 1 then rgb(200, 60, 120) else rgb(60, 140, 200)
			K:ell("BeanBag", V3(2.1, 1.4, 2.1), bb * CF(0, 0.7, 0), lk(c, M.Fabric))
			K:ell("BeanBagTop", V3(1.5, 0.9, 1.0), bb * CF(0, 1.35, -0.55), lk(dk(c, 0.1), M.Fabric))
		end
	end
	-- 펜던트 3 (따뜻한 글로브)
	K:free(function()
		for i = -1, 1 do
			Props.pendant(K, V3(cx + i * 2.6, P.ceil, zb + 4.5), 3.6, { shade = "globe", dia = 0.9, look = { c = rgb(255, 236, 200), m = M.Glass, t = 0.25 }, light = i == 0, range = 12, bright = 0.6, color = Look.warmLight })
		end
	end)
	-- 아크 플로어 램프 + 화분
	local fl = CF(x0 + 0.6, 0, zb + 3.6)
	if spotN(K, fl, V3(1.0, 6, 1.0), 0) then
		K:disc("FloorLampBase", 0.9, 0.1, fl * CF(0, 0.05, 0), Look.blackMetal)
		local top = fl * V3(0, 6.2, 0)
		K:seg("FloorLampPole", fl * V3(0, 0.1, 0), top, 0.1, Look.blackMetal)
		local tip = fl * V3(1.8, 5.9, 0.4)
		K:seg("FloorLampArc", top, tip, 0.08, Look.blackMetal)
		K:ell("FloorLampShade", V3(0.9, 0.55, 0.9), CF(tip - V3(0, 0.25, 0)), Look.blackMetal)
		K:disc("FloorLampGlow", 0.7, 0.02, CF(tip - V3(0, 0.5, 0)), Look.lampWarm)
	end
	local pl = CF(x1 + 0.4, 0, zb + 1.0)
	if spotN(K, pl, V3(1.6, 4.6, 1.6), 0) then
		Props.floorPlant(K, pl, { kind = "snake", h = 4.4, dia = 1.3 })
	end
end

-- 자판기 2대 (음료 · 전자기기)
local function vending(K: any, pcf: CFrame, kind: string)
	local P = K.pc
	local w, d, h = 3.0, 2.3, 6.6
	local bodyC = if kind == "drink" then rgb(196, 28, 36) else rgb(26, 70, 160)
	K:box("VendBody", V3(w, h, d), pcf * CF(0, h / 2, 0), lk(bodyC, M.SmoothPlastic, { r = 0.04 }))
	local f = pcf * CF(0, 0, d / 2)
	local fd = faceCF(f.Position, f.ZVector)
	-- 진열 창
	local ww, wh = 1.95, 3.9
	local wc = fd * CF(-0.4, 3.95, 0)
	K:plate("VendWindowBack", ww, wh, 0.02, wc, lk(rgb(236, 236, 236)))
	local glow = K:plate("VendWindowLight", ww, 0.06, 0.03, wc * CF(0, wh / 2 - 0.05, 0), Look.lampCool)
	K:light(glow, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 6, Brightness = 0.6, Angle = 130, Color = Look.coolLight })
	local rows = 4
	local btns = {}
	for r = 1, rows do
		local ry = -wh / 2 + wh * (r - 0.6) / rows
		K:plate("VendShelf", ww, 0.05, 0.25, wc * CF(0, ry - 0.05, 0), lk(rgb(200, 200, 204)))
		local n = 5
		for i = 1, n do
			local ix = -ww / 2 + ww * (i - 0.5) / n
			local p = wc * CF(ix, ry, 0.12)
			if kind == "drink" then
				drink(K, CFrame.fromMatrix(p.Position, fd.XVector, YA, fd.ZVector), ((r * 3 + i) % 8) + 1, 0.95)
			else
				local c = ({ rgb(240, 240, 240), rgb(30, 30, 34), rgb(60, 140, 230), rgb(240, 200, 40) })[((r + i) % 4) + 1]
				K:box("VendItem", V3(0.3, 0.55, 0.12), p * CF(0, 0.28, 0), lk(c))
				K:plate("VendItemLabel", 0.22, 0.12, 0.01, p * CF(0, 0.38, 0.06), lk(rgb(30, 30, 30)))
			end
			local b = K:plate("VendPrice", 0.34, 0.12, 0.02, wc * CF(ix, ry - 0.16, 0.26), neon(if kind == "drink" then C.green else C.amber, 0.1))
			table.insert(btns, b)
		end
	end
	K:plate("VendGlass", ww + 0.1, wh + 0.1, 0.02, wc * CF(0, 0, 0.3), { c = rgb(220, 232, 236), m = M.Glass, t = 0.82, r = 0.2 })
	-- 오른쪽 조작부: 지폐 · 동전 · 카드 · 가격 LED · 반환
	local cp = fd * CF(1.0, 3.95, 0)
	K:plate("VendPanel", 0.75, 3.9, 0.04, cp, lk(dk(bodyC, 0.35)))
	K:text("VendLED", 0.62, 0.32, cp * CF(0, 1.4, 0.045), "1,500", { fg = rgb(255, 60, 40), bg = rgb(20, 6, 6), glow = 2, font = F.RobotoMono, d = 0.02 })
	K:plate("VendBill", 0.5, 0.28, 0.06, cp * CF(0, 0.75, 0.04), lk(rgb(30, 30, 32)))
	K:plate("VendBillLED", 0.36, 0.03, 0.065, cp * CF(0, 0.85, 0.04), neon(C.green))
	K:plate("VendCoin", 0.14, 0.32, 0.06, cp * CF(0, 0.15, 0.04), Look.chrome)
	K:plate("VendCard", 0.5, 0.36, 0.06, cp * CF(0, -0.45, 0.04), lk(rgb(40, 40, 44)))
	K:text("VendCardText", 0.44, 0.14, cp * CF(0, -0.45, 0.105), "카드 · 페이", { fg = WHITE, d = 0.01 })
	wdisc(K, "VendReturn", 0.24, 0.05, cp * CF(0, -1.1, 0.04), Look.chrome)
	-- 위 간판 + 아래 꺼내는 곳
	K:text("VendHeader", w - 0.3, 0.55, fd * CF(0, h - 0.36, 0.01), if kind == "drink" then "시원한 음료" else "충전기 · 이어폰", { fg = WHITE, glow = 1.6, font = F.GothamBlack, d = 0.02 })
	K:plate("VendTray", 2.0, 0.75, 0.12, fd * CF(-0.4, 1.0, 0), lk(rgb(20, 20, 22)))
	K:plate("VendTrayFlap", 1.8, 0.5, 0.14, fd * CF(-0.4, 1.05, 0), lk(rgb(50, 50, 54), M.Glass, { t = 0.3 }))
	K:text("VendTrayText", 1.2, 0.18, fd * CF(-0.4, 0.5, 0.01), "꺼내는 곳", { fg = WHITE, d = 0.01 })
	K:box("VendKick", V3(w, 0.4, 0.1), pcf * CF(0, 0.2, d / 2 - 0.02), lk(rgb(20, 20, 22)))
	-- 버튼 깜빡임
	Interact.anim(K, function(t)
		local k = math.floor(t * 2) % math.max(1, #btns) + 1
		for i, b in btns do
			if b.Parent then
				b.Transparency = if i == k then 0.6 else 0.1
			end
		end
	end)
	local _ = P
end

-- 개인 보관함 + 휴대폰 충전함 (보관함 문 열기)
local function lockers(K: any, V: any, x0: number, x1: number)
	local P = K.pc
	local zb = P.zb
	local w = x1 - x0
	local d, h = 1.6, 6.4
	local pcf = facing(V3((x0 + x1) / 2, 0, zb + d / 2 + 0.02), V3(0, 0, 1))
	if not spotN(K, pcf, V3(w, h, d), 0) then
		return
	end
	K:box("LockerBody", V3(w, h, d), pcf * CF(0, h / 2, 0), lk(rgb(48, 50, 56), M.Metal))
	local fd = faceCF((pcf * V3(0, 0, d / 2)), V3(0, 0, 1))
	local cols = 3
	local cw = (w - 0.2) / cols
	local doorM: Model? = nil
	local hingeW: Vector3? = nil
	-- 아래 2줄: 보관함 문 (번호 + 디지털 자물쇠)
	for row = 0, 1 do
		for col = 0, cols - 1 do
			local u = -w / 2 + 0.1 + cw * (col + 0.5)
			local y = 0.4 + row * 2.0 + 1.0
			local num = row * cols + col + 1
			local function build()
				K:plate("LockerDoor", cw - 0.08, 1.92, 0.05, fd * CF(u, y, 0), lk(rgb(70, 74, 82), M.Metal))
				K:plate("LockerVent", cw * 0.5, 0.25, 0.055, fd * CF(u, y + 0.6, 0), lk(rgb(40, 42, 46), M.DiamondPlate))
				K:plate("LockerKeypad", 0.28, 0.4, 0.08, fd * CF(u + cw / 2 - 0.3, y, 0), lk(rgb(20, 20, 24)))
				K:plate("LockerKeypadLED", 0.1, 0.04, 0.09, fd * CF(u + cw / 2 - 0.3, y + 0.14, 0), neon(if num % 3 == 0 then C.red else C.green))
				K:text("LockerNo", 0.36, 0.26, fd * CF(u - cw / 2 + 0.3, y + 0.7, 0.05), string.format("%02d", num), { fg = WHITE, bg = rgb(30, 30, 34), font = F.Michroma, d = 0.01 })
			end
			if row == 0 and col == 0 then
				doorM = K:group("LockerDoor_01", build)
				hingeW = K.cf * (fd * V3(u - cw / 2 + 0.04, 0, 0.03))
			else
				build()
			end
		end
	end
	-- 윗줄: 휴대폰 충전함 (유리문 + 휴대폰 + 충전 LED)
	for col = 0, cols - 1 do
		local u = -w / 2 + 0.1 + cw * (col + 0.5)
		local y = 4.4 + 0.7
		K:plate("ChargeCubby", cw - 0.08, 1.3, 0.02, fd * CF(u, y, 0), lk(rgb(20, 20, 24)))
		K:plate("ChargePhone", 0.36, 0.7, 0.04, fd * CF(u - 0.1, y - 0.1, 0.02) * ANG(0, 0, 0.08), lk(rgb(30, 30, 34), M.Glass))
		K:plate("ChargePhoneScreen", 0.3, 0.6, 0.045, fd * CF(u - 0.1, y - 0.1, 0.02) * ANG(0, 0, 0.08), neon(if col == 1 then C.green else C.blue, 0.4))
		K:plate("ChargeLED", 0.12, 0.05, 0.03, fd * CF(u + cw / 2 - 0.2, y + 0.5, 0), neon(C.green))
		K:plate("ChargeGlass", cw - 0.1, 1.28, 0.06, fd * CF(u, y, 0), glassL(nil, 0.7))
	end
	K:text("LockerHeader", w - 0.2, 0.55, fd * CF(0, h - 0.4, 0.01), "개인 보관함 · 휴대폰 충전", { fg = WHITE, bg = rgb(24, 24, 28), glow = 1.3, font = F.GothamBlack, d = 0.02 })
	K:text("LockerNote", w - 0.4, 0.3, fd * CF(0, 0.2, 0.01), "카운터에서 열쇠 번호 받기 · 무료", { fg = rgb(220, 220, 220), d = 0.01 })
	if doorM and hingeW then
		local m: Model = doorM
		local handle = m:FindFirstChildWhichIsA("BasePart", true)
		if handle and promptOK(K, handle) then
			Interact.swing(K, m, hingeW, YA, -math.rad(105), { object = "개인 보관함 01", openText = "보관함 열기", closeText = "보관함 닫기" })
		end
	end
end

local function backBuild(K: any, V: any)
	local P = K.pc
	local zb = P.zb
	-- 라운지
	backLounge(K, V)
	-- 자판기 2 (벽 쪽, 라운지 오른쪽)
	for i, kind in { "drink", "gadget" } do
		local x = -3.55 + (i - 1) * 3.25
		local pcf = facing(V3(x, 0, zb + 1.2), V3(0, 0, 1))
		if spotN(K, pcf, V3(3.0, 6.6, 2.3), 0.02) then
			vending(K, pcf, kind)
		else
			K:note("vending blocked " .. kind)
		end
	end
	-- 보관함 (화장실 문과 프린터 사이)
	local rx1, px0 = 16.8, 21.2
	for _, r in recs(V, "RestroomDoor") do
		local _, mx = mb(K, r)
		rx1 = math.max(rx1, mx.X)
	end
	for _, r in recs(V, "PrinterTable") do
		local mn = mb(K, r)
		px0 = mn.X
	end
	lockers(K, V, rx1 + 0.55, px0 - 0.15)
	-- 화장실 문: 문틀 · 킥 플레이트 · 밀판 + 사이 손소독기
	K:free(function()
		for _, r in recs(V, "RestroomDoor") do
			local mn, mx, c = mb(K, r)
			local d = faceCF(V3(c.X, 0, mx.Z + 0.01), V3(0, 0, 1))
			local dw, dh = mx.X - mn.X, mx.Y
			K:plate("DoorCasing", 0.25, dh + 0.25, 0.1, d * CF(-dw / 2 - 0.12, (dh + 0.25) / 2, -0.02), Look.darkAlu)
			K:plate("DoorCasing", 0.25, dh + 0.25, 0.1, d * CF(dw / 2 + 0.12, (dh + 0.25) / 2, -0.02), Look.darkAlu)
			K:plate("DoorCasing", dw + 0.5, 0.25, 0.1, d * CF(0, dh + 0.12, -0.02), Look.darkAlu)
			K:plate("DoorKickPlate", dw - 0.3, 0.9, 0.02, d * CF(0, 0.5, 0), Look.brushed)
			K:plate("DoorPushPlate", 0.35, 1.2, 0.02, d * CF(dw / 2 - 0.5, 4.2, 0), Look.brushed)
		end
		local rr = {}
		for _, r in recs(V, "RestroomDoor") do
			local mn, mx = mb(K, r)
			table.insert(rr, { mn = mn, mx = mx })
		end
		table.sort(rr, function(a, b)
			return a.mn.X < b.mn.X
		end)
		if #rr >= 2 and rr[2].mn.X - rr[1].mx.X > 0.8 then
			local sx = (rr[1].mx.X + rr[2].mn.X) / 2
			local d = W(K, "back", sx, 4.2, 0.02)
			K:plate("SanitizerBack", 0.6, 0.9, 0.3, d, lk(rgb(240, 240, 240)))
			K:plate("SanitizerWindow", 0.3, 0.25, 0.32, d * CF(0, 0.15, 0), lk(rgb(120, 180, 220), M.Glass, { t = 0.3 }))
			K:plate("SanitizerNozzle", 0.14, 0.12, 0.42, d * CF(0, -0.42, 0), lk(rgb(200, 200, 200)))
			K:text("SanitizerLabel", 0.8, 0.24, d * CF(0, 0.75, 0), "손 소독제", { fg = rgb(30, 90, 160), bg = WHITE, d = 0.02 })
		end
	end)
	-- 프린터 (맵 상자 프린터 숨기고 복합기)
	for _, r in recs(V, "Printer") do
		local mn, mx, c = mb(K, r)
		hide(K, r)
		K:free(function()
			local b = facing(V3(c.X, mn.Y, c.Z), V3(0, 0, 1))
			K:rbox("MFPBody", V3(2.6, 1.2, 1.9), 0.1, b * CF(0, 0.6, 0), lk(rgb(232, 232, 230)))
			K:box("MFPDrawer", V3(2.4, 0.34, 0.04), b * CF(0, 0.25, 0.95), lk(rgb(210, 210, 208)))
			K:box("MFPDrawerHandle", V3(0.7, 0.06, 0.05), b * CF(0, 0.32, 0.98), lk(rgb(80, 80, 84)))
			K:box("MFPScanner", V3(2.6, 0.3, 1.9), b * CF(0, 1.35, 0), lk(rgb(60, 62, 66)))
			K:box("MFPLid", V3(2.5, 0.06, 1.8), b * CF(0, 1.53, 0), lk(rgb(40, 40, 44)))
			K:box("MFPOutTray", V3(1.8, 0.04, 1.0), b * CF(-0.2, 0.95, 0.4), lk(rgb(200, 200, 198)))
			K:box("MFPPaper", V3(1.5, 0.06, 0.9), b * CF(-0.2, 1.0, 0.45), Look.paper)
			local cp = faceCF(b * V3(0.8, 1.45, 0.96), V3(0, 0, 1)) * ANG(math.rad(-30), 0, 0)
			K:plate("MFPPanel", 0.9, 0.36, 0.04, cp, lk(rgb(30, 30, 34)))
			K:text("MFPLCD", 0.5, 0.22, cp * CF(-0.15, 0, 0.045), "인쇄 대기", { fg = C.cyan, bg = rgb(10, 20, 30), glow = 1.4, d = 0.01 })
			wdisc(K, "MFPStart", 0.14, 0.03, cp * CF(0.32, 0, 0.04), neon(C.green))
			-- 탁상 소품: A4 묶음 · 스테이플러
			K:box("PaperReam", V3(0.9, 0.3, 1.25), CF(mx.X + 0.35, mn.Y + 0.15, c.Z + 0.3), lk(rgb(240, 236, 220)))
			K:box("PaperReamBand", V3(0.92, 0.12, 1.27), CF(mx.X + 0.35, mn.Y + 0.15, c.Z + 0.3), lk(rgb(40, 120, 200)))
			K:box("Stapler", V3(0.25, 0.2, 0.75), CF(mn.X - 0.3, mn.Y + 0.1, c.Z + 0.4), lk(rgb(30, 30, 34)))
		end)
	end
	-- 분리수거 (오른쪽 구석)
	local px1 = 25.2
	for _, r in recs(V, "PrinterTable") do
		local _, mx = mb(K, r)
		px1 = mx.X
	end
	local bins = { { "일반쓰레기", rgb(70, 70, 76) }, { "플라스틱", rgb(40, 120, 220) }, { "캔 · 병", rgb(230, 160, 30) } }
	local bw = math.min(1.15, (P.xr - px1 - 0.5) / 3)
	if bw > 0.8 then
		for i, b in bins do
			local x = px1 + 0.3 + bw * (i - 0.5)
			local pcf = facing(V3(x, 0, zb + 0.82), V3(0, 0, 1))
			if spotN(K, pcf, V3(bw - 0.05, 3.2, 1.5), 0) then
				K:box("RecycleBin", V3(bw - 0.08, 2.8, 1.45), pcf * CF(0, 1.4, 0), lk(dk(b[2], 0.1)))
				K:box("RecycleLid", V3(bw - 0.04, 0.16, 1.5), pcf * CF(0, 2.88, 0), lk(b[2]))
				K:plate("RecycleSlot", bw * 0.6, 0.14, 0.02, faceCF(pcf * V3(0, 2.6, 0.73), V3(0, 0, 1)), lk(rgb(16, 16, 16)))
				K:text("RecycleLabel", bw - 0.2, 0.36, faceCF(pcf * V3(0, 1.9, 0.735), V3(0, 0, 1)), b[1], { fg = WHITE, bg = b[2], font = F.GothamBlack, d = 0.01 })
			end
		end
		K:free(function()
			local d = W(K, "back", px1 + 0.3 + bw * 1.5, 4.6, 0.02)
			K:text("RecycleSign", 3.0, 0.5, d, "분리수거 · 컵라면 국물은 셀프바 싱크에", { fg = WHITE, bg = rgb(0, 130, 80), font = F.GothamBold, d = 0.03 })
		end)
	end
	-- 명예의 전당 · 와이파이 (자판기와 화장실 사이 뒷벽)
	if wallFree(K, "back", 2.0, 6.6, 2.0, 9.6) then
		K:free(function()
			local d = W(K, "back", 4.3, 5.6, 0.02)
			K:plate("FameFrame", 4.2, 3.4, 0.12, d, Look.goldMetal)
			K:plate("FameFace", 3.9, 3.1, 0.14, d, lk(rgb(16, 14, 22)))
			K:text("FameTitle", 3.4, 0.55, d * CF(0, 1.15, 0.145), "명예의 전당 HALL OF FAME", { fg = rgb(255, 210, 90), glow = 1.6, font = F.GothamBlack })
			K:plate("FameRule", 3.4, 0.04, 0.15, d * CF(0, 0.8, 0), neon(rgb(255, 200, 80)))
			K:text("FameBody", 3.5, 2.0, d * CF(0, -0.3, 0.145), "시즌 2 우승 · 광안리 클랜\n준우승 · 민락동 FC\n나이트 레이서 최고 기록 · 좌석 17\n최다 이용 회원 · 1,284시간", { fg = WHITE, glow = 1.2, font = F.GothamBold })
			for _, sx in { -1.7, 1.7 } do
				K:ell("FameStar", V3(0.3, 0.3, 0.06), d * CF(sx, 1.15, 0.16), neon(rgb(255, 210, 90)))
			end
			local wd = W(K, "back", 4.3, 8.4, 0.02)
			K:plate("WifiBack", 3.6, 0.9, 0.05, wd, lk(rgb(14, 14, 18)))
			K:text("WifiText", 3.4, 0.7, wd * CF(0, 0, 0.055), "WiFi  GWANGALLI_PC_5G  ·  비번은 카운터", { fg = C.cyan, glow = 1.6, font = F.GothamBold })
		end)
		useWall(K, "back", 2.0, 6.6, 2.0, 9.6)
	end
	-- 커플석 리뉴얼 안내 A보드 (외부 간판의 '커플석' 이야기)
	local ab = facing(V3(3.6, 0, zb + 3.2), V3(-0.3, 0, 1).Unit)
	if spotN(K, ab, V3(2.0, 3.4, 1.4), 0, "aboard") then
		local tilt = math.rad(12)
		local fr = ab * CF(0, 1.6, 0.35) * ANG(-tilt, 0, 0)
		K:box("ABoardFace", V3(1.8, 3.2, 0.08), fr, Look.blackMetal)
		K:box("ABoardBack", V3(1.8, 3.2, 0.08), ab * CF(0, 1.6, -0.35) * ANG(tilt, 0, 0), Look.blackMetal)
		K:text("ABoardText", 1.55, 2.6, fr * CF(0, 0, 0.045), "커플석\n리뉴얼 중\n\n11월 오픈 예정\n2인 소파 · 32인치 듀얼", { fg = WHITE, bg = rgb(30, 30, 36), font = F.GothamBold, d = 0.01 })
		K:plate("ABoardTape", 1.9, 0.18, 0.012, fr * CF(0, 0.9, 0.05) * ANG(0, 0, 0.35), lk(rgb(250, 200, 30)))
	end
	-- 비상구 문틀 + 유도 + 소화기 (맵 소화기 숨기고 같은 자리)
	K:free(function()
		for _, r in recs(V, "ExitDoor") do
			local mn, mx, c = mb(K, r)
			local d = faceCF(V3(c.X, 0, mx.Z + 0.01), V3(0, 0, 1))
			local dw, dh = mx.X - mn.X, mx.Y
			K:plate("ExitCasing", 0.3, dh + 0.3, 0.1, d * CF(-dw / 2 - 0.15, (dh + 0.3) / 2, -0.02), lk(rgb(40, 110, 70), M.Metal))
			K:plate("ExitCasing", 0.3, dh + 0.3, 0.1, d * CF(dw / 2 + 0.15, (dh + 0.3) / 2, -0.02), lk(rgb(40, 110, 70), M.Metal))
			K:plate("ExitCasing", dw + 0.6, 0.3, 0.1, d * CF(0, dh + 0.15, -0.02), lk(rgb(40, 110, 70), M.Metal))
			K:text("ExitDoorNote", 2.0, 0.4, d * CF(0, 5.6, 0.01), "비상구 · 평소 닫아 두세요", { fg = WHITE, bg = rgb(200, 40, 40), font = F.GothamBold, d = 0.02 })
			K:box("ExitFloorStripe", V3(dw + 0.6, 0.02, 2.2), CF(c.X, 0.012, mx.Z + 1.3), lk(rgb(240, 200, 30)))
			K:box("ExitFloorStripeIn", V3(dw, 0.022, 1.6), CF(c.X, 0.014, mx.Z + 1.3), lk(rgb(30, 30, 30)))
		end
	end)
	for _, r in recs(V, "FireExtinguisher") do
		local _, _, c = mb(K, r)
		hide(K, r)
		for _, q in recs(V, "ExtinguisherValve") do
			hide(K, q)
		end
		K:free(function()
			extinguisher(K, W(K, "back", c.X, 0, 0.02))
		end)
	end
	-- 왼쪽 벽: 광안대교 네온 (탑 2 + 주케이블 + 행어 + 상판) + 문구
	if P.has.left then
		K:free(function()
			local u0 = -(zb + 0.6) -- 왼쪽 벽 u = -z
			local u1 = -(V.z1 - 3.6)
			local len = math.abs(u1 - u0)
			local uc = (u0 + u1) / 2
			local dcf = W(K, "left", uc, 0, 0.1)
			K:plate("BridgeMuralBack", len, 6.4, 0.03, dcf * CF(0, 5.4, -0.02), lk(rgb(14, 16, 28)))
			local deckY = 3.6
			local span = len - 1.0
			local tA, tB = -span * 0.28, span * 0.28
			local col = C.cyan
			local parts = {}
			table.insert(parts, K:plate("BridgeDeck", span, 0.1, 0.06, dcf * CF(0, deckY, 0), neon(col)))
			for _, tx in { tA, tB } do
				table.insert(parts, K:plate("BridgeTower", 0.12, 4.4, 0.06, dcf * CF(tx - 0.25, deckY + 1.6, 0), neon(col)))
				table.insert(parts, K:plate("BridgeTower", 0.12, 4.4, 0.06, dcf * CF(tx + 0.25, deckY + 1.6, 0), neon(col)))
				table.insert(parts, K:plate("BridgeTowerBeam", 0.6, 0.1, 0.06, dcf * CF(tx, deckY + 3.4, 0), neon(col)))
			end
			-- 주케이블 (포물선 근사 조각)
			local topY = deckY + 3.7
			local function cable(a: number, b: number, sag: number)
				local n = 8
				for i = 0, n - 1 do
					local s0, s1 = i / n, (i + 1) / n
					local x0, x1 = a + (b - a) * s0, a + (b - a) * s1
					local y0 = topY - sag * 4 * s0 * (1 - s0)
					local y1 = topY - sag * 4 * s1 * (1 - s1)
					local pa = (dcf * CF(x0, y0, 0.03)).Position
					local pb = (dcf * CF(x1, y1, 0.03)).Position
					local p = K:bar("BridgeCable", pa, pb, 0.06, 0.06, neon(C.magenta))
					if p then
						table.insert(parts, p)
					end
				end
			end
			cable(tA, tB, 3.4)
			-- 옆 경간 (탑 -> 끝, 반 포물선)
			for _, e in { { tA, -span / 2 }, { tB, span / 2 } } do
				local pa = (dcf * CF(e[1], topY, 0.03)).Position
				local pb = (dcf * CF(e[2], deckY + 0.3, 0.03)).Position
				local p = K:bar("BridgeCable", pa, pb, 0.06, 0.06, neon(C.magenta))
				if p then
					table.insert(parts, p)
				end
			end
			-- 행어 (세로선)
			for i = 1, 7 do
				local s = i / 8
				local x = tA + (tB - tA) * s
				local y = topY - 3.4 * 4 * s * (1 - s)
				if y - deckY > 0.3 then
					K:plate("BridgeHanger", 0.04, y - deckY, 0.05, dcf * CF(x, (y + deckY) / 2, 0), neon(lt(C.cyan, 0.3), 0.3))
				end
			end
			-- 바다 물결 + 문구
			K:plate("BridgeSea", span, 0.06, 0.05, dcf * CF(0, deckY - 0.7, 0), neon(C.blue, 0.4))
			K:plate("BridgeSea", span * 0.8, 0.05, 0.05, dcf * CF(0.5, deckY - 1.1, 0), neon(C.blue, 0.55))
			K:text("BridgeText", span * 0.7, 0.8, dcf * CF(0, deckY - 1.85, 0.02), "GWANGALLI PC · 광안리의 밤은 길다", { fg = WHITE, glow = 1.8, font = F.GothamBlack })
			for _, p in parts do
				table.insert(P.rgb, { p = p, c = p.Color, x = 0, z = 0 })
			end
		end)
	end
	-- 오른쪽 벽: 이용 안내 · 옥내소화전 · 비상벨 · 분실물 안내
	if P.has.right then
		K:free(function()
			local zc = zb + 4.5
			notice(K, W(K, "right", zc, 5.6, 0.02), 3.2, 3.4, "PC방 이용 수칙", "1. 자리 비움 30분 초과 시 자동 종료\n2. 외부 음식 반입 금지\n3. 귀중품 분실 책임지지 않습니다\n4. 22시 이후 청소년 출입 제한\n5. 음식 주문은 모니터 하단 메뉴", rgb(30, 100, 210), { align = "Left" })
			-- 옥내소화전
			local hd = W(K, "right", zc + 4.2, 2.6, 0.02)
			K:plate("HydrantBox", 1.8, 2.6, 0.35, hd, lk(rgb(200, 30, 30)))
			K:plate("HydrantDoor", 1.6, 2.0, 0.37, hd * CF(0, -0.15, 0), Look.steel)
			K:text("HydrantText", 1.4, 0.4, hd * CF(0, 0.95, 0.36), "소화전", { fg = WHITE, font = F.GothamBlack, d = 0.01 })
			K:plate("HydrantHandle", 0.1, 0.5, 0.42, hd * CF(0.6, -0.15, 0), Look.chrome)
			Props.fireBell(K, W(K, "right", zc + 4.2, 4.6, 0.02))
			notice(K, W(K, "right", zc - 3.4, 5.0, 0.02), 1.7, 2.0, "분실물 보관", "분실물은 카운터에서\n7일간 보관합니다", rgb(90, 90, 100))
		end)
	end
	-- 천장: 뒷벽 위 RGB · 스피커 · 스프링클러 · 감지기
	K:free(function()
		local p = K:plate("BackWallRGB", V.W - 3, 0.07, 0.05, W(K, "back", 0, P.ceil - 0.35, 0.02), neon(C.purple))
		table.insert(P.rgb, { p = p, c = C.purple, x = 0, z = 0 })
		speaker(K, W(K, "back", -24, 9.6, 0.02), 16)
		speaker(K, W(K, "back", 26.5, 9.6, 0.02), 16)
	end)
	for _, p in { { -22, -2 }, { -8, 1 }, { 4, -4 }, { 18, 0 }, { 25, 3 } } do
		sprinkler(K, p[1], p[2])
	end
	detector(K, -14, -1)
	detector(K, 12, 2)
	dome(K, V.x0 + 2.0, zb + 2.0)
	-- 바닥: 카펫 줄눈
	carpetSeams(K, P.xl, P.xr, zb, V.z1, 3.3, lk(rgb(46, 48, 53), M.Carpet))
end

------------------------------------------------------------------------------------------------------------
-- 스타일 · 빌드 ---------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

function T.style(V: any): any
	-- Common 은 전부 건너뜀: 이 건물은 바닥 0.1 아래 · 0.375° 회전이라 공통 마감(방 프레임)이 떠 보임 -> 직접 함
	return {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" },
		skip = { floor = true, ceiling = true, walls = true, chairs = true, stools = true, tables = true, counters = true, upgrades = true, fixtures = true },
	}
end

local function step(K: any, name: string, fn: (any, any) -> (), V: any)
	local ok, err = pcall(fn, K, V)
	if not ok then
		K:note("pc." .. name .. " error: " .. tostring(err))
	end
end

function T.build(K: any, V: any, S: any)
	measure(K, V)
	K.pc.rgb = {}
	local t = V.type
	if t == "pcbang" then
		step(K, "keeps", frontKeeps, V)
		step(K, "kitchen", frontKitchen, V)
		step(K, "stock", frontStock, V)
		step(K, "counter", frontCounter, V)
		step(K, "kiosk", frontKiosk, V)
		step(K, "selfbar", frontSelfBar, V)
		step(K, "smoking", frontSmoking, V)
		step(K, "lobby", frontLobby, V)
		step(K, "ceiling", frontCeiling, V)
		-- 실시간 좌석 현황 · 주문 현황 · 라면 김 · 타이머
		local pcs = pcModels(V)
		local P = K.pc
		local lastSeat = -100
		Interact.anim(K, function(tt)
			if tt - lastSeat >= 2 then
				lastSeat = tt
				local used = usedSeats(pcs)
				local tot = math.max(#pcs, 48)
				for _, s in P.seatLabels or {} do
					if s.l.Parent then
						s.l.Text = string.format(s.fmt, used, tot - used)
					end
				end
			end
			for _, tm in P.timers or {} do
				if tm.l.Parent then
					local left = math.max(0, tm.s - math.floor(tt) % (tm.s + 20))
					tm.l.Text = string.format("%02d:%02d", left // 60, left % 60)
				end
			end
			for _, s in P.steam or {} do
				if s.p.Parent then
					local ph = (tt * 0.6 + s.k * 0.33) % 1
					s.p.CFrame = s.cf * CF(math.sin(tt + s.k) * 0.06, ph * 0.9, 0)
					s.p.Transparency = 0.6 + 0.38 * ph
				end
			end
			if P.orderLabel and P.orderLabel.Parent then
				local k = math.floor(tt / 6) % 3
				local seat = { 17, 32, 5 }
				local food = { "컵라면", "핫도그", "짜파게티" }
				P.orderLabel.Text = string.format("주문 현황\n조리중  %02d번 %s\n완료  %02d번 %s", seat[k + 1], food[k + 1], seat[(k + 2) % 3 + 1], food[(k + 2) % 3 + 1])
			end
		end)
		rgbAnim(K, V, false)
	elseif t == "pchall" then
		local st = stations(K, V)
		step(K, "keeps", function(k, v)
			hallKeeps(k, v, st)
		end, V)
		step(K, "walls", hallWalls, V)
		step(K, "ceiling", hallCeiling, V)
		step(K, "floor", hallFloor, V)
		step(K, "rows", hallRows, V)
		step(K, "stations", function(k, v)
			hallStations(k, v, st)
		end, V)
		step(K, "purifiers", function(k, v)
			local P = k.pc
			local x = P.xr - 1.1
			floorPurifier(k, x, 12.6, V3(-1, 0, 0))
			floorPurifier(k, x, -16.6, V3(-1, 0, 0))
			local _ = v
		end, V)
		rgbAnim(K, V, true)
	elseif t == "pcback" then
		step(K, "keeps", backKeeps, V)
		step(K, "build", backBuild, V)
		rgbAnim(K, V, false)
	end
	local _ = S
end

return T
