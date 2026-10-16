--!strict
-- GwangalliBuildingInterior/Hosp_Signs: 길 안내 표지 (설계 §7.9).
--   * 층 번호: 1F (계단 입구 Sign_2F ↑ 옆), 2F (계단홀 CheckupWall), "↓ 1F"
--   * 2F 건강검진 안내판 (새 승강로 자리에서 옆 PartyWall 로 옮겨 다시 그림)
--   * 2F 복도 통로유도등 (계단 · 비상구 쪽 화살표)
--   * 1F 후면 홀 층별 안내 보조판 (엘리베이터 · 화장실 · 직원 휴게실 · 창고 · 비상구 방향)
-- 피난구 유도등 · 문 명판은 문을 만드는 모듈이 같이 그림 (Hosp_Doors · Hosp_Exits · Hosp_Elevator · Hosp_Rooms).

local here = script.Parent
local Lib = require(here:WaitForChild("Hosp_Lib"))
local Look = require(here:WaitForChild("Look"))

local S = {}

local CF = CFrame.new

local Geo = Lib.Geo
local C = Geo.C

function S.build(K: any, _env: any)
	local low = K.detail == "low"
	-- 1F 층 번호 (BackWall 북쪽 면, 홀을 봄)
	Lib.tx(K, "FloorNo1F", 1.6, 1.6, Lib.face(25.2, 8.5, 22.18, 0, 1), "1F", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	-- 2F 층 번호 (계단홀 서쪽 벽 CheckupWall 동쪽 면)
	Lib.tx(K, "FloorNo2F", 3.0, 3.0, Lib.face(-8.09, 18.7, 30.0, 1, 0), "2F", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	Lib.tx(K, "FloorDown1F", 1.4, 0.7, Lib.face(-8.09, 18.4, 25.25, 1, 0), "↓ 1F", C.TEAL_D, C.WHITE, { font = Lib.FONT_K })
	-- 2F 건강검진 안내판 (PartyWall 안쪽 면, -z 를 봄)
	local g = Lib.face(-23.7, 19.2, 38.94, 0, -1)
	K:plate("CheckupGuideBack", 7.4, 4.0, 0.06, g, Look.of(250, 250, 248))
	Lib.tx(K, "CheckupGuideTitle", 7.2, 0.8, g * CF(0, 1.5, 0.065), "건강검진 안내  CHECK-UP GUIDE", C.WHITE, C.TEAL, { font = Lib.FONT_K })
	local steps = { "① 접수", "② 신체계측", "③ 혈압", "④ 시력", "⑤ 청력", "⑥ 심전도", "⑦ 상담" }
	for i, s in steps do
		local cx = -3.15 + (i - 1) * 1.05
		Lib.tx(K, "CheckupStep", 0.98, 0.9, g * CF(cx, 0.35, 0.065), s, C.TEAL_D, C.MINT_L, { font = Lib.FONT_B, wrap = true })
		if i < #steps and not low then
			Lib.tx(K, "CheckupArrow", 0.2, 0.3, g * CF(cx + 0.525, 0.35, 0.07), "›", C.TEAL, nil, { font = Lib.FONT_K })
		end
	end
	Lib.tx(K, "CheckupGuideNote", 7.0, 0.9, g * CF(0, -1.05, 0.065), "검진 당일 아침 금식 · 접수 08:30 ~ 17:00\n결과는 2주 뒤 문자로 알려 드려요", C.INK, nil, { font = Lib.FONT_M })
	-- 2F 복도 통로유도등 (WardWall 복도 면, 낮게)
	Lib.exitSign(K, Lib.face(30.0, 14.15 + 1.2, -9.82, 0, 1), 1.2, "← 🏃 계단", "path")
	Lib.exitSign(K, Lib.face(-40.0, 14.15 + 1.2, -9.82, 0, 1), 1.2, "계단 🏃 →", "path")
	if not low then
		-- 1F 후면 홀 방향 안내 (엘리베이터 승강로 동쪽 면 바깥, +x 를 봄)
		local d = Lib.face(Geo.LIFT.x1, 5.6, 36.2, 1, 0)
		K:plate("HallGuideBack", 4.4, 3.4, 0.05, d, Look.of(250, 250, 248))
		Lib.tx(K, "HallGuideTitle", 4.2, 0.6, d * CF(0, 1.35, 0.055), "1F 후면 홀 안내", C.WHITE, C.TEAL, { font = Lib.FONT_K })
		local rows = {
			{ "🛗 엘리베이터", "← 바로 옆" },
			{ "🚻 화장실", "← 서쪽 끝" },
			{ "🔒 직원 휴게실 · 창고", "→ 뒷벽" },
			{ "🏃 비상구 · 2F 계단", "→ 동쪽" },
		}
		for i, r in rows do
			local ry = 0.6 - (i - 1) * 0.62
			Lib.tx(K, "HallGuideName", 2.6, 0.5, d * CF(-0.75, ry, 0.055), r[1], C.INK, nil, { font = Lib.FONT_B, align = "Left" })
			Lib.tx(K, "HallGuideDir", 1.4, 0.5, d * CF(1.4, ry, 0.055), r[2], C.TEAL_D, nil, { font = Lib.FONT_M, align = "Right" })
		end
	end
end

function S.ready(_env: any): boolean
	return Lib.hospital() ~= nil
end

return S
