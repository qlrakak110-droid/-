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
local SMOKYMIRROR = lk(rgb(74, 80, 92), M.Glass, { r = 0.45 })

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
	local leather: Color3 = lt(if baseR then baseR.part.Color else rgb(130, 26, 30), 0.12)
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
				addLight(K, st, p, "PointLight", { Range = 8, Brightness = 0.6, Color = theme })
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
					K:text("TVTopSign", 4.6, sh * 0.8, hz * CF(-0.3, sy0 + sh / 2 + 0.02, 0.1), "♪ SING SING", { fg = theme, glow = 2.4, font = F.FredokaOne, d = 0.02 })
					K:text("TVTopSignNo", 0.9, sh * 0.5, hz * CF(2.25, sy0 + sh / 2, 0.1), string.format("%02d", roomNo), { fg = WHITE, glow = 1.6, font = F.GothamBlack, d = 0.02 })
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
			-- 호출 버튼 (인터폰)
			K:plate("CallPlate", 0.5, 0.6, 0.05, fcf(px, 4.05, 0.0), lk(rgb(236, 236, 232)))
			wdisc(K, "CallButton", 0.24, 0.06, fcf(px, 4.12, 0.05), lk(rgb(220, 30, 40)))
			K:text("CallLabel", 0.44, 0.1, fcf(px, 3.86, 0.055), "호출 · 비상", { fg = rgb(30, 30, 36), font = F.GothamBold, d = 0.004 })
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
			-- 은은한 전체 조명 (천장 가운데, 테마색이 살짝 섞인 흰빛)
			local amb = K:disc("BoothAmbientLens", 0.5, 0.03, CF(0, H - 0.02, zFront - 4.4), lk(rgb(30, 30, 34), M.Metal))
			Common.useCeil(K, 0, zFront - 4.4)
			addLight(K, st, amb, "PointLight", { Range = 17, Brightness = 0.45, Color = lt(theme, 0.65) })
			-- 다운라이트 2 (양쪽 소파 위, 은은한 3000K)
			for k, p in { V3(x0 + 2.2, 0, -0.5), V3(x1 - 2.2, 0, 0.6) } do
				if Common.ceilFree(K, p.X, p.Z, 0.5) then
					K:disc("BoothDownTrim", 0.6, 0.04, CF(p.X, H - 0.02, p.Z), lk(rgb(30, 30, 34), M.Metal))
					local lens = K:disc("BoothDownLens", 0.4, 0.03, CF(p.X, H - 0.04, p.Z), Look.lampWarm)
					table.insert(st.leds, { p = lens, c = (Look.lampWarm :: any).c })
					addLight(K, st, lens, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 13, Brightness = 1.0, Angle = 80, Color = Look.warmLight })
					Common.useCeil(K, p.X, p.Z)
				end
				local _ = k
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
			K:plate("Mirror", 2.38, 2.18, 0.06, m0, SMOKYMIRROR)
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
-- 로비 (karaoke)
-- =====================================================================================================
local function lobbyBuild(K: any, V: any, S: any)
	local H = S.ceilY or V.H
	local st: any = { leds = {}, lights = {} }
	local function under(r: any, nm: string): boolean
		local a = r.part.Parent
		local depth = 0
		while a and depth < 3 do
			if a.Name == nm then
				return true
			end
			a = a.Parent
			depth += 1
		end
		return false
	end
	local function pick(name: string, parent: string?): { any }
		local out = {}
		for _, r in V.byName[name] or {} do
			if not parent or under(r, parent) then
				table.insert(out, r)
			end
		end
		return out
	end
	local function first(name: string, parent: string?): any?
		return pick(name, parent)[1]
	end
	-- 실제 벽면
	local xL, xR = V.x0, V.x1 - 0.05
	local wl = first("WallLining")
	if wl and math.abs(wl.c.X - V.x0) < 0.6 then
		xL = wl.max.X
	end
	local zB = V.z0
	for _, r in V.byName.BoothPartition or {} do
		if math.abs(r.c.Z - V.z0) < 0.6 then
			zB = math.max(zB, r.max.Z)
		end
	end
	local zF = V.z1
	local cx, cz = (xL + xR) / 2, (zB + zF) / 2
	local PINK, PURP, CYAN = NEONS.pink, NEONS.purple, NEONS.cyan
	-- 벽 표시면: wall = "L" (x=xL, +X 를 봄, 폭 방향 = -Z) | "R" (x=xR, -X, 폭 = +Z) | "B" (z=zB, +Z, 폭 = +X)
	local function wcf(wall: string, u: number, y: number, off: number): CFrame
		if wall == "L" then
			return faceCF(V3(xL + off, y, u), V3(1, 0, 0))
		elseif wall == "R" then
			return faceCF(V3(xR - off, y, u), V3(-1, 0, 0))
		end
		return faceCF(V3(u, y, zB + off), V3(0, 0, 1))
	end
	local function wp(name: string, wall: string, a: number, b: number, y0: number, y1: number, d: number, off: number, look: any): BasePart
		return K:plate(name, math.abs(b - a), y1 - y0, d, wcf(wall, (a + b) / 2, (y0 + y1) / 2, off), look)
	end
	local wallFab = lk(rgb(40, 24, 62), M.Fabric)

	-- 1) 바닥: 600x1200 유광 포세린 + 미러볼 아래 원형 인레이 + 복도 쪽 러너 + 현관 매트 ------------------------------
	step(K, "floor", function()
		K:free(function()
			K:box("LobbyFloorSkin", V3(xR - xL - 0.04, 0.03, zF - zB - 0.04), CF(cx, -0.03, cz), lk(rgb(30, 26, 36), M.Slate, { r = 0.06 }))
			local grout = lk(rgb(56, 50, 64), M.SmoothPlastic)
			if not lo(K) then
				local x = xL + 4
				while x < xR - 0.5 do
					K:box("LobbyFloorGrout", V3(0.05, 0.012, zF - zB - 0.06), CF(x, -0.012, cz), grout)
					x += 4
				end
				local z = zB + 2
				while z < zF - 0.5 do
					K:box("LobbyFloorGrout", V3(xR - xL - 0.06, 0.012, 0.05), CF(cx, -0.012, z), grout)
					z += 2
				end
			end
			local ball = first("MirrorBall")
			local bc = if ball then V3(ball.c.X, 0, ball.c.Z) else V3(-0.25, 0, 1.65)
			K:disc("FloorInlay", 8.6, 0.014, CF(bc.X, -0.008, bc.Z), lk(rgb(46, 20, 70), M.SmoothPlastic, { r = 0.12 }))
			local n = if hi(K) then 28 elseif lo(K) then 12 else 18
			local rr = K:ring("FloorInlayLED", CF(bc.X, -0.005, bc.Z) * ANG(PI / 2, 0, 0), 4.2, 0.07, n, neon(PINK))
			for _, p in rr do
				table.insert(st.leds, { p = p, c = PINK })
			end
			K:ring("FloorInlayRing", CF(bc.X, -0.006, bc.Z) * ANG(PI / 2, 0, 0), 3.55, 0.05, math.max(10, n - 6), CHROME)
			K:text("FloorLogo", 6.0, 1.1, topCF(V3(bc.X, 0.003, bc.Z - 0.3), V3(0, 0, -1)), "광안 코인노래연습장", { fg = rgb(255, 120, 200), glow = 1.3, font = F.GothamBlack, d = 0.004, free = true })
			K:text("FloorLogoSub", 4.0, 0.5, topCF(V3(bc.X, 0.003, bc.Z + 0.75), V3(0, 0, -1)), "♪ COIN KARAOKE · 24H", { fg = rgb(170, 230, 255), glow = 1.2, font = F.GothamBold, d = 0.004, free = true })
			-- 러너 (인레이 -> 복도 아치)
			local arch = first("ArchLintel")
			local ax = if arch then arch.c.X else 0
			local z0r, z1r = zB + 0.05, bc.Z - 4.3
			if z1r - z0r > 2 then
				local zc = (z0r + z1r) / 2
				K:box("LobbyRunner", V3(3.6, 0.02, z1r - z0r), CF(ax, -0.004, zc), lk(rgb(44, 22, 64), M.Carpet))
				for _, sx in { -1, 1 } do
					local p = K:box("LobbyRunnerLED", V3(0.06, 0.03, z1r - z0r), CF(ax + sx * 1.78, 0.0, zc), neon(CYAN))
					table.insert(st.leds, { p = p, c = CYAN })
				end
				for k = 0, 1 do
					K:text("LobbyRunnerArrow", 1.3, 1.0, topCF(V3(ax, 0.01, z1r - 1.2 - k * 1.5), V3(0, 0, -1)), "▲", { fg = CYAN, glow = 1.4, font = F.GothamBlack, d = 0.004, free = true })
				end
				K:text("LobbyRunnerText", 3.2, 0.6, topCF(V3(ax, 0.01, z0r + 1.0), V3(0, 0, -1)), "ROOM 01 ~ 08", { fg = rgb(220, 220, 240), glow = 1.1, font = F.GothamBlack, d = 0.004, free = true })
			end
			-- 현관 매트 (원래 자리 · 높이만 바닥 스킨 위로)
			local mat = first("EntranceMat")
			if mat then
				local c, s = mat.c, mat.size
				K:box("EntranceMatNew", V3(s.X, 0.03, s.Z), CF(c.X, 0.0, c.Z), lk(rgb(40, 40, 46), M.Fabric))
				K:box("EntranceMatEdge", V3(s.X + 0.1, 0.025, s.Z + 0.1), CF(c.X, -0.003, c.Z), RUBBER)
				K:text("EntranceMatText", s.X * 0.7, s.Z * 0.35, topCF(V3(c.X, 0.018, c.Z), V3(0, 0, -1)), "WELCOME ♪ SING SING", { fg = rgb(150, 150, 160), font = F.GothamBlack, d = 0.004, free = true })
				hideRec(K, mat)
			end
		end)
	end)

	-- 2) 벽: 오른벽 패브릭 · 징두리 (양옆 · 뒤) · 네온 세로 줄 -------------------------------------------------
	step(K, "walls", function()
		K:free(function()
			wp("LobbyWallR", "R", zB + 0.02, zF - 0.02, 0.0, H - 0.05, 0.02, 0.0, wallFab)
			local gl = GLOSS
			local function wain(wall: string, a: number, b: number)
				if b - a < 0.8 then
					return
				end
				wp("LobbyWainscot", wall, a, b, 0.0, 3.0, 0.05, 0.02, gl)
				wp("LobbyWainscotCap", wall, a, b, 3.0, 3.08, 0.1, 0.02, CHROME)
				local p = wp("LobbyWainscotLED", wall, a + 0.1, b - 0.1, 2.9, 2.94, 0.08, 0.02, neon(PURP))
				table.insert(st.leds, { p = p, c = PURP })
			end
			-- 왼벽 (직원 캐비닛 앞까지)
			local cab = first("StaffCabinet")
			local lz0 = if cab then cab.max.Z + 0.15 else zB + 0.1
			wain("L", lz0, zF - 0.1)
			-- 오른벽 (교환기 · 자판기 사이 · 뒤)
			local ch = first("CoinChanger")
			local vb = first("Body", "VendingMachine")
			local za = if vb then vb.max.Z + 0.12 else -5
			local zb = if ch then ch.min.Z - 0.12 else 6
			wain("R", za, zb)
			if vb then
				wain("R", zB + 0.1, vb.min.Z - 0.12)
			end
			if ch then
				wain("R", ch.max.Z + 0.12, zF - 0.1)
			end
			-- 뒷벽 (아치 양옆)
			local arch = first("ArchLintel")
			local axL = if arch then arch.min.X - 0.4 else -6.5
			local axR = if arch then arch.max.X + 0.4 else 6.5
			wain("B", axR, xR - 0.1)
			wain("B", -11.4, axL)
			-- 네온 세로 줄 (오른벽 빈 칸)
			for _, z in { za + 0.45, zb - 0.45 } do
				local p = wp("LobbyNeonBar", "R", z - 0.04, z + 0.04, 3.3, H - 0.6, 0.06, 0.02, neon(PINK))
				table.insert(st.leds, { p = p, c = PINK })
			end
			-- 위 띠 (천장 아래 블랙 몰딩)
			wp("LobbyCrown", "R", zB + 0.02, zF - 0.02, H - 0.35, H - 0.05, 0.12, 0.0, LACQ)
			wp("LobbyCrown", "L", zB + 0.02, zF - 0.02, H - 0.35, H - 0.05, 0.12, 0.0, LACQ)
		end)
	end)

	-- 3) 동전교환기 (같은 자리, 원래 상자 · 간판을 감싸는 실물) ----------------------------------------------------
	step(K, "changer", function()
		local ch = first("CoinChanger")
		if not ch then
			return
		end
		local mn, mx = ch.min, ch.max
		local front = mx.X
		for _, nm in { "ChangerDisplay", "BillSlot", "CoinTray" } do
			for _, r in V.byName[nm] or {} do
				front = math.min(front, r.min.X)
			end
		end
		for _, r in V.parts do
			if string.sub(r.name, 1, 5) == "Sign_" and r.c.X > mn.X - 0.6 and r.c.Z > mn.Z - 0.2 and r.c.Z < mx.Z + 0.2 then
				front = math.min(front, r.min.X)
			end
		end
		front -= 0.06
		local back = xR - 0.02
		local zc = (mn.Z + mx.Z) / 2
		local w = mx.Z - mn.Z + 0.1
		local depth = back - front
		local h = mx.Y + 0.08
		K:free(function()
			local body = lk(rgb(200, 204, 210), M.Metal)
			K:rbox("ChangerBody", V3(h, depth, w), 0.12, CF(front + depth / 2, h / 2, zc) * ANG(0, 0, PI / 2), body)
			local f0 = faceCF(V3(front, 0, zc), V3(-1, 0, 0))
			K:plate("ChangerFace", w - 0.2, h - 0.5, 0.03, f0 * CF(0, (h - 0.5) / 2 + 0.3, 0), lk(rgb(30, 92, 186), M.SmoothPlastic, { r = 0.05 }))
			K:text("ChangerHeader", w - 0.4, 0.6, f0 * CF(0, h - 0.62, 0.04), "지폐 교환기", { fg = WHITE, bg = rgb(20, 60, 140), glow = 1.4, font = F.GothamBlack, d = 0.03 })
			K:plate("ChangerLCDBezel", w - 0.7, 0.72, 0.04, f0 * CF(0, h - 1.5, 0.03), lk(rgb(20, 20, 24)))
			K:text("ChangerLCD", w - 0.9, 0.56, f0 * CF(0, h - 1.5, 0.075), "1,000원 → 500원 ×2", { fg = rgb(255, 60, 40), glow = 1.8, font = F.Arcade, d = 0.004, bg = rgb(16, 4, 4) })
			K:text("ChangerSteps", w - 0.6, 1.0, f0 * CF(0, h - 2.55, 0.035), "① 지폐를 반듯하게 넣으세요\n② 500원 동전이 아래로 나와요\n1천 · 5천 · 1만원권 (5만원권 불가)", { fg = WHITE, font = F.GothamMedium, d = 0.004, align = "Left" })
			K:plate("BillBezel", 1.3, 0.34, 0.08, f0 * CF(0, h - 3.45, 0.03), lk(rgb(26, 26, 30)))
			K:plate("BillSlotGap", 1.0, 0.04, 0.09, f0 * CF(0, h - 3.45, 0.03), lk(rgb(2, 2, 2)))
			st.changerLED = K:plate("BillSlotLEDs", 1.1, 0.05, 0.09, f0 * CF(0, h - 3.6, 0.03), Look.ledGreen)
			K:text("BillSlotLabel", 1.2, 0.14, f0 * CF(0, h - 3.24, 0.035), "지폐 투입구", { fg = rgb(220, 230, 255), font = F.GothamBold, d = 0.004 })
			-- 동전 배출구 (스테인리스 컵 + 동전)
			local cy0 = 1.3
			K:plate("CoinOutletFrame", 1.6, 1.0, 0.1, f0 * CF(0, cy0, 0.03), Look.steel)
			K:plate("CoinOutletHole", 1.3, 0.7, 0.11, f0 * CF(0, cy0 + 0.05, 0.03), lk(rgb(14, 14, 16)))
			K:box("CoinOutletLip", V3(0.3, 0.16, 1.4), CF(front - 0.25, cy0 - 0.4, zc), Look.steel)
			for k = 0, 2 do
				K:disc("CoinInTray", 0.26, 0.04, CF(front - 0.24 + k * 0.03, cy0 - 0.3 + k * 0.03, zc - 0.3 + k * 0.28) * ANG(0, 0, 0.1), lk(rgb(200, 190, 160), M.Metal, { r = 0.2 }))
			end
			K:text("CoinOutletLabel", 1.4, 0.16, f0 * CF(0, cy0 + 0.66, 0.035), "동전 나오는 곳", { fg = WHITE, font = F.GothamBold, d = 0.004 })
			wdisc(K, "ChangerLock", 0.16, 0.05, f0 * CF(w / 2 - 0.4, h - 4.1, 0.03), CHROME)
			K:text("ChangerSticker", 1.0, 0.36, f0 * CF(-w / 2 + 0.75, 0.55, 0.035), "고장 · 문의\n카운터 벨", { fg = rgb(30, 30, 36), bg = rgb(255, 214, 60), font = F.GothamBold, d = 0.01 })
			K:text("ChangerCCTV", 0.8, 0.36, f0 * CF(w / 2 - 0.65, 0.55, 0.035), "CCTV\n녹화 중", { fg = WHITE, bg = rgb(200, 30, 40), font = F.GothamBlack, d = 0.01 })
			K:plate("ChangerKick", w - 0.1, 0.25, 0.04, f0 * CF(0, 0.125, 0.0), lk(rgb(30, 30, 34)))
		end)
		hideRec(K, ch)
		for _, nm in { "ChangerDisplay", "BillSlot", "CoinTray" } do
			for _, r in V.byName[nm] or {} do
				hideRec(K, r)
			end
		end
	end)

	-- 4) 음료 자판기 (빛나는 진열창 · 캔 · 페트 · 가격표 · 버튼 · 동전/지폐/카드 · 꺼내는 곳) -------------------------------
	step(K, "vending", function()
		local vb = first("Body", "VendingMachine")
		if not vb then
			return
		end
		local disp = first("Display", "VendingMachine")
		local mn, mx = vb.min, vb.max
		local front = mn.X
		for _, r in pick("Can") do
			front = math.min(front, r.min.X)
		end
		if disp then
			front = math.min(front, disp.min.X)
		end
		front -= 0.25
		local back = xR - 0.02
		local depth = back - front
		local w = mx.Z - mn.Z + 0.12
		local zc = (mn.Z + mx.Z) / 2
		local h = mx.Y + 0.15
		-- 진열창 = 원래 Display 자리 (NightNeon 이 밤에 밝힘)
		local wy0, wy1 = 2.25, 5.65
		local wz0, wz1 = zc - w / 2 + 0.35, zc + w / 2 - 0.35
		if disp then
			wy0, wy1, wz0, wz1 = disp.min.Y, disp.max.Y, disp.min.Z, disp.max.Z
		end
		local red = lk(rgb(206, 30, 40), M.Metal, { r = 0.04 })
		local wf = (disp and disp.min.X or (front + 0.25)) - 0.02 -- 진열 뒤판 앞면
		K:free(function()
			-- 몸체: 뒤 블록 + 앞 테 (진열창 둘레)
			K:box("VendBack", V3(back - wf, h, w), CF((wf + back) / 2, h / 2, zc), red)
			K:box("VendFrameTop", V3(wf - front, h - wy1, w), CF((front + wf) / 2, (wy1 + h) / 2, zc), red)
			K:box("VendFrameBot", V3(wf - front, wy0, w), CF((front + wf) / 2, wy0 / 2, zc), red)
			K:box("VendFrameSide", V3(wf - front, wy1 - wy0, wz0 - (zc - w / 2)), CF((front + wf) / 2, (wy0 + wy1) / 2, (zc - w / 2 + wz0) / 2), red)
			K:box("VendFrameSide", V3(wf - front, wy1 - wy0, (zc + w / 2) - wz1), CF((front + wf) / 2, (wy0 + wy1) / 2, (wz1 + zc + w / 2) / 2), red)
			if not disp then
				K:box("VendBackLight", V3(0.04, wy1 - wy0, wz1 - wz0), CF(wf + 0.02, (wy0 + wy1) / 2, (wz0 + wz1) / 2), lk(rgb(250, 250, 255), M.Neon, { t = 0.3 }))
			end
			local f0 = faceCF(V3(front, 0, zc), V3(-1, 0, 0)) -- +X = 보는 사람 오른쪽 = +Z
			-- 헤더 라이트박스
			local hp = K:text("VendHeader", w - 0.3, 0.55, f0 * CF(0, h - 0.4, 0.0), "COOL DRINK  시원한 음료", { fg = WHITE, bg = rgb(170, 20, 30), glow = 1.5, font = F.GothamBlack, d = 0.04 })
			addLight(K, st, hp, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 8, Brightness = 0.7, Angle = 110, Color = rgb(255, 230, 230) })
			-- 진열: 3단 x 5칸
			local rows = 3
			local cols = 5
			local cw = (wz1 - wz0 - 0.1) / cols
			local rh = (wy1 - wy0) / rows
			local prods = {
				{ rgb(220, 30, 40), "can", "1,300" }, { rgb(40, 120, 220), "pet", "1,500" }, { rgb(250, 200, 30), "can", "1,300" },
				{ rgb(240, 240, 240), "pet", "1,000" }, { rgb(40, 160, 70), "can", "1,400" }, { rgb(250, 120, 30), "pet", "1,800" },
				{ rgb(120, 60, 30), "can", "1,500" }, { rgb(230, 230, 240), "can", "1,300" }, { rgb(200, 40, 140), "pet", "1,700" },
			}
			local px = wf - 0.16
			for rI = 0, rows - 1 do
				local y = wy0 + rI * rh + 0.1
				K:box("VendShelf", V3(0.3, 0.04, wz1 - wz0), CF(wf - 0.15, y - 0.02, (wz0 + wz1) / 2), lk(rgb(200, 204, 210), M.Metal))
				for cI = 0, cols - 1 do
					local z = wz0 + 0.05 + cw * (cI + 0.5)
					local p = prods[((rI * cols + cI) % #prods) + 1]
					if p[2] == "can" then
						K:vcyl("VendCan", 0.5, 0.2, CF(px, y + 0.25, z), lk(p[1], M.Metal, { r = 0.1 }))
						K:vcyl("VendCanTop", 0.03, 0.17, CF(px, y + 0.515, z), Look.alu)
					else
						K:vcyl("VendPet", 0.5, 0.22, CF(px, y + 0.25, z), lk(lt(p[1], 0.2), M.Glass, { t = 0.25 }))
						K:vcyl("VendPetLabel", 0.16, 0.225, CF(px, y + 0.25, z), lk(p[1]))
						K:vcyl("VendPetNeck", 0.16, 0.1, CF(px, y + 0.58, z), lk(lt(p[1], 0.2), M.Glass, { t = 0.25 }))
						K:vcyl("VendPetCap", 0.05, 0.11, CF(px, y + 0.68, z), lk(p[1]))
					end
					if hi(K) or rI == 0 then
						K:text("VendPrice", cw * 0.8, 0.12, faceCF(V3(wf - 0.31, y - 0.02, z), V3(-1, 0, 0)), p[3], { fg = rgb(20, 20, 20), bg = rgb(250, 250, 250), font = F.GothamBold, d = 0.01 })
					end
				end
			end
			-- 버튼 줄 (진열창 아래)
			for cI = 0, cols - 1 do
				local z = wz0 + 0.05 + cw * (cI + 0.5)
				K:plate("VendButton", 0.28, 0.14, 0.05, faceCF(V3(front, wy0 - 0.2, z), V3(-1, 0, 0)), lk(rgb(250, 250, 250)))
				K:plate("VendButtonLED", 0.1, 0.05, 0.06, faceCF(V3(front, wy0 - 0.2, z), V3(-1, 0, 0)), Look.ledRed)
			end
			K:plate("VendGlass", wz1 - wz0, wy1 - wy0, 0.02, faceCF(V3(front, (wy0 + wy1) / 2, (wz0 + wz1) / 2), V3(-1, 0, 0)), lk(rgb(220, 236, 240), M.Glass, { t = 0.82, r = 0.2 }))
			-- 결제부 (아래 오른쪽) + 꺼내는 곳
			local payZ = zc + w / 2 - 0.6
			K:plate("VendPayPanel", 0.9, 1.1, 0.04, faceCF(V3(front, 1.45, payZ), V3(-1, 0, 0)), lk(rgb(30, 30, 34)))
			K:text("VendPayLCD", 0.7, 0.2, faceCF(V3(front - 0.045, 1.82, payZ), V3(-1, 0, 0)), "투입 0원", { fg = rgb(90, 255, 120), bg = rgb(6, 16, 8), glow = 1.4, font = F.Arcade, d = 0.004 })
			K:plate("VendCoinSlot", 0.2, 0.26, 0.06, faceCF(V3(front, 1.45, payZ - 0.22), V3(-1, 0, 0)), CHROME)
			K:plate("VendBillSlot", 0.4, 0.08, 0.06, faceCF(V3(front, 1.45, payZ + 0.15), V3(-1, 0, 0)), Look.ledGreen)
			K:text("VendCard", 0.62, 0.22, faceCF(V3(front - 0.045, 1.1, payZ), V3(-1, 0, 0)), "카드 · 페이 OK", { fg = WHITE, bg = rgb(40, 90, 200), font = F.GothamBold, d = 0.01 })
			local flapZ = (wz0 + payZ - 0.5) / 2
			K:plate("VendFlap", payZ - 0.55 - wz0, 0.9, 0.06, faceCF(V3(front, 0.95, flapZ), V3(-1, 0, 0)), lk(rgb(24, 24, 28)))
			K:text("VendFlapText", 1.0, 0.18, faceCF(V3(front - 0.065, 1.2, flapZ), V3(-1, 0, 0)), "PUSH ▼ 꺼내는 곳", { fg = rgb(220, 220, 220), font = F.GothamBold, d = 0.004 })
			K:plate("VendKick", w - 0.1, 0.25, 0.04, faceCF(V3(front, 0.125, zc), V3(-1, 0, 0)), lk(rgb(30, 30, 34)))
		end)
		hideRec(K, vb)
		for _, r in pick("Can") do
			hideRec(K, r)
		end
	end)

	-- 5) 대기 소파 + 옆 탁자 · 화분 ---------------------------------------------------------------------------
	step(K, "sofa", function()
		for _, g in sofaGroups(V, function(_r)
			return true
		end) do
			sofaOverlay(K, g, { color = rgb(44, 40, 44), led = PINK, leds = st.leds })
		end
		local sofaR = first("Backrest", "WaitingSofa")
		if sofaR then
			-- 오른쪽 끝 원형 사이드 테이블 (자리 확인)
			local tx, tz = sofaR.max.X + 1.0, sofaR.min.Z - 1.1
			local pcf = CF(tx, 0, tz)
			if K:spot(pcf, V3(1.4, 2.1, 1.4), 0.1) then
				K:disc("SideTableTop", 1.4, 0.08, pcf * CF(0, 2.0, 0), lk(rgb(236, 232, 226), M.Marble))
				K:vcyl("SideTableStem", 1.9, 0.14, pcf * CF(0, 1.0, 0), Look.goldMetal)
				K:disc("SideTableBase", 0.9, 0.06, pcf * CF(0, 0.03, 0), Look.goldMetal)
				Props.potPlant(K, pcf * CF(0.2, 2.04, 0.15), 0.4, 0.55)
				K:box("SideTableCatalog", V3(0.7, 0.12, 0.9), pcf * CF(-0.2, 2.1, -0.1) * ANG(0, 0.3, 0), lk(rgb(88, 22, 168)))
			end
			-- 왼쪽 끝 큰 화분
			local px, pz = sofaR.min.X - 1.4, math.min(sofaR.min.Z - 0.8, 9.3)
			local pp = CF(px, 0, pz)
			if K:spot(pp, V3(1.6, 4.6, 1.6), 0.05) then
				Props.floorPlant(K, pp, { kind = "snake", h = 4.4, dia = 1.3, pot = lk(rgb(30, 30, 34), M.Concrete) })
			end
		end
	end)

	-- 6) 카운터 앞판 (세로 네온 플루트 · 로고) -----------------------------------------------------------------
	step(K, "counter", function()
		local body = first("Body", "Counter")
		local top = first("Top", "Counter")
		if not body then
			return
		end
		local mn, mx = body.min, body.max
		local len = mx.X - mn.X
		local zf = mx.Z + 0.02
		local f0 = faceCF(V3((mn.X + mx.X) / 2, 0, zf), V3(0, 0, 1))
		local y0, y1 = 0.72, mx.Y - 0.02
		K:free(function()
			K:plate("CounterClad", len - 0.04, y1 - y0, 0.03, f0 * CF(0, (y0 + y1) / 2, 0), GLOSS)
			local n = math.floor(len / 0.9)
			for i = 1, n do
				local u = -len / 2 + len * (i - 0.5) / n
				if math.abs(u) > 1.6 then
					local p = K:plate("CounterFluteLED", 0.05, y1 - y0 - 0.2, 0.05, f0 * CF(u, (y0 + y1) / 2, 0), neon(PURP))
					table.insert(st.leds, { p = p, c = PURP })
				end
			end
			K:plate("CounterLogoBack", 3.0, 1.3, 0.05, f0 * CF(0, (y0 + y1) / 2 + 0.1, 0.0), lk(rgb(30, 22, 44), M.Glass, { t = 0.1, r = 0.15 }))
			K:text("CounterLogo", 2.8, 0.66, f0 * CF(0, (y0 + y1) / 2 + 0.32, 0.06), "COUNTER", { fg = rgb(255, 120, 220), glow = 2.0, font = F.FredokaOne, d = 0.004 })
			K:text("CounterLogoSub", 2.8, 0.3, f0 * CF(0, (y0 + y1) / 2 - 0.25, 0.06), "무인 운영 · 문의는 벨", { fg = rgb(220, 220, 236), glow = 1.2, font = F.GothamBold, d = 0.004 })
			if top then
				local tmn, tmx = top.min, top.max
				K:box("CounterTopEdge", V3(tmx.X - tmn.X + 0.02, 0.06, 0.03), CF((tmn.X + tmx.X) / 2, tmn.Y + 0.04, tmx.Z + 0.015), CHROME)
				for _, sx in { -1, 1 } do
					local x = if sx < 0 then mn.X - 0.01 else mx.X + 0.01
					K:plate("CounterSide", mx.Z - mn.Z - 0.04, mx.Y - 0.4, 0.03, faceCF(V3(x, (mx.Y + 0.4) / 2, (mn.Z + mx.Z) / 2), V3(sx, 0, 0)), GLOSS)
				end
			end
		end)
	end)

	-- 7) 직원 구역: 캐비닛 (작업대 · 열린 선반) + UV 살균기 (살균하기) + 마이크 커버 디스펜서 (뽑기) -----------------------
	step(K, "staff", function()
		local cab = first("StaffCabinet")
		local ster = first("MicSterilizer")
		local cover = first("MicCoverBox")
		if cab then
			local mn, mx = cab.min, cab.max
			local fx = mx.X -- 앞면 (+X 를 봄)
			local zc = (mn.Z + mx.Z) / 2
			local w = mx.Z - mn.Z
			local h = mx.Y
			local carcass = lk(rgb(58, 50, 74), M.SmoothPlastic, { r = 0.04 })
			local wtY = if ster then ster.min.Y else 2.95
			K:free(function()
				K:box("StaffCabBack", V3(0.1, h, w), CF(mn.X + 0.05, h / 2, zc), carcass)
				K:box("StaffCabSide", V3(fx - mn.X, h, 0.1), CF((mn.X + fx) / 2, h / 2, mn.Z + 0.05), carcass)
				K:box("StaffCabSide", V3(fx - mn.X, h, 0.1), CF((mn.X + fx) / 2, h / 2, mx.Z - 0.05), carcass)
				K:box("StaffCabTop", V3(fx - mn.X + 0.08, 0.12, w + 0.08), CF((mn.X + fx) / 2, h - 0.06, zc), carcass)
				-- 아래 문 3짝
				K:box("StaffCabLower", V3(fx - mn.X - 0.1, wtY - 0.15, w - 0.2), CF((mn.X + fx) / 2 - 0.05, (wtY - 0.15) / 2, zc), carcass)
				for k = 0, 2 do
					local z = mn.Z + 0.1 + (w - 0.2) * (k + 0.5) / 3
					K:plate("StaffCabDoor", (w - 0.2) / 3 - 0.06, wtY - 0.4, 0.04, faceCF(V3(fx, wtY / 2 - 0.05, z), V3(1, 0, 0)), lk(rgb(72, 64, 92)))
					K:plate("StaffCabPull", 0.06, 0.6, 0.06, faceCF(V3(fx, wtY - 0.6, z + ((w - 0.2) / 6 - 0.2) * (if k == 1 then 1 else -1)), V3(1, 0, 0)), CHROME)
				end
				-- 작업대 (앞으로 1.3 튀어나옴: 살균기 · 디스펜서가 올라감)
				local wtFront = if ster then ster.max.X + 0.15 else fx + 1.3
				K:box("StaffWorktop", V3(wtFront - mn.X, 0.15, w + 0.04), CF((mn.X + wtFront) / 2, wtY - 0.075, zc), lk(rgb(236, 234, 228), M.SmoothPlastic))
				K:box("StaffWorktopEdge", V3(0.04, 0.15, w + 0.04), CF(wtFront + 0.02, wtY - 0.075, zc), CHROME)
				for _, z in { mn.Z + 0.4, mx.Z - 0.4 } do
					K:bar("StaffWorktopBracket", V3(fx, wtY - 0.9, z), V3(wtFront - 0.2, wtY - 0.16, z), 0.08, 0.08, CHROME)
				end
				-- 위 열린 선반 2단 + 상자
				for _, sy in { 4.55, 5.6 } do
					K:box("StaffShelf", V3(fx - mn.X - 0.1, 0.08, w - 0.2), CF((mn.X + fx) / 2, sy, zc), carcass)
				end
				local boxes = { { rgb(240, 240, 236), "마이크 커버" }, { rgb(30, 30, 30), "AA 건전지" }, { rgb(80, 170, 220), "물티슈" }, { rgb(240, 200, 60), "탬버린" } }
				for k, b in boxes do
					local z = mn.Z + 0.6 + (k - 1) * ((w - 1.2) / (#boxes - 1))
					local y = if k % 2 == 0 then 5.64 else 4.59
					K:box("StaffBox", V3(1.0, 0.68, 1.1), CF(fx - 0.6, y + 0.34, z), lk(b[1], M.Cardboard))
					K:text("StaffBoxLabel", 0.9, 0.28, faceCF(V3(fx - 0.1 + 0.001, y + 0.36, z), V3(1, 0, 0)), b[2], { fg = if k == 2 then WHITE else rgb(30, 30, 30), font = F.GothamBold, d = 0.004 })
				end
				K:text("StaffOnly", 1.8, 0.36, faceCF(V3(fx + 0.02, h - 0.35, zc), V3(1, 0, 0)), "STAFF ONLY", { fg = WHITE, bg = rgb(200, 30, 40), font = F.GothamBlack, d = 0.02 })
			end)
			hideRec(K, cab)
			-- UV 살균기 (같은 자리)
			if ster then
				local smn, smx = ster.min, ster.max
				local sc = (smn + smx) / 2
				local sw = smx.Z - smn.Z
				local sh = smx.Y - smn.Y
				local f0 = faceCF(V3(smx.X + 0.04, sc.Y, sc.Z), V3(1, 0, 0))
				local uv: BasePart? = nil
				local lab: TextLabel? = nil
				local doorP: BasePart? = nil
				K:free(function()
					K:rbox("SterBody", V3(sh, smx.X - smn.X + 0.04, sw + 0.04), 0.08, CF(sc) * ANG(0, 0, PI / 2), lk(rgb(240, 240, 244)))
					K:plate("SterWindowFrame", sw - 0.2, sh - 0.7, 0.03, f0 * CF(0, -0.2, 0), lk(rgb(30, 30, 36)))
					uv = K:plate("SterUVLamp", sw - 0.36, sh - 0.86, 0.02, f0 * CF(0, -0.2, 0.03), lk(rgb(120, 70, 220), M.Neon, { t = 0.35 }))
					for k = 0, 3 do
						local z = -sw / 2 + 0.4 + k * (sw - 0.8) / 3
						K:seg("SterMic", (f0 * CF(z, 0.25, 0.06)).Position, (f0 * CF(z, -0.6, 0.06)).Position, 0.16, lk(rgb(40, 40, 46)))
						K:ball("SterMicHead", 0.26, f0 * CF(z, -0.72, 0.06), MICGRILLE)
					end
					doorP = K:plate("SterDoorGlass", sw - 0.2, sh - 0.7, 0.03, f0 * CF(0, -0.2, 0.12), lk(rgb(200, 190, 255), M.Glass, { t = 0.6, r = 0.15 }))
					K:plate("SterDisplayBezel", sw - 0.5, 0.36, 0.04, f0 * CF(0, sh / 2 - 0.25, 0), lk(rgb(20, 20, 24)))
					local _, l = K:text("SterDisplay", sw - 0.6, 0.3, f0 * CF(0, sh / 2 - 0.25, 0.045), "UV 살균기 · 대기", { fg = rgb(190, 150, 255), glow = 1.6, font = F.GothamBold, d = 0.004 })
					lab = l
					K:plate("SterHandle", 0.06, 0.8, 0.06, f0 * CF(sw / 2 - 0.2, -0.2, 0.15), CHROME)
				end)
				hideRec(K, ster)
				hideRec(K, first("SterilizerUV"))
				st.ster = { uv = uv, lab = lab, t0 = -1 }
				if doorP then
					Interact.prompt(K, doorP :: BasePart, {
						action = "마이크 살균하기",
						object = "UV 마이크 살균기",
						hold = 0.4,
						fn = function()
							st.ster.t0 = os.clock()
						end,
					})
				end
			end
			-- 마이크 커버 디스펜서 (작업대 위, 살균기와 2.6 이상 떨어짐)
			if cover then
				hideRec(K, cover)
			end
			local dz = mn.Z + 1.0
			if ster then
				dz = math.min(dz, ster.min.Z - 2.1)
			end
			dz = math.max(dz, mn.Z + 0.75)
			local dy = wtY
			local dxF = fx + 0.85
			local popper: BasePart? = nil
			local popCF: CFrame? = nil
			local shell: BasePart? = nil
			K:free(function()
				local base = CF(dxF - 0.45, dy, dz)
				shell = K:box("CoverDispenser", V3(0.9, 1.6, 1.2), base * CF(0, 0.8, 0), lk(rgb(236, 240, 246), M.Glass, { t = 0.45, r = 0.1 }))
				K:box("CoverDispenserBase", V3(0.95, 0.25, 1.25), base * CF(0, 0.125, 0), lk(rgb(230, 30, 110)))
				local cols = { rgb(230, 40, 60), rgb(40, 120, 230), rgb(250, 200, 30), rgb(60, 200, 110), rgb(230, 40, 160) }
				for k = 0, 9 do
					local yy = 0.4 + (k % 5) * 0.22
					local zz = -0.35 + math.floor(k / 5) * 0.4 + (k % 2) * 0.12
					K:ell("CoverInBox", V3(0.42, 0.2, 0.36), base * CF(-0.05 + (k % 3) * 0.08, yy, zz), lk(cols[k % #cols + 1], M.Fabric))
				end
				K:text("CoverDispenserLabel", 1.1, 0.34, faceCF((base * V3(0.455, 1.35, 0)), V3(1, 0, 0)), "마이크 커버 무료\n1인 1개 · 위생", { fg = rgb(230, 30, 110), bg = rgb(255, 255, 255), font = F.GothamBold, d = 0.01 })
				K:plate("CoverSlot", 0.7, 0.08, 0.03, faceCF((base * V3(0.455, 0.3, 0)), V3(1, 0, 0)), lk(rgb(20, 20, 24)))
				popCF = base * CF(0.2, 0.42, 0)
				popper = K:ell("CoverPopped", V3(0.42, 0.2, 0.36), popCF :: CFrame, lk(rgb(230, 40, 60), M.Fabric, { t = 1 }))
			end)
			if shell then
				Interact.prompt(K, shell :: BasePart, {
					action = "마이크 커버 뽑기",
					object = "커버 디스펜서",
					fn = function(n)
						local p = popper
						if not (p and p.Parent and popCF) then
							return
						end
						local cols = { rgb(230, 40, 60), rgb(40, 120, 230), rgb(250, 200, 30), rgb(60, 200, 110) }
						p.Color = cols[(n - 1) % #cols + 1]
						p.Transparency = 0
						p.CFrame = K.cf * (popCF :: CFrame)
						TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = K.cf * (popCF :: CFrame) * CF(0.45, -0.3, 0) }):Play()
						task.delay(5, function()
							if p.Parent then
								p.Transparency = 1
							end
						end)
					end,
				})
			end
		end
		-- 뒤 카운터 (마이크 충전 랙 8 · 청소 도구) + 위 선반
		local x0b, x1b = -20.2, -11.8
		if cab then
			x0b = math.max(x0b, (if ster then ster.max.X else cab.max.X + 1.3) + 0.3)
		end
		local depthB = 1.5
		local pcf = CF((x0b + x1b) / 2, 0, zB + depthB / 2)
		if K:spot(pcf, V3(x1b - x0b, 3.3, depthB), 0.0) then
			local L = x1b - x0b
			K:box("BackCounterBody", V3(L, 3.0, depthB), pcf * CF(0, 1.5, 0), lk(rgb(40, 34, 52)))
			K:box("BackCounterTop", V3(L + 0.1, 0.12, depthB + 0.1), pcf * CF(0, 3.06, 0), lk(rgb(236, 234, 228)))
			local f0 = faceCF((pcf * V3(0, 0, depthB / 2 + 0.01)), V3(0, 0, 1))
			local nd = math.max(2, math.floor(L / 2.1))
			for k = 1, nd do
				local u = -L / 2 + L * (k - 0.5) / nd
				K:plate("BackCounterDoor", L / nd - 0.08, 2.5, 0.03, f0 * CF(u, 1.55, 0), lk(rgb(58, 50, 74)))
				K:plate("BackCounterPull", 0.5, 0.05, 0.05, f0 * CF(u, 2.6, 0.02), CHROME)
			end
			K:plate("BackCounterKick", L, 0.25, 0.02, f0 * CF(0, 0.125, -0.06), lk(rgb(14, 14, 16)))
			-- 마이크 충전 랙 (방 번호별)
			local rackL = math.min(L - 1.6, 6.4)
			local rcx = -L / 2 + 0.3 + rackL / 2
			local rack = pcf * CF(rcx, 3.12, -0.1)
			K:box("MicRackBase", V3(rackL, 0.2, 0.8), rack * CF(0, 0.1, 0), lk(rgb(24, 24, 28)))
			K:text("MicRackLabel", rackL - 0.4, 0.14, faceCF((rack * V3(0, 0.1, 0.405)), V3(0, 0, 1)), "마이크 충전 · 방 번호 확인 후 반납", { fg = rgb(200, 200, 210), font = F.GothamBold, d = 0.004 })
			for k = 1, 8 do
				local x = -rackL / 2 + rackL * (k - 0.5) / 8
				local a = (rack * V3(x, 0.24, 0.3))
				local b = (rack * V3(x, 0.32, -0.25))
				if not lo(K) then
					handMic(K, a, b, lk(if k % 2 == 0 then rgb(232, 232, 236) else rgb(30, 30, 34)), CYAN, nil)
				end
				K:plate("MicRackLED", 0.06, 0.05, 0.02, faceCF((rack * V3(x - 0.2, 0.16, 0.405)), V3(0, 0, 1)), if k == 3 or k == 6 then Look.ledRed else Look.ledGreen)
				K:text("MicRackNo", 0.24, 0.1, faceCF((rack * V3(x + 0.08, 0.16, 0.405)), V3(0, 0, 1)), string.format("%02d", k), { fg = WHITE, font = F.GothamBold, d = 0.004 })
			end
			-- 청소 도구 (분무기 · 수건)
			local tool = pcf * CF(L / 2 - 0.6, 3.12, 0)
			K:vcyl("SprayBottle", 0.7, 0.3, tool * CF(0, 0.35, 0.1), lk(rgb(80, 180, 230), M.Plastic, { t = 0.2 }))
			K:box("SprayHead", V3(0.16, 0.2, 0.3), tool * CF(0, 0.8, 0.05), lk(rgb(240, 240, 240)))
			for k = 0, 2 do
				K:box("TowelStack", V3(0.7, 0.12, 0.5), tool * CF(-0.7, 0.06 + k * 0.12, 0), lk(if k == 1 then rgb(240, 240, 240) else rgb(140, 200, 240), M.Fabric))
			end
			-- 위 벽 선반 + 상자
			local sh = Props.shelf(K, faceCF(V3((x0b + x1b) / 2, 4.75, zB), V3(0, 0, 1)), L - 0.6, { depth = 0.9, look = lk(rgb(236, 234, 228)), bracket = CHROME })
			Props.row(K, sh, L - 1.0, "boxes", { colors = { rgb(240, 240, 236), rgb(230, 40, 100), rgb(60, 120, 220), rgb(250, 200, 40) }, seed = 5 })
		end
	end)

	-- 8) 노래책 거치대 (기울어진 상판 + 펼친 바인더) -------------------------------------------------------------
	step(K, "catalog", function()
		local post = first("CatalogPost")
		local book = first("CatalogBook")
		if not post then
			return
		end
		local c = V3(post.c.X, 0, post.c.Z)
		local topY = if book then book.min.Y + 0.15 else 3.2
		K:free(function()
			K:box("LecternBase", V3(1.8, 0.1, 1.2), CF(c + V3(0, 0.05, 0)), lk(rgb(26, 26, 30), M.Metal))
			K:box("LecternPost", V3(0.3, topY - 0.1, 0.3), CF(c + V3(0, (topY - 0.1) / 2 + 0.1, 0)), CHROME)
			local tcf = CF(c + V3(0, topY, 0.05)) * ANG(math.rad(18), 0, 0)
			K:box("LecternTop", V3(2.4, 0.08, 1.7), tcf, lk(rgb(40, 34, 52)))
			K:box("LecternLip", V3(2.4, 0.12, 0.06), tcf * CF(0, 0.08, 0.82), CHROME)
			-- 펼친 바인더
			for _, sx in { -1, 1 } do
				K:box("BinderCover", V3(1.05, 0.04, 1.45), tcf * CF(sx * 0.55, 0.06, 0), lk(rgb(88, 22, 168)))
				K:box("BinderPages", V3(0.98, 0.1, 1.38), tcf * CF(sx * 0.53, 0.12, 0) * ANG(0, 0, -sx * 0.04), lk(rgb(246, 244, 236)))
			end
			K:box("BinderRings", V3(0.08, 0.14, 1.2), tcf * CF(0, 0.16, 0), CHROME)
			local lines1, lines2 = {}, {}
			for i = 1, 5 do
				table.insert(lines1, string.format("%d %s", songNo(i), SONGS[i]))
				table.insert(lines2, string.format("%d %s", songNo(i + 5), SONGS[i + 5]))
			end
			for k, sx in { -1, 1 } do
				local pcf = tcf * CF(sx * 0.53, 0.175, 0)
				local d = CFrame.fromMatrix(pcf.Position, pcf.XVector, -pcf.ZVector, pcf.YVector)
				K:text("BinderText", 0.9, 1.25, d, (if k == 1 then "가요 · 신곡\n" else "인기 · 추천\n") .. table.concat(if k == 1 then lines1 else lines2, "\n"), { fg = rgb(30, 30, 40), font = F.GothamMedium, align = "Left", d = 0.004 })
			end
		end)
		for _, nm in { "CatalogPost", "CatalogBase", "CatalogBook", "CatalogPage" } do
			hideRec(K, first(nm))
		end
	end)

	-- 9) LED 전광판 테 · 노래왕 보드 금색 LED 테 + 레일 조명 ----------------------------------------------------------
	step(K, "screens", function()
		K:free(function()
			local hs = first("ScreenHousing")
			if hs then
				local mn, mx = hs.min, hs.max
				local fx = mx.X + 0.01
				for _, sy in { -1, 1 } do
					K:box("ScreenTrim", V3(0.06, 0.08, mx.Z - mn.Z + 0.1), CF(fx, (mn.Y + mx.Y) / 2 + sy * ((mx.Y - mn.Y) / 2 + 0.04), (mn.Z + mx.Z) / 2), CHROME)
					K:box("ScreenTrim", V3(0.06, mx.Y - mn.Y + 0.16, 0.08), CF(fx, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2 + sy * ((mx.Z - mn.Z) / 2 + 0.04)), CHROME)
				end
				K:text("ScreenCaption", mx.Z - mn.Z, 0.4, faceCF(V3(xL + 0.03, mn.Y - 0.35, (mn.Z + mx.Z) / 2), V3(1, 0, 0)), "TOP 100 인기차트 · 매주 업데이트", { fg = rgb(200, 220, 255), glow = 1.2, font = F.GothamBold, d = 0.02 })
			end
			local bf = first("BoardFrame")
			if bf then
				local mn, mx = bf.min, bf.max
				local fx = mx.X + 0.02
				local gold = rgb(255, 200, 80)
				for _, sy in { -1, 1 } do
					local p1 = K:box("BoardLED", V3(0.05, 0.07, mx.Z - mn.Z + 0.3), CF(fx, (mn.Y + mx.Y) / 2 + sy * ((mx.Y - mn.Y) / 2 + 0.1), (mn.Z + mx.Z) / 2), neon(gold))
					local p2 = K:box("BoardLED", V3(0.05, mx.Y - mn.Y + 0.27, 0.07), CF(fx, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2 + sy * ((mx.Z - mn.Z) / 2 + 0.12)), neon(gold))
					table.insert(st.leds, { p = p1, c = gold })
					table.insert(st.leds, { p = p2, c = gold })
				end
				K:text("BoardCrown", 2.6, 0.55, faceCF(V3(xL + 0.03, mx.Y + 0.55, (mn.Z + mx.Z) / 2), V3(1, 0, 0)), "★ KING OF SING ★", { fg = gold, glow = 2.0, font = F.FredokaOne, d = 0.02 })
				Props.trackLight(K, V3(xL + 2.2, 0, mn.Z - 0.4), V3(xL + 2.2, 0, mx.Z + 0.4), 2, { aim = V3(-1, -0.6, 0), look = Look.blackMetal })
			end
		end)
	end)

	-- 10) 방 현황판 (실시간: Booth_NN 의 KRenter) ---------------------------------------------------------------
	step(K, "status", function()
		local arch = first("ArchLintel")
		local bx = (if arch then arch.min.X else -6.1) - 1.95
		local y0, y1 = 3.6, 8.7
		local f0 = faceCF(V3(bx, 0, zB + 0.02), V3(0, 0, 1))
		local rows = {}
		K:free(function()
			K:plate("StatusFrame", 2.7, y1 - y0, 0.12, f0 * CF(0, (y0 + y1) / 2, 0), lk(rgb(20, 20, 24), M.Metal))
			K:plate("StatusScreen", 2.5, y1 - y0 - 0.2, 0.02, f0 * CF(0, (y0 + y1) / 2, 0.12), lk(rgb(8, 8, 18)))
			K:text("StatusTitle", 2.3, 0.42, f0 * CF(0, y1 - 0.38, 0.145), "ROOM 현황", { fg = WHITE, bg = rgb(150, 30, 120), glow = 1.4, font = F.GothamBlack, d = 0.004 })
			local rh = (y1 - y0 - 1.0) / 8
			for i = 1, 8 do
				local y = y1 - 0.75 - rh * (i - 0.5)
				local dot = K:plate("StatusDot", 0.2, 0.2, 0.03, f0 * CF(-0.95, y, 0.14), neon(NEONS.green))
				local _, lab = K:text("StatusRow", 1.8, rh * 0.72, f0 * CF(0.2, y, 0.145), string.format("ROOM %02d   빈 방", i), { fg = rgb(220, 230, 240), glow = 1.2, font = F.GothamBold, align = "Left", d = 0.004 })
				rows[i] = { dot = dot, lab = lab, last = "" }
			end
			K:text("StatusFoot", 2.3, 0.22, f0 * CF(0, y0 + 0.22, 0.145), "초록 = 빈 방 · 빨강 = 이용 중", { fg = rgb(160, 170, 190), glow = 1.0, font = F.GothamMedium, d = 0.004 })
		end)
		local booths: { [number]: Instance? } = {}
		local lastScan = -100
		Interact.anim(K, function(t: number)
			if t - lastScan > 5 then
				lastScan = t
				for i = 1, 8 do
					local m = V.model:FindFirstChild(string.format("Booth_%02d", i))
					booths[i] = m
				end
			end
			for i = 1, 8 do
				local r = rows[i]
				local m = booths[i]
				local busy = rented(m)
				local txt = string.format("ROOM %02d   %s", i, if busy then "이용 중" else "빈 방")
				if txt ~= r.last then
					r.last = txt
					if r.lab and r.lab.Parent then
						r.lab.Text = txt
					end
					if r.dot and r.dot.Parent then
						r.dot.Color = if busy then NEONS.red else NEONS.green
					end
				end
			end
		end)
	end)

	-- 11) 천장: 미러볼 네온 링 · 다운라이트 · 스프링클러 · 스피커 · 비상구 유도등 ------------------------------------------
	step(K, "ceiling", function()
		local ball = first("MirrorBall")
		K:free(function()
			if ball and not lo(K) then
				local c = V3(ball.c.X, H - 0.85, ball.c.Z)
				local rr = K:ring("BallRingLED", CF(c) * ANG(PI / 2, 0, 0), 3.4, 0.12, if hi(K) then 24 else 14, neon(PINK))
				for _, p in rr do
					table.insert(st.leds, { p = p, c = PINK })
				end
				if hi(K) then
					local r2 = K:ring("BallRingLED", CF(c + V3(0, 0.2, 0)) * ANG(PI / 2, 0, 0), 2.9, 0.08, 18, neon(CYAN))
					for _, p in r2 do
						table.insert(st.leds, { p = p, c = CYAN })
					end
				end
				for k = 0, 2 do
					local a = k * 2 * PI / 3 + 0.3
					local p = c + V3(math.cos(a) * 3.4, 0, math.sin(a) * 3.4)
					K:seg("BallRingCable", p, V3(p.X, H, p.Z), 0.03, lk(rgb(20, 20, 22)))
				end
				if rr[1] then
					addLight(K, st, rr[1], "PointLight", { Range = 18, Brightness = 0.8, Color = rgb(255, 120, 210) })
				end
			end
		end)
		-- T-bar 칸 가운데 (맵 그리드 사이)
		local xs, zs = {}, {}
		for _, r in V.byName.TBar or {} do
			if r.size.Z > r.size.X then
				table.insert(xs, r.c.X)
			else
				table.insert(zs, r.c.Z)
			end
		end
		table.sort(xs)
		table.sort(zs)
		local function cell(x: number, z: number): (number, number)
			-- 가장 가까운 칸 가운데
			local function mid(list: { number }, v: number, lo0: number, hi0: number): number
				local a, b = lo0, hi0
				for _, g in list do
					if g <= v then
						a = math.max(a, g)
					else
						b = math.min(b, g)
					end
				end
				return (a + b) / 2
			end
			return mid(xs, x, xL, xR), mid(zs, z, zB, zF)
		end
		local used = {}
		local function place(x: number, z: number, kind: string, light: boolean?)
			local cxx, czz = cell(x, z)
			local key = string.format("%.1f,%.1f", cxx, czz)
			if used[key] or not Common.ceilFree(K, cxx, czz, 0.5) then
				return
			end
			used[key] = true
			Common.useCeil(K, cxx, czz)
			if kind == "down" then
				Props.downlight(K, cxx, czz, { light = light, dia = 0.75, glow = Look.lampWarm, color = Look.warmLight, bright = 0.8, range = 13 })
			elseif kind == "spr" then
				Props.sprinkler(K, cxx + 0.4, czz)
			elseif kind == "spk" then
				K:free(function()
					K:disc("CeilSpeaker", 0.9, 0.06, CF(cxx, H - 0.03, czz), lk(rgb(236, 236, 232)))
					K:disc("CeilSpeakerGrille", 0.74, 0.07, CF(cxx, H - 0.035, czz), lk(rgb(200, 200, 200), M.DiamondPlate))
				end)
			elseif kind == "smoke" then
				Props.smokeDetector(K, cxx - 0.4, czz)
			end
		end
		local body = first("Body", "Counter")
		local cnx = if body then (body.min.X + body.max.X) / 2 else -13.3
		place(cnx - 3.6, -1.6, "down", true)
		place(cnx + 3.6, -1.6, "down", false)
		place(cnx, -1.6, "down", false)
		place(-13, 9.8, "down", true)
		place(-8.5, 9.8, "down", false)
		place(18.5, 7.5, "down", true)
		place(18.5, -6.5, "down", false)
		place(0, -10.2, "down", false)
		place(-4.4, -6.3, "spr")
		place(8.6, -6.3, "spr")
		place(12.9, 1.9, "spr")
		place(4.2, 6.0, "spr")
		place(-17.5, -10.2, "spr")
		place(21.6, -2.1, "spr")
		place(-21.7, 6.0, "spr")
		place(8.6, 10.0, "spk")
		place(-17.4, 1.9, "spk")
		place(4.2, -10.2, "smoke")
		place(-8.8, 1.9, "smoke")
		-- 비상구 유도등 (현관 안쪽 천장에 매달림, 실내를 봄)
		local door = V.door
		if door then
			K:free(function()
				local p = V3(door.x, H - 1.05, zF - 2.6)
				K:box("ExitHangBox", V3(1.8, 0.62, 0.18), CF(p), lk(rgb(240, 244, 240)))
				K:text("ExitHang", 1.7, 0.52, faceCF(p + V3(0, 0, -0.095), V3(0, 0, -1)), "비상구 EXIT", { fg = WHITE, bg = rgb(20, 170, 80), glow = 1.6, font = F.GothamBlack, d = 0.01 })
				for _, sx in { -1, 1 } do
					K:seg("ExitHangRod", p + V3(sx * 0.7, 0.31, 0), V3(p.X + sx * 0.7, H, p.Z), 0.04, CHROME)
				end
			end)
		end
	end)

	-- 12) 바닥 소품: X배너 2 · 우산꽂이 · 손소독기 스탠드 · 분리수거함 -------------------------------------------------
	step(K, "props", function()
		local door = V.door or { x = 11.7, w = 10, z = zF }
		local dl = door.x - (door.w or 10) / 2 - 2
		local function xbanner(pcf: CFrame, title: string, body: string, col: Color3)
			if not K:spot(pcf, V3(1.9, 6.0, 0.9), 0.05) then
				return
			end
			K:box("XBannerFoot", V3(1.6, 0.06, 0.12), pcf * CF(0, 0.03, 0), lk(rgb(30, 30, 34), M.Metal))
			K:box("XBannerFoot", V3(0.12, 0.06, 0.8), pcf * CF(0, 0.03, 0), lk(rgb(30, 30, 34), M.Metal))
			for _, sx in { -1, 1 } do
				K:seg("XBannerRod", (pcf * V3(0, 0.1, -0.02)), (pcf * V3(sx * 0.82, 5.9, -0.04)), 0.04, lk(rgb(40, 40, 44), M.Metal))
				K:seg("XBannerRod", (pcf * V3(0, 0.1, -0.02)), (pcf * V3(sx * 0.82, 0.25, -0.04)), 0.04, lk(rgb(40, 40, 44), M.Metal))
			end
			local d0 = pcf * CF(0, 3.05, 0)
			K:plate("XBannerSheet", 1.7, 5.6, 0.02, d0, lk(col))
			K:text("XBannerTitle", 1.5, 1.2, d0 * CF(0, 1.9, 0.025), title, { fg = WHITE, font = F.GothamBlack, d = 0.004 })
			K:text("XBannerBody", 1.5, 3.4, d0 * CF(0, -0.6, 0.025), body, { fg = rgb(255, 245, 210), font = F.GothamBold, d = 0.004 })
		end
		local t1 = {}
		for i = 1, 4 do
			local k = (i * 3) % #SONGS + 1
			table.insert(t1, string.format("%s\n%s", SONGS[k], ARTISTS[k]))
		end
		xbanner(CF(math.min(dl - 1.6, 2.4), 0, zF - 3.1) * ANG(0, PI / 2, 0), "NEW!\n10월 신곡", table.concat(t1, "\n\n"), rgb(150, 20, 120))
		xbanner(CF(4.8, 0, zB + 3.2) * ANG(0, -0.35, 0), "오늘의\n노래왕 도전", "점수 90점 이상\n인기도 UP!\n\n최고 점수는\n로비 보드에\n표시돼요", rgb(20, 70, 160))
		-- 우산꽂이 (현관 옆)
		local ux = math.min(dl - 0.7, 4.0)
		local up = CF(ux, 0, zF - 1.4)
		if K:spot(up, V3(1.0, 2.6, 1.0), 0.02) then
			K:vcyl("UmbrellaStand", 2.0, 0.9, up * CF(0, 1.0, 0), Look.steel)
			K:vcyl("UmbrellaStandRim", 0.08, 0.96, up * CF(0, 2.0, 0), CHROME)
			for k = 0, 2 do
				local a = k * 2.1
				K:seg("Umbrella", up * V3(math.cos(a) * 0.2, 0.2, math.sin(a) * 0.2), up * V3(math.cos(a) * 0.32, 3.0, math.sin(a) * 0.32), 0.14, lk(({ rgb(30, 30, 36), rgb(40, 90, 180), rgb(200, 40, 60) })[k + 1], M.Fabric))
				K:seg("UmbrellaHandle", up * V3(math.cos(a) * 0.32, 3.0, math.sin(a) * 0.32), up * V3(math.cos(a) * 0.45, 3.15, math.sin(a) * 0.45), 0.08, lk(rgb(80, 50, 30)))
			end
			K:text("UmbrellaLabel", 0.6, 0.22, faceCF((up * V3(0, 1.4, 0.455)), V3(0, 0, 1)), "우산", { fg = WHITE, bg = rgb(40, 40, 46), font = F.GothamBold, d = 0.01 })
		end
		-- 손소독기 스탠드
		local sp = CF(ux, 0, zF - 3.3)
		if K:spot(sp, V3(1.0, 4.4, 1.0), 0.02) then
			K:disc("SanitizerStandBase", 0.9, 0.08, sp * CF(0, 0.04, 0), lk(rgb(240, 240, 236)))
			K:vcyl("SanitizerStandPole", 3.2, 0.14, sp * CF(0, 1.68, 0), lk(rgb(240, 240, 236)))
			K:rbox("SanitizerBox", V3(0.4, 0.9, 0.55), 0.08, sp * CF(0, 3.65, 0.05) * ANG(0, PI / 2, 0), lk(rgb(250, 250, 248)))
			K:plate("SanitizerWindow", 0.3, 0.3, 0.02, faceCF((sp * V3(0, 3.75, 0.27)), V3(0, 0, 1)), lk(rgb(150, 200, 240), M.Glass, { t = 0.3 }))
			K:text("SanitizerLabel", 0.5, 0.24, faceCF((sp * V3(0, 3.35, 0.27)), V3(0, 0, 1)), "손 소독", { fg = rgb(20, 120, 200), font = F.GothamBlack, d = 0.004 })
			K:box("SanitizerDrip", V3(0.3, 0.04, 0.3), sp * CF(0, 3.15, 0.15), lk(rgb(200, 200, 200)))
		end
		-- 분리수거함 3칸 (아치 오른쪽)
		local arch = first("ArchLintel")
		local bx0 = (if arch then arch.max.X else 6.1) + 0.9
		local bins = { { "일반", rgb(80, 80, 86) }, { "캔 · 병", rgb(40, 120, 200) }, { "플라스틱", rgb(240, 180, 30) } }
		for k, b in bins do
			local bp = CF(bx0 + (k - 0.5) * 1.0, 0, zB + 0.55)
			if K:spot(bp, V3(0.95, 2.8, 0.95), 0.0) then
				K:box("RecycleBin", V3(0.92, 2.5, 0.92), bp * CF(0, 1.25, 0), lk(b[2]))
				K:box("RecycleBinLid", V3(0.96, 0.18, 0.96), bp * CF(0, 2.59, 0), lk(dk(b[2], 0.3)))
				K:plate("RecycleBinSlot", 0.5, 0.12, 0.02, faceCF((bp * V3(0, 2.3, 0.46)), V3(0, 0, 1)), lk(rgb(10, 10, 10)))
				K:text("RecycleBinLabel", 0.8, 0.3, faceCF((bp * V3(0, 1.7, 0.46)), V3(0, 0, 1)), b[1], { fg = WHITE, font = F.GothamBlack, d = 0.004 })
			end
		end
	end)

	-- 13) 게시물: 등록증 · 청소년 출입시간 · 요금 변경 안내 (맵 간판 바로 옆) · 이벤트 라이트박스 · 비상벨 -----------------------
	step(K, "notices", function()
		local zN = math.min(zF - 3.0, 8.9)
		-- 왼벽 앞쪽
		Props.frame(K, wcf("L", zN, 6.4, 0.02), 1.4, 1.9, { frame = Look.goldMetal, text = "노래연습장업\n등록증\n\n광안 코인노래연습장\n\n부산광역시 수영구청장", fg = rgb(40, 40, 40), textH = 0.92, border = 0.07, depth = 0.05 })
		K:text("YouthNotice", 1.9, 1.15, wcf("L", zN, 4.35, 0.02), "청소년 출입시간 안내\n09:00 ~ 22:00\n(보호자 동반 시 제외)", { fg = rgb(30, 30, 36), bg = rgb(255, 236, 120), font = F.GothamBold, d = 0.03 })
		K:text("CCTVNotice", 1.3, 0.5, wcf("L", zN, 3.42, 0.02), "CCTV 녹화 중 · 24시간 무인", { fg = WHITE, bg = rgb(190, 30, 40), font = F.GothamBlack, d = 0.03 })
		-- 오른벽: 가격 간판 아래 요금 변경 안내
		local sign = nil
		for _, r in V.parts do
			if string.sub(r.name, 1, 5) == "Sign_" and r.c.X > xR - 1 and r.size.Z > 4 then
				sign = r
			end
		end
		if sign then
			local zc = (sign.min.Z + sign.max.Z) / 2
			local y = math.max(3.25, sign.min.Y - 0.55)
			K:free(function()
				K:text("PriceUpdate", math.min(5.6, sign.max.Z - sign.min.Z), 0.75, wcf("R", zc, y, 0.08), "※ 요금 변경 안내: 곡당 요금 → 시간제\n30분 500원 · 이용 중 자동 연장", { fg = rgb(20, 20, 26), bg = rgb(255, 230, 90), font = F.GothamBold, d = 0.02 })
			end)
		end
		-- 뒷벽: '이용 안내' 아래 같은 안내 + 오른쪽 이벤트 라이트박스 + 비상벨
		local guide = nil
		for _, r in V.parts do
			if r.name == "Sign_이용 안내" then
				guide = r
			end
		end
		K:free(function()
			if guide then
				local gx = (guide.min.X + guide.max.X) / 2
				K:text("GuideUpdate", guide.max.X - guide.min.X, 0.7, wcf("B", gx, math.max(2.3, guide.min.Y - 0.5), 0.13), "※ 지금은 시간제 운영 (30분 500원)\n방 잡기 = 복도 문 옆 패널", { fg = rgb(20, 20, 26), bg = rgb(255, 230, 90), font = F.GothamBold, d = 0.02 })
			end
			local arch = first("ArchLintel")
			local ex = (if arch then arch.max.X else 6.1) + 2.2
			local d0 = wcf("B", ex, 6.0, 0.02)
			K:plate("EventBox", 2.6, 3.6, 0.2, d0, lk(rgb(20, 20, 24), M.Metal))
			local p = K:text("EventBoxFace", 2.4, 3.4, d0 * CF(0, 0, 0.21), "★ EVENT ★\n\n생일 · 기념일\n축하곡 예약 OK\n\n점수 100점\n인증샷 환영!", { fg = WHITE, bg = rgb(120, 30, 160), glow = 1.3, font = F.GothamBlack, d = 0.02 })
			local _ = p
			Props.fireBell(K, wcf("B", xR - 1.4, 5.0, 0.02))
			K:text("FireBellLabel", 1.2, 0.3, wcf("B", xR - 1.4, 5.75, 0.02), "비상벨 · 소화전", { fg = WHITE, bg = rgb(190, 30, 30), font = F.GothamBold, d = 0.02 })
		end)
	end)

	-- 실시간: 교환기 지폐 LED 깜빡임 · 살균기 카운트다운 · 링 색 숨쉬기
	Interact.anim(K, function(t: number)
		if st.changerLED and st.changerLED.Parent then
			st.changerLED.Transparency = if math.floor(t * 2) % 2 == 0 then 0 else 0.7
		end
		local s = st.ster
		if s and s.lab and s.lab.Parent then
			local left = if s.t0 >= 0 then 10 - (os.clock() - s.t0) else -1
			if left > 0 then
				s.lab.Text = string.format("UV 살균 중 · %d초", math.ceil(left))
				if s.uv and s.uv.Parent then
					s.uv.Transparency = 0
					s.uv.Color = rgb(160, 90, 255)
				end
			else
				if s.t0 >= 0 and left > -4 then
					s.lab.Text = "살균 완료 ✓"
				else
					s.lab.Text = "UV 살균기 · 대기"
				end
				if s.uv and s.uv.Parent then
					s.uv.Transparency = 0.35
					s.uv.Color = rgb(120, 70, 220)
				end
			end
		end
	end)
