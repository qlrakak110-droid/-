--!strict
-- GwangalliDecorShared/ItemsKitchen: 주방 — 식탁 세트 · 바 스툴 · 아일랜드 · 냉장고 (문 열기) · 김치냉장고 ·
-- 홈카페 · 전자레인지 · 밥솥 · 벽 선반 · 펜던트 · 와인랙 · 트롤리.

return function(D: any)
	local S = D.slot
	local WOODM = { "wood", "planks", "gloss", "plastic" }
	local APPM = { "gloss", "metal", "brushed", "plastic" }

	local function chair(k: any, x: number, z: number, yaw: number, wood: any, seat: any)
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
		local function at(px: number, py: number, pz: number): CFrame
			return cf * CFrame.new(px, py, pz)
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				k:boxAt("ChairLeg", 0.13, 1.35, 0.13, at(sx * 0.62, 0.675, sz * 0.6), wood)
			end
			k:boxAt("ChairPost", 0.12, 1.6, 0.12, at(sx * 0.62, 2.1, 0.62), wood)
		end
		k:boxAt("ChairSeat", 1.45, 0.14, 1.45, at(0, 1.42, 0), seat, { solid = true })
		k:boxAt("ChairRail", 1.3, 0.3, 0.1, at(0, 2.55, 0.64), wood)
		k:boxAt("ChairRail", 1.3, 0.12, 0.08, at(0, 2.0, 0.64), wood)
		table.insert(k.seats, { cf = cf * CFrame.new(0, 1.5, 0), lie = false })
	end

	-- 4인 원목 식탁 세트 ----------------------------------------------------------------------------
	D.item({
		id = "kt_dining_4", cat = "kitchen", name = "4인 원목 식탁 세트", price = 690000, decor = 5, style = "natural", place = "floor",
		size = { 6.6, 3.2, 6.0 }, tags = { "식탁", "테이블", "의자", "다이닝" },
		slots = { S("wood", "원목", "oak", WOODM), S("seat", "의자 방석", "oak", { "wood", "fabric", "leather" }) },
		build = function(k, W, H, Dp)
			local tw, td = 4.8, 2.9
			k:box("Top", tw, 0.16, td, 0, 2.42, 0, "wood", { solid = true, top = true })
			k:box("Apron", tw - 0.5, 0.3, td - 0.5, 0, 2.2, 0, k:sh("wood", 0.9))
			k:legs(tw, td, 2.34, 0.28, 0.24, k:sh("wood", 0.94))
			for _, sx in { -1, 1 } do
				chair(k, sx * 1.2, -td / 2 - 0.55, 180, k:sh("wood", 0.96), "seat")
				chair(k, sx * 1.2, td / 2 + 0.55, 0, k:sh("wood", 0.96), "seat")
			end
			k:box("Runner", 0.9, 0.03, td - 0.2, 0, 2.515, 0, k:lit({ 236, 228, 210 }, "fabric"))
			k:cyl("Vase", 0.6, 0.35, 0, 2.8, 0, "y", k:lit({ 240, 240, 236 }, "ceramic"))
			k:foliage(0, 3.3, 0, 0.35, 5, k:lit({ 110, 150, 100 }, "leafy"))
			for _, sx in { -1, 1 } do
				k:cyl("Plate", 0.05, 0.75, sx * 1.2, 2.53, -0.8, "y", k:lit({ 246, 246, 244 }, "ceramic"))
				k:cyl("Plate", 0.05, 0.75, sx * 1.2, 2.53, 0.8, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			end
		end,
	})

	-- 대리석 6인 식탁 -------------------------------------------------------------------------------
	D.item({
		id = "kt_dining_marble", cat = "kitchen", name = "대리석 6인 식탁 + 벨벳 체어", price = 2600000, decor = 9, style = "luxury", place = "floor",
		size = { 9.0, 3.4, 6.2 }, tags = { "식탁", "대리석", "다이닝", "호텔" },
		slots = { S("stone", "상판", "carrara", { "marble", "granite", "glass", "wood" }), S("chair", "체어", "teal", { "velvet", "leather", "fabric" }), S("metal", "다리", "gold", { "metal", "brushed" }) },
		build = function(k, W, H, Dp)
			local tw, td = 7.0, 3.0
			k:box("Top", tw, 0.18, td, 0, 2.45, 0, "stone", { solid = true, top = true })
			for _, sx in { -1, 1 } do
				k:box("Pedestal", 0.5, 2.3, 1.6, sx * 2.2, 1.18, 0, "metal", { solid = true })
				k:box("Foot", 0.9, 0.1, 2.2, sx * 2.2, 0.05, 0, "metal")
			end
			for i = -1, 1 do
				for _, sz in { -1, 1 } do
					local x, z = i * 2.2, sz * (td / 2 + 0.6)
					local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, if sz < 0 then math.pi else 0, 0)
					k:boxAt("ChairSeat", 1.5, 0.35, 1.45, cf * CFrame.new(0, 1.42, 0), "chair", { solid = true })
					k:boxAt("ChairBack", 1.5, 1.6, 0.3, cf * CFrame.new(0, 2.35, 0.62) * CFrame.Angles(math.rad(-8), 0, 0), "chair")
					for _, lx in { -1, 1 } do
						for _, lz in { -1, 1 } do
							k:boxAt("ChairLeg", 0.08, 1.25, 0.08, cf * CFrame.new(lx * 0.6, 0.62, lz * 0.55), "metal")
						end
					end
					table.insert(k.seats, { cf = cf * CFrame.new(0, 1.6, 0), lie = false })
				end
			end
			for i = -1, 1 do
				k:cyl("Candle", 0.7, 0.16, i * 0.5, 2.9, 0, "y", k:lit({ 240, 232, 220 }))
			end
			k:box("Tray", 1.8, 0.04, 0.6, 0, 2.56, 0, k:as("metal", "metal"))
		end,
	})

	-- 비스트로 2인 테이블 ---------------------------------------------------------------------------
	D.item({
		id = "kt_bistro_set", cat = "kitchen", name = "비스트로 2인 원형 테이블 세트", price = 260000, decor = 3, style = "trendy", place = "floor",
		size = { 4.6, 3.2, 2.6 }, tags = { "카페", "테이블", "의자", "홈카페" },
		slots = { S("top", "상판", "white", { "marble", "wood", "gloss" }), S("metal", "프레임", "matteblack", { "metal", "brushed" }), S("seat", "의자", "camel", { "rattan", "wood", "leather" }) },
		build = function(k, W, H, Dp)
			k:cyl("Top", 0.1, 2.2, 0, 2.4, 0, "y", "top", { solid = true, top = true })
			k:cyl("Stem", 2.3, 0.16, 0, 1.2, 0, "y", "metal", { solid = true })
			k:cyl("Base", 0.08, 1.3, 0, 0.04, 0, "y", "metal")
			for _, sx in { -1, 1 } do
				local x = sx * 1.75
				k:cyl("Seat", 0.14, 1.25, x, 1.42, 0, "y", "seat", { solid = true })
				for i = 0, 3 do
					local a = i * math.pi / 2 + math.pi / 4
					k:cyl("Leg", 1.4, 0.08, x + math.cos(a) * 0.42, 0.7, math.sin(a) * 0.42, "y", "metal", { rx = math.sin(a) * 4, rz = -math.cos(a) * 4 })
				end
				k:box("Back", 0.08, 1.0, 1.1, x + sx * 0.58, 2.05, 0, "seat", { rz = -sx * 10 })
				k:seat(x, 1.5, 0, sx * 90)
			end
			k:cyl("Cup", 0.24, 0.24, -0.35, 2.57, 0.2, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			k:cyl("Cup", 0.24, 0.24, 0.35, 2.57, -0.2, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			k:cyl("Saucer", 0.03, 0.4, -0.35, 2.465, 0.2, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			k:cyl("Saucer", 0.03, 0.4, 0.35, 2.465, -0.2, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			k:box("Croissant", 0.4, 0.14, 0.2, 0, 2.52, 0.4, k:lit({ 214, 160, 80 }, "plastic"), { ry = 30 })
		end,
	})

	-- 바 스툴 ---------------------------------------------------------------------------------------
	D.item({
		id = "kt_bar_stool", cat = "kitchen", name = "가죽 바 스툴", price = 120000, decor = 2, style = "modern", place = "floor",
		size = { 1.5, 3.6, 1.5 }, tags = { "스툴", "의자", "바" },
		slots = { S("seat", "시트", "camel", { "leather", "velvet", "wood" }), S("metal", "프레임", "matteblack", { "metal", "brushed", "wood" }) },
		build = function(k, W, H, Dp)
			k:cyl("Seat", 0.3, 1.35, 0, 2.85, 0, "y", "seat", { solid = true })
			k:box("Back", 1.1, 0.55, 0.12, 0, 3.3, 0.55, "seat", { rx = -10 })
			for i = 0, 3 do
				local a = i * math.pi / 2 + math.pi / 4
				k:cyl("Leg", 2.75, 0.09, math.cos(a) * 0.52, 1.36, math.sin(a) * 0.52, "y", "metal", { rx = math.sin(a) * 5, rz = -math.cos(a) * 5 })
			end
			k:cyl("Ring", 0.07, 1.25, 0, 0.9, 0, "y", "metal")
			k:seat(0, 3.0, 0)
		end,
	})

	-- 아일랜드 식탁 ---------------------------------------------------------------------------------
	D.item({
		id = "kt_island", cat = "kitchen", name = "아일랜드 식탁 (수납형)", price = 1400000, decor = 6, style = "modern", place = "floor",
		size = { 6.4, 3.0, 3.0 }, tags = { "아일랜드", "주방", "수납", "조리대" },
		slots = { S("body", "몸체", "white", APPM), S("top", "상판", "carrara", { "marble", "granite", "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Kick", W - 0.4, 0.3, Dp - 0.6, 0, 0.15, 0.15, k:lit({ 40, 40, 44 }))
			k:box("Body", W - 0.2, H - 0.42, Dp - 0.5, 0, 0.3 + (H - 0.42) / 2 - 0.12, 0.25, "body", { solid = true })
			k:box("Top", W, 0.16, Dp, 0, H - 0.08, 0, "top", { solid = true, top = true })
			for i = 0, 3 do
				local x = -W / 2 + 0.85 + i * (W - 1.7) / 3
				k:box("Door", (W - 0.4) / 4 - 0.08, H - 0.8, 0.05, x, 0.35 + (H - 0.8) / 2, Dp / 2 + 0.02, k:sh("body", 0.97))
				k:box("Pull", 0.06, 0.8, 0.07, x + 0.55, H - 0.9, Dp / 2 + 0.08, k:lit({ 190, 192, 196 }, "metal"))
			end
			k:box("Bowl", 0.9, 0.3, 0.9, -1.5, H + 0.15, -0.3, k:lit({ 236, 236, 232 }, "ceramic"))
			for i = 0, 2 do
				k:ball("Apple", 0.3, -1.5 + (i - 1) * 0.25, H + 0.38, -0.3 + (i % 2) * 0.15, k:lit({ 200, 40, 40 }))
			end
			k:box("Board", 1.4, 0.08, 0.9, 1.2, H + 0.04, 0.2, k:lit({ 180, 130, 80 }, "wood"))
		end,
	})

	-- 4도어 냉장고 ----------------------------------------------------------------------------------
	D.item({
		id = "kt_fridge_4door", cat = "kitchen", name = "4도어 냉장고 (메탈)", price = 2400000, decor = 5, style = "modern", place = "floor",
		size = { 3.4, 6.0, 2.6 }, tags = { "냉장고", "가전", "주방" }, light = "cool", toggle = false,
		uses = { open = "냉장고 문 열기", close = "냉장고 문 닫기" },
		slots = { S("body", "도어", "lightgrey", APPM) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp - 0.2, 0, H / 2, 0.1, k:sh("body", 0.9), { solid = true })
			k:box("Inside", W - 0.3, H - 0.4, 0.05, 0, H / 2, -Dp / 2 + 0.25, k:lit({ 236, 240, 244 }, "plastic"))
			for i = 0, 2 do
				k:box("Shelf", W - 0.4, 0.04, Dp - 0.6, 0, H * 0.45 + i * 0.95, 0.1, k:lit({ 220, 236, 244 }, "glass"), { t = 0.3 })
			end
			k:box("Milk", 0.35, 0.8, 0.35, -0.8, H * 0.45 + 0.42, -0.3, k:lit({ 246, 246, 244 }))
			k:box("Kimchi", 0.7, 0.45, 0.6, 0.6, H * 0.45 + 1.2, 0, k:lit({ 214, 80, 60 }))
			local glow = k:box("FridgeLight", W - 0.6, 0.05, 0.2, 0, H - 0.3, -0.2, "light", { glow = true })
			local _ = glow
			local hw = W / 2
			local upper = H * 0.42
			local doors = {}
			for _, sx in { -1, 1 } do
				local d = k:box("Door", hw - 0.04, H - upper - 0.06, 0.18, sx * hw / 2, upper + (H - upper) / 2, -Dp / 2 + 0.09, "body")
				local h = k:box("Handle", 0.08, 1.6, 0.12, sx * 0.12, upper + 1.4, -Dp / 2 - 0.05, k:lit({ 200, 202, 206 }, "metal"))
				k:hinge({ d, h }, sx * hw, 0, -Dp / 2, "y", -sx * 105)
				table.insert(doors, d)
				k:box("Drawer", hw - 0.04, upper / 2 - 0.06, 0.16, sx * hw / 2, upper * 0.75, -Dp / 2 + 0.08, "body")
				k:box("Drawer", hw - 0.04, upper / 2 - 0.1, 0.16, sx * hw / 2, upper * 0.27, -Dp / 2 + 0.08, "body")
				k:box("Grip", hw - 0.5, 0.06, 0.08, sx * hw / 2, upper - 0.12, -Dp / 2 - 0.02, k:lit({ 200, 202, 206 }, "metal"))
			end
			k:box("Display", 0.5, 0.3, 0.02, -hw / 2, upper + 2.0, -Dp / 2 - 0.01, k:lit({ 120, 200, 255 }, "neon"))
		end,
	})

	-- 김치냉장고 ------------------------------------------------------------------------------------
	D.item({
		id = "kt_kimchi", cat = "kitchen", name = "스탠드형 김치냉장고", price = 1350000, decor = 4, style = "modern", place = "floor",
		size = { 2.3, 5.4, 2.4 }, tags = { "김치냉장고", "가전", "김치" },
		uses = { open = "문 열기", close = "문 닫기" },
		slots = { S("body", "도어", "blush", APPM) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp - 0.2, 0, H / 2, 0.1, k:sh("body", 0.88), { solid = true })
			k:box("Inside", W - 0.3, H - 0.5, 0.05, 0, H / 2, -Dp / 2 + 0.3, k:lit({ 236, 240, 244 }))
			for i = 0, 2 do
				k:box("Tong", W - 0.5, 0.9, Dp - 0.8, 0, 0.5 + i * 1.6, 0.1, k:lit({ 230, 120, 90 }))
			end
			local d1 = k:box("Door", W - 0.04, H * 0.42, 0.16, 0, H - H * 0.21, -Dp / 2 + 0.08, "body")
			local h1 = k:box("Handle", W - 0.6, 0.08, 0.1, 0, H - H * 0.42 + 0.2, -Dp / 2 - 0.04, k:lit({ 200, 202, 206 }, "metal"))
			k:hinge({ d1, h1 }, -W / 2, 0, -Dp / 2, "y", 100)
			for i = 0, 1 do
				k:box("Drawer", W - 0.04, H * 0.27, 0.16, 0, 0.1 + H * 0.135 + i * H * 0.29, -Dp / 2 + 0.08, "body")
				k:box("Grip", W - 0.6, 0.06, 0.08, 0, 0.1 + H * 0.27 - 0.15 + i * H * 0.29, -Dp / 2 - 0.02, k:lit({ 200, 202, 206 }, "metal"))
			end
			k:box("Display", 0.6, 0.25, 0.02, 0, H - 0.6, -Dp / 2 - 0.01, k:lit({ 120, 200, 255 }, "neon"))
		end,
	})

	-- 홈카페 커피 스테이션 --------------------------------------------------------------------------
	D.item({
		id = "kt_coffee_station", cat = "kitchen", name = "홈카페 커피 스테이션", price = 780000, decor = 6, style = "trendy", place = "floor",
		size = { 4.2, 3.4, 1.8 }, tags = { "커피", "홈카페", "에스프레소", "카페" },
		slots = { S("cab", "캐비닛", "walnut", WOODM), S("machine", "머신", "chrome", { "brushed", "metal", "gloss" }) },
		build = function(k, W, H, Dp)
			local top = 2.8
			k:box("Cabinet", W, top - 0.1, Dp, 0, (top - 0.1) / 2, 0, "cab", { solid = true })
			k:box("Top", W + 0.06, 0.12, Dp + 0.06, 0, top - 0.04, 0, k:lit({ 236, 236, 232 }, "marble"), { top = true })
			for _, sx in { -1, 1 } do
				k:front(W / 2 - 0.1, top - 0.4, sx * W / 4, 0.25 + (top - 0.4) / 2, -Dp / 2, k:sh("cab", 1.05), k:lit({ 198, 158, 92 }, "metal"), true)
			end
			local y = top + 0.02
			k:box("Espresso", 1.4, 1.1, 1.1, -0.9, y + 0.55, 0.1, "machine", { solid = true })
			k:box("Group", 0.5, 0.2, 0.4, -0.9, y + 0.65, -0.55, k:lit({ 40, 40, 44 }, "metal"))
			k:cyl("Portafilter", 0.6, 0.1, -0.9, y + 0.5, -0.85, "z", k:lit({ 30, 24, 20 }, "wood"))
			k:cyl("Gauge", 0.05, 0.3, -1.3, y + 0.85, -0.47, "z", k:lit({ 240, 240, 236 }))
			k:box("Tray", 0.9, 0.06, 0.5, -0.9, y + 0.05, -0.55, k:lit({ 60, 60, 66 }, "metal"))
			k:cyl("Cup", 0.24, 0.24, -0.9, y + 0.2, -0.6, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			k:box("Grinder", 0.5, 0.9, 0.55, 0.3, y + 0.45, 0.1, k:lit({ 36, 36, 40 }))
			k:cyl("Hopper", 0.5, 0.45, 0.3, y + 1.15, 0.1, "y", k:lit({ 120, 80, 50 }, "glass"), { t = 0.3 })
			for i = 0, 3 do
				k:cyl("Mug", 0.32, 0.3, 1.05 + (i % 2) * 0.38, y + 0.16 + math.floor(i / 2) * 0.33, -0.2 + (i % 2) * 0.1, "y", k:lit(if i % 2 == 0 then { 246, 246, 244 } else { 60, 100, 140 }, "ceramic"))
			end
			k:box("Jar", 0.35, 0.5, 0.35, 1.6, y + 0.25, 0.4, k:lit({ 220, 230, 236 }, "glass"), { t = 0.3 })
		end,
	})

	-- 전자레인지 ------------------------------------------------------------------------------------
	D.item({
		id = "kt_microwave", cat = "kitchen", name = "전자레인지", price = 160000, decor = 1, style = "modern", place = "surface",
		size = { 1.8, 1.05, 1.3 }, tags = { "전자레인지", "가전" },
		slots = { S("body", "몸체", "white", APPM) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp, 0, H / 2, 0, "body", { solid = true, top = true })
			k:box("Window", W * 0.62, H * 0.66, 0.03, -W * 0.13, H / 2, -Dp / 2 - 0.01, k:lit({ 30, 34, 40 }, "glass"), { t = 0.1 })
			k:box("Panel", W * 0.22, H * 0.8, 0.03, W * 0.36, H / 2, -Dp / 2 - 0.01, k:lit({ 50, 52, 58 }))
			k:box("Clock", 0.25, 0.1, 0.02, W * 0.36, H * 0.75, -Dp / 2 - 0.03, k:lit({ 120, 255, 160 }, "neon"))
			k:cyl("Dial", 0.06, 0.22, W * 0.36, H * 0.4, -Dp / 2 - 0.04, "z", k:lit({ 200, 202, 206 }, "metal"))
		end,
	})

	-- 전기밥솥 --------------------------------------------------------------------------------------
	D.item({
		id = "kt_rice_cooker", cat = "kitchen", name = "IH 전기밥솥 (10인용)", price = 290000, decor = 1, style = "modern", place = "surface",
		size = { 1.2, 1.15, 1.35 }, tags = { "밥솥", "쿠쿠", "가전" },
		slots = { S("body", "몸체", "white", APPM), S("accent", "포인트", "red", { "gloss", "metal" }) },
		build = function(k, W, H, Dp)
			k:cyl("Body", 0.85, W, 0, 0.425, 0, "y", "body", { solid = true })
			k:cyl("Lid", 0.3, W - 0.05, 0, 0.98, 0.02, "y", "accent")
			k:box("Handle", 0.7, 0.12, 0.25, 0, 1.17, 0, k:sh("body", 0.85))
			k:box("Panel", 0.55, 0.35, 0.05, 0, 0.6, -W / 2 + 0.03, k:lit({ 30, 30, 34 }), { rx = -10 })
			k:box("Screen", 0.3, 0.1, 0.02, 0, 0.66, -W / 2 - 0.0, k:lit({ 255, 160, 60 }, "neon"), { rx = -10 })
			k:box("Spatula", 0.12, 0.6, 0.04, W / 2 + 0.02, 0.5, 0.2, k:lit({ 240, 240, 236 }))
		end,
	})

	-- 주방 벽 선반 ----------------------------------------------------------------------------------
	D.item({
		id = "kt_wall_shelf", cat = "kitchen", name = "주방 벽 선반 (유리병 · 머그)", price = 98000, decor = 3, style = "natural", place = "wall",
		size = { 3.6, 2.0, 0.9 }, tags = { "선반", "벽", "주방", "홈카페" },
		slots = { S("wood", "선반", "oak", WOODM), S("metal", "브래킷", "matteblack", { "metal", "brushed" }) },
		build = function(k, W, H, Dp)
			for i = 0, 1 do
				local y = 0.15 + i * 1.15
				k:box("Board", W, 0.12, Dp - 0.05, 0, y, 0, "wood", { solid = true, top = true })
				for _, sx in { -1, 1 } do
					k:box("Bracket", 0.06, 0.4, Dp - 0.2, sx * (W / 2 - 0.4), y - 0.25, 0.05, "metal")
				end
			end
			for i = 0, 3 do
				k:cyl("Jar", 0.6, 0.38, -W / 2 + 0.45 + i * 0.5, 0.51, -0.05, "y", k:lit({ 220, 230, 236 }, "glass"), { t = 0.35 })
				k:cyl("JarFill", 0.3, 0.32, -W / 2 + 0.45 + i * 0.5, 0.36, -0.05, "y", k:lit(({ { 120, 80, 50 }, { 236, 226, 200 }, { 200, 150, 60 }, { 60, 40, 30 } })[i + 1]))
				k:cyl("Lid", 0.08, 0.4, -W / 2 + 0.45 + i * 0.5, 0.85, -0.05, "y", k:lit({ 190, 150, 100 }, "wood"))
			end
			for i = 0, 2 do
				k:cyl("Mug", 0.34, 0.3, W / 2 - 0.4 - i * 0.42, 1.49, -0.05, "y", k:lit(({ { 246, 246, 244 }, { 40, 40, 44 }, { 176, 208, 238 } })[i + 1], "ceramic"))
			end
			k:box("Book", 0.15, 0.7, 0.55, -1.1, 1.56, 0, k:lit({ 176, 56, 52 }))
			k:box("Book", 0.15, 0.62, 0.55, -0.93, 1.52, 0, k:lit({ 60, 100, 76 }))
			local soil = k:pot(-0.4, 0, 0.36, 0.34, k:lit({ 238, 236, 230 }, "ceramic"), true, 1.36)
			k:foliage(-0.4, soil + 0.2, 0, 0.22, 4, k:lit({ 90, 140, 80 }, "leafy"))
		end,
	})

	-- 펜던트 조명 3구 -------------------------------------------------------------------------------
	D.item({
		id = "kt_pendant_trio", cat = "kitchen", name = "펜던트 조명 3구 (식탁등)", price = 240000, decor = 4, style = "modern", place = "ceiling",
		size = { 4.4, 2.6, 1.0 }, tags = { "펜던트", "조명", "식탁등" }, light = "warm",
		slots = { S("shade", "갓", "matteblack", { "metal", "brushed", "glass", "rattan" }) },
		build = function(k, W, H, Dp)
			k:box("Canopy", W, 0.1, 0.5, 0, H - 0.05, 0, "shade")
			for i = -1, 1 do
				local x = i * 1.5
				k:box("Cord", 0.03, H - 0.9, 0.03, x, H - 0.1 - (H - 0.9) / 2, 0, k:lit({ 30, 30, 32 }))
				k:cyl("Shade", 0.7, 0.9, x, 0.6, 0, "y", "shade", { solid = true })
				k:cyl("ShadeTop", 0.2, 0.4, x, 1.05, 0, "y", "shade")
				local b = k:ball("Bulb", 0.4, x, 0.25, 0, "light", { glow = true })
				if i == 0 then
					k:light(b, 14, 1.0)
				end
			end
		end,
	})

	-- 케이크 스탠드 ---------------------------------------------------------------------------------
	D.item({
		id = "kt_cake_stand", cat = "kitchen", name = "유리 돔 케이크 스탠드", price = 45000, decor = 2, style = "cozy", place = "surface",
		size = { 1.1, 1.3, 1.1 }, tags = { "케이크", "디저트", "홈카페" },
		slots = { S("cake", "케이크", "blush", { "plastic", "fabric" }) },
		build = function(k, W, H, Dp)
			k:cyl("Foot", 0.3, 0.3, 0, 0.15, 0, "y", k:lit({ 240, 240, 236 }, "ceramic"))
			k:cyl("Plate", 0.06, W, 0, 0.33, 0, "y", k:lit({ 240, 240, 236 }, "ceramic"), { top = true })
			k:cyl("Cake", 0.4, 0.75, 0, 0.56, 0, "y", "cake")
			k:cyl("Cream", 0.08, 0.77, 0, 0.78, 0, "y", k:lit({ 250, 246, 236 }))
			for i = 0, 4 do
				local a = i * math.pi * 2 / 5
				k:ball("Berry", 0.11, math.cos(a) * 0.25, 0.85, math.sin(a) * 0.25, k:lit({ 210, 30, 50 }))
			end
			k:ball("Dome", W - 0.05, 0, 0.6, 0, k:lit({ 220, 232, 238 }, "glass"), { t = 0.7 })
		end,
	})

	-- 와인 랙 ---------------------------------------------------------------------------------------
	D.item({
		id = "kt_wine_rack", cat = "kitchen", name = "와인 랙 (20병)", price = 330000, decor = 4, style = "luxury", place = "floor",
		size = { 2.6, 4.6, 1.2 }, tags = { "와인", "랙", "바" },
		slots = { S("frame", "프레임", "walnut", { "wood", "metal" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Side", 0.14, H, Dp, sx * (W / 2 - 0.07), H / 2, 0, "frame", { solid = true })
			end
			k:box("Top", W, 0.14, Dp, 0, H - 0.07, 0, "frame", { top = true })
			k:box("Base", W, 0.2, Dp, 0, 0.1, 0, "frame")
			local wine = { { 70, 20, 30 }, { 40, 60, 30 }, { 90, 30, 40 }, { 230, 220, 160 } }
			for r = 0, 4 do
				for c = 0, 3 do
					local x = -W / 2 + 0.42 + c * (W - 0.84) / 3
					local y = 0.5 + r * 0.8
					k:box("Cradle", 0.5, 0.06, Dp - 0.1, x, y - 0.18, 0, k:sh("frame", 1.1))
					k:cyl("Bottle", Dp - 0.1, 0.32, x, y, -0.02, "z", k:lit(wine[((r + c) % #wine) + 1], "glass"), { t = 0.1 })
					k:cyl("Neck", 0.2, 0.12, x, y, -Dp / 2 - 0.05, "z", k:lit({ 120, 30, 40 }, "foil"))
				end
			end
			k:cyl("Glass", 0.5, 0.25, -0.5, H + 0.25, 0, "y", k:lit({ 220, 232, 238 }, "glass"), { t = 0.6 })
		end,
	})

	-- 식기건조대 ------------------------------------------------------------------------------------
	D.item({
		id = "kt_dish_rack", cat = "kitchen", name = "스테인리스 식기건조대", price = 49000, decor = 1, style = "modern", place = "surface",
		size = { 1.9, 1.1, 1.2 }, tags = { "식기", "건조대", "그릇" },
		slots = { S("metal", "프레임", "chrome", { "metal", "brushed", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Tray", W, 0.08, Dp, 0, 0.04, 0, k:lit({ 220, 222, 226 }, "plastic"))
			for _, sx in { -1, 1 } do
				k:box("Frame", 0.05, 0.7, Dp - 0.1, sx * (W / 2 - 0.05), 0.42, 0, "metal")
			end
			for i = 0, 5 do
				k:box("Wire", W - 0.1, 0.03, 0.03, 0, 0.12 + (i % 2) * 0.55, -Dp / 2 + 0.1 + math.floor(i / 2) * 0.45, "metal")
			end
			for i = 0, 3 do
				k:cyl("Plate", 0.05, 0.8, -0.5 + i * 0.16, 0.5, 0.15, "x", k:lit({ 246, 246, 244 }, "ceramic"))
			end
			k:cyl("Bowl", 0.3, 0.6, 0.55, 0.35, -0.2, "y", k:lit({ 236, 236, 232 }, "ceramic"))
			k:cyl("Cup", 0.3, 0.26, 0.55, 0.65, 0.25, "y", k:lit({ 60, 100, 140 }, "ceramic"))
		end,
	})

	-- 키친 트롤리 -----------------------------------------------------------------------------------
	D.item({
		id = "kt_trolley", cat = "kitchen", name = "3단 키친 트롤리", price = 69000, decor = 2, style = "natural", place = "floor",
		size = { 1.9, 3.0, 1.3 }, tags = { "트롤리", "수납", "선반" },
		slots = { S("metal", "프레임", "white", { "metal", "plastic", "wood" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:cyl("Post", H - 0.3, 0.08, sx * (W / 2 - 0.06), 0.3 + (H - 0.3) / 2, sz * (Dp / 2 - 0.06), "y", "metal")
					k:ball("Caster", 0.25, sx * (W / 2 - 0.1), 0.13, sz * (Dp / 2 - 0.1), k:lit({ 40, 40, 44 }, "rubber"))
				end
			end
			for i = 0, 2 do
				local y = 0.5 + i * 1.1
				k:box("Basket", W - 0.05, 0.5, Dp - 0.05, 0, y + 0.25, 0, k:sh("metal", 0.96), { solid = i == 0, top = i == 2 })
				k:box("BasketIn", W - 0.2, 0.4, Dp - 0.2, 0, y + 0.3, 0, k:sh("metal", 0.8))
			end
			k:ball("Lemon", 0.3, -0.4, 1.95, 0, k:lit({ 246, 214, 60 }))
			k:ball("Onion", 0.32, 0.2, 1.97, 0.1, k:lit({ 200, 140, 90 }))
			k:cyl("Spray", 0.5, 0.2, 0.5, 3.0, 0, "y", k:lit({ 120, 200, 160 }))
		end,
	})
end
