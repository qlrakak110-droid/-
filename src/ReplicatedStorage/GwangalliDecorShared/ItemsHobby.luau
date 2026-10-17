--!strict
-- GwangalliDecorShared/ItemsHobby: 취미·게임 — 게이밍 데스크 · 게이밍 의자 · 오락기 · 피아노 · 기타 · 이젤 ·
-- 수족관 (먹이 주기) · 러닝머신 · 다트 · 망원경 · 블록 도시 · 가정용 노래방 기계.

return function(D: any)
	local S = D.slot
	local MET = { "metal", "brushed", "plastic" }

	D.item({
		id = "hb_gaming_desk", cat = "hobby", name = "게이밍 데스크 + 듀얼 모니터", price = 1290000, decor = 6, style = "trendy", place = "floor",
		size = { 5.6, 4.6, 2.6 }, tags = { "책상", "게이밍", "PC", "모니터", "데스크" }, light = "violet",
		slots = { S("top", "상판", "black", { "plastic", "wood", "metal" }), S("frame", "프레임", "matteblack", MET) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Leg", 0.2, 2.35, 1.8, sx * (W / 2 - 0.4), 1.18, 0, "frame", { solid = true })
				k:box("Foot", 0.3, 0.12, Dp - 0.2, sx * (W / 2 - 0.4), 0.06, 0, "frame")
			end
			k:box("Top", W, 0.12, Dp, 0, 2.4, 0, "top", { solid = true, top = true })
			local strip = k:box("LED", W - 0.2, 0.04, 0.04, 0, 2.32, -Dp / 2 + 0.05, "light", { glow = true })
			k:light(strip, 9, 0.7)
			for _, sx in { -1, 1 } do
				local x = sx * 1.25
				k:box("Stand", 0.15, 0.6, 0.15, x, 2.75, 0.75, "frame")
				k:box("StandFoot", 0.6, 0.04, 0.5, x, 2.48, 0.75, "frame")
				k:tvPanel(2.4, 1.45, x, 3.65, 0.55, k:lit({ 24, 24, 28 }), 0.12)
			end
			k:box("Keyboard", 1.6, 0.08, 0.5, -0.2, 2.5, -0.55, k:lit({ 30, 30, 34 }))
			k:box("Keys", 1.5, 0.03, 0.42, -0.2, 2.555, -0.55, "light", { glow = true, t = 0.3 })
			k:box("Pad", 2.6, 0.02, 0.9, 0.2, 2.47, -0.5, k:lit({ 30, 30, 34 }, "fabric"))
			k:box("Mouse", 0.2, 0.08, 0.3, 1.1, 2.51, -0.5, k:lit({ 30, 30, 34 }))
			k:box("Tower", 0.8, 1.6, 1.6, W / 2 - 0.9, 3.26, 0.4, k:lit({ 30, 30, 34 }), { solid = true })
			k:box("TowerGlass", 0.02, 1.4, 1.4, W / 2 - 1.31, 3.26, 0.4, k:lit({ 90, 80, 160 }, "glass"), { t = 0.4 })
			k:cyl("Fan", 0.04, 0.5, W / 2 - 1.3, 3.5, 0.4, "x", "light", { glow = true })
		end,
	})

	D.item({
		id = "hb_gaming_chair", cat = "hobby", name = "게이밍 의자", price = 390000, decor = 3, style = "trendy", place = "floor",
		size = { 2.4, 4.6, 2.4 }, tags = { "의자", "게이밍", "체어" },
		slots = { S("leather", "시트", "black", { "leather", "fabric" }), S("accent", "포인트", "red", { "leather", "fabric" }) },
		build = function(k, W, H, Dp)
			for i = 0, 4 do
				local a = math.rad(i * 72)
				k:box("Star", 0.18, 0.12, 1.0, math.sin(a) * 0.5, 0.25, math.cos(a) * 0.5, k:lit({ 30, 30, 34 }, "metal"), { ry = i * 72 })
				k:ball("Caster", 0.22, math.sin(a) * 1.0, 0.11, math.cos(a) * 1.0, k:lit({ 30, 30, 34 }))
			end
			k:cyl("Gas", 0.9, 0.2, 0, 0.75, 0, "y", k:lit({ 120, 124, 130 }, "metal"))
			k:box("Seat", 1.9, 0.4, 1.9, 0, 1.35, 0, "leather", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Bolster", 0.3, 0.25, 1.8, sx * 0.85, 1.6, 0, "accent")
				k:box("ArmPost", 0.12, 0.7, 0.12, sx * 1.05, 1.75, 0.1, k:lit({ 30, 30, 34 }))
				k:box("ArmPad", 0.25, 0.1, 0.8, sx * 1.05, 2.12, 0.1, k:lit({ 30, 30, 34 }))
			end
			k:box("Back", 1.8, 2.8, 0.35, 0, 3.0, 0.85, "leather", { rx = -10, solid = true })
			k:box("BackStripe", 0.3, 2.6, 0.05, -0.55, 3.0, 0.65, "accent", { rx = -10 })
			k:box("BackStripe", 0.3, 2.6, 0.05, 0.55, 3.0, 0.65, "accent", { rx = -10 })
			k:box("Pillow", 1.0, 0.4, 0.25, 0, 4.0, 0.75, k:sh("leather", 1.4), { rx = -10 })
			k:seat(0, 1.55, 0)
		end,
	})

	D.item({
		id = "hb_arcade", cat = "hobby", name = "레트로 오락기 (스트리트 파이터)", price = 1490000, decor = 6, style = "trendy", place = "floor",
		size = { 2.4, 5.8, 2.6 }, tags = { "오락기", "게임", "아케이드", "레트로" }, light = "magenta",
		slots = { S("cab", "캐비닛", "cobalt", { "gloss", "plastic", "wood" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Side", 0.1, H, Dp, sx * (W / 2 - 0.05), H / 2, 0, "cab", { solid = true })
			end
			k:box("Body", W - 0.2, 3.0, Dp - 0.4, 0, 1.5, 0.2, k:sh("cab", 0.8), { solid = true })
			k:box("Panel", W - 0.2, 0.15, 1.0, 0, 3.0, -0.8, k:lit({ 30, 30, 34 }), { rx = -12, top = true })
			k:box("StickBase", 0.3, 0.04, 0.3, -0.5, 3.12, -0.85, k:lit({ 214, 52, 56 }))
			k:cyl("Stick", 0.35, 0.06, -0.5, 3.3, -0.85, "y", k:lit({ 30, 30, 34 }))
			k:ball("Ball", 0.22, -0.5, 3.48, -0.85, k:lit({ 214, 52, 56 }, "gloss"))
			for i = 0, 5 do
				k:cyl("Btn", 0.06, 0.18, 0.1 + (i % 3) * 0.3, 3.12, -0.95 + (i // 3) * 0.25, "y", k:lit(({ { 246, 206, 60 }, { 64, 168, 90 }, { 40, 84, 196 } })[(i % 3) + 1]))
			end
			k:box("Bezel", W - 0.2, 1.9, 0.12, 0, 4.0, 0.0, k:lit({ 20, 20, 22 }), { rx = -8 })
			k:box("Screen", W - 0.6, 1.6, 0.03, 0, 4.0, -0.08, k:lit({ 10, 10, 14 }, "glass"), { screen = true, rx = -8 })
			local marquee = k:box("Marquee", W - 0.2, 0.6, 0.1, 0, H - 0.35, -0.35, "light", { glow = true })
			k:light(marquee, 9, 0.8)
		end,
	})

	D.item({
		id = "hb_piano", cat = "hobby", name = "업라이트 피아노 + 벤치", price = 4200000, decor = 9, style = "classic", place = "floor",
		size = { 4.8, 4.2, 3.6 }, tags = { "피아노", "악기", "음악" },
		slots = { S("body", "본체", "black", { "gloss", "wood" }), S("bench", "벤치 쿠션", "burgundy", { "velvet", "leather" }) },
		build = function(k, W, H, Dp)
			local zb = Dp / 2 - 0.8
			k:box("Case", W, H, 1.6, 0, H / 2, zb, "body", { solid = true, top = true })
			k:box("KeyBed", W - 0.6, 0.25, 0.9, 0, 2.3, zb - 1.2, "body", { solid = true })
			k:box("White", W - 0.8, 0.08, 0.7, 0, 2.46, zb - 1.25, k:lit({ 246, 246, 240 }))
			for i = 0, 35 do
				if i % 7 ~= 2 and i % 7 ~= 6 then
					k:box("Black", 0.06, 0.08, 0.4, -W / 2 + 0.55 + i * 0.105, 2.53, zb - 1.12, k:lit({ 20, 20, 22 }))
				end
			end
			k:box("Music", 1.4, 0.8, 0.05, 0, 3.0, zb - 0.82, k:lit({ 246, 240, 226 }), { rx = -15 })
			for _, sx in { -1, 1 } do
				k:box("Toe", 0.2, 0.3, 1.2, sx * (W / 2 - 0.3), 0.15, zb - 1.2, "body")
			end
			k:box("Bench", 2.6, 0.25, 1.1, 0, 1.45, -Dp / 2 + 0.55, "bench", { solid = true })
			k:legs(2.4, 0.9, 1.3, 0.12, 0.14, "body", false)
			k:seat(0, 1.6, -Dp / 2 + 0.55)
			k:cyl("Candle", 0.5, 0.14, W / 2 - 0.5, H + 0.25, zb, "y", k:lit({ 246, 240, 226 }))
		end,
	})

	D.item({
		id = "hb_guitar", cat = "hobby", name = "어쿠스틱 기타 + 스탠드", price = 320000, decor = 3, style = "cozy", place = "floor",
		size = { 1.6, 4.0, 1.4 }, tags = { "기타", "악기", "음악" },
		slots = { S("wood", "바디", "teak", { "wood", "gloss" }) },
		build = function(k, W, H, Dp)
			k:box("StandFoot", 1.2, 0.08, 1.2, 0, 0.04, 0, k:lit({ 30, 30, 34 }, "metal"))
			k:box("StandPost", 0.08, 3.4, 0.08, 0, 1.7, 0.3, k:lit({ 30, 30, 34 }, "metal"))
			k:ball("Lower", 1.4, 0, 1.05, -0.05, "wood", { solid = true })
			k:ball("Upper", 1.05, 0, 1.85, -0.05, "wood")
			k:cyl("Hole", 0.04, 0.35, 0, 1.6, -0.6, "z", k:lit({ 30, 22, 16 }))
			k:box("Neck", 0.22, 1.7, 0.12, 0, 3.05, -0.1, k:lit({ 70, 44, 30 }, "wood"))
			k:box("Head", 0.3, 0.45, 0.1, 0, 4.0 - 0.25, -0.1, k:lit({ 40, 28, 20 }, "wood"))
			k:box("Strings", 0.12, 2.8, 0.01, 0, 2.6, -0.18, k:lit({ 220, 220, 210 }, "metal"))
		end,
	})

	D.item({
		id = "hb_easel", cat = "hobby", name = "원목 이젤 + 캔버스", price = 89000, decor = 3, style = "natural", place = "floor",
		size = { 2.4, 5.4, 2.2 }, tags = { "이젤", "그림", "미술", "캔버스" },
		slots = { S("wood", "이젤", "birch", { "wood" }), S("paint", "그림 색", "cyan", { "plastic" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Leg", 0.12, 5.4, 0.12, sx * 0.7, 2.65, -0.2, "wood", { rz = -sx * 8, rx = 6 })
			end
			k:box("Back", 0.12, 5.0, 0.12, 0, 2.4, 0.75, "wood", { rx = -20 })
			k:box("Ledge", 1.9, 0.1, 0.35, 0, 1.6, -0.35, "wood")
			k:box("Canvas", 2.0, 2.4, 0.1, 0, 2.85, -0.3, k:lit({ 246, 244, 238 }, "fabric"), { rx = 6, solid = true })
			k:ball("Sun", 0.6, 0.4, 3.3, -0.38, "paint")
			k:box("Sea", 1.8, 0.6, 0.02, 0, 2.1, -0.37, k:mx("paint", { 30, 60, 120 }, 0.5), { rx = 6 })
			k:box("Palette", 0.6, 0.04, 0.45, 0.5, 1.68, -0.35, k:lit({ 200, 164, 118 }, "wood"))
		end,
	})

	D.item({
		id = "hb_aquarium", cat = "hobby", name = "열대어 수족관 (수납장 포함)", price = 860000, decor = 7, style = "modern", place = "floor",
		size = { 4.2, 4.6, 1.8 }, tags = { "수족관", "어항", "물고기", "열대어" }, light = "blue", toggle = true,
		slots = { S("cab", "수납장", "black", { "gloss", "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Cabinet", W, 2.3, Dp, 0, 1.15, 0, "cab", { solid = true, top = true })
			k:box("Glass", W - 0.05, 2.0, Dp - 0.05, 0, 3.3, 0, k:lit({ 200, 230, 240 }, "glass"), { t = 0.75, solid = true })
			k:box("Water", W - 0.2, 1.75, Dp - 0.2, 0, 3.22, 0, k:lit({ 60, 140, 190 }, "glass"), { t = 0.6 })
			k:box("Sand", W - 0.2, 0.18, Dp - 0.2, 0, 2.39, 0, k:lit({ 226, 210, 170 }, "sand"))
			for i = 0, 5 do
				local x = -W / 2 + 0.5 + i * 0.6
				k:box("Weed", 0.12, 0.8 + (i % 3) * 0.3, 0.06, x, 2.8 + (i % 3) * 0.15, 0.3 - (i % 2) * 0.5, k:lit({ 60, 150, 80 }, "leafy"), { rz = (i % 2) * 10 - 5 })
			end
			k:box("Rock", 0.7, 0.45, 0.5, 1.2, 2.6, 0.2, k:lit({ 110, 110, 108 }, "slate"))
			k:box("Lid", W, 0.15, Dp, 0, H - 0.075, 0, "cab")
			local lamp = k:box("Lamp", W - 0.4, 0.05, 0.3, 0, H - 0.18, 0, "light", { glow = true })
			k:light(lamp, 8, 0.6)
			k:tank(0, 3.25, 0, W - 0.4, 1.5, Dp - 0.4)
		end,
	})

	D.item({
		id = "hb_treadmill", cat = "hobby", name = "접이식 러닝머신", price = 790000, decor = 2, style = "modern", place = "floor",
		size = { 2.6, 4.4, 5.6 }, tags = { "러닝머신", "운동", "헬스" },
		slots = { S("body", "본체", "charcoal", { "plastic", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("Deck", W, 0.5, Dp - 0.8, 0, 0.25, 0.4, "body", { solid = true, top = true })
			k:box("Belt", W - 0.5, 0.04, Dp - 1.0, 0, 0.52, 0.4, k:lit({ 40, 40, 44 }, "rubber"))
			for _, sx in { -1, 1 } do
				k:box("Upright", 0.18, 3.6, 0.25, sx * (W / 2 - 0.15), 2.1, -Dp / 2 + 0.6, "body", { rx = -8 })
				k:box("Rail", 0.12, 0.12, 1.4, sx * (W / 2 - 0.2), 3.3, -Dp / 2 + 1.2, k:lit({ 120, 124, 130 }, "metal"))
			end
			k:box("Console", W - 0.2, 0.8, 0.5, 0, 3.95, -Dp / 2 + 0.55, "body", { rx = -25 })
			k:box("Display", 1.0, 0.4, 0.03, 0, 4.0, -Dp / 2 + 0.33, k:lit({ 90, 200, 255 }, "neon"), { rx = -25 })
		end,
	})

	D.item({
		id = "hb_dartboard", cat = "hobby", name = "다트판 + 캐비닛", price = 98000, decor = 3, style = "classic", place = "wall",
		size = { 2.6, 2.6, 0.45 }, tags = { "다트", "게임", "펍" },
		slots = { S("wood", "캐비닛", "walnut", { "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Cabinet", W, H, 0.15, 0, H / 2, Dp / 2 - 0.075, "wood", { solid = true })
			local z = Dp / 2 - 0.2
			k:cyl("Board", 0.15, 1.9, 0, H / 2, z, "z", k:lit({ 30, 30, 30 }))
			for i = 0, 19 do
				local a = i * 18
				k:box("Seg", 0.25, 0.85, 0.02, math.sin(math.rad(a)) * 0.45, H / 2 + math.cos(math.rad(a)) * 0.45, z - 0.08, k:lit(if i % 2 == 0 then { 236, 222, 190 } else { 30, 30, 30 }), { rz = -a })
			end
			k:cyl("Ring", 0.02, 1.25, 0, H / 2, z - 0.09, "z", k:lit({ 214, 52, 56 }))
			k:cyl("Ring2", 0.03, 1.15, 0, H / 2, z - 0.1, "z", k:lit({ 30, 30, 30 }))
			k:cyl("Bull", 0.04, 0.16, 0, H / 2, z - 0.11, "z", k:lit({ 214, 52, 56 }))
			for i = 0, 2 do
				k:cyl("Dart", 0.5, 0.05, -0.3 + i * 0.25, H / 2 + 0.2 - i * 0.15, z - 0.3, "z", k:lit({ 64, 168, 90 }))
			end
		end,
	})

	D.item({
		id = "hb_telescope", cat = "hobby", name = "천체 망원경 (광안리 별 보기)", price = 450000, decor = 4, style = "classic", place = "floor",
		size = { 2.4, 4.4, 3.0 }, tags = { "망원경", "별", "취미", "창가" },
		slots = { S("tube", "경통", "white", { "gloss", "metal", "brushed" }) },
		build = function(k, W, H, Dp)
			for i = 0, 2 do
				local a = math.rad(i * 120)
				k:cyl("Leg", 3.0, 0.1, math.sin(a) * 0.45, 1.45, math.cos(a) * 0.45, "y", k:lit({ 40, 40, 44 }, "metal"), { rx = -math.cos(a) * 14, rz = math.sin(a) * 14 })
			end
			k:box("Mount", 0.4, 0.4, 0.4, 0, 3.05, 0, k:lit({ 40, 40, 44 }, "metal"))
			k:cyl("Tube", 2.8, 0.55, 0, 3.6, -0.2, "z", "tube", { rx = -30, solid = true })
			k:cyl("Lens", 0.1, 0.62, 0, 4.28, -1.4, "z", k:lit({ 30, 30, 34 }), { rx = -30 })
			k:cyl("Finder", 0.8, 0.14, 0.3, 3.85, 0.1, "z", k:lit({ 30, 30, 34 }), { rx = -30 })
			k:cyl("Eyepiece", 0.3, 0.14, 0, 3.0, 0.95, "y", k:lit({ 30, 30, 34 }))
		end,
	})

	D.item({
		id = "hb_lego_city", cat = "hobby", name = "블록 장난감 · 광안리 도시", price = 189000, decor = 4, style = "trendy", place = "surface",
		size = { 2.4, 1.8, 1.6 }, tags = { "레고", "블록", "피규어", "장난감" },
		slots = { S("base", "판", "green", { "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W, 0.06, Dp, 0, 0.03, 0, "base", { solid = true, top = true })
			local cols = { { 214, 52, 56 }, { 246, 206, 60 }, { 40, 84, 196 }, { 246, 246, 244 }, { 240, 128, 40 } }
			local bld = { { -0.8, 0.5, 1.2, 0.4 }, { -0.25, 0.5, 0.8, 0.5 }, { 0.3, 0.45, 1.6, 0.35 }, { 0.8, 0.5, 0.6, 0.6 } }
			for i, b in bld do
				k:box("Block", b[2], b[3], b[4], b[1], 0.06 + b[3] / 2, -0.3, k:lit(cols[i], "gloss"))
				for j = 0, math.floor(b[3] / 0.25) - 1 do
					k:box("Window", b[2] + 0.01, 0.06, 0.1, b[1], 0.2 + j * 0.25, -0.3 - b[4] / 2 + 0.06, k:lit({ 150, 210, 240 }, "glass"))
				end
			end
			k:box("Road", W - 0.1, 0.02, 0.35, 0, 0.07, 0.45, k:lit({ 70, 72, 78 }, "gloss"))
			k:box("Car", 0.3, 0.15, 0.18, -0.5, 0.15, 0.45, k:lit({ 214, 52, 56 }, "gloss"))
			k:box("Car", 0.3, 0.15, 0.18, 0.4, 0.15, 0.45, k:lit({ 246, 206, 60 }, "gloss"))
		end,
	})

	D.item({
		id = "hb_karaoke", cat = "hobby", name = "가정용 노래방 기계 + 마이크", price = 980000, decor = 5, style = "trendy", place = "floor",
		size = { 2.6, 3.2, 1.8 }, tags = { "노래방", "마이크", "노래", "파티" }, light = "magenta", glow = true, toggle = false,
		slots = { S("body", "본체", "black", { "gloss", "plastic" }) },
		build = function(k, W, H, Dp)
			local body = k:box("Cabinet", W, 2.2, Dp, 0, 1.1, 0, "body", { solid = true, top = true })
			for _, sx in { -1, 1 } do
				k:cyl("Woofer", 0.06, 0.9, sx * 0.65, 0.9, -Dp / 2 - 0.03, "z", k:lit({ 40, 40, 44 }, "metal"))
				k:cyl("Cone", 0.04, 0.5, sx * 0.65, 0.9, -Dp / 2 - 0.06, "z", k:lit({ 70, 70, 76 }))
			end
			k:box("LEDBar", W - 0.2, 0.08, 0.03, 0, 1.7, -Dp / 2 - 0.02, "light", { glow = true })
			k:box("Remote", 0.25, 0.06, 0.6, 0.7, 2.23, 0, k:lit({ 40, 40, 44 }))
			k:box("Songbook", 0.7, 0.12, 0.9, -0.5, 2.26, 0, k:lit({ 214, 52, 56 }))
			for i = 0, 1 do
				k:cyl("Mic", 0.65, 0.12, 0.1 + i * 0.25, 2.3, -0.2, "z", k:lit(if i == 0 then { 200, 202, 206 } else { 214, 176, 64 }, "metal"), { ry = 70 })
				k:ball("MicHead", 0.2, 0.1 + i * 0.25 - 0.3, 2.3, -0.3, k:lit({ 120, 124, 130 }, "metal"))
			end
			k:tvPanel(2.4, 1.0, 0, 2.75, 0.0, k:lit({ 24, 24, 28 }), 0.12)
			k:speaker(body)
		end,
	})
end
