--!strict
-- GwangalliBuildingInterior/T_karaoke: 광안 코인노래연습장 (Venues: karaoke 로비 · kcorridor 복도 · kbooth 노래방 8칸).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (+ 방 상자 보정: 부스의 문 · 가짜 유리 keep 을 실제 문 자리로)
--   build(K, V, S) 유형별 디테일
--
-- 게임플레이 계약 (bld/pcbang_karaoke.json): KaraokePanel · KaraokeZone · KaraokeScreen (화면 앞면 = 클라이언트 TV gui) ·
--   StatusLight · MirrorBall · Booth_NN 모델 · 좌석 Seat 6개 · TableTop · Board_karaoke · CardReader · LEDScreen · Sign_* 는
--   절대 숨기거나 덮지 않음. 소파 좌석은 같은 자세의 쿠션으로 감싸기만 (윗면 +0.02). 장식 쉘(소파 몸체 · 스피커 상자 ·
--   반주기 상자 · 흡음판 · 유리문 · 장식 소품)만 숨기고 같은 자리에 다시 만듦.
-- 부스 (kbooth): U자 가죽 소파(채널 등받이 · 버튼 쿠션 · 크롬 걸레받이 LED) · 실제 콘이 있는 스피커 · 랙 앰프 · 반주기(지금 곡 번호
--   표시) · 마이크 충전 거치대 · 코인기(남은 시간 표시: KPaidUntil) · 터치 선곡 패널 · 벽걸이 에어컨 · 조명 패널 · QRD 디퓨저 ·
--   채널 패딩 벽 · 별빛 천장 · 핀스폿 · 유리문(문 닫기/열기) · 피난안내도 · 유도등.
--   상호작용: 조명 모드 (기본/무드/파티/끄기), 에어컨 켜기/끄기, 문 닫기/열기 (+ 프롬프트 없는 실시간 표시 2종)
-- 로비 (karaoke): 동전교환기 · 음료 자판기 실물 오버레이, 대기 소파, 카운터 앞판, 직원 구역(마이크 충전 랙 · 캐비닛),
--   UV 살균기(살균하기) · 마이크 커버 디스펜서(뽑기), 방 현황판(실시간), 노래책 거치대, 미러볼 네온 링, 바닥 인레이,
--   X배너 · 우산꽂이 · 분리수거함 · 법정 게시물(청소년 출입시간 · 등록증 · 요금 변경 안내).
-- 복도 (kcorridor): 유광 블랙 징두리 · 신곡 포스터 라이트박스 · 문틀 리빌 · 러너 패턴 · 바닥 방 번호 · 천장 다운라이트/스피커/
--   유도등 · 소화기함 · 피난안내도 · 손 소독기(소독하기) · 안내 터치스크린(페이지 넘기기).

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))
local Scan = require(script.Parent:WaitForChild("Scan"))
local TweenService = game:GetService("TweenService")

local T = {}
T.types = { "karaoke", "kcorridor", "kbooth" }

local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles
local PI = math.pi
local M = Enum.Material
local F = Enum.Font
local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 작은 도구 ------------------------------------------------------------------------------------------
local function dk(c: Color3, f: number): Color3
	return c:Lerp(BLACK, f)
end
local function lt(c: Color3, f: number): Color3
	return c:Lerp(WHITE, f)
end
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
local function rnd(seed: number, i: number): number
	local s = math.sin((seed % 9973) * 0.731 + i * 12.9898) * 43758.5453
	return s - math.floor(s)
end
-- 표시면 프레임 (점 p, 바깥 법선 n): +X = 보는 사람 오른쪽
local function faceCF(p: Vector3, n: Vector3): CFrame
	local x = Vector3.yAxis:Cross(n).Unit
	return CFrame.fromMatrix(p, x, Vector3.yAxis, n)
end
-- 위를 보는 글자판 (바닥 표시 · 책 표지): p 중심, 글자 위쪽 = up (수평)
local function topCF(p: Vector3, up: Vector3): CFrame
	local x = up:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(p, x, up, Vector3.yAxis)
end
-- 표시면에서 튀어나온 원판 (축 = dcf Z)
local function wdisc(K: any, name: string, dia: number, t: number, dcf: CFrame, look: any): BasePart
	return K:disc(name, dia, t, dcf * CF(0, 0, t / 2) * ANG(PI / 2, 0, 0), look)
end
local function snapAxis(v: Vector3): Vector3
	if math.abs(v.X) >= math.abs(v.Z) then
		return V3(if v.X >= 0 then 1 else -1, 0, 0)
	end
	return V3(0, 0, if v.Z >= 0 then 1 else -1)
end
local function hi(K: any): boolean
	return K.detail == "high"
end
local function lo(K: any): boolean
	return K.detail == "low"
end
local function hideRec(K: any, r: any)
	if r and r.part then
		Scan.hide(K.hidden, r.part)
	end
end
-- 파트 원래 축 (rec.lcf) 기준 프레임
local function recCF(r: any): CFrame
	return r.lcf :: CFrame
