--!strict
-- GwangalliBuildingInterior/T_arcade: 큰 시설 방 유형 (arcade · stairlobby · photo · bowarcade) 실내.
--   arcade     광안 게임랜드 1F 오락실 홀 (74x79): 대전 격투 · 레트로 · 건슈팅 · 태고 · 두더지 · 댄스(펌프식) · 경품 존 ·
--              가챠 벽 · 키디라이드 · 휴게 존 + 기존 기계 오버레이 (인형뽑기 LED · 레트로 베젤 · 레이싱 버킷 ·
--              댄스 화살표 · 자판기 앞면 · 동전교환기 · 에어하키 · 경품 카운터) + 우주 카펫 · 천장 스피커 · 존 사인 · 벽 포스터
--   stairlobby 게임랜드 빌딩 계단 로비: 논슬립 · 핸드레일 · 계단 센서등 · 2F/3F 방화문 · 층별 안내 · 방탈출/보드게임 포스터
--   photo      셀프사진관 찰칵: 촬영 부스 (커튼 · 카메라 · 링라이트 · 배경지 · 결제 키오스크) · 파우더룸 · 소품 카트 ·
--              샘플 사진 벽 · 카운터 오버레이 (알바생 자리 그대로)
--   bowarcade  락볼링 오락코너 (22x26, 천장 21.9): 인생사진 부스 속을 비워 다시 짓기 · 대전 기계 2대 · 키디라이드 · 가챠 ·
--              매달린 LED 프레임 · 네온 벽화 · 카펫 무늬 · 기존 기계 오버레이
--
-- 맵 건물이 방 프레임에서 약 1도 돌아가 있어서 (게임랜드 -1.07도 · 볼링장 +0.95도) 벽 · 바닥 소품은 전부
-- '정렬 프레임' R.A (바닥 파트의 회전) 기준으로 짓고, 벽 안쪽 면은 모델의 벽 파트를 읽어 다시 잽니다 (makeRoom).
-- 게임플레이 계약 (arcade_club.json / bowling.json):
--   펀치기계 · BasketballMachine_1/2 · 농구게임 · ClawMachine_NN(PrizeDoor) · LEDScreen · ScoreDisplay · Spot_bowl_punch ·
--   Board_punch · StoolSeat/RacingSeat/SeatBase/Step · ShopFloor/Counter 는 숨기거나 옮기지 않음 (덧붙이기만).
--   팔씨름 테이블 후보 4곳 (서버가 빈 곳에 지음) · 펀치/농구 서 있는 자리 · 벽 점수판 레이캐스트 자리는 keep 로 비워 둠.
--   숨기는 것: 카펫 색종이 (CarpetConfetti) · 자판기 Display/Can · 오락코너 인생사진 BoothBody/Curtain (속을 다시 지음).

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "arcade", "stairlobby", "photo", "bowarcade" }

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
local function hsv(h: number, s: number, v: number): Color3
	return Color3.fromHSV(h % 1, s, v)
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

-- 정렬 프레임 · 벽 ----------------------------------------------------------------------------------------
local FLOORS = { SpaceCarpet = true, ShopFloor = true, LobbyFloor = true, Floor_Arcade = true }
local FRONTS = { ShopWindow = true, Window = true, ShopGlass = true, Door = true, GlassDoor = true }

