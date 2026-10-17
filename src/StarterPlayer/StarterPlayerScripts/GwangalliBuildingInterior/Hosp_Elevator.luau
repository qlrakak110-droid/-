--!strict
-- GwangalliBuildingInterior/Hosp_Elevator: 진짜로 타는 엘리베이터 1F · 2F · R (설계 §7.3).
--   * 층마다 승강로 마감(벽 · 석재 마감 · 스테인리스 문틀) + 미닫이 승강장 문 2 짝 + 홀 표시등 + 호출 버튼
--   * 옥상에는 새 승강기 탑(펜트하우스)
--   * 카(cabin) 모델 하나가 층 사이를 오감: 문이 닫힌 채 도착하는 순간 카와 탑승자를 같은 렌더 프레임에
--     수직으로 옮겨서 끊김 없이 이어짐 (페이드 없음)
--   * 조작반(화면 UI): 1 · 2 · R · 열림 · 닫힘 · 비상, PC 숫자키 1 · 2 · 3, 패드, 터치
--   * 병원 NPC 가 엘리베이터 앞(lift1/lift2)에 오면 호출, 다른 층에 나타나면 그 층에서 문이 열림
-- 좌표: 병원 프레임 HF. 층 바닥 0 / 14.15 / 25.20.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Lib = require(script.Parent:WaitForChild("Hosp_Lib"))
local Look = require(script.Parent:WaitForChild("Look"))
local Interact = require(script.Parent:WaitForChild("Interact"))

local E = {}

local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C3 = Color3.fromRGB

local Geo = Lib.Geo
local C = Geo.C
local SND = Geo.SND
local LV = Geo.LEVELS
local LIFT = Geo.LIFT
local LABEL = { "1", "2", "R" }
local FLOOR_TOAST = { "1층입니다", "2층입니다 · 입원실 · 건강검진센터", "옥상입니다 · 옥상 정원" }

local LK = {
	plaster = Look.of(222, 218, 208, M.Plaster),
	stone = Look.of(214, 210, 204, M.Marble),
	concrete = Look.of(184, 182, 176, M.Concrete),
	trim = Look.of(196, 198, 202, M.Metal, { r = 0.15 }),
	leaf = Look.of(160, 163, 168, M.Metal, { r = 0.1 }),
	sill = Look.of(176, 178, 182, M.Metal),
	granite = Look.of(90, 92, 96, M.Granite),
	steel = Look.steel,
	hairline = Look.of(170, 172, 176, M.Metal, { r = 0.06 }),
	champagne = Look.of(190, 182, 170, M.Metal, { r = 0.08 }),
	chrome = Look.chrome,
	blackGlass = Look.of(14, 14, 16, M.Glass, { t = 0.05, r = 0.2 }),
	white = Look.white,
	led = Look.neon(C3(255, 244, 228)),
	amber = Look.neon(C3(255, 176, 60)),
	ringOff = Look.of(232, 234, 236, M.SmoothPlastic),
	louver = Look.of(120, 124, 128, M.Metal),
}

local function solid(l: any): any
	local t = table.clone(l)
	t.collide = true
	t.shadow = true
	t.free = true
	return t
end

