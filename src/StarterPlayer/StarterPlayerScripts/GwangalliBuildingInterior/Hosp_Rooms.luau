--!strict
-- GwangalliBuildingInterior/Hosp_Rooms: 숨은 방 3 개 (설계 §7.5 · §7.7). Hosp_Portal 이 필요할 때 짓고 치움.
--   staff  직원 휴게실: 사물함 (2 칸은 열림), 소파 (앉기), 탁자, 미니 주방 (물 · 커피 · 전자레인지 · 냉장고),
--          식탁 + 의자, 근무표 화이트보드, 게시판, TV (채널), 시계, 전등 스위치, 포스터
--   store  창고: 라벨 붙은 물품 선반 3 면, 린넨 카트, 접힌 휠체어 2, 산소통 3 (체인), 수액대, 사다리, 재고 점검표
--   stair  비상계단: 2F ↔ RF 계단 (실제로 걸어 올라감), 층 표시 그래픽, 피난구 유도등, 벽등
-- 좌표: 병원 프레임 HF, 방 바닥 y = -50 (월드 약 -43.1). K.doorFx[side] = fn(alpha) (문 살짝 열림 연출).

local Lib = require(script.Parent:WaitForChild("Hosp_Lib"))
local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))

local Rooms = {}

local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C3 = Color3.fromRGB
local rad = math.rad

local Geo = Lib.Geo
local C = Geo.C
local SND = Geo.SND
local F = Geo.PORTAL_Y -- -50

local function sol(l: any): any
	local t = table.clone(l)
	t.collide = true
	t.shadow = true
	t.free = true
	return t
end

-- 방 껍데기: 안쪽 x0..x1, z0..z1, 바닥 F, 천장 ct. looks = { floor, wall, ceil, wains?, base? }
local function shell(K: any, x0: number, x1: number, z0: number, z1: number, ct: number, looks: any)
	local t = 0.4
	Lib.wall(K, "RoomFloor", x0 - t, F - 0.6, z0 - t, x1 + t, F, z1 + t, looks.floor)
	Lib.wall(K, "RoomCeiling", x0 - t, ct, z0 - t, x1 + t, ct + 0.5, z1 + t, looks.ceil)
	Lib.wall(K, "RoomWallS", x0 - t, F, z0 - t, x1 + t, ct, z0, looks.wall)
	Lib.wall(K, "RoomWallN", x0 - t, F, z1, x1 + t, ct, z1 + t, looks.wall)
	Lib.wall(K, "RoomWallW", x0 - t, F, z0, x0, ct, z1, looks.wall)
	Lib.wall(K, "RoomWallE", x1, F, z0, x1 + t, ct, z1, looks.wall)
	K:free(function()
		if looks.wains then
			local h = looks.wainsH or 3.0
			Lib.ab(K, "Wainscot", x0, F, z0, x1, F + h, z0 + 0.04, looks.wains)
			Lib.ab(K, "Wainscot", x0, F, z1 - 0.04, x1, F + h, z1, looks.wains)
			Lib.ab(K, "Wainscot", x0, F, z0 + 0.04, x0 + 0.04, F + h, z1 - 0.04, looks.wains)
			Lib.ab(K, "Wainscot", x1 - 0.04, F, z0 + 0.04, x1, F + h, z1 - 0.04, looks.wains)
			Lib.ab(K, "WainscotCap", x0, F + h, z0, x1, F + h + 0.08, z0 + 0.07, Look.of(160, 162, 164))
			Lib.ab(K, "WainscotCap", x0, F + h, z1 - 0.07, x1, F + h + 0.08, z1, Look.of(160, 162, 164))
		end
		local b = looks.base or Look.of(90, 94, 98)
		Lib.ab(K, "Baseboard", x0, F, z0 + 0.04, x1, F + 0.4, z0 + 0.08, b)
		Lib.ab(K, "Baseboard", x0, F, z1 - 0.08, x1, F + 0.4, z1 - 0.04, b)
		Lib.ab(K, "Baseboard", x0 + 0.04, F, z0, x0 + 0.08, F + 0.4, z1, b)
		Lib.ab(K, "Baseboard", x1 - 0.08, F, z0, x1 - 0.04, F + 0.4, z1, b)
	end)
end

-- 천장 LED 평판 (방 천장 아래면 ct 에 붙음). 반환: 빛 파트
local function panel(K: any, x: number, z: number, ct: number, s: number?): BasePart
	local sz = s or 2.0
	K:box("PanelLightFrame", V3(sz, 0.05, sz), CF(x, ct - 0.025, z), Look.white)
	return K:box("PanelLight", V3(sz - 0.16, 0.03, sz - 0.16), CF(x, ct - 0.06, z), Look.lampCool)
end

-- 방 쪽 문 (여닫이, 문 열림 연출만): x0..x1, 벽 z, 경첩 쪽, 방 안 법선 n (+1 = +z)
local function roomDoorLeaf(K: any, name: string, x0: number, x1: number, zw: number, y0: number, h: number, look: any, hingeAtX1: boolean): (Model, BasePart?)
	local lever: BasePart? = nil
	local g = K:group(name, function()
		K:free(function()
			Lib.ab(K, "RoomDoorLeaf", x0, y0 + 0.02, zw, x1, y0 + h, zw + 0.15, look)
			local lx = if hingeAtX1 then x0 + 0.5 else x1 - 0.5
			lever = K:box("RoomDoorLever", V3(0.65, 0.12, 0.12), CF(lx + (if hingeAtX1 then 0.25 else -0.25), y0 + 3.6, zw + 0.30), Look.chrome)
			K:cyl("RoomDoorRose", 0.06, 0.3, CF(lx, y0 + 3.6, zw + 0.17) * ANG(0, PI / 2, 0), Look.chrome)
			K:plate("RoomDoorKick", x1 - x0 - 0.1, 0.7, 0.02, Lib.face((x0 + x1) / 2, y0 + 0.45, zw + 0.15, 0, 1), Look.steel)
		end)
	end)
	-- 문틀
	K:free(function()
		Lib.ab(K, "RoomDoorJamb", x0 - 0.2, y0, zw, x0, y0 + h + 0.2, zw + 0.22, Look.of(120, 124, 128, M.Metal))
		Lib.ab(K, "RoomDoorJamb", x1, y0, zw, x1 + 0.2, y0 + h + 0.2, zw + 0.22, Look.of(120, 124, 128, M.Metal))
		Lib.ab(K, "RoomDoorHead", x0 - 0.2, y0 + h, zw, x1 + 0.2, y0 + h + 0.2, zw + 0.22, Look.of(120, 124, 128, M.Metal))
	end)
	return g, lever
end

local function crackMover(K: any, g: Model, hx: number, zw: number, sign: number): (number) -> ()
	local mv = Lib.Swinger(K, Lib.partsOf(g), Geo.W(hx, 0, zw), Geo.HF.YVector, rad(18) * sign, { tOpen = 0.25, tClose = 0.6, easeOpen = "quadOut", easeClose = "quadIn" })
	return function(a: number)
		mv:set(a)
	end
