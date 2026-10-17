--!strict
-- GwangalliDecorShared/ItemsKids: 아이·펫 — 자동차 침대 · 인디언 텐트 · 장난감 상자 · 대형 곰인형 · 캣타워 ·
-- 강아지 방석 · 흔들목마 · 아기 침대 · 미끄럼틀 · 어린이 책상 · 강아지 집 · 금붕어 어항.

return function(D: any)
	local S = D.slot
	local PL = { "plastic", "gloss", "wood" }

	D.item({
		id = "kd_car_bed", cat = "kids", name = "레이싱카 어린이 침대", price = 590000, decor = 5, style = "kids", place = "floor",
		size = { 3.8, 2.6, 7.0 }, tags = { "침대", "어린이", "자동차", "키즈" },
		slots = { S("body", "차체", "red", PL), S("bedding", "이불", "sky", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:box("Body", W, 1.3, Dp, 0, 0.75, 0, "body", { solid = true })
			k:box("Hood", W - 0.2, 0.7, 1.6, 0, 1.2, -Dp / 2 + 0.8, k:sh("body", 1.08), { rx = -12 })
			k:box("Spoiler", W, 0.12, 0.8, 0, 2.3, Dp / 2 - 0.4, k:sh("body", 0.85))
			for _, sx in { -1, 1 } do
				k:box("Fin", 0.12, 0.9, 0.5, sx * (W / 2 - 0.4), 1.85, Dp / 2 - 0.4, k:sh("body", 0.85))
				for _, z in { -Dp / 2 + 1.4, Dp / 2 - 1.4 } do
					k:cyl("Wheel", 0.5, 1.5, sx * (W / 2 + 0.05), 0.75, z, "x", k:lit({ 30, 30, 34 }, "rubber"))
					k:cyl("Rim", 0.52, 0.7, sx * (W / 2 + 0.06), 0.75, z, "x", k:lit({ 200, 202, 206 }, "metal"))
				end
			end
			k:box("Mattress", W - 0.6, 0.4, Dp - 2.4, 0, 1.5, 0.5, k:lit({ 246, 246, 244 }, "fabric"))
			k:box("Duvet", W - 0.5, 0.25, Dp - 3.6, 0, 1.78, 1.0, "bedding")
			k:box("Pillow", 1.8, 0.35, 0.9, 0, 1.85, -0.9, k:lit({ 246, 246, 244 }, "fabric"))
			k:box("Number", 0.9, 0.9, 0.02, 0, 0.9, -Dp / 2 - 0.01, k:lit({ 255, 255, 255 }))
			k:box("Light", 0.6, 0.25, 0.04, -1.2, 1.1, -Dp / 2 - 0.02, k:lit({ 255, 240, 200 }, "neon"))
			k:box("Light", 0.6, 0.25, 0.04, 1.2, 1.1, -Dp / 2 - 0.02, k:lit({ 255, 240, 200 }, "neon"))
			k:bed(0, 1.85, 0.6, 0)
		end,
	})

	D.item({
		id = "kd_tent", cat = "kids", name = "인디언 놀이 텐트", price = 99000, decor = 4, style = "kids", place = "floor",
		size = { 3.4, 5.4, 3.4 }, tags = { "텐트", "놀이", "어린이", "티피" }, light = "warm", glow = true,
		slots = { S("canvas", "천", "ivory", { "fabric" }), S("flag", "깃발", "mustard", { "fabric" }) },
		build = function(k, W, H, Dp)
			for i = 0, 3 do
				local a = math.rad(i * 90 + 45)
				local x, z = math.cos(a) * 1.4, math.sin(a) * 1.4
				k:cyl("Pole", 5.6, 0.1, x * 0.45, 2.7, z * 0.45, "y", k:lit({ 200, 170, 120 }, "wood"), { rx = -math.sin(a) * 15, rz = math.cos(a) * 15 })
			end
			for i = 0, 3 do
				local a = math.rad(i * 90)
				local panel = k:box("Panel", 2.3, 4.4, 0.06, math.sin(a) * 0.82, 2.1, math.cos(a) * 0.82, if i == 0 then k:sh("canvas", 0.95) else "canvas", { ry = math.deg(a), rx = 17 })
				local _ = panel
			end
			k:box("Door", 1.0, 2.2, 0.02, 0, 1.1, -1.3, k:lit({ 40, 36, 34 }), { rx = -17 })
			k:box("Mat", 2.8, 0.1, 2.8, 0, 0.05, 0, k:lit({ 236, 220, 200 }, "fabric"), { top = true })
			k:box("Flag", 0.5, 0.3, 0.02, 0.25, H - 0.3, 0, "flag")
			k:box("Pillow", 0.8, 0.4, 0.6, 0.4, 0.3, 0.4, k:lit({ 240, 176, 196 }, "fabric"))
			local ll = k:ball("Lantern", 0.3, 0, 3.2, 0, "light", { glow = true })
			k:light(ll, 8, 0.5)
		end,
	})

	D.item({
		id = "kd_toy_chest", cat = "kids", name = "원목 장난감 상자", price = 119000, decor = 3, style = "kids", place = "floor",
		size = { 3.0, 2.2, 1.8 }, tags = { "장난감", "수납", "상자", "어린이" },
		uses = { open = "상자 열기", close = "상자 닫기" },
		slots = { S("wood", "상자", "mint", PL) },
		build = function(k, W, H, Dp)
			k:box("Chest", W, 1.6, Dp, 0, 0.8, 0, "wood", { solid = true })
			k:box("Band", W + 0.02, 0.12, Dp + 0.02, 0, 0.3, 0, k:sh("wood", 0.85))
			local lid = k:box("Lid", W + 0.05, 0.25, Dp + 0.05, 0, 1.72, 0, k:sh("wood", 1.08), { top = true })
			k:hinge({ lid }, 0, 1.6, Dp / 2, "x", 75)
			k:ball("Ball", 0.6, -0.8, 1.6, 0, k:lit({ 214, 52, 56 }, "gloss"))
			k:box("Block", 0.4, 0.4, 0.4, 0.3, 1.5, -0.2, k:lit({ 246, 206, 60 }))
			k:box("Block", 0.4, 0.4, 0.4, 0.75, 1.5, 0.2, k:lit({ 40, 84, 196 }))
			k:box("Letter", 0.9, 0.5, 0.02, 0, 0.95, -Dp / 2 - 0.01, k:lit({ 255, 255, 255 }))
		end,
	})

	D.item({
		id = "kd_bear_big", cat = "kids", name = "대형 곰인형", price = 89000, decor = 4, style = "cozy", place = "floor",
		size = { 2.8, 3.6, 2.4 }, tags = { "곰인형", "인형", "테디베어" },
		slots = { S("fur", "털", "camel", { "fabric", "velvet" }), S("ribbon", "리본", "red", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:ball("Body", 2.0, 0, 1.0, 0.1, "fur", { solid = true })
			k:ball("Belly", 1.3, 0, 1.0, -0.4, k:mx("fur", { 255, 240, 220 }, 0.5))
			k:ball("Head", 1.5, 0, 2.6, 0, "fur")
			k:ball("Muzzle", 0.6, 0, 2.45, -0.65, k:mx("fur", { 255, 240, 220 }, 0.5))
			k:ball("Nose", 0.18, 0, 2.55, -0.95, k:lit({ 30, 22, 20 }))
			for _, sx in { -1, 1 } do
				k:ball("Ear", 0.5, sx * 0.6, 3.25, 0, "fur")
				k:ball("Eye", 0.14, sx * 0.25, 2.8, -0.68, k:lit({ 20, 20, 22 }, "gloss"))
				k:ball("Arm", 0.7, sx * 1.05, 1.4, -0.2, "fur")
				k:ball("Leg", 0.85, sx * 0.65, 0.4, -0.75, "fur")
			end
			k:box("Bow", 0.6, 0.3, 0.2, 0, 1.95, -0.7, "ribbon")
		end,
	})

	D.item({
		id = "kd_cat_tower", cat = "kids", name = "캣타워 (스크래처)", price = 149000, decor = 4, style = "cozy", place = "floor",
		size = { 2.6, 6.2, 2.4 }, tags = { "캣타워", "고양이", "반려동물", "펫" },
		slots = { S("plush", "패드", "greige", { "fabric", "carpet" }), S("cat", "고양이", "orange", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W, 0.25, Dp, 0, 0.125, 0, "plush", { solid = true })
			for _, p in { { -0.7, 2.6 }, { 0.6, 4.3 }, { -0.3, 5.9 } } do
				k:cyl("Post", p[2] - 0.25, 0.35, p[1], 0.25 + (p[2] - 0.25) / 2, 0.3, "y", k:lit({ 200, 170, 120 }, "rattan"))
			end
			k:box("Shelf", 1.6, 0.18, 1.4, -0.4, 2.6, 0, "plush", { top = true })
			k:box("House", 1.4, 1.2, 1.3, 0.5, 0.85, -0.2, "plush")
			k:cyl("Hole", 0.05, 0.8, 0.5, 0.85, -0.86, "z", k:lit({ 40, 36, 34 }))
			k:box("Shelf", 1.4, 0.18, 1.3, 0.5, 4.3, 0.1, "plush", { top = true })
			k:cyl("Bed", 0.4, 1.4, -0.3, 6.0, 0, "y", "plush")
			k:ball("Toy", 0.25, 1.1, 3.6, 0.1, k:lit({ 214, 52, 56 }))
			-- a sleeping cat on the top
			k:ball("CatBody", 0.8, -0.3, 6.4, 0, "cat")
			k:ball("CatHead", 0.45, 0.1, 6.45, -0.25, "cat")
			k:box("Ear", 0.12, 0.15, 0.08, 0.0, 6.7, -0.3, "cat", { rz = 30 })
			k:box("Ear", 0.12, 0.15, 0.08, 0.2, 6.7, -0.3, "cat", { rz = -30 })
			k:cyl("Tail", 0.7, 0.12, -0.55, 6.25, -0.2, "x", "cat", { ry = 40 })
		end,
	})

	D.item({
		id = "kd_dog_bed", cat = "kids", name = "도넛 강아지 방석 (+ 강아지)", price = 69000, decor = 3, style = "cozy", place = "floor",
		size = { 2.6, 1.6, 2.6 }, tags = { "방석", "강아지", "반려동물", "펫" },
		slots = { S("plush", "방석", "blush", { "fabric", "velvet" }), S("dog", "강아지", "white", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:cyl("Bed", 0.5, W, 0, 0.25, 0, "y", "plush", { solid = true })
			k:cyl("Rim", 0.5, W - 0.1, 0, 0.6, 0, "y", k:sh("plush", 1.05))
			k:cyl("Inner", 0.2, W - 0.9, 0, 0.55, 0, "y", k:sh("plush", 0.9))
			k:ball("DogBody", 1.0, 0, 0.95, 0.1, "dog")
			k:ball("DogHead", 0.6, 0, 1.0, -0.55, "dog")
			k:ball("Snout", 0.25, 0, 0.92, -0.85, k:sh("dog", 0.95))
			k:ball("Nose", 0.1, 0, 0.98, -0.97, k:lit({ 20, 20, 22 }))
			for _, sx in { -1, 1 } do
				k:box("Ear", 0.18, 0.35, 0.1, sx * 0.3, 1.05, -0.55, k:sh("dog", 0.8), { rz = sx * 20 })
				k:ball("Eye", 0.08, sx * 0.13, 1.1, -0.82, k:lit({ 20, 20, 22 }))
			end
			k:box("Bone", 0.5, 0.12, 0.12, 0.8, 0.82, -0.3, k:lit({ 246, 240, 226 }), { ry = 30 })
		end,
	})

	D.item({
		id = "kd_rocking_horse", cat = "kids", name = "원목 흔들목마", price = 129000, decor = 3, style = "kids", place = "floor",
		size = { 1.4, 2.8, 3.4 }, tags = { "흔들목마", "목마", "장난감" },
		slots = { S("wood", "목마", "birch", { "wood", "gloss" }), S("mane", "갈기", "terracotta", { "fabric" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for i = 0, 4 do
					local t = (i - 2) / 2
					k:box("Rocker", 0.12, 0.12, 0.8, sx * 0.55, 0.12 + t * t * 0.25, t * 1.3, "wood", { rx = t * 18 })
				end
			end
			k:legs(1.0, 1.6, 0.9, 0.1, 0.14, "wood", true, 0.2)
			k:box("Body", 0.8, 0.7, 2.0, 0, 1.45, 0, "wood", { solid = true })
			k:box("Neck", 0.6, 1.0, 0.5, 0, 2.0, -0.9, "wood", { rx = -25 })
			k:box("Head", 0.55, 0.5, 0.9, 0, 2.45, -1.3, "wood")
			k:box("Mane", 0.2, 0.8, 0.4, 0, 2.2, -0.75, "mane", { rx = -25 })
			k:box("Tail", 0.2, 0.6, 0.3, 0, 1.5, 1.1, "mane", { rx = 30 })
			k:box("Saddle", 0.85, 0.12, 0.7, 0, 1.85, 0, k:lit({ 214, 52, 56 }, "leather"))
			k:seat(0, 1.95, 0)
		end,
	})

	D.item({
		id = "kd_crib", cat = "kids", name = "원목 아기 침대 + 모빌", price = 390000, decor = 5, style = "kids", place = "floor",
		size = { 2.6, 5.4, 4.4 }, tags = { "아기침대", "범퍼", "모빌", "육아" },
		slots = { S("wood", "프레임", "white", { "wood", "gloss" }), S("bedding", "침구", "mint", { "fabric" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:box("Post", 0.16, 3.0, 0.16, sx * (W / 2 - 0.08), 1.5, sz * (Dp / 2 - 0.08), "wood", { solid = true })
				end
			end
			k:box("Base", W - 0.1, 0.2, Dp - 0.1, 0, 1.0, 0, "wood", { solid = true })
			k:box("Mattress", W - 0.3, 0.3, Dp - 0.3, 0, 1.25, 0, "bedding")
			for _, sz in { -1, 1 } do
				k:box("Rail", W, 0.12, 0.12, 0, 2.9, sz * (Dp / 2 - 0.08), "wood")
			end
			for _, sx in { -1, 1 } do
				k:box("Rail", 0.12, 0.12, Dp, sx * (W / 2 - 0.08), 2.9, 0, "wood")
				for i = 0, 9 do
					k:box("Slat", 0.08, 1.7, 0.08, sx * (W / 2 - 0.08), 2.0, -Dp / 2 + 0.4 + i * (Dp - 0.8) / 9, "wood")
				end
			end
			k:box("Bunny", 0.4, 0.5, 0.3, 0.4, 1.65, 1.2, k:lit({ 246, 240, 244 }, "fabric"))
			k:box("MobilePole", 0.08, 2.4, 0.08, W / 2 - 0.08, 4.1, Dp / 2 - 0.08, "wood")
			k:box("MobileArm", 0.08, 0.08, 1.3, W / 2 - 0.08, 5.3, Dp / 2 - 0.7, "wood")
			local cols = { { 246, 206, 60 }, { 240, 176, 196 }, { 176, 208, 238 } }
			for i = 0, 2 do
				local a = i * 2.1
				k:box("MobileStr", 0.02, 0.5, 0.02, W / 2 - 0.08 + math.cos(a) * 0.4, 4.95, Dp / 2 - 1.3 + math.sin(a) * 0.4, k:lit({ 236, 232, 222 }))
				k:ball("MobileStar", 0.3, W / 2 - 0.08 + math.cos(a) * 0.4, 4.6, Dp / 2 - 1.3 + math.sin(a) * 0.4, k:lit(cols[i + 1]))
			end
		end,
	})

	D.item({
		id = "kd_slide", cat = "kids", name = "실내 미끄럼틀", price = 159000, decor = 3, style = "kids", place = "floor",
		size = { 2.4, 3.6, 6.4 }, tags = { "미끄럼틀", "놀이", "어린이" },
		slots = { S("slide", "미끄럼", "yellow", { "gloss", "plastic" }), S("frame", "계단", "sky", { "gloss", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Platform", W, 0.25, 1.8, 0, 2.9, Dp / 2 - 1.2, "frame", { solid = true, top = true })
			for _, sx in { -1, 1 } do
				k:box("Side", 0.15, 3.0, 1.8, sx * (W / 2 - 0.075), 1.5, Dp / 2 - 1.2, "frame", { solid = true })
				k:box("Rail", 0.12, 0.9, 1.8, sx * (W / 2 - 0.06), 3.45, Dp / 2 - 1.2, k:sh("frame", 0.85))
				k:box("SlideWall", 0.12, 0.45, 4.3, sx * 0.85, 1.75, -Dp / 2 + 2.15, "slide", { rx = -33 })
			end
			for i = 0, 3 do
				k:box("Step", W - 0.3, 0.15, 0.4, 0, 0.6 + i * 0.7, Dp / 2 - 0.2 + 0.0, k:sh("frame", 1.1))
			end
			k:box("Slide", 1.8, 0.15, 4.4, 0, 1.55, -Dp / 2 + 2.1, "slide", { rx = -33, solid = true })
			k:box("Lip", 1.8, 0.15, 0.6, 0, 0.12, -Dp / 2 + 0.3, "slide")
		end,
	})

	D.item({
		id = "kd_kids_desk", cat = "kids", name = "어린이 책상 + 의자 세트", price = 219000, decor = 3, style = "kids", place = "floor",
		size = { 3.4, 3.4, 3.2 }, tags = { "책상", "공부", "어린이", "학생" },
		slots = { S("top", "상판", "white", { "wood", "plastic" }), S("color", "포인트", "sky", { "gloss", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Top", W, 0.12, 1.8, 0, 2.0, 0.6, "top", { solid = true, top = true })
			for _, sx in { -1, 1 } do
				k:box("Side", 0.12, 1.95, 1.7, sx * (W / 2 - 0.06), 0.97, 0.6, "color", { solid = true })
			end
			k:box("Hutch", W, 1.2, 0.5, 0, 2.66, Dp / 2 - 0.25, "color")
			k:box("HutchShelf", W - 0.2, 0.08, 0.45, 0, 2.7, Dp / 2 - 0.27, "top", { top = true })
			k:books(-1.4, 0.2, 2.74, Dp / 2 - 0.3, 0.4, 0.5, 4)
			k:box("Lamp", 0.2, 0.9, 0.2, 1.3, 2.5, 0.8, k:lit({ 246, 246, 244 }))
			k:box("Book", 0.9, 0.06, 0.6, 0, 2.09, 0.3, k:lit({ 246, 206, 60 }))
			-- chair
			k:box("Seat", 1.3, 0.15, 1.2, 0, 1.25, -0.9, "color", { solid = true })
			k:legs(1.2, 1.1, 1.18, 0.1, 0.12, "top", true)
			k:box("Back", 1.3, 0.9, 0.12, 0, 1.85, -1.45, "color")
			k:seat(0, 1.35, -0.9, 180)
		end,
	})

	D.item({
		id = "kd_dog_house", cat = "kids", name = "강아지 집 (지붕형)", price = 159000, decor = 3, style = "cozy", place = "floor",
		size = { 3.0, 3.2, 3.2 }, tags = { "강아지집", "펫하우스", "반려동물", "펫" },
		slots = { S("wall", "벽", "white", { "wood", "planks", "plastic" }), S("roof", "지붕", "red", { "wood", "plastic", "slate" }) },
		build = function(k, W, H, Dp)
			k:box("Floor", W, 0.2, Dp, 0, 0.1, 0, k:sh("wall", 0.85), { solid = true })
			k:box("Back", W, 2.0, 0.15, 0, 1.2, Dp / 2 - 0.075, "wall", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Side", 0.15, 2.0, Dp, sx * (W / 2 - 0.075), 1.2, 0, "wall", { solid = true })
				k:box("Roof", 1.9, 0.12, Dp + 0.4, sx * 0.72, 2.75, 0, "roof", { rz = sx * -38 })
			end
			k:box("FrontL", 0.8, 2.0, 0.15, -W / 2 + 0.4, 1.2, -Dp / 2 + 0.075, "wall")
			k:box("FrontR", 0.8, 2.0, 0.15, W / 2 - 0.4, 1.2, -Dp / 2 + 0.075, "wall")
			k:box("Gable", 1.4, 0.6, 0.15, 0, 2.5, -Dp / 2 + 0.075, "wall")
			k:box("Sign", 0.8, 0.3, 0.04, 0, 2.5, -Dp / 2 - 0.02, k:lit({ 200, 160, 110 }, "wood"))
			k:box("Cushion", W - 0.4, 0.2, Dp - 0.4, 0, 0.3, 0, k:lit({ 176, 208, 238 }, "fabric"))
			k:cyl("Bowl", 0.2, 0.5, W / 2 + 0.1, 0.1, -Dp / 2 + 0.2, "y", k:lit({ 200, 202, 206 }, "metal"))
		end,
	})

	D.item({
		id = "kd_fishbowl", cat = "kids", name = "금붕어 어항", price = 39000, decor = 3, style = "kids", place = "surface",
		size = { 1.2, 1.3, 1.2 }, tags = { "어항", "금붕어", "물고기", "펫" },
		slots = { S("gravel", "자갈", "sky", { "pebble", "plastic" }) },
		build = function(k, W, H, Dp)
			k:ball("Bowl", 1.2, 0, 0.62, 0, k:lit({ 210, 236, 246 }, "glass"), { t = 0.7, solid = true })
			k:ball("Water", 1.05, 0, 0.58, 0, k:lit({ 90, 170, 220 }, "glass"), { t = 0.6 })
			k:cyl("Gravel", 0.1, 0.75, 0, 0.12, 0, "y", "gravel")
			k:box("Weed", 0.06, 0.4, 0.04, -0.2, 0.35, 0.1, k:lit({ 60, 150, 80 }, "leafy"))
			k:tank(0, 0.6, 0, 0.6, 0.45, 0.6)
		end,
	})
end