end
local function step(K: any, name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		K:note("karaoke." .. name .. " error: " .. tostring(err))
	end
end

-- 재질
local LACQ = lk(rgb(16, 15, 20), M.SmoothPlastic, { r = 0.08 }) -- 유광 블랙 래커
local GLOSS = lk(rgb(10, 10, 14), M.Glass, { r = 0.18 }) -- 유광 블랙 패널 (반사)
local CHROME = Look.chrome
local ALU = Look.alu
local DARKALU = Look.darkAlu
local RUBBER = Look.rubber
local CONE = lk(rgb(30, 30, 34), M.Fabric)
local GRILLE = lk(rgb(26, 26, 30), M.DiamondPlate)
local MICGRILLE = lk(rgb(176, 178, 186), M.DiamondPlate)

local NEONS = {
	pink = rgb(255, 60, 170), cyan = rgb(40, 240, 240), purple = rgb(170, 70, 255), green = rgb(60, 255, 120),
	amber = rgb(255, 160, 50), blue = rgb(40, 170, 255), red = rgb(255, 40, 60), yellow = rgb(255, 230, 60), white = rgb(240, 236, 255),
}

-- 노래 (GwangalliVenuesShared.SONGS 와 같은 제목 · 번호 = 38000 + i*131)
local SONGS = {
	"광안대교 불빛 아래", "민락동 치킨송", "2호선 막차", "갈매기 트로트", "썸머 모래성",
	"PC방 영웅", "새벽 편의점", "득근득근", "해운대 말고 광안리", "생일 축하해 친구야",
}
local ARTISTS = { "파도청년단", "바삭즈", "금련산 밴드", "김부산", "오션걸즈", "레벨업", "도시소년", "헬스보이즈", "수영구 청년회", "노래방 오리지널" }
local function songNo(i: number): number
	return 38000 + i * 131
end

-- 실제 천장 아랫면 (방 상자 높이 11.1 보다 0.05 위)
local function ceilingY(V: any): number
	local best = math.huge
	for _, nm in { "Ceiling", "CeilingBoard" } do
		for _, r in V.byName[nm] or {} do
			if r.size.X > 8 and r.size.Z > 8 then
				best = math.min(best, r.min.Y)
			end
		end
	end
	if best == math.huge then
		return V.H + 0.05
	end
	return best
end

-- 소파 오버레이 ----------------------------------------------------------------------------------------
local SOFA_PARTS = { Base = true, Plinth = true, Arm = true, Seat = true, BackCushion = true, Backrest = true }

local function sofaRoot(p: Instance): Instance?
	local a = p.Parent
	while a and a ~= workspace do
		if string.find(a.Name, "Sofa", 1, true) then
			return a
		end
		a = a.Parent
	end
	return nil
end

local function sofaGroups(V: any, accept: (any) -> boolean): { any }
	local by: { [Instance]: any } = {}
	local out = {}
	for _, r in V.parts do
		if SOFA_PARTS[r.name] and accept(r) then
			local root = sofaRoot(r.part)
			if root then
				local g = by[root]
				if not g then
					g = { root = root, recs = {} }
					by[root] = g
					table.insert(out, g)
				end
				table.insert(g.recs, r)
				if r.name == "Backrest" then
					g.back = r
				elseif r.name == "Base" then
					g.base = r
				end
			end
		end
	end
	return out
end

-- o = { color, led (Color3?), leds (목록: 조명 모드용) }
local function sofaOverlay(K: any, g: any, o: any)
	local back, base = g.back, g.base
	if not back or not base then
		return
	end
	local d = base.c - back.c
	local f = snapAxis(V3(d.X, 0, d.Z))
	local org = V3(back.c.X, 0, back.c.Z)
	local sf = CFrame.lookAt(org, org - f) -- +Z = 앉는 쪽(앞)
	local swap = math.abs(f.X) > 0.5
	local C: Color3 = o.color
	local up = lk(C, M.Leather)
	local side = lk(dk(C, 0.18), M.Leather)
	local pipe = lk(dk(C, 0.5), M.Leather)
	local btn = lk(dk(C, 0.42), M.Leather)
	local function loc(r: any): (Vector3, Vector3)
		local c = sf:PointToObjectSpace(r.c)
		local s = if swap then V3(r.size.Z, r.size.Y, r.size.X) else r.size
		return c, s
	end
	K:free(function()
		for _, r in g.recs do
			local c, s = loc(r)
			local at = sf * CF(c)
			local top = c.Y + s.Y / 2
			local bot = c.Y - s.Y / 2
			if r.name == "Plinth" then
				K:box("SofaKick", V3(s.X - 0.04, s.Y, s.Z - 0.04), at, Look.of(20, 20, 24, M.Metal))
				K:box("SofaKickTrim", V3(s.X - 0.04, 0.04, 0.03), at * CF(0, s.Y / 2 - 0.04, s.Z / 2 - 0.005), CHROME)
				if o.led then
					local p = K:box("SofaKickLED", V3(s.X - 0.3, 0.05, 0.03), at * CF(0, -0.02, s.Z / 2 - 0.005), neon(o.led))
					table.insert(o.leds, { p = p, c = o.led })
				end
			elseif r.name == "Base" then
				K:rbox("SofaBase", V3(s.X + 0.03, s.Y + 0.02, s.Z + 0.03), 0.12, at, side)
				K:box("SofaBaseTrim", V3(s.X - 0.2, 0.05, 0.02), at * CF(0, -s.Y / 2 + 0.16, s.Z / 2 + 0.02), CHROME)
			elseif r.name == "Backrest" then
				local dia = s.Z + 0.04
				local h = s.Y - dia / 2 + 0.02
				K:box("SofaBackrest", V3(s.X + 0.03, h, s.Z + 0.03), sf * CF(c.X, bot + h / 2, c.Z), up)
				K:cyl("SofaBackRoll", s.X + 0.03, dia, sf * CF(c.X, top - dia / 2 + 0.01, c.Z), up)
				K:cyl("SofaBackPipe", s.X + 0.05, 0.07, sf * CF(c.X, top - dia * 0.5 + 0.01, c.Z + dia / 2 - 0.01), pipe)
				-- 등받이 뒤쪽 세로 채널 (벽 쪽에서 살짝 보이는 옆면 선)
				if hi(K) then
					K:box("SofaBackSeam", V3(s.X + 0.04, 0.03, 0.02), sf * CF(c.X, bot + 0.6, c.Z + s.Z / 2 + 0.02), pipe)
				end
			elseif r.name == "Arm" then
				local dia = s.X + 0.05
				local h = s.Y - dia / 2 + 0.01
				K:box("SofaArm", V3(s.X + 0.04, h, s.Z + 0.04), sf * CF(c.X, bot + h / 2, c.Z), up)
				K:cyl("SofaArmRoll", s.Z + 0.04, dia, sf * CF(c.X, top - dia / 2 + 0.01, c.Z) * ANG(0, PI / 2, 0), up)
				K:box("SofaArmFront", V3(s.X + 0.06, h - 0.2, 0.03), sf * CF(c.X, bot + h / 2 + 0.05, c.Z + s.Z / 2 + 0.03), side)
				K:box("SofaArmTrim", V3(0.06, h - 0.4, 0.02), sf * CF(c.X, bot + h / 2 + 0.05, c.Z + s.Z / 2 + 0.05), CHROME)
			elseif r.name == "Seat" then
				-- Seat 은 숨기지 않음: 같은 자세 쿠션으로 감쌈 (윗면 +0.02)
				local th = 0.46
				K:rbox("SofaCushion", V3(s.X + 0.05, th, s.Z + 0.05), 0.15, sf * CF(c.X, top + 0.02 - th / 2, c.Z), up)
				K:cyl("SofaCushionPipe", s.X + 0.02, 0.06, sf * CF(c.X, top - 0.2, c.Z + s.Z / 2 + 0.03), pipe)
				if s.X > 3.6 then
					K:box("SofaCushionSeam", V3(0.05, 0.03, s.Z - 0.1), sf * CF(c.X, top + 0.03, c.Z), pipe)
					K:box("SofaCushionGap", V3(0.05, th - 0.1, 0.03), sf * CF(c.X, top - th / 2, c.Z + s.Z / 2 + 0.03), pipe)
				end
			elseif r.name == "BackCushion" then
				K:rbox("SofaBackCushion", V3(s.X - 0.03, s.Y, s.Z + 0.08), 0.19, at, up)
				if not lo(K) then
					local n = math.max(2, math.floor(s.X / 0.9))
					for i = 1, n do
						local x = -s.X / 2 + (i - 0.5) * s.X / n
						for _, yy in { 0.27, -0.2 } do
							K:ball("SofaButton", 0.11, at * CF(x, yy * s.Y, s.Z / 2 + 0.035), btn)
						end
					end
				end
			end
		end
	end)
	for _, r in g.recs do
		if r.name ~= "Seat" then
			hideRec(K, r)
		end
	end
end

-- 스피커 (드라이버: 서라운드 + 콘 + 더스트캡 + LED 링) ---------------------------------------------------
local function driver(K: any, dcf: CFrame, dia: number, ring: Color3?, leds: { any }?)
	if ring then
		local p = wdisc(K, "SpeakerLEDRing", dia + 0.07, 0.02, dcf, neon(ring))
		if leds then
			table.insert(leds, { p = p, c = ring })
		end
	end
	wdisc(K, "SpeakerSurround", dia, 0.05, dcf, RUBBER)
	wdisc(K, "SpeakerCone", dia * 0.78, 0.06, dcf, CONE)
	K:ball("SpeakerDustCap", dia * 0.28, dcf * CF(0, 0, 0.06), lk(rgb(40, 40, 44), M.Metal))
end

-- 세로 스피커 (FloorSpeaker): 둥근 모서리 캐비닛 + 그릴 테 + 우퍼 2 + 혼 트위터 + 포트 + 로고
local function columnSpeaker(K: any, r: any, ring: Color3?, leds: { any })
	local mn, mx = r.min, r.max
	local c = (mn + mx) / 2
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	local front = mx.Z
	K:free(function()
		K:rbox("SpeakerCabinet", V3(h + 0.02, w + 0.06, d + 0.04), 0.1, CF(c.X, c.Y, c.Z) * ANG(0, 0, PI / 2), lk(rgb(22, 22, 26), M.SmoothPlastic, { r = 0.05 }))
		local f0 = faceCF(V3(c.X, 0, front + 0.02), V3(0, 0, 1))
		K:plate("SpeakerBaffle", w - 0.08, h - 0.3, 0.02, f0 * CF(0, c.Y, 0), lk(rgb(14, 14, 16)))
		for _, yy in { 1.35, 3.35 } do
			driver(K, f0 * CF(0, yy, 0.02), math.min(0.74, w - 0.16), ring, leds)
		end
		K:plate("SpeakerHorn", w - 0.3, 0.42, 0.06, f0 * CF(0, 4.85, 0.02), lk(rgb(34, 34, 38), M.Metal))
		K:plate("SpeakerHornThroat", 0.34, 0.2, 0.07, f0 * CF(0, 4.85, 0.02), lk(rgb(8, 8, 10)))
		K:ball("SpeakerTweeter", 0.14, f0 * CF(0, 4.85, 0.08), lk(rgb(190, 190, 196), M.Metal))
		K:plate("SpeakerPort", w - 0.36, 0.12, 0.03, f0 * CF(0, 0.42, 0.02), lk(rgb(4, 4, 6)))
		K:text("SpeakerBadge", 0.36, 0.1, f0 * CF(0, 5.3, 0.02), "GW·PRO", { fg = rgb(200, 200, 206), font = F.GothamBlack, d = 0.01 })
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				K:vcyl("SpeakerFoot", 0.06, 0.16, CF(c.X + sx * (w / 2 - 0.12), 0.03, c.Z + sz * (d / 2 - 0.15)), CHROME)
			end
		end
	end)
end

-- 천장 모서리 스피커 (Speaker): 캐비닛 + 그릴 + 벽 브래킷
local function wallSpeaker(K: any, r: any)
	local mn, mx = r.min, r.max
	local c = (mn + mx) / 2
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	K:free(function()
		K:rbox("WallSpeakerBox", V3(h, w + 0.04, d + 0.02), 0.08, CF(c) * ANG(0, 0, PI / 2), lk(rgb(26, 26, 30)))
		local f0 = faceCF(V3(c.X, c.Y, mx.Z + 0.01), V3(0, 0, 1))
		K:plate("WallSpeakerGrille", w - 0.14, h - 0.18, 0.03, f0, GRILLE)
		driver(K, f0 * CF(0, 0.25, 0.03), 0.8, nil, nil)
		K:ball("WallSpeakerTweet", 0.16, f0 * CF(0, -0.68, 0.05), lk(rgb(170, 170, 176), M.Metal))
		for _, sx in { -1, 1 } do
			K:box("WallSpeakerBracket", V3(0.06, 0.5, d * 0.7), CF(c.X + sx * (w / 2 + 0.05), c.Y, c.Z - d * 0.1), DARKALU)
			wdisc(K, "WallSpeakerKnob", 0.16, 0.05, faceCF(V3(c.X + sx * (w / 2 + 0.08), c.Y, c.Z), V3(sx, 0, 0)), DARKALU)
		end
	end)
end

local function subwoofer(K: any, r: any, ring: Color3?, leds: { any })
	local mn, mx = r.min, r.max
	local c = (mn + mx) / 2
	local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
	K:free(function()
		K:rbox("SubCabinet", V3(w + 0.04, h + 0.02, d + 0.04), 0.08, CF(c), lk(rgb(20, 20, 24), M.SmoothPlastic, { r = 0.04 }))
		local f0 = faceCF(V3(c.X, c.Y + 0.08, mx.Z + 0.02), V3(0, 0, 1))
		driver(K, f0, math.min(1.02, w - 0.2), ring, leds)
		K:plate("SubPort", w - 0.4, 0.1, 0.02, f0 * CF(0, -h / 2 + 0.2, 0), lk(rgb(4, 4, 6)))
		K:text("SubBadge", 0.5, 0.1, f0 * CF(0, h / 2 - 0.16, 0), "SUB 12\"", { fg = rgb(190, 190, 196), font = F.GothamBold, d = 0.01 })
	end)
end

-- 마이크 (손잡이 + 밴드 + 그릴 볼): a = 손잡이 끝, b = 그릴 쪽 (로컬 점)
local function handMic(K: any, a: Vector3, b: Vector3, body: any, band: Color3, cover: Color3?)
	local dir = (b - a).Unit
	K:seg("MicBodyTail", a, a:Lerp(b, 0.55), 0.24, body)
	K:seg("MicBodyNeck", a:Lerp(b, 0.55), b - dir * 0.18, 0.3, body)
	K:seg("MicBand", b - dir * 0.22, b - dir * 0.16, 0.32, neon(band))
	local head = b + dir * 0.1
	if cover then
		K:ball("MicCoverSponge", 0.5, CF(head), lk(cover, M.Fabric))
	else
		K:ball("MicGrille", 0.44, CF(head), MICGRILLE)
	end
	K:seg("MicSwitch", a:Lerp(b, 0.6) + V3(0, 0.13, 0), a:Lerp(b, 0.7) + V3(0, 0.13, 0), 0.06, lk(rgb(60, 60, 64)))
end

-- 상태 · 테마 ------------------------------------------------------------------------------------------
local function boothModel(V: any): Instance?
	local best, bd = nil, math.huge
	for _, r in V.byName.KaraokeZone or {} do
		local d = math.abs(r.c.X) + math.abs(r.c.Z)
		if d < bd then
			best, bd = r, d
		end
	end
	if best and bd < 3 then
		return best.part.Parent
	end
	return nil
end

local function attr(m: Instance?, k: string): any
	if not m then
		return nil
	end
	local ok, v = pcall(function()
		return m:GetAttribute(k)
	end)
	return if ok then v else nil
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

local function rented(m: Instance?): boolean
	local r = attr(m, "KRenter")
	return type(r) == "number" and r ~= 0
end

-- 조명 모드 묶음 (부스) ---------------------------------------------------------------------------------
-- st = { leds = { {p, c} }, stars = { p }, lights = { {l, c, b} }, mode = 1 }
local MODES = { "기본", "무드", "파티", "끄기" }
local WARM = rgb(255, 136, 60)

local function applyMode(st: any, t: number)
	local mode = st.mode
	for i, e in st.leds do
		local p: BasePart = e.p
		if p.Parent then
			if mode == 4 then
				p.Material = M.SmoothPlastic
				p.Color = dk(e.c, 0.75)
			elseif mode == 3 then
				p.Material = M.Neon
				p.Color = Color3.fromHSV((t * 0.18 + i * 0.07) % 1, 0.85, 1)
			elseif mode == 2 then
				p.Material = M.Neon
				p.Color = e.c:Lerp(WARM, 0.75)
			else
				p.Material = M.Neon
				p.Color = e.c
			end
		end
	end
	for i, p in st.stars do
		if p.Parent then
			if mode == 4 then
				p.Transparency = 1
			elseif mode == 3 then
				p.Transparency = if rnd(i, math.floor(t * 6)) > 0.55 then 0 else 0.85
			else
				p.Transparency = if mode == 2 then 0.35 else 0
			end
		end
	end
	for i, e in st.lights do
		local l: any = e.l
		if l.Parent then
			l.Enabled = mode ~= 4 and not (e.party and mode ~= 3)
			if mode == 3 then
				l.Color = Color3.fromHSV((t * 0.18 + i * 0.21) % 1, 0.8, 1)
				l.Brightness = e.b * 1.15
			elseif mode == 2 then
				l.Color = e.c:Lerp(WARM, 0.75)
				l.Brightness = e.b * 0.55
			else
				l.Color = e.c
				l.Brightness = e.b
			end
		end
	end
	for i, p in st.buttons or {} do
		if p.Parent then
			p.Material = if i == mode then M.Neon else M.SmoothPlastic
			p.Transparency = if i == mode then 0 else 0.1
		end
	end
end

local function addLight(K: any, st: any, part: BasePart, kind: string, props: { [string]: any }, party: boolean?): Light?
	local l = K:light(part, kind, props)
	if l then
		table.insert(st.lights, { l = l, c = props.Color or WHITE, b = props.Brightness or 1, party = party })
		if party then
			l.Enabled = false
		end
	end
	return l
end

-- =====================================================================================================
-- 부스 (kbooth)
-- =====================================================================================================
local function boothBuild(K: any, V: any, S: any)
	local booth = boothModel(V)
	local function mine(r: any): boolean
		return booth ~= nil and r.part:IsDescendantOf(booth)
	end
	local function first(name: string): any?
		for _, r in V.byName[name] or {} do
			if mine(r) then
				return r
			end
		end
		return nil
	end
	local function all(name: string): { any }
		local out = {}
		for _, r in V.byName[name] or {} do
			if mine(r) then
				table.insert(out, r)
			end
		end
		return out
	end
	local roomNo = tonumber(attr(booth, "RoomNo")) or tonumber(string.match(tostring(V.room or ""), "%d+")) or 1
	local H = S.ceilY or V.H
	-- 테마: 맵의 LED 띠 색 · 패브릭 벽 색 · 소파 색
	local ledR = first("LedStrip")
	local theme: Color3 = if ledR then ledR.part.Color else NEONS.cyan
	local accR = first("AccentWall")
	local fabric: Color3 = if accR then accR.part.Color else rgb(30, 42, 120)
	local baseR = first("Base")
	local leather: Color3 = if baseR then baseR.part.Color else rgb(130, 26, 30)
	local zBack = if accR then accR.max.Z else V.z0
	local cw = first("CorridorWall")
	local zFront = if cw then cw.min.Z else V.z1
	local x0, x1 = V.x0, V.x1
	local st: any = { leds = {}, stars = {}, lights = {}, mode = 1, buttons = {} }
	K.kst = st
	local wallTone = lk(dk(fabric, 0.55), M.Fabric)
	local panelTone = lk(lt(dk(fabric, 0.15), 0.06), M.Fabric)

	-- 1) 소파 (U자 3개) -------------------------------------------------------------------------------
	step(K, "sofa", function()
		for _, g in sofaGroups(V, mine) do
			sofaOverlay(K, g, { color = leather, led = theme, leds = st.leds })
		end
	end)

	-- 2) 테이블: 받침 다시 + 유리 상판 크롬 테 (상판 · 위 소품 자리 그대로) -------------------------------------
	step(K, "table", function()
		local tb = first("TableBase")
		local tt = first("TableTop")
		K:free(function()
			if tb then
				local c = tb.c
				local s = tb.size
				K:rbox("TablePedestal", V3(s.Y - 0.02, s.X - 0.04, s.Z - 0.04), 0.3, CF(c.X, c.Y, c.Z) * ANG(0, 0, PI / 2), LACQ)
				K:box("TableBand", V3(s.X - 0.02, 0.06, s.Z - 0.02), CF(c.X, tb.max.Y - 0.06, c.Z), CHROME)
				local p = K:box("TableLEDLine", V3(s.X + 0.0, 0.05, s.Z + 0.0), CF(c.X, 0.42, c.Z), neon(theme))
				table.insert(st.leds, { p = p, c = theme })
				hideRec(K, tb)
			end
			if tt then
				local mn, mx = tt.min, tt.max
				local cy = (mn.Y + mx.Y) / 2
				local h = mx.Y - mn.Y - 0.03
				local cx, cz = (mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2
				local w, l = mx.X - mn.X, mx.Z - mn.Z
				K:box("TableRim", V3(w + 0.06, h, 0.04), CF(cx, cy - 0.015, mx.Z + 0.02), CHROME)
				K:box("TableRim", V3(w + 0.06, h, 0.04), CF(cx, cy - 0.015, mn.Z - 0.02), CHROME)
				K:box("TableRim", V3(0.04, h, l + 0.02), CF(mx.X + 0.02, cy - 0.015, cz), CHROME)
				K:box("TableRim", V3(0.04, h, l + 0.02), CF(mn.X - 0.02, cy - 0.015, cz), CHROME)
			end
		end)
	end)

	-- 3) 테이블 위 소품 (같은 자리 다시: 마이크 · 탬버린 · 노래책 · 리모컨 · 안내 스탠드) ------------------------------
	step(K, "tableItems", function()
		K:free(function()
			local mics = all("WirelessMic")
			local heads = all("WirelessMicHead")
			for i, m in mics do
				local cfm = recCF(m)
				local ax = cfm.XVector
				local len = m.part.Size.X
				local pA = cfm.Position + ax * len / 2
				local pB = cfm.Position - ax * len / 2
				-- 그릴 쪽 = 머리에 가까운 끝
				local hd = heads[i]
				if hd and (hd.c - pA).Magnitude < (hd.c - pB).Magnitude then
					pA, pB = pB, pA
				end
				local y = m.c.Y
				pA = V3(pA.X, y, pA.Z)
				pB = V3(pB.X, y, pB.Z)
				local body = if m.part.Color.R > 0.5 then lk(rgb(232, 232, 236), M.SmoothPlastic, { r = 0.05 }) else lk(rgb(30, 30, 34), M.SmoothPlastic, { r = 0.05 })
				handMic(K, pA, pB, body, if i == 1 then theme else NEONS.pink, if i == 2 then rgb(220, 40, 60) else nil)
				hideRec(K, m)
				if hd then
					hideRec(K, hd)
				end
			end
			local tam = first("Tambourine")
			if tam then
				local c = tam.c
				local dia = tam.size.X
				local base = CF(c.X, tam.min.Y, c.Z)
				K:disc("TambourineRim", dia, 0.2, base * CF(0, 0.1, 0), lk(rgb(250, 204, 20), M.Plastic))
				K:disc("TambourineHole", dia * 0.62, 0.21, base * CF(0, 0.1, 0), lk(rgb(30, 30, 36)))
				K:box("TambourineGrip", V3(dia * 0.62, 0.16, 0.18), base * CF(0, 0.1, 0), lk(rgb(250, 204, 20), M.Plastic))
				for j = 0, 4 do
					local a = j * 2 * PI / 5 + 0.3
					local r0 = dia * 0.4
					local p = base * CF(math.cos(a) * r0, 0.1, math.sin(a) * r0)
					K:box("TambourineSlot", V3(0.3, 0.22, 0.16), p * ANG(0, -a, 0), lk(rgb(20, 20, 24)))
					K:disc("TambourineJingle", 0.22, 0.03, p * CF(0, 0.05, 0), lk(rgb(214, 218, 226), M.Metal, { r = 0.2 }))
					K:disc("TambourineJingle", 0.22, 0.03, p * CF(0, -0.05, 0), lk(rgb(214, 218, 226), M.Metal, { r = 0.2 }))
				end
				hideRec(K, tam)
				for _, j in all("Jingle") do
					hideRec(K, j)
				end
			end
			local book = first("SongBook")
			if book then
				local c, s = book.c, book.size
				local th = s.Y
				K:box("SongBookCover", V3(s.X, 0.06, s.Z), CF(c.X, book.min.Y + 0.03, c.Z), lk(dk(theme, 0.35)))
				K:box("SongBookPages", V3(s.X - 0.08, th - 0.12, s.Z - 0.06), CF(c.X + 0.02, c.Y, c.Z), lk(rgb(240, 236, 226)))
				K:box("SongBookCover", V3(s.X, 0.06, s.Z), CF(c.X, book.max.Y - 0.03, c.Z), lk(dk(theme, 0.35)))
				K:box("SongBookSpine", V3(0.08, th, s.Z), CF(book.min.X + 0.04, c.Y, c.Z), lk(dk(theme, 0.55)))
				for j, col in { NEONS.red, NEONS.yellow, NEONS.green, NEONS.blue } do
					K:box("SongBookTab", V3(0.12, 0.04, 0.2), CF(book.max.X + 0.02, c.Y + 0.1 - j * 0.05, book.min.Z + 0.3 + j * 0.28), lk(col))
				end
				K:text("SongBookTitle", s.X - 0.2, s.Z * 0.5, topCF(V3(c.X, book.max.Y + 0.002, c.Z), V3(0, 0, -1)), "노래방 책\n2026 최신곡", { fg = WHITE, font = F.GothamBlack, d = 0.01, free = true })
				hideRec(K, book)
				hideRec(K, first("SongBookLabel"))
			end
			local rem = first("Remote")
			if rem then
				local cfr = recCF(rem)
				local s = rem.part.Size
				local long = if s.Z >= s.X then cfr.ZVector else cfr.XVector
				local L = math.max(s.X, s.Z)
				local Wd = math.min(s.X, s.Z)
				local c = V3(rem.c.X, rem.min.Y, rem.c.Z)
				local frame = CFrame.lookAt(c, c + V3(long.X, 0, long.Z)) -- -Z = 리모컨 앞(화면 쪽)
				K:rbox("RemoteBody", V3(L, 0.12, Wd + 0.02), 0.05, frame * CF(0, 0.06, 0) * ANG(0, PI / 2, 0), lk(rgb(28, 28, 32), M.SmoothPlastic, { r = 0.06 }))
				K:box("RemoteScreen", V3(Wd - 0.08, 0.02, 0.24), frame * CF(0, 0.125, -L / 2 + 0.2), lk(rgb(60, 200, 230), M.Neon, { t = 0.2 }))
				if not lo(K) then
					for row = 0, 3 do
						for col = -1, 1 do
							K:box("RemoteKey", V3(0.07, 0.025, 0.06), frame * CF(col * 0.09, 0.125, -L / 2 + 0.46 + row * 0.1), lk(rgb(200, 200, 206)))
						end
					end
				end
				K:box("RemoteKeyRes", V3(0.12, 0.03, 0.08), frame * CF(-0.06, 0.13, L / 2 - 0.18), lk(rgb(40, 120, 230)))
				K:box("RemoteKeyCancel", V3(0.12, 0.03, 0.08), frame * CF(0.07, 0.13, L / 2 - 0.18), lk(rgb(220, 40, 50)))
				hideRec(K, rem)
				hideRec(K, first("RemoteKeys"))
			end
			local ms = first("MenuStand")
			if ms then
				local c = V3(ms.c.X, ms.min.Y, ms.c.Z)
				local w = math.max(ms.size.X, ms.size.Z) * 0.9
				local along = if ms.size.X >= ms.size.Z then V3(1, 0, 0) else V3(0, 0, 1)
				local n = Vector3.yAxis:Cross(along)
				K:box("MenuStandFoot", V3(w, 0.04, 0.42), CFrame.fromMatrix(c + V3(0, 0.02, 0), along, Vector3.yAxis, n), lk(rgb(240, 240, 244), M.Glass, { t = 0.3 }))
				for _, sgn in { 1, -1 } do
					local nn = n * sgn
					local d0 = faceCF(c + V3(0, 0.38, 0) + nn * 0.09, nn) * ANG(math.rad(-12), 0, 0)
					K:text("MenuStandCard", w - 0.06, 0.66, d0, "이용 안내\n30분 500원 · 자동 연장\n문 옆 패널에서 방 잡기\n주류 · 흡연 금지", { fg = rgb(30, 30, 40), bg = rgb(250, 248, 240), d = 0.02, font = F.GothamBold, free = true })
				end
				hideRec(K, ms)
			end
			-- 컵: 빨대 · 얼음
			for i, cp in all("Cup") do
				local top = cp.max.Y
				K:seg("CupStraw", V3(cp.c.X, top - 0.3, cp.c.Z), V3(cp.c.X + 0.12, top + 0.32, cp.c.Z - 0.08), 0.05, lk(if i == 1 then rgb(240, 80, 120) else rgb(60, 160, 240)))
				K:disc("CupIce", cp.size.X * 0.8, 0.04, CF(cp.c.X, top - 0.12, cp.c.Z), lk(rgb(220, 236, 244), M.Glass, { t = 0.3 }))
			end
			local tissue = first("TissueBox")
			if tissue then
				K:ell("TissuePuff", V3(0.3, 0.26, 0.22), CF(tissue.c.X, tissue.max.Y + 0.08, tissue.c.Z), lk(rgb(250, 250, 248), M.Fabric))
				K:box("TissueBand", V3(tissue.size.X + 0.01, 0.1, tissue.size.Z + 0.01), CF(tissue.c.X, tissue.c.Y, tissue.c.Z), lk(dk(theme, 0.3)))
			end
		end)
	end)

	-- 4) TV 벽: 베젤 테 · LED 헤일로 · 위 네온 간판 · 옆 LED 바 (화면 앞면은 비움) ------------------------------
	step(K, "tvwall", function()
		local bez = first("TVBezel")
		local scr = first("KaraokeScreen")
		if bez and scr then
			local bmn, bmx = bez.min, bez.max
			local smn, smx = scr.min, scr.max
			local zf = bmx.Z -- 베젤 앞면
			local cx = (bmn.X + bmx.X) / 2
			local fz = faceCF(V3(cx, 0, zf), V3(0, 0, 1))
			K:free(function()
				-- 화면 바깥 테두리 (화면 사각형 밖만)
				local topH = bmx.Y - smx.Y
				local botH = smn.Y - bmn.Y
				local sideW = (bmx.X - bmn.X - (smx.X - smn.X)) / 2
				local bw = bmx.X - bmn.X
				K:plate("TVFrameTop", bw, topH, 0.05, fz * CF(0, smx.Y + topH / 2, 0), GLOSS)
				K:plate("TVFrameBot", bw, botH, 0.05, fz * CF(0, bmn.Y + botH / 2, 0), GLOSS)
				K:plate("TVFrameSide", sideW, smx.Y - smn.Y, 0.05, fz * CF(-bw / 2 + sideW / 2, (smn.Y + smx.Y) / 2, 0), GLOSS)
				K:plate("TVFrameSide", sideW, smx.Y - smn.Y, 0.05, fz * CF(bw / 2 - sideW / 2, (smn.Y + smx.Y) / 2, 0), GLOSS)
				for _, sy in { -1, 1 } do
					K:plate("TVTrim", bw, 0.035, 0.06, fz * CF(0, (bmn.Y + bmx.Y) / 2 + sy * ((bmx.Y - bmn.Y) / 2 - 0.0175), 0), CHROME)
					K:plate("TVTrim", 0.035, bmx.Y - bmn.Y, 0.06, fz * CF(sy * (bw / 2 - 0.0175), (bmn.Y + bmx.Y) / 2, 0), CHROME)
				end
				K:text("TVLogo", 1.0, math.min(0.12, botH * 0.7), fz * CF(0, bmn.Y + botH / 2, 0.055), "GW MEDIA", { fg = rgb(170, 170, 180), font = F.GothamBold, d = 0.005 })
				K:plate("TVPowerLED", 0.06, 0.04, 0.06, fz * CF(bw / 2 - 0.3, bmn.Y + botH / 2, 0.01), Look.ledRed)
				-- 벽 쪽 LED 헤일로 (베젤 밖으로 0.1 삐져나온 빛 테)
				local zw = zBack + 0.01
				local hz = faceCF(V3(cx, 0, zw), V3(0, 0, 1))
				local hw, hh = bw + 0.24, (bmx.Y - bmn.Y) + 0.24
				local hc = (bmn.Y + bmx.Y) / 2
				local parts = {
					K:plate("TVHaloLED", hw, 0.08, 0.05, hz * CF(0, hc + hh / 2 - 0.04, 0), neon(theme)),
					K:plate("TVHaloLED", hw, 0.08, 0.05, hz * CF(0, hc - hh / 2 + 0.04, 0), neon(theme)),
					K:plate("TVHaloLED", 0.08, hh, 0.05, hz * CF(-hw / 2 + 0.04, hc, 0), neon(theme)),
					K:plate("TVHaloLED", 0.08, hh, 0.05, hz * CF(hw / 2 - 0.04, hc, 0), neon(theme)),
				}
				for _, p in parts do
					table.insert(st.leds, { p = p, c = theme })
				end
				addLight(K, st, parts[1], "PointLight", { Range = 9, Brightness = 0.7, Color = theme })
				-- 위: 네온 간판 (검정 아크릴 + 글자)
				local sy0 = bmx.Y + 0.35
				local sh = math.min(1.2, H - 0.75 - sy0)
				if sh > 0.6 then
					K:plate("TVTopSignBack", 5.6, sh, 0.08, hz * CF(0, sy0 + sh / 2, 0), GLOSS)
					local p = K:text("TVTopSign", 5.2, sh * 0.72, hz * CF(0, sy0 + sh / 2, 0.1), string.format("♪ ROOM %02d  ·  SING SING", roomNo), { fg = theme, glow = 2.2, font = F.FredokaOne, d = 0.02 })
					local _ = p
					local ln = K:plate("TVTopSignLine", 5.4, 0.04, 0.1, hz * CF(0, sy0 + 0.06, 0), neon(theme))
					table.insert(st.leds, { p = ln, c = theme })
				end
				-- 옆 세로 LED 바 (바닥 스피커 위 · 천장 스피커 아래)
				for _, sx in { -1, 1 } do
					local x = sx * ((bmx.X - bmn.X) / 2 + 0.62)
					local p = K:plate("TVSideLED", 0.1, 2.2, 0.06, hz * CF(x, 6.9, 0), neon(theme))
					table.insert(st.leds, { p = p, c = theme })
					K:plate("TVSideLEDBack", 0.3, 2.4, 0.03, hz * CF(x, 6.9, 0), GLOSS)
				end
			end)
		end
	end)

	-- 5) AV 장 · 반주기 · 마이크 충전 거치대 ------------------------------------------------------------------
	step(K, "av", function()
		local cab = first("MachineCabinet")
		local ctop = first("CabinetTop")
		K:free(function()
			if cab then
				local mn, mx = cab.min, cab.max
				local c = (mn + mx) / 2
				local w, h, d = mx.X - mn.X + 0.06, mx.Y - mn.Y, mx.Z - mn.Z + 0.04
				local zf = mx.Z + 0.02
				-- 몸체 (옆판 · 뒤판 · 바닥 · 칸막이: 앞 0.18 들어간 칸)
				local rec = 0.18
				K:box("CabinetSide", V3(0.12, h, d), CF(mn.X - 0.03 + 0.06, c.Y, c.Z), LACQ)
				K:box("CabinetSide", V3(0.12, h, d), CF(mx.X + 0.03 - 0.06, c.Y, c.Z), LACQ)
				local bayW = (w - 0.24 - 0.16) / 3
				local xs = { mn.X + 0.12 + bayW / 2, c.X, mx.X - 0.12 - bayW / 2 }
				local zb = mn.Z - 0.02
				for k, x in xs do
					local depth = if k == 2 then 1.4 else rec
					local bd = (zf - depth) - zb
					K:box("CabinetBack", V3(bayW + 0.02, h - 0.3, bd), CF(x, c.Y + 0.15, zb + bd / 2), lk(rgb(10, 10, 12)))
				end
				K:box("CabinetKick", V3(w - 0.24, 0.24, 0.05), CF(c.X, 0.12, zf - rec - 0.02), lk(rgb(8, 8, 10)))
				K:box("CabinetShelf", V3(w - 0.2, 0.08, d), CF(c.X, 0.28, c.Z), LACQ)
				for _, dx in { -1, 1 } do
					K:box("CabinetDivider", V3(0.08, h - 0.32, d), CF(c.X + dx * (bayW / 2 + 0.04), c.Y + 0.14, c.Z), LACQ)
				end
				K:box("CabinetFrontTrim", V3(w, 0.04, 0.03), CF(c.X, mx.Y - 0.05, zf), CHROME)
				local fz = faceCF(V3(0, 0, zf - rec + 0.02), V3(0, 0, 1))
				-- 왼쪽 칸: 앰프 (VU 미터 2 · 노브 4) + 무선 수신기
				do
					local x = xs[1]
					K:plate("AmpFace", bayW - 0.06, 0.95, 0.06, fz * CF(x, 1.85, 0), lk(rgb(176, 178, 184), M.Metal))
					for k, ux in { -0.42, 0.06 } do
						K:plate("AmpVU", 0.42, 0.26, 0.07, fz * CF(x + ux, 2.08, 0), lk(rgb(255, 176, 80), M.Neon, { t = 0.15 }))
						K:plate("AmpNeedle", 0.02, 0.2, 0.08, fz * CF(x + ux - 0.04 + k * 0.03, 2.06, 0) * ANG(0, 0, 0.35 - k * 0.5), lk(rgb(20, 20, 20)))
					end
					for k = 0, 3 do
						wdisc(K, "AmpKnob", 0.17, 0.08, fz * CF(x - 0.6 + k * 0.4, 1.6, 0.06), lk(rgb(30, 30, 34), M.Metal))
					end
					K:text("AmpLabel", bayW - 0.2, 0.09, fz * CF(x, 1.45, 0.065), "MIC    ECHO    MUSIC    MASTER", { fg = rgb(30, 30, 34), font = F.GothamBold, d = 0.005 })
					K:text("AmpBrand", 0.5, 0.08, fz * CF(x + 0.55, 2.24, 0.065), "GW-A800", { fg = rgb(30, 30, 34), font = F.GothamBlack, d = 0.005 })
					K:plate("RxFace", bayW - 0.06, 0.5, 0.06, fz * CF(x, 1.0, 0), lk(rgb(22, 22, 26), M.Metal))
					for k, ux in { -0.35, 0.35 } do
						K:plate("RxLCD", 0.5, 0.2, 0.065, fz * CF(x + ux, 1.05, 0), lk(rgb(30, 60, 110)))
						K:text("RxLCDText", 0.46, 0.16, fz * CF(x + ux, 1.05, 0.07), if k == 1 then "A 638.2" else "B 645.5", { fg = rgb(140, 220, 255), glow = 1.4, font = F.Arcade, d = 0.005 })
					end
					K:plate("RxLED", 0.05, 0.05, 0.07, fz * CF(x + 0.8, 0.86, 0), Look.ledGreen)
					K:plate("BayVent", bayW - 0.06, 0.38, 0.03, fz * CF(x, 0.55, 0), lk(rgb(12, 12, 14)))
					for k = 0, 2 do
						K:plate("BayVentSlot", bayW - 0.3, 0.03, 0.04, fz * CF(x, 0.45 + k * 0.1, 0), lk(rgb(40, 40, 44)))
					end
				end
				-- 가운데 칸: 열린 선반 (노래책 · 마이크 커버 상자 · 건전지)
				do
					local x = xs[2]
					local sy = 1.32
					K:box("CabinetMidShelf", V3(bayW, 0.06, 1.38), CF(x, sy, zf - 0.71), LACQ)
					K:box("CabinetMidLED", V3(bayW - 0.1, 0.03, 0.04), CF(x, mx.Y - 0.14, zf - 0.08), neon(theme))
					for k = 0, 2 do
						local th = 0.22 + k * 0.03
						K:box("ShelfSongBook", V3(bayW * 0.8, th, 1.0), CF(x, 0.32 + k * 0.27 + th / 2, zf - 0.72), lk(({ rgb(200, 40, 60), rgb(40, 90, 200), rgb(250, 190, 30) })[k + 1]))
						K:box("ShelfSongBookPages", V3(bayW * 0.8 - 0.06, th - 0.06, 0.02), CF(x, 0.32 + k * 0.27 + th / 2, zf - 0.21), lk(rgb(240, 236, 226)))
					end
					K:box("ShelfCoverBox", V3(0.8, 0.5, 0.6), CF(x - 0.25, sy + 0.28, zf - 0.6), lk(rgb(240, 240, 236)))
					K:text("ShelfCoverLabel", 0.7, 0.26, faceCF(V3(x - 0.25, sy + 0.3, zf - 0.295), V3(0, 0, 1)), "마이크 커버\n100매", { fg = rgb(220, 40, 90), font = F.GothamBold, d = 0.005 })
					K:box("ShelfBattery", V3(0.5, 0.3, 0.4), CF(x + 0.42, sy + 0.18, zf - 0.5), lk(rgb(30, 30, 30)))
					K:plate("ShelfBatteryBand", 0.5, 0.1, 0.01, faceCF(V3(x + 0.42, sy + 0.18, zf - 0.295), V3(0, 0, 1)), lk(rgb(250, 190, 30)))
				end
				-- 오른쪽 칸: 스모크 유리문 (안에 파워 분배기 LED)
				do
					local x = xs[3]
					K:plate("PowerUnit", bayW - 0.1, 0.4, 0.04, fz * CF(x, 1.5, 0), lk(rgb(26, 26, 30), M.Metal))
					for k = 0, 3 do
						K:plate("PowerLED", 0.06, 0.06, 0.05, fz * CF(x - 0.5 + k * 0.3, 1.5, 0), if k < 3 then Look.ledBlue else Look.ledRed)
					end
					local dz = zf - 0.02
					local fd = faceCF(V3(x, 0, dz), V3(0, 0, 1))
					K:plate("CabinetGlassDoor", bayW - 0.02, h - 0.42, 0.03, fd * CF(0, 0.32 + (h - 0.42) / 2, 0), lk(rgb(40, 40, 50), M.Glass, { t = 0.45, r = 0.15 }))
					K:plate("CabinetDoorPull", 0.05, 0.8, 0.06, fd * CF(-bayW / 2 + 0.16, 1.3, 0.03), CHROME)
				end
			end
			if ctop then
				local mn, mx = ctop.min, ctop.max
				K:box("CabinetTopStone", V3(mx.X - mn.X + 0.06, mx.Y - mn.Y + 0.02, mx.Z - mn.Z + 0.04), CF((mn + mx) / 2), lk(rgb(34, 30, 40), M.Marble, { r = 0.06 }))
				K:box("CabinetTopEdge", V3(mx.X - mn.X + 0.08, 0.04, 0.03), CF((mn.X + mx.X) / 2, mn.Y + 0.03, mx.Z + 0.03), CHROME)
				-- 안테나 (무선 수신기)
				for k, x in { mn.X + 0.35, mn.X + 0.85 } do
					K:seg("RxAntenna", V3(x, mx.Y, mn.Z + 0.35), V3(x + (k - 1.5) * 0.3, mx.Y + 0.85, mn.Z + 0.28), 0.06, lk(rgb(20, 20, 22)))
				end
				-- 왼쪽 끝: 손 소독제 · 휴지
				K:vcyl("SanitizerBottle", 0.5, 0.26, CF(mn.X + 0.45, mx.Y + 0.25, mx.Z - 0.4), lk(rgb(220, 236, 244), M.Glass, { t = 0.3 }))
				K:vcyl("SanitizerPump", 0.14, 0.1, CF(mn.X + 0.45, mx.Y + 0.57, mx.Z - 0.4), lk(rgb(240, 240, 240)))
			end
			for _, r in { cab, ctop, first("CabinetSeam") } do
				hideRec(K, r)
			end
			-- 반주기
			local km = first("KaraokeMachine")
			if km then
				local mn, mx = km.min, km.max
				local c = (mn + mx) / 2
				local w, h, d = mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z
				K:rbox("KMBody", V3(w + 0.04, h + 0.02, d + 0.04), 0.06, CF(c), lk(rgb(40, 42, 48), M.Metal))
				local fz = faceCF(V3(c.X, c.Y, mx.Z + 0.02), V3(0, 0, 1))
				K:plate("KMFace", w - 0.06, h - 0.1, 0.03, fz, lk(rgb(14, 14, 18), M.SmoothPlastic, { r = 0.12 }))
				K:plate("KMVFD", 1.6, 0.36, 0.04, fz * CF(-0.62, 0.08, 0), lk(rgb(6, 16, 18)))
				local _, vfd = K:text("KMVFDText", 1.5, 0.3, fz * CF(-0.62, 0.08, 0.045), "♪ READY", { fg = rgb(90, 255, 230), glow = 1.8, font = F.Arcade, d = 0.005 })
				st.vfd = vfd
				for k = 0, 5 do
					K:plate("KMLevel", 0.18, 0.06, 0.04, fz * CF(-1.32 + k * 0.22, -0.22, 0), neon(if k < 4 then NEONS.green elseif k < 5 then NEONS.yellow else NEONS.red))
				end
				for row = 0, 1 do
					for col = 0, 3 do
						K:plate("KMButton", 0.18, 0.1, 0.05, fz * CF(0.42 + col * 0.24, 0.12 - row * 0.2, 0), lk(rgb(64, 64, 70)))
					end
				end
				K:text("KMButtonLabel", 1.0, 0.07, fz * CF(0.78, 0.25, 0.04), "예약  취소  반주  템포", { fg = rgb(170, 170, 178), font = F.GothamBold, d = 0.005 })
				wdisc(K, "KMKnob", 0.3, 0.06, fz * CF(1.5, 0.0, 0.03), lk(rgb(190, 190, 196), M.Metal))
				K:text("KMBrand", 0.9, 0.08, fz * CF(-0.62, 0.32, 0.04), "GW MEDIA  G-9000", { fg = rgb(200, 200, 208), font = F.GothamBlack, d = 0.005 })
				K:plate("KMPower", 0.06, 0.06, 0.05, fz * CF(1.5, 0.3, 0), Look.ledBlue)
				hideRec(K, km)
				hideRec(K, first("MachineDisplay"))
				for _, r in all("MachineLED") do
					hideRec(K, r)
				end
			end
			-- 마이크 충전 거치대 (+ 꽂힌 마이크 2)
			local dock = first("MicDock")
			if dock then
				local mn, mx = dock.min, dock.max
				local c = (mn + mx) / 2
				K:rbox("MicCradle", V3(mx.X - mn.X + 0.04, 0.26, mx.Z - mn.Z + 0.04), 0.08, CF(c.X, mn.Y + 0.13, c.Z), lk(rgb(26, 26, 30), M.SmoothPlastic, { r = 0.05 }))
				for k, dz in { -0.24, 0.24 } do
					local y = mn.Y + 0.36
					local a = V3(mx.X - 0.08, y, c.Z + dz)
					local b = V3(mn.X + 0.22, y + 0.06, c.Z + dz)
					K:box("MicCradleSlot", V3(mx.X - mn.X - 0.1, 0.06, 0.34), CF(c.X, mn.Y + 0.27, c.Z + dz), lk(rgb(40, 40, 46)))
					handMic(K, a, b, lk(if k == 1 then rgb(30, 30, 34) else rgb(232, 232, 236), M.SmoothPlastic, { r = 0.05 }), theme, nil)
					K:plate("MicCradleLED", 0.05, 0.05, 0.03, faceCF(V3(mx.X - 0.12 - k * 0.12, mn.Y + 0.14, mx.Z + 0.02), V3(0, 0, 1)), Look.ledGreen)
				end
				K:text("MicCradleLabel", 0.7, 0.07, faceCF(V3(c.X, mn.Y + 0.06, mx.Z + 0.025), V3(0, 0, 1)), "CH1 · 충전 · CH2", { fg = rgb(170, 170, 178), font = F.GothamBold, d = 0.005 })
				hideRec(K, dock)
			end
		end)
	end)

	-- 6) 스피커 · 우퍼 · 마이크 스탠드 · 미러볼 모터 · 레이저 브래킷 ---------------------------------------------
	step(K, "speakers", function()
		for _, r in all("FloorSpeaker") do
			columnSpeaker(K, r, theme, st.leds)
			hideRec(K, r)
		end
		for _, nm in { "Woofer", "Tweeter" } do
			for _, r in all(nm) do
				hideRec(K, r)
			end
		end
		for _, r in all("Speaker") do
			wallSpeaker(K, r)
			hideRec(K, r)
		end
		for _, r in all("SpeakerCone") do
			hideRec(K, r)
		end
		local sub = first("Subwoofer")
		if sub then
			subwoofer(K, sub, nil, st.leds)
			hideRec(K, sub)
			hideRec(K, first("SubCone"))
		end
		-- 스피커 케이블 (바닥 · 벽 몰딩) + 전원 콘센트
		K:free(function()
			local cab = first("MachineCabinet")
			for _, r in all("FloorSpeaker") do
				if cab then
					local sx = if r.c.X < 0 then -1 else 1
					local a = V3(r.c.X - sx * 0.2, 0.05, r.min.Z + 0.25)
					local b = V3((if sx < 0 then cab.min.X else cab.max.X) - sx * 0.05, 0.05, r.min.Z + 0.25)
					K:seg("SpeakerCable", a, b, 0.07, lk(rgb(10, 10, 12), M.Rubber))
				end
			end
			if cab then
				local x = cab.min.X - 0.6
				local zw = zBack + 0.01
				K:plate("CableRaceway", 0.22, 3.2, 0.1, faceCF(V3(x, cab.max.Y + 1.6 - 1.4, zw), V3(0, 0, 1)), lk(rgb(24, 24, 28)))
				Props.outlet(K, faceCF(V3(x - 0.6, 1.2, zw), V3(0, 0, 1)))
			end
		end)
		-- 마이크 스탠드
		local mb = first("MicBase")
		local mh = first("MicHead")
		if mb then
			K:free(function()
				local c = V3(mb.c.X, 0, mb.c.Z)
				local topY = 5.05
				K:disc("MicStandBase", mb.size.X, 0.1, CF(c + V3(0, 0.05, 0)), lk(rgb(26, 26, 30), M.Metal))
				K:disc("MicStandRubber", mb.size.X + 0.04, 0.03, CF(c + V3(0, 0.015, 0)), RUBBER)
				K:vcyl("MicStandTube", 3.0, 0.2, CF(c + V3(0, 1.6, 0)), lk(rgb(30, 30, 34), M.Metal))
				K:vcyl("MicStandClutch", 0.26, 0.3, CF(c + V3(0, 3.12, 0)), CHROME)
				K:vcyl("MicStandRod", topY - 3.2, 0.12, CF(c + V3(0, 3.2 + (topY - 3.2) / 2, 0)), CHROME)
				if mh then
					local tip = V3(c.X, topY, c.Z)
					local head = mh.c
					local dir = (head - tip).Unit
					K:seg("MicClip", tip, tip + dir * 0.3, 0.12, lk(rgb(30, 30, 34)))
					handMic(K, tip + dir * 0.2, head - dir * 0.1, lk(rgb(40, 40, 46), M.Metal), theme, nil)
				end
			end)
			for _, nm in { "MicBase", "MicPole", "Mic", "MicHead" } do
				hideRec(K, first(nm))
			end
		end
		local rod = first("MirrorBallRod")
		if rod then
			K:free(function()
				K:disc("MirrorBallCanopy", 0.7, 0.06, CF(rod.c.X, H - 0.03, rod.c.Z), lk(rgb(30, 30, 34), M.Metal))
				K:box("MirrorBallMotor", V3(0.4, 0.3, 0.4), CF(rod.c.X, H - 0.21, rod.c.Z), lk(rgb(24, 24, 28), M.Metal))
				K:plate("MirrorBallMotorLED", 0.06, 0.06, 0.02, faceCF(V3(rod.c.X, H - 0.21, rod.c.Z + 0.2), V3(0, 0, 1)), Look.ledRed)
			end)
		end
		local las = first("LaserProjector")
		if las then
			K:free(function()
				for _, sx in { -1, 1 } do
					K:box("LaserBracket", V3(0.05, H - las.c.Y + 0.1, 0.5), CF(las.c.X + sx * (las.size.X / 2 + 0.03), (H + las.c.Y) / 2, las.c.Z), DARKALU)
				end
				K:box("LaserBracketTop", V3(las.size.X + 0.16, 0.05, 0.5), CF(las.c.X, H - 0.025, las.c.Z), DARKALU)
			end)
		end
	end)

	-- 7) 벽 (옆벽 두 면 · 복도 쪽 벽) -----------------------------------------------------------------------
	local function sideCF(sd: number, z: number, y: number, off: number): CFrame
		local x = if sd < 0 then x0 + off else x1 - off
		return faceCF(V3(x, y, z), V3(-sd, 0, 0))
	end
	-- 옆벽 판: z 범위 a..b (a<b), 높이 y0..y1, 두께 d, 벽에서 off
	local function sidePlate(name: string, sd: number, a: number, b: number, y0: number, y1: number, d: number, off: number, look: any): BasePart
		-- dcf +X = 보는 사람 오른쪽 (왼벽: -Z, 오른벽: +Z) 이므로 폭 방향은 z
		return K:plate(name, b - a, y1 - y0, d, sideCF(sd, (a + b) / 2, (y0 + y1) / 2, off), look)
	end
	step(K, "walls", function()
		for _, r in all("AcousticPanel") do
			hideRec(K, r)
		end
		for _, r in all("AcousticTile") do
			hideRec(K, r)
		end
		-- 소파 등받이 범위 (각 옆벽)
		local backs = { [-1] = {}, [1] = {} }
		for _, g in sofaGroups(V, mine) do
			if g.back then
				local b = g.back
				if b.max.X - b.min.X < b.max.Z - b.min.Z then
					local sd = if b.c.X < 0 then -1 else 1
					table.insert(backs[sd], { a = b.min.Z, b = b.max.Z, top = b.max.Y })
				end
			end
		end
		local sign = nil
		for _, r in V.parts do
			if string.sub(r.name, 1, 5) == "Sign_" and mine(r) and r.size.Y > 2 then
				sign = r
			end
		end
		local zA, zB = zBack + 0.02, zFront - 0.02
		local spkZ = zBack + 1.25 -- 천장 스피커 앞면 (디퓨저는 그 앞부터)
		for _, sp in all("Speaker") do
			spkZ = math.max(spkZ, sp.max.Z + 0.1)
		end
		K:free(function()
			for _, sd in { -1, 1 } do
				-- 바탕 벽지 + 아래 걸레받이 + 위 블랙 띠
				sidePlate("BoothWallpaper", sd, zA, zB, 0.02, H - 0.02, 0.02, 0.0, wallTone)
				sidePlate("BoothKick", sd, zA, zB, 0.02, 0.4, 0.05, 0.02, GLOSS)
				sidePlate("BoothTopBand", sd, zA, zB, H - 0.95, H - 0.4, 0.05, 0.02, GLOSS)
				local band = sidePlate("BoothTopBandLED", sd, zA + 0.2, zB - 0.2, H - 0.69, H - 0.65, 0.07, 0.02, neon(theme))
				table.insert(st.leds, { p = band, c = theme })
				-- 소파 위 선반 (음료 받침) + 업라이트
				for _, bk in backs[sd] do
					local ly = bk.top + 0.02
					local shelf = K:box("WallLedge", V3(0.6, 0.12, bk.b - bk.a), CF(if sd < 0 then x0 + 0.3 else x1 - 0.3, ly + 0.06, (bk.a + bk.b) / 2), Look.walnut)
					local _ = shelf
					K:box("WallLedgeEdge", V3(0.03, 0.12, bk.b - bk.a), CF(if sd < 0 then x0 + 0.615 else x1 - 0.615, ly + 0.06, (bk.a + bk.b) / 2), CHROME)
					local led = K:box("WallLedgeLED", V3(0.05, 0.04, bk.b - bk.a - 0.3), CF(if sd < 0 then x0 + 0.08 else x1 - 0.08, ly + 0.14, (bk.a + bk.b) / 2), neon(theme))
					table.insert(st.leds, { p = led, c = theme })
					addLight(K, st, led, "SurfaceLight", { Face = Enum.NormalId.Top, Range = 7, Brightness = 0.5, Angle = 120, Color = theme })
				end
				-- 디퓨저 (TV 쪽: 천장 스피커 앞 ~ 소파 앞)
				local da = spkZ
				local db = -4.75
				for _, bk in backs[sd] do
					db = math.min(db, bk.a - 0.1)
				end
				if db - da > 1.6 then
					local y0, y1 = 5.75, H - 1.2
					local n = math.floor((db - da - 0.16) / 0.42)
					local seq = { 0, 1, 4, 2, 2, 4, 1 }
					local cw = (db - da - 0.16) / n
					for i = 1, n do
						local z = da + 0.08 + cw * (i - 0.5)
						local dep = 0.08 + seq[(i - 1) % #seq + 1] * 0.07
						sidePlate("DiffuserWell", sd, z - cw / 2 + 0.02, z + cw / 2 - 0.02, y0 + 0.08, y1 - 0.08, dep, 0.02, if i % 2 == 0 then Look.walnut else Look.oak)
						if i < n then
							sidePlate("DiffuserFin", sd, z + cw / 2 - 0.02, z + cw / 2 + 0.02, y0 + 0.08, y1 - 0.08, 0.42, 0.02, lk(rgb(30, 22, 18), M.Wood))
						end
					end
					sidePlate("DiffuserFrame", sd, da, db, y1 - 0.08, y1, 0.46, 0.02, LACQ)
					sidePlate("DiffuserFrame", sd, da, db, y0, y0 + 0.08, 0.46, 0.02, LACQ)
					sidePlate("DiffuserFrame", sd, da, da + 0.08, y0, y1, 0.46, 0.02, LACQ)
					sidePlate("DiffuserFrame", sd, db - 0.08, db, y0, y1, 0.46, 0.02, LACQ)
				end
				-- 소파 위 채널 패딩 벽 (간판 자리는 비움)
				for _, bk in backs[sd] do
					local segs = { { bk.a + 0.1, bk.b - 0.1 } }
					if sign and ((sign.c.X < 0) == (sd < 0)) then
						local cut = { sign.min.Z - 0.25, sign.max.Z + 0.25 }
						local nxt = {}
						for _, s in segs do
							if cut[2] <= s[1] or cut[1] >= s[2] then
								table.insert(nxt, s)
							else
								if cut[1] - s[1] > 1.0 then
									table.insert(nxt, { s[1], cut[1] })
								end
								if s[2] - cut[2] > 1.0 then
									table.insert(nxt, { cut[2], s[2] })
								end
							end
						end
						segs = nxt
						-- 간판 테두리 LED
						local fr = sidePlate("SignFrameLED", sd, sign.min.Z - 0.12, sign.max.Z + 0.12, sign.min.Y - 0.12, sign.max.Y + 0.12, 0.03, 0.0, neon(theme))
						table.insert(st.leds, { p = fr, c = theme })
					end
					local y0 = bk.top + 0.45
					local y1 = H - 1.25
					for _, s in segs do
						local len = s[2] - s[1]
						local pitch = 0.58
						local n = math.max(2, math.floor(len / pitch))
						local pw = len / n
						sidePlate("ChannelBack", sd, s[1], s[2], y0, y1, 0.04, 0.02, lk(dk(fabric, 0.45), M.Fabric))
						for i = 1, n do
							local z = s[1] + pw * (i - 0.5)
							local x = if sd < 0 then x0 + 0.06 else x1 - 0.06
							K:vcyl("ChannelTuft", y1 - y0 - 0.16, pw * 0.98, CF(x, (y0 + y1) / 2, z), panelTone)
						end
						sidePlate("ChannelFrame", sd, s[1] - 0.06, s[2] + 0.06, y1, y1 + 0.08, 0.36, 0.02, CHROME)
						sidePlate("ChannelFrame", sd, s[1] - 0.06, s[2] + 0.06, y0 - 0.08, y0, 0.36, 0.02, CHROME)
					end
				end
			end
		end)
	end)

	-- 8) 복도 쪽 벽 (안쪽 면): 문틀 · 조명 패널 · 코인기 · 에어컨 리모컨 · 터치 선곡 패널 · 에어컨 · 안내문 · 비상구 --------------
	step(K, "frontwall", function()
		local fz = zFront
		local n = V3(0, 0, -1)
		local function fcf(x: number, y: number, off: number): CFrame
			return faceCF(V3(x, y, fz - off), n)
		end
		-- 문 구멍: CorridorWall 들 사이 (로컬 x)
		local walls = {}
		for _, r in V.byName.CorridorWall or {} do
			if math.abs(r.c.Z - (V.z1 + 0.15)) < 0.8 then
				table.insert(walls, r)
			end
		end
		local dx0, dx1 = 0.5, 5.5
		local lin = nil
		for _, r in V.byName.CorridorWallLintel or {} do
			if math.abs(r.c.Z - (V.z1 + 0.15)) < 0.8 then
				lin = r
			end
		end
		if lin then
			dx0, dx1 = lin.min.X, lin.max.X
		end
		local doorTop = if lin then lin.min.Y else 8.55
		local ledgeTop = 4.2
		for _, g in sofaGroups(V, mine) do
			if g.back and g.back.max.X - g.back.min.X > g.back.max.Z - g.back.min.Z then
				ledgeTop = g.back.max.Y + 0.05
			end
		end
		K:free(function()
			-- 벽지 (소파 위) + 위 블랙 띠
			K:plate("FrontWallpaper", dx0 - x0 - 0.04, H - ledgeTop - 0.04, 0.02, fcf((x0 + dx0) / 2, (ledgeTop + H) / 2, 0), wallTone)
			K:plate("FrontLintelPaper", dx1 - dx0, H - doorTop - 0.04, 0.02, fcf((dx0 + dx1) / 2, (doorTop + H) / 2, 0), wallTone)
			K:plate("FrontTopBand", x1 - x0 - 0.06, 0.55, 0.05, fcf((x0 + x1) / 2, H - 0.675, 0.02), GLOSS)
			local band = K:plate("FrontTopBandLED", x1 - x0 - 0.4, 0.04, 0.07, fcf((x0 + x1) / 2, H - 0.67, 0.02), neon(theme))
			table.insert(st.leds, { p = band, c = theme })
			-- 소파 위 선반
			for _, g in sofaGroups(V, mine) do
				local b = g.back
				if b and b.max.X - b.min.X > b.max.Z - b.min.Z then
					K:box("WallLedge", V3(b.max.X - b.min.X, 0.12, 0.6), CF(b.c.X, b.max.Y + 0.08, fz - 0.3), Look.walnut)
					K:box("WallLedgeEdge", V3(b.max.X - b.min.X, 0.12, 0.03), CF(b.c.X, b.max.Y + 0.08, fz - 0.615), CHROME)
					local led = K:box("WallLedgeLED", V3(b.max.X - b.min.X - 0.3, 0.04, 0.05), CF(b.c.X, b.max.Y + 0.16, fz - 0.08), neon(theme))
					table.insert(st.leds, { p = led, c = theme })
				end
			end
			-- 문틀 (안쪽 면 케이싱)
			local casing = lk(rgb(30, 30, 34), M.Metal)
			K:plate("DoorCasing", 0.24, doorTop + 0.2, 0.1, fcf(dx1 + 0.1, (doorTop + 0.2) / 2, 0.0), casing)
			K:plate("DoorCasing", 0.24, doorTop + 0.2, 0.1, fcf(dx0 - 0.1, (doorTop + 0.2) / 2, 0.0), casing)
			K:plate("DoorCasing", dx1 - dx0 + 0.44, 0.22, 0.1, fcf((dx0 + dx1) / 2, doorTop + 0.09, 0.0), casing)
			K:plate("DoorCasingLine", 0.03, doorTop, 0.11, fcf(dx1 - 0.0, doorTop / 2, 0.0), CHROME)
			K:plate("DoorCasingLine", 0.03, doorTop, 0.11, fcf(dx0 + 0.0, doorTop / 2, 0.0), CHROME)
			-- 유도등 (비상구) + 비상조명등
			local exitY = doorTop + 0.75
			K:plate("ExitSignBox", 1.3, 0.55, 0.16, fcf((dx0 + dx1) / 2, exitY, 0.0), lk(rgb(240, 244, 240)))
			K:text("ExitSign", 1.2, 0.45, fcf((dx0 + dx1) / 2, exitY, 0.165), "← 비상구 EXIT", { fg = WHITE, bg = rgb(20, 170, 80), glow = 1.6, font = F.GothamBlack, d = 0.01 })
			local ex = math.min(dx1 - 0.6, (dx0 + dx1) / 2 + 1.75)
			K:plate("EmergencyLight", 1.0, 0.36, 0.22, fcf(ex, exitY + 0.05, 0.0), lk(rgb(240, 240, 236)))
			for _, sx in { -1, 1 } do
				wdisc(K, "EmergencyLamp", 0.22, 0.12, fcf(ex + sx * 0.3, exitY, 0.22), lk(rgb(255, 250, 230), M.Glass, { t = 0.2 }))
			end
			K:plate("EmergencyLightLED", 0.06, 0.06, 0.24, fcf(ex, exitY + 0.15, 0.0), Look.ledGreen)
		end)

		-- 조명 패널 (문 바로 왼쪽): 4 버튼
		local px = dx0 - 0.55
		local panel: BasePart? = nil
		K:free(function()
			panel = K:plate("LightPanel", 0.6, 1.0, 0.06, fcf(px, 5.0, 0.0), lk(rgb(20, 20, 24), M.SmoothPlastic, { r = 0.1 }))
			K:text("LightPanelTitle", 0.5, 0.12, fcf(px, 5.4, 0.065), "조명", { fg = rgb(220, 220, 230), font = F.GothamBold, d = 0.005 })
			local cols = { theme, WARM, NEONS.pink, rgb(120, 120, 130) }
			for i = 1, 4 do
				local b = K:plate("LightPanelKey", 0.42, 0.14, 0.05, fcf(px, 5.2 - i * 0.19, 0.06), lk(cols[i]))
				table.insert(st.buttons, b)
				K:text("LightPanelKeyText", 0.4, 0.11, fcf(px, 5.2 - i * 0.19, 0.115), MODES[i], { fg = WHITE, font = F.GothamBold, d = 0.004 })
			end
		end)
		-- 코인기 (동전 · 지폐 투입 + 남은 시간): 밖의 KaraokePanel 바로 뒤
		local cx = px - 1.4
		local coinLabel: TextLabel? = nil
		K:free(function()
			local d0 = fcf(cx, 5.55, 0.0)
			K:rbox("CoinBox", V3(0.5, 2.0, 1.2), 0.08, d0 * CF(0, 0, 0.25) * ANG(0, PI / 2, 0), lk(rgb(70, 74, 82), M.Metal))
			local fc = d0 * CF(0, 0, 0.5)
			K:plate("CoinBoxHeader", 1.1, 0.26, 0.02, fc * CF(0, 0.82, 0), lk(dk(theme, 0.2)))
			K:text("CoinBoxHeaderText", 1.0, 0.2, fc * CF(0, 0.82, 0.025), "COIN · BILL", { fg = WHITE, font = F.GothamBlack, d = 0.004 })
			K:plate("CoinBoxLCD", 0.9, 0.46, 0.02, fc * CF(0, 0.38, 0), lk(rgb(10, 4, 4)))
			local _, lab = K:text("CoinBoxLCDText", 0.84, 0.4, fc * CF(0, 0.38, 0.025), "500원 · 30분\n동전 · 지폐", { fg = rgb(255, 70, 50), glow = 1.6, font = F.Arcade, d = 0.004 })
			coinLabel = lab
			K:plate("CoinSlot", 0.24, 0.3, 0.03, fc * CF(-0.28, -0.06, 0), CHROME)
			K:plate("CoinSlotHole", 0.04, 0.2, 0.035, fc * CF(-0.28, -0.06, 0), lk(rgb(4, 4, 4)))
			K:plate("BillSlotBezel", 0.62, 0.14, 0.03, fc * CF(0.12, -0.32, 0), lk(rgb(30, 30, 34)))
			local bill = K:plate("BillSlotLED", 0.52, 0.04, 0.035, fc * CF(0.12, -0.32, 0), Look.ledGreen)
			st.billLED = bill
			wdisc(K, "CoinReturnBtn", 0.18, 0.05, fc * CF(0.3, -0.06, 0), lk(rgb(220, 40, 40)))
			K:plate("CoinCup", 0.6, 0.22, 0.12, fc * CF(0, -0.78, 0), lk(rgb(40, 40, 44), M.Metal))
			K:text("CoinBoxSticker", 1.0, 0.12, fc * CF(0, -0.56, 0.01), "500원 동전 · 1,000원 지폐", { fg = rgb(230, 230, 236), font = F.GothamBold, d = 0.004 })
		end)
		st.coinLabel = coinLabel
		-- 에어컨 리모컨 (상호작용) · 터치 선곡 패널
		local ax = cx - 1.45
		local acCtl: BasePart? = nil
		local acLabel: TextLabel? = nil
		K:free(function()
			acCtl = K:plate("ACControl", 0.62, 0.62, 0.07, fcf(ax, 5.0, 0.0), lk(rgb(240, 240, 236)))
			K:plate("ACControlLCD", 0.46, 0.26, 0.02, fcf(ax, 5.1, 0.07), lk(rgb(150, 200, 210)))
			local _, l = K:text("ACControlText", 0.44, 0.22, fcf(ax, 5.1, 0.095), "OFF", { fg = rgb(20, 30, 40), font = F.GothamBold, d = 0.004 })
			acLabel = l
			wdisc(K, "ACControlBtn", 0.14, 0.04, fcf(ax, 4.82, 0.07), lk(rgb(60, 140, 230)))
			-- 터치 선곡 패널 (태블릿 + 벽 거치대)
			local tx = ax - 1.55
			K:plate("TabletMount", 0.5, 0.5, 0.12, fcf(tx, 5.4, 0.0), DARKALU)
			K:plate("TabletBody", 1.7, 1.1, 0.08, fcf(tx, 5.4, 0.12), lk(rgb(16, 16, 20), M.SmoothPlastic, { r = 0.1 }))
			K:plate("TabletScreen", 1.56, 0.96, 0.02, fcf(tx, 5.4, 0.2), lk(rgb(20, 26, 50), M.Neon, { t = 0.55 }))
			K:text("TabletHeader", 1.5, 0.16, fcf(tx, 5.78, 0.225), "곡 검색 · 예약", { fg = WHITE, bg = dk(theme, 0.25), glow = 1.2, font = F.GothamBold, d = 0.004 })
			local list = {}
			for i = 1, 4 do
				local k = ((roomNo + i * 3) % #SONGS) + 1
				table.insert(list, string.format("%d  %s", songNo(k), SONGS[k]))
			end
			K:text("TabletList", 1.48, 0.66, fcf(tx, 5.32, 0.225), table.concat(list, "\n"), { fg = rgb(220, 230, 255), glow = 1.2, font = F.GothamMedium, align = "Left", d = 0.004 })
			-- 안내문 + 가방 고리
			local nx = ax + 0.3
			K:plate("NoticeFrame", 2.5, 1.36, 0.04, fcf(nx, 7.35, 0.0), CHROME)
			K:text("Notice", 2.4, 1.26, fcf(nx, 7.35, 0.045), "이용 안내\n· 30분 500원 · 사용 중 자동 연장\n· 음식물 OK · 주류 · 흡연 금지\n· 기물 파손 시 변상\n· 퇴실 시 마이크는 충전 거치대에", { fg = rgb(30, 30, 36), bg = rgb(250, 248, 242), font = F.GothamMedium, d = 0.01, align = "Left" })
			for k = 0, 1 do
				local hx = x0 + 0.5 + k * 0.55
				K:plate("BagHookPlate", 0.16, 0.3, 0.04, fcf(hx, 7.0, 0.0), CHROME)
				K:seg("BagHook", (fcf(hx, 7.05, 0.04)).Position, (fcf(hx, 6.85, 0.32)).Position, 0.07, CHROME)
				K:ball("BagHookTip", 0.1, fcf(hx, 6.92, 0.34), CHROME)
			end
		end)
		-- 벽걸이 에어컨 (루버가 열림)
		local acx = x0 + 1.75
		local louver: BasePart? = nil
		local louverCF: CFrame? = nil
		local acLED: BasePart? = nil
		K:free(function()
			local yb = H - 2.3
			local d0 = fcf(acx, yb + 0.55, 0.0)
			K:rbox("ACUnit", V3(0.72, 1.1, 3.2), 0.18, d0 * CF(0, 0, 0.36) * ANG(0, PI / 2, 0), lk(rgb(242, 242, 238)))
			K:plate("ACFrontLine", 3.0, 0.03, 0.73, d0 * CF(0, 0.18, 0), lk(rgb(210, 210, 206)))
			K:text("ACBrand", 0.8, 0.12, d0 * CF(-1.0, 0.32, 0.73), "INVERTER", { fg = rgb(150, 150, 156), font = F.GothamBold, d = 0.004 })
			acLED = K:plate("ACLED", 0.1, 0.06, 0.73, d0 * CF(1.2, 0.32, 0), lk(rgb(120, 120, 120)))
			K:plate("ACIntake", 2.8, 0.12, 0.735, d0 * CF(0, -0.42, 0.0), lk(rgb(60, 60, 64)))
			local lcf = d0 * CF(0, -0.53, 0.66)
			louverCF = lcf
			louver = K:box("ACLouver", V3(2.9, 0.06, 0.24), lcf, lk(rgb(236, 236, 232)))
			-- 배관 커버 (벽 따라 위로)
			K:plate("ACPipeCover", 0.3, H - yb - 1.1, 0.16, fcf(acx + 1.75, (yb + 1.1 + H) / 2, 0.0), lk(rgb(236, 236, 232)))
		end)
		-- 상호작용: 조명 모드 · 에어컨
		if panel then
			Interact.prompt(K, panel :: BasePart, {
				action = "조명: " .. MODES[2],
				object = "방 조명 모드",
				fn = function(_n, pr)
					st.mode = st.mode % #MODES + 1
					applyMode(st, os.clock())
					pr.ActionText = "조명: " .. MODES[st.mode % #MODES + 1]
				end,
			})
		end
		if acCtl then
			local on = false
			Interact.toggle(K, acCtl :: BasePart, {
				object = "벽걸이 에어컨",
				state = false,
				onText = "에어컨 끄기",
				offText = "에어컨 켜기",
				on = function(s: boolean)
					on = s
					if acLabel then
						acLabel.Text = if s then "냉방 22°C" else "OFF"
					end
					if acLED and acLED.Parent then
						acLED.Material = if s then M.Neon else M.SmoothPlastic
						acLED.Color = if s then rgb(60, 230, 120) else rgb(120, 120, 120)
					end
					if louver and louver.Parent and louverCF then
						local w = K.cf * (louverCF :: CFrame) * (if s then CF(0, -0.05, 0.05) * ANG(math.rad(-40), 0, 0) else CF())
						TweenService:Create(louver :: BasePart, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = w }):Play()
					end
				end,
			})
			local _ = on
		end
	end)

	-- 9) 문 (유리문: 같은 자리 열린 자세, 문 닫기/열기) -----------------------------------------------------------
	step(K, "door", function()
		local dr = first("BoothDoor")
		if not dr then
			return
		end
		local hingeZ = math.max(dr.max.Z, zFront - 0.12)
		local L = hingeZ - dr.min.Z
		local x = dr.c.X - 0.03
		local hcf = CF(x, 0, hingeZ) -- 문 프레임: 원점 = 경첩 아래, 문은 -Z 로 뻗음, 두께 = X
		local hgt = dr.max.Y
		local alu = lk(rgb(56, 58, 64), M.Metal)
		local m = K:group("BoothDoorLeaf", function()
			K:free(function()
				K:box("DoorStile", V3(0.16, hgt, 0.2), hcf * CF(0, hgt / 2, -0.1), alu)
				K:box("DoorStile", V3(0.16, hgt, 0.2), hcf * CF(0, hgt / 2, -L + 0.1), alu)
				K:box("DoorRail", V3(0.16, 0.3, L), hcf * CF(0, hgt - 0.15, -L / 2), alu)
				K:box("DoorRail", V3(0.16, 0.5, L), hcf * CF(0, 0.25, -L / 2), alu)
				K:box("DoorKickPlate", V3(0.18, 0.4, L - 0.4), hcf * CF(0, 0.26, -L / 2), Look.brushed)
				K:box("DoorGlass", V3(0.05, hgt - 0.8, L - 0.4), hcf * CF(0, 0.5 + (hgt - 0.8) / 2, -L / 2), lk(lt(dk(theme, 0.55), 0.1), M.Glass, { t = 0.55, r = 0.15 }))
				K:box("DoorFrost", V3(0.07, 1.0, L - 0.4), hcf * CF(0, 4.0, -L / 2), lk(rgb(236, 236, 240), M.Glass, { t = 0.25 }))
				for _, sx in { -1, 1 } do
					K:text("DoorFrostText", L - 0.8, 0.7, faceCF((hcf * V3(sx * 0.04, 4.0, -L / 2)), V3(sx, 0, 0)), string.format("%02d   ♪ COIN KARAOKE", roomNo), { fg = dk(theme, 0.35), font = F.GothamBlack, d = 0.004 })
					-- 레버 손잡이 (양면)
					K:disc("DoorLeverRose", 0.22, 0.05, hcf * CF(sx * 0.1, 3.8, -L + 0.35) * ANG(0, 0, PI / 2) * ANG(0, 0, 0), CHROME)
					K:box("DoorLever", V3(0.07, 0.07, 0.5), hcf * CF(sx * 0.16, 3.8, -L + 0.55), CHROME)
				end
				for k = 0, 2 do
					K:vcyl("DoorHinge", 0.4, 0.1, hcf * CF(-0.09, 0.8 + k * 3.2, -0.02), CHROME)
				end
				K:box("DoorSeal", V3(0.1, hgt - 0.1, 0.04), hcf * CF(0, hgt / 2, -L - 0.01), RUBBER)
				K:box("DoorCloser", V3(0.16, 0.24, 1.0), hcf * CF(-0.16, hgt - 0.32, -0.75), lk(rgb(150, 152, 158), M.Metal))
				K:box("DoorCloserArm", V3(0.05, 0.05, 0.9), hcf * CF(-0.2, hgt - 0.12, -0.6), lk(rgb(130, 132, 138), M.Metal))
				-- 가로 밀대 (프롬프트 자리: 테이블에서 6.5 이상)
				K:box("DoorPushHandle", V3(0.08, 0.08, L * 0.6), hcf * CF(-0.18, 3.1, -L / 2 + 0.2), CHROME)
				for _, f in { -1, 1 } do
					K:box("DoorPushPost", V3(0.12, 0.06, 0.06), hcf * CF(-0.12, 3.1, -L / 2 + 0.2 + f * L * 0.27), CHROME)
				end
			end)
		end)
		for _, nm in { "BoothDoor", "DoorEdge", "DoorHandle" } do
			for _, r in all(nm) do
				hideRec(K, r)
			end
		end
		local hingeW = (K.cf * hcf).Position
		Interact.swing(K, m, hingeW, K.cf.YVector, PI / 2 - 0.04, { object = "노래방 문", openText = "문 닫기", closeText = "문 열기", sound = "rbxasset://sounds/clickfast.wav" })
	end)

	-- 10) 천장: 별빛 · 핀스폿 · 파 조명 · 환기구 · 비상 (스프링클러 · 감지기는 Common) ----------------------------------
	step(K, "ceiling", function()
		K:free(function()
			-- 핀스폿 (미러볼 비춤)
			local ball = first("MirrorBall")
			if ball then
				local pos = V3(ball.c.X + 2.2, H - 0.25, ball.c.Z + 2.6)
				local dir = (ball.c - pos).Unit
				K:disc("PinspotMount", 0.4, 0.05, CF(pos.X, H - 0.025, pos.Z), DARKALU)
				Common.useCeil(K, pos.X, pos.Z)
				local can = K:cyl("PinspotCan", 0.55, 0.32, CFrame.lookAt(pos, pos + dir) * ANG(0, PI / 2, 0), lk(rgb(24, 24, 28), M.Metal))
				K:disc("PinspotLens", 0.24, 0.02, CFrame.lookAt(pos + dir * 0.28, pos + dir) * ANG(PI / 2, 0, 0), Look.lampNeutral)
				addLight(K, st, can, "SpotLight", { Face = Enum.NormalId.Right, Range = 9, Brightness = 2.2, Angle = 16, Color = rgb(255, 250, 240) })
			end
			-- 파 조명 2 (TV 쪽 천장 모서리, 소파를 향함)
			for k, sx in { -1, 1 } do
				local pos = V3(sx * (x1 - 1.6), H - 0.45, zBack + 2.2)
				local aim = V3(sx * -1.2, 1.2, 1.5)
				local dir = (aim - pos).Unit
				K:box("ParYoke", V3(0.6, 0.06, 0.12), CF(pos.X, H - 0.03, pos.Z), DARKALU)
				Common.useCeil(K, pos.X, pos.Z)
				K:bar("ParYokeArm", V3(pos.X - 0.28, H - 0.05, pos.Z), V3(pos.X - 0.28, pos.Y, pos.Z), 0.05, 0.05, DARKALU)
				K:bar("ParYokeArm", V3(pos.X + 0.28, H - 0.05, pos.Z), V3(pos.X + 0.28, pos.Y, pos.Z), 0.05, 0.05, DARKALU)
				local can = K:cyl("ParCan", 0.6, 0.44, CFrame.lookAt(pos, pos + dir) * ANG(0, PI / 2, 0), lk(rgb(20, 20, 24), M.Metal))
				local lens = K:disc("ParLensLED", 0.36, 0.02, CFrame.lookAt(pos + dir * 0.31, pos + dir) * ANG(PI / 2, 0, 0), neon(if k == 1 then theme else NEONS.pink))
				table.insert(st.leds, { p = lens, c = if k == 1 then theme else NEONS.pink })
				if k == 1 then
					addLight(K, st, can, "SpotLight", { Face = Enum.NormalId.Right, Range = 14, Brightness = 1.4, Angle = 40, Color = theme }, true)
				end
			end
			-- 환기구 (정사각 디퓨저)
			local vx, vz = x0 + 2.4, zFront - 3.2
			if Common.ceilFree(K, vx, vz, 0.8) then
				K:box("CeilingVent", V3(1.3, 0.04, 1.3), CF(vx, H - 0.02, vz), lk(rgb(220, 220, 216)))
				for k = 1, 3 do
					local s = 1.3 - k * 0.3
					K:box("CeilingVentRing", V3(s, 0.05, s), CF(vx, H - 0.03, vz), lk(if k % 2 == 1 then rgb(150, 150, 150) else rgb(220, 220, 216)))
				end
				Common.useCeil(K, vx, vz)
			end
			-- 별빛 (광섬유 점)
			local nStars = if hi(K) then 46 elseif lo(K) then 0 else 24
			local seed = roomNo * 17 + 3
			local placed = 0
			for i = 1, nStars * 3 do
				if placed >= nStars then
					break
				end
				local x = x0 + 0.9 + rnd(seed, i) * (x1 - x0 - 1.8)
				local z = zBack + 1.6 + rnd(seed + 7, i) * (zFront - zBack - 2.6)
				if Common.ceilFree(K, x, z, 0.3) then
					local s = 0.05 + rnd(seed + 11, i) * 0.05
					local p = K:disc("StarDot", s, 0.02, CF(x, H - 0.01, z), neon(if i % 5 == 0 then rgb(180, 210, 255) else rgb(255, 250, 236)))
					table.insert(st.stars, p)
					placed += 1
				end
			end
		end)
	end)

	-- 11) 바닥: 카펫 무늬 테두리 + 입구 매트 -------------------------------------------------------------------
	step(K, "floor", function()
		local tt = first("TableTop")
		K:free(function()
			if tt then
				local cx, cz = (tt.min.X + tt.max.X) / 2, (tt.min.Z + tt.max.Z) / 2
				local hw, hl = (tt.max.X - tt.min.X) / 2 + 0.45, (tt.max.Z - tt.min.Z) / 2 + 0.55
				local lineL = lk(dk(theme, 0.45), M.Fabric)
				for _, sx in { -1, 1 } do
					K:box("CarpetLine", V3(0.12, 0.02, hl * 2), CF(cx + sx * hw, 0.03, cz), lineL)
					K:box("CarpetLine", V3(hw * 2 + 0.12, 0.02, 0.12), CF(cx, 0.03, cz + sx * hl), lineL)
				end
			end
			-- TV 앞 줄무늬 (무대 자리)
			local cab = first("MachineCabinet")
			if cab then
				for k = 0, 2 do
					K:box("CarpetStage", V3(cab.max.X - cab.min.X + 1.4, 0.02, 0.1), CF((cab.min.X + cab.max.X) / 2, 0.03, cab.max.Z + 0.45 + k * 0.4), lk(dk(theme, 0.35 + k * 0.1), M.Fabric))
				end
			end
			-- 입구 매트
			K:box("DoorMatBooth", V3(3.4, 0.03, 1.4), CF(3.0, 0.025, zFront - 1.0), lk(rgb(30, 30, 34), M.Fabric))
			K:text("DoorMatBoothText", 2.6, 0.9, topCF(V3(3.0, 0.042, zFront - 1.0), V3(0, 0, -1)), "♪ WELCOME", { fg = dk(theme, 0.2), font = F.GothamBlack, d = 0.004, free = true })
		end)
	end)

	-- 12) 피난안내도 · 거울 (왼벽 복도 쪽) ---------------------------------------------------------------------
	step(K, "evac", function()
		local sd = -1
		local zc = zFront - 1.8
		K:free(function()
			local m0 = sideCF(sd, zc, 6.0, 0.02)
			K:plate("MirrorFrame", 2.5, 2.3, 0.05, m0, CHROME)
			K:plate("Mirror", 2.38, 2.18, 0.06, m0, Look.mirror)
			local e0 = sideCF(sd, zc, 8.3, 0.02)
			K:plate("EvacMapFrame", 2.0, 1.4, 0.05, e0, Look.goldMetal)
			K:text("EvacMap", 1.88, 1.28, e0 * CF(0, 0, 0.055), "피난안내도\n[현위치] ROOM " .. string.format("%02d", roomNo) .. "\n→ 복도 → 비상구 / 로비 출입구\n소화기 · 유도등 위치 표시", { fg = rgb(20, 120, 60), bg = rgb(250, 250, 246), font = F.GothamBold, d = 0.01 })
		end)
	end)

	-- 13) 실시간 표시 + 조명 모드 애니메이션 ------------------------------------------------------------------
	applyMode(st, 0)
	local lastTxt = ""
	local lastVfd = ""
	Interact.anim(K, function(t: number)
		if st.mode == 3 then
			applyMode(st, t)
		end
		local busy = rented(booth)
		if st.coinLabel and st.coinLabel.Parent then
			local txt
			if busy then
				local pu = attr(booth, "KPaidUntil")
				local left = if type(pu) == "number" then math.max(0, pu - serverNow()) else 0
				-- 30초 = 게임 30분
				txt = string.format("남은 시간\n%d분", math.floor(left + 0.5))
			else
				txt = "500원 · 30분\n동전 · 지폐"
			end
			if txt ~= lastTxt then
				st.coinLabel.Text = txt
				lastTxt = txt
			end
		end
		if st.billLED and st.billLED.Parent then
			st.billLED.Transparency = if (not busy) and (math.floor(t * 2) % 2 == 0) then 0.6 else 0
		end
		if st.vfd and st.vfd.Parent then
			local id = attr(booth, "KSong")
			local v = "♪ READY"
			if type(id) == "string" and id ~= "" then
				local i = tonumber(string.match(id, "%d+"))
				if i then
					v = string.format("%d", songNo(i))
				end
			elseif busy then
				v = "선곡 대기"
			end
			if v ~= lastVfd then
				st.vfd.Text = v
				lastVfd = v
			end
		end
	end)