-- 승강장 하나 (f = 1, 2, 3). 반환: { leaves = mover L, R, lantern label, ring parts, call part }
local function landing(K: any, f: number): any
	local y = LV[f]
	local hh = LIFT.height[f]
	local zb = LIFT.backZ[f]
	local low = K.detail == "low"
	local out: any = { f = f }
	local x0, x1 = LIFT.x0, LIFT.x1
	local ox0, ox1 = LIFT.openX0, LIFT.openX1
	local zf = LIFT.front
	local top = y + hh
	-- 승강로 옆벽 (1F · 2F 는 회벽, 옥상은 탑 외벽이 따로)
	if f < 3 then
		Lib.wall(K, "ShaftWallW", x0, y, zf + 0.25, x0 + 0.30, top, zb, LK.plaster)
		Lib.wall(K, "ShaftWallE", x1 - 0.30, y, zf + 0.25, x1, top, zb, LK.plaster)
	end
	-- 앞 마감: 석재 (문 높이 + 0.7 까지) + 회벽 위
	local sy = math.min(y + 7.9, top)
	Lib.wall(K, "CladL", x0, y, zf, ox0, sy, zf + 0.25, LK.stone)
	Lib.wall(K, "CladR", ox1, y, zf, x1, sy, zf + 0.25, LK.stone)
	Lib.wall(K, "CladTransom", ox0, y + LIFT.doorH, zf, ox1, sy, zf + 0.25, LK.stone)
	if top > sy + 0.02 then
		Lib.wall(K, "CladTop", x0, sy, zf, x1, top, zf + 0.25, if f == 3 then LK.concrete else LK.plaster)
	end
	-- 스테인리스 문틀 (0.04 돌출)
	K:free(function()
		Lib.ab(K, "DoorTrim", ox0 - 0.25, y, zf - 0.04, ox0, y + LIFT.doorH + 0.25, zf, LK.trim)
		Lib.ab(K, "DoorTrim", ox1, y, zf - 0.04, ox1 + 0.25, y + LIFT.doorH + 0.25, zf, LK.trim)
		Lib.ab(K, "DoorTrimHead", ox0 - 0.25, y + LIFT.doorH, zf - 0.04, ox1 + 0.25, y + LIFT.doorH + 0.25, zf, LK.trim)
		Lib.ab(K, "LiftSill", ox0 - 0.11, y, zf, ox1 + 0.11, y + 0.06, zf + 0.65, LK.sill)
		Lib.ab(K, "SillGroove", ox0, y + 0.06, zf + 0.34, ox1, y + 0.065, zf + 0.38, Look.black)
	end)
	-- 승강장 문 2 짝 (닫힘 = 개구부 가운데에서 맞닿음)
	local mid = (ox0 + ox1) / 2
	local leafL = Lib.ab(K, "LandingLeafL", ox0 - 0.05, y + 0.05, zf + 0.30, mid, y + LIFT.doorH, zf + 0.42, LK.leaf)
	local leafR = Lib.ab(K, "LandingLeafR", mid, y + 0.05, zf + 0.30, ox1 + 0.05, y + LIFT.doorH, zf + 0.42, LK.leaf)
	for _, p in { leafL, leafR } do
		p.Reflectance = 0.1
		p.CanQuery = true
	end
	if not low then
		K:free(function()
			Lib.ab(K, "LeafSeam", mid - 0.01, y + 0.05, zf + 0.29, mid + 0.01, y + LIFT.doorH, zf + 0.30, Look.black)
		end)
	end
	local ax = Geo.HF.XVector
	local o = { tOpen = 0.9, tClose = 1.1, easeOpen = "quadInOut", easeClose = "quadInOut", collide = { leafL } }
	out.leafL = Lib.Slider(K, { leafL }, ax * -1.60, o)
	out.leafR = Lib.Slider(K, { leafR }, ax * 1.60, { tOpen = 0.9, tClose = 1.1, easeOpen = "quadInOut", easeClose = "quadInOut", collide = { leafR } })
	out.leafPart = leafL
	-- 홀 표시등
	local ly = if f == 1 then y + 7.55 else y + 7.50
	K:free(function()
		Lib.ab(K, "HallLantern", -33.0, ly, zf - 0.05, -31.18, ly + 0.55, zf, LK.blackGlass)
	end)
	local _, lt = Lib.tx(K, "HallLanternText", 1.7, 0.48, Lib.face(-32.09, ly + 0.275, zf - 0.052, 0, -1), LABEL[f], C3(255, 70, 50), nil, { glow = 1.6, font = Enum.Font.Code })
	out.lantern = lt
	-- 호출 버튼판
	local cp = K:plate("CallPlate", 0.55, 1.50, 0.05, Lib.face(-29.625, y + 3.85, zf, 0, -1), LK.steel)
	out.call = cp
	out.rings = {}
	if f < 3 then
		local up = K:disc("CallRingUp", 0.42, 0.03, Lib.face(-29.625, y + 4.15, zf - 0.05, 0, -1) * ANG(PI / 2, 0, 0), LK.ringOff)
		K:disc("CallUp", 0.30, 0.05, Lib.face(-29.625, y + 4.15, zf - 0.06, 0, -1) * ANG(PI / 2, 0, 0), LK.white)
		Lib.tx(K, "CallUpArrow", 0.22, 0.22, Lib.face(-29.625, y + 4.15, zf - 0.087, 0, -1), "▲", C3(90, 94, 100), nil, { font = Lib.FONT_K })
		table.insert(out.rings, up)
	end
	if f > 1 then
		local dn = K:disc("CallRingDown", 0.42, 0.03, Lib.face(-29.625, y + 3.55, zf - 0.05, 0, -1) * ANG(PI / 2, 0, 0), LK.ringOff)
		K:disc("CallDown", 0.30, 0.05, Lib.face(-29.625, y + 3.55, zf - 0.06, 0, -1) * ANG(PI / 2, 0, 0), LK.white)
		Lib.tx(K, "CallDownArrow", 0.22, 0.22, Lib.face(-29.625, y + 3.55, zf - 0.087, 0, -1), "▼", C3(90, 94, 100), nil, { font = Lib.FONT_K })
		table.insert(out.rings, dn)
	end
	-- 낮은 호출 버튼 · 화재 시 안내 · 층 표시
	Lib.tx(K, "LowCall", 0.5, 0.6, Lib.face(-34.85, y + 2.70, zf, 0, -1), "▲▼", C.NAVY, C.WHITE, { font = Lib.FONT_K })
	if not low then
		K:plate("FireWarnBorder", 1.6, 1.6, 0.02, Lib.face(-34.80, y + 4.20, zf, 0, -1), Look.of(206, 36, 40))
		Lib.tx(K, "FireWarn", 1.5, 1.5, Lib.face(-34.80, y + 4.20, zf - 0.025, 0, -1), "화재 발생 시\n엘리베이터를\n이용하지 마시고\n계단을\n이용하십시오", C.RED, C.WHITE, { font = Lib.FONT_B })
	end
	Lib.tx(K, "FloorPlate", 0.6, 0.6, Lib.face(-34.20, y + 5.90, zf - 0.005, 0, -1), if f == 3 then "RF" else (LABEL[f] .. "F"), C.WHITE, C.TEAL, { font = Lib.FONT_K })
	if f == 1 then
		Lib.tx(K, "LiftSign", 3.0, 0.7, Lib.face(-32.09, 8.90, zf - 0.005, 0, -1), "엘리베이터  ELEVATOR", C.TEAL_D, nil, { font = Lib.FONT_K })
	end
	return out
