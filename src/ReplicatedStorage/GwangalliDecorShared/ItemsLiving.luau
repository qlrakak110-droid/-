--!strict
-- GwangalliDecorShared/ItemsLiving: 거실 — 소파 · 라운지 체어 · 커피테이블 · 거실장 · 벽난로 · 좌식 테이블.
-- Item frame: origin = bottom centre, front = -Z, back = +Z (see Kit). 1 stud ≈ 0.32 m.

return function(D: any)
	local S = D.slot
	local FAB = { "fabric", "velvet", "leather" }
	local LEGM = { "wood", "metal", "brushed" }
	local TOPM = { "wood", "marble", "glass", "gloss" }

	-- 3인 패브릭 소파 -------------------------------------------------------------------------------
	D.item({
		id = "lv_sofa_3seat", cat = "living", name = "3인 패브릭 소파", price = 890000, decor = 6, style = "modern", place = "floor",
		size = { 7.2, 2.9, 3.2 }, tags = { "소파", "쇼파", "sofa" },
		slots = { S("fabric", "패브릭", "grey", FAB), S("legs", "다리", "walnut", LEGM), S("pillow", "쿠션", "mustard", { "fabric", "velvet" }) },
		build = function(k, W, H, Dp)
			k:legs(W - 0.3, Dp - 0.3, 0.45, 0.2, 0.18, "legs", true)
			k:box("Base", W, 0.55, Dp, 0, 0.725, 0, "fabric", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Arm", 0.62, 1.15, Dp, sx * (W / 2 - 0.31), 1.0 + 0.575, 0, "fabric", { solid = true })
				k:cyl("ArmRoll", Dp - 0.1, 0.62, sx * (W / 2 - 0.31), 2.15, 0, "z", "fabric")
			end
			k:box("Back", W - 1.24, 1.5, 0.5, 0, 1.0 + 0.75, Dp / 2 - 0.25, "fabric", { solid = true })
			local sw = (W - 1.24) / 3
			for i = 1, 3 do
				local x = -W / 2 + 0.62 + sw * (i - 0.5)
				k:seatPad(sw - 0.04, 0.42, Dp - 0.62, x, 1.21, -0.25, "fabric", k:sh("fabric", 0.85))
				k:box("BackCushion", sw - 0.08, 1.05, 0.42, x, 1.95, Dp / 2 - 0.68, k:sh("fabric", 1.04), { rx = -9 })
				k:seat(x, 1.42, -0.25)
			end
			k:box("Pillow", 0.95, 0.95, 0.28, -W / 2 + 1.25, 1.85, Dp / 2 - 1.05, "pillow", { rx = -12, rz = 8 })
			k:box("Pillow", 0.95, 0.95, 0.28, W / 2 - 1.25, 1.85, Dp / 2 - 1.05, "pillow", { rx = -12, rz = -8 })
		end,
	})

	-- L자 모듈 소파 --------------------------------------------------------------------------------
	D.item({
		id = "lv_sofa_modular", cat = "living", name = "L자 모듈 소파 (카우치)", price = 1650000, decor = 8, style = "modern", place = "floor",
		size = { 8.6, 2.6, 6.0 }, tags = { "소파", "카우치", "코너 소파" },
		slots = { S("fabric", "패브릭", "ivory", FAB), S("plinth", "받침", "charcoal", { "plastic", "wood", "metal" }), S("pillow", "쿠션", "sky", { "fabric", "velvet" }) },
		build = function(k, W, H, Dp)
			local dBack = 3.1
			local zMain = Dp / 2 - dBack / 2
			-- plinth (recessed)
			k:box("Plinth", W - 0.3, 0.35, dBack - 0.3, 0, 0.175, zMain, "plinth")
			k:box("Plinth", 2.9, 0.35, Dp - dBack, W / 2 - 1.6, 0.175, -dBack / 2 + 0.15, "plinth")
			-- seat block
			k:box("Base", W, 0.5, dBack, 0, 0.6, zMain, "fabric", { solid = true })
			k:box("Base", 3.2, 0.5, Dp - dBack + 0.02, W / 2 - 1.6, 0.6, -dBack / 2 + 0.01, "fabric", { solid = true })
			-- back + left arm
			k:box("Back", W, 1.25, 0.55, 0, 0.85 + 0.625, Dp / 2 - 0.275, "fabric", { solid = true })
			k:box("Arm", 0.6, 0.95, dBack, -W / 2 + 0.3, 0.85 + 0.475, zMain, "fabric", { solid = true })
			-- cushions
			local sw = (W - 3.8) / 2
			for i = 1, 2 do
				local x = -W / 2 + 0.6 + sw * (i - 0.5)
				k:seatPad(sw - 0.04, 0.4, dBack - 0.6, x, 1.05, zMain - 0.27, "fabric")
				k:box("BackCushion", sw - 0.1, 1.0, 0.45, x, 1.75, Dp / 2 - 0.75, k:sh("fabric", 0.97), { rx = -8 })
				k:seat(x, 1.25, zMain - 0.3)
			end
			k:seatPad(3.1, 0.4, Dp - 0.6, W / 2 - 1.6, 1.05, -0.27, "fabric")
			k:box("BackCushion", 3.0, 1.0, 0.45, W / 2 - 1.6, 1.75, Dp / 2 - 0.75, k:sh("fabric", 0.97), { rx = -8 })
			k:seat(W / 2 - 1.6, 1.25, Dp / 2 - 1.6)
			k:bed(W / 2 - 1.6, 1.3, -0.4, 180)
			k:box("Pillow", 1.0, 1.0, 0.3, -W / 2 + 1.3, 1.62, Dp / 2 - 1.1, "pillow", { rx = -14, rz = 6 })
			k:box("Pillow", 0.9, 0.9, 0.3, W / 2 - 0.8, 1.6, Dp / 2 - 1.1, k:sh("pillow", 0.8), { rx = -14, rz = -10 })
			k:box("Throw", 1.4, 0.1, 2.4, W / 2 - 1.7, 1.31, -Dp / 2 + 1.6, k:lit({ 222, 210, 188 }, "fabric"), { ry = 8 })
		end,
	})

	-- 벨벳 체스터필드 소파 --------------------------------------------------------------------------
	D.item({
		id = "lv_chesterfield", cat = "living", name = "벨벳 체스터필드 소파", price = 3800000, decor = 12, style = "classic", place = "floor",
		size = { 7.0, 2.7, 3.1 }, tags = { "소파", "체스터필드", "벨벳", "호텔" },
		slots = { S("velvet", "벨벳", "teal", { "velvet", "leather", "fabric" }), S("legs", "다리", "brass", { "metal", "wood" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local x, z = sx * (W / 2 - 0.35), sz * (Dp / 2 - 0.3)
					k:cyl("Leg", 0.35, 0.22, x, 0.175, z, "y", "legs")
					k:ball("Foot", 0.2, x, 0.08, z, "legs")
				end
			end
			k:box("Base", W, 0.75, Dp, 0, 0.35 + 0.375, 0, "velvet", { solid = true })
			-- rolled arms the height of the back
			for _, sx in { -1, 1 } do
				k:box("Arm", 0.7, 1.25, Dp, sx * (W / 2 - 0.35), 1.1 + 0.55, 0, "velvet", { solid = true })
				k:cyl("ArmRoll", Dp + 0.05, 0.85, sx * (W / 2 - 0.3), 2.3, 0, "z", "velvet")
				k:cyl("ArmFace", 0.08, 0.86, sx * (W / 2 - 0.3), 2.3, -Dp / 2 - 0.02, "z", k:sh("velvet", 0.8))
			end
			k:box("Back", W - 1.2, 1.45, 0.6, 0, 1.1 + 0.725, Dp / 2 - 0.3, "velvet", { solid = true })
			k:cyl("BackRoll", W - 1.1, 0.7, 0, 2.48, Dp / 2 - 0.3, "x", "velvet")
			-- tufting
			for row = 0, 1 do
				for i = 0, 6 do
					local x = -W / 2 + 0.95 + i * (W - 1.9) / 6 + (row % 2) * ((W - 1.9) / 12)
					if x < W / 2 - 0.85 then
						k:ball("Tuft", 0.11, x, 1.6 + row * 0.42, Dp / 2 - 0.61, k:sh("velvet", 0.6))
					end
				end
			end
			for _, sx in { -1, 1 } do
				for i = 0, 2 do
					k:ball("Tuft", 0.1, sx * (W / 2 - 0.71), 1.45 + i * 0.3, -0.6 + i * 0.6, k:sh("velvet", 0.6))
				end
			end
			k:seatPad(W - 1.4, 0.38, Dp - 0.7, 0, 1.29, -0.3, "velvet", k:sh("velvet", 0.75))
			k:box("Studs", W - 0.2, 0.06, 0.04, 0, 1.06, -Dp / 2 - 0.02, k:as("legs", "metal"))
			for i = -1, 1 do
				k:seat(i * 1.8, 1.48, -0.3)
			end
		end,
	})

	-- 윙체어 ----------------------------------------------------------------------------------------
	D.item({
		id = "lv_armchair_wing", cat = "living", name = "클래식 윙체어", price = 720000, decor = 5, style = "classic", place = "floor",
		size = { 2.9, 3.7, 2.9 }, tags = { "의자", "암체어", "체어" },
		slots = { S("fabric", "패브릭", "olive", FAB), S("legs", "다리", "walnut", LEGM) },
		build = function(k, W, H, Dp)
			k:splayLegs(W - 0.4, Dp - 0.4, 0.55, 0.15, 0.16, "legs", 6)
			k:box("Seat", W - 0.2, 0.5, Dp - 0.2, 0, 0.8, 0, "fabric", { solid = true })
			k:seatPad(W - 1.0, 0.36, Dp - 0.7, 0, 1.23, -0.25, k:sh("fabric", 1.05))
			k:box("Back", W - 0.6, 2.35, 0.45, 0, 1.05 + 1.17, Dp / 2 - 0.32, "fabric", { solid = true, rx = -5 })
			for _, sx in { -1, 1 } do
				k:box("Arm", 0.42, 0.75, Dp - 0.5, sx * (W / 2 - 0.3), 1.42, -0.15, "fabric", { solid = true })
				k:cyl("ArmRoll", Dp - 0.5, 0.42, sx * (W / 2 - 0.3), 1.8, -0.15, "z", "fabric")
				k:box("Wing", 0.32, 1.35, 1.1, sx * (W / 2 - 0.38), 2.6, Dp / 2 - 0.85, k:sh("fabric", 0.95), { ry = sx * 14 })
			end
			k:seat(0, 1.42, -0.2)
		end,
	})

	-- 라탄 라운지 체어 ------------------------------------------------------------------------------
	D.item({
		id = "lv_rattan_chair", cat = "living", name = "라탄 라운지 체어", price = 340000, decor = 4, style = "natural", place = "floor",
		size = { 2.7, 2.9, 2.7 }, tags = { "의자", "라탄", "라운지" },
		slots = { S("rattan", "라탄", "teak", { "rattan", "wood", "metal" }), S("cushion", "방석", "ivory", { "fabric", "velvet" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Frame", 0.14, 0.14, Dp - 0.2, sx * (W / 2 - 0.15), 0.07, 0, "rattan")
				k:box("Frame", 0.14, 1.5, 0.14, sx * (W / 2 - 0.15), 0.75, -Dp / 2 + 0.2, "rattan")
				k:box("Frame", 0.14, 2.6, 0.14, sx * (W / 2 - 0.15), 1.3, Dp / 2 - 0.25, "rattan", { rx = -10 })
				k:box("ArmWeave", 0.1, 0.8, Dp - 0.5, sx * (W / 2 - 0.15), 1.1, 0, k:sh("rattan", 1.12, "planks"))
				k:box("ArmTop", 0.2, 0.1, Dp - 0.3, sx * (W / 2 - 0.15), 1.55, 0, "rattan")
			end
			k:box("SeatWeave", W - 0.3, 0.12, Dp - 0.4, 0, 0.95, 0, k:sh("rattan", 1.1, "planks"), { solid = true })
			k:box("BackWeave", W - 0.35, 1.8, 0.1, 0, 1.9, Dp / 2 - 0.35, k:sh("rattan", 1.1, "planks"), { rx = -10, solid = true })
			k:seatPad(W - 0.5, 0.32, Dp - 0.6, 0, 1.17, -0.1, "cushion")
			k:box("BackPillow", W - 0.8, 1.0, 0.32, 0, 1.85, Dp / 2 - 0.6, k:sh("cushion", 0.95), { rx = -12 })
			k:seat(0, 1.33, -0.1)
		end,
	})

	-- 니트 푸프 -------------------------------------------------------------------------------------
	D.item({
		id = "lv_ottoman_pouf", cat = "living", name = "니트 푸프 스툴", price = 89000, decor = 2, style = "cozy", place = "floor",
		size = { 1.7, 1.2, 1.7 }, tags = { "스툴", "푸프", "오토만" },
		slots = { S("knit", "니트", "oatmeal", { "fabric", "velvet", "leather" }) },
		build = function(k, W, H, Dp)
			k:cyl("Pouf", 1.05, W, 0, 0.53, 0, "y", "knit", { solid = true, top = true })
			for i = 0, 7 do
				local a = i * math.pi / 4
				k:box("Rib", 0.12, 0.95, 0.06, math.cos(a) * W / 2, 0.53, math.sin(a) * W / 2, k:sh("knit", 0.86), { ry = -math.deg(a) + 90 })
			end
			k:cyl("Top", 0.08, W - 0.3, 0, 1.08, 0, "y", k:sh("knit", 1.06))
			k:ball("Button", 0.18, 0, 1.12, 0, k:sh("knit", 0.8))
			k:seat(0, 1.12, 0)
		end,
	})

	-- 빈백 ------------------------------------------------------------------------------------------
	D.item({
		id = "lv_beanbag", cat = "living", name = "빈백 소파", price = 129000, decor = 2, style = "cozy", place = "floor",
		size = { 2.8, 2.2, 2.8 }, tags = { "빈백", "소파", "쿠션" },
		slots = { S("fabric", "커버", "mustard", { "fabric", "velvet", "leather" }) },
		build = function(k, W, H, Dp)
			k:ball("Bag", 2.7, 0, 0.95, 0.05, "fabric", { solid = true })
			k:ball("Back", 2.0, 0, 1.45, 0.65, k:sh("fabric", 0.95))
			k:ball("Dent", 1.6, 0, 1.25, -0.3, k:sh("fabric", 1.06))
			k:box("Handle", 0.5, 0.12, 0.05, 0, 1.9, 1.15, k:sh("fabric", 0.7), { rx = -30 })
			k:seat(0, 1.45, -0.2)
		end,
	})

	-- 라운드 커피테이블 -----------------------------------------------------------------------------
	D.item({
		id = "lv_coffee_round", cat = "living", name = "라운드 화이트 커피테이블", price = 260000, decor = 3, style = "modern", place = "floor",
		size = { 3.0, 1.35, 3.0 }, tags = { "테이블", "커피테이블", "원형" },
		slots = { S("top", "상판", "white", TOPM), S("base", "다리", "oak", LEGM) },
		build = function(k, W, H, Dp)
			k:cyl("Top", 0.14, W, 0, 1.28, 0, "y", "top", { solid = true, top = true })
			k:cyl("Edge", 0.05, W + 0.02, 0, 1.2, 0, "y", k:sh("top", 0.9))
			for i = 0, 2 do
				local a = i * 2.094 + 0.5
				k:cyl("Leg", 1.2, 0.16, math.cos(a) * W * 0.32, 0.6, math.sin(a) * W * 0.32, "y", "base", { rx = math.sin(a) * 7, rz = -math.cos(a) * 7 })
			end
			k:box("Book", 0.9, 0.1, 0.7, -0.35, 1.4, 0.2, k:lit({ 52, 82, 120 }), { ry = 20 })
			k:box("Book", 0.8, 0.08, 0.6, -0.33, 1.49, 0.2, k:lit({ 226, 214, 190 }), { ry = 12 })
			k:cyl("Mug", 0.3, 0.28, 0.5, 1.5, -0.3, "y", k:lit({ 240, 238, 232 }, "ceramic"))
		end,
	})

	-- 오크 원목 커피테이블 --------------------------------------------------------------------------
	D.item({
		id = "lv_coffee_oak", cat = "living", name = "오크 원목 커피테이블 (선반형)", price = 320000, decor = 3, style = "natural", place = "floor",
		size = { 4.0, 1.35, 2.2 }, tags = { "테이블", "커피테이블", "원목" },
		slots = { S("wood", "원목", "oak", { "wood", "planks", "gloss" }) },
		build = function(k, W, H, Dp)
			k:box("Top", W - 0.3, 0.16, Dp, 0, 1.27, 0, "wood", { solid = true, top = true })
			for _, sx in { -1, 1 } do
				k:cyl("TopEdge", Dp, 0.16, sx * (W / 2 - 0.15), 1.27, 0, "z", "wood")
			end
			k:legs(W - 0.2, Dp - 0.2, 1.19, 0.15, 0.2, k:sh("wood", 0.92))
			k:box("Shelf", W - 0.6, 0.1, Dp - 0.5, 0, 0.35, 0, k:sh("wood", 0.95), { top = true })
			k:box("Magazine", 1.0, 0.06, 0.8, -0.8, 0.43, 0.1, k:lit({ 214, 52, 56 }), { ry = -8 })
			k:box("Magazine", 1.0, 0.06, 0.8, -0.75, 0.49, 0.1, k:lit({ 236, 232, 222 }), { ry = 6 })
			k:box("Basket", 0.9, 0.5, 0.8, 0.9, 0.65, 0, k:lit({ 190, 160, 110 }, "planks"))
			k:box("Tray", 1.2, 0.06, 0.8, 0.6, 1.38, 0, k:lit({ 40, 40, 44 }, "wood"))
			k:ball("Objet", 0.3, 0.4, 1.56, 0, k:lit({ 214, 176, 64 }, "metal"))
			k:cyl("Candle", 0.36, 0.22, 0.85, 1.59, 0.1, "y", k:lit({ 238, 232, 220 }))
		end,
	})

	-- 대리석 커피테이블 -----------------------------------------------------------------------------
	D.item({
		id = "lv_coffee_marble", cat = "living", name = "대리석 커피테이블 (골드 프레임)", price = 980000, decor = 6, style = "luxury", place = "floor",
		size = { 4.4, 1.25, 2.4 }, tags = { "테이블", "대리석", "호텔" },
		slots = { S("stone", "상판", "carrara", { "marble", "granite", "glass" }), S("frame", "프레임", "gold", { "metal", "brushed" }) },
		build = function(k, W, H, Dp)
			k:box("Slab", W, 0.2, Dp, 0, 1.15, 0, "stone", { solid = true, top = true })
			k:box("Lip", W + 0.04, 0.04, Dp + 0.04, 0, 1.03, 0, "frame")
			for _, sx in { -1, 1 } do
				k:box("Frame", 0.1, 1.0, 0.1, sx * (W / 2 - 0.2), 0.52, -Dp / 2 + 0.2, "frame")
				k:box("Frame", 0.1, 1.0, 0.1, sx * (W / 2 - 0.2), 0.52, Dp / 2 - 0.2, "frame")
				k:box("Frame", 0.1, 0.1, Dp - 0.3, sx * (W / 2 - 0.2), 0.05, 0, "frame")
			end
			k:box("Frame", W - 0.3, 0.1, 0.1, 0, 0.05, 0, "frame")
			k:box("Tray", 1.3, 0.05, 0.8, -0.8, 1.28, 0, k:as("frame", "metal"))
			k:cyl("Vase", 0.7, 0.36, -1.0, 1.65, 0, "y", k:lit({ 36, 36, 40 }, "ceramic"))
			k:box("Book", 1.0, 0.16, 0.75, 1.0, 1.33, 0.1, k:lit({ 236, 232, 222 }), { ry = 10 })
		end,
	})

	-- C형 사이드 테이블 -----------------------------------------------------------------------------
	D.item({
		id = "lv_side_table", cat = "living", name = "C형 사이드 테이블", price = 79000, decor = 2, style = "modern", place = "floor",
		size = { 1.4, 2.0, 1.4 }, tags = { "협탁", "사이드", "테이블" },
		slots = { S("top", "상판", "walnut", TOPM), S("frame", "프레임", "matteblack", { "metal", "brushed", "plastic" }) },
		build = function(k, W, H, Dp)
			k:cyl("Top", 0.1, W, 0, H - 0.05, 0, "y", "top", { solid = true, top = true })
			k:box("Base", W - 0.1, 0.08, 0.3, 0, 0.04, -0.15, "frame")
			k:box("Post", 0.1, H - 0.1, 0.1, 0, H / 2, W / 2 - 0.15, "frame", { solid = true })
			k:box("Foot", 0.1, 0.08, W - 0.2, 0, 0.04, 0.1, "frame")
			k:box("Arm", 0.1, 0.08, W / 2, 0, H - 0.14, W / 4 - 0.1, "frame")
		end,
	})

	-- 낮은 거실장 -----------------------------------------------------------------------------------
	D.item({
		id = "lv_tv_console", cat = "living", name = "슬림 원목 거실장", price = 450000, decor = 4, style = "natural", place = "floor",
		size = { 6.2, 1.65, 1.4 }, tags = { "거실장", "TV장", "수납" },
		slots = { S("body", "몸체", "oak", { "wood", "planks", "gloss", "plastic" }), S("front", "문짝", "whitewash", { "wood", "gloss", "plastic", "rattan" }), S("legs", "다리", "matteblack", LEGM) },
		build = function(k, W, H, Dp)
			k:legs(W - 0.4, Dp - 0.3, 0.42, 0.15, 0.14, "legs", true)
			k:box("Body", W, H - 0.42, Dp, 0, 0.42 + (H - 0.42) / 2, 0, "body", { solid = true })
			k:box("Top", W + 0.04, 0.08, Dp + 0.04, 0, H - 0.04, 0, k:sh("body", 1.06), { top = true })
			local cw = (W - 0.3) / 3
			k:front(cw, H - 0.62, -cw, 0.52 + (H - 0.62) / 2, -Dp / 2, "front", k:lit({ 40, 40, 44 }, "metal"))
			k:front(cw, H - 0.62, cw, 0.52 + (H - 0.62) / 2, -Dp / 2, "front", k:lit({ 40, 40, 44 }, "metal"))
			-- middle: slatted open shelf
			k:box("Niche", cw - 0.1, H - 0.7, 0.05, 0, 0.52 + (H - 0.62) / 2, -Dp / 2 + 0.6, k:sh("body", 0.6))
			for i = 0, 6 do
				k:box("Slat", 0.06, H - 0.66, 0.06, -cw / 2 + 0.12 + i * (cw - 0.24) / 6, 0.52 + (H - 0.62) / 2, -Dp / 2 + 0.04, k:sh("body", 0.9))
			end
			k:box("Router", 0.6, 0.2, 0.5, 0, 0.75, -0.1, k:lit({ 36, 36, 40 }))
		end,
	})

	-- 벽난로 ----------------------------------------------------------------------------------------
	D.item({
		id = "lv_fireplace", cat = "living", name = "대리석 벽난로", price = 2900000, decor = 10, style = "classic", place = "floor",
		size = { 4.8, 4.3, 1.5 }, tags = { "벽난로", "난로", "불", "호텔" }, light = { 255, 150, 70 },
		uses = { },
		slots = { S("stone", "맨틀", "carrara", { "marble", "granite", "concrete", "wood" }), S("box", "화구", "nero", { "slate", "metal", "concrete" }) },
		build = function(k, W, H, Dp)
			k:box("Hearth", W + 0.4, 0.25, Dp + 0.5, 0, 0.125, -0.25, k:sh("stone", 0.92), { solid = true })
			k:box("Back", W, H - 0.5, 0.4, 0, 0.25 + (H - 0.5) / 2, Dp / 2 - 0.2, "stone", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Pillar", 0.8, H - 0.85, Dp - 0.2, sx * (W / 2 - 0.4), 0.25 + (H - 0.85) / 2, -0.1, "stone", { solid = true })
				k:box("Capital", 0.95, 0.15, Dp, sx * (W / 2 - 0.4), H - 0.65, -0.1, k:sh("stone", 1.04))
			end
			k:box("Lintel", W - 1.6, 0.6, Dp - 0.2, 0, H - 0.9, -0.1, "stone", { solid = true })
			k:box("Mantel", W + 0.3, 0.22, Dp + 0.25, 0, H - 0.47, -0.2, k:sh("stone", 1.06), { top = true })
			k:box("Firebox", W - 1.6, H - 1.55, Dp - 0.5, 0, 0.25 + (H - 1.55) / 2, 0.05, "box")
			k:box("Grate", W - 2.0, 0.08, Dp - 0.9, 0, 0.45, 0, k:lit({ 30, 30, 32 }, "metal"))
			for i = -1, 1 do
				k:cyl("Log", W - 2.3, 0.28, 0, 0.62 + (i == 0 and 0.2 or 0), -0.05 + i * 0.22, "x", k:lit({ 92, 62, 40 }, "wood"), { ry = i * 12 })
			end
			local ember = k:box("Ember", W - 2.2, 0.12, Dp - 1.0, 0, 0.52, 0, "light", { glow = true })
			k:light(ember, 16, 1.4)
			k:fire(0, 0.9, -0.05, W - 2.2, 0.8, Dp - 1.0)
			k:box("Screen", W - 1.7, 1.3, 0.04, 0, 0.95, -Dp / 2 + 0.3, k:lit({ 30, 30, 32 }, "metal"), { t = 0.55 })
			k:cyl("Candle", 0.6, 0.22, -W / 2 + 0.5, H - 0.06, -0.2, "y", k:lit({ 240, 232, 220 }))
			k:cyl("Candle", 0.4, 0.22, -W / 2 + 0.85, H - 0.16, -0.2, "y", k:lit({ 240, 232, 220 }))
			k:box("Frame", 1.6, 1.1, 0.1, W / 2 - 1.2, H - 0.36 + 0.55, 0.15, k:lit({ 198, 158, 92 }, "metal"), { rx = -8 })
		end,
	})

	-- 리클라이너 ------------------------------------------------------------------------------------
	D.item({
		id = "lv_recliner", cat = "living", name = "가죽 리클라이너 (1인)", price = 890000, decor = 5, style = "cozy", place = "floor",
		size = { 3.0, 3.4, 3.2 }, tags = { "리클라이너", "의자", "안락의자" },
		uses = { open = "발받침 펴기", close = "발받침 접기" },
		slots = { S("leather", "가죽", "camel", { "leather", "fabric", "velvet" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W - 0.5, 0.3, Dp - 0.8, 0, 0.15, 0.2, k:lit({ 36, 36, 40 }))
			k:box("Body", W - 0.2, 0.75, Dp - 0.6, 0, 0.3 + 0.375, 0.1, "leather", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Arm", 0.55, 1.05, Dp - 0.6, sx * (W / 2 - 0.28), 0.3 + 0.525 + 0.25, 0.1, "leather", { solid = true })
				k:cyl("ArmRoll", Dp - 0.6, 0.55, sx * (W / 2 - 0.28), 1.6, 0.1, "z", k:sh("leather", 1.05))
			end
			k:seatPad(W - 1.2, 0.42, Dp - 1.1, 0, 1.26, -0.05, k:sh("leather", 1.04))
			k:box("Back", W - 1.1, 2.0, 0.6, 0, 1.05 + 1.0, Dp / 2 - 0.35, "leather", { solid = true, rx = -8 })
			k:box("Head", W - 1.3, 0.55, 0.4, 0, 2.85, Dp / 2 - 0.65, k:sh("leather", 1.08), { rx = -12 })
			local fr = k:box("Footrest", W - 1.2, 0.35, 0.18, 0, 0.75, -Dp / 2 + 0.38, k:sh("leather", 0.95))
			local fp = k:box("FootPad", W - 1.2, 0.18, 1.0, 0, 0.75, -Dp / 2 + 0.3, k:sh("leather", 1.02))
			k.parts[fp].cf = CFrame.new(0, 0.62, -Dp / 2 + 0.39) * CFrame.Angles(math.rad(90), 0, 0)
			k:pose(fr, CFrame.new(0, 1.05, -Dp / 2 - 0.05))
			k:pose(fp, CFrame.new(0, 1.12, -Dp / 2 - 0.55))
			k:seat(0, 1.47, 0)
		end,
	})

	-- 좌식 테이블 + 방석 ----------------------------------------------------------------------------
	D.item({
		id = "lv_low_table_set", cat = "living", name = "좌식 원목 테이블 + 방석 4", price = 230000, decor = 3, style = "cozy", place = "floor",
		size = { 4.6, 1.2, 4.6 }, tags = { "좌식", "방석", "좌탁", "한식" },
		slots = { S("wood", "원목", "teak", { "wood", "planks", "gloss" }), S("cushion", "방석", "sage", { "fabric", "velvet" }) },
		build = function(k, W, H, Dp)
			local tw, td = 3.0, 2.0
			k:box("Top", tw, 0.14, td, 0, 1.08, 0, "wood", { solid = true, top = true })
			k:box("Apron", tw - 0.3, 0.2, td - 0.3, 0, 0.92, 0, k:sh("wood", 0.85))
			k:legs(tw, td, 0.92, 0.2, 0.18, k:sh("wood", 0.92))
			local spots = { { 0, -td / 2 - 0.65, 0 }, { 0, td / 2 + 0.65, 180 }, { -tw / 2 - 0.55, 0, 90 }, { tw / 2 + 0.55, 0, -90 } }
			for i, s in spots do
				local isSide = i > 2
				local cw, cd = if isSide then 1.0 else 1.25, if isSide then 1.25 else 1.0
				k:box("Bangseok", cw, 0.22, cd, s[1], 0.11, s[2], if i % 2 == 0 then "cushion" else k:sh("cushion", 0.88))
				k:box("Stitch", cw - 0.3, 0.02, cd - 0.3, s[1], 0.23, s[2], k:sh("cushion", 1.15))
				k:seat(s[1], 0.24, s[2], s[3])
			end
			k:cyl("Teapot", 0.4, 0.42, -0.6, 1.35, 0, "y", k:lit({ 236, 236, 230 }, "ceramic"))
			k:box("Spout", 0.08, 0.08, 0.3, -0.6, 1.4, -0.28, k:lit({ 236, 236, 230 }, "ceramic"), { rx = 30 })
			for i = 0, 1 do
				k:cyl("Cup", 0.2, 0.22, 0.4 + i * 0.4, 1.25, 0.3, "y", k:lit({ 236, 236, 230 }, "ceramic"))
			end
		end,
	})

	-- 1인 소파 (트렌디 커브) -----------------------------------------------------------------------
	D.item({
		id = "lv_curve_chair", cat = "living", name = "부클레 커브 체어", price = 420000, decor = 4, style = "trendy", place = "floor",
		size = { 2.8, 2.5, 2.6 }, tags = { "의자", "부클레", "체어" },
		slots = { S("boucle", "부클레", "ivory", { "fabric", "velvet", "leather" }) },
		build = function(k, W, H, Dp)
			k:cyl("Base", 0.95, W - 0.2, 0, 0.48, 0, "y", "boucle", { solid = true })
			k:cyl("Seat", 0.38, W - 0.7, 0, 1.12, -0.15, "y", k:sh("boucle", 1.05), { top = true })
			for i = 0, 6 do
				local a = math.rad(200 + i * 23)
				k:ball("Shell", 1.15, math.cos(a) * (W / 2 - 0.45), 1.55, -math.sin(a) * (Dp / 2 - 0.45), "boucle", { solid = i == 3 })
			end
			k:seat(0, 1.32, -0.2)
		end,
	})
end