end

-- =====================================================================================================
-- 스타일 · 진입
-- =====================================================================================================
local function fixKeeps(V: any)
	if V.type == "kbooth" then
		-- 부스: 복도 쪽 벽을 '앞 유리'로 본 keep, 가운데로 추측한 문 keep 을 실제 문 자리로 바꿈
		local keep = {}
		for _, k in V.keep do
			if k.kind ~= "window" and k.kind ~= "door" then
				table.insert(keep, k)
			end
		end
		V.keep = keep
		local lin = nil
		for _, r in V.byName.CorridorWallLintel or {} do
			if math.abs(r.c.Z - (V.z1 + 0.15)) < 0.8 then
				lin = r
			end
		end
		local a, b = 0.5, 5.5
		if lin then
			a, b = lin.min.X, lin.max.X
		end
		V:addKeep(V3(a - 0.1, 0.1, V.z1 - 4.9), V3(b + 0.1, 8.6, V.z1 + 0.6), "door")
		V.door = { x = (a + b) / 2, z = V.z1, w = b - a, min = V3(a, 0, V.z1 - 0.2), max = V3(b, 8.6, V.z1 + 0.2) }
	elseif V.type == "kcorridor" then
		local keep = {}
		for _, k in V.keep do
			if k.kind ~= "window" then
				table.insert(keep, k)
			end
		end
		V.keep = keep
		-- 복도 바닥 전체 = 통로 (벽에서 0.9 안쪽)
		V:addKeep(V3(V.x0 + 0.9, 0.1, V.z0), V3(V.x1 - 0.9, 7.2, V.z1), "lane")
	elseif V.type == "karaoke" then
		-- 로비 동선 (입구 -> 복도 아치 · 카운터 · 교환기 · 자판기)
		local function lane(ax: number, az: number, bx: number, bz: number, w: number)
			local a, b = V3(ax, 0, az), V3(bx, 0, bz)
			local n = math.max(1, math.ceil((b - a).Magnitude / 1.5))
			for i = 0, n do
				local p = a:Lerp(b, i / n)
				V:addKeep(V3(p.X - w / 2, 0.1, p.Z - w / 2), V3(p.X + w / 2, 6.5, p.Z + w / 2), "lane")
			end
		end
		local d = V.door or { x = 11.7, z = V.z1 }
		lane(d.x, V.z1 - 3.5, 0, V.z0 + 1.6, 3.6)
		lane(d.x, V.z1 - 3.5, -12, -0.6, 3.0)
		lane(d.x, V.z1 - 3.5, V.x1 - 4.0, 7.8, 3.0)
		lane(V.x1 - 4.0, 7.8, V.x1 - 4.0, -6.8, 3.0)
		lane(0, V.z0 + 1.6, -8, -0.8, 3.0)
	end
end

function T.style(V: any): any
	local ok, err = pcall(fixKeeps, V)
	if not ok then
		warn("[T_karaoke] keep fix: " .. tostring(err))
	end
	local cy = ceilingY(V)
	if V.type == "kbooth" or V.type == "kcorridor" then
		cy = math.max(cy, V.H + 0.05)
	end
	local S: any = {
		chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false,
		clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" },
		skip = { upgrades = V.type ~= "karaoke", fixtures = true, floor = true, walls = true },
		ceilY = cy,
	}
	-- 스프링클러 · 감지기가 실제 천장에 붙게
	V.H = cy
	return S
end

function T.build(K: any, V: any, S: any)
	if V.type == "kbooth" then
		boothBuild(K, V, S)
	elseif V.type == "kcorridor" then
		if T.corridor then
			T.corridor(K, V, S)
		end
	else
		if T.lobby then
			T.lobby(K, V, S)
		end
	end
end

return T