end

-- 옥상 승강기 탑 (앞면 마감은 landing(3) 이 맡음)
local function penthouse(K: any)
	local y, top = LV[3], LV[3] + LIFT.height[3]
	local zb = LIFT.backZ[3]
	Lib.wall(K, "PentWallW", -36.20, y, LIFT.front, LIFT.x0, top, zb + 0.40, LK.concrete)
	Lib.wall(K, "PentWallE", LIFT.x1, y, LIFT.front, -28.00, top, zb + 0.40, LK.concrete)
	Lib.wall(K, "PentWallBack", LIFT.x0, y, zb, LIFT.x1, top, zb + 0.40, LK.concrete)
	Lib.wall(K, "PentInnerW", LIFT.x0, y, LIFT.front + 0.25, LIFT.x0 + 0.30, top, zb, LK.plaster)
	Lib.wall(K, "PentInnerE", LIFT.x1 - 0.30, y, LIFT.front + 0.25, LIFT.x1, top, zb, LK.plaster)
	Lib.wall(K, "PentCladFill", -36.20, y, LIFT.front, LIFT.x0, top, LIFT.front + 0.25, LK.concrete)
	Lib.wall(K, "PentCladFill", LIFT.x1, y, LIFT.front, -28.00, top, LIFT.front + 0.25, LK.concrete)
	Lib.wall(K, "PentRoof", -36.50, top, 33.00, -27.70, top + 0.35, zb + 0.40, LK.concrete)
	Lib.wall(K, "PentInnerCeil", LIFT.x0, top - 0.3, LIFT.front, LIFT.x1, top, zb, LK.white)
	K:free(function()
		Lib.ab(K, "PentCoping", -36.60, top + 0.35, 32.90, -27.60, top + 0.50, zb + 0.40, Look.of(70, 74, 78, M.Metal))
		if K.detail ~= "low" then
			-- 기계실 루버 (양 옆)
			for i = 0, 5 do
				Lib.ab(K, "PentLouver", -36.26, y + 5.9 + i * 0.4, 34.6, -36.20, y + 6.1 + i * 0.4, 37.6, LK.louver)
				Lib.ab(K, "PentLouver", -28.00, y + 5.9 + i * 0.4, 34.6, -27.94, y + 6.1 + i * 0.4, 37.6, LK.louver)
			end
		end
		-- 간판 + 처마 + 등
		Lib.tx(K, "PentSign", 4.0, 0.6, Lib.face(-32.09, y + 8.45, LIFT.front - 0.005, 0, -1), "엘리베이터 · 옥상 RF", C.WHITE, C.TEAL, { font = Lib.FONT_K })
		Lib.ab(K, "PentCanopy", -34.6, y + 8.95, 31.6, -29.6, y + 9.15, LIFT.front, Look.of(236, 236, 232))
		Lib.ab(K, "PentCanopyLamp", -32.8, y + 8.91, 32.1, -31.4, y + 8.95, 32.9, LK.led)
	end)
end