end

-- 짧은 안내 글자 (벽 dcf)
local function note(K: any, dcf: CFrame, w: number, h: number, s: string, fg: Color3?, bg: Color3?)
	Lib.tx(K, "Note", w, h, dcf, s, fg or C.INK, bg, { font = Lib.FONT_B })
end

-- P1 직원 휴게실 -----------------------------------------------------------------------------------

function Rooms.staff(K: any, env: any, P: any)
	local UI = env.UI
	local low = K.detail == "low"
	local x0, x1, z0, z1, ct = -24.0, -2.0, 22.0, 36.0, -41.4
	local y = F
	shell(K, x0, x1, z0, z1, ct, {
		floor = sol(Look.of(176, 140, 104, M.WoodPlanks)),
		wall = sol(Look.of(238, 234, 226, M.Plaster)),
		ceil = sol(Look.of(244, 244, 240)),
		wains = Look.of(196, 198, 198),
	})
	-- 문 (남쪽 벽 안쪽) + 나가기
	local dg, lever = roomDoorLeaf(K, "StaffRoomDoor", -13.975, -10.225, z0, y, 7.6, Look.oak, true)
	K.doorFx = { hall = crackMover(K, dg, -10.225, z0, 1) }
	if lever then
		Interact.prompt(K, lever, { action = "나가기", object = "1층 후면 홀", sound = SND.click, fn = function()
			P.back("staff", "hall")
		end })
	end
	Lib.plate(K, "StaffExitPlate", 2.4, 0.5, Lib.face(-12.1, y + 8.05, z0, 0, 1), "나가는 문 · 1층 후면 홀", { bg = C.TEAL, fg = C.WHITE })
	-- 시계 (문 위 오른쪽) + 전등 스위치
	local hr, mn = Props.clock(K, Lib.face(-8.6, y + 7.6, z0, 0, 1), 1.2)
	Interact.clock(K, hr, mn, Lib.face(-8.6, y + 7.6, z0, 0, 1), 1.2)
	local sw = Props.switchPlate(K, Lib.face(-9.4, y + 4.0, z0, 0, 1), 2)

	-- 사물함 (서쪽 벽, +x 를 봄): 2 단 x 5 열
	Lib.wall(K, "LockerBody", x0, y + 0.3, 23.0, -22.4, y + 6.7, 30.0, Look.of(150, 156, 160, M.Metal))
	Lib.wall(K, "LockerPlinth", x0, y, 23.0, -22.5, y + 0.3, 30.0, Look.of(70, 72, 76))
	Lib.ab(K, "LockerTop", x0, y + 6.7, 22.95, -22.3, y + 6.8, 30.05, Look.of(140, 146, 150, M.Metal))
	local n = 0
	for tier = 0, 1 do
		for col = 0, 4 do
			n += 1
			local za, zb = 23.0 + col * 1.4 + 0.03, 23.0 + (col + 1) * 1.4 - 0.03
			local ya, yb = y + 0.3 + tier * 3.2 + 0.03, y + 0.3 + (tier + 1) * 3.2 - 0.03
			local zc, yc = (za + zb) / 2, (ya + yb) / 2
			local interactive = (tier == 0 and col == 1) or (tier == 1 and col == 3)
			local function door()
				Lib.ab(K, "LockerDoor", -22.40, ya, za, -22.30, yb, zb, Look.of(166, 172, 176, M.Metal))
				if not low then
					for i = 0, 3 do
						Lib.ab(K, "LockerVent", -22.30, yb - 0.5 - i * 0.14, zc - 0.4, -22.29, yb - 0.45 - i * 0.14, zc + 0.4, Look.of(80, 84, 88))
					end
				end
				Lib.tx(K, "LockerTag", 0.9, 0.26, Lib.face(-22.295, yc + 0.5, zc, 1, 0), string.format("간호부 %02d", n), C.INK, C.WHITE, { font = Lib.FONT_B })
				K:box("LockerHandle", V3(0.08, 0.5, 0.1), CF(-22.24, yc, zb - 0.25), Look.chrome)
			end
			if interactive then
				-- 안쪽 (문 열면 보임): 걸린 근무복
				K:free(function()
					Lib.ab(K, "LockerInside", -22.41, ya, za, -22.40, yb, zb, Look.of(60, 64, 68))
					Lib.ab(K, "LockerScrub", -22.41, ya + 0.6, zc - 0.45, -22.36, yb - 0.4, zc + 0.45, Look.of(40, 150, 140, M.Fabric))
				end)
				local g = K:group("LockerDoor" .. n, function()
					K:free(door)
				end)
				Interact.swing(K, g, Geo.W(-22.30, 0, za), Geo.HF.YVector, rad(100), { object = string.format("사물함 %02d", n), openText = "사물함 열기", closeText = "사물함 닫기" })
			else
				K:free(door)
			end
		end
	end
	-- 근무복 걸이 (동쪽 벽)
	K:free(function()
		K:seg("UniformRail", V3(-2.12, y + 4.6, 29.2), V3(-2.12, y + 4.6, 33.0), 0.1, Look.chrome)
		local garments = { { 29.8, Look.of(40, 150, 140, M.Fabric), "" }, { 31.1, Look.of(246, 246, 244, M.Fabric), "김선생" }, { 32.4, Look.of(40, 52, 90, M.Fabric), "" } }
		for _, gm in garments do
			local gz: number = gm[1] :: number
			K:seg("Hanger", V3(-2.30, y + 4.5, gz - 0.6), V3(-2.30, y + 4.5, gz + 0.6), 0.06, Look.of(120, 90, 60, M.Wood))
			K:box("Garment", V3(0.25, 3.2, 1.4), CF(-2.32, y + 2.85, gz), gm[2])
			if not low then
				for _, sz in { -0.85, 0.85 } do
					K:box("GarmentSleeve", V3(0.22, 1.8, 0.35), CF(-2.32, y + 3.3, gz + sz) * ANG(rad(sz * 6), 0, 0), gm[2])
				end
			end
			if gm[3] ~= "" then
				Lib.tx(K, "GarmentTag", 0.5, 0.16, Lib.face(-2.45, y + 3.9, gz - 0.3, -1, 0), gm[3] :: string, C.NAVY, C.WHITE, { font = Lib.FONT_B })
			end
		end
	end)
	-- 근무표 화이트보드 (동쪽 벽, -x 를 봄)
	local wb = Lib.face(-2.0, y + 5.0, 25.8, -1, 0)
	local board = K:plate("DutyBoard", 4.4, 3.2, 0.08, wb, Look.of(250, 250, 250))
	K:plate("DutyBoardFrame", 4.5, 0.06, 0.1, wb * CF(0, 1.62, 0), Look.alu)
	K:plate("DutyBoardFrame", 4.5, 0.06, 0.1, wb * CF(0, -1.62, 0), Look.alu)
	K:plate("DutyBoardTray", 3.0, 0.08, 0.25, wb * CF(0, -1.68, 0), Look.alu)
	local duty = "10월 근무표 (간호부)\n      월  화  수  목  금  토  일\n김   D   D   E   E   N   -   -\n박   E   E   N   N   -   D   D\n이   N   -   D   D   E   E   N\n최   -   N   N   D   D   E   E"
	Lib.tx(K, "DutyText", 4.1, 2.9, wb * CF(0, 0, 0.085), duty, C3(30, 40, 90), nil, { font = Enum.Font.Code })
	Interact.prompt(K, board, { action = "근무표 보기", object = "근무표", fn = function()
		UI.toast("이번 주 김선생 D · D · E · E · N 근무 (D 07-15 · E 15-23 · N 23-07)", 3.5)
	end })
	-- 게시판 (남쪽 벽, 문 동쪽)
	local nb = Lib.face(-6.6, y + 4.8, z0, 0, 1)
	local cork = K:plate("NoticeBoard", 4.6, 3.0, 0.08, nb, Look.of(176, 132, 86, M.Wood))
	K:plate("NoticeFrame", 4.7, 0.08, 0.1, nb * CF(0, 1.52, 0), Look.walnut)
	K:plate("NoticeFrame", 4.7, 0.08, 0.1, nb * CF(0, -1.52, 0), Look.walnut)
	local notes = { "감염관리 교육\n10/24 14:00", "휴게실 냉장고\n금요일 정리", "직원 독감\n예방접종", "주차권 신청은\n원무과", "회식 11/7(금) 19시\n광안리 횟집", "화재 대피 훈련\n11/3" }
	local noteCols = { C3(255, 246, 170), C3(220, 240, 255), C3(255, 220, 220), C3(230, 255, 220), C3(255, 236, 200), C3(240, 240, 240) }
	for i, s in notes do
		local cx = -1.5 + ((i - 1) % 3) * 1.5
		local cy = 0.65 - math.floor((i - 1) / 3) * 1.35
		Lib.tx(K, "NoticePaper", 1.3, 1.1, nb * CF(cx, cy, 0.085) * ANG(0, 0, rad((i % 3 - 1) * 3)), s, C.INK, noteCols[i], { font = Lib.FONT_M })
		K:disc("NoticePin", 0.1, 0.04, nb * CF(cx, cy + 0.48, 0.12) * ANG(PI / 2, 0, 0), Look.ledRed)
	end
	local ni = 0
	Interact.prompt(K, cork, { action = "게시판 보기", object = "게시판", fn = function()
		ni = ni % #notes + 1
		UI.toast("📌 " .. (string.gsub(notes[ni], "\n", " ")), 2.6)
	end })
	-- 포스터
	Props.frame(K, Lib.face(-3.15, y + 5.0, z0, 0, 1), 1.6, 2.2, { text = "손 위생\n5원칙\n\n환자 접촉 전\n청결 처치 전\n체액 노출 후\n환자 접촉 후\n환경 접촉 후", fg = C.TEAL_D, frame = Look.alu, textH = 0.95 })
	Props.frame(K, Lib.face(x0, y + 5.0, 31.8, 1, 0), 2.0, 2.6, { text = "직원 휴게실\n이용 수칙\n\n· 음식은 냉장고에\n· 사용한 컵은 세척\n· 소등 후 퇴실\n· 금연", fg = C.INK, frame = Look.alu, textH = 0.95 })
	-- TV (남쪽 벽, 문 서쪽)
	local tvd = Lib.face(-18.0, y + 4.85, z0, 0, 1)
	local scr = Props.tv(K, tvd, 4.0, { text = "광안리 해변 CCTV", screen = C3(40, 90, 150) })
	local tvLabel: TextLabel? = nil
	for _, d in K.folder:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "광안리 해변 CCTV" then
			tvLabel = d
		end
	end
	local channels = {
		{ "📺 KBS 뉴스 · 오늘의 날씨", C3(30, 60, 120) },
		{ "☀️ 부산 맑음 21° · 내일 오전 비", C3(60, 130, 190) },
		{ "🌊 광안리 해변 CCTV · LIVE", C3(30, 110, 150) },
	}
	Interact.cycle(K, scr, channels, { action = "채널 바꾸기", object = "TV", start = 3, on = function(_i, ch)
		if scr.Parent then
			scr.Color = ch[2]
		end
		if tvLabel then
			tvLabel.Text = ch[1]
		end
	end })
	-- 소파 (북쪽 벽 서쪽, -z 를 봄) + 앉기 3
	local sofa = Look.of(92, 110, 128, M.Fabric)
	Lib.wall(K, "SofaBase", -23.2, y + 0.3, 33.6, -15.6, y + 1.55, 36.0, sofa)
	K:free(function()
		Lib.ab(K, "SofaBack", -23.2, y + 1.55, 35.3, -15.6, y + 3.6, 36.0, sofa)
		Lib.ab(K, "SofaArm", -23.2, y + 1.55, 33.6, -22.7, y + 2.6, 35.3, sofa)
		Lib.ab(K, "SofaArm", -16.1, y + 1.55, 33.6, -15.6, y + 2.6, 35.3, sofa)
		for _, fx in { -23.0, -15.8 } do
			for _, fz in { 33.8, 35.8 } do
				Lib.ab(K, "SofaFoot", fx - 0.1, y, fz - 0.1, fx + 0.1, y + 0.3, fz + 0.1, Look.blackMetal)
			end
		end
	end)
	for i, sx in { -21.93, -19.4, -16.87 } do
		local cush = K:box("SofaCushion", V3(2.4, 0.35, 1.7), CF(sx, y + 1.72, 34.45), Look.of(100, 120, 140, M.Fabric))
		Lib.solid(cush, true)
		if not low then
			K:box("SofaPillow", V3(1.8, 1.3, 0.35), CF(sx, y + 2.5, 35.1) * ANG(rad(-12), 0, 0), Look.of(if i == 2 then 220 else 200, 190, 160, M.Fabric))
		end
		Lib.seatPrompt(K, cush, CF(sx, y + 1.9, 34.4), "소파")
	end
	-- 커피 탁자
	K:free(function()
		Lib.solid(Lib.ab(K, "CoffeeTable", -21.6, y + 1.25, 30.8, -17.6, y + 1.4, 32.6, Look.oak), true)
		for _, tx in { -21.3, -17.9 } do
			for _, tz in { 31.1, 32.3 } do
				Lib.ab(K, "CoffeeTableLeg", tx - 0.08, y, tz - 0.08, tx + 0.08, y + 1.25, tz + 0.08, Look.blackMetal)
			end
		end
		K:vcyl("Mug", 0.35, 0.3, CF(-20.4, y + 1.575, 31.5), Look.white)
		K:box("Magazine", V3(1.0, 0.04, 1.3), CF(-18.6, y + 1.42, 31.7) * ANG(0, 0.3, 0), Look.of(200, 80, 70))
	end)
	-- 미니 주방 (북쪽 벽 동쪽, -z 를 봄)
	Lib.wall(K, "KitchenBase", -14.8, y, 33.8, -4.6, y + 3.0, 36.0, Look.of(236, 236, 232))
	Lib.wall(K, "KitchenTop", -14.9, y + 3.0, 33.7, -4.5, y + 3.15, 36.0, Look.marbleWhite)
	K:free(function()
		for i = 0, 4 do
			local xa = -14.8 + i * 2.04
			Lib.ab(K, "KitchenDoor", xa + 0.03, y + 0.35, 33.76, xa + 2.01, y + 2.9, 33.8, Look.of(242, 242, 238))
			Lib.ab(K, "KitchenPull", xa + 0.8, y + 2.6, 33.72, xa + 1.24, y + 2.66, 33.76, Look.chrome)
		end
		Lib.ab(K, "KitchenToeKick", -14.8, y, 33.9, -4.6, y + 0.35, 33.95, Look.charcoal)
		Lib.ab(K, "UpperCabinet", -14.8, y + 5.4, 35.0, -4.6, y + 7.6, 36.0, Look.of(236, 236, 232))
		Lib.ab(K, "Backsplash", -14.8, y + 3.15, 35.96, -4.6, y + 5.4, 36.0, Look.tileWhite)
	end)
	-- 싱크 + 수전
	K:free(function()
		Lib.ab(K, "KitchenSink", -13.3, y + 3.1, 34.2, -11.7, y + 3.16, 35.4, Look.steel)
		Lib.ab(K, "KitchenSinkIn", -13.15, y + 3.16, 34.35, -11.85, y + 3.17, 35.25, Look.of(150, 154, 158, M.Metal))
	end)
	local kfaucet = K:vcyl("KitchenFaucet", 1.0, 0.16, CF(-12.5, y + 3.65, 35.65), Look.chrome)
	K:cyl("KitchenSpout", 0.7, 0.12, CF(-12.5, y + 4.15, 35.35) * ANG(0, PI / 2, 0), Look.chrome)
	local tap = false
	Interact.prompt(K, kfaucet, { action = "물 틀기", object = "싱크대", sound = SND.click, fn = function(_n, pr)
		tap = not tap
		pr.ActionText = if tap then "물 잠그기" else "물 틀기"
		if tap then
			local s = Lib.temp(K, "TapWater", V3(0.95, 0.07, 0.07), CF(-12.5, y + 3.6, 35.05) * ANG(0, 0, PI / 2), Look.of(180, 220, 240, M.Glass, { t = 0.45 }), Enum.PartType.Cylinder)
			local snd = Lib.sfx(kfaucet, SND.water, { vol = 0.25, speed = 1.3, loop = true, dur = 20 })
			task.spawn(function()
				local t0 = os.clock()
				while tap and os.clock() - t0 < 20 and s.Parent do
					task.wait(0.2)
				end
				tap = false
				pr.ActionText = "물 틀기"
				s:Destroy()
				if snd and snd.Parent then
					snd:Destroy()
				end
			end)
		end
	end })
	-- 커피 머신
	local cm = K:box("CoffeeMachine", V3(1.2, 1.6, 1.3), CF(-9.8, y + 3.95, 35.2), Look.black)
	K:box("CoffeeMachineFace", V3(1.0, 0.5, 0.02), CF(-9.8, y + 4.4, 34.54), Look.chrome)
	K:box("CoffeeMachineTray", V3(0.8, 0.05, 0.4), CF(-9.8, y + 3.2, 34.5), Look.chrome)
	K:disc("CoffeeMachineLED", 0.08, 0.02, CF(-9.4, y + 4.55, 34.53) * ANG(PI / 2, 0, 0), Look.ledBlue)
	Interact.prompt(K, cm, { action = "커피 내리기", object = "커피 머신", sound = SND.click, fn = function()
		local cup = Lib.temp(K, "CoffeeCup", V3(0.4, 0.3, 0.3), CF(-9.8, y + 3.45, 34.55) * ANG(0, 0, PI / 2), Look.white, Enum.PartType.Cylinder)
		Lib.particles(cup, "steam", 3, Enum.NormalId.Right) -- 눕힌 원통: +X 가 위
		Lib.sfx(cm, SND.water, { vol = 0.3, speed = 0.9, dur = 2.5 })
		task.delay(3, function()
			UI.toast("따뜻한 아메리카노 ☕", 2.2)
		end)
		task.delay(25, function()
			if cup.Parent then
				cup:Destroy()
			end
		end)
	end })
	-- 전자레인지
	local mw = K:box("Microwave", V3(1.6, 0.95, 1.2), CF(-7.1, y + 3.63, 35.3), Look.of(230, 230, 228))
	local mwDoor = K:box("MicrowaveWindow", V3(1.0, 0.6, 0.02), CF(-7.3, y + 3.63, 34.69), Look.with(Look.glassDark, { t = 0.2 }))
	K:box("MicrowavePanel", V3(0.35, 0.7, 0.02), CF(-6.55, y + 3.63, 34.69), Look.charcoal)
	Interact.prompt(K, mw, { action = "데우기", object = "전자레인지", sound = SND.click, fn = function()
		if mwDoor.Parent then
			mwDoor.Material = M.Neon
			mwDoor.Color = C3(255, 214, 140)
		end
		Lib.sfx(mw, SND.wind, { vol = 0.12, speed = 0.4, loop = true, dur = 3 })
		task.delay(3, function()
			if mwDoor.Parent then
				mwDoor.Material = M.Glass
				mwDoor.Color = Color3.fromRGB(40, 46, 52)
			end
			Lib.sfx(mw, SND.chime, { vol = 0.5, speed = 1.0 })
		end)
	end })
	K:vcyl("Kettle", 0.8, 0.6, CF(-5.6, y + 3.55, 35.2), Look.steel)
	K:box("KettleHandle", V3(0.12, 0.5, 0.4), CF(-5.6, y + 3.95, 35.55), Look.black)
	-- 냉장고 (2 도어)
	Lib.wall(K, "FridgeBody", -4.4, y, 33.5, -2.0, y + 6.3, 36.0, Look.of(214, 216, 218, M.Metal))
	local fg = K:group("FridgeDoor", function()
		K:free(function()
			Lib.ab(K, "FridgeDoorUpper", -4.4, y + 2.4, 33.4, -2.0, y + 6.3, 33.5, Look.of(220, 222, 224, M.Metal))
			K:box("FridgeHandle", V3(0.1, 1.4, 0.12), CF(-4.2, y + 3.6, 33.3), Look.chrome)
		end)
	end)
	K:free(function()
		Lib.ab(K, "FridgeDoorLower", -4.4, y + 0.1, 33.4, -2.0, y + 2.35, 33.5, Look.of(220, 222, 224, M.Metal))
		Lib.ab(K, "FridgeInside", -4.3, y + 2.5, 33.5, -2.1, y + 6.2, 33.52, Look.of(250, 252, 255))
		Lib.ab(K, "FridgeShelf", -4.3, y + 4.2, 33.52, -2.1, y + 4.25, 34.4, Look.glassClear)
		K:vcyl("FridgeBottle", 0.9, 0.3, CF(-3.5, y + 4.7, 33.8), Look.of(80, 150, 90, M.Glass, { t = 0.3 }))
		K:box("FridgeLunch", V3(0.8, 0.4, 0.6), CF(-2.7, y + 4.45, 33.9), Look.of(230, 120, 80))
	end)
	Interact.swing(K, fg, Geo.W(-2.0, 0, 33.4), Geo.HF.YVector, rad(-100), { object = "냉장고", openText = "냉장고 열기", closeText = "냉장고 닫기" })
	-- 식탁 + 의자 4
	K:free(function()
		Lib.solid(Lib.ab(K, "DiningTop", -10.0, y + 2.65, 26.8, -5.8, y + 2.8, 29.6, Look.of(226, 214, 196, M.Wood)), true)
		for _, tx in { -9.7, -6.1 } do
			for _, tz in { 27.1, 29.3 } do
				Lib.ab(K, "DiningLeg", tx - 0.08, y, tz - 0.08, tx + 0.08, y + 2.65, tz + 0.08, Look.blackMetal)
			end
		end
		K:vcyl("TableTissue", 0.4, 0.5, CF(-7.9, y + 3.0, 28.2), Look.white)
	end)
	for _, c in { { -9.0, 25.9, 0 }, { -6.8, 25.9, 0 }, { -9.0, 30.5, PI }, { -6.8, 30.5, PI } } do
		Props.chair(K, CF(c[1], y, c[2]) * ANG(0, c[3], 0), { style = "padded", detail = if low then "low" else nil })
	end
	-- 천장: LED 4 (빛 2) · 에어컨 · 감지기 · 스프링클러
	local pl1 = panel(K, -18.0, 26.0, ct)
	panel(K, -18.0, 32.0, ct)
	local pl2 = panel(K, -7.0, 26.0, ct)
	panel(K, -7.0, 32.0, ct)
	K:light(pl1, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 18, Brightness = 1.0, Angle = 150, Color = Look.coolLight })
	K:light(pl2, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 18, Brightness = 1.0, Angle = 150, Color = Look.coolLight })
	K:free(function()
		K:box("ACCassette", V3(2.6, 0.25, 2.6), CF(-12.5, ct - 0.125, 29.0), Look.white)
		K:box("ACGrille", V3(1.6, 0.02, 1.6), CF(-12.5, ct - 0.26, 29.0), Look.of(200, 200, 200))
		K:disc("SmokeDetector", 0.55, 0.12, CF(-12.5, ct - 0.06, 33.0), Look.white)
		K:disc("Sprinkler", 0.28, 0.1, CF(-15.0, ct - 0.05, 29.0), Look.brass)
		K:disc("Sprinkler", 0.28, 0.1, CF(-5.0, ct - 0.05, 29.0), Look.brass)
	end)
	Interact.lightSwitch(K, sw, "휴게실 조명")
	if not low then
		Props.floorPlant(K, CF(-23.0, y, 31.6), { kind = "snake", h = 3.2, dia = 1.1 })
		K:box("Rug", V3(5.6, 0.02, 3.6), CF(-19.6, y + 0.01, 31.7), Look.of(170, 160, 146, M.Fabric))
	end
