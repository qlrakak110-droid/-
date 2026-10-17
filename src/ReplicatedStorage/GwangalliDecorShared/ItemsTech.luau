--!strict
-- GwangalliDecorShared/ItemsTech: 가전·전자 — TV (채널 바꾸기) · 빔프로젝터 · 게임기 · 스피커 (음악) ·
-- 턴테이블 · 로봇청소기 · 공기청정기 · 의류관리기 · 안마의자 · 에어컨.
-- Parts flagged `screen` show the client's TV channels when the piece is on.

return function(D: any)
	local S = D.slot
	local BODY = { "plastic", "gloss", "brushed", "metal" }

	-- 액자형 TV (벽걸이) ---------------------------------------------------------------------------
	D.item({
		id = "tc_tv_frame", cat = "tech", name = "65형 액자형 TV (벽걸이)", price = 1890000, decor = 6, style = "modern", place = "wall",
		size = { 5.8, 3.4, 0.35 }, tags = { "TV", "티비", "액자", "벽걸이" },
		slots = { S("bezel", "베젤 프레임", "walnut", { "wood", "plastic", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("Mount", 2.0, 1.2, 0.1, 0, H / 2, Dp / 2 - 0.05, k:lit({ 40, 40, 44 }, "metal"))
			k:tvPanel(W, H, 0, H / 2, -Dp / 2 + 0.05, "bezel", Dp - 0.12)
		end,
	})

	-- 스탠드 TV ------------------------------------------------------------------------------------
	D.item({
		id = "tc_tv_stand", cat = "tech", name = "75형 QLED TV + 이젤 스탠드", price = 2490000, decor = 6, style = "modern", place = "floor",
		size = { 6.6, 6.0, 2.4 }, tags = { "TV", "티비", "스탠드", "거실" },
		slots = { S("bezel", "베젤", "black", BODY), S("stand", "스탠드", "gunmetal", { "metal", "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Base", 2.4, 0.12, 1.8, 0, 0.06, 0.2, "stand", { solid = true })
			k:box("Pole", 0.4, 3.2, 0.25, 0, 1.7, 0.45, "stand")
			k:tvPanel(W, 3.7, 0, 4.1, 0.15, "bezel", 0.2)
			k:box("Soundbar", 3.0, 0.3, 0.4, 0, 2.0, 0.1, k:lit({ 30, 30, 34 }, "fabric"))
		end,
	})

	-- 빔프로젝터 스크린 ----------------------------------------------------------------------------
	D.item({
		id = "tc_projector_screen", cat = "tech", name = "빔프로젝터 + 롤 스크린 (홈시어터)", price = 1290000, decor = 6, style = "trendy", place = "wall",
		size = { 7.0, 4.8, 0.6 }, tags = { "빔프로젝터", "스크린", "홈시어터", "영화" },
		slots = { S("case", "케이스", "white", BODY) },
		build = function(k, W, H, Dp)
			k:box("Case", W, 0.35, 0.4, 0, H - 0.18, Dp / 2 - 0.2, "case", { solid = true })
			k:box("Screen", W - 0.5, H - 0.7, 0.03, 0, (H - 0.7) / 2 + 0.25, Dp / 2 - 0.2, k:lit({ 236, 236, 236 }, "fabric"), { screen = true })
			k:box("BlackBorder", W - 0.5, 0.12, 0.035, 0, H - 0.42, Dp / 2 - 0.21, k:lit({ 20, 20, 22 }))
			k:box("Bar", W - 0.4, 0.1, 0.1, 0, 0.22, Dp / 2 - 0.2, k:lit({ 40, 40, 44 }, "metal"))
		end,
	})

	-- 게임 콘솔 ------------------------------------------------------------------------------------
	D.item({
		id = "tc_console", cat = "tech", name = "게임 콘솔 + 듀얼 패드", price = 690000, decor = 3, style = "trendy", place = "surface",
		size = { 1.6, 1.4, 1.0 }, tags = { "게임기", "콘솔", "게임" }, light = "blue", glow = true, toggle = false,
		slots = { S("body", "본체", "white", { "gloss", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Body", 0.5, 1.35, 0.95, -0.5, 0.675, 0, "body", { solid = true })
			k:box("Core", 0.32, 1.25, 0.9, -0.5, 0.67, 0, k:lit({ 30, 30, 34 }))
			k:box("LED", 0.04, 0.9, 0.02, -0.25, 0.7, -0.48, "light", { glow = true })
			for i = 0, 1 do
				local x = 0.25 + i * 0.5
				k:box("Pad", 0.42, 0.1, 0.28, x, 0.06, -0.1 + i * 0.25, if i == 0 then "body" else k:lit({ 30, 30, 34 }), { ry = -12 + i * 20 })
				k:ball("Grip", 0.16, x - 0.18, 0.06, -0.02 + i * 0.25, if i == 0 then "body" else k:lit({ 30, 30, 34 }))
				k:ball("Grip", 0.16, x + 0.18, 0.06, -0.02 + i * 0.25, if i == 0 then "body" else k:lit({ 30, 30, 34 }))
			end
		end,
	})

	-- 톨보이 스피커 --------------------------------------------------------------------------------
	D.item({
		id = "tc_speaker_tower", cat = "tech", name = "톨보이 스피커 (블루투스)", price = 890000, decor = 4, style = "classic", place = "floor",
		size = { 1.4, 4.4, 1.6 }, tags = { "스피커", "음악", "오디오" }, light = "amber", glow = true, toggle = false,
		slots = { S("wood", "인클로저", "walnut", { "wood", "gloss", "plastic" }), S("grille", "그릴", "charcoal", { "fabric", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("Plinth", W + 0.1, 0.15, Dp + 0.1, 0, 0.075, 0, k:lit({ 30, 30, 34 }, "metal"))
			local body = k:box("Cabinet", W, H - 0.15, Dp, 0, 0.15 + (H - 0.15) / 2, 0, "wood", { solid = true })
			k:box("Baffle", W - 0.1, H - 0.4, 0.05, 0, 0.15 + (H - 0.15) / 2, -Dp / 2 - 0.02, "grille")
			for i, y in { 3.7, 2.7, 1.6 } do
				local d = if i == 1 then 0.4 else 0.9
				k:cyl("Driver", 0.06, d, 0, y, -Dp / 2 - 0.06, "z", k:lit({ 40, 40, 44 }, "metal"))
				k:cyl("Cone", 0.04, d * 0.6, 0, y, -Dp / 2 - 0.09, "z", k:lit({ 70, 70, 76 }, "plastic"))
			end
			k:box("Badge", 0.5, 0.06, 0.02, 0, 0.6, -Dp / 2 - 0.06, "light", { glow = true })
			k:speaker(body)
		end,
	})

	-- 블루투스 스피커 ------------------------------------------------------------------------------
	D.item({
		id = "tc_speaker_bt", cat = "tech", name = "패브릭 블루투스 스피커", price = 159000, decor = 2, style = "modern", place = "surface",
		size = { 1.4, 0.9, 0.7 }, tags = { "스피커", "음악", "블루투스" }, light = "warm", glow = true, toggle = false,
		slots = { S("fabric", "패브릭", "greige", { "fabric" }), S("trim", "테두리", "gold", { "metal", "brushed" }) },
		build = function(k, W, H, Dp)
			local body = k:box("Body", W, H - 0.05, Dp, 0, (H - 0.05) / 2 + 0.05, 0, "fabric", { solid = true })
			k:box("TopPlate", W - 0.06, 0.04, Dp - 0.06, 0, H, 0, "trim")
			k:cyl("Knob", 0.06, 0.18, 0.4, H + 0.04, 0, "y", "trim")
			k:box("Feet", W - 0.2, 0.05, Dp - 0.2, 0, 0.025, 0, k:lit({ 30, 30, 32 }))
			k:box("LED", 0.12, 0.03, 0.02, -0.5, H - 0.12, -Dp / 2 - 0.01, "light", { glow = true })
			k:speaker(body)
		end,
	})

	-- 턴테이블 -------------------------------------------------------------------------------------
	D.item({
		id = "tc_turntable", cat = "tech", name = "LP 턴테이블", price = 420000, decor = 4, style = "classic", place = "surface",
		size = { 1.6, 0.6, 1.3 }, tags = { "턴테이블", "LP", "레코드", "음악" },
		slots = { S("wood", "본체", "walnut", { "wood", "gloss" }) },
		build = function(k, W, H, Dp)
			local body = k:box("Plinth", W, 0.3, Dp, 0, 0.15, 0, "wood", { solid = true, top = true })
			k:cyl("Platter", 0.06, 1.1, -0.18, 0.33, 0, "y", k:lit({ 200, 202, 206 }, "metal"))
			k:cyl("Record", 0.03, 1.0, -0.18, 0.375, 0, "y", k:lit({ 20, 20, 22 }, "gloss"))
			k:cyl("Label", 0.035, 0.32, -0.18, 0.38, 0, "y", k:lit({ 214, 52, 56 }))
			k:cyl("ArmBase", 0.15, 0.18, 0.55, 0.38, 0.35, "y", k:lit({ 200, 202, 206 }, "metal"))
			k:cyl("Tonearm", 0.85, 0.04, 0.35, 0.44, 0.0, "z", k:lit({ 200, 202, 206 }, "metal"), { ry = 25 })
			k:box("Dust", W - 0.05, 0.04, Dp - 0.05, 0, 0.62, 0, k:lit({ 220, 230, 236 }, "glass"), { t = 0.6 })
			k:speaker(body)
		end,
	})

	-- 로봇청소기 -----------------------------------------------------------------------------------
	D.item({
		id = "tc_robot_vacuum", cat = "tech", name = "로봇청소기 + 스테이션", price = 1290000, decor = 2, style = "modern", place = "floor",
		size = { 1.8, 1.8, 1.6 }, tags = { "로봇청소기", "청소기", "가전" }, light = "cool", glow = true, toggle = false,
		slots = { S("body", "본체", "white", { "gloss", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Station", 1.5, 1.7, 0.9, 0, 0.85, 0.35, "body", { solid = true })
			k:box("Tank", 0.6, 0.7, 0.05, -0.35, 1.25, -0.12, k:lit({ 150, 200, 230 }, "glass"), { t = 0.3 })
			k:box("Status", 0.4, 0.05, 0.02, 0.35, 1.5, -0.12, "light", { glow = true })
			k:cyl("Robot", 0.35, 1.2, 0, 0.175, -0.2, "y", "body", { solid = true })
			k:cyl("Lidar", 0.12, 0.3, 0, 0.41, -0.15, "y", k:lit({ 40, 40, 44 }))
			k:box("Bumper", 0.9, 0.2, 0.06, 0, 0.15, -0.8, k:lit({ 40, 40, 44 }))
		end,
	})

	-- 공기청정기 -----------------------------------------------------------------------------------
	D.item({
		id = "tc_air_purifier", cat = "tech", name = "타워형 공기청정기", price = 590000, decor = 2, style = "modern", place = "floor",
		size = { 1.2, 3.4, 1.2 }, tags = { "공기청정기", "가전", "미세먼지" }, light = "green", glow = true, toggle = false,
		slots = { S("body", "본체", "white", { "gloss", "plastic", "brushed" }) },
		build = function(k, W, H, Dp)
			k:cyl("Body", H - 0.3, 1.15, 0, (H - 0.3) / 2, 0, "y", "body", { solid = true })
			for i = 0, 8 do
				k:cyl("Grille", 0.04, 1.17, 0, 0.3 + i * 0.28, 0, "y", k:sh("body", 0.88))
			end
			k:cyl("Top", 0.3, 1.0, 0, H - 0.15, 0, "y", k:lit({ 40, 40, 44 }))
			k:cyl("Ring", 0.04, 0.85, 0, H - 0.02, 0, "y", "light", { glow = true })
		end,
	})

	-- 의류관리기 -----------------------------------------------------------------------------------
	D.item({
		id = "tc_styler", cat = "tech", name = "의류관리기 (스타일러)", price = 1690000, decor = 3, style = "modern", place = "floor",
		size = { 1.6, 6.0, 1.9 }, tags = { "스타일러", "의류관리기", "가전" },
		uses = { open = "문 열기", close = "문 닫기" },
		slots = { S("door", "도어", "charcoal", { "glass", "gloss", "brushed" }) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp - 0.15, 0, H / 2, 0.075, k:lit({ 60, 62, 68 }, "plastic"), { solid = true })
			k:box("Inside", W - 0.2, H - 0.6, 0.05, 0, H / 2, -Dp / 2 + 0.3, k:lit({ 230, 232, 236 }))
			k:box("Shirt", 1.0, 2.0, 0.1, 0, H - 2.0, -0.2, k:lit({ 236, 240, 246 }, "fabric"))
			k:box("Pants", 0.8, 1.8, 0.08, 0, 1.4, 0.1, k:lit({ 60, 70, 90 }, "fabric"))
			local d = k:box("Door", W, H - 0.05, 0.12, 0, H / 2, -Dp / 2 + 0.06, "door", { rf = 0.25 })
			local h = k:box("Handle", 0.06, 1.2, 0.08, W / 2 - 0.15, H / 2 + 0.3, -Dp / 2 - 0.04, k:lit({ 200, 202, 206 }, "metal"))
			k:box("Display", 0.3, 0.1, 0.02, 0, H - 0.6, -Dp / 2 - 0.01, k:lit({ 255, 255, 255 }, "neon"))
			k:hinge({ d, h }, -W / 2, 0, -Dp / 2, "y", 100)
		end,
	})

	-- 안마의자 -------------------------------------------------------------------------------------
	D.item({
		id = "tc_massage_chair", cat = "tech", name = "안마의자 (리클라이너)", price = 3200000, decor = 5, style = "luxury", place = "floor",
		size = { 3.0, 4.2, 4.4 }, tags = { "안마의자", "의자", "가전", "효도" },
		slots = { S("leather", "가죽", "camel", { "leather", "fabric" }), S("shell", "커버", "charcoal", { "gloss", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W - 0.6, 0.6, Dp - 1.6, 0, 0.3, 0.5, "shell", { solid = true })
			k:box("Seat", W - 0.9, 0.5, 2.0, 0, 1.25, 0.3, "leather", { solid = true })
			k:box("Back", W - 0.9, 2.8, 0.7, 0, 2.6, 1.55, "leather", { rx = -18, solid = true })
			k:box("Head", W - 1.1, 0.9, 0.6, 0, 3.85, 1.95, k:sh("leather", 0.9), { rx = -18 })
			for _, sx in { -1, 1 } do
				k:box("Arm", 0.45, 1.6, 2.6, sx * (W / 2 - 0.22), 1.6, 0.6, "shell", { solid = true })
				k:box("ArmPad", 0.4, 0.15, 2.2, sx * (W / 2 - 0.22), 2.45, 0.6, "leather")
				k:box("Remote", 0.15, 0.08, 0.5, sx * (W / 2 - 0.22), 2.56, -0.2, k:lit({ 30, 30, 34 }))
			end
			k:box("LegRest", W - 1.0, 1.4, 0.7, 0, 0.75, -1.4, "leather", { rx = 20 })
			k:box("Foot", W - 1.0, 0.5, 0.9, 0, 0.25, -1.8, "shell")
			k:seat(0, 1.5, 0.2)
		end,
	})

	-- 스탠드 에어컨 --------------------------------------------------------------------------------
	D.item({
		id = "tc_aircon", cat = "tech", name = "스탠드 에어컨", price = 2100000, decor = 2, style = "modern", place = "floor",
		size = { 1.8, 5.8, 1.2 }, tags = { "에어컨", "가전", "여름" }, light = "cool", glow = true, toggle = false,
		slots = { S("body", "본체", "white", { "gloss", "plastic", "brushed" }) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp, 0, H / 2, 0, "body", { solid = true })
			for i = 0, 2 do
				k:cyl("Vent", 0.08, 1.0, 0, H - 1.2 - i * 1.25, -Dp / 2 - 0.02, "z", k:sh("body", 0.85))
				for j = 0, 3 do
					k:cyl("Hole", 0.02, 0.1, -0.3 + j * 0.2, H - 1.2 - i * 1.25, -Dp / 2 - 0.07, "z", k:lit({ 120, 124, 130 }))
				end
			end
			k:box("Panel", W - 0.3, 0.6, 0.03, 0, 1.0, -Dp / 2 - 0.01, k:lit({ 40, 40, 44 }, "gloss"))
			k:box("Temp", 0.4, 0.15, 0.02, 0, 1.0, -Dp / 2 - 0.03, "light", { glow = true })
		end,
	})
end