-- 카 (cabin) 모델. 피벗 = 바닥 가운데. 반환 info
local function cabin(K: any, y: number): any
	local low = K.detail == "low"
	local info: any = {}
	local m = K:group("LiftCabin", function()
		local G = solid(LK.granite)
		Lib.wall(K, "CabFloor", -34.89, y + 0.03, 33.85, -29.29, y + 0.12, 38.35, G)
		K:free(function()
			Lib.ab(K, "CabFloorBorder", -34.89, y + 0.12, 33.85, -29.29, y + 0.125, 33.95, LK.steel)
			Lib.ab(K, "CabSillStrip", -33.69, y + 0.03, 33.75, -30.49, y + 0.13, 33.85, LK.sill)
		end)
		-- 뒷벽: 아래 스테인리스, 위 거울
		Lib.wall(K, "CabBack", -34.89, y + 0.12, 38.35, -29.29, y + 7.90, 38.45, LK.hairline)
		K:free(function()
			K:plate("CabMirror", 4.42, 4.0, 0.03, Lib.face(-32.09, y + 5.40, 38.35, 0, -1), Look.mirror)
			-- 옆벽: 아래 헤어라인, 위 샴페인 골드 + 이음 선
			for _, sx in { -1, 1 } do
				local xa, xb = if sx < 0 then -34.99 else -29.29, if sx < 0 then -34.89 else -29.19
				Lib.solid(Lib.ab(K, "CabSideLow", xa, y + 0.12, 33.75, xb, y + 3.30, 38.45, LK.hairline), true)
				Lib.solid(Lib.ab(K, "CabSideHigh", xa, y + 3.30, 33.75, xb, y + 7.90, 38.45, LK.champagne), true)
				if not low then
					local fx = if sx < 0 then xb else xa
					for _, z in { 35.3, 36.85 } do
						Lib.ab(K, "CabSeam", fx - 0.005, y + 3.30, z - 0.01, fx + 0.005, y + 7.90, z + 0.01, Look.of(120, 116, 110))
					end
				end
			end
			-- 앞 기둥 + 문 위 패널
			Lib.solid(Lib.ab(K, "CabReturnL", -34.89, y + 0.12, 33.75, -33.69, y + 7.90, 33.85, LK.hairline), true)
			Lib.solid(Lib.ab(K, "CabReturnR", -30.49, y + 0.12, 33.75, -29.29, y + 7.90, 33.85, LK.hairline), true)
			Lib.solid(Lib.ab(K, "CabTransom", -33.69, y + 7.20, 33.75, -30.49, y + 7.90, 33.85, LK.hairline), true)
			-- 천장
			Lib.ab(K, "CabCeiling", -34.99, y + 7.90, 33.75, -29.19, y + 8.00, 38.45, LK.white)
			for _, x in { -33.2, -31.0 } do
				local led = Lib.ab(K, "CabLED", x - 0.06, y + 7.86, 34.0, x + 0.06, y + 7.90, 38.2, LK.led)
				info.led = info.led or led
			end
			-- 손잡이 (뒤 · 양옆)
			K:seg("CabRail", V3(-34.4, y + 2.95, 38.0), V3(-29.8, y + 2.95, 38.0), 0.16, LK.chrome)
			for _, x in { -34.0, -30.2 } do
				K:seg("CabRailBracket", V3(x, y + 2.95, 38.0), V3(x, y + 2.95, 38.35), 0.1, LK.chrome)
			end
			for _, x in { -34.55, -29.63 } do
				K:seg("CabRail", V3(x, y + 2.95, 34.6), V3(x, y + 2.95, 37.9), 0.16, LK.chrome)
				local wx = if x < -32 then -34.89 else -29.29
				for _, z in { 35.0, 37.5 } do
					K:seg("CabRailBracket", V3(x, y + 2.95, z), V3(wx, y + 2.95, z), 0.1, LK.chrome)
				end
			end
			-- 조작반 (COP): 오른쪽 기둥 안쪽면 (z 33.85, +z 를 봄)
			local cop = Lib.face(-29.89, y + 4.30, 33.85, 0, 1)
			K:plate("COPPanel", 1.06, 3.8, 0.05, cop, LK.steel)
			K:plate("COPDisplay", 0.8, 0.35, 0.02, cop * CF(0, 1.45, 0.05), LK.blackGlass)
			local _, dl = Lib.tx(K, "COPDisplayText", 0.76, 0.32, cop * CF(0, 1.45, 0.072), "1", C3(255, 70, 50), nil, { glow = 1.6, font = Enum.Font.Code })
			info.copLabel = dl
			info.copRings = {}
			for i, by in { 4.15, 4.65, 5.15 } do
				local r = K:disc("COPRing", 0.38, 0.03, Lib.face(-29.89, y + by, 33.90, 0, 1) * ANG(PI / 2, 0, 0), LK.ringOff)
				K:disc("COPButton", 0.30, 0.05, Lib.face(-29.89, y + by, 33.91, 0, 1) * ANG(PI / 2, 0, 0), LK.white)
				Lib.tx(K, "COPLabel", 0.22, 0.22, Lib.face(-29.89, y + by, 33.937, 0, 1), LABEL[i], C3(50, 54, 60), nil, { font = Lib.FONT_K })
				info.copRings[i] = r
			end
			for _, b in { { -30.15, "◀▶" }, { -29.63, "▶◀" } } do
				K:disc("COPButton", 0.30, 0.05, Lib.face(b[1] :: number, y + 3.55, 33.91, 0, 1) * ANG(PI / 2, 0, 0), LK.white)
				Lib.tx(K, "COPLabel", 0.26, 0.2, Lib.face(b[1] :: number, y + 3.55, 33.937, 0, 1), b[2] :: string, C3(50, 54, 60), nil, { font = Lib.FONT_K })
			end
			K:disc("COPAlarm", 0.30, 0.05, Lib.face(-29.89, y + 2.95, 33.91, 0, 1) * ANG(PI / 2, 0, 0), Look.of(240, 200, 30))
			Lib.tx(K, "COPAlarmLabel", 0.22, 0.2, Lib.face(-29.89, y + 2.95, 33.937, 0, 1), "🔔", C3(40, 40, 40), nil, { font = Lib.FONT_K })
			info.copPart = K:plate("COPKey", 0.16, 0.16, 0.03, cop * CF(0.32, -1.6, 0.05), LK.chrome)
			Lib.tx(K, "COPCapacity", 1.0, 0.22, cop * CF(0, -1.75, 0.052), "정원 9인 · 600kg", C3(40, 44, 48), nil, { font = Lib.FONT_M })
			if not low then
				Lib.tx(K, "COPIntercom", 1.0, 0.3, cop * CF(0, -1.35, 0.052), "비상시 인터폰\n버튼을 누르세요", C3(40, 44, 48), nil, { font = Lib.FONT_M })
			end
			-- 안쪽 층 표시
			Lib.ab(K, "CabIndicator", -32.6, y + 7.35, 33.85, -31.6, y + 7.75, 33.88, LK.blackGlass)
			local _, il = Lib.tx(K, "CabIndicatorText", 0.94, 0.36, Lib.face(-32.1, y + 7.55, 33.882, 0, 1), "1", C3(255, 70, 50), nil, { glow = 1.6, font = Enum.Font.Code })
			info.inLabel = il
			-- 검사증 · 스티커 · CCTV
			if not low then
				local cert = Lib.face(-34.88, y + 5.12, 34.75, 1, 0)
				K:plate("CertFrame", 0.95, 1.30, 0.03, cert, LK.chrome)
				Lib.tx(K, "Cert", 0.85, 1.18, cert * CF(0, 0, 0.032), "승강기 안전검사\n합격증명서\n\n승강기번호 2601-0317\n정기검사 · 합격\n유효기간\n2026.04.01 ~ 2027.03.31\n\n한국승강기안전공단", C3(30, 40, 60), C3(248, 246, 238), { font = Lib.FONT_M })
				Lib.tx(K, "CabNoSmoke", 0.6, 0.6, Lib.face(-29.30, y + 6.0, 37.2, -1, 0), "🚭", C.RED, C.WHITE, { font = Lib.FONT_K })
				Lib.tx(K, "CabFull", 1.6, 0.3, Lib.face(-29.30, y + 5.3, 37.2, -1, 0), "만원 시 다음 운행을 이용해 주세요", C3(60, 60, 64), nil, { font = Lib.FONT_M })
				K:ell("CabCCTV", V3(0.5, 0.3, 0.5), CF(-29.8, y + 7.86, 37.9), Look.with(Look.glassDark, { t = 0.15 }))
				Lib.tx(K, "CabCCTVNote", 0.9, 0.18, Lib.face(-29.30, y + 7.3, 37.9, -1, 0), "CCTV 녹화 중", C3(160, 40, 40), nil, { font = Lib.FONT_B })
				K:box("CabSpeaker", V3(0.6, 0.02, 0.6), CF(-32.09, y + 7.89, 37.4), Look.of(200, 200, 200))
			end
		end)
	end)
	info.model = m
	return info
