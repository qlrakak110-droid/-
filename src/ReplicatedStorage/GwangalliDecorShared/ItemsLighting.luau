--!strict
-- GwangalliDecorShared/ItemsLighting: 조명 — 플로어 스탠드 · 테이블 램프 · 샹들리에 · 펜던트 · 벽등 ·
-- 네온 사인 · LED 바 · 한지 등 · 무드등. Every piece toggles (불 켜기/끄기) and takes a 빛 색.
-- Ceiling pieces: the top (y = H) touches the ceiling.

return function(D: any)
	local S = D.slot
	local MET = { "metal", "brushed", "plastic" }
	local SHADE = { "fabric", "plaster", "glass", "rattan" }

	-- 아크 플로어 스탠드 ----------------------------------------------------------------------------
	D.item({
		id = "lt_floor_arc", cat = "lighting", name = "아크 플로어 스탠드", price = 260000, decor = 4, style = "modern", place = "floor",
		size = { 4.9, 5.4, 1.6 }, tags = { "스탠드", "장스탠드", "조명" }, light = "warm",
		slots = { S("metal", "프레임", "brass", MET), S("base", "받침", "carrara", { "marble", "concrete", "metal" }) },
		build = function(k, W, H, Dp)
			k:cyl("Base", 0.35, 1.3, -W / 2 + 0.7, 0.175, 0, "y", "base", { solid = true })
			local x0 = -W / 2 + 0.7
			-- straight pole, then an arc (radius 1.9) bending over to the shade
			local pts = { Vector3.new(x0, 0.35, 0) }
			for i = 0, 8 do
				local phi = math.rad(180 - i * 150 / 8)
				table.insert(pts, Vector3.new(x0 + 1.9 + math.cos(phi) * 1.9, 3.2 + math.sin(phi) * 1.9, 0))
			end
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local mid = (a + b) / 2
				local len = (b - a).Magnitude
				local ang = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
				k:cyl("Arc", len + 0.05, 0.12, mid.X, mid.Y, 0, "x", "metal", { rz = ang })
			end
			local tip = pts[#pts]
			k:cyl("Shade", 0.7, 1.4, tip.X, tip.Y - 0.5, 0, "y", "metal", { solid = true })
			k:cyl("ShadeIn", 0.05, 1.25, tip.X, tip.Y - 0.84, 0, "y", k:lit({ 250, 240, 220 }))
			local b = k:ball("Bulb", 0.4, tip.X, tip.Y - 0.75, 0, "light", { glow = true })
			k:light(b, 18, 1.2, { spot = true, face = "Bottom", angle = 90 })
		end,
	})

	-- 린넨 테이블 램프 ------------------------------------------------------------------------------
	D.item({
		id = "lt_table_linen", cat = "lighting", name = "린넨 갓 테이블 램프", price = 89000, decor = 3, style = "natural", place = "surface",
		size = { 1.3, 2.2, 1.3 }, tags = { "램프", "스탠드", "협탁" }, light = "warm",
		slots = { S("body", "몸체", "travertine", { "ceramic", "wood", "marble", "glass" }), S("shade", "갓", "oatmeal", SHADE) },
		build = function(k, W, H, Dp)
			k:cyl("Foot", 0.12, 0.7, 0, 0.06, 0, "y", "body")
			k:ball("Body", 0.75, 0, 0.5, 0, "body", { solid = true })
			k:cyl("Neck", 0.4, 0.14, 0, 1.0, 0, "y", k:lit({ 198, 158, 92 }, "metal"))
			k:cyl("Shade", 0.9, 1.25, 0, 1.68, 0, "y", "shade", { t = 0.15 })
			k:cyl("ShadeTop", 0.05, 0.9, 0, 2.15, 0, "y", k:sh("shade", 0.9))
			local b = k:ball("Bulb", 0.3, 0, 1.55, 0, "light", { glow = true })
			k:light(b, 11, 0.9)
		end,
	})

	-- 크리스탈 샹들리에 ------------------------------------------------------------------------------
	D.item({
		id = "lt_chandelier", cat = "lighting", name = "크리스탈 샹들리에", price = 1450000, decor = 10, style = "luxury", place = "ceiling",
		size = { 3.6, 3.0, 3.6 }, tags = { "샹들리에", "호텔", "조명" }, light = "warm",
		slots = { S("metal", "프레임", "gold", { "metal", "brushed" }) },
		build = function(k, W, H, Dp)
			k:cyl("Canopy", 0.15, 0.9, 0, H - 0.075, 0, "y", "metal")
			k:cyl("Rod", 0.9, 0.08, 0, H - 0.6, 0, "y", "metal")
			k:ball("Hub", 0.55, 0, H - 1.25, 0, "metal", { solid = true })
			k:cyl("Ring", 0.08, 3.2, 0, H - 1.5, 0, "y", "metal")
			k:cyl("RingIn", 0.06, 2.9, 0, H - 1.5, 0, "y", k:sh("metal", 0.8))
			for i = 0, 7 do
				local a = math.rad(i * 45)
				local x, z = math.sin(a) * 1.5, math.cos(a) * 1.5
				k:cyl("Arm", 1.5, 0.06, x / 2, H - 1.38, z / 2, "x", "metal", { ry = math.deg(a) - 90, rz = 8 })
				k:cyl("Cup", 0.15, 0.24, x, H - 1.42, z, "y", "metal")
				k:cyl("Candle", 0.35, 0.12, x, H - 1.18, z, "y", k:lit({ 250, 246, 236 }))
				local fl = k:ball("Flame", 0.14, x, H - 0.96, z, "light", { glow = true })
				if i == 0 then
					k:light(fl, 20, 1.3)
				end
				for j = 1, 3 do
					k:ball("Crystal", 0.13 - j * 0.02, x * 0.97, H - 1.6 - j * 0.24, z * 0.97, k:lit({ 236, 244, 255 }, "glass"), { t = 0.2, rf = 0.4 })
				end
			end
			for j = 1, 5 do
				k:ball("Drop", 0.2, 0, H - 1.55 - j * 0.26, 0, k:lit({ 236, 244, 255 }, "glass"), { t = 0.15, rf = 0.4 })
			end
		end,
	})

	-- "광안리" 네온 사인 ---------------------------------------------------------------------------
	D.item({
		id = "lt_neon_wall", cat = "lighting", name = "네온 사인 '광안리 ♥'", price = 159000, decor = 5, style = "trendy", place = "wall",
		size = { 4.2, 1.6, 0.3 }, tags = { "네온", "사인", "LED", "포인트" }, light = "pink", glow = true,
		slots = { S("back", "아크릴 판", "white", { "glass", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Acrylic", W, H, 0.06, 0, H / 2, Dp / 2 - 0.03, "back", { t = 0.6, solid = true })
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					k:cyl("Standoff", 0.2, 0.1, sx * (W / 2 - 0.15), H / 2 + sy * (H / 2 - 0.15), Dp / 2 - 0.12, "z", k:lit({ 200, 202, 206 }, "metal"))
				end
			end
			local z = Dp / 2 - 0.1
			-- 광
			k:box("Tube", 0.55, 0.07, 0.07, -1.55, 1.15, z, "light", { glow = true })
			k:box("Tube", 0.07, 0.4, 0.07, -1.3, 0.95, z, "light", { glow = true })
			k:box("Tube", 0.6, 0.07, 0.07, -1.55, 0.7, z, "light", { glow = true })
			k:cyl("Ring", 0.07, 0.36, -1.55, 0.38, z, "z", "light", { glow = true })
			-- 안
			k:cyl("Ring", 0.07, 0.4, -0.75, 0.95, z, "z", "light", { glow = true })
			k:box("Tube", 0.07, 0.6, 0.07, -0.42, 0.95, z, "light", { glow = true })
			k:box("Tube", 0.2, 0.07, 0.07, -0.3, 0.95, z, "light", { glow = true })
			k:box("Tube", 0.07, 0.3, 0.07, -0.75, 0.48, z, "light", { glow = true })
			k:box("Tube", 0.45, 0.07, 0.07, -0.55, 0.34, z, "light", { glow = true })
			-- 리
			k:box("Tube", 0.4, 0.07, 0.07, 0.25, 1.15, z, "light", { glow = true })
			k:box("Tube", 0.07, 0.25, 0.07, 0.42, 1.02, z, "light", { glow = true })
			k:box("Tube", 0.4, 0.07, 0.07, 0.25, 0.9, z, "light", { glow = true })
			k:box("Tube", 0.07, 0.25, 0.07, 0.08, 0.78, z, "light", { glow = true })
			k:box("Tube", 0.4, 0.07, 0.07, 0.25, 0.66, z, "light", { glow = true })
			k:box("Tube", 0.07, 0.75, 0.07, 0.7, 0.92, z, "light", { glow = true })
			-- ♥
			local hz = k:cyl("Heart", 0.07, 0.36, 1.45, 1.0, z, "z", "light", { glow = true })
			k:cyl("Heart", 0.07, 0.36, 1.75, 1.0, z, "z", "light", { glow = true })
			k:box("Heart", 0.42, 0.42, 0.07, 1.6, 0.78, z, "light", { glow = true, rz = 45 })
			k:light(hz, 10, 1.1)
		end,
	})

	-- LED 무드 바 ----------------------------------------------------------------------------------
	D.item({
		id = "lt_led_strip", cat = "lighting", name = "RGB LED 무드 바", price = 69000, decor = 3, style = "trendy", place = "wall",
		size = { 4.0, 0.4, 0.25 }, tags = { "LED", "RGB", "게이밍", "무드등" }, light = "violet",
		slots = { S("body", "하우징", "black", { "plastic", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("Housing", W, 0.24, 0.16, 0, 0.2, Dp / 2 - 0.08, "body", { solid = true })
			local led = k:box("LED", W - 0.1, 0.1, 0.04, 0, 0.2, Dp / 2 - 0.18, "light", { glow = true })
			k:box("Glow", W - 0.1, 0.3, 0.02, 0, 0.2, Dp / 2 - 0.02, "light", { glow = true, t = 0.55 })
			k:light(led, 10, 0.9)
		end,
	})

	-- 라탄 펜던트 ------------------------------------------------------------------------------------
	D.item({
		id = "lt_pendant_rattan", cat = "lighting", name = "라탄 펜던트 조명", price = 129000, decor = 4, style = "natural", place = "ceiling",
		size = { 2.2, 3.4, 2.2 }, tags = { "펜던트", "라탄", "식탁등" }, light = "warm",
		slots = { S("shade", "갓", "teak", { "rattan", "fabric", "plaster" }) },
		build = function(k, W, H, Dp)
			k:cyl("Canopy", 0.12, 0.6, 0, H - 0.06, 0, "y", k:lit({ 236, 232, 224 }))
			k:cyl("Cord", H - 1.2, 0.04, 0, H - 0.1 - (H - 1.2) / 2, 0, "y", k:lit({ 30, 30, 32 }))
			k:cyl("Shade", 0.9, 2.1, 0, 0.6, 0, "y", "shade", { solid = true })
			k:cyl("ShadeTop", 0.25, 1.4, 0, 1.15, 0, "y", "shade")
			for i = 0, 5 do
				k:cyl("Weave", 0.04, 2.14, 0, 0.2 + i * 0.15, 0, "y", k:sh("shade", 0.75))
			end
			local b = k:ball("Bulb", 0.4, 0, 0.35, 0, "light", { glow = true })
			k:light(b, 16, 1.1)
		end,
	})

	-- 머쉬룸 램프 ------------------------------------------------------------------------------------
	D.item({
		id = "lt_mushroom", cat = "lighting", name = "머쉬룸 무드 램프", price = 79000, decor = 3, style = "trendy", place = "surface",
		size = { 1.2, 1.4, 1.2 }, tags = { "램프", "무드등", "머쉬룸" }, light = "warm",
		slots = { S("body", "몸체", "butter", { "gloss", "glass", "plastic" }) },
		build = function(k, W, H, Dp)
			k:cyl("Foot", 0.12, 0.8, 0, 0.06, 0, "y", "body")
			k:cyl("Stem", 0.8, 0.28, 0, 0.5, 0, "y", "body", { solid = true })
			local dome = k:ball("Dome", 1.2, 0, 1.0, 0, "body", { t = 0.1 })
			k:cyl("Rim", 0.08, 1.15, 0, 0.94, 0, "y", k:sh("body", 0.9))
			local b = k:ball("Bulb", 0.3, 0, 0.88, 0, "light", { glow = true })
			local _ = dome
			k:light(b, 8, 0.7)
		end,
	})

	-- 삼각대 플로어 램프 ----------------------------------------------------------------------------
	D.item({
		id = "lt_tripod", cat = "lighting", name = "우드 삼각대 플로어 램프", price = 149000, decor = 4, style = "natural", place = "floor",
		size = { 2.2, 5.6, 2.2 }, tags = { "스탠드", "삼각대", "장스탠드" }, light = "warm",
		slots = { S("wood", "다리", "walnut", { "wood", "metal" }), S("shade", "갓", "ivory", SHADE) },
		build = function(k, W, H, Dp)
			for i = 0, 2 do
				local a = math.rad(i * 120)
				local x, z = math.sin(a) * 0.7, math.cos(a) * 0.7
				k:cyl("Leg", 4.2, 0.12, x * 0.5, 2.05, z * 0.5, "y", "wood", { rx = -math.cos(a) * 10, rz = math.sin(a) * 10 })
			end
			k:cyl("Neck", 0.5, 0.1, 0, 4.3, 0, "y", k:lit({ 198, 158, 92 }, "metal"))
			k:cyl("Shade", 1.1, 1.9, 0, 4.9, 0, "y", "shade", { t = 0.15, solid = true })
			local b = k:ball("Bulb", 0.35, 0, 4.7, 0, "light", { glow = true })
			k:light(b, 16, 1.0)
		end,
	})

	-- 한지 등 ----------------------------------------------------------------------------------------
	D.item({
		id = "lt_hanji", cat = "lighting", name = "한지 플로어 등", price = 118000, decor = 4, style = "classic", place = "floor",
		size = { 1.5, 4.0, 1.5 }, tags = { "한지", "전통", "등", "한옥" }, light = "amber",
		slots = { S("paper", "한지", "ivory", { "fabric", "plaster" }), S("wood", "살대", "ebony", { "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W, 0.25, Dp, 0, 0.125, 0, "wood", { solid = true })
			k:box("Lantern", W - 0.1, 3.4, Dp - 0.1, 0, 1.95, 0, "paper", { t = 0.2, solid = true })
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:box("Post", 0.1, 3.6, 0.1, sx * (W / 2 - 0.05), 1.95, sz * (Dp / 2 - 0.05), "wood")
				end
			end
			for i = 1, 3 do
				k:box("Rail", W, 0.06, 0.06, 0, 0.25 + i * 0.85, -Dp / 2 + 0.02, "wood")
				k:box("Rail", W, 0.06, 0.06, 0, 0.25 + i * 0.85, Dp / 2 - 0.02, "wood")
			end
			k:box("Cap", W + 0.1, 0.15, Dp + 0.1, 0, H - 0.08, 0, "wood")
			local b = k:ball("Bulb", 0.5, 0, 2.0, 0, "light", { glow = true })
			k:light(b, 12, 0.9)
		end,
	})

	-- 브라스 벽등 ------------------------------------------------------------------------------------
	D.item({
		id = "lt_sconce", cat = "lighting", name = "브라스 벽등 (스콘스)", price = 98000, decor = 3, style = "classic", place = "wall",
		size = { 0.9, 1.6, 1.0 }, tags = { "벽등", "스콘스", "브라스" }, light = "warm",
		slots = { S("metal", "몸체", "brass", MET), S("shade", "갓", "white", { "glass", "fabric" }) },
		build = function(k, W, H, Dp)
			k:cyl("Plate", 0.08, 0.7, 0, 0.6, Dp / 2 - 0.04, "z", "metal", { solid = true })
			k:cyl("Arm", 0.7, 0.08, 0, 0.75, Dp / 2 - 0.4, "z", "metal", { rx = -20 })
			k:cyl("Cup", 0.15, 0.3, 0, 0.88, -Dp / 2 + 0.4, "y", "metal")
			k:cyl("Globe", 0.65, 0.7, 0, 1.22, -Dp / 2 + 0.4, "y", "shade", { t = 0.25 })
			local b = k:ball("Bulb", 0.26, 0, 1.15, -Dp / 2 + 0.4, "light", { glow = true })
			k:light(b, 10, 0.7)
		end,
	})

	-- 달 무드등 --------------------------------------------------------------------------------------
	D.item({
		id = "lt_moon", cat = "lighting", name = "3D 달 무드등", price = 35000, decor = 2, style = "cozy", place = "surface",
		size = { 1.1, 1.4, 1.1 }, tags = { "무드등", "달", "수면등" }, light = "warm",
		slots = { S("stand", "받침", "oak", { "wood", "metal" }) },
		build = function(k, W, H, Dp)
			k:cyl("Stand", 0.15, 0.7, 0, 0.075, 0, "y", "stand", { solid = true })
			k:cyl("Cradle", 0.2, 0.3, 0, 0.25, 0, "y", "stand")
			local m = k:ball("Moon", 1.05, 0, 0.88, 0, "light", { glow = true })
			for i = 0, 3 do
				local a = math.rad(i * 95 + 20)
				k:ball("Crater", 0.18, math.cos(a) * 0.4, 0.95 + math.sin(a) * 0.2, -0.32, k:shp("light", 0.82), { glow = true })
			end
			k:light(m, 8, 0.55)
		end,
	})

	-- 데스크 스탠드 ---------------------------------------------------------------------------------
	D.item({
		id = "lt_desk_task", cat = "lighting", name = "LED 공부 스탠드", price = 59000, decor = 1, style = "modern", place = "surface",
		size = { 1.2, 2.0, 1.4 }, tags = { "스탠드", "책상", "공부" }, light = "cool",
		slots = { S("body", "몸체", "white", { "plastic", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("Base", 0.9, 0.1, 0.9, 0, 0.05, 0.3, "body", { solid = true })
			k:box("Arm", 0.09, 1.4, 0.09, 0, 0.78, 0.36, "body", { rx = -8 })
			k:ball("Joint", 0.16, 0, 1.47, 0.44, k:sh("body", 0.85))
			k:box("Arm", 0.09, 0.09, 1.05, 0, 1.52, -0.04, "body", { rx = -5 })
			k:box("Head", 0.42, 0.1, 0.72, 0, 1.52, -0.66, "body")
			local led = k:box("LEDPanel", 0.34, 0.03, 0.62, 0, 1.455, -0.66, "light", { glow = true })
			k:light(led, 8, 0.6, { spot = true, face = "Bottom", angle = 80 })
		end,
	})
end