end
T.lobby = lobbyBuild

-- =====================================================================================================
-- 복도 (kcorridor)
-- =====================================================================================================
local POSTERS = {
	{ "NEW", "광안대교 불빛 아래", "파도청년단 · 발라드", rgb(30, 50, 150) },
	{ "HOT", "민락동 치킨송", "바삭즈 · 댄스", rgb(210, 70, 30) },
	{ "TOP 3", "해운대 말고 광안리", "수영구 청년회 · 시티팝", rgb(10, 120, 130) },
	{ "★ 100점", "오늘의 노래왕 도전", "최고 점수는 로비 보드에", rgb(110, 30, 160) },
	{ "축하곡", "생일 축하해 친구야", "노래방 오리지널", rgb(200, 40, 120) },
	{ "트로트", "갈매기 트로트", "김부산 · 신곡", rgb(30, 130, 60) },
	{ "ROCK", "2호선 막차", "금련산 밴드 · 록", rgb(150, 20, 30) },
	{ "EDM", "득근득근", "헬스보이즈 · EDM", rgb(20, 90, 190) },
}
local INFO_PAGES = {
	"이용 안내\n① 초록불 방 · 문 옆 패널 터치 → 방 잡기\n② 30분 500원 · 이용 중 자동 연장\n③ 화면 아래 버튼으로 노래 선택",
	"요금 안내\n30분 500원 (자동 연장)\n동전 교환: 로비 지폐 교환기\n음료: 로비 자판기",
	"비상 대피\n비상구 · 화장실: 복도 끝 ↑\n소화기: 복도 벽 소화기함\n화재 시 엘리베이터 사용 금지",
	"분실물 · 문의\n분실물은 카운터 보관\n24시간 무인 운영 · CCTV 녹화 중\n복도에서는 뛰지 마세요",
}