-- 모델 밖 (외벽 모델) 에 벽이 있는 방의 벽 안쪽 면 (정렬 프레임, 맵에서 잼)
local ROOM_OVERRIDES: { [string]: any } = {
	bowarcade = { x0 = -10.03, z1 = 12.36 },
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

-- R = { K, V, A (회전만), x0 x1 z0 z1 (정렬 프레임의 벽 안쪽 면), cx cz W D H, hosts (서버 프롬프트 자리, 정렬 xz) }
local function makeRoom(K: any, V: any): any
	local yaw: number? = nil
	for _, r in V.parts do
		if FLOORS[r.name] then
			yaw = yawOf(r.lcf)
			break
		end
	end
	if yaw == nil then
		-- 바닥이 다른 모델에 있으면 (볼링장 오락코너) 큰 파트들의 회전 최빈값
		local w: { [number]: number } = {}
		local best, bw = 0, -1
		for _, r in V.parts do
			local s = r.part.Size
			if s.X * s.Z > 1 and not r.shell then
				local a = math.floor(yawOf(r.lcf) * 500 + 0.5)
				w[a] = (w[a] or 0) + s.X * s.Z
				if w[a] > bw then
					best, bw = a, w[a]
				end
			end
		end
		yaw = best / 500
	end
	local A = ANG(0, yaw :: number, 0)
	local R: any = { K = K, V = V, A = A, yaw = yaw, hosts = {} }
	local bx0, bx1, bz0, bz1 = V.x0, V.x1, V.z0, V.z1
	local x0, x1, z0, z1 = bx0, bx1, bz0, bz1
	local bestL, bestR, bestB, bestF = -math.huge, math.huge, -math.huge, math.huge
	local ok = pcall(function()
		for _, d in V.model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.8 then
				local lc = A:ToObjectSpace(V.cf:ToObjectSpace(d.CFrame))
				local mn, mx = Kit.laabb(lc, d.Size)
				local h = mx.Y - mn.Y
				if h >= 2.5 and mn.Y < 3 and mx.Y > 1.5 then
					local sx, sz = mx.X - mn.X, mx.Z - mn.Z
					local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
					local front = FRONTS[d.Name] == true
					if sx <= 1.8 and not front then
						local ov = math.min(mx.Z, bz1) - math.max(mn.Z, bz0)
						if ov >= 0.4 * (bz1 - bz0) then
							if cx > bx0 - 2.5 and cx < bx0 + 2.0 and mx.X <= bx0 + 2.0 and mx.X > bestL then
								bestL = mx.X
							elseif cx < bx1 + 2.5 and cx > bx1 - 2.0 and mn.X >= bx1 - 2.0 and mn.X < bestR then
								bestR = mn.X
							end
						end
					end
					if sz <= 1.8 then
						local ov = math.min(mx.X, bx1) - math.max(mn.X, bx0)
						if not front and ov >= 0.4 * (bx1 - bx0) and cz > bz0 - 2.5 and cz < bz0 + 2.0 and mx.Z <= bz0 + 2.0 and mx.Z > bestB then
							bestB = mx.Z
						end
						if front and h >= 4 and ov > 0 and cz < bz1 + 2.5 and cz > bz1 - 2.0 and mn.Z >= bz1 - 2.0 and mn.Z < bestF then
							bestF = mn.Z
						end
					end
				end
			end
		end
	end)
	if ok then
		if bestL > -math.huge then
			x0 = bestL
		end
		if bestR < math.huge then
			x1 = bestR
		end
		if bestB > -math.huge then
			z0 = bestB
		end
		if bestF < math.huge then
			z1 = bestF
		end
	end
	-- 벽이 다른 모델에 있는 방 (볼링장 1층_외벽): 잰 값 (정렬 프레임)
	local OVR = ROOM_OVERRIDES[V.type or ""]
	if OVR then
		if bestL == -math.huge and OVR.x0 then
			x0, bestL = OVR.x0, OVR.x0
		end
		if bestF == math.huge and OVR.z1 then
			z1, bestF = OVR.z1, OVR.z1
		end
	end
	R.x0, R.x1, R.z0, R.z1 = x0, x1, z0, z1
	R.cx, R.cz = (x0 + x1) / 2, (z0 + z1) / 2
	R.W, R.D, R.H = x1 - x0, z1 - z0, V.H
	R.open = { left = bestL == -math.huge, right = bestR == math.huge, back = bestB == -math.huge, front = bestF == math.huge }
	K:note(string.format("aligned yaw=%.4f x %.2f..%.2f z %.2f..%.2f", yaw, x0, x1, z0, z1))
	return R
end

-- 정렬 프레임 → 방 프레임
local function at(R: any, x: number, z: number, yaw: number?, y: number?): CFrame
	return R.A * CF(x, y or 0, z) * ANG(0, yaw or 0, 0)
end
local function ap(R: any, x: number, y: number, z: number): Vector3
	return R.A * V3(x, y, z)
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
-- 맵 파트 (V.parts 의 rec) 의 정렬 프레임 AABB · 중심
local function abox(R: any, rec: any): (Vector3, Vector3)
	return Kit.laabb(R.A:ToObjectSpace(rec.lcf), rec.part.Size)
end
local function acen(R: any, rec: any): Vector3
	return R.A:PointToObjectSpace(rec.lcf.Position)
end
-- 정렬 프레임 상자 → keep (방 프레임 AABB)
local function keepBox(R: any, x0: number, z0: number, x1: number, z1: number, y1: number, kind: string)
	local c = R.A * CF((x0 + x1) / 2, (0.1 + y1) / 2, (z0 + z1) / 2)
	local mn, mx = Kit.laabb(c, V3(x1 - x0, y1 - 0.1, z1 - z0))
	R.V:addKeep(mn, mx, kind)
end
local function host(R: any, x: number, z: number)
	table.insert(R.hosts, V3(x, 0, z))
end
local function farFromHosts(R: any, p: Vector3, d: number?): boolean
	local q = R.A:PointToObjectSpace(p)
	for _, h in R.hosts do
		if (V3(q.X, 0, q.Z) - h).Magnitude < (d or 6.6) then
			return false
		end
	end
	return true
end

-- 바닥 소품 자리 (정렬 프레임 벽 기준; Kit:spot 과 같지만 숨긴 맵 파트 · 바닥 스티커는 무시)
local function place(R: any, pcf: CFrame, size: Vector3, pad: number?, kind: string?): boolean
	local K, V = R.K, R.V
	local p = pad or 0
	local c = pcf * CF(0, size.Y / 2, 0)
	local mn, mx = Kit.laabb(c, size + V3(2 * p, 0, 2 * p))
	local amn, amx = Kit.laabb(R.A:ToObjectSpace(c), size)
	if amn.X < R.x0 - 0.05 or amx.X > R.x1 + 0.05 or amn.Z < R.z0 - 0.05 or amx.Z > R.z1 + 0.05 then
		return false
	end
	if K:hitsKeep(mn, mx) then
		return false
	end
	for _, s in V.solid do
		if not K.hidden[s.part] and not (s.size.Y < 0.15 and s.max.Y < 0.2) and Kit.overlap(mn, mx, s.min, s.max, 0.04) then
			return false
		end
	end
	for _, r in K.reserved do
		if Kit.overlap(mn, mx, r.min, r.max, 0.02) then
			return false
		end
	end
	table.insert(K.reserved, { min = mn, max = mx, kind = kind or "prop" })
	return true
end

-- 프롬프트 (서버 앵커와 6.6 이상 떨어진 곳만)
local function prompt(R: any, part: BasePart?, kind: string, spec: any, items: { any }?): ProximityPrompt?
	if not part or part.Parent == nil then
		return nil
	end
	local lp = R.V.cf:PointToObjectSpace(part.Position)
	if not farFromHosts(R, lp) then
		R.K:note("prompt skipped near arcade host: " .. tostring(spec.object))
		return nil
	end
	if kind == "toggle" then
		return Interact.toggle(R.K, part, spec)
	elseif kind == "cycle" then
		return Interact.cycle(R.K, part, items or {}, spec)
	end
	return Interact.prompt(R.K, part, spec)
end

local function tween(p: BasePart, goal: { [string]: any }, t: number?)
	if p.Parent then
		TweenService:Create(p, TweenInfo.new(t or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	end
end

-- 공통 소형 소품 ------------------------------------------------------------------------------------------
-- 둥근 스툴 (4 파트): pcf 바닥, 좌판 높이 top
local function stool(K: any, pcf: CFrame, top: number, seat: Color3?)
	K:disc("StoolFoot", 1.1, 0.08, pcf * CF(0, 0.04, 0), Look.blackMetal)
	K:vcyl("StoolPole", top - 0.3, 0.16, pcf * CF(0, (top - 0.3) / 2 + 0.06, 0), Look.chrome)
	K:disc("StoolRing", 0.8, 0.06, pcf * CF(0, top * 0.38, 0), Look.chrome)
	K:disc("StoolCushion", 1.2, 0.26, pcf * CF(0, top - 0.13, 0), lk(seat or rgb(196, 28, 40), M.Leather))
end

-- 포스터 (액자 없는 인쇄 포스터 + 얇은 아크릴): dcf, w, h, o = { bg, a1, a2, title, sub, fg, tag }
local function poster(K: any, dcf: CFrame, w: number, h: number, o: any)
	local bg: Color3 = o.bg or rgb(20, 18, 40)
	K:plate("PosterBack", w, h, 0.03, dcf, lk(bg))
	local a1: Color3 = o.a1 or rgb(255, 60, 140)
	local a2: Color3 = o.a2 or rgb(60, 220, 255)
	-- 사선 띠 2개 (게임 포스터 느낌)
	K:plate("PosterBand", w * 1.05, h * 0.16, 0.035, dcf * CF(0, h * 0.06, 0) * ANG(0, 0, 0.32), lk(a1))
	K:plate("PosterBand", w * 1.05, h * 0.07, 0.036, dcf * CF(0, -h * 0.08, 0) * ANG(0, 0, 0.32), lk(a2))
	if o.disc then
		wdisc(K, "PosterDisc", math.min(w, h) * 0.42, 0.037, dcf * CF(w * 0.2, h * 0.18, 0), lk(o.disc))
	end
	txt(K, "PosterTitle", w * 0.92, h * 0.24, dcf * CF(0, h * 0.3, 0.04), o.title or "", o.fg or WHITE, nil, o.font or F.GothamBlack)
	if o.sub then
		txt(K, "PosterSub", w * 0.9, h * 0.26, dcf * CF(0, -h * 0.3, 0.04), o.sub, o.fg2 or rgb(255, 236, 120), nil, F.GothamBold)
	end
	if o.tag then
		txt(K, "PosterTag", w * 0.5, h * 0.07, dcf * CF(-w * 0.2, -h * 0.46, 0.04), o.tag, rgb(230, 230, 230), nil, F.Gotham)
	end
	K:plate("PosterAcrylic", w + 0.06, h + 0.06, 0.02, dcf * CF(0, 0, 0.05), gl(rgb(240, 244, 248), 0.9))
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			wdisc(K, "PosterPin", 0.1, 0.03, dcf * CF(sx * (w / 2 - 0.08), sy * (h / 2 - 0.08), 0.07), Look.chrome)
		end
	end
end

-- 안내문 (흰 판 + 색 머리띠 + 본문): dcf, w, h, title, body, head 색
local function notice(K: any, dcf: CFrame, w: number, h: number, title: string, body: string, head: Color3?, o: any?)
	local op: any = o or {}
	K:plate("NoticeBoard", w, h, 0.04, dcf, lk(op.bg or rgb(250, 250, 246)))
	local hh = math.min(h * 0.24, 0.8)
	K:plate("NoticeHead", w, hh, 0.045, dcf * CF(0, h / 2 - hh / 2, 0), lk(head or rgb(220, 40, 50)))
	txt(K, "NoticeTitle", w * 0.92, hh * 0.78, dcf * CF(0, h / 2 - hh / 2, 0.05), title, WHITE, nil, F.GothamBlack)
	txt(K, "NoticeBody", w * 0.9, (h - hh) * 0.86, dcf * CF(0, -hh / 2, 0.05), body, op.fg or rgb(34, 34, 40), nil, op.font or F.GothamMedium, nil, { wrap = op.wrap })
	if op.frame ~= false then
		K:plate("NoticeFrame", w + 0.1, h + 0.1, 0.03, dcf * CF(0, 0, -0.005), op.frameL or Look.alu)
	end
end

-- 천장 스피커 (원형 매입) · 스프링클러 · 감지기
local function ceilSpeaker(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("CeilSpeakerTrim", 1.1, 0.04, at(R, x, z, 0, y - 0.02), Look.white)
		K:disc("CeilSpeakerGrille", 0.92, 0.03, at(R, x, z, 0, y - 0.045), lk(rgb(58, 58, 62), M.DiamondPlate))
	end)
end
local function sprinkler(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("SprinklerRose", 0.32, 0.03, at(R, x, z, 0, y - 0.015), Look.white)
		K:vcyl("SprinklerBody", 0.2, 0.12, at(R, x, z, 0, y - 0.12), Look.brass)
	end)
end
local function smoke(K: any, R: any, x: number, z: number)
	local y = R.H
	K:free(function()
		K:disc("SmokeDetector", 0.55, 0.14, at(R, x, z, 0, y - 0.07), Look.white)
		K:disc("SmokeDetectorLED", 0.06, 0.02, at(R, x + 0.16, z, 0, y - 0.15), Look.ledRed)
	end)
end

-- 매달린 존 사인 (양면): 정렬 x, z, 아래 높이 y, 폭 w, yaw (0 = 앞뒤가 ±z)
local function zoneSign(K: any, R: any, x: number, z: number, y: number, w: number, yaw: number, title: string, sub: string, c: Color3)
	local h = 1.5
	local base = at(R, x, z, yaw, y + h / 2)
	K:free(function()
		for _, sx in { -1, 1 } do
			local a = (base * CF(sx * (w / 2 - 0.4), h / 2, 0)).Position
			local b = a + R.A:VectorToWorldSpace(V3(0, R.H - (y + h), 0))
			K:seg("ZoneSignRod", a, b, 0.06, Look.blackMetal)
		end
		K:box("ZoneSignBox", V3(w, h, 0.3), base, Look.black)
		K:box("ZoneSignEdge", V3(w + 0.08, 0.08, 0.34), base * CF(0, -h / 2, 0), nl(c))
		K:box("ZoneSignEdge", V3(w + 0.08, 0.08, 0.34), base * CF(0, h / 2, 0), nl(c))
		for _, s in { 1, -1 } do
			local d = base * CF(0, 0.12, s * 0.16) * (if s < 0 then ANG(0, PI, 0) else CFrame.new())
			txt(K, "ZoneSignTitle", w * 0.9, h * 0.52, d, title, c, nil, F.GothamBlack, 1.6)
			txt(K, "ZoneSignSub", w * 0.86, h * 0.26, d * CF(0, -h * 0.42, 0), sub, WHITE, nil, F.GothamBold, 1.2)
		end
	end)
end

-- 카펫 무늬 (블랙라이트 우주 카펫): 정렬 프레임 (x0..x1, z0..z1) 격자에 별 · 행성 · 고리 · 지그재그. avoid = 함수(pmin, pmax)
local CARPET_COLS = { rgb(255, 70, 170), rgb(60, 230, 255), rgb(255, 220, 60), rgb(120, 255, 120), rgb(170, 110, 255), rgb(255, 140, 50) }
local function carpetPrint(K: any, R: any, x0: number, x1: number, z0: number, z1: number, step: number, seed: number)
	local V = R.V
	local function covered(cx: number, cz: number, r: number): boolean
		local c = R.A * V3(cx, 0.05, cz)
		local mn, mx = c - V3(r, 0, r), c + V3(r, 0.3, r)
		for _, s in V.solid do
			if not K.hidden[s.part] and s.max.Y > 0.3 and Kit.overlap(mn, mx, s.min, s.max, 0) then
				return true
			end
		end
		for _, rr in K.reserved do
			if Kit.overlap(mn, mx, rr.min, rr.max, 0) then
				return true
			end
		end
		return false
	end
	local i = 0
	local z = z0 + step / 2
	while z < z1 do
		local x = x0 + step / 2
		while x < x1 do
			i += 1
			local px = x + (rnd(seed, i) - 0.5) * step * 0.6
			local pz = z + (rnd(seed + 7, i) - 0.5) * step * 0.6
			if not covered(px, pz, 0.9) then
				local col = CARPET_COLS[(i + seed) % #CARPET_COLS + 1]
				local kind = math.floor(rnd(seed + 3, i) * 5)
				local rot = rnd(seed + 11, i) * PI
				local c = at(R, px, pz, rot, 0.012)
				K:free(function()
					if kind == 0 then
						-- 4각 별
						K:box("CarpetStar", V3(1.1, 0.012, 0.16), c, lk(col, M.Fabric))
						K:box("CarpetStar", V3(0.16, 0.012, 1.1), c, lk(col, M.Fabric))
					elseif kind == 1 then
						-- 행성 + 고리
						K:disc("CarpetPlanet", 0.9, 0.012, c, lk(col, M.Fabric))
						K:box("CarpetRing", V3(1.7, 0.014, 0.12), c * ANG(0, 0.5, 0), lk(CARPET_COLS[(i + seed + 2) % #CARPET_COLS + 1], M.Fabric))
					elseif kind == 2 then
						-- 지그재그 번개
						K:box("CarpetZig", V3(0.9, 0.012, 0.14), c * CF(-0.3, 0, 0) * ANG(0, 0.6, 0), lk(col, M.Fabric))
						K:box("CarpetZig", V3(0.9, 0.012, 0.14), c * CF(0.3, 0, 0.1) * ANG(0, -0.6, 0), lk(col, M.Fabric))
					elseif kind == 3 then
						-- 동그라미 3개
						for j = 0, 2 do
							K:disc("CarpetDot", 0.32 - j * 0.06, 0.012, c * CF(j * 0.5 - 0.5, 0, (j % 2) * 0.35), lk(CARPET_COLS[(i + j) % #CARPET_COLS + 1], M.Fabric))
						end
					else
						-- 고리 (도넛)
						K:disc("CarpetDonut", 0.8, 0.012, c, lk(col, M.Fabric))
						K:disc("CarpetDonutHole", 0.42, 0.014, c, lk(rgb(26, 22, 58), M.Fabric))
					end
				end)
			end
			x += step
		end
		z += step
	end
end

-- 기계 빌더 (pcf = 바닥 가운데, +Z = 손님 쪽) -------------------------------------------------------------
-- 1) 캔디 캐비닛 (대전 격투 · 레트로 50in1): 폭 2.9, 깊이 3.0 (등 -1.6 .. 패널 +1.4), 높이 5.9
--    o = { body, accent, title, screen, scr (화면색), sub, stool (true), coin ("500원") }  반환 { screen, label, marquee }
local function candy(K: any, pcf: CFrame, o: any): any
	local W = 2.9
	local body: Color3 = o.body or rgb(238, 236, 230)
	local acc: Color3 = o.accent or rgb(220, 36, 52)
	local dark = lk(rgb(24, 24, 28))
	local out: any = {}
	-- 하부 (코인 도어 · 발판)
	K:box("CandyBase", V3(W, 2.3, 2.6), pcf * CF(0, 1.15, -0.3), lk(body))
	K:box("CandyKick", V3(W - 0.1, 0.34, 0.06), pcf * CF(0, 0.17, 1.02), dark)
	K:box("CandyDoor", V3(1.15, 1.05, 0.05), pcf * CF(0, 1.2, 1.02), Look.darkAlu)
	for _, x in { -0.27, 0.27 } do
		K:box("CandyCoinSlot", V3(0.08, 0.28, 0.03), pcf * CF(x, 1.47, 1.06), nl(rgb(255, 70, 40)))
		if hi(K) then
			K:box("CandyCoinReturn", V3(0.24, 0.12, 0.03), pcf * CF(x, 1.0, 1.06), Look.chrome)
		end
	end
	txt(K, "CandyCoinLabel", 1.0, 0.18, pcf * CF(0, 1.66, 1.05), o.coin or "500원", WHITE, nil, F.GothamBold)
	-- 조작 패널 (앞으로 기울어진 판 + 레버 · 버튼 6 + 스타트)
	local pan = pcf * CF(0, 2.45, 0.75) * ANG(math.rad(12), 0, 0)
	K:box("CandyPanel", V3(W + 0.04, 0.24, 1.3), pan, dark)
	K:box("CandyPanelArt", V3(W - 0.1, 0.02, 1.1), pan * CF(0, 0.13, 0.02), lk(dk(acc, 0.35)))
	if hi(K) then
		K:box("CandyPanelEdge", V3(W + 0.06, 0.1, 0.08), pan * CF(0, 0, 0.66), Look.chrome)
	end
	local ball = o.ball or rgb(220, 30, 40)
	K:vcyl("CandyStick", 0.34, 0.07, pan * CF(-0.75, 0.3, 0.05), Look.chrome)
	K:ball("CandyStickBall", 0.3, pan * CF(-0.75, 0.5, 0.05), lk(ball))
	local bcols = o.buttons or { rgb(230, 40, 40), rgb(250, 200, 30), rgb(40, 140, 240), rgb(60, 200, 90), rgb(240, 240, 240), rgb(170, 60, 220) }
	for i = 0, 5 do
		local bx = 0.05 + (i % 3) * 0.36 + (if i >= 3 then 0.08 else 0)
		local bz = if i >= 3 then 0.28 else -0.12
		K:vcyl("CandyButton", 0.09, 0.22, pan * CF(bx, 0.16, bz), lk(bcols[i + 1]))
	end
	-- 모니터 몸체 (뒤로 기움) + 베젤 + 화면
	local mon = pcf * CF(0, 2.55, -0.55) * ANG(math.rad(-9), 0, 0)
	K:box("CandyMonitorBox", V3(W, 2.65, 2.05), mon * CF(0, 1.32, 0), lk(body))
	local face = mon * CF(0, 1.4, 1.03)
	K:plate("CandyBezel", W - 0.16, 2.2, 0.05, face, dark)
	local scrL = { c = o.scr or rgb(30, 50, 120), m = M.Neon, t = 0.05 }
	local scr = K:plate("CandyScreen", W - 0.55, 1.75, 0.04, face * CF(0, 0.06, 0.05), scrL)
	local _, lab = txt(K, "CandyScreenText", W - 0.7, 1.2, face * CF(0, 0.1, 0.1), o.screen or "INSERT COIN", WHITE, nil, F.Arcade, 1.4)
	out.screen, out.label = scr, lab
	if hi(K) then
		K:plate("CandyGlass", W - 0.3, 1.95, 0.02, face * CF(0, 0.06, 0.14), gl(rgb(220, 230, 240), 0.86))
	end
	-- 마키 (위 간판)
	local mq = pcf * CF(0, 5.45, -0.55)
	K:box("CandyMarqueeBox", V3(W, 0.8, 1.7), mq, lk(body))
	local mqF = mq * CF(0, 0, 0.86) * ANG(math.rad(-6), 0, 0)
	local mp = K:plate("CandyMarquee", W - 0.2, 0.62, 0.05, mqF, nl(lt(acc, 0.15)))
	txt(K, "CandyTitle", W - 0.35, 0.5, mqF * CF(0, 0, 0.06), o.title or "VS FIGHT", WHITE, nil, o.font or F.GothamBlack, 1.3)
	out.marquee = mp
	-- 옆판 (색 띠 + 사선) 양쪽
	for _, sx in { -1, 1 } do
		local x = sx * (W / 2 + 0.03)
		K:box("CandySide", V3(0.06, 2.3, 2.6), pcf * CF(x, 1.15, -0.3), lk(acc))
		K:box("CandySideUpper", V3(0.06, 3.2, 1.9), pcf * CF(x, 4.25, -0.75) * ANG(math.rad(-9), 0, 0), lk(body))
		K:box("CandySideStripe", V3(0.07, 0.28, 2.8), pcf * CF(x, 3.7, -0.6) * ANG(math.rad(28), 0, 0), lk(acc))
	end
	if o.stool ~= false then
		stool(K, pcf * CF(0, 0, 2.3), 2.2, o.seat)
	end
	return out
end

-- 2) 펌프식 댄스 기계: 폭 7.0, 깊이 8.2 (캐비닛 z -2.6..0, 발판 0..5.0, 안전바 5.4)
local function danceMachine(K: any, pcf: CFrame, o: any): any
	local out: any = { arrows = {} }
	local body = lk(rgb(26, 24, 34))
	local acc: Color3 = o.accent or rgb(255, 120, 20)
	-- 가운데 탑 + 스피커 탑 2
	K:box("DanceTower", V3(3.8, 7.8, 2.4), pcf * CF(0, 3.9, -1.3), body)
	for _, sx in { -1, 1 } do
		local sp = pcf * CF(sx * 2.65, 0, -1.25)
		K:box("DanceSpeakerTower", V3(1.5, 6.4, 2.3), sp * CF(0, 3.2, 0), lk(rgb(36, 34, 46)))
		for j, y in { 1.5, 3.3, 5.0 } do
			wdisc(K, "DanceWoofer", if j == 1 then 1.1 else 0.85, 0.06, sp * CF(0, y, 1.16), lk(rgb(46, 46, 50), M.DiamondPlate))
			wdisc(K, "DanceWooferCap", 0.3, 0.08, sp * CF(0, y, 1.16), Look.chrome)
		end
		K:box("DanceSpeakerLED", V3(0.08, 6.2, 0.08), sp * CF(-sx * 0.76, 3.2, 1.16), nl(acc))
		K:box("DanceSpeakerLED", V3(0.08, 6.2, 0.08), sp * CF(sx * 0.76, 3.2, 1.16), nl(rgb(60, 200, 255)))
	end
	-- 화면 (55인치)
	local face = pcf * CF(0, 5.0, -0.08)
	K:plate("DanceBezel", 3.4, 2.3, 0.06, face, lk(rgb(12, 12, 14)))
	local scr = K:plate("DanceScreen", 3.1, 1.95, 0.05, face * CF(0, 0, 0.06), { c = rgb(40, 20, 90), m = M.Neon, t = 0.05 })
	local _, lab = txt(K, "DanceScreenText", 2.9, 1.4, face * CF(0, 0, 0.12), o.screen or "SELECT SONG\n♪ 광안대교 야경 ♪", WHITE, nil, F.GothamBlack, 1.5)
	out.screen, out.label = scr, lab
	-- 마키
	local mq = pcf * CF(0, 7.4, -0.1)
	K:box("DanceMarqueeBox", V3(4.2, 1.1, 0.6), mq * CF(0, 0, -0.25), body)
	local mp = K:plate("DanceMarquee", 4.0, 0.9, 0.05, mq * CF(0, 0, 0.06), nl(acc))
	txt(K, "DanceTitle", 3.7, 0.72, mq * CF(0, 0, 0.12), o.title or "BEAT STEP XX", WHITE, nil, F.GothamBlack, 1.6)
	out.marquee = mp
	-- 아래 몸체: 버튼 패널 2 · 코인 · 가격
	for _, sx in { -1, 1 } do
		local bp = pcf * CF(sx * 0.95, 3.35, 0.0) * ANG(math.rad(25), 0, 0)
		K:box("DanceBtnPanel", V3(1.4, 0.18, 0.5), bp, lk(rgb(40, 40, 48)))
		for i, c in { rgb(60, 140, 255), rgb(250, 210, 40), rgb(60, 140, 255) } do
			K:vcyl("DanceBtn", 0.08, 0.26, bp * CF((i - 2) * 0.42, 0.11, 0), lk(c))
		end
		K:box("DanceCoinSlot", V3(0.08, 0.3, 0.03), pcf * CF(sx * 0.95, 2.1, 0.0), nl(rgb(255, 70, 40)))
	end
	txt(K, "DancePrice", 3.0, 0.42, pcf * CF(0, 2.65, 0.0), o.price or "1곡 1,000원 · 3곡 2,000원", rgb(255, 230, 120), rgb(20, 20, 24), F.GothamBold, 1.2)
	-- 발판 (5칸 대각선 화살표 x 2)
	K:box("DanceStage", V3(7.0, 0.5, 5.0), pcf * CF(0, 0.25, 2.5), lk(rgb(44, 44, 50), M.DiamondPlate))
	K:box("DanceStageEdge", V3(7.06, 0.12, 0.1), pcf * CF(0, 0.44, 5.0), Look.chrome)
	for _, px in { -1.75, 1.75 } do
		local pad = pcf * CF(px, 0.5, 2.5)
		K:box("DancePadFrame", V3(3.1, 0.06, 3.1), pad * CF(0, 0.03, 0), Look.brushed)
		local cells = { { -1, -1, rgb(230, 40, 50), 3 * PI / 4 }, { 1, -1, rgb(230, 40, 50), PI / 4 }, { 0, 0, rgb(250, 210, 30), nil }, { -1, 1, rgb(40, 120, 250), -3 * PI / 4 }, { 1, 1, rgb(40, 120, 250), -PI / 4 } }
		for _, c in cells do
			local cc = pad * CF(c[1] * 1.0, 0.07, c[2] * 1.0)
			local tile = K:box("DancePanel", V3(0.9, 0.05, 0.9), cc, lk(dk(c[3], 0.35)))
			local g = {}
			if c[4] then
				-- 대각선 화살표: 머리 (쐐기 2) + 몸통
				local ar = cc * CF(0, 0.035, 0) * ANG(0, c[4], 0)
				table.insert(g, K:wedge("DanceArrowHead", V3(0.02, 0.36, 0.3), ar * CF(0.16, 0, -0.15) * ANG(0, 0, PI / 2) * ANG(0, PI / 2, 0), nl(c[3])))
				table.insert(g, K:box("DanceArrowShaft", V3(0.16, 0.02, 0.36), ar * CF(0, 0, 0.12), nl(c[3])))
			else
				table.insert(g, K:box("DanceArrowCenter", V3(0.5, 0.02, 0.5), cc * CF(0, 0.035, 0) * ANG(0, PI / 4, 0), nl(c[3])))
			end
			table.insert(out.arrows, { tile = tile, glyph = g, c = c[3] })
		end
	end
	-- 안전바 (U자)
	local bz = 5.3
	for _, sx in { -1, 1 } do
		K:seg("DanceBarPost", (pcf * CF(sx * 3.3, 0.5, bz)).Position, (pcf * CF(sx * 3.3, 4.2, bz)).Position, 0.16, Look.chrome)
	end
	K:seg("DanceBarTop", (pcf * CF(-3.3, 4.2, bz)).Position, (pcf * CF(3.3, 4.2, bz)).Position, 0.16, Look.chrome)
	K:seg("DanceBarFoam", (pcf * CF(-1.2, 4.2, bz)).Position, (pcf * CF(1.2, 4.2, bz)).Position, 0.26, lk(rgb(30, 30, 34), M.Rubber))
	K:box("DanceStepUp", V3(7.0, 0.25, 0.6), pcf * CF(0, 0.125, 5.3), lk(rgb(240, 200, 40), M.DiamondPlate))
	return out
end

-- 3) 건슈팅 2인용: 폭 5.2, 깊이 6 (캐비닛 z -2.6..0, 페달 0..1.6)
local function gunCabinet(K: any, pcf: CFrame, o: any): any
	local out: any = {}
	local body = lk(rgb(30, 30, 34))
	local acc: Color3 = o.accent or rgb(60, 220, 90)
	K:box("GunCabinet", V3(5.2, 7.0, 2.6), pcf * CF(0, 3.5, -1.3), body)
	K:box("GunHood", V3(5.4, 0.5, 3.2), pcf * CF(0, 6.9, -1.0), body)
	local face = pcf * CF(0, 4.75, 0.0)
	K:plate("GunBezel", 4.8, 2.9, 0.05, face, lk(rgb(10, 10, 12)))
	local scr = K:plate("GunScreen", 4.5, 2.55, 0.05, face * CF(0, 0, 0.05), { c = rgb(80, 20, 20), m = M.Neon, t = 0.05 })
	local _, lab = txt(K, "GunScreenText", 4.1, 1.6, face * CF(0, 0, 0.11), o.screen or "STAGE 3\n해운대 좀비 습격!", rgb(255, 230, 200), nil, F.Bangers, 1.5)
	out.screen, out.label = scr, lab
	local mq = pcf * CF(0, 6.5, 0.33)
	K:plate("GunMarquee", 5.0, 0.6, 0.05, mq, nl(acc))
	txt(K, "GunTitle", 4.6, 0.5, mq * CF(0, 0, 0.06), o.title or "ZOMBIE HUNTER 광안", rgb(20, 20, 20), nil, F.Bangers, 1.3)
	-- 앞 선반 + 총 2정 + 홀스터
	K:box("GunLedge", V3(5.2, 0.24, 0.9), pcf * CF(0, 3.1, 0.35), lk(rgb(46, 46, 52)))
	K:box("GunLedgeLED", V3(5.2, 0.06, 0.04), pcf * CF(0, 3.0, 0.81), nl(acc))
	for i, sx in { -1, 1 } do
		local col = if i == 1 then rgb(220, 40, 40) else rgb(40, 110, 230)
		local g = pcf * CF(sx * 1.45, 3.4, 0.45) * ANG(0, 0, sx * 0.15)
		K:box("GunBarrel", V3(0.24, 0.26, 1.1), g * CF(0, 0.12, -0.1), lk(col))
		K:box("GunGrip", V3(0.22, 0.55, 0.28), g * CF(0, -0.12, 0.35) * ANG(math.rad(-18), 0, 0), lk(rgb(30, 30, 30)))
		K:box("GunHolster", V3(0.5, 0.3, 1.0), pcf * CF(sx * 1.45, 3.3, 0.45), lk(rgb(20, 20, 24)))
		K:seg("GunCable", (g * CF(0, -0.35, 0.45)).Position, (pcf * CF(sx * 1.9, 2.6, 0.02)).Position, 0.06, Look.black)
		K:wedge("GunPedal", V3(0.9, 0.3, 1.2), pcf * CF(sx * 1.45, 0.15, 0.85) * ANG(0, PI, 0), lk(rgb(60, 60, 64), M.DiamondPlate))
		K:box("GunCoin", V3(0.08, 0.28, 0.03), pcf * CF(sx * 1.45, 2.2, 0.02), nl(rgb(255, 70, 40)))
		txt(K, "GunPlayer", 0.7, 0.3, pcf * CF(sx * 1.45, 2.55, 0.02), if i == 1 then "1P" else "2P", WHITE, col, F.GothamBlack)
	end
	txt(K, "GunPrice", 1.6, 0.3, pcf * CF(0, 2.2, 0.02), o.price or "1,000원", rgb(255, 230, 120), rgb(20, 20, 24), F.GothamBold, 1.1)
	for _, sx in { -1, 1 } do
		K:box("GunSideLED", V3(0.06, 6.8, 0.06), pcf * CF(sx * 2.62, 3.5, -0.02), nl(acc))
		K:box("GunSideArt", V3(0.04, 4.0, 2.2), pcf * CF(sx * 2.62, 3.6, -1.3), lk(rgb(120, 20, 20)))
	end
	return out
end

-- 4) 북 리듬게임 (태고식): 폭 4.4, 깊이 4.6 (캐비닛 z -2.2..0, 북 0..1.6)
local function drumGame(K: any, pcf: CFrame, o: any): any
	local out: any = {}
	local red = rgb(210, 40, 36)
	K:box("DrumCabinet", V3(4.4, 6.6, 2.2), pcf * CF(0, 3.3, -1.1), lk(red))
	K:box("DrumCabinetTrim", V3(4.5, 0.2, 2.3), pcf * CF(0, 6.6, -1.1), lk(rgb(250, 200, 40)))
	local face = pcf * CF(0, 4.6, 0.0)
	K:plate("DrumBezel", 3.4, 2.1, 0.05, face, lk(rgb(14, 14, 16)))
	local scr = K:plate("DrumScreen", 3.1, 1.8, 0.05, face * CF(0, 0, 0.05), { c = rgb(240, 120, 30), m = M.Neon, t = 0.05 })
	local _, lab = txt(K, "DrumScreenText", 2.9, 1.3, face * CF(0, 0, 0.11), o.screen or "둥! 딱! 둥둥!\nFULL COMBO", rgb(30, 20, 10), nil, F.FredokaOne, 1.3)
	out.screen, out.label = scr, lab
	local mq = pcf * CF(0, 6.1, 0.02)
	K:plate("DrumMarquee", 4.0, 0.7, 0.05, mq, nl(rgb(255, 230, 80)))
	txt(K, "DrumTitle", 3.7, 0.56, mq * CF(0, 0, 0.06), o.title or "북치기 달인", rgb(160, 20, 20), nil, F.FredokaOne, 1.2)
	for i, sx in { -1, 1 } do
		local d = pcf * CF(sx * 1.1, 2.55, 0.85)
		K:box("DrumStand", V3(1.3, 2.0, 1.2), pcf * CF(sx * 1.1, 1.0, 0.8), lk(dk(red, 0.25)))
		K:cyl("DrumBody", 1.0, 1.55, d * ANG(0, PI / 2, 0), lk(rgb(150, 70, 30), M.Wood))
		for _, z in { -0.48, 0.48 } do
			K:cyl("DrumRim", 0.08, 1.62, d * CF(0, 0, z) * ANG(0, PI / 2, 0), lk(rgb(30, 30, 30)))
		end
		K:cyl("DrumSkin", 0.04, 1.4, d * CF(0, 0, 0.51) * ANG(0, PI / 2, 0), lk(rgb(240, 230, 210), M.Fabric))
		K:cyl("DrumSkinMark", 0.045, 0.5, d * CF(0, 0, 0.52) * ANG(0, PI / 2, 0), lk(rgb(200, 40, 40)))
		for _, j in { -1, 1 } do
			K:seg("DrumStick", (pcf * CF(sx * 1.1 + j * 0.12, 1.9, 1.45)).Position, (pcf * CF(sx * 1.1 + j * 0.16, 2.5, 1.5)).Position, 0.09, lk(rgb(230, 200, 150), M.Wood))
		end
		K:box("DrumStickHolder", V3(0.6, 0.2, 0.25), pcf * CF(sx * 1.1, 1.85, 1.45), lk(rgb(30, 30, 30)))
		txt(K, "DrumPlayer", 0.6, 0.3, pcf * CF(sx * 1.1, 1.25, 1.41), if i == 1 then "1P" else "2P", WHITE, rgb(40, 40, 40), F.GothamBlack)
	end
	txt(K, "DrumPrice", 1.6, 0.3, pcf * CF(0, 3.25, 0.02), o.price or "1곡 1,000원", WHITE, rgb(40, 20, 20), F.GothamBold)
	return out
end

-- 5) 두더지 잡기: 폭 2.9, 깊이 4.4 (몸체 z -2.2..1.2, 뒤판 -2.2..-1.6)
local function moleGame(K: any, pcf: CFrame, o: any): any
	local out: any = { moles = {} }
	local green = rgb(60, 170, 70)
	K:box("MoleBody", V3(2.9, 2.6, 3.4), pcf * CF(0, 1.3, -0.5), lk(green))
	K:box("MoleDeck", V3(2.95, 0.12, 3.45), pcf * CF(0, 2.66, -0.5), lk(rgb(250, 200, 40)))
	K:box("MolePad", V3(3.0, 0.22, 0.3), pcf * CF(0, 2.7, 1.25), lk(rgb(30, 30, 30), M.Rubber))
	local holes = { { -0.85, 0.35 }, { 0, 0.35 }, { 0.85, 0.35 }, { -0.45, -0.6 }, { 0.45, -0.6 } }
	for i, h in holes do
		local hc = pcf * CF(h[1], 2.73, h[2] - 0.5)
		K:disc("MoleHole", 0.7, 0.02, hc, lk(rgb(20, 20, 20)))
		local up = 0.12 + rnd(i, 3) * 0.35
		local head = K:ell("MoleHead", V3(0.5, 0.55, 0.5), hc * CF(0, up, 0), lk(rgb(130, 82, 50)))
		local nose = K:ball("MoleNose", 0.12, hc * CF(0, up + 0.05, 0.24), lk(rgb(230, 120, 140)))
		table.insert(out.moles, { head = head, nose = nose, base = hc, up = up })
	end
	local bt = pcf * CF(0, 2.7, -1.9)
	K:box("MoleTower", V3(2.9, 3.6, 0.6), bt * CF(0, 1.8, 0), lk(green))
	local led = K:plate("MoleScore", 2.2, 0.6, 0.05, bt * CF(0, 1.5, 0.3), { c = rgb(30, 10, 10), m = M.Neon })
	local _, lab = txt(K, "MoleScoreText", 2.0, 0.5, bt * CF(0, 1.5, 0.36), "SCORE 0072", rgb(255, 60, 40), nil, F.Arcade, 1.6)
	out.label = lab
	out.screen = led
	local mq = bt * CF(0, 2.9, 0.31)
	K:plate("MoleMarquee", 2.7, 0.8, 0.05, mq, nl(rgb(255, 240, 120)))
	txt(K, "MoleTitle", 2.5, 0.66, mq * CF(0, 0, 0.06), o.title or "두더지 잡기", rgb(100, 50, 20), nil, F.FredokaOne, 1.2)
	-- 뿅망치 (줄에 묶임)
	local mh = pcf * CF(1.0, 2.86, 0.95) * ANG(0, 0.4, 0)
	K:cyl("MoleMalletHead", 0.7, 0.42, mh * CF(0, 0.15, 0) * ANG(0, PI / 2, 0), lk(rgb(240, 60, 70)))
	K:box("MoleMalletHandle", V3(0.12, 0.12, 0.9), mh * CF(0, 0.12, -0.6), lk(rgb(250, 220, 60)))
	K:seg("MoleCord", (mh * CF(0, 0.12, -1.0)).Position, (pcf * CF(1.3, 2.4, -0.2)).Position, 0.04, Look.black)
	K:box("MoleCoin", V3(0.08, 0.28, 0.03), pcf * CF(0.9, 1.7, 1.22), nl(rgb(255, 70, 40)))
	txt(K, "MolePrice", 1.2, 0.3, pcf * CF(-0.4, 1.7, 1.22), o.price or "1회 500원", WHITE, rgb(30, 80, 30), F.GothamBold)
	return out
end

-- 6) 경품 기계 (키마스터 / 가위 자르기): 폭 2.8, 깊이 2.9, 높이 6.4. o.kind = "key" | "cut"
local PRIZES = {
	{ "게임기", rgb(220, 30, 40) }, { "무선이어폰", rgb(245, 245, 245) }, { "향수", rgb(240, 170, 200) }, { "블루투스\n스피커", rgb(40, 40, 46) },
	{ "문화상품권\n5만원", rgb(250, 210, 60) }, { "태블릿", rgb(170, 175, 180) }, { "스마트워치", rgb(30, 30, 36) }, { "드론", rgb(240, 240, 240) },
	{ "보조배터리", rgb(60, 120, 230) }, { "캠코더", rgb(90, 90, 96) }, { "피규어", rgb(250, 120, 40) }, { "인형 키링", rgb(250, 200, 220) },
}
local function prizeMachine(K: any, pcf: CFrame, o: any, seed: number): any
	local out: any = {}
	local col: Color3 = o.body or rgb(30, 30, 36)
	local acc: Color3 = o.accent or rgb(255, 200, 40)
	K:box("PrizeBody", V3(2.8, 2.6, 2.8), pcf * CF(0, 1.3, -0.05), lk(col))
	K:box("PrizeTopBox", V3(2.9, 1.0, 2.9), pcf * CF(0, 5.9, -0.05), lk(col))
	for _, sx in { -1, 1 } do
		K:box("PrizePillar", V3(0.18, 3.0, 2.8), pcf * CF(sx * 1.31, 4.1, -0.05), lk(col))
		K:box("PrizePillarLED", V3(0.06, 3.0, 0.06), pcf * CF(sx * 1.25, 4.1, 1.36), nl(acc))
	end
	K:box("PrizeBack", V3(2.5, 3.0, 0.08), pcf * CF(0, 4.1, -1.4), Look.mirror)
	K:box("PrizeGlass", V3(2.5, 3.0, 0.06), pcf * CF(0, 4.1, 1.3), gl(rgb(226, 236, 240), 0.82))
	local mq = pcf * CF(0, 5.95, 1.41)
	local mp = K:plate("PrizeMarquee", 2.6, 0.75, 0.05, mq, nl(acc))
	txt(K, "PrizeTitle", 2.4, 0.6, mq * CF(0, 0, 0.06), o.title or (if o.kind == "cut" then "가위 자르기" else "KEY MASTER"), rgb(20, 20, 24), nil, F.GothamBlack, 1.2)
	out.marquee = mp
	if o.kind == "cut" then
		-- 끈에 매달린 경품 + 가위 캐리지
		K:box("PrizeCutRail", V3(2.4, 0.08, 0.1), pcf * CF(0, 5.25, 0.2), Look.chrome)
		for i = 1, 4 do
			local p = PRIZES[(seed + i) % #PRIZES + 1]
			local x = -0.9 + (i - 1) * 0.6
			K:seg("PrizeString", (pcf * CF(x, 5.2, 0.2)).Position, (pcf * CF(x, 4.4, 0.2)).Position, 0.025, Look.white)
			K:box("PrizeBox", V3(0.5, 0.6, 0.4), pcf * CF(x, 4.05, 0.2), lk(p[2]))
			txt(K, "PrizeBoxText", 0.46, 0.3, pcf * CF(x, 4.05, 0.41), p[1], if p[2].R + p[2].G + p[2].B > 1.8 then BLACK else WHITE, nil, F.GothamBold)
		end
		local sc = pcf * CF(0.25, 4.95, 0.55)
		K:wedge("PrizeScissor", V3(0.05, 0.12, 0.6), sc * ANG(0, 0, 0.3), Look.chrome)
		K:wedge("PrizeScissor", V3(0.05, 0.12, 0.6), sc * ANG(0, 0, -0.3), Look.chrome)
		K:box("PrizeCarriage", V3(0.4, 0.2, 0.3), pcf * CF(0.25, 5.15, 0.45), lk(rgb(240, 60, 60)))
	else
		-- 3단 진열 + 열쇠 구멍
		for row = 0, 2 do
			local y = 2.75 + row * 0.95
			K:box("PrizeShelf", V3(2.4, 0.06, 1.6), pcf * CF(0, y, 0.2), gl(rgb(240, 244, 248), 0.4))
			for j = 0, 2 do
				local p = PRIZES[(seed + row * 3 + j) % #PRIZES + 1]
				local x = -0.78 + j * 0.78
				K:box("PrizeBox", V3(0.62, 0.55, 0.45), pcf * CF(x, y + 0.31, 0.2), lk(p[2]))
				txt(K, "PrizeBoxText", 0.58, 0.28, pcf * CF(x, y + 0.31, 0.43), p[1], if p[2].R + p[2].G + p[2].B > 1.8 then BLACK else WHITE, nil, F.GothamBold)
				K:disc("PrizeKeyhole", 0.12, 0.02, pcf * CF(x, y + 0.04, 0.85) * ANG(PI / 2, 0, 0), Look.goldMetal)
			end
		end
	end
	-- 앞 조작부: 버튼 2 + 지폐 투입구 + 카드 단말 + 경품 출구
	local fr = pcf * CF(0, 0, 1.35)
	K:box("PrizePanel", V3(2.6, 0.2, 0.5), fr * CF(0, 2.5, 0.15) * ANG(math.rad(15), 0, 0), lk(rgb(20, 20, 24)))
	for _, sx in { -0.55, 0.55 } do
		K:vcyl("PrizeButton", 0.12, 0.42, fr * CF(sx, 2.66, 0.18), lk(if sx < 0 then rgb(250, 60, 60) else rgb(60, 200, 90)))
	end
	K:plate("PrizeBill", 0.55, 0.8, 0.06, fr * CF(-0.75, 1.55, 0), lk(rgb(40, 40, 44)))
	K:plate("PrizeBillSlot", 0.4, 0.05, 0.02, fr * CF(-0.75, 1.75, 0.06), nl(rgb(60, 255, 120)))
	K:plate("PrizeCard", 0.45, 0.6, 0.08, fr * CF(0.05, 1.6, 0), lk(rgb(230, 230, 230)))
	K:plate("PrizeCardLCD", 0.3, 0.18, 0.02, fr * CF(0.05, 1.75, 0.08), { c = rgb(120, 200, 230), m = M.Neon })
	K:plate("PrizeChute", 0.75, 0.75, 0.04, fr * CF(0.75, 0.75, 0), lk(rgb(16, 16, 18)))
	K:plate("PrizeChuteFrame", 0.9, 0.1, 0.06, fr * CF(0.75, 1.17, 0), Look.chrome)
	txt(K, "PrizePrice", 2.4, 0.32, fr * CF(0, 2.2, 0.01), o.price or "1회 2,000원 · 지폐 · 카드", rgb(255, 230, 120), rgb(20, 20, 24), F.GothamBold, 1.1)
	txt(K, "PrizeOut", 0.8, 0.18, fr * CF(0.75, 0.25, 0.01), "경품 출구", WHITE, nil, F.GothamBold)
	return out
end

-- 7) 캡슐 토이 (가챠) 2단 스택: 폭 1.7, 깊이 1.7, 높이 4.55. themes = { {제목, 색, 가격} x2 }
local function gachaStack(K: any, pcf: CFrame, themes: { any }, seed: number): any
	local out: any = { handles = {} }
	K:box("GachaBase", V3(1.75, 0.15, 1.7), pcf * CF(0, 0.075, 0), lk(rgb(30, 30, 34)))
	for lvl = 0, 1 do
		local th = themes[lvl + 1]
		local y0 = 0.15 + lvl * 2.2
		local col: Color3 = th[2]
		local u = pcf * CF(0, y0, 0)
		K:box("GachaFrame", V3(1.7, 2.2, 1.6), u * CF(0, 1.1, 0), lk(lt(col, 0.1)))
		-- 위 반: 투명 창 + 캡슐
		K:box("GachaWindow", V3(1.36, 0.95, 0.05), u * CF(0, 1.62, 0.81), gl(rgb(240, 246, 250), 0.7))
		for j = 0, (if lowD(K) then 2 else 3) do
			local cc = CARPET_COLS[(seed + lvl * 5 + j) % #CARPET_COLS + 1]
			K:ball("GachaCapsule", 0.38, u * CF(-0.48 + (j % 3) * 0.48, 1.33 + (j // 3) * 0.36, 0.55 - (j % 2) * 0.15), lk(cc))
		end
		-- 아래 반: 그림 카드 · 핸들 · 투입구 · 출구
		txt(K, "GachaCard", 1.3, 0.42, u * CF(0, 0.98, 0.81), th[1], WHITE, dk(col, 0.25), F.FredokaOne)
		local hc = u * CF(-0.25, 0.48, 0.81)
		local knob = wdisc(K, "GachaKnob", 0.5, 0.08, hc, lk(rgb(240, 240, 240)))
		local bar = K:plate("GachaHandle", 0.48, 0.1, 0.08, hc * CF(0, 0, 0.08), lk(rgb(220, 220, 224)))
		table.insert(out.handles, { knob = knob, bar = bar, cf = K.cf * hc * CF(0, 0, 0.12) })
		K:plate("GachaCoinSlot", 0.06, 0.2, 0.02, u * CF(0.42, 0.62, 0.81), lk(rgb(20, 20, 20)))
		K:plate("GachaOut", 0.36, 0.3, 0.03, u * CF(0.42, 0.25, 0.81), lk(rgb(20, 20, 20)))
		txt(K, "GachaPrice", 0.6, 0.18, u * CF(0.38, 0.84, 0.82), th[3], rgb(20, 20, 20), rgb(255, 230, 80), F.GothamBlack)
	end
	return out
end

-- 8) 키디라이드 (동전 넣는 자동차): 폭 2.3, 길이 4.0 (+Z = 앞), 높이 3.2
local function kiddieRide(K: any, pcf: CFrame, o: any): any
	local col: Color3 = o.body or rgb(230, 40, 50)
	local out: any = { parts = {} }
	local function add(p: BasePart?)
		if p then
			table.insert(out.parts, p)
		end
	end
	K:slab("KiddieBase", 2.4, 4.1, 0.35, 0.5, pcf * CF(0, 0.175, 0), lk(rgb(40, 40, 46), M.DiamondPlate))
	local b = pcf * CF(0, 0.35, 0)
	out.base = K.cf * b
	add(K:ell("KiddieBody", V3(2.1, 1.5, 3.7), b * CF(0, 0.9, 0), lk(col)))
	add(K:ell("KiddieHood", V3(1.9, 1.0, 1.5), b * CF(0, 1.45, 0.9), lk(col)))
	add(K:ell("KiddieEyeL", V3(0.5, 0.55, 0.2), b * CF(-0.45, 1.6, 1.72), lk(WHITE)))
	add(K:ell("KiddieEyeR", V3(0.5, 0.55, 0.2), b * CF(0.45, 1.6, 1.72), lk(WHITE)))
	add(K:ball("KiddiePupil", 0.22, b * CF(-0.45, 1.6, 1.8), lk(BLACK)))
	add(K:ball("KiddiePupil", 0.22, b * CF(0.45, 1.6, 1.8), lk(BLACK)))
	add(K:box("KiddieSmile", V3(0.8, 0.08, 0.06), b * CF(0, 1.05, 1.72), lk(rgb(40, 20, 20))))
	add(K:box("KiddieSeat", V3(1.4, 0.3, 1.0), b * CF(0, 1.55, -0.6), lk(rgb(40, 40, 46), M.Leather)))
	add(K:box("KiddieSeatBack", V3(1.4, 0.9, 0.2), b * CF(0, 2.0, -1.15) * ANG(math.rad(-10), 0, 0), lk(rgb(40, 40, 46), M.Leather)))
	add(K:vcyl("KiddieColumn", 0.6, 0.1, b * CF(0, 1.9, 0.3) * ANG(math.rad(-30), 0, 0), Look.blackMetal))
	add(K:cyl("KiddieWheel", 0.08, 0.7, b * CF(0, 2.15, 0.15) * ANG(math.rad(-30), 0, 0) * ANG(0, 0, PI / 2), lk(rgb(30, 30, 30))))
	for _, sx in { -1, 1 } do
		for _, sz in { -1.1, 1.0 } do
			add(K:cyl("KiddieTire", 0.4, 0.8, b * CF(sx * 1.02, 0.4, sz), lk(rgb(26, 26, 28), M.Rubber)))
		end
	end
	add(K:box("KiddieLight", V3(0.08, 0.6, 0.08), b * CF(0, 2.6, -1.25), nl(rgb(255, 200, 40))))
	add(K:ball("KiddieBeacon", 0.3, b * CF(0, 2.95, -1.25), nl(rgb(255, 60, 60))))
	-- 코인 박스 (발판 앞)
	K:box("KiddieCoinBox", V3(0.7, 1.2, 0.5), pcf * CF(0.75, 0.95, 2.1), lk(rgb(250, 210, 40)))
	K:box("KiddieCoinSlot", V3(0.06, 0.22, 0.02), pcf * CF(0.75, 1.25, 2.36), nl(rgb(255, 60, 40)))
	txt(K, "KiddiePrice", 0.62, 0.3, pcf * CF(0.75, 0.85, 2.36), o.price or "1,000원", rgb(30, 30, 30), nil, F.GothamBlack)
	txt(K, "KiddieName", 1.6, 0.36, b * CF(0, 0.85, 1.72 + 0.03), o.name or "빵빵이", WHITE, nil, F.FredokaOne)
	return out
end

-- 9) 휴게 소품: 정수기 · 분리수거함 · 벤치 · 보조배터리 대여기
local function purifier(K: any, pcf: CFrame)
	K:box("PurifierBody", V3(1.1, 3.9, 1.2), pcf * CF(0, 1.95, 0), lk(rgb(240, 240, 238)))
	K:box("PurifierFace", V3(0.9, 1.6, 0.04), pcf * CF(0, 2.6, 0.62), lk(rgb(200, 205, 210)))
	K:box("PurifierLED", V3(0.5, 0.12, 0.02), pcf * CF(0, 3.2, 0.65), nl(rgb(60, 160, 255)))
	for _, x in { -0.2, 0.2 } do
		K:vcyl("PurifierTap", 0.2, 0.12, pcf * CF(x, 2.1, 0.55), Look.chrome)
		K:box("PurifierBtn", V3(0.16, 0.12, 0.03), pcf * CF(x, 2.85, 0.65), lk(if x < 0 then rgb(60, 140, 255) else rgb(240, 60, 60)))
	end
	K:box("PurifierTray", V3(0.9, 0.08, 0.4), pcf * CF(0, 1.5, 0.6), lk(rgb(120, 124, 128)))
	K:vcyl("PurifierCups", 0.9, 0.28, pcf * CF(0.68, 2.6, 0.3), lk(rgb(250, 250, 246)))
	K:vcyl("PurifierCupHolder", 0.15, 0.32, pcf * CF(0.68, 2.1, 0.3), Look.chrome)
	txt(K, "PurifierLabel", 0.8, 0.22, pcf * CF(0, 3.5, 0.63), "정수기", rgb(40, 60, 90), nil, F.GothamBold)
end
local function bins(K: any, pcf: CFrame)
	local kinds = { { "일반", rgb(80, 84, 90) }, { "캔·병", rgb(40, 110, 200) }, { "플라스틱", rgb(240, 170, 30) } }
	for i, k in kinds do
		local b = pcf * CF((i - 2) * 0.95, 0, 0)
		K:box("BinBody", V3(0.85, 2.3, 0.85), b * CF(0, 1.15, 0), lk(rgb(232, 232, 228)))
		K:box("BinLid", V3(0.9, 0.18, 0.9), b * CF(0, 2.39, 0), lk(k[2]))
		K:box("BinMouth", V3(0.5, 0.12, 0.04), b * CF(0, 2.0, 0.44), lk(rgb(20, 20, 20)))
		txt(K, "BinLabel", 0.75, 0.3, b * CF(0, 1.45, 0.44), k[1], WHITE, k[2], F.GothamBold)
	end
end
local function bench(K: any, pcf: CFrame, w: number, c: Color3?)
	K:box("BenchSeat", V3(w, 0.32, 1.3), pcf * CF(0, 1.75, 0), lk(c or rgb(30, 30, 36), M.Leather))
	K:box("BenchFrame", V3(w, 0.12, 1.2), pcf * CF(0, 1.53, 0), Look.blackMetal)
	for _, sx in { -1, 1 } do
		K:box("BenchLeg", V3(0.14, 1.5, 1.1), pcf * CF(sx * (w / 2 - 0.3), 0.75, 0), Look.blackMetal)
	end
end
local function charger(K: any, pcf: CFrame)
	K:box("ChargerBody", V3(1.0, 3.6, 0.8), pcf * CF(0, 1.8, 0), lk(rgb(250, 210, 40)))
	K:plate("ChargerLCD", 0.7, 0.5, 0.03, pcf * CF(0, 2.9, 0.4), { c = rgb(60, 140, 220), m = M.Neon })
	txt(K, "ChargerLCDText", 0.66, 0.4, pcf * CF(0, 2.9, 0.44), "대여 가능\n8대", WHITE, nil, F.GothamBold, 1.1)
	for i = 0, 3 do
		K:plate("ChargerSlot", 0.7, 0.18, 0.04, pcf * CF(0, 1.3 + i * 0.32, 0.4), lk(rgb(30, 30, 34)))
		K:plate("ChargerSlotLED", 0.06, 0.06, 0.02, pcf * CF(0.28, 1.3 + i * 0.32, 0.44), nl(if i < 3 then rgb(60, 255, 120) else rgb(255, 60, 40)))
	end
	txt(K, "ChargerTitle", 0.9, 0.3, pcf * CF(0, 3.35, 0.41), "보조배터리\n대여", rgb(30, 30, 30), nil, F.GothamBlack)
end

-- 맵 기계 오버레이 ----------------------------------------------------------------------------------------
-- 모델 묶음: 이름 패턴으로 기계 Model 찾기 → { name, recs = { rec } }
local function machines(V: any, pattern: string): { any }
	local out, byM = {}, {}
	for _, r in V.parts do
		local a: Instance? = r.part.Parent
		while a and a ~= V.model do
			if a:IsA("Model") and string.match(a.Name, pattern) then
				break
			end
			a = a.Parent
		end
		if a and a ~= V.model then
			local g = byM[a]
			if not g then
				g = { name = a.Name, model = a, recs = {}, by = {} }
				byM[a] = g
				table.insert(out, g)
			end
			table.insert(g.recs, r)
			g.by[r.name] = g.by[r.name] or r
		end
	end
	table.sort(out, function(x, y)
		return x.name < y.name
	end)
	return out
end

-- 인형뽑기 오버레이 (기계 자세 그대로, 덧붙이기만): 앞 기둥 LED 2 · 상품 출구 테 · 카드 단말 · 요금 스티커 · 안쪽 거울 · 안쪽 조명
-- 반환: LED 파트 목록 (색 순환 애니)
local function clawOverlay(K: any, R: any, g: any, idx: number): { BasePart }
	local cab = g.by.Cabinet
	local top = g.by.TopBox
	local door = g.by.PrizeDoor
	local mq = g.by.Marquee or g.by.TrimNeon
	local glass = g.by.GlassBox or g.by.Glass
	if not cab or not top then
		return {}
	end
	local cmn, cmx = abox(R, cab)
	local tmn, tmx = abox(R, top)
	local cc = (cmn + cmx) / 2
	-- 앞 방향: 상품 출구 / 마키가 있는 쪽
	local ref = door or mq
	local f = if ref then acen(R, ref) - cc else V3(0, 0, 1)
	local dir: Vector3
	if math.abs(f.X) > math.abs(f.Z) then
		dir = V3(math.sign(f.X), 0, 0)
	else
		dir = V3(0, 0, math.sign(f.Z))
	end
	local hw = if dir.X ~= 0 then (cmx.Z - cmn.Z) / 2 else (cmx.X - cmn.X) / 2
	local hd = if dir.X ~= 0 then (cmx.X - cmn.X) / 2 else (cmx.Z - cmn.Z) / 2
	-- 기계 프레임: 원점 = 몸체 바닥 가운데, +Z = 앞
	local mf = R.A * CFrame.lookAt(V3(cc.X, 0, cc.Z), V3(cc.X, 0, cc.Z) - dir)
	local glassTop = tmn.Y
	local cabTop = cmx.Y
	local leds = {}
	local accent = CARPET_COLS[idx % #CARPET_COLS + 1]
	K:free(function()
		-- 앞 기둥 LED (유리 모서리 바깥 0.06)
		for _, sx in { -1, 1 } do
			local p = K:box("ClawPostLED", V3(0.08, glassTop - cabTop - 0.1, 0.08), mf * CF(sx * (hw - 0.04), (cabTop + glassTop) / 2, hd + 0.04), nl(accent))
			table.insert(leds, p)
		end
		-- 위 테두리 LED (마키 아래)
		local tl = K:box("ClawTopLED", V3(hw * 2 - 0.1, 0.07, 0.06), mf * CF(0, glassTop - 0.05, hd + 0.05), nl(lt(accent, 0.3)))
		table.insert(leds, tl)
		-- 안쪽 거울 (뒷면) + 안쪽 조명 띠
		K:box("ClawMirror", V3(hw * 2 - 0.4, glassTop - cabTop - 0.7, 0.04), mf * CF(0, (cabTop + glassTop) / 2 + 0.2, -hd + 0.18), Look.mirror)
		K:box("ClawInnerLight", V3(hw * 2 - 0.5, 0.06, 0.12), mf * CF(0, glassTop - 0.12, hd - 0.35), nl(rgb(255, 250, 240)))
		-- 상품 출구 테 (문 바깥 0.03, 문은 그대로 보이게)
		if door then
			local dc = acen(R, door)
			local dmn, dmx = abox(R, door)
			local u = (dc - cc):Dot(V3(dir.Z, 0, -dir.X)) -- 기계 프레임 x (오른쪽 +)
			local s = math.max(dmx.Y - dmn.Y, 0.6)
			local x = -u
			local y = (dmn.Y + dmx.Y) / 2
			local z = hd + 0.03
			K:box("ClawChuteFrame", V3(s + 0.24, 0.1, 0.06), mf * CF(x, y + s / 2 + 0.07, z), Look.chrome)
			K:box("ClawChuteFrame", V3(s + 0.24, 0.1, 0.06), mf * CF(x, y - s / 2 - 0.07, z), Look.chrome)
			K:box("ClawChuteFrame", V3(0.1, s + 0.04, 0.06), mf * CF(x - s / 2 - 0.07, y, z), Look.chrome)
			K:box("ClawChuteFrame", V3(0.1, s + 0.04, 0.06), mf * CF(x + s / 2 + 0.07, y, z), Look.chrome)
			if dmx.Y + 0.35 < cabTop - 0.45 then
				txt(K, "ClawChuteLabel", s + 0.2, 0.2, mf * CF(x, y + s / 2 + 0.28, z), "상품 출구", WHITE, nil, F.GothamBold)
			end
			-- 카드 단말 (출구 반대쪽 아래)
			local cx = if x > 0 then -hw + 0.55 else hw - 0.55
			K:box("ClawCardReader", V3(0.5, 0.62, 0.1), mf * CF(cx, 0.75, hd + 0.05), lk(rgb(232, 232, 232)))
			K:box("ClawCardLCD", V3(0.32, 0.18, 0.02), mf * CF(cx, 0.88, hd + 0.11), { c = rgb(120, 200, 230), m = M.Neon })
		end
		-- 요금 스티커 (유리 아래 모서리)
		txt(K, "ClawPriceSticker", 1.3, 0.34, mf * CF(-hw + 0.8, cabTop + 0.28, hd + 0.06), "1회 1,000원\n5,000원 6회", rgb(30, 20, 20), rgb(255, 230, 60), F.GothamBlack)
		if hi(K) then
			txt(K, "ClawNotice", 1.0, 0.24, mf * CF(hw - 0.62, cabTop + 0.22, hd + 0.06), "집게 힘 조절 X\n정품 인형", rgb(255, 255, 255), rgb(200, 30, 90), F.GothamBold)
		end
	end)
	return leds
end

-- 레트로 캐비닛 오버레이: 화면 베젤 · 후드 · 코인 도어 · 버튼 12 · T몰딩
local function retroOverlay(K: any, R: any, g: any, i: number)
	local body = g.by.CabinetBody
	local scr = g.by.RetroScreen
	local deck = g.by.ControlDeck
	if not body or not scr then
		return
	end
	local bmn, bmx = abox(R, body)
	local sc = acen(R, scr)
	local cc = (bmn + bmx) / 2
	local f = sc - cc
	local dir = if math.abs(f.X) > math.abs(f.Z) then V3(math.sign(f.X), 0, 0) else V3(0, 0, math.sign(f.Z))
	local hw = if dir.X ~= 0 then (bmx.Z - bmn.Z) / 2 else (bmx.X - bmn.X) / 2
	local hd = if dir.X ~= 0 then (bmx.X - bmn.X) / 2 else (bmx.Z - bmn.Z) / 2
	local mf = R.A * CFrame.lookAt(V3(cc.X, 0, cc.Z), V3(cc.X, 0, cc.Z) - dir)
	local smn, smx = abox(R, scr)
	local sy0, sy1 = smn.Y, smx.Y
	local sw = if dir.X ~= 0 then smx.Z - smn.Z else smx.X - smn.X
	local fz = hd + 0.12 -- 화면 앞면 (+0.1)
	local acc = ({ rgb(255, 60, 80), rgb(60, 170, 255), rgb(80, 230, 120), rgb(255, 160, 40) })[(i - 1) % 4 + 1]
	K:free(function()
		-- 베젤 (화면 둘레 4)
		local yc = (sy0 + sy1) / 2
		local hgt = sy1 - sy0
		K:box("RetroBezel", V3(sw + 0.5, 0.25, 0.1), mf * CF(0, sy1 + 0.12, fz), lk(rgb(16, 16, 18)))
		K:box("RetroBezel", V3(sw + 0.5, 0.25, 0.1), mf * CF(0, sy0 - 0.12, fz), lk(rgb(16, 16, 18)))
		K:box("RetroBezel", V3(0.25, hgt, 0.1), mf * CF(-sw / 2 - 0.12, yc, fz), lk(rgb(16, 16, 18)))
		K:box("RetroBezel", V3(0.25, hgt, 0.1), mf * CF(sw / 2 + 0.12, yc, fz), lk(rgb(16, 16, 18)))
		-- 후드 (화면 위로 튀어나온 차양)
		K:wedge("RetroHood", V3(hw * 2, 0.35, 0.7), mf * CF(0, sy1 + 0.42, hd + 0.3) * ANG(0, PI, 0), lk(rgb(26, 26, 30)))
		-- 코인 도어 + 투입구 2 + 반환 버튼
		local dz = hd + 0.03
		K:box("RetroCoinDoor", V3(1.5, 1.3, 0.05), mf * CF(0, 1.35, dz), Look.darkAlu)
		for _, x in { -0.35, 0.35 } do
			K:box("RetroCoinSlot", V3(0.08, 0.3, 0.03), mf * CF(x, 1.6, dz + 0.04), nl(rgb(255, 60, 40)))
			K:box("RetroCoinReturn", V3(0.26, 0.12, 0.03), mf * CF(x, 1.1, dz + 0.04), Look.chrome)
		end
		txt(K, "RetroCoinLabel", 1.3, 0.2, mf * CF(0, 1.88, dz + 0.04), "500원 · 1 CREDIT", WHITE, nil, F.GothamBold)
		-- T몰딩 (앞 모서리 세로 2)
		for _, sx in { -1, 1 } do
			K:box("RetroTMold", V3(0.08, bmx.Y - 0.2, 0.08), mf * CF(sx * (hw + 0.02), (bmx.Y) / 2, hd - 0.05), nl(acc))
		end
		-- 버튼 (덱 위, 1P/2P 각 3)
		if deck then
			local dmn, dmx = abox(R, deck)
			local dc = acen(R, deck)
			local dzc = (dc - cc):Dot(dir)
			local y = dmx.Y + 0.04
			for p = 0, 1 do
				for b = 0, 2 do
					local x = (if p == 0 then -0.55 else 1.15) + b * 0.32
					K:vcyl("RetroButton", 0.08, 0.2, mf * CF(x - 0.3, y, dzc + 0.05 * (b - 1)), lk(({ rgb(230, 40, 40), rgb(250, 200, 30), rgb(40, 140, 240) })[b + 1]))
				end
			end
			-- 사이드 아트 (몸체 양옆 큰 띠)
		end
		K:box("RetroSideArt", V3(0.04, 2.6, hd * 1.6), mf * CF(-hw - 0.02, 4.4, 0) * ANG(0.35, 0, 0), lk(acc))
		K:box("RetroSideArt", V3(0.04, 2.6, hd * 1.6), mf * CF(hw + 0.02, 4.4, 0) * ANG(0.35, 0, 0), lk(acc))
	end)
end

-- 레이싱 오버레이: 버킷 시트 옆 날개 · 헤드레스트 · 기어 레버 · 스피커 · 옆판 글자
local function racingOverlay(K: any, R: any, g: any, i: number)
	local back = g.by.SeatBack
	local scab = g.by.ScreenCabinet
	local side = g.by.SidePanel
	if not back or not scab then
		return
	end
	local bmn, bmx = abox(R, back)
	local smn, smx = abox(R, scab)
	local sc = (smn + smx) / 2
	local bc = (bmn + bmx) / 2
	local f = bc - sc
	local dir = if math.abs(f.X) > math.abs(f.Z) then V3(math.sign(f.X), 0, 0) else V3(0, 0, math.sign(f.Z))
	-- 기계 프레임: 원점 = 등받이 바닥 아래, +Z = 화면 반대 (앉은 사람 뒤쪽) → 화면 쪽을 보게 돌림
	local mf = R.A * CFrame.lookAt(V3(bc.X, 0, bc.Z), V3(bc.X, 0, bc.Z) + dir)
	local col = back.part.Color
	local bw = if dir.X ~= 0 then bmx.Z - bmn.Z else bmx.X - bmn.X
	K:free(function()
		-- 날개 (등받이 양옆, 앞으로 꺾임)
		for _, sx in { -1, 1 } do
			K:box("RaceBolster", V3(0.35, bmx.Y - bmn.Y - 0.2, 0.6), mf * CF(sx * (bw / 2 + 0.12), (bmn.Y + bmx.Y) / 2, -0.25) * ANG(0, sx * 0.35, 0), lk(dk(col, 0.15), M.Leather))
		end
		K:rbox("RaceHeadrest", V3(bw - 0.3, 0.7, 0.5), 0.2, mf * CF(0, bmx.Y + 0.38, 0.05), lk(dk(col, 0.1), M.Leather))
		K:box("RaceHeadrestLogo", V3(0.9, 0.22, 0.02), mf * CF(0, bmx.Y + 0.4, -0.21) * ANG(0, PI, 0), lk(WHITE))
		-- 기어 레버 (오른쪽 옆)
		local gx = bw / 2 + 0.85
		K:box("RaceShiftBase", V3(0.5, 0.9, 0.6), mf * CF(-gx, 0.75, -1.4), lk(rgb(30, 30, 34)))
		K:seg("RaceShiftLever", (mf * CF(-gx, 1.2, -1.4)).Position, (mf * CF(-gx, 2.1, -1.5)).Position, 0.08, Look.chrome)
		K:ball("RaceShiftKnob", 0.26, mf * CF(-gx, 2.15, -1.5), lk(rgb(20, 20, 20)))
		-- 화면 옆 스피커
		local ff = R.A * CFrame.lookAt(V3(sc.X, 0, sc.Z), V3(sc.X, 0, sc.Z) + dir)
		local hd = if dir.X ~= 0 then (smx.X - smn.X) / 2 else (smx.Z - smn.Z) / 2
		local hw = if dir.X ~= 0 then (smx.Z - smn.Z) / 2 else (smx.X - smn.X) / 2
		for _, sx in { -1, 1 } do
			wdisc(K, "RaceSpeaker", 0.55, 0.04, ff * CF(sx * (hw - 0.3), 2.6, hd), lk(rgb(50, 50, 54), M.DiamondPlate))
		end
		K:box("RaceScreenHood", V3(hw * 2 + 0.1, 0.25, 0.9), ff * CF(0, 7.85, hd + 0.4), lk(rgb(20, 20, 24)))
		-- 옆판 글자 (바깥쪽만)
		if side then
			for _, s in g.recs do
				if s.name == "SidePanel" then
					local pc = acen(R, s)
					local off = pc - bc
					local sgn = if dir.X ~= 0 then math.sign(off.Z) else math.sign(off.X)
					local pmn, pmx = abox(R, s)
					local o = R.A * CFrame.lookAt(V3(pc.X, 0, pc.Z), V3(pc.X, 0, pc.Z) + (if dir.X ~= 0 then V3(0, 0, sgn) else V3(sgn, 0, 0)))
					txt(K, "RaceSideText", 3.6, 0.9, o * CF(0, 2.4, -0.13) * ANG(0, PI, 0), "BUSAN RACER", WHITE, nil, F.Oswald)
					K:box("RaceSideStripe", V3(4.4, 0.18, 0.03), o * CF(0, 1.6, -0.12), lk(rgb(250, 250, 250)))
				end
			end
		end
	end)
end

-- 댄스 화살표 오버레이 (맵 DanceBeat 의 네모 ArrowPanel 위에 화살표 모양)
local function danceArrows(K: any, R: any, g: any): { any }
	local out = {}
	local panels = {}
	for _, r in g.recs do
		if r.name == "ArrowPanel" then
			table.insert(panels, r)
		end
	end
	-- 4개씩 묶어 가운데를 찾기 (x 로 두 무리)
	table.sort(panels, function(a, b)
		return acen(R, a).X < acen(R, b).X
	end)
	for gi = 0, 1 do
		local grp = {}
		for j = 1, 4 do
			local r = panels[gi * 4 + j]
			if r then
				table.insert(grp, r)
			end
		end
		if #grp == 4 then
			local c = V3(0, 0, 0)
			for _, r in grp do
				c += acen(R, r)
			end
			c /= 4
			for _, r in grp do
				local pc = acen(R, r)
				local d = V3(pc.X - c.X, 0, pc.Z - c.Z)
				if d.Magnitude > 0.1 then
					local _, pmx = abox(R, r)
					local ar = R.A * CFrame.lookAt(V3(pc.X, pmx.Y + 0.02, pc.Z), V3(pc.X, pmx.Y + 0.02, pc.Z) + d.Unit)
					local col = r.part.Color
					K:free(function()
						local head = K:wedge("DanceArrowHead", V3(0.03, 0.42, 0.5), ar * CF(0, 0, -0.18) * ANG(PI / 2, 0, 0) * ANG(0, 0, 0), nl(lt(col, 0.5)))
						local shaft = K:box("DanceArrowShaft", V3(0.22, 0.03, 0.4), ar * CF(0, 0, 0.22), nl(lt(col, 0.5)))
						table.insert(out, { head, shaft })
					end)
				end
			end
		end
	end
	return out
end

-- 자판기 새 앞면 (맵 Display · Can 숨김): body rec, 앞 방향
local function vendingFront(K: any, R: any, body: any)
	local bmn, bmx = abox(R, body)
	local cc = (bmn + bmx) / 2
	-- 앞 = 방 안쪽 (뒷벽에서 먼 쪽)
	local dir = V3(0, 0, 1)
	local hw = (bmx.X - bmn.X) / 2
	local hd = (bmx.Z - bmn.Z) / 2
	local mf = R.A * CFrame.lookAt(V3(cc.X, 0, cc.Z), V3(cc.X, 0, cc.Z) - dir)
	local z = hd + 0.02
	local H = bmx.Y
	K:free(function()
		K:box("VendFace", V3(hw * 2 - 0.1, H - 0.3, 0.04), mf * CF(0, H / 2, z), lk(rgb(20, 80, 170)))
		-- 진열 창 (3단 x 5)
		local ww, wh = hw * 2 - 0.9, 3.0
		local wy = H - 0.55 - wh / 2
		local wx = -0.32
		K:box("VendWindowBack", V3(ww, wh, 0.03), mf * CF(wx, wy, z + 0.02), lk(rgb(245, 245, 245)))
		for row = 0, 2 do
			local y = wy - wh / 2 + 0.25 + row * 0.95
			K:box("VendShelf", V3(ww, 0.04, 0.4), mf * CF(wx, y, z + 0.2), Look.chrome)
			for j = 0, 4 do
				local x = wx - ww / 2 + 0.3 + j * (ww - 0.6) / 4
				local col = CARPET_COLS[(row * 5 + j) % #CARPET_COLS + 1]
				if (row + j) % 2 == 0 then
					K:vcyl("VendCan", 0.5, 0.28, mf * CF(x, y + 0.27, z + 0.22), lk(col, M.Metal))
				else
					K:vcyl("VendBottle", 0.55, 0.26, mf * CF(x, y + 0.3, z + 0.22), gl(lt(col, 0.2), 0.3))
					K:vcyl("VendBottleCap", 0.08, 0.14, mf * CF(x, y + 0.62, z + 0.22), lk(WHITE))
				end
				K:box("VendPriceBtn", V3(0.3, 0.12, 0.03), mf * CF(x, y - 0.1, z + 0.42), nl(if (row + j) % 3 == 0 then rgb(255, 80, 60) else rgb(80, 255, 140)))
			end
		end
		K:box("VendGlass", V3(ww + 0.06, wh + 0.06, 0.03), mf * CF(wx, wy, z + 0.45), gl(rgb(220, 236, 244), 0.78))
		local lamp = K:box("VendLamp", V3(ww, 0.08, 0.12), mf * CF(wx, wy + wh / 2 - 0.1, z + 0.36), Look.lampCool)
		K:light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 7, Brightness = 0.7, Angle = 120, Color = Look.coolLight })
		-- 오른쪽 결제부
		local px = hw - 0.42
		K:box("VendPayPanel", V3(0.6, 1.8, 0.05), mf * CF(px, 3.2, z + 0.03), lk(rgb(30, 30, 34)))
		K:box("VendCoinSlot", V3(0.06, 0.24, 0.02), mf * CF(px, 3.75, z + 0.06), nl(rgb(255, 70, 40)))
		K:box("VendBillSlot", V3(0.4, 0.05, 0.02), mf * CF(px, 3.35, z + 0.06), nl(rgb(60, 255, 120)))
		K:box("VendCardPad", V3(0.42, 0.42, 0.03), mf * CF(px, 2.8, z + 0.06), lk(rgb(230, 230, 230)))
		K:box("VendLCD", V3(0.46, 0.2, 0.02), mf * CF(px, 4.1, z + 0.06), { c = rgb(30, 200, 90), m = M.Neon })
		-- 꺼내는 곳
		K:box("VendOutlet", V3(hw * 2 - 0.8, 0.7, 0.06), mf * CF(0, 0.75, z + 0.03), lk(rgb(14, 14, 16)))
		K:box("VendFlap", V3(hw * 2 - 0.9, 0.6, 0.03), mf * CF(0, 0.75, z + 0.08), gl(rgb(60, 60, 70), 0.4))
		txt(K, "VendHeader", hw * 2 - 0.3, 0.35, mf * CF(0, H - 0.25, z + 0.05), "시원한 음료 · 1,200원~", WHITE, nil, F.GothamBlack, 1.2)
		txt(K, "VendTake", 1.4, 0.18, mf * CF(0, 1.2, z + 0.06), "꺼내는 곳", WHITE, nil, F.GothamBold)
	end)
end

-- 바닥에 서는 기계를 자리 확인 후 짓기 (정렬 x, z, yaw, 크기 = 회전 전 W x H x D, pcf 원점 = 발자국 가운데)
local function placeMachine(R: any, x: number, z: number, yaw: number, size: Vector3, pad: number, fn: (CFrame) -> any): any
	local pcf = at(R, x, z, yaw)
	if not place(R, pcf, size, pad, "machine") then
		R.K:note(string.format("machine spot busy @ %.1f,%.1f", x, z))
		return nil
	end
	local ok, res = pcall(fn, pcf)
	if not ok then
		R.K:note("machine error: " .. tostring(res))
		return nil
	end
	return res
end

-- 기계 발자국 (pcf 원점에서 앞뒤로 비대칭인 기계는 중심을 옮겨 빌더에 넘김)
local function footprint(R: any, x: number, z: number, yaw: number, w: number, h: number, dBack: number, dFront: number, pad: number, fn: (CFrame) -> any): any
	-- 기계 원점 (x, z) 에서 앞(+Z)으로 dFront, 뒤로 dBack 차지
	local mid = (dFront - dBack) / 2
	local c = at(R, x, z, yaw) * CF(0, 0, mid)
	local q = R.A:PointToObjectSpace(c.Position)
	local d = dFront + dBack
	if not place(R, R.A * CF(q.X, 0, q.Z) * ANG(0, yaw, 0), V3(math.max(0.2, w - 0.14), h, math.max(0.2, d - 0.14)), pad, "machine") then
		R.K:note(string.format("machine spot busy @ %.1f,%.1f", x, z))
		return nil
	end
	local ok, res = pcall(fn, at(R, x, z, yaw))
	if not ok then
		R.K:note("machine error: " .. tostring(res))
		return nil
	end
	return res
end

-- =========================================================================================================
-- 광안 게임랜드 홀 (arcade)
-- =========================================================================================================
-- 팔씨름 테이블 후보 (GwangalliPlayShared.Arcade.MACHINES gl_arm spots, 월드)
local ARM_SPOTS = { Vector3.new(-327, 6.75, 428), Vector3.new(-330, 6.75, 425), Vector3.new(-332, 6.75, 440), Vector3.new(-345, 6.75, 425) }

local function hallKeeps(R: any)
	local V = R.V
	-- 팔씨름: 서버 상자 6(X) x 4 x 7(Z) + 여유 1, 점수판 (+8.6) 까지
	for _, w in ARM_SPOTS do
		local p = V.cf:PointToObjectSpace(Vector3.new(w.X, V.cf.Y, w.Z))
		local q = R.A:PointToObjectSpace(p)
		keepBox(R, q.X - 4.6, q.Z - 4.1, q.X + 4.6, q.Z + 4.1, R.H - 0.3, "arm")
		host(R, q.X, q.Z)
	end
	-- 펀치 · 농구: 서 있는 자리 + 벽 점수판 자리
	local punch = V:first("PunchBase")
	if punch then
		local c = acen(R, punch)
		local pad = V:first("PunchPad")
		local dx = if pad then math.sign(acen(R, pad).X - c.X) else -1
		local sx = c.X + dx * 4.6
		keepBox(R, sx - 3.2, c.Z - 3.4, sx + 3.2, c.Z + 3.4, 7.5, "punch")
		host(R, sx, c.Z)
		-- 점수판 (side = +z, 6.5): 동전교환기 앞 또는 도전 사인 위
		keepBox(R, R.x1 - 3.4, c.Z + 3.6, R.x1 + 0.1, c.Z + 9.4, 8.2, "board")
	end
	for _, nm in { "FrontCabinet" } do
		for _, r in V.byName[nm] or {} do
			local c = acen(R, r)
			if c.X < -10 then
				local sz = c.Z + 3.4
				keepBox(R, c.X - 3.4, sz - 2.4, c.X + 3.4, sz + 2.6, 7.5, "basket")
				host(R, c.X, sz)
				keepBox(R, R.x0 - 0.1, sz - 4.5, R.x0 + 1.4, sz + 0.9, 8.6, "board")
			end
		end
	end
	-- 인형뽑기 앞 (프롬프트 · 손님 자리)
	for _, r in V.byName.PrizeDoor or {} do
		local c = acen(R, r)
		host(R, c.X, c.Z)
	end
	keepBox(R, -35.9, 7.5, -32.6, 34.5, 6.5, "claw")
	keepBox(R, -25.6, 18.6, -22.1, 32.6, 6.5, "claw")
	keepBox(R, -13.9, 18.6, -10.6, 32.6, 6.5, "claw")
	-- 입구 통로 · 비상구 · 화장실 문 앞
	keepBox(R, 5.4, 24.5, 18.8, R.z1, 9.5, "lane")
	keepBox(R, 6.0, 13.0, 12.6, 24.5, 9.5, "lane")
	keepBox(R, 25.4, R.z0, 36.6, R.z0 + 4.6, 8.5, "exit")
end

-- 홀 벽 · 천장 · 바닥 마감
local function hallShell(K: any, R: any)
	-- 걸레받이 (검정 + 네온 띠): 벽 따라 (기계 뒤에 가려져도 괜찮음)
	K:free(function()
		K:box("HallBaseboard", V3(0.06, 0.42, R.D - 0.2), at(R, R.x0 + 0.03, R.cz, 0, 0.21), Look.black)
		K:box("HallBaseboard", V3(0.06, 0.42, R.D - 0.2), at(R, R.x1 - 0.03, R.cz, 0, 0.21), Look.black)
		K:box("HallBaseboard", V3(R.W - 0.2, 0.42, 0.06), at(R, R.cx, R.z0 + 0.03, 0, 0.21), Look.black)
		K:box("HallBaseNeon", V3(0.03, 0.05, R.D - 0.4), at(R, R.x0 + 0.075, R.cz, 0, 0.36), nl(rgb(170, 70, 255)))
		K:box("HallBaseNeon", V3(0.03, 0.05, R.D - 0.4), at(R, R.x1 - 0.075, R.cz, 0, 0.36), nl(rgb(170, 70, 255)))
		K:box("HallBaseNeon", V3(R.W - 0.4, 0.05, 0.03), at(R, R.cx, R.z0 + 0.075, 0, 0.36), nl(rgb(170, 70, 255)))
	end)
	-- 천장: 스피커 · 스프링클러 · 감지기 (네온 줄 사이)
	for _, p in { { -25, 11 }, { -11, 23 }, { -11, -1 }, { 17, 23 }, { 17, -13 }, { -25, -25 }, { 3, -25 }, { 31, 33 } } do
		ceilSpeaker(K, R, p[1], p[2])
	end
	for _, x in { -25, -11, 3, 17, 31 } do
		for _, z in { 32.5, 20.5, 8.5, -3.5, -15.5, -27.5 } do
			if not (x == 3 and (z == 20.5 or z == -15.5)) then
				sprinkler(K, R, x + 1.6, z)
			end
		end
	end
	for _, p in { { -32 + 6, 2.5 }, { 10 + 4, -24.5 }, { -18 + 6, 26.5 }, { 24 + 7, 14.5 } } do
		smoke(K, R, p[1], p[2])
	end
	-- 매달린 존 사인
	zoneSign(K, R, -20.8, 9.5, 8.6, 7.0, 0, "VIDEO GAME", "대전 격투 · 레트로 50in1", rgb(60, 220, 255))
	zoneSign(K, R, 26.0, 29.0, 8.6, 6.4, 0, "PRIZE GAME", "경품 존 · 키마스터", rgb(255, 210, 60))
	zoneSign(K, R, 6.0, -26.0, 9.0, 6.4, 0, "BEAT ZONE", "리듬 · 댄스", rgb(255, 80, 200))
	zoneSign(K, R, 4.0, -1.0, 8.8, 6.0, PI / 2, "SPORTS", "에어하키 · 팔씨름 · 펀치", rgb(120, 255, 120))
	zoneSign(K, R, -22.0, -9.5, 9.0, 6.4, 0, "ACTION", "건슈팅 · 북 · 두더지", rgb(255, 120, 60))
end

-- 벽 포스터 · 안내 · 네온 아트
local function hallWalls(K: any, R: any)
	-- 왼벽 (x0)
	notice(K, wallL(R, -17.95, 6.4, 0.02), 2.4, 3.4, "청소년 출입시간", "게임산업진흥법에 따라\n청소년(만 18세 미만)은\n09:00 ~ 22:00 만 이용\n\n22시 이후 보호자 동반 필수", rgb(30, 90, 200))
	txt(K, "CCTVSticker", 2.0, 0.6, wallL(R, 35.7, 2.6, 0.02), "● CCTV 24시간 녹화중", WHITE, rgb(200, 30, 30), F.GothamBlack)
	poster(K, wallL(R, 6.4, 6.6, 0.02), 2.6, 3.6, { bg = rgb(16, 12, 40), a1 = rgb(255, 50, 80), a2 = rgb(255, 200, 40), title = "BUSAN\nFIGHTER", sub = "2026 신작 입고!\n대전 1판 500원", disc = rgb(255, 120, 40), tag = "VIDEO GAME" })
	poster(K, wallL(R, -1.05, 6.8, 0.02), 3.4, 3.8, { bg = rgb(10, 30, 50), a1 = rgb(60, 220, 255), a2 = rgb(255, 60, 200), title = "BEAT STEP\nXX", sub = "신곡 업데이트\n'광안대교 야경'", disc = rgb(60, 120, 255), tag = "RHYTHM" })
	poster(K, wallL(R, -8.3, 6.8, 0.02), 2.2, 3.4, { bg = rgb(40, 10, 10), a1 = rgb(120, 255, 80), a2 = rgb(255, 255, 255), title = "ZOMBIE\nHUNTER", sub = "2인 협동 1,000원", tag = "ACTION" })
	-- 인형뽑기 줄 위 네온 글씨
	K:free(function()
		local d = wallL(R, 21.0, 8.55, 0.04)
		K:plate("ClawNeonBacker", 15.0, 0.95, 0.03, d, lk(rgb(20, 14, 36)))
		txt(K, "ClawNeonText", 14.4, 0.8, d * CF(0, 0, 0.05), "♥ 인형뽑기 천국 ♥ 매일 신상 인형 입고 ♥", rgb(255, 120, 200), nil, F.FredokaOne, 2.2)
	end)
	-- 뒷벽 (z0)
	poster(K, wallB(R, -23.3, 4.6, 0.02), 3.8, 4.4, { bg = rgb(250, 120, 20), a1 = rgb(255, 255, 255), a2 = rgb(30, 30, 30), title = "농구왕\n챌린지", sub = "이번 주 최고 기록\n도전하세요!", fg = rgb(30, 20, 10), fg2 = rgb(255, 255, 255), disc = rgb(255, 220, 120), tag = "SPORTS" })
	notice(K, wallB(R, -23.3, 1.3, 0.02), 3.4, 1.6, "기기 고장 문의", "동전이 걸리거나 고장 나면\n경품 카운터로 말씀해 주세요", rgb(80, 80, 90))
	-- 비상구 · 화장실 사이: 피난 안내도
	K:free(function()
		local d = wallB(R, 30.98, 4.6, 0.02)
		K:plate("EvacFrame", 1.7, 2.4, 0.05, d, Look.alu)
		K:plate("EvacMap", 1.5, 2.2, 0.06, d, lk(rgb(250, 250, 246)))
		txt(K, "EvacTitle", 1.4, 0.3, d * CF(0, 0.9, 0.07), "피난 안내도", WHITE, rgb(0, 140, 70), F.GothamBlack)
		for j = 0, 3 do
			K:plate("EvacRoom", 0.5, 0.4, 0.065, d * CF(-0.35 + (j % 2) * 0.7, 0.25 - (j // 2) * 0.55, 0.005), lk(rgb(200, 220, 240)))
		end
		K:plate("EvacArrow", 0.9, 0.08, 0.07, d * CF(0, -0.6, 0.006), lk(rgb(0, 160, 80)))
		K:plate("EvacHere", 0.16, 0.16, 0.072, d * CF(0.3, -0.3, 0.007), lk(rgb(220, 30, 30)))
	end)
	-- 뒷벽 오른쪽 끝: 옥내소화전함 + 비상벨
	K:free(function()
		local d = wallB(R, 38.0, 2.9, 0.02)
		K:plate("HydrantBox", 2.4, 3.6, 0.35, d, lk(rgb(200, 26, 30)))
		K:plate("HydrantDoorLine", 0.04, 3.4, 0.37, d, lk(rgb(140, 16, 20)))
		K:plate("HydrantWindow", 1.6, 1.0, 0.36, d * CF(0, 0.9, 0), gl(rgb(220, 230, 236), 0.4))
		txt(K, "HydrantText", 2.0, 0.5, d * CF(0, -0.6, 0.37), "소화전", WHITE, nil, F.GothamBlack)
		K:plate("HydrantHandle", 0.1, 0.5, 0.42, d * CF(0.25, -0.1, 0), Look.chrome)
		Props.fireBell(K, wallB(R, 38.0, 5.6, 0.02))
	end)
	-- 오른벽 (x1) 뒤쪽 휴게 존 위
	notice(K, wallR(R, -36.2, 5.6, 0.02), 2.4, 3.0, "이용 수칙", "음식물 반입 금지\n기기 위 음료 금지\n실내 전 구역 금연\n분실물은 카운터 보관", rgb(220, 40, 50))
	notice(K, wallR(R, -32.6, 5.6, 0.02), 2.6, 3.0, "게임물 등급 안내", "전체이용가 · 12세 · 15세\n등급분류필 게임물만\n운영합니다\n게임물관리위원회", rgb(40, 120, 70))
	-- 레트로 위 네온
	K:free(function()
		local d = wallR(R, -11.0, 8.5, 0.04)
		K:plate("RetroNeonBacker", 14.0, 1.0, 0.03, d, lk(rgb(16, 14, 30)))
		txt(K, "RetroNeonText", 13.4, 0.82, d * CF(0, 0, 0.05), "★ RETRO GAMES · 추억의 오락실 ★", rgb(90, 220, 255), nil, F.Arcade, 2.2)
	end)
	-- 사업자 · 게임제공업 등록증 (경품 카운터 옆 벽, 높이 9 근처 비어 있음)
	Props.frame(K, wallR(R, 14.0, 6.6, 0.02), 1.0, 1.4, { frame = Look.goldMetal, text = "게임제공업\n등록증\n\n광안 게임랜드\n수영구청장", textH = 0.9, border = 0.05, depth = 0.05 })
end

-- 경품 카운터 보강: 뒤 라이트박스 · 선반 가격표 · POS · 티켓 계수기
local function prizeCorner(K: any, R: any)
	local V = R.V
	local top = V:first("PrizeCounterTop")
	local shelves = V.byName.PrizeShelf or {}
	if #shelves > 0 then
		local zmin, zmax, smin = math.huge, -math.huge, math.huge
		for _, s in shelves do
			local mn, mx = abox(R, s)
			zmin, zmax = math.min(zmin, mn.Z), math.max(zmax, mx.Z)
			smin = math.min(smin, mn.X)
		end
		K:free(function()
			local zc = (zmin + zmax) / 2
			local d = wallR(R, zc, 5.5, 0.01)
			K:plate("PrizeWallBack", zmax - zmin, 6.4, 0.03, d, lk(rgb(255, 236, 246)))
			local glow = K:plate("PrizeWallGlow", zmax - zmin - 0.2, 0.08, 0.04, wallR(R, zc, 8.6, 0.01), Look.lampWarm)
			K:light(glow, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 9, Brightness = 0.8, Angle = 120, Color = Look.warmLight })
			-- 가격표 (선반 앞 모서리)
			local tags = { "티켓 50장", "티켓 100장", "티켓 300장", "티켓 500장" }
			for si, s in shelves do
				local mn, mx = abox(R, s)
				for j = 0, 2 do
					local z = zmin + (zmax - zmin) * (j + 0.5) / 3
					local tc = R.A * CFrame.fromMatrix(V3(mn.X - 0.01, mx.Y - 0.12, z), V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
					txt(K, "PrizeTag", 1.2, 0.26, tc, tags[(si + j) % #tags + 1], rgb(200, 20, 60), rgb(255, 250, 220), F.GothamBlack)
				end
			end
		end)
	end
	if top then
		local mn, mx = abox(R, top)
		local y = mx.Y
		local cx = (mn.X + mx.X) / 2
		K:free(function()
			-- POS + 카드 단말 (카운터 남쪽 끝), 티켓 계수기 (북쪽 끝)
			local p = R.A * CFrame.lookAt(V3(cx + 0.6, y, mn.Z + 1.6), V3(cx + 0.6, y, mn.Z + 1.6) + V3(-1, 0, 0))
			p = p * ANG(0, 0, 0)
			K:box("PrizePOSBase", V3(0.5, 0.2, 0.5), p * CF(0, 0.1, 0), lk(rgb(30, 30, 34)))
			K:box("PrizePOSArm", V3(0.12, 0.7, 0.12), p * CF(0, 0.55, -0.1), lk(rgb(30, 30, 34)))
			K:box("PrizePOSScreen", V3(1.1, 0.75, 0.08), p * CF(0, 1.05, -0.05) * ANG(math.rad(-12), 0, 0), lk(rgb(20, 20, 24)))
			K:box("PrizePOSLCD", V3(1.0, 0.65, 0.02), p * CF(0, 1.05, 0.0) * ANG(math.rad(-12), 0, 0), { c = rgb(60, 130, 220), m = M.Neon })
			Props.cardTerminal(K, R.A * CFrame.lookAt(V3(cx - 0.9, y, mn.Z + 2.4), V3(cx - 0.9, y, mn.Z + 2.4) + V3(-1, 0, 0)))
			local tcf = R.A * CFrame.lookAt(V3(cx - 0.3, y, mx.Z - 1.4), V3(cx - 0.3, y, mx.Z - 1.4) + V3(-1, 0, 0))
			K:box("TicketCounter", V3(1.0, 0.9, 0.9), tcf * CF(0, 0.45, 0), lk(rgb(240, 200, 40)))
			K:box("TicketCounterMouth", V3(0.7, 0.08, 0.04), tcf * CF(0, 0.75, 0.46), lk(rgb(20, 20, 20)))
			K:box("TicketCounterLCD", V3(0.6, 0.22, 0.02), tcf * CF(0, 0.45, 0.46), { c = rgb(255, 60, 40), m = M.Neon })
			txt(K, "TicketCounterText", 0.56, 0.18, tcf * CF(0, 0.45, 0.48), "0350", rgb(255, 230, 220), nil, F.Arcade, 1.4)
			txt(K, "TicketCounterLabel", 0.9, 0.18, tcf * CF(0, 0.15, 0.46), "티켓 넣는 곳", rgb(20, 20, 20), nil, F.GothamBold)
			-- 티켓 묶음 (접힌 띠)
			for j = 0, 2 do
				K:box("TicketStack", V3(0.5, 0.18, 0.28), tcf * CF(0.1, 0.09 + j * 0.0, 1.2 + j * 0.35) * ANG(0, 0.2 * j, 0), lk(rgb(250, 120, 160)))
			end
		end)
	end
end

-- 동전교환기 아래쪽 보강 (서버 점수판 자리 위쪽은 비움)
local function coinExchangers(K: any, R: any)
	for i, r in R.V.byName.CoinExchanger or {} do
		local mn, mx = abox(R, r)
		local fx = mn.X - 0.01 -- 앞면 (-x 방향, 방 안쪽)
		local zc = (mn.Z + mx.Z) / 2
		local d = R.A * CFrame.fromMatrix(V3(fx, 0, zc), V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
		K:free(function()
			K:plate("ExchBillBezel", 1.2, 0.5, 0.06, d * CF(0, 3.8, 0), lk(rgb(30, 30, 34)))
			K:plate("ExchBillSlot", 0.9, 0.06, 0.03, d * CF(0, 3.8, 0.06), nl(rgb(60, 255, 120)))
			txt(K, "ExchBillText", 2.2, 0.32, d * CF(0, 3.35, 0.02), "1천 · 5천 · 1만원권 사용", WHITE, rgb(20, 60, 140), F.GothamBold)
			K:plate("ExchCoinOut", 1.4, 0.6, 0.05, d * CF(0, 1.0, 0), lk(rgb(16, 16, 18)))
			K:plate("ExchCoinLED", 1.2, 0.06, 0.03, d * CF(0, 1.35, 0.05), nl(rgb(255, 200, 40)))
			txt(K, "ExchCoinText", 1.6, 0.26, d * CF(0, 1.65, 0.02), "500원 동전 나오는 곳", rgb(255, 230, 120), nil, F.GothamBold)
			K:plate("ExchKick", 2.4, 0.3, 0.04, d * CF(0, 0.15, 0), Look.black)
			if i == 1 then
				txt(K, "ExchNo", 0.6, 0.6, d * CF(0.9, 2.4, 0.02), "1", WHITE, rgb(220, 40, 50), F.GothamBlack)
			else
				txt(K, "ExchNo", 0.6, 0.6, d * CF(0.9, 2.4, 0.02), "2", WHITE, rgb(40, 110, 220), F.GothamBlack)
			end
		end)
	end
end

-- 에어하키 보강: 몸체 LED 띠 · 코인 박스 · 위 조명 캐노피
local function airHockey(K: any, R: any)
	local body = R.V:first("TableBody")
	if not body then
		return
	end
	local mn, mx = abox(R, body)
	local c = (mn + mx) / 2
	K:free(function()
		for _, sx in { -1, 1 } do
			K:box("HockeyLED", V3(0.04, 0.08, mx.Z - mn.Z - 0.2), at(R, if sx < 0 then mn.X - 0.02 else mx.X + 0.02, c.Z, 0, 1.9), nl(rgb(60, 230, 255)))
			K:box("HockeyStripe", V3(0.03, 0.5, mx.Z - mn.Z - 0.4), at(R, if sx < 0 then mn.X - 0.015 else mx.X + 0.015, c.Z, 0, 1.0), lk(rgb(240, 240, 240)))
		end
		for _, sz in { -1, 1 } do
			local z = if sz < 0 then mn.Z - 0.02 else mx.Z + 0.02
			local d = R.A * CFrame.fromMatrix(V3(c.X, 0, z), V3(-sz, 0, 0), Vector3.yAxis, V3(0, 0, sz))
			K:plate("HockeyCoinBox", 1.0, 0.8, 0.12, d * CF(1.6, 1.3, 0), lk(rgb(30, 30, 34)))
			K:plate("HockeyCoinSlot", 0.06, 0.24, 0.02, d * CF(1.6, 1.4, 0.12), nl(rgb(255, 70, 40)))
			txt(K, "HockeyPrice", 0.9, 0.22, d * CF(1.6, 1.05, 0.13), "1,000원", WHITE, nil, F.GothamBold)
			txt(K, "HockeyGoal", 1.4, 0.3, d * CF(0, 1.9, 0.01), "GOAL", rgb(255, 230, 60), nil, F.GothamBlack, 1.3)
		end
	end)
end

-- 홀 바닥 기계 배치
local function hallMachines(K: any, R: any): any
	local made: any = { candy = {}, gacha = {}, kiddie = {}, prize = {} }
	-- VIDEO 블록 A: 대전 격투 3 + 3 (등 맞대기)
	local fight = { { "철권 레전드 8", "FIGHT!\nROUND 1", rgb(200, 30, 40) }, { "부산 파이터 2026", "SELECT\nYOUR FIGHTER", rgb(240, 120, 20) }, { "KING OF 광안리", "K.O.!", rgb(140, 40, 220) } }
	local retro = { { "보글보글 클래식", "BUBBLE POP\nSTAGE 12", rgb(40, 150, 240) }, { "갤럭시 슈터 1987", "HI-SCORE\n088400", rgb(40, 200, 120) }, { "테트로 배틀", "LINE CLEAR!\nLV 15", rgb(240, 200, 30) } }
	local function block(x0: number, zc: number, list: { any }, list2: { any }, seed: number)
		for i = 0, 2 do
			local x = x0 + i * 3.06
			local a = list[i + 1]
			local b = list2[i + 1]
			local m1 = footprint(R, x, zc + 1.65, 0, 2.95, 6.0, 1.65, 3.0, 0, function(p)
				return candy(K, p, { title = a[1], screen = a[2], accent = a[3], scr = dk(a[3], 0.55), body = rgb(236, 234, 228), seat = dk(a[3], 0.1) })
			end)
			if m1 then
				table.insert(made.candy, m1)
			end
			local m2 = footprint(R, x, zc - 1.65, PI, 2.95, 6.0, 1.65, 3.0, 0, function(p)
				return candy(K, p, { title = b[1], screen = b[2], accent = b[3], scr = dk(b[3], 0.55), body = rgb(30, 30, 36), seat = rgb(30, 30, 36), coin = "500원" })
			end)
			if m2 then
				table.insert(made.candy, m2)
			end
		end
	end
	block(-30.2, 9.0, fight, retro, 1)
	block(-19.2, 9.0, { retro[2], fight[3], retro[1] }, { fight[1], retro[3], fight[2] }, 2)
	-- ACTION 줄 (앞 = +z): 건슈팅 · 북 · 두더지
	made.gun = footprint(R, -28.6, -8.2, 0, 5.4, 7.4, 2.7, 1.8, 0, function(p)
		return gunCabinet(K, p, {})
	end)
	made.drum = footprint(R, -21.8, -8.6, 0, 4.5, 6.8, 2.3, 1.7, 0, function(p)
		return drumGame(K, p, {})
	end)
	made.mole = footprint(R, -16.4, -8.1, 0, 3.1, 6.6, 2.3, 1.4, 0, function(p)
		return moleGame(K, p, {})
	end)
	made.gun2 = footprint(R, -10.0, -8.2, 0, 5.4, 7.4, 2.7, 1.8, 0, function(p)
		return gunCabinet(K, p, { title = "DEEP SEA SHOOTER", screen = "광안 앞바다\n상어 출현!", accent = rgb(60, 160, 255) })
	end)
	-- BEAT 존: 댄스 (뒷벽 레이싱과 댄스비트 사이)
	made.dance = footprint(R, 5.9, R.z0 + 2.7, 0, 7.3, 8.6, 2.65, 5.7, 0, function(p)
		return danceMachine(K, p, {})
	end)
	-- PRIZE 존 (입구 오른쪽 창가): 경품 기계 4 (앞 = -z)
	local kinds = { { "key", "KEY MASTER", rgb(255, 200, 40) }, { "cut", "가위 자르기", rgb(255, 80, 160) }, { "key", "럭키 박스", rgb(80, 220, 255) }, { "cut", "선물 뽑기", rgb(120, 255, 120) } }
	for i, k in kinds do
		local m = footprint(R, 21.5 + (i - 1) * 3.12, 32.9, PI, 2.95, 6.6, 1.45, 1.5, 0, function(p)
			return prizeMachine(K, p, { kind = k[1], title = k[2], accent = k[3] }, i * 3)
		end)
		if m then
			table.insert(made.prize, m)
		end
	end
	-- 가챠 벽 (왼벽, 안내판 아래)
	local themes = {
		{ { "갈매기 키링", rgb(80, 160, 230), "3,000원" }, { "광안대교 마그넷", rgb(40, 90, 190), "3,000원" } },
		{ { "미니 피규어", rgb(240, 80, 120), "5,000원" }, { "동물 잠옷 인형", rgb(250, 160, 190), "4,000원" } },
		{ { "부산 사투리 뱃지", rgb(250, 190, 40), "2,000원" }, { "미니 어묵 키링", rgb(230, 120, 40), "3,000원" } },
		{ { "공룡 캡슐", rgb(80, 190, 90), "3,000원" }, { "고양이 피규어", rgb(160, 110, 220), "4,000원" } },
		{ { "랜덤 스티커", rgb(255, 120, 60), "1,000원" }, { "반짝 반지", rgb(230, 70, 200), "2,000원" } },
	}
	for i, th in themes do
		local z = -8.6 + (i - 1) * 1.8
		local m = footprint(R, R.x0 + 0.92, z, PI / 2, 1.75, 4.6, 0.85, 0.85, 0, function(p)
			return gachaStack(K, p, th, i)
		end)
		if m then
			table.insert(made.gacha, m)
		end
	end
	-- 키디라이드 2 (입구 왼쪽 창가, 앞 = -z)
	for i, k in { { -7.4, rgb(230, 40, 50), "빵빵이" }, { -2.4, rgb(40, 140, 230), "씽씽이" } } do
		local m = footprint(R, k[1], 32.6, PI, 2.5, 3.4, 2.1, 2.5, 0, function(p)
			return kiddieRide(K, p, { body = k[2], name = k[3] })
		end)
		if m then
			table.insert(made.kiddie, m)
		end
	end
	-- 휴게 존 (오른벽 뒤쪽)
	footprint(R, R.x1 - 0.62, -23.4, -PI / 2, 1.2, 4.0, 0.62, 0.7, 0, function(p)
		purifier(K, p)
		return true
	end)
	footprint(R, R.x1 - 0.5, -27.6, -PI / 2, 2.9, 2.6, 0.5, 0.5, 0, function(p)
		bins(K, p)
		return true
	end)
	footprint(R, R.x1 - 0.5, -20.4, -PI / 2, 1.1, 3.7, 0.45, 0.45, 0, function(p)
		charger(K, p)
		return true
	end)
	footprint(R, R.x1 - 0.75, -31.6, -PI / 2, 3.6, 2.2, 0.7, 0.7, 0, function(p)
		bench(K, p, 3.4)
		return true
	end)
	return made
end

-- 홀 상호작용 + 애니메이션
local function hallInteract(K: any, R: any, made: any, clawLeds: { BasePart })
	-- 1) 대전 격투 데모 화면 (cycle): 서버 자리에서 가장 먼 기계
	local cand = nil
	local bestD = -1
	for _, c in made.candy do
		if c.screen and c.screen.Parent then
			local q = R.A:PointToObjectSpace(R.V.cf:PointToObjectSpace(c.screen.Position))
			local dmin = math.huge
			for _, h in R.hosts do
				dmin = math.min(dmin, (V3(q.X, 0, q.Z) - h).Magnitude)
			end
			if dmin > bestD then
				cand, bestD = c, dmin
			end
		end
	end
	if cand and cand.screen then
		local frames = {
			{ "SELECT\nYOUR FIGHTER", rgb(40, 30, 110) },
			{ "ROUND 1\nFIGHT!", rgb(130, 20, 20) },
			{ "K.O.!\nPERFECT", rgb(200, 120, 10) },
			{ "오늘의 랭킹\n1위 광안불주먹", rgb(20, 90, 60) },
		}
		prompt(R, cand.screen, "cycle", {
			action = "데모 화면 넘기기",
			object = "대전 격투 기계",
			on = function(_i: number, f: any)
				if cand.label then
					cand.label.Text = f[1]
				end
				cand.screen.Color = f[2]
			end,
		}, frames)
	end
	-- 2) 댄스 데모 모드 (toggle): 발판 화살표가 박자에 맞춰 번쩍
	local dm = made.dance
	if dm and dm.screen then
		local demo = false
		prompt(R, dm.screen, "toggle", {
			object = "BEAT STEP 데모 모드",
			onText = "데모 끄기",
			offText = "데모 켜기",
			state = false,
			on = function(s: boolean)
				demo = s
				if dm.label then
					dm.label.Text = if s then "DEMO PLAY\n♪ 광안리 연가 ♪  x128 COMBO" else "SELECT SONG\n♪ 광안대교 야경 ♪"
				end
			end,
		})
		Interact.anim(K, function(t: number)
			for i, a in dm.arrows do
				local beat = math.floor(t * 4)
				local lit = if demo then ((beat + i) % 5 == 0 or (beat * 3 + i) % 7 == 0) else ((math.floor(t * 1.5) + i) % 10 == 0)
				for _, gp in a.glyph do
					if gp.Parent then
						gp.Color = if lit then lt(a.c, 0.6) else a.c
					end
				end
				if a.tile.Parent then
					a.tile.Color = if lit then a.c else dk(a.c, 0.35)
					a.tile.Material = if lit then M.Neon else M.SmoothPlastic
				end
			end
		end)
	end
	-- 3) 가챠 핸들 돌려보기 (캡슐이 나왔다가 사라짐 - 구경용)
	local gs = made.gacha[3] or made.gacha[1]
	if gs and gs.handles[1] then
		local h = gs.handles[1]
		local busy = false
		prompt(R, h.knob, "prompt", {
			action = "핸들 돌려보기",
			object = "캡슐 토이 (구경)",
			sound = "rbxasset://sounds/clickfast.wav",
			fn = function()
				if busy then
					return
				end
				busy = true
				local c0 = h.bar.CFrame
				task.spawn(function()
					for k = 1, 8 do
						if h.bar.Parent then
							h.bar.CFrame = h.cf * CF(0, 0, -0.04) * ANG(0, 0, k * PI / 4) * CF(0, 0, 0)
						end
						task.wait(0.05)
					end
					if h.bar.Parent then
						h.bar.CFrame = c0
					end
					local cap = Instance.new("Part")
					cap.Name = "GachaCapsuleOut"
					cap.Shape = Enum.PartType.Ball
					Kit.apply(cap, lk(CARPET_COLS[math.random(1, #CARPET_COLS)]))
					cap.Size = V3(0.34, 0.34, 0.34)
					cap.CFrame = h.cf * CF(0.67, -0.25, 0.05)
					cap.Parent = h.bar.Parent
					task.wait(3)
					cap:Destroy()
					busy = false
				end)
			end,
		})
	end
	-- 4) 키디라이드 흔들기 (구경용 애니)
	local kd = made.kiddie[1]
	if kd and kd.parts[1] then
		local base = {}
		for _, p in kd.parts do
			table.insert(base, { p = p, cf = p.CFrame })
		end
		local rockUntil = 0
		local now = 0
		prompt(R, kd.parts[1], "prompt", {
			action = "흔들어 보기",
			object = "키디라이드 빵빵이",
			fn = function()
				rockUntil = now + 4
			end,
		})
		Interact.anim(K, function(t: number)
			now = t
			if t < rockUntil then
				local a = math.sin(t * 9) * 0.06
				local pivot = kd.base
				for _, b in base do
					if b.p.Parent then
						b.p.CFrame = pivot * ANG(a * 0.5, 0, a) * pivot:ToObjectSpace(b.cf)
					end
				end
			elseif t < rockUntil + 0.2 then
				for _, b in base do
					if b.p.Parent then
						b.p.CFrame = b.cf
					end
				end
			end
		end)
	end
	-- 프롬프트 없는 애니: 인형뽑기 LED 색 순환 · 경품 마키 깜빡 · 두더지
	if #clawLeds > 0 then
		Interact.anim(K, function(t: number)
			for i, p in clawLeds do
				if p.Parent then
					p.Color = hsv(t * 0.12 + i * 0.07, 0.75, 1)
				end
			end
		end)
	end
	if made.mole then
		local ml = made.mole
		Interact.anim(K, function(t: number)
			for i, m in ml.moles do
				local up = math.max(0, math.sin(t * 2.2 + i * 1.7)) * 0.45 - 0.05
				if m.head.Parent then
					m.head.CFrame = K.cf * m.base * CF(0, up, 0)
					m.nose.CFrame = K.cf * m.base * CF(0, up + 0.05, 0.24)
				end
			end
		end)
	end
	local loops = {}
	for _, pm in made.prize do
		if pm.marquee then
			table.insert(loops, pm.marquee)
		end
	end
	if #loops > 0 then
		local base = {}
		for _, p in loops do
			table.insert(base, p.Color)
		end
		Interact.anim(K, function(t: number)
			for i, p in loops do
				if p.Parent then
					local on = (math.floor(t * 2) + i) % 3 ~= 0
					p.Color = if on then base[i] else dk(base[i], 0.5)
				end
			end
		end)
	end
end

local function buildHall(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	hallKeeps(R)
	-- 카펫 색종이 숨김 (새 카펫 무늬로 대신)
	for _, r in V.byName.CarpetConfetti or {} do
		Scan.hide(K.hidden, r.part)
	end
	-- 자판기 앞면 새로 (Display · Can 숨김)
	local vb = V:first("Body")
	if vb then
		Scan.hide(K.hidden, (V:first("Display") or vb).part)
		for _, r in V.byName.Can or {} do
			Scan.hide(K.hidden, r.part)
		end
		if V:first("Display") then
			vendingFront(K, R, vb)
		end
		K.hidden[vb.part] = nil
	end
	local ok, err = pcall(hallShell, K, R)
	if not ok then
		K:note("hall shell error: " .. tostring(err))
	end
	ok, err = pcall(hallWalls, K, R)
	if not ok then
		K:note("hall walls error: " .. tostring(err))
	end
	-- 기존 기계 오버레이
	local clawLeds = {}
	for i, g in machines(V, "^ClawMachine_%d+$") do
		local ok2, res = pcall(clawOverlay, K, R, g, i)
		if ok2 then
			for _, p in res do
				table.insert(clawLeds, p)
			end
		else
			K:note("claw overlay error: " .. tostring(res))
		end
	end
	for i, g in machines(V, "^RetroCabinet_%d+$") do
		local ok2, e2 = pcall(retroOverlay, K, R, g, i)
		if not ok2 then
			K:note("retro overlay error: " .. tostring(e2))
		end
	end
	for i, g in machines(V, "^RacingCabinet_%d+$") do
		local ok2, e2 = pcall(racingOverlay, K, R, g, i)
		if not ok2 then
			K:note("racing overlay error: " .. tostring(e2))
		end
	end
	for _, g in machines(V, "DanceBeat") do
		pcall(danceArrows, K, R, g)
	end
	pcall(prizeCorner, K, R)
	pcall(coinExchangers, K, R)
	pcall(airHockey, K, R)
	-- 새 기계
	local made: any = {}
	ok, err = pcall(function()
		made = hallMachines(K, R)
	end)
	if not ok then
		K:note("hall machines error: " .. tostring(err))
		made = made or {}
	end
	-- 불빛 (기계 화면 · 존)
	pcall(function()
		local function glow(p: BasePart?, c: Color3, range: number)
			if p then
				K:light(p, "SurfaceLight", { Face = Enum.NormalId.Back, Range = range, Brightness = 0.9, Angle = 110, Color = c })
			end
		end
		if made.dance then
			glow(made.dance.screen, rgb(170, 110, 255), 12)
		end
		if made.candy and made.candy[1] then
			glow(made.candy[1].screen, rgb(120, 160, 255), 9)
		end
		if made.candy and made.candy[8] then
			glow(made.candy[8].screen, rgb(120, 255, 200), 9)
		end
		if made.gun then
			glow(made.gun.screen, rgb(255, 120, 100), 10)
		end
		if made.prize and made.prize[2] then
			glow(made.prize[2].marquee, rgb(255, 210, 120), 10)
		end
	end)
	-- 문 앞 매트
	K:free(function()
		local d = V.door
		if d then
			local q = R.A:PointToObjectSpace(V3(d.x, 0, d.z))
			K:box("HallDoorMat", V3(11.6, 0.04, 2.6), at(R, q.X, R.z1 - 1.8, 0, 0.02), lk(rgb(30, 30, 34), M.Fabric))
			K:box("HallDoorMatEdge", V3(11.8, 0.035, 2.7), at(R, q.X, R.z1 - 1.8, 0, 0.0175), Look.rubber)
			txt(K, "HallDoorMatText", 6.4, 1.3, topCF(ap(R, q.X, 0.045, R.z1 - 1.8), R.A:VectorToWorldSpace(V3(0, 0, -1))), "WELCOME · 광안 게임랜드", rgb(255, 120, 200), nil, F.GothamBlack, nil, { free = true })
		end
	end)
	-- 카펫 무늬 (기계 자리 빼고)
	pcall(carpetPrint, K, R, R.x0 + 0.4, R.x1 - 0.4, R.z0 + 0.4, R.z1 - 2.8, if lowD(K) then 10 else 7.4, 17)
	pcall(hallInteract, K, R, made, clawLeds)
end

-- =========================================================================================================
-- 셀프사진관 찰칵 (photo)
-- =========================================================================================================
local function photoBooth(K: any, R: any, x0: number, x1: number, z0: number, z1: number): any
	local out: any = {}
	local H = 7.4
	local white = lk(rgb(250, 250, 248))
	local pink = rgb(255, 150, 190)
	local front = z1
	local openA, openB = x0 + 2.0, x1 - 0.35 -- 커튼 구간
	K:free(function()
		-- 몸체: 옆판 · 지붕 · 뒷판 · 앞판 (키오스크 쪽) · 상단 띠
		K:box("BoothSide", V3(0.16, H, z1 - z0), at(R, x0 + 0.08, (z0 + z1) / 2, 0, H / 2), white)
		K:box("BoothSide", V3(0.16, H, z1 - z0), at(R, x1 - 0.08, (z0 + z1) / 2, 0, H / 2), white)
		K:box("BoothRoof", V3(x1 - x0, 0.2, z1 - z0), at(R, (x0 + x1) / 2, (z0 + z1) / 2, 0, H - 0.1), white)
		K:box("BoothBack", V3(x1 - x0 - 0.3, H - 0.2, 0.12), at(R, (x0 + x1) / 2, z0 + 0.08, 0, (H - 0.2) / 2), white)
		K:box("BoothFrontL", V3(openA - x0, H, 0.18), at(R, (x0 + openA) / 2, front - 0.09, 0, H / 2), white)
		K:box("BoothFrontR", V3(x1 - openB, H, 0.18), at(R, (openB + x1) / 2, front - 0.09, 0, H / 2), white)
		K:box("BoothHeader", V3(openB - openA, H - 6.3, 0.18), at(R, (openA + openB) / 2, front - 0.09, 0, 6.3 + (H - 6.3) / 2), white)
		K:box("BoothPinkBand", V3(x1 - x0 + 0.04, 0.35, 0.04), at(R, (x0 + x1) / 2, front + 0.02, 0, 0.5), lk(pink))
		K:box("BoothPinkBand", V3(0.04, 0.35, z1 - z0), at(R, x1 + 0.02, (z0 + z1) / 2, 0, 0.5), lk(pink))
		K:box("BoothKick", V3(x1 - x0, 0.2, 0.05), at(R, (x0 + x1) / 2, front + 0.03, 0, 0.1), lk(rgb(230, 230, 228)))
		-- 브랜드 네온 (앞 위)
		local hd = R.A * CFrame.fromMatrix(V3((x0 + x1) / 2, H - 0.55, front + 0.02), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1))
		K:plate("BoothLogoBack", x1 - x0 - 0.4, 0.9, 0.04, hd, lk(rgb(255, 228, 238)))
		txt(K, "BoothLogo", x1 - x0 - 0.8, 0.72, hd * CF(0, 0, 0.05), "찰칵 PHOTO ♥", rgb(255, 70, 140), nil, F.FredokaOne, 1.8)
		-- 옆면 (방 쪽 +x): 샘플 사진 스트립 + 가격
		local sd = R.A * CFrame.fromMatrix(V3(x1 + 0.03, 0, (z0 + z1) / 2), V3(0, 0, 1), Vector3.yAxis, V3(1, 0, 0))
		txt(K, "BoothSidePrice", 2.8, 1.0, sd * CF(0, 6.0, 0), "4컷 4,000원\n6컷 5,000원", rgb(255, 80, 140), rgb(255, 245, 250), F.GothamBlack)
		for j = 0, 3 do
			local sx = -1.65 + j * 1.1
			K:plate("BoothSampleStrip", 0.8, 2.4, 0.03, sd * CF(sx, 3.8, 0), lk(WHITE))
			for k = 0, 3 do
				K:plate("BoothSampleShot", 0.66, 0.5, 0.035, sd * CF(sx, 4.75 - k * 0.58, 0.002), lk(hsv(0.92 + j * 0.05 + k * 0.03, 0.3, 0.95)))
			end
		end
		txt(K, "BoothSideTag", 3.2, 0.36, sd * CF(0, 2.3, 0), "#광안리네컷 #찰칵", rgb(120, 120, 130), nil, F.GothamBold)
		-- 안쪽: 배경지 (오른쪽 안벽) · 카메라/모니터 (왼쪽 안벽) · 벤치
		local bd = R.A * CFrame.fromMatrix(V3(x1 - 0.17, 0, (z0 + z1) / 2 - 0.2), V3(0, 0, 1), Vector3.yAxis, V3(-1, 0, 0))
		K:plate("BoothBackdrop", z1 - z0 - 0.6, H - 0.6, 0.03, bd * CF(0, (H - 0.6) / 2 + 0.05, 0), lk(rgb(255, 214, 228), M.Fabric))
		K:plate("BoothBackdropRoll", z1 - z0 - 0.4, 0.3, 0.3, bd * CF(0, H - 0.5, 0), lk(rgb(230, 230, 232)))
		local cd = R.A * CFrame.fromMatrix(V3(x0 + 0.17, 0, (z0 + z1) / 2 - 0.2), V3(0, 0, -1), Vector3.yAxis, V3(1, 0, 0))
		K:plate("BoothCamPanel", 2.4, 3.6, 0.2, cd * CF(0, 3.9, 0), lk(rgb(30, 30, 34)))
		local mon = K:plate("BoothMonitor", 1.9, 1.15, 0.03, cd * CF(0, 3.5, 0.21), { c = rgb(255, 190, 210), m = M.Neon, t = 0.05 })
		local _, ml = txt(K, "BoothMonitorText", 1.8, 0.9, cd * CF(0, 3.5, 0.25), "화면을 터치하세요\n♥ 3 · 2 · 1 ♥", rgb(120, 30, 70), nil, F.FredokaOne, 1.2)
		out.monitor, out.monLabel = mon, ml
		wdisc(K, "BoothCamLens", 0.34, 0.12, cd * CF(0, 4.6, 0.2), lk(rgb(16, 16, 18), M.Glass))
		wdisc(K, "BoothCamRing", 0.5, 0.08, cd * CF(0, 4.6, 0.2), Look.chrome)
		-- 링라이트
		local ring = cd * CF(0, 4.6, 0.32)
		local rl = K:ring("BoothRingLight", ring, 0.95, 0.14, 12, Look.lampNeutral)
		out.ring = rl
		K:plate("BoothSoftbox", 2.2, 0.8, 0.3, cd * CF(0, 6.2, 0.1) * ANG(math.rad(-25), 0, 0), lk(rgb(250, 250, 250)))
		K:plate("BoothSoftboxFace", 2.0, 0.6, 0.02, cd * CF(0, 6.2, 0.41) * ANG(math.rad(-25), 0, 0), Look.lampNeutral)
		K:box("BoothShutterBtn", V3(0.4, 0.15, 0.4), at(R, x0 + 1.0, z1 - 1.1, 0, 2.6), lk(rgb(255, 80, 140)))
		K:box("BoothShutterStand", V3(0.12, 2.5, 0.12), at(R, x0 + 1.0, z1 - 1.1, 0, 1.3), Look.chrome)
		-- 벤치
		K:box("BoothBench", V3(1.6, 0.4, z1 - z0 - 1.6), at(R, x1 - 1.3, (z0 + z1) / 2 - 0.2, 0, 1.6), lk(rgb(250, 250, 250), M.Leather))
		K:box("BoothBenchBase", V3(1.4, 1.4, z1 - z0 - 1.8), at(R, x1 - 1.3, (z0 + z1) / 2 - 0.2, 0, 0.7), lk(rgb(236, 236, 234)))
		K:box("BoothFloor", V3(x1 - x0 - 0.3, 0.04, z1 - z0 - 0.3), at(R, (x0 + x1) / 2, (z0 + z1) / 2, 0, 0.03), lk(rgb(240, 230, 236)))
		-- 커튼 레일
		K:box("BoothCurtainRail", V3(openB - openA + 0.2, 0.1, 0.1), at(R, (openA + openB) / 2, front + 0.08, 0, 6.25), Look.chrome)
	end)
	-- 커튼 (주름 8): 닫힘 = 고르게, 열림 = 오른쪽으로 모임
	local folds = {}
	local n = 8
	local span = openB - openA
	K:free(function()
		for i = 1, n do
			local u = (i - 0.5) / n
			local x = openA + span * u
			local p = K:box("BoothCurtain", V3(span / n + 0.08, 5.8, 0.1), at(R, x, front + 0.12 + (i % 2) * 0.06, (i % 2 == 0) and 0.22 or -0.22, 3.3), lk(rgb(240, 90, 150), M.Fabric))
			table.insert(folds, { p = p, closed = p.CFrame, open = K.cf * at(R, openB - 0.15 - (n - i) * 0.12, front + 0.12 + (i % 2) * 0.06, (i % 2 == 0) and 0.9 or -0.9, 3.3) })
		end
	end)
	out.folds = folds
	out.curtainAnchor = folds[2] and folds[2].p
	-- 결제 키오스크 (앞판 왼쪽)
	K:free(function()
		local kd = R.A * CFrame.fromMatrix(V3(x0 + 0.95, 0, front + 0.02), V3(1, 0, 0), Vector3.yAxis, V3(0, 0, 1))
		K:plate("KioskBody", 1.5, 3.2, 0.25, kd * CF(0, 3.1, 0), lk(rgb(40, 40, 46)))
		local scr = K:plate("KioskScreen", 1.2, 1.6, 0.03, kd * CF(0, 3.6, 0.26), { c = rgb(255, 200, 220), m = M.Neon, t = 0.05 })
		local _, kl = txt(K, "KioskText", 1.1, 1.3, kd * CF(0, 3.6, 0.3), "프레임을\n선택하세요\n\n화이트 ▶", rgb(80, 30, 60), nil, F.GothamBold, 1.1)
		out.kiosk, out.kioskLabel = scr, kl
		K:plate("KioskCardSlot", 0.7, 0.08, 0.04, kd * CF(0, 2.5, 0.26), nl(rgb(60, 220, 120)))
		K:plate("KioskBill", 0.8, 0.3, 0.05, kd * CF(0, 2.15, 0.26), lk(rgb(20, 20, 24)))
		K:plate("KioskPrintOut", 0.9, 0.12, 0.05, kd * CF(0, 1.7, 0.26), lk(rgb(16, 16, 18)))
		txt(K, "KioskPrintLabel", 1.1, 0.18, kd * CF(0, 1.45, 0.27), "사진 나오는 곳", WHITE, nil, F.GothamBold)
		txt(K, "KioskPay", 1.3, 0.22, kd * CF(0, 4.6, 0.27), "카드 · 현금 · 페이", WHITE, nil, F.GothamBold)
	end)
	return out
end

local function buildPhoto(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	local counter = V:first("Counter")
	local cmn, cmx = V3(0.5, 0, -3.6), V3(4.2, 3.3, -1.5)
	if counter then
		cmn, cmx = abox(R, counter)
		local cc = (cmn + cmx) / 2
		host(R, cc.X, cc.Z)
		host(R, cc.X, R.z0 + 0.6)
		-- 알바생 자리: 카운터 뒤 ~ 뒷벽 (높이 6.5)
		keepBox(R, cmn.X - 0.4, R.z0, cmx.X + 0.6, cmn.Z, 6.5, "staff")
		-- 손님 자리: 카운터 앞 2.6
		keepBox(R, cmn.X, cmx.Z, cmx.X, cmx.Z + 2.6, 6.0, "aisle")
	end
	local ceilY = R.H
	-- 바닥 (화이트 포세린 600각) · 천장 · 뒷벽 스킨 (맵 바닥이 벽까지 안 닿는 틈 덮기)
	K:free(function()
		K:box("PhotoFloor", V3(R.W, 0.03, R.D), at(R, R.cx, R.cz, 0, 0.015), lk(rgb(244, 242, 240), M.Marble, { r = 0.05 }))
		local x = R.x0 + 2
		while x < R.x1 - 0.2 do
			K:box("PhotoGrout", V3(0.03, 0.034, R.D), at(R, x, R.cz, 0, 0.017), lk(rgb(210, 206, 204)))
			x += 2
		end
		local z = R.z0 + 2
		while z < R.z1 - 0.2 do
			K:box("PhotoGrout", V3(R.W, 0.034, 0.03), at(R, R.cx, z, 0, 0.017), lk(rgb(210, 206, 204)))
			z += 2
		end
		K:box("PhotoCeiling", V3(R.W, 0.06, R.D), at(R, R.cx, R.cz, 0, ceilY - 0.03), lk(rgb(250, 250, 250), M.Plaster))
		K:box("PhotoBackSkin", V3(R.W, ceilY, 0.03), at(R, R.cx, R.z0 + 0.015, 0, ceilY / 2), lk(rgb(255, 246, 250)))
		K:box("PhotoLeftSkin", V3(0.03, ceilY, R.D), at(R, R.x0 + 0.015, R.cz, 0, ceilY / 2), lk(rgb(255, 246, 250)))
		K:box("PhotoRightSkin", V3(0.03, ceilY, R.D), at(R, R.x1 - 0.015, R.cz, 0, ceilY / 2), lk(rgb(255, 246, 250)))
		-- 걸레받이 (핑크)
		K:box("PhotoBase", V3(R.W, 0.35, 0.05), at(R, R.cx, R.z0 + 0.05, 0, 0.175), lk(rgb(255, 170, 200)))
		K:box("PhotoBase", V3(0.05, 0.35, R.D), at(R, R.x1 - 0.05, R.cz, 0, 0.175), lk(rgb(255, 170, 200)))
		-- 천장 조명판 테두리 + 다운라이트 + 설비
		local sl = V:first("ShopLight")
		if sl then
			local smn, smx = abox(R, sl)
			local sc = (smn + smx) / 2
			local w, d = smx.X - smn.X, smx.Z - smn.Z
			for _, s in { -1, 1 } do
				K:box("PhotoLightFrame", V3(w + 0.2, 0.12, 0.1), at(R, sc.X, sc.Z + s * (d / 2 + 0.05), 0, smn.Y + 0.06), Look.white)
				K:box("PhotoLightFrame", V3(0.1, 0.12, d + 0.2), at(R, sc.X + s * (w / 2 + 0.05), sc.Z, 0, smn.Y + 0.06), Look.white)
			end
			for _, p in { { smn.X + 1.0, smn.Z + 1.0 }, { smx.X - 1.0, smx.Z - 1.0 } } do
				K:vcyl("PhotoLightHanger", ceilY - smx.Y, 0.04, at(R, p[1], p[2], 0, (ceilY + smx.Y) / 2), Look.chrome)
			end
		end
	end)
	sprinkler(K, R, R.x1 - 1.0, R.z1 - 1.2)
	smoke(K, R, R.cx + 3.0, R.z1 - 0.9)
	K:free(function()
		K:disc("PhotoCCTVBase", 0.6, 0.06, at(R, R.x1 - 0.8, R.z0 + 0.8, 0, ceilY - 0.03), Look.white)
		K:ell("PhotoCCTV", V3(0.5, 0.5, 0.5), at(R, R.x1 - 0.8, R.z0 + 0.8, 0, ceilY - 0.06), gl(rgb(40, 46, 52), 0.15))
	end)
	-- 카운터 오버레이 (같은 자세: 핑크 루버 앞판 + 화이트 상판) — 원본은 숨기지 않고 바깥 0.02 스킨
	local made: any = {}
	if counter then
		K:free(function()
			local c = (cmn + cmx) / 2
			local w, d, h = cmx.X - cmn.X, cmx.Z - cmn.Z, cmx.Y
			K:box("PhotoCounterTop", V3(w + 0.2, 0.14, d + 0.2), at(R, c.X, c.Z, 0, h + 0.07), lk(rgb(250, 248, 246), M.Marble))
			local n = math.floor(w / 0.3)
			for i = 0, n - 1 do
				K:cyl("PhotoCounterFlute", h - 0.4, 0.28, at(R, cmn.X + 0.15 + i * (w - 0.3) / math.max(1, n - 1), cmx.Z + 0.08, 0, 0.3 + (h - 0.4) / 2) * ANG(0, 0, PI / 2), lk(rgb(255, 170, 205)))
			end
			K:box("PhotoCounterKick", V3(w, 0.3, 0.05), at(R, c.X, cmx.Z + 0.04, 0, 0.15), lk(rgb(240, 240, 240)))
			for _, sx in { -1, 1 } do
				K:box("PhotoCounterSide", V3(0.04, h - 0.1, d), at(R, if sx < 0 then cmn.X - 0.03 else cmx.X + 0.03, c.Z, 0, h / 2), lk(rgb(255, 200, 222)))
			end
			local led = K:box("PhotoCounterLED", V3(w, 0.05, 0.04), at(R, c.X, cmx.Z + 0.14, 0, h - 0.06), nl(rgb(255, 200, 220)))
			K:light(led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 5, Brightness = 0.5, Angle = 120, Color = rgb(255, 210, 230) })
			-- 카운터 위: 카드 단말 · 액자 진열 · 투명 케이스 · 안내 스탠드 (손님 쪽 가장자리, 가운데 비움)
			local top = h + 0.14
			Props.cardTerminal(K, at(R, cmx.X - 0.5, cmx.Z - 0.45, 0, top))
			for j = 0, 2 do
				local fx = cmn.X + 0.45 + j * 0.55
				local fc = at(R, fx, cmn.Z + 0.45, 0, top)
				K:box("PhotoFrameSample", V3(0.45, 0.6, 0.06), fc * CF(0, 0.32, 0) * ANG(math.rad(-12), 0, 0), lk(({ rgb(255, 255, 255), rgb(255, 190, 210), rgb(40, 40, 46) })[j + 1]))
				K:box("PhotoFrameInner", V3(0.33, 0.46, 0.065), fc * CF(0, 0.33, 0.005) * ANG(math.rad(-12), 0, 0), lk(hsv(0.55 + j * 0.15, 0.3, 0.95)))
			end
			Props.menuStand(K, at(R, c.X + 0.2, cmx.Z - 0.4, 0, top), "포토 프레임 판매\n아크릴 5,000원\n원목 8,000원\n\n소품 대여 무료")
			K:box("PhotoCaseStack", V3(0.6, 0.3, 0.45), at(R, cmn.X + 0.6, cmx.Z - 0.4, 0, top + 0.15), gl(rgb(240, 244, 248), 0.5))
		end)
	end
	-- 촬영 부스 (뒤 왼쪽)
	local doorKeepZ = R.z1 - 4.8
	local bx1 = (if counter then cmn.X else 0.5) - 2.0
	local booth: any = nil
	if bx1 - R.x0 > 4.4 then
		local ok, res = pcall(photoBooth, K, R, R.x0 + 0.02, bx1, R.z0 + 0.04, math.min(doorKeepZ, R.z0 + 5.0))
		if ok then
			booth = res
		else
			K:note("booth error: " .. tostring(res))
		end
		local c = R.A * CF((R.x0 + bx1) / 2, 3.7, (R.z0 + doorKeepZ) / 2)
		local mn, mx = Kit.laabb(c, V3(bx1 - R.x0, 7.4, 5.0))
		K:reserve(mn, mx, "booth")
	end
	-- 오른벽: 파우더룸 (조명 거울 + 선반 + 드라이기 · 고데기 · 빗)
	local vz0, vz1 = (if counter then cmx.Z else -1.5) + 0.3, math.min(R.z1 - 2.2, (if counter then cmx.Z else -1.5) + 4.5)
	local vanity: any = {}
	K:free(function()
		local zc = (vz0 + vz1) / 2
		local w = vz1 - vz0
		local d = wallR(R, zc, 0, 0.02)
		K:plate("VanityMirror", w - 0.6, 3.2, 0.05, d * CF(0, 5.3, 0), Look.mirror)
		K:plate("VanityMirrorFrame", w - 0.2, 3.6, 0.04, d * CF(0, 5.3, -0.005), lk(rgb(255, 250, 252)))
		vanity.bulbs = {}
		for j = 0, 5 do
			local yy = 3.8 + j * 0.6
			for _, sx in { -1, 1 } do
				table.insert(vanity.bulbs, K:ball("VanityBulb", 0.26, d * CF(sx * (w / 2 - 0.2), yy, 0.12), Look.lampWarm))
			end
		end
		for j = 0, 3 do
			table.insert(vanity.bulbs, K:ball("VanityBulb", 0.26, d * CF(-w / 2 + 0.7 + j * (w - 1.4) / 3, 7.0, 0.12), Look.lampWarm))
		end
		K:plate("VanityShelf", w, 0.12, 0.9, d * CF(0, 3.3, 0), lk(rgb(255, 255, 255)))
		K:plate("VanityShelfEdge", w, 0.14, 0.9, d * CF(0, 3.29, -0.002), lk(rgb(255, 180, 205)))
		local sh = d * CF(0, 3.36, 0.45)
		-- 드라이기
		K:box("HairDryerBody", V3(0.25, 0.25, 0.7), sh * CF(-w / 2 + 0.6, 0.15, 0) * ANG(0, 0.3, 0), lk(rgb(250, 250, 250)))
		K:box("HairDryerGrip", V3(0.18, 0.5, 0.18), sh * CF(-w / 2 + 0.6, 0.0, 0.1) * ANG(0, 0.3, 0.6), lk(rgb(250, 250, 250)))
		-- 고데기 · 빗 · 스프레이 · 헤어롤
		K:box("HairIron", V3(0.1, 0.08, 0.8), sh * CF(-0.2, 0.05, 0) * ANG(0, -0.4, 0), lk(rgb(40, 40, 44)))
		K:box("HairComb", V3(0.08, 0.03, 0.6), sh * CF(0.3, 0.02, -0.1) * ANG(0, 0.7, 0), lk(rgb(240, 120, 160)))
		K:vcyl("HairSpray", 0.55, 0.18, sh * CF(0.75, 0.28, -0.05), lk(rgb(240, 200, 220)))
		K:vcyl("HairSprayCap", 0.12, 0.17, sh * CF(0.75, 0.62, -0.05), lk(rgb(250, 250, 250)))
		for j = 0, 2 do
			K:cyl("HairRoller", 0.4, 0.22, sh * CF(w / 2 - 0.5, 0.12, -0.2 + j * 0.25), lk(({ rgb(255, 140, 180), rgb(140, 200, 255), rgb(255, 220, 120) })[j + 1]))
		end
		txt(K, "VanityLabel", 2.0, 0.3, d * CF(0, 7.45, 0.06), "POWDER ROOM", rgb(255, 120, 160), nil, F.GothamBlack)
		vanity.switch = K:plate("VanitySwitch", 0.35, 0.5, 0.04, wallR(R, vz1 + 0.35, 4.1, 0.02), Look.white)
		K:plate("VanitySwitchRocker", 0.15, 0.3, 0.03, wallR(R, vz1 + 0.35, 4.1, 0.06), Look.offWhite)
	end)
	-- 파우더룸 스툴 + 소품 카트 (창가 낮게)
	local sz = (vz0 + vz1) / 2
	if place(R, at(R, R.x1 - 1.7, sz, 0), V3(1.3, 2.3, 1.3), 0, "stool") then
		stool(K, at(R, R.x1 - 1.7, sz, 0), 2.2, rgb(255, 170, 200))
	end
	local cartZ = math.min(R.z1 - 1.1, vz1 + 1.3)
	local cartOK = place(R, at(R, R.x1 - 0.85, cartZ, -PI / 2), V3(1.9, 3.2, 1.3), 0, "cart")
	if cartOK then
		K:free(function()
			local p = at(R, R.x1 - 0.85, cartZ, -PI / 2)
			for j, y in { 0.7, 1.8, 2.9 } do
				K:box("PropCartShelf", V3(1.8, 0.08, 1.2), p * CF(0, y, 0), lk(rgb(255, 255, 255)))
				K:box("PropBasket", V3(1.6, 0.4, 1.0), p * CF(0, y + 0.24, 0), lk(({ rgb(255, 200, 220), rgb(200, 230, 255), rgb(255, 240, 180) })[j], M.Fabric))
			end
			for _, sx in { -0.85, 0.85 } do
				for _, sz2 in { -0.55, 0.55 } do
					K:box("PropCartPost", V3(0.06, 3.0, 0.06), p * CF(sx, 1.55, sz2), Look.chrome)
				end
			end
			-- 바구니 속 소품: 토끼 머리띠 · 하트 안경 · 왕관 · 미니 모자
			local b3 = p * CF(0, 3.3, 0)
			for _, sx in { -0.5, -0.2 } do
				K:ell("PropBunnyEar", V3(0.16, 0.6, 0.08), b3 * CF(sx, 0.3, -0.2) * ANG(0, 0, sx * 0.3), lk(rgb(255, 255, 255)))
			end
			K:box("PropHeadband", V3(0.5, 0.06, 0.06), b3 * CF(-0.35, 0.02, -0.2), lk(rgb(255, 160, 200)))
			for _, sx in { 0.25, 0.55 } do
				K:ell("PropHeartGlass", V3(0.24, 0.2, 0.05), b3 * CF(sx, 0.12, 0.2) * ANG(0, 0, PI / 4), lk(rgb(255, 60, 120)))
			end
			K:box("PropCrown", V3(0.4, 0.22, 0.4), p * CF(0.4, 2.3, -0.1), Look.goldMetal)
			for j = 0, 2 do
				K:wedge("PropCrownTip", V3(0.06, 0.18, 0.12), p * CF(0.25 + j * 0.15, 2.5, 0.1), Look.goldMetal)
			end
			K:vcyl("PropHat", 0.3, 0.45, p * CF(-0.4, 2.28, 0.1), lk(rgb(40, 40, 46)))
			K:disc("PropHatBrim", 0.7, 0.04, p * CF(-0.4, 2.14, 0.1), lk(rgb(40, 40, 46)))
			txt(K, "PropCartSign", 1.6, 0.4, p * CF(0, 3.9, 0.62), "소품 무료 대여\n사용 후 제자리에 ♥", rgb(255, 80, 140), rgb(255, 255, 255), F.GothamBold)
		end)
	end
	-- 뒷벽 위 (카운터 뒤): 샘플 사진 벽 · 로고 네온 · 가격판 (얇은 판, 알바생 머리 위)
	K:free(function()
		local x0w = bx1 + 0.3
		local x1w = R.x1 - 0.3
		local wc = (x0w + x1w) / 2
		local ww = x1w - x0w
		local d = wallB(R, wc, 0, 0.03)
		-- 샘플 폴라로이드 · 4컷 콜라주 (6.6..9.2)
		local i = 0
		for row = 0, 1 do
			for col = 0, math.floor(ww / 0.95) - 1 do
				i += 1
				local x = -ww / 2 + 0.5 + col * 0.95 + (row % 2) * 0.25
				local y = 7.0 + row * 1.25 + (rnd(i, 2) - 0.5) * 0.2
				local rot = (rnd(i, 5) - 0.5) * 0.25
				local fc = d * CF(x, y, 0) * ANG(0, 0, rot)
				K:plate("SamplePhoto", 0.75, 0.95, 0.02, fc, lk(WHITE))
				K:plate("SamplePhotoImg", 0.62, 0.62, 0.025, fc * CF(0, 0.1, 0.001), lk(hsv(0.85 + rnd(i, 7) * 0.4, 0.35, 0.95)))
				if i % 3 == 0 then
					K:plate("SamplePhotoTape", 0.3, 0.1, 0.03, fc * CF(0, 0.47, 0.002), lk(rgb(255, 230, 140)))
				end
			end
		end
		txt(K, "PhotoLogoNeon", math.min(4.6, ww - 0.4), 0.9, d * CF(0, 5.7, 0.02), "찰칵 ♥ SELF PHOTO", rgb(255, 80, 150), nil, F.FredokaOne, 2.0)
		K:plate("PhotoLogoBacker", math.min(4.9, ww - 0.1), 1.1, 0.02, d * CF(0, 5.7, 0), lk(rgb(255, 236, 244)))
	end)
	-- 왼벽 앞쪽 (문 옆): 이용 방법 · QR · CCTV
	K:free(function()
		local zU = R.z0 + 5.4
		notice(K, wallL(R, zU + 1.3, 5.0, 0.02), 2.4, 3.2, "이용 방법", "① 프레임 선택 · 결제\n② 부스 입장 · 3·2·1 촬영\n③ 사진 고르고 인화\n④ QR 로 원본 다운로드", rgb(255, 90, 150))
		txt(K, "PhotoCCTV", 1.6, 0.4, wallL(R, zU + 1.3, 2.9, 0.02), "● CCTV 촬영중", WHITE, rgb(200, 30, 30), F.GothamBold)
		local q = wallL(R, zU + 1.3, 7.6, 0.02)
		K:plate("PhotoQRBoard", 1.2, 1.2, 0.03, q, lk(WHITE))
		for a = 0, 4 do
			for b = 0, 4 do
				if (a * 7 + b * 3) % 3 ~= 1 then
					K:plate("PhotoQRDot", 0.17, 0.17, 0.035, q * CF(-0.36 + a * 0.18, -0.36 + b * 0.18, 0.001), lk(BLACK))
				end
			end
		end
	end)
	-- 휴지통 (부스와 카운터 사이 뒤쪽)
	local tx = (bx1 + (if counter then cmn.X else 0.5)) / 2
	if place(R, at(R, tx, R.z0 + 0.6, 0), V3(0.9, 1.8, 0.9), 0, "bin") then
		K:free(function()
			K:vcyl("PhotoBin", 1.6, 0.8, at(R, tx, R.z0 + 0.6, 0, 0.8), lk(rgb(250, 250, 250)))
			K:disc("PhotoBinLid", 0.84, 0.08, at(R, tx, R.z0 + 0.6, 0, 1.64), lk(rgb(255, 170, 200)))
		end)
	end
	-- 상호작용: 커튼 · 키오스크 프레임 · 파우더룸 조명
	if booth then
		local open = false
		local anchor = booth.folds[4] and booth.folds[4].p
		prompt(R, anchor, "prompt", {
			action = "커튼 열기",
			object = "촬영 부스",
			sound = "rbxasset://sounds/clickfast.wav",
			fn = function(_n: number, p: ProximityPrompt)
				open = not open
				for _, f in booth.folds do
					tween(f.p, { CFrame = if open then f.open else f.closed }, 0.5)
				end
				p.ActionText = if open then "커튼 닫기" else "커튼 열기"
				if booth.monLabel then
					booth.monLabel.Text = if open then "어서 오세요!\n화면을 터치하세요" else "화면을 터치하세요\n♥ 3 · 2 · 1 ♥"
				end
			end,
		})
		if booth.kiosk then
			local frames = { { "화이트", rgb(255, 255, 255) }, { "블랙", rgb(60, 60, 66) }, { "핑크", rgb(255, 170, 200) }, { "광안리 오션", rgb(120, 200, 255) }, { "레트로 필름", rgb(250, 210, 140) } }
			prompt(R, booth.kiosk, "cycle", {
				action = "프레임 바꾸기",
				object = "포토 키오스크",
				on = function(_i: number, f: any)
					booth.kiosk.Color = f[2]
					if booth.kioskLabel then
						booth.kioskLabel.Text = "프레임을\n선택하세요\n\n" .. f[1] .. " ▶"
					end
				end,
			}, frames)
		end
		Interact.anim(K, function(t: number)
			if booth.ring then
				local b = 0.85 + 0.15 * math.sin(t * 2)
				for _, p in booth.ring do
					if p.Parent then
						p.Color = rgb(255, 240, 220):Lerp(rgb(255, 255, 255), b - 0.7)
					end
				end
			end
		end)
	end
	if vanity.switch then
		local cols = {}
		for _, b in vanity.bulbs do
			table.insert(cols, b.Color)
		end
		prompt(R, vanity.switch, "toggle", {
			object = "파우더룸 거울 조명",
			state = true,
			on = function(s: boolean)
				for i, b in vanity.bulbs do
					if b.Parent then
						b.Material = if s then M.Neon else M.SmoothPlastic
						b.Color = if s then cols[i] else rgb(200, 196, 190)
					end
				end
			end,
		})
		local bulb = vanity.bulbs[1]
		if bulb then
			K:light(bulb, "PointLight", { Range = 7, Brightness = 0.6, Color = Look.warmLight })
		end
	end
end

-- =========================================================================================================
-- 계단 로비 (stairlobby)
-- =========================================================================================================
local function buildLobby(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	local steps = {}
	for _, r in V.byName.Step or {} do
		local mn, mx = abox(R, r)
		table.insert(steps, { rec = r, mn = mn, mx = mx })
	end
	table.sort(steps, function(a, b)
		return a.mx.Y < b.mx.Y
	end)
	-- 계단 앞 (아래) 비우기: 첫 단 앞 2.5
	if #steps > 0 then
		local s1 = steps[1]
		keepBox(R, s1.mn.X, s1.mx.Z, s1.mx.X, s1.mx.Z + 2.5, 6.0, "aisle")
		for _, s in steps do
			host(R, (s.mn.X + s.mx.X) / 2, (s.mn.Z + s.mx.Z) / 2)
		end
	end
	local topZ = if #steps > 0 then steps[#steps].mn.Z else R.z0
	local ceilLow = 11.2
	local ceilHigh = 13.08
	K:free(function()
		-- 계단 위 천장 (Slab 아래) + 단 아래 끝 몰딩
		local lc = V:first("LobbyCeiling")
		local cz0 = if lc then (abox(R, lc)).Z else 2.0
		K:box("StairCeiling", V3(R.W, 0.06, cz0 - R.z0), at(R, R.cx, (R.z0 + cz0) / 2, 0, ceilHigh - 0.03), lk(rgb(236, 234, 228), M.Plaster))
		K:box("StairSoffit", V3(R.W, ceilHigh - ceilLow, 0.08), at(R, R.cx, cz0 - 0.04, 0, (ceilLow + ceilHigh) / 2), lk(rgb(236, 234, 228), M.Plaster))
		K:box("StairSoffitTrim", V3(R.W, 0.1, 0.14), at(R, R.cx, cz0 - 0.07, 0, ceilLow + 0.02), Look.alu)
		-- 벽 스킨: 왼벽 (홀 쪽 보라 벽) 을 밝은 석재 패널로 (위 · 아래 띠)
		K:box("LobbyLeftSkin", V3(0.04, ceilHigh, R.D), at(R, R.x0 + 0.02, R.cz, 0, ceilHigh / 2), lk(rgb(222, 216, 206), M.Plaster))
		local z = R.z0 + 2.4
		while z < R.z1 - 0.5 do
			K:box("LobbyPanelJoint", V3(0.05, ceilHigh - 0.2, 0.04), at(R, R.x0 + 0.04, z, 0, ceilHigh / 2), lk(rgb(196, 190, 180)))
			z += 2.4
		end
		-- 걸레받이 (양 벽, 계단 높이 따라 계단식으로)
		for _, side in { -1, 1 } do
			local x = if side < 0 then R.x0 + 0.05 else R.x1 - 0.05
			K:box("LobbyBase", V3(0.06, 0.4, R.z1 - (steps[1] and steps[1].mx.Z or R.z1)), at(R, x, ((steps[1] and steps[1].mx.Z or R.z1) + R.z1) / 2, 0, 0.2), lk(rgb(60, 58, 56)))
			for _, s in steps do
				K:box("LobbyBase", V3(0.06, 0.4, s.mx.Z - s.mn.Z), at(R, x, (s.mn.Z + s.mx.Z) / 2, 0, s.mx.Y + 0.2), lk(rgb(60, 58, 56)))
			end
		end
		-- 논슬립 (단 앞 끝)
		for _, s in steps do
			local w = s.mx.X - s.mn.X - 0.2
			K:box("StairNosing", V3(w, 0.04, 0.32), at(R, (s.mn.X + s.mx.X) / 2, s.mx.Z - 0.18, 0, s.mx.Y + 0.02), lk(rgb(70, 72, 76), M.Metal))
			K:box("StairNosingGrip", V3(w - 0.1, 0.045, 0.1), at(R, (s.mn.X + s.mx.X) / 2, s.mx.Z - 0.12, 0, s.mx.Y + 0.024), lk(rgb(230, 180, 30), M.Rubber))
		end
	end)
	-- 핸드레일 (양 벽, 기울기 따라): 브래킷 3 + 둥근 레일 + 끝 꺾임
	if #steps >= 2 then
		local a, b = steps[1], steps[#steps]
		local y0 = a.mx.Y + 3.0
		local y1 = b.mx.Y + 3.0
		local z0, z1 = a.mx.Z - 0.2, b.mn.Z + 0.6
		K:free(function()
			for _, side in { -1, 1 } do
				local x = if side < 0 then R.x0 + 0.3 else R.x1 - 0.3
				local pa, pb = ap(R, x, y0, z0), ap(R, x, y1, z1)
				K:seg("Handrail", pa, pb, 0.16, Look.steel)
				K:seg("HandrailEnd", pa, ap(R, x, y0, z0 + 0.9), 0.16, Look.steel)
				K:seg("HandrailEnd", ap(R, x, y0, z0 + 0.9), ap(R, x, y0 - 0.4, z0 + 1.1), 0.16, Look.steel)
				for i = 0, 3 do
					local p = pa:Lerp(pb, (i + 0.5) / 4)
					local wallX = if side < 0 then R.x0 else R.x1
					local q = R.A:PointToObjectSpace(p)
					K:seg("HandrailBracket", p - R.A:VectorToWorldSpace(V3(0, 0.08, 0)), ap(R, wallX, q.Y - 0.3, q.Z), 0.06, Look.steel)
					K:disc("HandrailRose", 0.3, 0.04, R.A * CFrame.fromMatrix(V3(wallX - side * 0.02, q.Y - 0.3, q.Z), V3(0, 1, 0), V3(0, 0, 1), V3(1, 0, 0)), Look.steel)
				end
			end
		end)
	end
	-- 계단 센서등 (오른벽, 단마다 작은 호박색 등)
	local stepLights = {}
	K:free(function()
		for i, s in steps do
			if i % 2 == 1 then
				local d = wallR(R, (s.mn.Z + s.mx.Z) / 2, s.mx.Y + 0.8, 0.02)
				K:plate("StepLightBox", 0.6, 0.3, 0.06, d, Look.alu)
				table.insert(stepLights, K:plate("StepLight", 0.45, 0.12, 0.03, d * CF(0, -0.05, 0.06), Look.lampWarm))
			end
		end
	end)
	if stepLights[2] then
		K:light(stepLights[2], "SurfaceLight", { Face = Enum.NormalId.Back, Range = 6, Brightness = 0.6, Angle = 120, Color = Look.warmLight })
	end
	-- 계단 꼭대기: 방화문 (2F/3F 계단실, 준비중)
	local doorSign: TextLabel? = nil
	if #steps > 0 then
		local top = steps[#steps]
		local fy = top.mx.Y
		K:free(function()
			local d = wallB(R, R.cx, fy, 0.02)
			K:plate("FireDoorFrame", 3.4, 4.9, 0.12, d * CF(0, 2.45, 0), lk(rgb(90, 92, 96), M.Metal))
			K:plate("FireDoor", 3.0, 4.7, 0.16, d * CF(0, 2.35, 0), lk(rgb(150, 152, 156), M.Metal))
			K:plate("FireDoorVision", 0.4, 1.2, 0.18, d * CF(0.8, 3.4, 0), gl(rgb(200, 220, 230), 0.5))
			K:plate("FireDoorBar", 2.4, 0.18, 0.3, d * CF(0, 2.1, 0), Look.chrome)
			K:plate("FireDoorCloser", 0.8, 0.22, 0.25, d * CF(0.9, 4.55, 0), lk(rgb(60, 60, 64)))
			txt(K, "FireDoorLabel", 1.6, 0.36, d * CF(0, 4.05, 0.17), "방화문 · 항상 닫아 두세요", rgb(255, 255, 255), rgb(200, 30, 30), F.GothamBold)
			local _, lab = txt(K, "FloorSign", 2.6, 1.0, d * CF(0, 2.9, 0.17), "▲ 2F 보드게임카페 주사위\n▲ 3F 방탈출 미스터리룸", rgb(30, 30, 30), rgb(255, 230, 80), F.GothamBlack)
			doorSign = lab
			-- 비상구 유도등
			local ex = d * CF(0, 5.25, 0.03)
			K:plate("ExitSignBox", 1.6, 0.6, 0.15, ex, lk(rgb(240, 240, 240)))
			K:plate("ExitSignFace", 1.5, 0.5, 0.02, ex * CF(0, 0, 0.15), nl(rgb(0, 190, 90)))
			txt(K, "ExitSignText", 1.4, 0.4, ex * CF(0, 0, 0.18), "🏃 비상구 EXIT", WHITE, nil, F.GothamBlack, 1.3)
		end)
	end
	if doorSign then
		local frames = { "▲ 2F 보드게임카페 주사위\n▲ 3F 방탈출 미스터리룸", "보드게임카페 주사위\nOPEN 13:00 ~ 02:00", "방탈출 미스터리룸\n예약제 · 현장 대기 가능", "공사 중이 아닙니다!\n곧 문을 엽니다 🙏" }
		local lab = doorSign
		Interact.anim(K, function(t: number)
			local i = math.floor(t / 4) % #frames + 1
			if lab.Parent and lab.Text ~= frames[i] then
				lab.Text = frames[i]
			end
		end)
	end
	-- 벽 포스터 (오른벽: 방탈출 테마 3, 계단 따라 계단식) · 보드게임 포스터 (왼벽)
	local themes = {
		{ "폐병원 303호", "공포 · 난이도 ★★★★\n60분 · 2~4인", rgb(30, 10, 10), rgb(200, 20, 20), rgb(80, 80, 80) },
		{ "광안리 탐정사무소", "추리 · 난이도 ★★★\n70분 · 2~5인", rgb(20, 30, 50), rgb(250, 200, 60), rgb(120, 160, 220) },
		{ "마지막 편지", "감성 · 난이도 ★★\n60분 · 2~3인", rgb(250, 230, 220), rgb(240, 120, 150), rgb(255, 255, 255) },
	}
	for i, th in themes do
		local s = steps[2 + (i - 1) * 2]
		if s then
			local zc = (s.mn.Z + s.mx.Z) / 2
			poster(K, wallR(R, zc, s.mx.Y + 4.6, 0.02), 2.2, 3.0, { bg = th[3], a1 = th[4], a2 = th[5], title = th[1], sub = th[2], fg = if i == 3 then rgb(80, 30, 40) else WHITE, fg2 = if i == 3 then rgb(160, 60, 90) else rgb(255, 236, 120), tag = "3F 방탈출" })
		end
	end
	local s3 = steps[3]
	if s3 then
		poster(K, wallL(R, (s3.mn.Z + s3.mx.Z) / 2 - 1.0, s3.mx.Y + 4.4, 0.04), 3.0, 3.2, { bg = rgb(40, 120, 70), a1 = rgb(250, 220, 60), a2 = rgb(255, 255, 255), title = "보드게임\n무제한", sub = "1시간 3,000원\n음료 1잔 필수", disc = rgb(255, 120, 60), tag = "2F 주사위" })
	end
	-- 입구 쪽: 층별 안내 (오른벽) · 소화기함 · 우산꽂이 · CCTV · 계단 조심
	local dirLab: TextLabel? = nil
	local dirBoard: BasePart? = nil
	K:free(function()
		local zc = R.z1 - 3.6
		local d = wallR(R, zc, 5.6, 0.02)
		K:plate("DirBoardFrame", 2.8, 4.0, 0.08, d, Look.darkAlu)
		dirBoard = K:plate("DirBoard", 2.6, 3.8, 0.1, d, lk(rgb(24, 30, 48)))
		txt(K, "DirTitle", 2.3, 0.4, d * CF(0, 1.55, 0.11), "층별 안내 FLOOR GUIDE", rgb(255, 220, 80), nil, F.GothamBlack)
		local rows = { { "3F", "방탈출 카페 미스터리룸", rgb(200, 60, 60) }, { "2F", "보드게임카페 주사위", rgb(60, 160, 90) }, { "1F", "광안 게임랜드 · 셀프사진관 찰칵", rgb(80, 120, 230) } }
		for i, r in rows do
			local y = 0.85 - (i - 1) * 0.95
			K:plate("DirRowTag", 0.6, 0.6, 0.11, d * CF(-0.95, y, 0), lk(r[3]))
			txt(K, "DirRowTagText", 0.5, 0.45, d * CF(-0.95, y, 0.12), r[1], WHITE, nil, F.GothamBlack)
			txt(K, "DirRowText", 1.75, 0.5, d * CF(0.3, y, 0.12), r[2], WHITE, nil, F.GothamBold)
		end
		local _, l2 = txt(K, "DirFoot", 2.3, 0.3, d * CF(0, -1.65, 0.12), "엘리베이터 없음 · 계단을 이용하세요", rgb(200, 200, 210), nil, F.GothamMedium)
		dirLab = l2
		-- 소화기함 (왼벽 아래)
		local f = wallL(R, R.z1 - 2.4, 1.3, 0.02)
		K:plate("ExtCabinet", 1.0, 2.2, 0.4, f, lk(rgb(200, 26, 30)))
		K:plate("ExtCabinetWindow", 0.7, 1.2, 0.41, f * CF(0, 0.2, 0), gl(rgb(220, 230, 236), 0.5))
		K:vcyl("ExtInside", 1.0, 0.45, f * CF(0, 0.1, 0.2), lk(rgb(220, 30, 30)))
		txt(K, "ExtCabinetText", 0.8, 0.3, f * CF(0, -0.75, 0.42), "소화기", WHITE, nil, F.GothamBlack)
		txt(K, "StairCaution", 2.2, 0.5, wallL(R, R.z1 - 5.6, 4.4, 0.02), "⚠ 계단 조심 · 뛰지 마세요", rgb(30, 30, 30), rgb(255, 210, 40), F.GothamBlack)
		K:disc("LobbyCCTVBase", 0.6, 0.06, at(R, R.x1 - 0.7, R.z1 - 1.2, 0, ceilLow - 0.03), Look.white)
		K:ell("LobbyCCTV", V3(0.5, 0.5, 0.5), at(R, R.x1 - 0.7, R.z1 - 1.2, 0, ceilLow - 0.06), gl(rgb(40, 46, 52), 0.15))
		-- 현관 매트
		K:box("LobbyMat", V3(5.6, 0.04, 2.4), at(R, R.cx, R.z1 - 1.5, 0, 0.02), lk(rgb(40, 40, 44), M.Fabric))
		K:box("LobbyMatEdge", V3(5.8, 0.035, 2.5), at(R, R.cx, R.z1 - 1.5, 0, 0.0175), Look.rubber)
	end)
	-- 우산꽂이 (입구 오른쪽 구석)
	local ux, uz = R.x1 - 0.8, R.z1 - 0.9
	if place(R, at(R, ux, uz, 0), V3(1.0, 2.4, 1.0), 0, "umbrella") then
		K:free(function()
			K:vcyl("UmbrellaStand", 1.6, 0.9, at(R, ux, uz, 0, 0.8), Look.steel)
			K:disc("UmbrellaStandRim", 0.96, 0.06, at(R, ux, uz, 0, 1.6), Look.chrome)
			for j, c in { rgb(30, 60, 140), rgb(200, 40, 50), rgb(30, 30, 30) } do
				K:seg("Umbrella", ap(R, ux - 0.2 + j * 0.15, 0.3, uz), ap(R, ux - 0.3 + j * 0.2, 2.3, uz + 0.1), 0.14, lk(c, M.Fabric))
			end
		end)
	end
	-- 천장 설비
	for _, p in { { R.cx, R.z1 - 3.0, ceilLow }, { R.cx + 1.5, R.z0 + 4.0, ceilHigh } } do
		K:free(function()
			K:disc("LobbyDownTrim", 0.8, 0.04, at(R, p[1], p[2], 0, p[3] - 0.02), Look.white)
			local lens = K:disc("LobbyDownLens", 0.58, 0.03, at(R, p[1], p[2], 0, p[3] - 0.035), Look.lampNeutral)
			K:light(lens, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 14, Brightness = 0.9, Angle = 80, Color = Look.neutralLight })
		end)
	end
	K:free(function()
		K:disc("SmokeDetector", 0.55, 0.14, at(R, R.cx - 1.2, R.z0 + 6.0, 0, ceilHigh - 0.07), Look.white)
		K:disc("SmokeDetector", 0.55, 0.14, at(R, R.cx - 1.2, R.z1 - 5.0, 0, ceilLow - 0.07), Look.white)
	end)
	-- 상호작용: 층별 안내 넘기기 · 계단 센서등 스위치
	if dirBoard and dirLab then
		local lab: TextLabel = dirLab
		prompt(R, dirBoard, "cycle", {
			action = "안내 넘기기",
			object = "층별 안내판",
			on = function(_i: number, f: any)
				lab.Text = f
			end,
		}, { "엘리베이터 없음 · 계단을 이용하세요", "2F 주사위: 1시간 3,000원 · 음료 필수", "3F 미스터리룸: 1인 22,000원 (2인 이상)", "1F 게임랜드: 연중무휴 24시간" })
	end
	K:free(function()
		local sw = Props.switchPlate(K, wallL(R, R.z1 - 1.2, 4.2, 0.02), 1)
		prompt(R, sw, "toggle", {
			object = "계단 센서등",
			state = true,
			on = function(s: boolean)
				for _, p in stepLights do
					if p.Parent then
						p.Material = if s then M.Neon else M.SmoothPlastic
						p.Color = if s then Look.lampWarm.c else rgb(150, 140, 120)
					end
				end
				for _, l in K.lights do
					if l.Parent == stepLights[2] then
						l.Enabled = s
					end
				end
			end,
		})
	end)
end

-- =========================================================================================================
-- 락볼링 오락코너 (bowarcade)
-- =========================================================================================================
local function buildBowArcade(K: any, V: any, S: any)
	local R = makeRoom(K, V)
	-- 서버 자리: 펀치 스팟 · 농구 서 있는 자리
	local ps = V:first("Spot_bowl_punch")
	if ps then
		local c = acen(R, ps)
		host(R, c.X, c.Z)
	end
	local fc = V:first("FrontCabinet")
	if fc then
		local c = acen(R, fc)
		host(R, c.X, c.Z + 3.4)
		keepBox(R, c.X - 3.2, c.Z + 1.2, c.X + 3.2, c.Z + 4.6, 7.5, "basket")
	end
	-- 로비 쪽 (오른쪽) · 라운지 쪽 (뒤) 출입 통로
	keepBox(R, R.x1 - 3.0, -1.2, R.x1 + 0.2, 4.6, 8, "lane")
	-- 인생사진 부스: 속 빈 부스로 다시 짓기 (BoothBody · Curtain 숨김, Sign_ 은 그대로)
	local bb = V:first("BoothBody")
	local booth: any = nil
	if bb then
		local bmn, bmx = abox(R, bb)
		Scan.hide(K.hidden, bb.part)
		local cu = V:first("Curtain")
		if cu then
			Scan.hide(K.hidden, cu.part)
		end
		booth = {}
		K:free(function()
			local H = bmx.Y
			local x0, x1, z0, z1 = bmn.X, bmx.X, bmn.Z, bmx.Z
			local white = lk(rgb(248, 248, 246))
			K:box("GZBoothBack", V3(0.16, H, z1 - z0), at(R, x0 + 0.08, (z0 + z1) / 2, 0, H / 2), white)
			K:box("GZBoothSide", V3(x1 - x0, H, 0.16), at(R, (x0 + x1) / 2, z0 + 0.08, 0, H / 2), white)
			K:box("GZBoothSide", V3(x1 - x0, H, 0.16), at(R, (x0 + x1) / 2, z1 - 0.08, 0, H / 2), white)
			K:box("GZBoothRoof", V3(x1 - x0, 0.2, z1 - z0), at(R, (x0 + x1) / 2, (z0 + z1) / 2, 0, H - 0.1), white)
			-- 앞면 (+x): 커튼 구멍 둘레
			local oa, ob = z0 + 1.2, z1 - 1.2
			K:box("GZBoothFront", V3(0.16, H, oa - z0), at(R, x1 - 0.08, (z0 + oa) / 2, 0, H / 2), white)
			K:box("GZBoothFront", V3(0.16, H, z1 - ob), at(R, x1 - 0.08, (ob + z1) / 2, 0, H / 2), white)
			K:box("GZBoothHeader", V3(0.16, H - 6.6, ob - oa), at(R, x1 - 0.08, (oa + ob) / 2, 0, 6.6 + (H - 6.6) / 2), white)
			K:box("GZBoothBand", V3(0.04, 0.4, z1 - z0), at(R, x1 + 0.02, (z0 + z1) / 2, 0, 0.6), lk(rgb(255, 120, 170)))
			K:box("GZBoothBand", V3(x1 - x0, 0.4, 0.04), at(R, (x0 + x1) / 2, z0 - 0.02, 0, 0.6), lk(rgb(255, 120, 170)))
			-- 옆면 (방 안쪽 z0 면): 가격 · 샘플
			local sd = R.A * CFrame.fromMatrix(V3((x0 + x1) / 2, 0, z0 - 0.03), V3(-1, 0, 0), Vector3.yAxis, V3(0, 0, -1))
			txt(K, "GZBoothPrice", 3.4, 0.9, sd * CF(0, 6.6, 0), "인생사진 4컷 4,000원", rgb(255, 80, 140), rgb(255, 245, 250), F.GothamBlack)
			for j = 0, 2 do
				local sx = -1.2 + j * 1.2
				K:plate("GZSampleStrip", 0.85, 2.6, 0.03, sd * CF(sx, 4.4, 0), lk(WHITE))
				for k = 0, 3 do
					K:plate("GZSampleShot", 0.7, 0.55, 0.035, sd * CF(sx, 5.4 - k * 0.63, 0.002), lk(hsv(0.6 + j * 0.12 + k * 0.04, 0.3, 0.95)))
				end
			end
			-- 안쪽: 카메라 판 (뒤 -x 안벽) · 배경 롤 (커튼 안쪽) · 의자
			local cd = R.A * CFrame.fromMatrix(V3(x0 + 0.17, 0, (z0 + z1) / 2), V3(0, 0, -1), Vector3.yAxis, V3(1, 0, 0))
			K:plate("GZBoothCamPanel", 2.4, 3.4, 0.2, cd * CF(0, 4.2, 0), lk(rgb(30, 30, 34)))
			local mon = K:plate("GZBoothMonitor", 1.9, 1.1, 0.03, cd * CF(0, 3.8, 0.21), { c = rgb(255, 200, 220), m = M.Neon, t = 0.05 })
			local _, ml = txt(K, "GZBoothMonitorText", 1.8, 0.9, cd * CF(0, 3.8, 0.25), "프레임 선택\n♥ 화이트 ♥", rgb(120, 30, 70), nil, F.FredokaOne, 1.2)
			booth.monitor, booth.monLabel = mon, ml
			local ring = K:ring("GZBoothRing", cd * CF(0, 5.0, 0.32), 0.9, 0.13, 12, Look.lampNeutral)
			booth.ring = ring
			wdisc(K, "GZBoothLens", 0.32, 0.12, cd * CF(0, 5.0, 0.2), lk(rgb(16, 16, 18), M.Glass))
			K:box("GZBoothStool", V3(2.6, 1.7, 1.2), at(R, x1 - 1.0, (z0 + z1) / 2, 0, 0.85), lk(rgb(255, 255, 255), M.Leather))
			K:box("GZBoothBackdrop", V3(0.04, H - 1.4, z1 - z0 - 0.5), at(R, x1 - 0.35, (z0 + z1) / 2, 0, (H - 1.4) / 2 + 0.6), lk(rgb(200, 230, 255), M.Fabric))
			K:box("GZBoothFloor", V3(x1 - x0 - 0.3, 0.04, z1 - z0 - 0.3), at(R, (x0 + x1) / 2, (z0 + z1) / 2, 0, 0.03), lk(rgb(240, 236, 240)))
			K:box("GZBoothRail", V3(0.1, 0.1, ob - oa + 0.2), at(R, x1 + 0.08, (oa + ob) / 2, 0, 6.5), Look.chrome)
			-- 결제 화면 (앞면 왼쪽 판)
			local kd = R.A * CFrame.fromMatrix(V3(x1 + 0.02, 0, (z0 + oa) / 2), V3(0, 0, 1), Vector3.yAxis, V3(1, 0, 0))
			local ks = K:plate("GZBoothKiosk", 0.9, 1.2, 0.05, kd * CF(0, 4.2, 0), { c = rgb(255, 190, 210), m = M.Neon, t = 0.05 })
			txt(K, "GZBoothKioskText", 0.8, 1.0, kd * CF(0, 4.2, 0.06), "카드\n결제\n4,000원", rgb(120, 30, 70), nil, F.GothamBold, 1.1)
			K:plate("GZBoothCardSlot", 0.6, 0.08, 0.04, kd * CF(0, 3.4, 0), nl(rgb(60, 220, 120)))
			K:plate("GZBoothPrintSlot", 0.8, 0.12, 0.05, kd * CF(0, 2.6, 0), lk(rgb(16, 16, 18)))
			booth.kiosk = ks
		end)
		-- 커튼 주름 (z 방향으로 펼침)
		local folds = {}
		local oa, ob = bmn.Z + 1.2, bmx.Z - 1.2
		local n = 7
		K:free(function()
			for i = 1, n do
				local z = oa + (ob - oa) * (i - 0.5) / n
				local p = K:box("GZBoothCurtain", V3(0.1, 5.8, (ob - oa) / n + 0.08), at(R, bmx.X + 0.14 + (i % 2) * 0.05, z, (i % 2 == 0) and 0.22 or -0.22, 3.6), lk(rgb(240, 80, 150), M.Fabric))
				table.insert(folds, { p = p, closed = p.CFrame, open = K.cf * at(R, bmx.X + 0.14 + (i % 2) * 0.05, oa + 0.15 + (i - 1) * 0.12, (i % 2 == 0) and 0.9 or -0.9, 3.6) })
			end
		end)
		booth.folds = folds
		local mn, mx = Kit.laabb(R.A * CF((bmn.X + bmx.X) / 2 + 0.3, 4, (bmn.Z + bmx.Z) / 2), V3(bmx.X - bmn.X + 0.6, 8, bmx.Z - bmn.Z))
		K:reserve(mn, mx, "booth")
	end
	-- 인형뽑기 3대 오버레이 (같은 함수, 이름만 다름)
	local clawLeds = {}
	for i, g in machines(V, "^인형뽑기_%d+$") do
		local ok, res = pcall(clawOverlay, K, R, g, i + 2)
		if ok then
			for _, p in res do
				table.insert(clawLeds, p)
			end
		end
	end
	-- 펀치 · 농구는 그대로. 에어하키 몸체 LED 띠
	local hb = V:first("HockeyBody")
	if hb then
		local mn, mx = abox(R, hb)
		local c = (mn + mx) / 2
		K:free(function()
			for _, sx in { -1, 1 } do
				K:box("GZHockeyLED", V3(0.04, 0.08, mx.Z - mn.Z - 0.2), at(R, if sx < 0 then mn.X - 0.02 else mx.X + 0.02, c.Z, 0, 1.8), nl(rgb(60, 230, 255)))
				K:box("GZHockeyStripe", V3(0.03, 0.5, mx.Z - mn.Z - 0.4), at(R, if sx < 0 then mn.X - 0.015 else mx.X + 0.015, c.Z, 0, 0.9), lk(rgb(240, 240, 240)))
			end
			for _, sz in { -1, 1 } do
				local z = if sz < 0 then mn.Z - 0.02 else mx.Z + 0.02
				local d = R.A * CFrame.fromMatrix(V3(c.X, 0, z), V3(-sz, 0, 0), Vector3.yAxis, V3(0, 0, sz))
				K:plate("GZHockeyCoin", 0.9, 0.7, 0.1, d * CF(1.5, 1.3, 0), lk(rgb(30, 30, 34)))
				K:plate("GZHockeySlot", 0.06, 0.22, 0.02, d * CF(1.5, 1.4, 0.1), nl(rgb(255, 70, 40)))
				txt(K, "GZHockeyPrice", 0.8, 0.2, d * CF(1.5, 1.08, 0.11), "1,000원", WHITE, nil, F.GothamBold)
				txt(K, "GZHockeyGoal", 1.4, 0.3, d * CF(0, 1.8, 0.01), "GOAL", rgb(255, 230, 60), nil, F.GothamBlack, 1.3)
			end
		end)
	end
	-- 기존 무늬 없는 카펫 + 벽 · 천장 마감
	-- 매달린 LED 프레임 (높은 천장 아래 존 표시) + 행거
	K:free(function()
		local y = 12.6
		local x0, x1, z0, z1 = R.x0 + 0.8, R.x1 - 0.8, R.z0 + 0.8, R.z1 - 1.0
		local tl = lk(rgb(26, 26, 30), M.Metal)
		for _, z in { z0, z1 } do
			K:box("GZTruss", V3(x1 - x0, 0.5, 0.5), at(R, (x0 + x1) / 2, z, 0, y), tl)
			K:box("GZTrussLED", V3(x1 - x0, 0.1, 0.12), at(R, (x0 + x1) / 2, z, 0, y - 0.3), nl(rgb(255, 60, 170)))
		end
		for _, x in { x0, x1 } do
			K:box("GZTruss", V3(0.5, 0.5, z1 - z0), at(R, x, (z0 + z1) / 2, 0, y), tl)
			K:box("GZTrussLED", V3(0.12, 0.1, z1 - z0), at(R, x, (z0 + z1) / 2, 0, y - 0.3), nl(rgb(60, 230, 255)))
		end
		for _, p in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } } do
			K:seg("GZHanger", ap(R, p[1], y + 0.25, p[2]), ap(R, p[1], R.H, p[2]), 0.08, Look.steel)
		end
		-- 기존 GAME ZONE 사인 매달기 (떠 있던 것)
		local sg = nil
		for _, r in V.parts do
			if r.name == "NeonTube" then
				local c = acen(R, r)
				if c.Y > 15 and c.Z < -11 then
					sg = c
				end
			end
		end
		if sg then
			for _, sx in { -5.2, 6.2 } do
				K:seg("GZSignHanger", ap(R, 0.5 + sx, 16.0, sg.Z), ap(R, 0.5 + sx, R.H, sg.Z), 0.06, Look.steel)
			end
		end
		-- 떠 있던 소화기 표지판: 받침 기둥
		local se = V:first("Sign_소화기")
		if se then
			local c = acen(R, se)
			K:box("ExtSignPost", V3(0.12, 3.7, 0.12), at(R, c.X, c.Z - 0.1, 0, 1.85), lk(rgb(200, 30, 30)))
			K:disc("ExtSignPostBase", 0.7, 0.08, at(R, c.X, c.Z - 0.1, 0, 0.04), lk(rgb(200, 30, 30)))
		end
	end)
	for _, p in { { -4, -6 }, { 5, 6 }, { -4, 6 } } do
		ceilSpeaker(K, R, p[1], p[2])
	end
	-- 네온 벽화 (왼벽 위, 창 위 11.8~21)
	K:free(function()
		local d = wallL(R, 0.5, 15.8, 0.04)
		K:plate("GZMuralBack", 20.0, 6.6, 0.03, d, lk(rgb(20, 14, 40)))
		txt(K, "GZMuralText", 11.0, 2.2, d * CF(2.6, 1.2, 0.05), "LET'S PLAY!", rgb(255, 80, 200), nil, F.Bangers, 2.4)
		txt(K, "GZMuralSub", 11.0, 1.1, d * CF(2.6, -0.9, 0.05), "인형뽑기 · 펀치 · 농구 · 에어하키 · 인생사진", rgb(80, 230, 255), nil, F.GothamBlack, 2.0)
		-- 픽셀 외계인 (네온 칸)
		local px = {
			"..X.....X..",
			"...X...X...",
			"..XXXXXXX..",
			".XX.XXX.XX.",
			"XXXXXXXXXXX",
			"X.XXXXXXX.X",
			"X.X.....X.X",
			"...XX.XX...",
		}
		local cell = 0.42
		for r, row in px do
			for c = 1, #row do
				if string.sub(row, c, c) == "X" then
					K:plate("GZInvaderPixel", cell - 0.04, cell - 0.04, 0.04, d * CF(-7.6 + (c - 6) * cell, 1.6 - (r - 1) * cell, 0.05), nl(rgb(120, 255, 120)))
				end
			end
		end
		-- 번개
		K:plate("GZBolt", 0.3, 2.0, 0.05, d * CF(8.6, 0.8, 0.05) * ANG(0, 0, 0.4), nl(rgb(255, 230, 60)))
		K:plate("GZBolt", 0.3, 2.0, 0.05, d * CF(8.9, -0.6, 0.05) * ANG(0, 0, 0.4), nl(rgb(255, 230, 60)))
		K:plate("GZBolt", 1.0, 0.3, 0.05, d * CF(8.75, 0.1, 0.05), nl(rgb(255, 230, 60)))
	end)
	-- 아래 벽 (창 아래 0~2.8): 안내 스티커
	txt(K, "GZYouthSticker", 3.2, 0.9, wallL(R, -4.6, 1.5, 0.02), "청소년 출입시간\n09:00 ~ 22:00", WHITE, rgb(30, 90, 200), F.GothamBlack)
	txt(K, "GZCCTVSticker", 2.0, 0.5, wallL(R, -9.0, 1.9, 0.02), "● CCTV 녹화중", WHITE, rgb(200, 30, 30), F.GothamBold)
	-- 새 기계: 대전 2대 (로비 쪽 경계, 앞 = -x) · 키디라이드 (창가) · 가챠 1단 (창가 낮게)
	local made: any = { candy = {} }
	for i, k in { { -7.0, "부산 파이터 2026", "ROUND 2\nFIGHT!", rgb(220, 40, 50) }, { -3.94, "보글보글 클래식", "BUBBLE POP\nSTAGE 5", rgb(40, 150, 240) } } do
		local m = footprint(R, R.x1 - 1.7, k[1], -PI / 2, 2.95, 6.0, 1.65, 3.0, 0, function(p)
			return candy(K, p, { title = k[2], screen = k[3], accent = k[4], scr = dk(k[4], 0.55) })
		end)
		if m then
			table.insert(made.candy, m)
		end
	end
	made.kiddie = footprint(R, -3.2, R.z1 - 2.5, PI / 2, 2.5, 3.3, 2.1, 2.5, 0, function(p)
		return kiddieRide(K, p, { body = rgb(250, 190, 30), name = "통통이" })
	end)
	for i = 0, 1 do
		footprint(R, 2.4 + i * 1.8, R.z1 - 1.0, PI, 1.75, 2.4, 0.85, 0.85, 0, function(p)
			local th = ({ { "볼링핀 키링", rgb(240, 80, 80), "3,000원" }, { "미니 볼링공", rgb(60, 120, 230), "3,000원" } })[i + 1]
			K:box("GachaBase", V3(1.75, 0.15, 1.7), p * CF(0, 0.075, 0), lk(rgb(30, 30, 34)))
			K:box("GachaFrame", V3(1.7, 2.2, 1.6), p * CF(0, 0.15 + 1.1, 0), lk(lt(th[2], 0.1)))
			K:box("GachaWindow", V3(1.36, 0.95, 0.05), p * CF(0, 0.15 + 1.62, 0.81), gl(rgb(240, 246, 250), 0.7))
			for j = 0, 3 do
				K:ball("GachaCapsule", 0.38, p * CF(-0.4 + (j % 3) * 0.4, 0.15 + 1.35 + (j // 3) * 0.36, 0.5), lk(CARPET_COLS[(i * 3 + j) % #CARPET_COLS + 1]))
			end
			txt(K, "GachaCard", 1.3, 0.42, p * CF(0, 0.15 + 0.98, 0.81), th[1], WHITE, dk(th[2], 0.25), F.FredokaOne)
			wdisc(K, "GachaKnob", 0.5, 0.08, p * CF(-0.25, 0.15 + 0.48, 0.81), lk(rgb(240, 240, 240)))
			K:plate("GachaOut", 0.36, 0.3, 0.03, p * CF(0.42, 0.15 + 0.25, 0.81), lk(rgb(20, 20, 20)))
			txt(K, "GachaPrice", 0.6, 0.18, p * CF(0.38, 0.15 + 0.84, 0.82), th[3], rgb(20, 20, 20), rgb(255, 230, 80), F.GothamBlack)
			return true
		end)
	end
	-- 분리수거 (왼쪽 뒤 구석)
	footprint(R, R.x0 + 1.6, R.z0 + 1.6, PI / 2, 2.9, 2.6, 0.5, 0.5, 0, function(p)
		bins(K, p)
		return true
	end)
	-- 카펫 무늬
	pcall(carpetPrint, K, R, R.x0 + 0.3, R.x1 - 0.3, R.z0 + 0.3, R.z1 - 0.3, if lowD(K) then 6 else 3.6, 23)
	-- 불빛: 부스 안 · 대전 화면 · 프레임
	if booth and booth.ring and booth.ring[1] then
		K:light(booth.ring[1], "PointLight", { Range = 8, Brightness = 0.8, Color = rgb(255, 240, 230) })
	end
	if made.candy[1] then
		K:light(made.candy[1].screen, "SurfaceLight", { Face = Enum.NormalId.Back, Range = 9, Brightness = 0.9, Angle = 110, Color = rgb(255, 120, 140) })
	end
	-- 상호작용: 부스 커튼 · 부스 프레임 고르기 · 대전 데모
	if booth and booth.folds then
		local open = false
		prompt(R, booth.folds[5] and booth.folds[5].p, "prompt", {
			action = "커튼 열기",
			object = "인생사진 부스",
			sound = "rbxasset://sounds/clickfast.wav",
			fn = function(_n: number, p: ProximityPrompt)
				open = not open
				for _, f in booth.folds do
					tween(f.p, { CFrame = if open then f.open else f.closed }, 0.5)
				end
				p.ActionText = if open then "커튼 닫기" else "커튼 열기"
			end,
		})
		if booth.kiosk then
			local frames = { { "화이트", rgb(255, 255, 255) }, { "핑크", rgb(255, 170, 200) }, { "볼링핀", rgb(255, 120, 120) }, { "네온 블랙", rgb(60, 50, 80) } }
			prompt(R, booth.kiosk, "cycle", {
				action = "프레임 바꾸기",
				object = "인생사진 결제 화면",
				on = function(_i: number, f: any)
					booth.kiosk.Color = f[2]
					if booth.monLabel then
						booth.monLabel.Text = "프레임 선택\n♥ " .. f[1] .. " ♥"
					end
				end,
			}, frames)
		end
	end
	local cand = made.candy[1]
	if cand and cand.screen then
		prompt(R, cand.screen, "cycle", {
			action = "데모 화면 넘기기",
			object = "대전 격투 기계",
			on = function(_i: number, f: any)
				if cand.label then
					cand.label.Text = f[1]
				end
				cand.screen.Color = f[2]
			end,
		}, { { "SELECT\nYOUR FIGHTER", rgb(40, 30, 110) }, { "ROUND 2\nFIGHT!", rgb(130, 20, 20) }, { "K.O.!", rgb(200, 120, 10) }, { "볼링장 최강자\n도전 환영", rgb(20, 90, 60) } })
	end
	if #clawLeds > 0 then
		Interact.anim(K, function(t: number)
			for i, p in clawLeds do
				if p.Parent then
					p.Color = hsv(t * 0.12 + i * 0.09, 0.75, 1)
				end
			end
		end)
	end
	if booth and booth.ring then
		Interact.anim(K, function(t: number)
			local b = 0.5 + 0.5 * math.sin(t * 1.5)
			for _, p in booth.ring do
				if p.Parent then
					p.Color = rgb(255, 236, 214):Lerp(WHITE, b)
				end
			end
		end)
	end
end

-- =========================================================================================================
function T.style(V: any): any
	-- 공통 마감은 거의 다 끄고 (벽이 1도 돌아가 있어서) 유형 빌더가 정렬 프레임으로 직접 지음.
	-- upgrades (소화기 다시 만들기) 만 사용.
	if V.type == "bowarcade" then
		-- 앞면은 통유리 (문 없음): 추측한 '문' keep 을 걷어냄 (rooms.json 에 noDoorGuess 요청)
		local keep = {}
		for _, k in V.keep do
			if k.kind ~= "door" then
				table.insert(keep, k)
			end
		end
		V.keep = keep
		V.door = nil
		V.doors = {}
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
		skip = { floor = true, ceiling = true, walls = true, fixtures = true, upgrades = V.type == "stairlobby" or V.type == "photo" },
	}
end

function T.build(K: any, V: any, S: any)
	if V.type == "arcade" then
		buildHall(K, V, S)
	elseif V.type == "photo" then
		buildPhoto(K, V, S)
	elseif V.type == "stairlobby" then
		buildLobby(K, V, S)
	elseif V.type == "bowarcade" then
		buildBowArcade(K, V, S)
	end
end

return T