end

-- P2 창고 -------------------------------------------------------------------------------------------

local LABELS = {
	"거즈", "주사기 1cc", "주사기 3cc", "주사기 5cc", "수액세트", "생리식염수 1L", "마스크 KF94", "니트릴 장갑 M",
	"니트릴 장갑 L", "알코올 솜", "드레싱 키트", "소독제", "붕대", "반창고", "검체 용기", "체온계 커버", "환자복", "시트 · 베개커버", "일회용 가운",
}

-- 선반 한 칸 (벽을 따라): 축 "x" (벽이 x = 고정, 선반이 z 로 길다) 또는 "z". a0..a1 = 길이 범위, d0..d1 = 깊이 범위, n = 보는 쪽 법선
local function shelfBay(K: any, axis: string, a0: number, a1: number, d0: number, d1: number, nx: number, nz: number, li: { n: number })
	local low = K.detail == "low"
	local mid = K.detail == "mid"
	local frame = Look.of(110, 116, 122, M.Metal)
	local shelfL = Look.of(196, 200, 204, M.Metal)
	local function box3(name: string, a: number, b: number, ya: number, yb: number, da: number, db: number, look: any)
		if axis == "x" then
			return Lib.ab(K, name, da, ya, a, db, yb, b, look)
		end
		return Lib.ab(K, name, a, ya, da, b, yb, db, look)
	end
	K:free(function()
		for _, a in { a0, a1 - 0.12 } do
			for _, d in { d0, d1 - 0.12 } do
				box3("ShelfUpright", a, a + 0.12, F, F + 6.6, d, d + 0.12, frame)
			end
		end
		for _, h in { 0.3, 1.8, 3.3, 4.8, 6.3 } do
			box3("ShelfDeck", a0, a1, F + h, F + h + 0.06, d0, d1, shelfL)
		end
	end)
	-- 상자 (선반마다 2 ~ 3)
	local len = a1 - a0
	for si, h in { 0.3, 1.8, 3.3, 4.8 } do
		local count = if low then 1 elseif mid then 2 else (if len > 5.5 then 3 else 2)
		for bi = 1, count do
			li.n += 1
			local label = LABELS[(li.n - 1) % #LABELS + 1]
			local seg = len / count
			local ca = a0 + seg * (bi - 0.5)
			local bw = math.min(seg - 0.35, 2.2)
			local bh = if si == 1 then 1.2 else 1.1
			local white = (li.n % 3 == 0)
			local look = if white then Look.of(240, 240, 236) else Look.kraft
			local dd = (d1 - d0) - 0.3
			K:free(function()
				box3("SupplyBox", ca - bw / 2, ca + bw / 2, F + h + 0.06, F + h + 0.06 + bh, d0 + 0.15, d0 + 0.15 + dd, look)
			end)
			if not low or si == 2 then
				-- 앞면 라벨
				-- 상자 앞면 (보는 쪽)
				local fcf: CFrame
				if axis == "x" then
					fcf = Lib.face(if nx > 0 then d0 + 0.15 + dd + 0.002 else d0 + 0.15 - 0.002, F + h + 0.06 + bh * 0.55, ca, nx, nz)
				else
					fcf = Lib.face(ca, F + h + 0.06 + bh * 0.55, if nz > 0 then d0 + 0.15 + dd + 0.002 else d0 + 0.15 - 0.002, nx, nz)
				end
				Lib.tx(K, "SupplyLabel", math.min(bw - 0.2, 1.6), 0.38, fcf, label, C.INK, C.WHITE, { font = Lib.FONT_B })
			end
		end
	end
end

-- 접힌 휠체어 (옆으로 세워 둠): pcf 바닥, +Z = 앞
local function foldedWheelchair(K: any, pcf: CFrame)
	local fr = Look.chrome
	for _, sx in { -0.12, 0.12 } do
		K:make("Part", "WheelchairWheel", V3(0.12, 2.0, 2.0), pcf * CF(sx * 2, 1.0, -0.1), Look.rubber, Enum.PartType.Cylinder)
		K:make("Part", "WheelchairRim", V3(0.13, 1.7, 1.7), pcf * CF(sx * 2, 1.0, -0.1), fr, Enum.PartType.Cylinder)
	end
	K:seg("WheelchairFrame", (pcf * CF(0, 0.5, 0.6)).Position, (pcf * CF(0, 3.4, -0.6)).Position, 0.1, fr)
	K:seg("WheelchairFrame", (pcf * CF(0, 3.4, -0.6)).Position, (pcf * CF(0, 3.6, -0.9)).Position, 0.1, fr)
	K:box("WheelchairSeat", V3(0.2, 1.4, 1.2), pcf * CF(0, 2.2, 0.0), Look.of(40, 44, 60, M.Fabric))
	K:box("WheelchairBack", V3(0.2, 1.4, 1.0), pcf * CF(0, 3.0, -0.5), Look.of(40, 44, 60, M.Fabric))
	K:seg("WheelchairFoot", (pcf * CF(0, 0.3, 0.8)).Position, (pcf * CF(0, 1.4, 0.6)).Position, 0.08, fr)
	K:make("Part", "WheelchairCaster", V3(0.12, 0.5, 0.5), pcf * CF(0, 0.25, 0.9), Look.rubber, Enum.PartType.Cylinder)
end

function Rooms.store(K: any, env: any, P: any)
	local UI = env.UI
	local low = K.detail == "low"
	local x0, x1, z0, z1, ct = -30.0, -15.0, 2.0, 14.0, -41.4
	local y = F
	shell(K, x0, x1, z0, z1, ct, {
		floor = sol(Look.of(120, 124, 128, M.Concrete)),
		wall = sol(Look.of(206, 206, 200, M.Concrete)),
		ceil = sol(Look.of(226, 226, 222, M.Concrete)),
		base = Look.of(60, 62, 66),
	})
	-- 에폭시 바닥 광택 + 안전선
	K:free(function()
		Lib.ab(K, "EpoxyGloss", x0, y, z0, x1, y + 0.01, z1, Look.of(132, 138, 142, M.SmoothPlastic, { r = 0.06 }))
		Lib.ab(K, "SafetyLine", x0 + 2.0, y + 0.01, z0 + 0.2, x0 + 2.12, y + 0.02, z1 - 2.0, Look.of(240, 200, 40))
	end)
	-- 문 + 나가기
	local dg, lever = roomDoorLeaf(K, "StoreRoomDoor", -23.975, -20.225, z0, y, 7.6, Look.of(150, 154, 158, M.Metal), true)
	K.doorFx = { hall = crackMover(K, dg, -20.225, z0, 1) }
	if lever then
		Interact.prompt(K, lever, { action = "나가기", object = "1층 후면 홀", sound = SND.click, fn = function()
			P.back("store", "hall")
		end })
	end
	Lib.plate(K, "StoreExitPlate", 2.4, 0.5, Lib.face(-22.1, y + 8.05, z0, 0, 1), "나가는 문 · 1층 후면 홀", { bg = C3(110, 114, 118), fg = C.WHITE })
	local sw = Props.switchPlate(K, Lib.face(-19.4, y + 4.0, z0, 0, 1), 1)
	-- 선반: A 서쪽 벽 (2 칸), B 북쪽 벽 (2 칸), C 동쪽 벽 (1 칸)
	local li = { n = 0 }
	shelfBay(K, "x", 3.0, 8.0, -30.0, -28.3, 1, 0, li)
	shelfBay(K, "x", 8.0, 13.0, -30.0, -28.3, 1, 0, li)
	shelfBay(K, "z", -28.0, -22.5, 12.3, 14.0, 0, -1, li)
	shelfBay(K, "z", -22.5, -17.0, 12.3, 14.0, 0, -1, li)
	shelfBay(K, "x", 6.0, 13.0, -16.7, -15.0, -1, 0, li)
	-- 린넨 카트
	K:free(function()
		local cx0, cx1, cz0, cz1 = -24.0, -21.4, 8.0, 9.6
		for _, px in { cx0, cx1 - 0.1 } do
			for _, pz in { cz0, cz1 - 0.1 } do
				Lib.ab(K, "CartPost", px, y + 0.3, pz, px + 0.1, y + 3.6, pz + 0.1, Look.steel)
				K:make("Part", "CartCaster", V3(0.12, 0.3, 0.3), CF(px + 0.05, y + 0.15, pz + 0.05), Look.rubber, Enum.PartType.Cylinder)
			end
		end
		for i, h in { 0.5, 1.7, 2.9 } do
			Lib.ab(K, "CartShelf", cx0, y + h, cz0, cx1, y + h + 0.06, cz1, Look.steel)
			for j = 0, 1 do
				local col = if (i + j) % 2 == 0 then Look.of(248, 248, 246, M.Fabric) else Look.of(196, 224, 236, M.Fabric)
				Lib.ab(K, "FoldedLinen", cx0 + 0.15 + j * 1.2, y + h + 0.06, cz0 + 0.2, cx0 + 1.2 + j * 1.2, y + h + 0.5, cz1 - 0.2, col)
			end
		end
		Lib.ab(K, "CartHamper", cx1 + 0.05, y + 1.0, cz0 + 0.1, cx1 + 1.25, y + 3.4, cz1 - 0.1, Look.of(70, 90, 120, M.Fabric))
	end)
	Lib.guard(K, "CartCollider", -24.0, y, 8.0, -20.1, y + 3.6, 9.6)
	-- 접힌 휠체어 2
	if not low then
		foldedWheelchair(K, CF(-16.2, y, 3.4) * ANG(0, PI / 2, 0))
		foldedWheelchair(K, CF(-16.2, y, 4.7) * ANG(0, PI / 2, 0))
	end
	-- 산소통 3 + 체인 + 표지
	for _, cx in { -29.0, -27.9, -26.8 } do
		K:vcyl("O2Cylinder", 4.0, 0.85, CF(cx, y + 2.0, 2.5), Look.of(40, 120, 70, M.Metal))
		K:ball("O2Shoulder", 0.85, CF(cx, y + 4.0, 2.5), Look.white)
		K:vcyl("O2Valve", 0.45, 0.25, CF(cx, y + 4.55, 2.5), Look.brass)
		if not low then
			K:box("O2Tag", V3(0.3, 0.4, 0.02), CF(cx, y + 3.0, 2.06), Look.white)
		end
	end
	Lib.guard(K, "O2Collider", -29.5, y, 2.07, -26.3, y + 4.6, 2.95)
	K:seg("O2Chain", V3(-29.6, y + 3.2, 2.05), V3(-26.2, y + 3.2, 2.05), 0.06, Look.steel)
	K:box("O2Bracket", V3(3.8, 0.3, 0.12), CF(-27.9, y + 3.2, 2.06), Look.of(100, 104, 108, M.Metal))
	Lib.tx(K, "O2Sign", 2.6, 0.7, Lib.face(-27.9, y + 6.0, z0, 0, 1), "산소 O₂ · 화기엄금", C.WHITE, C.RED, { font = Lib.FONT_K })
	-- 수액대 2 · 사다리
	for _, ip in { { -18.4, 3.2 }, { -17.6, 3.6 } } do
		K:vcyl("IVPole", 6.4, 0.1, CF(ip[1], y + 3.3, ip[2]), Look.chrome)
		K:seg("IVHook", V3(ip[1] - 0.4, y + 6.4, ip[2]), V3(ip[1] + 0.4, y + 6.4, ip[2]), 0.06, Look.chrome)
		for k = 0, 4 do
			local a = k * 2 * PI / 5
			K:seg("IVBase", V3(ip[1], y + 0.2, ip[2]), V3(ip[1] + math.cos(a) * 0.7, y + 0.1, ip[2] + math.sin(a) * 0.7), 0.06, Look.chrome)
		end
	end
	if not low then
		local lcf = CF(-25.6, y, 11.1)
		for _, sx in { -0.6, 0.6 } do
			K:seg("LadderRail", (lcf * CF(sx, 0, -0.6)).Position, (lcf * CF(sx * 0.7, 4.0, 0)).Position, 0.1, Look.alu)
			K:seg("LadderRail", (lcf * CF(sx, 0, 0.6)).Position, (lcf * CF(sx * 0.7, 4.0, 0)).Position, 0.1, Look.alu)
		end
		for k = 1, 3 do
			K:box("LadderStep", V3(1.1, 0.08, 0.35), lcf * CF(0, k * 1.0, -0.6 + k * 0.15), Look.alu)
		end
	end
	-- 재고 점검표 (클립보드) + 안내
	local cb = Lib.face(x0, y + 4.6, 2.9, 1, 0)
	local clip = K:plate("Clipboard", 1.0, 1.4, 0.05, cb, Look.of(120, 90, 60, M.Wood))
	Lib.tx(K, "ClipboardText", 0.86, 1.1, cb * CF(0, -0.05, 0.055), "재고 점검표\n10/16\n거즈 42\n주사기 3cc 120\n수액세트 36\nKF94 400\n장갑 M 12박스", C.INK, C.WHITE, { font = Lib.FONT_M })
	K:box("ClipboardClip", V3(0.14, 0.12, 0.5), CF(x0 + 0.12, y + 5.25, 2.9), Look.chrome)
	Interact.prompt(K, clip, { action = "재고 확인", object = "재고 점검표", fn = function()
		UI.toast("거즈 42 · 주사기 3cc 120 · 수액세트 36 · KF94 400 · 장갑 M 12박스 (10/16 점검 · 간호부 박선생)", 4)
	end })
	note(K, Lib.face(-24.3, y + 7.2, 14.0, 0, -1), 3.4, 0.5, "선입선출 (FIFO) · 유효기간 확인", C.WHITE, C.TEAL)
	note(K, Lib.face(-15.0, y + 7.2, 9.5, -1, 0), 2.8, 0.5, "물품 반출 시 장부 기록", C.WHITE, C3(110, 114, 118))
	-- 천장 LED 튜브 2 + 빛 2 (선반 사이 통로까지 밝게)
	local tubes = {}
	for _, tz in { 5.5, 10.5 } do
		K:box("TubeLampHousing", V3(5.2, 0.18, 0.5), CF(-22.5, ct - 0.09, tz), Look.white)
		table.insert(tubes, K:box("TubeLampLED", V3(4.9, 0.06, 0.25), CF(-22.5, ct - 0.21, tz), Look.lampCool))
	end
	for _, tube in tubes do
		K:light(tube, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 18, Brightness = 1.1, Angle = 160, Color = Look.coolLight })
	end
	K:free(function()
		K:disc("SmokeDetector", 0.55, 0.12, CF(-22.5, ct - 0.06, 8.0), Look.white)
	end)
	Interact.lightSwitch(K, sw, "창고 조명")