local function corridorBuild(K: any, V: any, S: any)
	local H = S.ceilY or V.H
	local st: any = { leds = {}, lights = {} }
	local xLw, xRw = V.x0, V.x1
	-- 벽 마디 (CorridorWall) 와 문 구멍
	local segs = { [-1] = {}, [1] = {} }
	for _, r in V.byName.CorridorWall or {} do
		if r.size.Z > r.size.X then
			local sd = if r.c.X < 0 then -1 else 1
			table.insert(segs[sd], { a = r.min.Z, b = r.max.Z, r = r })
			if sd < 0 then
				xLw = math.max(xLw, r.max.X)
			else
				xRw = math.min(xRw, r.min.X)
			end
		end
	end
	local doorTop = 8.55
	for _, r in V.byName.CorridorWallLintel or {} do
		doorTop = math.min(doorTop, r.min.Y)
	end
	local openings = {}
	for _, sd in { -1, 1 } do
		table.sort(segs[sd], function(p, q)
			return p.a < q.a
		end)
		for i = 1, #segs[sd] - 1 do
			local a, b = segs[sd][i].b, segs[sd][i + 1].a
			if b - a > 3 then
				table.insert(openings, { sd = sd, a = a, b = b })
			end
		end
	end
	local panels = {}
	for _, r in V.byName.KaraokePanel or {} do
		table.insert(panels, r)
	end
	local function wx(sd: number, off: number): number
		return if sd < 0 then xLw + off else xRw - off
	end
	local function wcf(sd: number, z: number, y: number, off: number): CFrame
		return faceCF(V3(wx(sd, off), y, z), V3(-sd, 0, 0))
	end
	local function wp(name: string, sd: number, a: number, b: number, y0: number, y1: number, d: number, off: number, look: any): BasePart
		return K:plate(name, b - a, y1 - y0, d, wcf(sd, (a + b) / 2, (y0 + y1) / 2, off), look)
	end
	local PINK, CYAN = NEONS.pink, NEONS.cyan

	-- 1) 벽 마디: 징두리 · 캡 · LED 줄 · 포스터 라이트박스 · 패널 아래 안내 스티커 ------------------------------------
	local posterI = 0
	local special = {} -- 마디별 특수 소품 자리
	step(K, "walls", function()
		K:free(function()
			for _, sd in { -1, 1 } do
				for si, sg in segs[sd] do
					local len = sg.b - sg.a
					if len >= 3 then
						local a, b = sg.a + 0.25, sg.b - 0.25
						wp("CorrWainscot", sd, a, b, 0.0, 3.0, 0.05, 0.02, GLOSS)
						wp("CorrWainscotCap", sd, a, b, 3.0, 3.08, 0.1, 0.02, CHROME)
						local led = wp("CorrWainscotLED", sd, a + 0.1, b - 0.1, 2.88, 2.92, 0.08, 0.02, neon(if sd < 0 then PINK else CYAN))
						table.insert(st.leds, { p = led, c = if sd < 0 then PINK else CYAN })
						wp("CorrUpperBand", sd, a, b, 9.1, H - 0.05, 0.03, 0.01, lk(rgb(26, 18, 40), M.Fabric))
						-- 이 마디의 패널
						local pz = nil
						for _, p in panels do
							if math.abs(p.c.X - wx(sd, 0)) < 0.6 and p.c.Z > sg.a and p.c.Z < sg.b then
								pz = p
							end
						end
						if pz then
							K:text("PanelHint", 1.15, 0.62, wcf(sd, pz.c.Z, 3.55, 0.02), "터치 → 방 잡기\n30분 500원", { fg = WHITE, bg = rgb(30, 24, 44), font = F.GothamBold, d = 0.03 })
						end
						-- 포스터 자리: 패널에서 먼 쪽
						if len >= 5 then
							local zc
							local pw = 2.2
							if pz then
								if pz.c.Z - sg.a < sg.b - pz.c.Z then
									zc = pz.c.Z + 0.55 + 0.4 + pw / 2
									special[#special + 1] = { sd = sd, a = zc + pw / 2 + 0.3, b = sg.b - 0.3, seg = si }
								else
									zc = pz.c.Z - 0.55 - 0.4 - pw / 2
									special[#special + 1] = { sd = sd, a = sg.a + 0.3, b = zc - pw / 2 - 0.3, seg = si }
								end
							else
								zc = (sg.a + sg.b) / 2
							end
							posterI += 1
							local P = POSTERS[(posterI - 1) % #POSTERS + 1]
							local d0 = wcf(sd, zc, 5.75, 0.02)
							K:plate("PosterBox", 2.2, 3.4, 0.16, d0, lk(rgb(16, 16, 20), M.Metal))
							K:plate("PosterFace", 2.0, 3.2, 0.02, d0 * CF(0, 0, 0.16), lk(P[4]))
							K:text("PosterTag", 1.3, 0.5, d0 * CF(0, 1.2, 0.185), P[1], { fg = rgb(255, 230, 90), glow = 1.6, font = F.FredokaOne, d = 0.004 })
							K:text("PosterTitle", 1.85, 1.2, d0 * CF(0, 0.15, 0.185), P[2], { fg = WHITE, glow = 1.5, font = F.GothamBlack, d = 0.004, wrap = true })
							K:text("PosterSub", 1.85, 0.36, d0 * CF(0, -0.92, 0.185), P[3], { fg = rgb(230, 230, 240), glow = 1.2, font = F.GothamBold, d = 0.004 })
							K:text("PosterFoot", 1.85, 0.2, d0 * CF(0, -1.4, 0.185), "광안 코인노래연습장 · 2026", { fg = rgb(200, 200, 210), glow = 1.0, font = F.GothamMedium, d = 0.004 })
							local e = K:plate("PosterLED", 2.26, 0.05, 0.17, d0 * CF(0, 1.73, 0), neon(if sd < 0 then PINK else CYAN))
							table.insert(st.leds, { p = e, c = if sd < 0 then PINK else CYAN })
							-- 포스터 조명 (벽 팔 + 헤드)
							local arm0 = wcf(sd, zc, 7.95, 0.0)
							K:plate("PosterLampPlate", 0.3, 0.2, 0.04, arm0, lk(rgb(20, 20, 24), M.Metal))
							K:seg("PosterLampArm", arm0 * V3(0, 0, 0.04), arm0 * V3(0, 0.12, 0.62), 0.05, lk(rgb(20, 20, 24), M.Metal))
							K:cyl("PosterLampHead", 0.9, 0.16, arm0 * CF(0, 0.1, 0.66) * ANG(0, 0, math.rad(-12)), lk(rgb(20, 20, 24), M.Metal))
							K:box("PosterLampLens", V3(0.82, 0.02, 0.08), arm0 * CF(0, 0.02, 0.66), Look.lampWarm)
							if posterI % 3 == 0 then
								K:text("CorrSticker", 1.0, 0.36, wcf(sd, zc, 3.5, 0.02), if posterI % 2 == 0 then "금연 · NO SMOKING" else "CCTV 녹화 중", { fg = WHITE, bg = rgb(190, 30, 40), font = F.GothamBlack, d = 0.02 })
							end
						end
					end
				end
			end
		end)
	end)

	-- 2) 문 구멍 리빌 (검은 알루미늄) + 문턱 · 바닥 방 번호 -------------------------------------------------------------
	step(K, "doors", function()
		K:free(function()
			for _, o in openings do
				local x0w = wx(o.sd, 0)
				local x1w = x0w + o.sd * 0.4
				local xm = (x0w + x1w) / 2
				local alu = lk(rgb(30, 30, 34), M.Metal)
				K:box("DoorReveal", V3(0.42, doorTop, 0.04), CF(xm, doorTop / 2, o.a + 0.02), alu)
				K:box("DoorReveal", V3(0.42, doorTop, 0.04), CF(xm, doorTop / 2, o.b - 0.02), alu)
				K:box("DoorRevealHead", V3(0.42, 0.04, o.b - o.a), CF(xm, doorTop - 0.02, (o.a + o.b) / 2), alu)
				K:box("DoorThreshold", V3(0.44, 0.05, o.b - o.a - 0.06), CF(xm, 0.02, (o.a + o.b) / 2), Look.brushed)
				-- 바닥 방 번호 (문 앞)
				local no = nil
				for _, p in panels do
					if math.abs(p.c.X - x0w) < 0.6 and math.abs(p.c.Z - (o.a + o.b) / 2) < 5 then
						no = tonumber(p.part:GetAttribute("RoomNo"))
					end
				end
				if no then
					local up = V3(o.sd, 0, 0)
					K:text("FloorRoomNo", 1.3, 0.8, topCF(V3(wx(o.sd, 1.55), 0.012, (o.a + o.b) / 2), up), string.format("%02d", no), { fg = rgb(200, 200, 230), glow = 1.1, font = F.GothamBlack, d = 0.004, free = true })
				end
			end
		end)
	end)

	-- 3) 바닥 러너 무늬 (테두리 띠 · 다이아몬드) ----------------------------------------------------------------
	step(K, "floor", function()
		local run = V:first("CorridorRunner")
		if not run then
			return
		end
		local mn, mx = run.min, run.max
		local zc = (mn.Z + mx.Z) / 2
		K:free(function()
			for _, sx in { -1, 1 } do
				local x = (if sx < 0 then mn.X else mx.X) - sx * 0.5
				K:box("RunnerBorder", V3(0.32, 0.012, mx.Z - mn.Z - 0.6), CF(x, mx.Y + 0.006, zc), lk(rgb(80, 30, 100), M.Carpet))
				K:box("RunnerBorderLine", V3(0.06, 0.014, mx.Z - mn.Z - 0.6), CF(x - sx * 0.3, mx.Y + 0.007, zc), lk(rgb(170, 120, 60), M.Carpet))
			end
			local n = math.floor((mx.Z - mn.Z) / 6)
			for i = 0, n - 1 do
				local z = mn.Z + 3 + i * 6
				K:box("RunnerDiamond", V3(1.3, 0.012, 1.3), CF((mn.X + mx.X) / 2, mx.Y + 0.006, z) * ANG(0, PI / 4, 0), lk(rgb(170, 120, 60), M.Carpet))
				K:box("RunnerDiamondIn", V3(0.8, 0.014, 0.8), CF((mn.X + mx.X) / 2, mx.Y + 0.007, z) * ANG(0, PI / 4, 0), lk(rgb(60, 24, 80), M.Carpet))
			end
		end)
	end)

	-- 4) 천장: 벽쪽 소핏 · 다운라이트 · 스피커 · CCTV · 유도등 2 · 환기구 -----------------------------------------------
	step(K, "ceiling", function()
		K:free(function()
			for _, sd in { -1, 1 } do
				K:box("CorrSoffit", V3(0.55, 0.45, V.D - 0.1), CF(wx(sd, 0.275), H - 0.225, (V.z0 + V.z1) / 2), LACQ)
				local p = K:box("CorrSoffitLED", V3(0.05, 0.05, V.D - 0.3), CF(wx(sd, 0.56), H - 0.42, (V.z0 + V.z1) / 2), neon(rgb(150, 90, 255)))
				table.insert(st.leds, { p = p, c = rgb(150, 90, 255) })
			end
		end)
		local nl = 0
		for _, z in { -20, -14, -7, 7, 14, 20 } do
			if Common.ceilFree(K, 0, z, 0.5) then
				nl += 1
				Props.downlight(K, 0, z, { light = nl % 2 == 1, dia = 0.6, glow = Look.lampWarm, color = Look.warmLight, bright = 0.7, range = 12 })
				Common.useCeil(K, 0, z)
			end
		end
		K:free(function()
			for _, z in { -10, 10 } do
				if Common.ceilFree(K, -1.6, z, 0.5) then
					K:disc("CeilSpeaker", 0.8, 0.06, CF(-1.6, H - 0.03, z), lk(rgb(30, 30, 34)))
					K:disc("CeilSpeakerGrille", 0.66, 0.07, CF(-1.6, H - 0.035, z), lk(rgb(60, 60, 66), M.DiamondPlate))
					Common.useCeil(K, -1.6, z)
				end
			end
			for _, z in { -18, 18 } do
				if Common.ceilFree(K, 1.6, z, 0.5) then
					K:box("CeilVent", V3(1.2, 0.04, 0.8), CF(1.6, H - 0.02, z), lk(rgb(40, 40, 44)))
					for k = 0, 3 do
						K:box("CeilVentSlot", V3(1.0, 0.05, 0.06), CF(1.6, H - 0.025, z - 0.27 + k * 0.18), lk(rgb(10, 10, 12)))
					end
					Common.useCeil(K, 1.6, z)
				end
			end
			-- 유도등 (매달린 양면)
			for k, z in { V.z0 + 1.2, V.z1 - 1.6 } do
				local p = V3(0, H - 1.0, z)
				K:box("ExitHangBox", V3(1.9, 0.62, 0.18), CF(p), lk(rgb(240, 244, 240)))
				local txt = if k == 1 then "↑ 비상구 · 화장실" else "↑ 출구 · 로비"
				local n = if k == 1 then V3(0, 0, 1) else V3(0, 0, -1)
				K:text("ExitHang", 1.8, 0.52, faceCF(p + n * 0.095, n), txt, { fg = WHITE, bg = rgb(20, 170, 80), glow = 1.6, font = F.GothamBlack, d = 0.01 })
				for _, sx in { -1, 1 } do
					K:seg("ExitHangRod", p + V3(sx * 0.75, 0.31, 0), V3(sx * 0.75, H, p.Z), 0.04, CHROME)
				end
			end
		end)
		if Common.ceilFree(K, 4.2, V.z1 - 2.5, 0.5) then
			Props.cctv(K, 4.2, V.z1 - 2.5)
		end
		if Common.ceilFree(K, -4.2, V.z0 + 2.5, 0.5) then
			Props.cctv(K, -4.2, V.z0 + 2.5)
		end
	end)

	K:note(string.format("corr segs L=%d R=%d openings=%d panels=%d special=%d posters=%d", #segs[-1], #segs[1], #openings, #panels, #special, posterI))
	for _, sp in special do
		K:note(string.format("  special sd=%d %.2f..%.2f", sp.sd, sp.a, sp.b))
	end
	-- 5) 특수 소품: 안내 터치스크린 (페이지) · 손 소독기 · 소화기함 · 피난안내도 · 네온 음표 ----------------------------------
	step(K, "special", function()
		-- 로비 쪽에 가까운 자리부터
		table.sort(special, function(p, q)
			return (p.a + p.b) > (q.a + q.b)
		end)
		local used = 0
		local function take(minW: number, sd: number?): any?
			for i, s in special do
				if not s.used and s.b - s.a >= minW and (sd == nil or s.sd == sd) then
					s.used = true
					used += 1
					local _ = i
					return s
				end
			end
			return nil
		end
		-- 안내 터치스크린
		local s1 = take(1.6)
		if s1 then
			local zc = (s1.a + s1.b) / 2
			local d0 = wcf(s1.sd, zc, 5.1, 0.02)
			local scr: BasePart? = nil
			local lab: TextLabel? = nil
			K:free(function()
				K:plate("InfoKioskBody", 1.5, 2.5, 0.16, d0, lk(rgb(20, 20, 24), M.Metal))
				scr = K:plate("InfoKioskScreen", 1.32, 2.1, 0.02, d0 * CF(0, 0.1, 0.16), lk(rgb(10, 14, 30)))
				local _, l = K:text("InfoKioskText", 1.24, 1.9, d0 * CF(0, 0.1, 0.185), INFO_PAGES[1], { fg = rgb(220, 235, 255), glow = 1.4, font = F.GothamBold, d = 0.004, wrap = true })
				lab = l
				K:text("InfoKioskTitle", 1.3, 0.16, d0 * CF(0, -1.08, 0.165), "TOUCH · 안내", { fg = rgb(170, 200, 255), font = F.GothamBold, d = 0.004 })
			end)
			if scr then
				local page = 1
				Interact.prompt(K, scr :: BasePart, {
					action = "다음 안내 보기",
					object = "안내 화면",
					fn = function()
						page = page % #INFO_PAGES + 1
						if lab and lab.Parent then
							lab.Text = INFO_PAGES[page]
						end
					end,
				})
			end
		end
		-- 손 소독기 (벽걸이 자동)
		local s2 = take(1.0, if s1 then -s1.sd else nil) or take(1.0)
		if s2 then
			local zc = (s2.a + s2.b) / 2
			local d0 = wcf(s2.sd, zc, 4.7, 0.02)
			local body: BasePart? = nil
			local foam: BasePart? = nil
			local led: BasePart? = nil
			local foamCF = d0 * CF(0, -0.62, 0.22)
			K:free(function()
				body = K:plate("SanitizerUnit", 0.62, 0.95, 0.36, d0, lk(rgb(248, 248, 246)))
				K:plate("SanitizerUnitWindow", 0.3, 0.3, 0.02, d0 * CF(0, 0.15, 0.36), lk(rgb(120, 190, 240), M.Glass, { t = 0.3 }))
				K:text("SanitizerUnitLabel", 0.5, 0.16, d0 * CF(0, -0.15, 0.365), "손 소독제", { fg = rgb(20, 110, 200), font = F.GothamBlack, d = 0.004 })
				led = K:plate("SanitizerUnitLED", 0.06, 0.06, 0.37, d0 * CF(0.2, 0.36, 0), Look.ledBlue)
				K:plate("SanitizerNozzle", 0.14, 0.08, 0.3, d0 * CF(0, -0.5, 0), lk(rgb(200, 200, 204)))
				K:plate("SanitizerDripTray", 0.5, 0.06, 0.5, d0 * CF(0, -1.55, 0), lk(rgb(200, 200, 204)))
				foam = K:ball("SanitizerFoam", 0.2, foamCF, lk(rgb(250, 252, 255), M.SmoothPlastic, { t = 1 }))
			end)
			if body then
				Interact.prompt(K, body :: BasePart, {
					action = "손 소독하기",
					object = "손 소독기",
					fn = function()
						local f = foam
						if f and f.Parent then
							f.Transparency = 0.05
							f.Size = V3(0.08, 0.08, 0.08)
							f.CFrame = K.cf * foamCF
							TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(0.32, 0.26, 0.32), CFrame = K.cf * foamCF * CF(0, -0.12, 0) }):Play()
							task.delay(2.5, function()
								if f.Parent then
									TweenService:Create(f, TweenInfo.new(0.6), { Transparency = 1 }):Play()
								end
							end)
						end
						if led and led.Parent then
							led.Color = NEONS.green
							task.delay(1.5, function()
								if led and led.Parent then
									led.Color = NEONS.blue
								end
							end)
						end
					end,
				})
			end
		end
		-- 소화기함 (먼 쪽)
		table.sort(special, function(p, q)
			return (p.a + p.b) < (q.a + q.b)
		end)
		local s3 = take(1.4)
		if s3 then
			local zc = (s3.a + s3.b) / 2
			local d0 = wcf(s3.sd, zc, 1.75, 0.07)
			K:free(function()
				K:plate("ExtCabinet", 1.2, 3.0, 0.3, d0, lk(rgb(200, 30, 36), M.Metal))
				K:plate("ExtCabinetGlass", 0.9, 2.2, 0.02, d0 * CF(0, -0.1, 0.3), lk(rgb(220, 230, 236), M.Glass, { t = 0.6 }))
				K:vcyl("ExtInCabinet", 1.5, 0.5, CF((d0 * V3(0, -0.4, 0.15))), lk(rgb(210, 30, 36), M.Metal))
				K:text("ExtCabinetLabel", 1.0, 0.3, d0 * CF(0, 1.25, 0.305), "소화기", { fg = WHITE, bg = rgb(160, 20, 26), font = F.GothamBlack, d = 0.01 })
				K:text("ExtCabinetSign", 1.2, 0.5, d0 * CF(0, 1.95, 0.0), "소화기 ↓", { fg = WHITE, bg = rgb(200, 30, 36), glow = 1.2, font = F.GothamBlack, d = 0.04 })
			end)
		end
		-- 피난안내도
		local s4 = take(1.4)
		if s4 then
			local zc = (s4.a + s4.b) / 2
			K:free(function()
				local d0 = wcf(s4.sd, zc, 5.6, 0.02)
				K:plate("EvacMapFrame", 1.5, 1.2, 0.05, d0, Look.goldMetal)
				K:text("EvacMap", 1.4, 1.1, d0 * CF(0, 0, 0.055), "피난안내도\n현위치: 복도\n↑ 비상구 · ↓ 로비 출구", { fg = rgb(20, 120, 60), bg = rgb(250, 250, 246), font = F.GothamBold, d = 0.01 })
			end)
		end
		-- 남은 자리: 네온 음표 아트
		for _, s in special do
			if not s.used and s.b - s.a >= 1.2 then
				s.used = true
				local zc = (s.a + s.b) / 2
				local col = if s.sd < 0 then PINK else CYAN
				K:free(function()
					local p = K:text("NeonNotes", math.min(1.6, s.b - s.a - 0.2), 1.4, wcf(s.sd, zc, 6.0, 0.03), if (math.floor(zc) % 2 == 0) then "♪" else "♫", { fg = col, glow = 2.4, font = F.GothamBlack, d = 0.02 })
					local _ = p
				end)
			end
		end
	end)

	applyMode({ leds = st.leds, stars = {}, lights = {}, mode = 1 }, 0)
end
T.corridor = corridorBuild

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