end

-- 짓기 ---------------------------------------------------------------------------------------------

function E.build(K: any, env: any)
	local UI = env.UI
	local hub = env.hub
	-- 맵 가짜 엘리베이터 (1F 뒷벽) 숨김: 문 · 문틀은 카 뒤라 충돌은 그대로
	local function backZone(): Instance?
		return Lib.child(Lib.hospital(), { "1F", "BackZone" })
	end
	local fake: { [string]: boolean } = {}
	for _, n in Geo.FAKE_LIFT do
		fake[n] = true
	end
	Lib.hideModel(K, backZone, function(p)
		return fake[p.Name] == true and p.Parent == backZone()
	end)
	-- 2F 건강검진 안내판 (새 승강로 자리) 숨김 → Hosp_Signs 가 옆으로 다시 그림
	Lib.hideOwn(K, function()
		return Lib.find(Geo.PARTS.checkupGuide, 3)
	end, true)

	-- 다른 실내 빌더의 keep 무시 장식이 승강로(1F · 2F) 안에 들어오면 이 클라이언트에서 숨김
	Lib.ghostForeign(K, env.ctx and env.ctx.root, env.folder, {
		{ LIFT.x0 + 0.05, 0.12, LIFT.front + 0.3, LIFT.x1 - 0.05, 10.8, LIFT.backZ[1] - 0.02 },
		{ LIFT.x0 + 0.05, LV[2] + 0.12, LIFT.front + 0.3, LIFT.x1 - 0.05, LV[2] + 8.3, LIFT.backZ[2] - 0.02 },
	})

	local lands = {}
	for f = 1, 3 do
		lands[f] = landing(K, f)
	end
	penthouse(K)
	local cab = cabin(K, 0)
	local light: Light? = nil
	if cab.led then
		light = K:light(cab.led, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 10, Brightness = 1.0, Angle = 140, Color = Look.neutralLight })
	end
	if K.detail ~= "low" then
		-- 2F 층별 안내 (승강로 동쪽 벽 바깥면, +x 를 봄)
		local d = Lib.face(LIFT.x1, 18.4, 36.2, 1, 0)
		K:plate("Dir2FBack", 4.8, 4.8, 0.05, d, Look.of(250, 250, 248))
		Lib.tx(K, "Dir2FTitle", 4.6, 0.7, d * CF(0, 1.95, 0.055), "층별 안내  FLOOR GUIDE", C.WHITE, C.TEAL, { font = Lib.FONT_K })
		local rows = {
			{ "RF", "옥상 정원 · 휴게 공간" },
			{ "2F", "입원실 201 · 202 · 간호사실\n건강검진센터 · 휴게실" },
			{ "1F", "접수 · 수납 · 진료실 1 (내과)\n주사실 · 처치실 · 약국 · 화장실" },
		}
		for i, r in rows do
			local ry = 0.95 - (i - 1) * 1.25
			Lib.tx(K, "Dir2FLevel", 0.8, 0.8, d * CF(-1.85, ry, 0.055), r[1], C.WHITE, if i == 2 then C.RED else C.TEAL_D, { font = Lib.FONT_K })
			Lib.tx(K, "Dir2FRow", 3.5, 1.0, d * CF(0.5, ry, 0.055), r[2], C.INK, nil, { font = Lib.FONT_M, align = "Left" })
		end
		Lib.tx(K, "Dir2FHere", 1.6, 0.3, d * CF(1.4, -2.15, 0.055), "● 현재 위치 2F", C.RED, nil, { font = Lib.FONT_B })
	end

	-- 상태 기계 ---------------------------------------------------------------------------------------
	local st: any = { floor = 1, mode = "idle", calls = {}, dir = 0, tOpen = 0, from = 1, to = 1, t0 = 0, dur = 0, lastUse = 0, hum = nil, alarmUntil = 0 }
	local cabBaseY = 0 -- 카가 지금 있는 층 높이 (로컬)
	local function setDisplay(text: string)
		for _, l in lands do
			if l.lantern then
				l.lantern.Text = text
			end
		end
		if cab.copLabel then
			cab.copLabel.Text = text
		end
		if cab.inLabel then
			cab.inLabel.Text = text
		end
		if st.panel then
			st.panel.display(text)
		end
	end
	local function lightRings()
		for f = 1, 3 do
			local on = st.calls[f] == true
			for _, r in lands[f].rings do
				if r.Parent then
					r.Material = if on then M.Neon else M.SmoothPlastic
					r.Color = if on then C3(255, 176, 60) else C3(232, 234, 236)
				end
			end
			local cr = cab.copRings and cab.copRings[f]
			if cr and cr.Parent then
				cr.Material = if on then M.Neon else M.SmoothPlastic
				cr.Color = if on then C3(255, 176, 60) else C3(232, 234, 236)
			end
			if st.panel then
				st.panel.lit(f, on)
			end
		end
	end
	local function doors(open: boolean)
		local l = lands[st.floor]
		l.leafL:set(if open then 1 else 0)
		l.leafR:set(if open then 1 else 0)
		Lib.sfx(l.leafPart, SND.swoosh, { vol = 0.15, speed = if open then 0.55 else 0.5 })
	end
	local function inCabin(): boolean
		local me = Lib.me()
		local c = LIFT.cabin
		return me ~= nil and me.X > c.x0 and me.X < c.x1 and me.Z > c.z0 and me.Z < c.z1 and me.Y > cabBaseY - 1 and me.Y < cabBaseY + 8.5
	end
	local function inDoorway(f: number): boolean
		local d = LIFT.doorway
		local y = LV[f]
		for _, a in Lib.actors() do
			if a.l.X > d.x0 and a.l.X < d.x1 and a.l.Z > d.z0 and a.l.Z < d.z1 and a.l.Y > y - 1 and a.l.Y < y + 8 then
				return true
			end
		end
		return false
	end
	local function chime(n: number)
		local part = lands[st.floor].call
		Lib.sfx(part, SND.chime, { vol = 0.45, speed = 1.0 })
		if n > 1 then
			task.delay(0.35, function()
				Lib.sfx(part, SND.chime, { vol = 0.45, speed = 0.8 })
			end)
		end
	end
	local function call(f: number)
		st.lastUse = os.clock()
		if f == st.floor and (st.mode == "idle" or st.mode == "open" or st.mode == "closing") then
			if st.mode == "open" then
				st.tOpen = os.clock()
			else
				st.mode = "opening"
				st.modeT = os.clock()
				doors(true)
				chime(1)
			end
			return
		end
		st.calls[f] = true
		lightRings()
		-- 다른 층을 누르면 문이 열려 있던 시간을 줄여 곧 닫힘 (실제 승강기처럼 약 2 초 뒤)
		if st.mode == "open" then
			st.tOpen = math.min(st.tOpen, os.clock() - 2.2)
		end
	end
	local function nextTarget(): number?
		local best, bd = nil, 1e9
		for f = 1, 3 do
			if st.calls[f] and f ~= st.floor then
				local d = math.abs(f - st.floor)
				-- 같은 방향 우선
				if st.dir ~= 0 and (f - st.floor) * st.dir < 0 then
					d += 10
				end
				if d < bd then
					best, bd = f, d
				end
			end
		end
		return best
	end
	-- 도착: 카 + (탄 경우) 캐릭터 + 카메라를 같은 렌더 프레임에 수직 이동
	local function arrive()
		local to = st.to
		local dy = LV[to] - LV[st.from]
		local riding = inCabin()
		local function shift()
			if riding then
				local hrp = Lib.localRoot()
				if hrp then
					hrp.CFrame = hrp.CFrame + V3(0, dy, 0)
					local cam = Workspace.CurrentCamera
					if cam then
						cam.CFrame = cam.CFrame + V3(0, dy, 0)
					end
				end
			end
			cab.model:PivotTo(cab.model:GetPivot() + V3(0, dy, 0))
			cabBaseY = LV[to]
		end
		local bound = pcall(function()
			RunService:BindToRenderStep("GwHospLift", Enum.RenderPriority.Camera.Value + 1, function()
				RunService:UnbindFromRenderStep("GwHospLift")
				shift()
			end)
		end)
		if not bound then
			shift()
		else
			-- 렌더가 안 도는 환경(오프라인 등) 대비
			task.delay(0.25, function()
				if cabBaseY ~= LV[to] then
					pcall(function()
						RunService:UnbindFromRenderStep("GwHospLift")
					end)
					shift()
				end
			end)
		end
		st.floor = to
		st.calls[to] = nil
		lightRings()
		if st.hum then
			st.hum:Destroy()
			st.hum = nil
		end
		chime(2)
		if riding then
			UI.toast(FLOOR_TOAST[to], 2.4)
		end
		st.mode = "opening"
		st.modeT = os.clock()
		task.delay(0.3, function()
			if st.mode == "opening" and st.floor == to then
				doors(true)
			end
		end)
	end
	-- 즉시 다른 층에 갖다 놓기 (NPC 가 그 층에서 나타날 때 · 리셋)
	local function snapTo(f: number)
		local dy = LV[f] - cabBaseY
		if math.abs(dy) > 1e-3 then
			cab.model:PivotTo(cab.model:GetPivot() + V3(0, dy, 0))
		end
		cabBaseY = LV[f]
		for g = 1, 3 do
			lands[g].leafL:set(0, true)
			lands[g].leafR:set(0, true)
		end
		st.floor = f
		st.mode = "idle"
		setDisplay(LABEL[f])
	end

	local function openCmd()
		if st.mode == "open" then
			st.tOpen = os.clock()
		elseif st.mode == "closing" or st.mode == "idle" then
			st.mode = "opening"
			st.modeT = os.clock()
			doors(true)
		end
	end
	local function closeCmd()
		if st.mode == "open" and os.clock() - st.tOpen > 0.5 then
			st.mode = "closing"
			st.modeT = os.clock()
			doors(false)
		end
	end
	local function alarm()
		if os.clock() < st.alarmUntil then
			return
		end
		st.alarmUntil = os.clock() + 4
		Lib.beeps(cab.copPart or lands[st.floor].call, SND.chime, 8, 0.22, { vol = 0.55, speed = 1.9 })
		UI.toast("비상벨을 눌렀어요. 관리실에 연결하고 있어요", 3)
	end
	local handlers = {
		floor = function(i: number)
			call(i)
		end,
		open = openCmd,
		close = closeCmd,
		alarm = alarm,
	}

	-- 호출 프롬프트 (승강장마다)
	for f = 1, 3 do
		Interact.prompt(K, lands[f].call, {
			action = "엘리베이터 호출",
			object = (if f == 3 then "RF" else LABEL[f] .. "F") .. " 엘리베이터",
			sound = SND.click,
			fn = function()
				call(f)
			end,
		})
	end
	-- 카 안 "층 선택" 프롬프트 (조작반 보이기/숨기기)
	if cab.copPart then
		Lib.promptAny(K, cab.copPart, {
			action = "층 선택",
			object = "엘리베이터",
			sound = SND.click,
			fn = function()
				if st.panel and st.panel.shown() then
					st.manualHide = true
					UI.lift(false)
				else
					st.manualHide = false
					st.panel = UI.lift(true, handlers)
					setDisplay(LABEL[st.floor])
					lightRings()
				end
			end,
		})
	end

	-- NPC 연동 ------------------------------------------------------------------------------------
	local npcCallT = { -1e9, -1e9, -1e9 }
	local npcConn: RBXScriptConnection? = nil
	local function hookNpcFolder()
		if npcConn then
			return
		end
		local f = Workspace:FindFirstChild("GwangalliNPCs")
		if not f then
			return
		end
		npcConn = f.ChildAdded:Connect(function(m)
			task.wait(0.1)
			if not m:IsA("Model") or m:GetAttribute("NpcKind") ~= "hospital" then
				return
			end
			local ok, pv = pcall(function()
				return m:GetPivot().Position
			end)
			if not ok then
				return
			end
			local l = Geo.L(pv)
			if V3(l.X - Geo.LIFT_SPOT.X, 0, l.Z - Geo.LIFT_SPOT.Z).Magnitude < 3.5 then
				local f2 = if l.Y > 20 then 3 elseif l.Y > 9 then 2 else 1
				if not inCabin() and (st.mode == "idle" or st.mode == "open") then
					if f2 ~= st.floor then
						snapTo(f2)
					end
					st.mode = "opening"
					st.modeT = os.clock()
					doors(true)
					chime(1)
				end
			end
		end)
		table.insert(K.conns, npcConn)
	end
	hookNpcFolder()
	Lib.onSec(K, function()
		hookNpcFolder()
		-- 다가오는 NPC → 그 층 호출
		for _, a in Lib.actors() do
			if a.kind == "npc" then
				local d = V3(a.l.X - Geo.LIFT_SPOT.X, 0, a.l.Z - Geo.LIFT_SPOT.Z).Magnitude
				local f2 = if a.l.Y > 20 then 3 elseif a.l.Y > 9 then 2 else 1
				if d < 6 and d > 1.0 and os.clock() - npcCallT[f2] > 8 then
					npcCallT[f2] = os.clock()
					if not inCabin() then
						call(f2)
					end
				end
			end
		end
	end)

	-- 10 Hz 틱 ------------------------------------------------------------------------------------
	setDisplay(LABEL[1])
	Interact.anim(K, function()
		local now = os.clock()
		local riding = inCabin()
		if riding then
			st.lastUse = now
		end
		-- 조작반: 카 안에 있으면 보이기
		if riding and not st.manualHide then
			if not st.panel or not st.panel.shown() then
				st.panel = UI.lift(true, handlers)
				setDisplay(LABEL[st.floor])
				lightRings()
			end
		elseif not riding then
			st.manualHide = false
			if st.panel and st.panel.shown() then
				UI.lift(false)
			end
		end
		-- 카 조명: 60 초 동안 아무도 없으면 끔
		if light then
			local want = (now - st.lastUse) < 60 or st.mode ~= "idle"
			if light.Enabled ~= want then
				light.Enabled = want
			end
		end
		local mode = st.mode
		if mode == "idle" then
			local nt = nextTarget()
			if nt then
				st.from, st.to = st.floor, nt
				st.dir = if nt > st.floor then 1 else -1
				st.t0 = now
				st.dur = 1.4 + 1.1 * math.abs(nt - st.floor)
				st.mode = "moving"
				st.lastStep = st.floor
				setDisplay(LABEL[st.floor] .. (if st.dir > 0 then " ▲" else " ▼"))
				if st.hum then
					st.hum:Destroy()
				end
				st.hum = Lib.sfx(cab.copPart or lands[st.floor].call, SND.wind, { vol = 0.12, speed = 0.35, loop = true, dur = st.dur + 0.5 })
			else
				st.dir = 0
			end
		elseif mode == "opening" then
			if now - (st.modeT or now) > 1.0 then
				st.mode = "open"
				st.tOpen = now
				setDisplay(LABEL[st.floor])
			end
		elseif mode == "open" then
			if inDoorway(st.floor) then
				st.tOpen = now
			end
			if now - st.tOpen > 4.0 then
				st.mode = "closing"
				st.modeT = now
				doors(false)
			end
		elseif mode == "closing" then
			if inDoorway(st.floor) then
				-- 문 끼임 방지: 다시 열기
				st.mode = "opening"
				st.modeT = now
				doors(true)
			elseif now - st.modeT > 1.2 then
				st.mode = "idle"
			end
		elseif mode == "moving" then
			local k = (now - st.t0) / st.dur
			-- 층 표시: 구간 가운데를 지나면 다음 층 숫자
			local span = st.to - st.from
			local passed = st.from + math.floor(math.abs(span) * k + 0.5) * (if span > 0 then 1 else -1)
			if passed ~= st.lastStep and k < 1 then
				st.lastStep = passed
				setDisplay(LABEL[passed] .. (if st.dir > 0 then " ▲" else " ▼"))
			end
			if k >= 1 then
				arrive()
			end
		end
	end)

	hub.lift = {
		reset = function()
			if not inCabin() then
				st.calls = {}
				lightRings()
				snapTo(1)
			end
		end,
		state = function()
			return st
		end,
		call = call,
	}
	Lib.onClean(K, function()
		UI.lift(false)
		pcall(function()
			RunService:UnbindFromRenderStep("GwHospLift")
		end)
		if hub.lift and hub.lift.state and hub.lift.state() == st then
			hub.lift = nil
		end
	end)
end

function E.ready(_env: any): boolean
	return Lib.child(Lib.hospital(), { "1F", "BackZone" }) ~= nil
end

return E
