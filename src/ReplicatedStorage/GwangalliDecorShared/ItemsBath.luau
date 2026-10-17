--!strict
-- GwangalliDecorShared/ItemsBath: 욕실 — 욕조 · 세면대 · 욕실 거울 · 수건걸이 · 선반 · 세탁기 · 발매트.
-- Item frame: origin = bottom centre, front = -Z, back = +Z (wall pieces: back face at z = D/2).

return function(D: any)
	local S = D.slot
	local CER = { "ceramic", "gloss", "marble" }
	local MET = { "metal", "brushed" }
	local WOOD = { "wood", "planks" }

	-- 프리스탠딩 욕조 -------------------------------------------------------------------------------
	D.item({
		id = "bt_bathtub", cat = "bath", name = "프리스탠딩 욕조", price = 1900000, decor = 8, style = "luxury", place = "floor",
		size = { 5.4, 3.2, 2.7 }, tags = { "욕조", "반신욕", "호텔" },
		slots = { S("shell", "욕조", "white", CER), S("feet", "다리 · 수전", "brass", MET) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:ball("Foot", 0.32, sx * (W / 2 - 0.7), 0.16, sz * (Dp / 2 - 0.45), "feet")
				end
			end
			k:box("Tub", W - 0.4, 1.7, Dp - 0.2, 0, 1.15, 0, "shell", { solid = true })
			for _, sx in { -1, 1 } do
				k:cyl("TubEnd", Dp - 0.2, 1.7, sx * (W / 2 - 0.45), 1.15, 0, "z", "shell", { rz = 90 })
				k:box("Rim", 0.3, 0.12, Dp, sx * (W / 2 - 0.3), 2.04, 0, k:sh("shell", 1.02))
			end
			k:box("Rim", W - 0.6, 0.12, 0.25, 0, 2.04, -Dp / 2 + 0.12, k:sh("shell", 1.02))
			k:box("Rim", W - 0.6, 0.12, 0.25, 0, 2.04, Dp / 2 - 0.12, k:sh("shell", 1.02))
			k:box("Water", W - 1.0, 0.05, Dp - 0.6, 0, 1.78, 0, k:lit({ 150, 210, 230 }, "glass"), { t = 0.35, rf = 0.2 })
			k:box("Foam", 1.6, 0.12, 1.1, 0.8, 1.84, 0.1, k:lit({ 250, 250, 252 }, "fabric"))
			-- floor-standing tap
			k:cyl("TapPost", 2.9, 0.16, W / 2 + 0.05, 1.45, 0.7, "y", "feet")
			k:cyl("TapArm", 0.9, 0.12, W / 2 - 0.35, 2.85, 0.7, "x", "feet")
			k:box("Tray", 2.0, 0.08, 0.6, -0.6, 2.12, 0, k:lit({ 160, 116, 76 }, "wood"))
			k:cyl("Candle", 0.24, 0.2, -1.3, 2.28, 0, "y", k:lit({ 246, 240, 226 }))
			k:box("Towel", 0.9, 0.18, 0.5, -0.2, 2.25, 0, k:lit({ 222, 210, 188 }, "fabric"))
			k:bed(0, 1.55, 0, 90)
		end,
	})

	-- 세면대 하부장 ---------------------------------------------------------------------------------
	D.item({
		id = "bt_vanity", cat = "bath", name = "원목 세면대 하부장 (도기 볼)", price = 680000, decor = 5, style = "natural", place = "floor",
		size = { 3.4, 3.4, 1.8 }, tags = { "세면대", "하부장", "욕실장" },
		uses = { open = "수납장 열기", close = "수납장 닫기" },
		slots = { S("wood", "하부장", "oak", WOOD), S("basin", "세면볼", "white", CER), S("tap", "수전", "matteblack", MET) },
		build = function(k, W, H, Dp)
			k:box("Cabinet", W, 2.3, Dp - 0.1, 0, 1.35, 0.05, "wood", { solid = true })
			k:box("Kick", W - 0.2, 0.2, Dp - 0.3, 0, 0.1, 0.1, k:sh("wood", 0.6))
			k:box("Top", W + 0.05, 0.12, Dp, 0, 2.56, 0, k:lit({ 236, 236, 232 }, "marble"), { solid = true, top = true })
			local doors = {}
			for _, sx in { -1, 1 } do
				local d = k:box("Door", W / 2 - 0.06, 2.0, 0.08, sx * W / 4, 1.38, -Dp / 2 + 0.04, k:sh("wood", 1.05))
				local h = k:box("Handle", 0.06, 0.6, 0.08, sx * 0.14, 1.9, -Dp / 2 - 0.04, "tap")
				k:hinge({ d, h }, sx * W / 2, 0, -Dp / 2, "y", -sx * 100)
				table.insert(doors, d)
			end
			k:cyl("Basin", 0.5, 1.5, 0, 2.87, 0.0, "y", "basin")
			k:cyl("BasinIn", 0.06, 1.3, 0, 3.1, 0.0, "y", k:sh("basin", 0.92))
			k:cyl("TapBody", 0.6, 0.12, 0, 2.92, Dp / 2 - 0.25, "y", "tap")
			k:cyl("Spout", 0.55, 0.08, 0, 3.2, Dp / 2 - 0.5, "z", "tap")
			k:box("Soap", 0.2, 0.4, 0.2, W / 2 - 0.4, 2.82, 0.2, k:lit({ 120, 160, 140 }, "glass"), { t = 0.2 })
			k:box("Cup", 0.18, 0.3, 0.18, W / 2 - 0.75, 2.77, 0.3, k:lit({ 246, 246, 244 }, "ceramic"))
		end,
	})

	-- LED 욕실 거울 --------------------------------------------------------------------------------
	D.item({
		id = "bt_mirror_led", cat = "bath", name = "라운드 LED 욕실 거울", price = 290000, decor = 4, style = "modern", place = "wall",
		size = { 2.6, 2.6, 0.25 }, tags = { "거울", "LED", "욕실" }, light = "cool",
		slots = { S("frame", "테두리", "matteblack", MET) },
		build = function(k, W, H, Dp)
			k:cyl("Back", 0.1, W, 0, H / 2, Dp / 2 - 0.05, "z", "frame", { solid = true })
			local ring = k:cyl("LEDRing", 0.06, W - 0.05, 0, H / 2, Dp / 2 - 0.12, "z", "light", { glow = true })
			k:cyl("Mirror", 0.04, W - 0.25, 0, H / 2, Dp / 2 - 0.17, "z", k:lit({ 210, 220, 226 }, "glass"), { t = 0.05, rf = 0.6 })
			k:light(ring, 8, 0.6)
		end,
	})

	-- 수건 사다리 ------------------------------------------------------------------------------------
	D.item({
		id = "bt_towel_ladder", cat = "bath", name = "원목 수건 사다리", price = 69000, decor = 2, style = "natural", place = "floor",
		size = { 1.7, 5.0, 1.3 }, tags = { "수건", "사다리", "행거" },
		slots = { S("wood", "프레임", "birch", WOOD), S("towel", "수건", "sage", { "fabric" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Rail", 0.14, 5.0, 0.14, sx * (W / 2 - 0.1), 2.45, 0, "wood", { rx = -12, solid = true })
			end
			for i = 0, 4 do
				local y = 0.6 + i * 0.95
				local z = -0.02 + (y - 2.45) * 0.21
				k:cyl("Rung", W - 0.2, 0.1, 0, y, z, "x", "wood")
				if i == 2 or i == 3 then
					k:box("Towel", W - 0.45, 0.9, 0.06, 0, y - 0.42, z - 0.08, if i == 2 then "towel" else k:lit({ 246, 244, 238 }, "fabric"), { rx = -4 })
				end
			end
		end,
	})

	-- 열선 수건걸이 ---------------------------------------------------------------------------------
	D.item({
		id = "bt_towel_rail", cat = "bath", name = "열선 수건걸이", price = 180000, decor = 3, style = "modern", place = "wall",
		size = { 1.8, 3.0, 0.45 }, tags = { "수건걸이", "라디에이터" },
		slots = { S("metal", "프레임", "chrome", MET), S("towel", "수건", "white", { "fabric" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:cyl("Post", H, 0.14, sx * (W / 2 - 0.1), H / 2, Dp / 2 - 0.2, "y", "metal", { solid = true })
				k:box("Mount", 0.1, 0.1, 0.2, sx * (W / 2 - 0.1), H - 0.3, Dp / 2 - 0.1, "metal")
			end
			for i = 0, 7 do
				k:cyl("Bar", W - 0.2, 0.07, 0, 0.3 + i * 0.36, Dp / 2 - 0.2, "x", "metal")
			end
			k:box("Towel", W - 0.5, 1.2, 0.08, 0, 1.9, Dp / 2 - 0.32, "towel")
			k:box("TowelFold", W - 0.5, 0.12, 0.2, 0, 2.5, Dp / 2 - 0.26, "towel")
		end,
	})

	-- 욕실 벽 선반 ----------------------------------------------------------------------------------
	D.item({
		id = "bt_wall_shelf", cat = "bath", name = "욕실 2단 유리 선반", price = 59000, decor = 2, style = "modern", place = "wall",
		size = { 2.0, 1.6, 0.6 }, tags = { "선반", "욕실", "수납" },
		slots = { S("metal", "브래킷", "chrome", MET) },
		build = function(k, W, H, Dp)
			for i = 0, 1 do
				local y = 0.1 + i * 1.1
				k:box("Glass", W, 0.06, Dp - 0.08, 0, y, -0.04, k:lit({ 210, 230, 236 }, "glass"), { t = 0.4, top = true, solid = true })
				k:box("Rail", W, 0.06, 0.06, 0, y + 0.1, -Dp / 2 + 0.07, "metal")
				for _, sx in { -1, 1 } do
					k:box("Bracket", 0.06, 0.3, Dp - 0.05, sx * (W / 2 - 0.12), y - 0.1, 0, "metal")
				end
			end
			local cols = { { 120, 180, 210 }, { 246, 246, 244 }, { 230, 150, 160 }, { 180, 220, 190 } }
			for i = 0, 3 do
				local h = 0.35 + (i % 2) * 0.15
				k:cyl("Bottle", h, 0.2, -W / 2 + 0.35 + i * 0.42, 0.13 + h / 2, -0.05, "y", k:lit(cols[i + 1], "gloss"))
				k:cyl("Pump", 0.1, 0.06, -W / 2 + 0.35 + i * 0.42, 0.18 + h, -0.05, "y", k:lit({ 40, 40, 44 }))
			end
			k:box("Basket", 0.7, 0.3, 0.38, 0.4, 1.36, -0.05, k:lit({ 200, 170, 120 }, "rattan"))
		end,
	})

	-- 욕실 용품 트레이 ------------------------------------------------------------------------------
	D.item({
		id = "bt_toiletries", cat = "bath", name = "욕실 용품 트레이 세트", price = 39000, decor = 1, style = "cozy", place = "surface",
		size = { 1.4, 0.8, 0.7 }, tags = { "소품", "샴푸", "디퓨저" },
		slots = { S("tray", "트레이", "travertine", { "marble", "wood", "ceramic" }) },
		build = function(k, W, H, Dp)
			k:box("Tray", W, 0.08, Dp, 0, 0.04, 0, "tray", { solid = true, top = true })
			k:cyl("Bottle", 0.55, 0.22, -0.45, 0.36, 0, "y", k:lit({ 96, 70, 52 }, "glass"), { t = 0.15 })
			k:cyl("Pump", 0.12, 0.08, -0.45, 0.7, 0, "y", k:lit({ 30, 30, 32 }))
			k:cyl("Diffuser", 0.4, 0.26, 0.1, 0.28, 0, "y", k:lit({ 230, 220, 200 }, "glass"), { t = 0.2 })
			for i = -1, 1 do
				k:cyl("Reed", 0.6, 0.02, 0.1 + i * 0.04, 0.72, 0, "y", k:lit({ 60, 44, 30 }), { rz = i * 10 })
			end
			k:box("Soap", 0.3, 0.12, 0.2, 0.48, 0.14, 0, k:lit({ 240, 200, 210 }, "plastic"))
		end,
	})

	-- 규조토 발매트 ---------------------------------------------------------------------------------
	D.item({
		id = "bt_bathmat", cat = "bath", name = "규조토 발매트", price = 29000, decor = 1, style = "natural", place = "rug",
		size = { 2.6, 0.1, 1.6 }, tags = { "발매트", "러그", "욕실" },
		slots = { S("mat", "매트", "greige", { "concrete", "slate", "fabric" }) },
		build = function(k, W, H, Dp)
			k:box("Mat", W, 0.08, Dp, 0, 0.04, 0, "mat", { top = true })
			for i = -3, 3 do
				k:box("Groove", 0.04, 0.02, Dp - 0.3, i * 0.32, 0.085, 0, k:sh("mat", 0.85))
			end
		end,
	})

	-- 드럼 세탁기 + 건조기 -------------------------------------------------------------------------
	D.item({
		id = "bt_laundry", cat = "bath", name = "드럼 세탁기 + 건조기 (직렬)", price = 2600000, decor = 3, style = "modern", place = "floor",
		size = { 2.4, 5.8, 2.4 }, tags = { "세탁기", "건조기", "가전", "빨래" },
		uses = { open = "문 열기", close = "문 닫기" },
		slots = { S("body", "본체", "white", { "plastic", "gloss", "brushed" }), S("door", "도어", "charcoal", { "glass", "gloss" }) },
		build = function(k, W, H, Dp)
			for i = 0, 1 do
				local y0 = i * 2.95
				k:box("Body", W, 2.85, Dp, 0, y0 + 1.425, 0, "body", { solid = true, top = i == 1 })
				k:box("Panel", W - 0.1, 0.45, 0.06, 0, y0 + 2.55, -Dp / 2 - 0.02, k:sh("body", 0.92))
				k:box("Display", 0.6, 0.2, 0.03, 0.5, y0 + 2.55, -Dp / 2 - 0.06, k:lit({ 90, 200, 255 }, "neon"))
				k:cyl("Dial", 0.08, 0.32, -0.6, y0 + 2.55, -Dp / 2 - 0.08, "z", k:lit({ 200, 202, 206 }, "metal"))
				local ring = k:cyl("DoorRing", 0.12, 1.55, 0, y0 + 1.25, -Dp / 2 - 0.05, "z", k:sh("door", 1.2, "gloss"))
				local glass = k:cyl("DoorGlass", 0.08, 1.2, 0, y0 + 1.25, -Dp / 2 - 0.08, "z", "door", { t = 0.25 })
				k:hinge({ ring, glass }, -0.78, y0 + 1.25, -Dp / 2 - 0.05, "y", 95)
				k:cyl("Drum", 0.05, 1.1, 0, y0 + 1.25, -Dp / 2 + 0.05, "z", k:lit({ 190, 194, 200 }, "metal"))
			end
			k:box("Clothes", 0.9, 0.35, 0.9, 0, 1.0, -0.4, k:lit({ 120, 150, 200 }, "fabric"))
		end,
	})

	-- 라탄 빨래 바구니 ------------------------------------------------------------------------------
	D.item({
		id = "bt_hamper", cat = "bath", name = "라탄 빨래 바구니", price = 49000, decor = 2, style = "natural", place = "floor",
		size = { 1.5, 2.3, 1.5 }, tags = { "바구니", "빨래", "라탄" },
		slots = { S("rattan", "바구니", "teak", { "rattan", "fabric" }) },
		build = function(k, W, H, Dp)
			k:cyl("Basket", 1.9, 1.4, 0, 0.95, 0, "y", "rattan", { solid = true })
			for i = 0, 4 do
				k:cyl("Weave", 0.06, 1.44, 0, 0.25 + i * 0.38, 0, "y", k:sh("rattan", 0.78))
			end
			k:cyl("Lid", 0.12, 1.5, 0, 1.96, 0, "y", k:sh("rattan", 0.9), { top = true })
			k:box("Handle", 0.3, 0.08, 0.08, 0, 2.07, 0, k:sh("rattan", 0.7))
			k:box("Shirt", 0.9, 0.08, 0.6, 0.3, 2.06, 0.25, k:lit({ 236, 240, 246 }, "fabric"), { rz = -15, ry = 20 })
		end,
	})
end