end

-- P3 비상계단 ---------------------------------------------------------------------------------------

function Rooms.stair(K: any, env: any, P: any)
	local low = K.detail == "low"
	local x0, x1, z0, z1, ct = -10.0, -1.4, -24.0, -7.0, -30.5
	local y = F
	local RISE, RUN = 0.6906, 1.0
	local yMid = y + RISE * 8 -- -44.475
	local yTop = yMid + RISE * 8 -- -38.95
	local lowerL = sol(Look.of(150, 152, 154, M.Concrete))
	shell(K, x0, x1, z0, z1, ct, {
		floor = sol(Look.of(140, 142, 146, M.Concrete)),
		wall = sol(Look.of(236, 236, 232, M.Concrete)),
		ceil = sol(Look.of(226, 226, 222, M.Concrete)),
		base = Look.of(60, 62, 66),
	})
	-- 두 톤 벽 (아래 3.5 회색): 아래층 · 중간 · 위층 높이마다
	K:free(function()
		for _, lv in { y, yMid, yTop } do
			Lib.ab(K, "WallLower", x0, lv, z0, x0 + 0.03, lv + 3.5, z1, Look.of(150, 152, 154, M.Concrete))
			Lib.ab(K, "WallLower", x1 - 0.03, lv, z0, x1, lv + 3.5, z1, Look.of(150, 152, 154, M.Concrete))
		end
		Lib.ab(K, "WallLower", x0, y, z0, x1, y + 3.5, z0 + 0.03, Look.of(150, 152, 154, M.Concrete))
		Lib.ab(K, "WallLower", x0, yMid, z1 - 0.03, x1, yMid + 3.5, z1, Look.of(150, 152, 154, M.Concrete))
	end)
	-- 계단 1 (서쪽, 북쪽으로 올라감) · 중간 참 · 계단 2 (동쪽, 남쪽으로 올라감) · 위 참
	local nose = Look.of(240, 200, 40)
	for k = 1, 8 do
		local za, zb = -19.5 + (k - 1) * RUN, -19.5 + k * RUN
		local top = y + RISE * k
		Lib.wall(K, "Step1", -10.0, y, za, -6.0, top, zb, lowerL)
		K:free(function()
			Lib.ab(K, "StepNose", -10.0, top - 0.02, za, -6.0, top + 0.005, za + 0.18, nose)
			if not low then
				Lib.ab(K, "StepNoseDark", -10.0, top - 0.02, za + 0.18, -6.0, top + 0.004, za + 0.26, Look.black)
			end
		end)
	end
	Lib.wall(K, "MidLanding", -10.0, y, -11.5, -1.4, yMid, -7.0, lowerL)
	for k = 1, 8 do
		local zb, za = -11.5 - (k - 1) * RUN, -11.5 - k * RUN
		local top = yMid + RISE * k
		Lib.wall(K, "Step2", -5.4, y, za, -1.4, top, zb, lowerL)
		K:free(function()
			Lib.ab(K, "StepNose", -5.4, top - 0.02, zb - 0.18, -1.4, top + 0.005, zb, nose)
			if not low then
				Lib.ab(K, "StepNoseDark", -5.4, top - 0.02, zb - 0.26, -1.4, top + 0.004, zb - 0.18, Look.black)
			end
		end)
	end
	-- 계단 2 아래 막음 (서쪽 면) + 두 계단 사이 벽
	Lib.wall(K, "FlightGapWall", -6.0, y, -19.5, -5.4, yMid, -11.5, lowerL)
	Lib.wall(K, "TopLanding", -5.4, yTop - 0.5, -24.0, -1.4, yTop, -19.5, lowerL)
	-- 위 참 서쪽 끝: 철판 + 유리 난간 (3.3) + 보이지 않는 막이
	K:free(function()
		Lib.ab(K, "TopRailPanel", -5.5, yTop, -24.0, -5.4, yTop + 1.2, -19.5, Look.of(110, 116, 122, M.Metal))
		Lib.ab(K, "TopRailGlass", -5.48, yTop + 1.2, -24.0, -5.42, yTop + 3.1, -19.5, Look.glass(Color3.fromRGB(200, 220, 226), 0.5))
		K:seg("TopRailBar", V3(-5.45, yTop + 3.2, -24.0), V3(-5.45, yTop + 3.2, -19.5), 0.16, Look.steel)
	end)
	Lib.guard(K, "TopRailGuard", -5.6, yTop, -24.0, -5.4, yTop + 6.0, -19.5)
	-- 계단 2 서쪽 끝 (아래로 떨어지지 않게): 보이는 난간 + 보이지 않는 막이
	Lib.guard(K, "Flight2Guard", -5.6, yMid, -19.5, -5.4, yTop + 4.0, -11.5)
	K:free(function()
		K:seg("Flight2Rail", V3(-5.5, yMid + 3.0, -11.5), V3(-5.5, yTop + 3.0, -19.5), 0.16, Look.steel)
		if not low then
			for k = 0, 8 do
				local zz = -11.5 - k
				local tp = yMid + RISE * k
				K:seg("Baluster", V3(-5.5, tp, zz), V3(-5.5, tp + 3.0, zz), 0.08, Look.steel)
			end
		end
	end)
	-- 손잡이 (벽 쪽 + 두 계단 사이)
	K:free(function()
		K:seg("Handrail", V3(-9.85, y + 3.0, -19.5), V3(-9.85, yMid + 3.0, -11.5), 0.16, Look.steel)
		K:seg("Handrail", V3(-1.55, yMid + 3.0, -11.5), V3(-1.55, yTop + 3.0, -19.5), 0.16, Look.steel)
		K:seg("Handrail", V3(-6.05, y + 3.0, -19.5), V3(-6.05, yMid + 3.0, -11.5), 0.16, Look.steel)
	end)
	-- 문 2 (남쪽 벽): 아래 = 2F, 위 = RF
	local d1, lever1 = roomDoorLeaf(K, "StairDoorBottom", -9.7, -6.3, z0, y, 7.2, Look.of(214, 210, 198, M.Metal), true)
	local d2, lever2 = roomDoorLeaf(K, "StairDoorTop", -5.1, -1.7, z0, yTop, 7.2, Look.of(130, 136, 140, M.Metal), true)
	K.doorFx = { hall = crackMover(K, d1, -6.3, z0, 1), roof = crackMover(K, d2, -1.7, z0, 1) }
	if lever1 then
		Interact.prompt(K, lever1, { action = "2층으로 나가기", object = "비상계단 2F", sound = SND.click, fn = function()
			P.back("stair", "hall")
		end })
	end
	if lever2 then
		Interact.prompt(K, lever2, { action = "옥상으로 나가기", object = "비상계단 RF", sound = SND.click, fn = function()
			P.back("stair", "roof")
		end })
	end
	Lib.exitSign(K, Lib.face(-8.0, y + 7.85, z0, 0, 1), 1.6, "🏃 2F 출구", "door")
	Lib.exitSign(K, Lib.face(-3.4, yTop + 7.85, z0, 0, 1), 1.6, "🏃 옥상 출구", "door")
	-- 층 그래픽
	Lib.tx(K, "FloorGraphic2F", 2.6, 3.0, Lib.face(x0, y + 4.2, -21.8, 1, 0), "2F", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	Lib.tx(K, "FloorGraphicMid", 4.0, 1.4, Lib.face(-5.7, yMid + 4.4, z1, 0, -1), "RF ↑ 옥상", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	Lib.tx(K, "FloorGraphicRF", 2.6, 2.6, Lib.face(x1, yTop + 4.0, -21.8, -1, 0), "RF\n옥상", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	Lib.tx(K, "RoofDoorNote", 3.0, 0.5, Lib.face(-3.4, yTop + 8.9, z0, 0, 1), "옥상 출입문 · 비상시 자동 개방", C.WHITE, C.RED, { font = Lib.FONT_B })
	Lib.exitSign(K, Lib.face(-5.7, yMid + 2.0, z1, 0, -1), 1.2, "🏃 → 2F", "path") -- 북쪽 벽을 보면 서쪽(아래 계단)이 오른쪽
	-- 소화기
	K:vcyl("StairExtinguisher", 1.5, 0.5, CF(-9.5, y + 0.85, -23.4), Look.of(214, 36, 36))
	Lib.tx(K, "StairExtLabel", 0.8, 0.3, Lib.face(x0, y + 2.3, -23.4, 1, 0), "소화기", C.WHITE, C.RED, { font = Lib.FONT_K })
	-- 벽등 2 (아래 참 · 위 참)
	local function bulkhead(dcf: CFrame): BasePart
		K:plate("BulkheadBody", 1.0, 0.6, 0.25, dcf, Look.of(60, 62, 66, M.Metal))
		return K:plate("BulkheadLens", 0.8, 0.42, 0.06, dcf * CF(0, 0, 0.25), Look.lampNeutral)
	end
	local l1 = bulkhead(Lib.face(x0, y + 6.8, -16.0, 1, 0))
	local l2 = bulkhead(Lib.face(x1, yTop + 6.0, -22.0, -1, 0))
	K:light(l1, "PointLight", { Range = 14, Brightness = 0.9, Color = Look.neutralLight })
	K:light(l2, "PointLight", { Range = 14, Brightness = 0.9, Color = Look.neutralLight })
end

return Rooms
