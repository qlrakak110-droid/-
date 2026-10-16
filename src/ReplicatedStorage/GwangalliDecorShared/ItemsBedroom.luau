--!strict
-- GwangalliDecorShared/ItemsBedroom: 침실 — 침대 (눕기) · 협탁 · 서랍장 · 화장대 · 행거 · 요·이불 · 전신 거울.

return function(D: any)
	local S = D.slot
	local BEDDING = { "fabric", "velvet" }
	local WOODM = { "wood", "planks", "gloss", "plastic" }

	local WHITE_SHEET = { 246, 246, 244 }

	-- mattress + duvet + pillows on top of a base whose top is at y (bed width W, length L, headboard at +Z)
	local function bedding(k: any, W: number, L: number, y: number, duvet: any, pillowN: number)
		k:box("Mattress", W - 0.3, 0.75, L - 0.45, 0, y + 0.375, -0.12, k:lit(WHITE_SHEET, "fabric"), { solid = true, top = true })
		k:box("Duvet", W - 0.2, 0.24, (L - 0.45) * 0.68, 0, y + 0.82, -L / 2 + 0.12 + (L - 0.45) * 0.34, duvet)
		k:box("DuvetFold", W - 0.18, 0.28, 0.4, 0, y + 0.86, -L / 2 + 0.12 + (L - 0.45) * 0.68 - 0.1, k:shp(duvet, 1.1))
		for _, sx in { -1, 1 } do
			k:box("DuvetSide", 0.12, 0.62, (L - 0.45) * 0.68, sx * (W / 2 - 0.08), y + 0.5, -L / 2 + 0.12 + (L - 0.45) * 0.34, duvet)
		end
		local pw = (W - 0.6) / pillowN
		for i = 1, pillowN do
			local x = -W / 2 + 0.3 + pw * (i - 0.5)
			k:box("Pillow", pw - 0.12, 0.38, 1.0, x, y + 0.92, L / 2 - 0.95, k:lit({ 250, 250, 252 }, "fabric"), { rx = -14 })
		end
		k:bed(0, y + 0.95, -0.2)
	end

	-- 원목 퀸 침대 ----------------------------------------------------------------------------------
	D.item({
		id = "bd_wood_queen", cat = "bedroom", name = "원목 퀸 침대", price = 1290000, decor = 7, style = "natural", place = "floor",
		size = { 5.4, 3.4, 7.0 }, tags = { "침대", "퀸", "원목", "bed" },
		slots = { S("wood", "원목", "oak", WOODM), S("duvet", "이불", "sage", BEDDING) },
		build = function(k, W, H, Dp)
			k:box("Frame", W, 0.6, Dp - 0.3, 0, 0.6, -0.15, "wood", { solid = true })
			k:legs(W, Dp - 0.3, 0.3, 0.25, 0.3, k:sh("wood", 0.9), false)
			for i = 0, 5 do
				k:box("Slat", W - 0.4, 0.05, 0.3, 0, 0.92, -Dp / 2 + 0.8 + i * 1.0, k:sh("wood", 1.05))
			end
			k:box("Headboard", W + 0.1, H - 0.3, 0.3, 0, 0.3 + (H - 0.3) / 2, Dp / 2 - 0.15, "wood", { solid = true })
			for i = -3, 3 do
				k:box("Groove", 0.04, H - 0.8, 0.02, i * (W / 7), 0.55 + (H - 0.8) / 2, Dp / 2 - 0.31, k:sh("wood", 0.78))
			end
			k:box("HeadCap", W + 0.2, 0.12, 0.42, 0, H - 0.06, Dp / 2 - 0.15, k:sh("wood", 1.08))
			bedding(k, W - 0.2, Dp - 0.6, 0.9, "duvet", 2)
			k:box("Throw", W - 0.3, 0.06, 1.0, 0, 1.92, -Dp / 2 + 1.0, k:lit({ 222, 210, 188 }, "fabric"))
		end,
	})

	-- 캐노피 침대 -----------------------------------------------------------------------------------
	D.item({
		id = "bd_canopy", cat = "bedroom", name = "캐노피 침대 (호텔 스위트)", price = 3900000, decor = 12, style = "luxury", place = "floor",
		size = { 5.8, 7.4, 7.2 }, tags = { "침대", "캐노피", "호텔", "킹" },
		slots = { S("frame", "프레임", "gold", { "metal", "brushed", "wood" }), S("drape", "커튼", "ivory", { "fabric", "velvet" }), S("duvet", "이불", "white", BEDDING), S("head", "헤드보드", "greige", { "velvet", "fabric", "leather" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W - 0.3, 0.9, Dp - 0.5, 0, 0.45, -0.1, k:sh("head", 0.9), { solid = true })
			k:box("Headboard", W - 0.4, 3.1, 0.45, 0, 0.9 + 1.55, Dp / 2 - 0.35, "head", { solid = true })
			for i = 0, 4 do
				k:box("Channel", 0.05, 2.8, 0.04, -W / 2 + 0.8 + i * (W - 1.6) / 4, 2.45, Dp / 2 - 0.59, k:sh("head", 0.8))
			end
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:cyl("Post", H, 0.18, sx * (W / 2 - 0.12), H / 2, sz * (Dp / 2 - 0.12), "y", "frame")
					k:ball("Finial", 0.3, sx * (W / 2 - 0.12), H + 0.05, sz * (Dp / 2 - 0.12), "frame")
				end
				k:box("Rail", 0.1, 0.1, Dp - 0.2, sx * (W / 2 - 0.12), H - 0.1, 0, "frame")
				k:box("Drape", 0.08, H - 0.6, 1.2, sx * (W / 2 - 0.12), H / 2 + 0.2, -Dp / 2 + 0.7, "drape", { t = 0.25 })
				k:box("Drape", 0.08, H - 0.6, 1.2, sx * (W / 2 - 0.12), H / 2 + 0.2, Dp / 2 - 0.9, "drape", { t = 0.25 })
				k:box("Tie", 0.14, 0.15, 0.3, sx * (W / 2 - 0.12), 2.6, -Dp / 2 + 0.7, "frame")
			end
			k:box("Rail", W - 0.2, 0.1, 0.1, 0, H - 0.1, -Dp / 2 + 0.12, "frame")
			k:box("Rail", W - 0.2, 0.1, 0.1, 0, H - 0.1, Dp / 2 - 0.12, "frame")
			k:box("Canopy", W - 0.3, 0.06, Dp - 0.3, 0, H - 0.1, 0, "drape", { t = 0.4 })
			bedding(k, W - 0.6, Dp - 0.9, 0.9, "duvet", 3)
			k:box("Runner", W - 0.5, 0.08, 1.2, 0, 1.92, -Dp / 2 + 1.4, k:sh("head", 0.75, "velvet"))
		end,
	})

	-- 저상형 LED 침대 -------------------------------------------------------------------------------
	D.item({
		id = "bd_platform_led", cat = "bedroom", name = "저상형 플랫폼 침대 (LED)", price = 980000, decor = 6, style = "modern", place = "floor",
		size = { 7.4, 2.6, 7.0 }, tags = { "침대", "저상형", "LED" }, light = "warm",
		slots = { S("body", "프레임", "charcoal", { "fabric", "leather", "wood", "gloss" }), S("duvet", "이불", "lightgrey", BEDDING) },
		build = function(k, W0, H, Dp)
			local W = W0 - 2.2
			k:box("Plinth", W - 0.6, 0.12, Dp - 0.8, 0, 0.06, -0.1, k:lit({ 24, 24, 26 }))
			local led = k:box("LEDStrip", W - 0.5, 0.05, Dp - 0.7, 0, 0.1, -0.1, "light", { glow = true })
			k:light(led, 7, 0.6)
			k:box("Platform", W, 0.45, Dp - 0.25, 0, 0.12 + 0.225, -0.12, "body", { solid = true })
			k:box("Headboard", W, H - 0.12, 0.35, 0, 0.12 + (H - 0.12) / 2, Dp / 2 - 0.18, "body", { solid = true })
			k:box("HeadPanel", W - 0.6, H - 0.7, 0.06, 0, 0.6 + (H - 0.7) / 2, Dp / 2 - 0.38, k:sh("body", 1.15))
			for _, sx in { -1, 1 } do
				k:box("Shelf", 1.1, 0.12, 1.2, sx * (W / 2 + 0.55), 1.4, Dp / 2 - 0.8, "body", { top = true })
			end
			bedding(k, W - 0.5, Dp - 0.6, 0.57, "duvet", 2)
		end,
	})

	-- 철제 싱글 침대 --------------------------------------------------------------------------------
	D.item({
		id = "bd_single_iron", cat = "bedroom", name = "철제 싱글 침대", price = 260000, decor = 3, style = "trendy", place = "floor",
		size = { 3.4, 3.2, 6.6 }, tags = { "침대", "싱글", "철제" },
		slots = { S("metal", "프레임", "matteblack", { "metal", "brushed", "plastic" }), S("duvet", "이불", "blush", BEDDING) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:cyl("Post", H, 0.14, sx * (W / 2 - 0.07), H / 2, Dp / 2 - 0.07, "y", "metal", { solid = true })
				k:cyl("Post", 1.9, 0.14, sx * (W / 2 - 0.07), 0.95, -Dp / 2 + 0.07, "y", "metal")
				k:box("SideRail", 0.1, 0.18, Dp - 0.1, sx * (W / 2 - 0.07), 0.75, 0, "metal", { solid = true })
			end
			for _, z in { Dp / 2 - 0.07, -Dp / 2 + 0.07 } do
				local top = if z > 0 then H - 0.1 else 1.85
				k:cyl("Bar", W - 0.1, 0.1, 0, top, z, "x", "metal")
				k:cyl("Bar", W - 0.1, 0.1, 0, 0.9, z, "x", "metal")
				for i = 1, 6 do
					k:cyl("Spindle", top - 0.9, 0.05, -W / 2 + i * W / 7, 0.9 + (top - 0.9) / 2, z, "y", "metal")
				end
			end
			k:box("Deck", W - 0.2, 0.08, Dp - 0.2, 0, 0.82, 0, k:lit({ 120, 90, 60 }, "planks"))
			bedding(k, W - 0.1, Dp - 0.2, 0.86, "duvet", 1)
		end,
	})

	-- 2층 침대 --------------------------------------------------------------------------------------
	D.item({
		id = "bd_bunk", cat = "bedroom", name = "원목 2층 침대", price = 640000, decor = 4, style = "natural", place = "floor",
		size = { 3.6, 6.8, 6.8 }, tags = { "침대", "2층", "벙커" },
		slots = { S("wood", "원목", "birch", WOODM), S("duvet", "이불 (아래)", "navy", BEDDING), S("duvet2", "이불 (위)", "mustard", BEDDING) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:box("Post", 0.3, H, 0.3, sx * (W / 2 - 0.15), H / 2, sz * (Dp / 2 - 0.15), "wood", { solid = true })
				end
			end
			for _, y in { 0.7, 3.9 } do
				for _, sx in { -1, 1 } do
					k:box("Rail", 0.16, 0.35, Dp - 0.6, sx * (W / 2 - 0.15), y, 0, "wood", { solid = true })
				end
				k:box("Rail", W - 0.6, 0.35, 0.16, 0, y, Dp / 2 - 0.15, "wood")
				k:box("Rail", W - 0.6, 0.35, 0.16, 0, y, -Dp / 2 + 0.15, "wood")
				k:box("Deck", W - 0.5, 0.08, Dp - 0.5, 0, y + 0.1, 0, k:sh("wood", 0.9), { solid = true })
			end
			bedding(k, W - 0.4, Dp - 0.5, 0.82, "duvet", 1)
			bedding(k, W - 0.4, Dp - 0.5, 4.02, "duvet2", 1)
			k:box("GuardRail", 0.14, 0.14, Dp - 2.0, W / 2 - 0.15, 5.6, 0.6, "wood")
			k:box("GuardRail", 0.14, 0.14, Dp - 0.6, -W / 2 + 0.15, 5.6, 0, "wood")
			for i = 1, 5 do
				k:box("Rung", 0.1, 0.1, 1.1, W / 2 - 0.15, 0.6 + i * 0.95, -Dp / 2 + 1.0, "wood")
			end
			k:box("LadderSide", 0.12, 5.2, 0.12, W / 2 - 0.15, 2.6, -Dp / 2 + 0.45, "wood")
		end,
	})

	-- 오크 협탁 -------------------------------------------------------------------------------------
	D.item({
		id = "bd_nightstand_oak", cat = "bedroom", name = "오크 협탁 (2단 서랍)", price = 159000, decor = 2, style = "natural", place = "floor",
		size = { 1.7, 1.9, 1.5 }, tags = { "협탁", "서랍", "침대 옆" },
		slots = { S("wood", "원목", "oak", WOODM), S("knob", "손잡이", "brass", { "metal", "wood", "plastic" }) },
		build = function(k, W, H, Dp)
			k:splayLegs(W - 0.2, Dp - 0.2, 0.45, 0.12, 0.12, k:sh("wood", 0.9), 5)
			k:box("Body", W, H - 0.45, Dp, 0, 0.45 + (H - 0.45) / 2, 0, "wood", { solid = true })
			k:box("Top", W + 0.06, 0.07, Dp + 0.06, 0, H - 0.03, 0, k:sh("wood", 1.06), { top = true })
			for i = 0, 1 do
				local y = 0.5 + 0.33 + i * 0.66
				k:box("Drawer", W - 0.12, 0.6, 0.05, 0, y, -Dp / 2 - 0.02, k:sh("wood", 1.03))
				k:ball("Knob", 0.12, 0, y, -Dp / 2 - 0.08, "knob")
			end
		end,
	})

	-- 하이글로시 협탁 -------------------------------------------------------------------------------
	D.item({
		id = "bd_nightstand_gloss", cat = "bedroom", name = "하이글로시 무드등 협탁", price = 189000, decor = 3, style = "modern", place = "floor",
		size = { 1.8, 1.7, 1.4 }, tags = { "협탁", "무드등", "LED" }, light = "warm",
		slots = { S("body", "몸체", "white", { "gloss", "plastic", "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H - 0.1, Dp, 0, 0.1 + (H - 0.1) / 2, 0, "body", { solid = true, top = true })
			local glow = k:box("UnderGlow", W - 0.2, 0.04, Dp - 0.2, 0, 0.06, 0, "light", { glow = true })
			k:light(glow, 5, 0.4)
			k:box("Drawer", W - 0.1, 0.65, 0.04, 0, 0.55, -Dp / 2 - 0.02, k:sh("body", 0.96))
			k:box("Niche", W - 0.2, 0.55, Dp - 0.2, 0, 1.2, -0.05, k:sh("body", 0.8))
			k:box("Grip", W - 0.3, 0.05, 0.06, 0, 0.86, -Dp / 2 - 0.04, k:lit({ 190, 192, 196 }, "metal"))
			k:cyl("Clock", 0.12, 0.6, 0.4, H + 0.06, 0, "y", k:lit({ 30, 30, 34 }))
		end,
	})

	-- 6단 서랍장 ------------------------------------------------------------------------------------
	D.item({
		id = "bd_dresser", cat = "bedroom", name = "6단 와이드 서랍장", price = 420000, decor = 4, style = "classic", place = "floor",
		size = { 4.4, 2.9, 1.6 }, tags = { "서랍장", "수납", "체스트" },
		slots = { S("wood", "몸체", "walnut", WOODM), S("knob", "손잡이", "brass", { "metal", "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Plinth", W - 0.2, 0.25, Dp - 0.2, 0, 0.125, 0, k:sh("wood", 0.8))
			k:box("Body", W, H - 0.25, Dp, 0, 0.25 + (H - 0.25) / 2, 0, "wood", { solid = true })
			k:box("Top", W + 0.1, 0.1, Dp + 0.08, 0, H + 0.02, 0, k:sh("wood", 1.08), { top = true })
			for row = 0, 2 do
				for col = -1, 1, 2 do
					local y = 0.35 + 0.42 + row * 0.84
					k:box("Drawer", W / 2 - 0.1, 0.76, 0.05, col * W / 4, y, -Dp / 2 - 0.02, k:sh("wood", 1.04))
					k:box("Pull", 0.6, 0.07, 0.08, col * W / 4, y + 0.1, -Dp / 2 - 0.08, "knob")
				end
			end
			k:box("Tray", 1.0, 0.04, 0.7, -1.2, H + 0.09, 0, k:lit({ 198, 158, 92 }, "metal"))
			k:cyl("Perfume", 0.35, 0.22, -1.4, H + 0.27, 0, "y", k:lit({ 236, 200, 170 }, "glass"))
			k:box("Frame", 0.9, 1.1, 0.08, 1.2, H + 0.62, 0.3, k:lit({ 36, 36, 40 }, "wood"), { rx = -10 })
		end,
	})

	-- 화장대 + 스툴 ---------------------------------------------------------------------------------
	D.item({
		id = "bd_vanity", cat = "bedroom", name = "화장대 + 조명 거울 + 스툴", price = 380000, decor = 5, style = "cozy", place = "floor",
		size = { 3.6, 5.4, 2.6 }, tags = { "화장대", "거울", "스툴" }, light = "neutral",
		slots = { S("body", "몸체", "white", { "gloss", "wood", "plastic" }), S("stool", "스툴", "blush", { "velvet", "fabric", "leather" }) },
		build = function(k, W, H, Dp)
			local tz = Dp / 2 - 0.75
			k:box("Top", W, 0.12, 1.5, 0, 2.5, tz, "body", { solid = true, top = true })
			k:box("Drawer", W - 0.2, 0.5, 1.4, 0, 2.18, tz, k:sh("body", 0.97))
			k:box("Pull", 0.8, 0.06, 0.06, 0, 2.18, tz - 0.74, k:lit({ 198, 158, 92 }, "metal"))
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:cyl("Leg", 1.93, 0.14, sx * (W / 2 - 0.15), 0.965, tz + sz * 0.6, "y", "body")
				end
			end
			k:box("Mirror", 2.4, 2.6, 0.06, 0, 2.56 + 1.4, Dp / 2 - 0.12, k:lit({ 200, 214, 222 }, "glass"), { rf = 0.5, t = 0 })
			k:box("MirrorFrame", 2.6, 2.8, 0.08, 0, 2.56 + 1.4, Dp / 2 - 0.06, "body")
			for i = 0, 4 do
				for _, sx in { -1, 1 } do
					local b = k:ball("Bulb", 0.22, sx * 1.25, 2.86 + i * 0.55, Dp / 2 - 0.2, "light", { glow = true })
					if i == 2 and sx == 1 then
						k:light(b, 7, 0.6)
					end
				end
			end
			k:cyl("Lotion", 0.4, 0.2, -1.2, 2.76, tz, "y", k:lit({ 250, 230, 230 }, "glass"))
			k:cyl("Lotion", 0.3, 0.18, -0.95, 2.71, tz + 0.1, "y", k:lit({ 214, 176, 64 }, "metal"))
			k:box("Brush", 0.5, 0.06, 0.08, 0.9, 2.59, tz - 0.2, k:lit({ 40, 40, 44 }))
			-- stool in front
			k:cyl("StoolSeat", 0.35, 1.3, 0, 1.45, -Dp / 2 + 0.75, "y", "stool", { solid = true })
			for i = 0, 3 do
				local a = i * math.pi / 2 + math.pi / 4
				k:cyl("StoolLeg", 1.3, 0.1, math.cos(a) * 0.45, 0.65, -Dp / 2 + 0.75 + math.sin(a) * 0.45, "y", k:lit({ 198, 158, 92 }, "metal"))
			end
			k:seat(0, 1.63, -Dp / 2 + 0.75, 180)
		end,
	})

	-- 침대 벤치 -------------------------------------------------------------------------------------
	D.item({
		id = "bd_bench", cat = "bedroom", name = "베드 엔드 벤치", price = 290000, decor = 3, style = "luxury", place = "floor",
		size = { 4.4, 1.5, 1.4 }, tags = { "벤치", "침대 끝" },
		slots = { S("pad", "쿠션", "greige", { "velvet", "leather", "fabric" }), S("legs", "다리", "gold", { "metal", "wood" }) },
		build = function(k, W, H, Dp)
			k:box("Pad", W, 0.5, Dp, 0, 1.2, 0, "pad", { solid = true, top = true })
			for i = 0, 5 do
				k:ball("Tuft", 0.08, -W / 2 + 0.45 + i * (W - 0.9) / 5, 1.46, 0, k:sh("pad", 0.7))
			end
			for _, sx in { -1, 1 } do
				k:box("Leg", 0.08, 0.95, 0.08, sx * (W / 2 - 0.2), 0.48, -Dp / 2 + 0.15, "legs")
				k:box("Leg", 0.08, 0.95, 0.08, sx * (W / 2 - 0.2), 0.48, Dp / 2 - 0.15, "legs")
				k:box("Brace", 0.08, 0.08, Dp - 0.3, sx * (W / 2 - 0.2), 0.12, 0, "legs")
			end
			k:seat(-1, 1.45, 0)
			k:seat(1, 1.45, 0)
		end,
	})

	-- 요·이불 세트 ----------------------------------------------------------------------------------
	D.item({
		id = "bd_yo", cat = "bedroom", name = "요·이불 세트 (바닥 잠자리)", price = 160000, decor = 2, style = "cozy", place = "floor",
		size = { 3.6, 0.8, 6.4 }, tags = { "이불", "요", "한식", "바닥" },
		slots = { S("yo", "요", "white", BEDDING), S("quilt", "이불", "rose", BEDDING) },
		build = function(k, W, H, Dp)
			k:box("Yo", W, 0.32, Dp, 0, 0.16, 0, "yo", { solid = true, top = true })
			k:box("Quilt", W + 0.1, 0.22, Dp * 0.62, 0, 0.43, -Dp / 2 + Dp * 0.31, "quilt")
			k:box("QuiltFold", W + 0.12, 0.26, 0.45, 0, 0.47, -Dp / 2 + Dp * 0.62 - 0.1, k:sh("quilt", 1.1))
			for i = 0, 3 do
				k:box("Quilting", W + 0.11, 0.03, 0.05, 0, 0.55, -Dp / 2 + 0.5 + i * 0.85, k:sh("quilt", 0.85))
			end
			k:box("Pillow", 1.8, 0.4, 0.9, 0, 0.52, Dp / 2 - 0.7, k:lit({ 236, 226, 200 }, "fabric"))
			k:bed(0, 0.42, 0)
		end,
	})

	-- 전신 거울 -------------------------------------------------------------------------------------
	D.item({
		id = "bd_mirror_stand", cat = "bedroom", name = "아치형 전신 거울", price = 129000, decor = 3, style = "trendy", place = "floor",
		size = { 2.0, 5.6, 0.9 }, tags = { "거울", "전신", "아치" },
		slots = { S("frame", "프레임", "matteblack", { "metal", "wood", "gloss" }) },
		build = function(k, W, H, Dp)
			local tilt = -6
			local cf = CFrame.new(0, H / 2, 0.1) * CFrame.Angles(math.rad(tilt), 0, 0)
			k:boxAt("Mirror", W - 0.24, H - 1.0, 0.04, cf * CFrame.new(0, -0.35, -0.02), k:lit({ 205, 220, 228 }, "glass"), { rf = 0.6, t = 0 })
			k:boxAt("Frame", W, H - 0.9, 0.1, cf * CFrame.new(0, -0.4, 0.04), "frame", { solid = true })
			k:boxAt("Arch", W, 0.2, 0.1, cf * CFrame.new(0, H / 2 - 0.85, 0.04), "frame")
			local arch = k:cyl("ArchTop", 0.1, W, 0, 0, 0, "z", "frame")
			k.parts[arch].cf = cf * CFrame.new(0, H / 2 - 0.85, 0.04) * CFrame.Angles(0, math.rad(90), 0)
			local glass = k:cyl("ArchGlass", 0.05, W - 0.24, 0, 0, 0, "z", k:lit({ 205, 220, 228 }, "glass"), { rf = 0.6, t = 0 })
			k.parts[glass].cf = cf * CFrame.new(0, H / 2 - 0.85, -0.02) * CFrame.Angles(0, math.rad(90), 0)
			k:box("Stand", 0.08, H * 0.7, 0.08, 0, H * 0.35, Dp / 2 - 0.1, "frame", { rx = 18 })
		end,
	})

	-- 행거 ------------------------------------------------------------------------------------------
	D.item({
		id = "bd_hanger", cat = "bedroom", name = "철제 오픈 행거 + 옷", price = 99000, decor = 2, style = "trendy", place = "floor",
		size = { 4.0, 5.6, 1.6 }, tags = { "행거", "옷걸이", "옷" },
		slots = { S("metal", "프레임", "matteblack", { "metal", "brushed", "wood" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:cyl("Upright", H, 0.12, sx * (W / 2 - 0.08), H / 2, 0, "y", "metal", { solid = true })
				k:box("Foot", 0.12, 0.1, Dp, sx * (W / 2 - 0.08), 0.05, 0, "metal")
			end
			k:cyl("Rod", W, 0.1, 0, H - 0.1, 0, "x", "metal")
			k:box("Shelf", W - 0.2, 0.08, Dp - 0.3, 0, 0.5, 0, k:lit({ 200, 164, 118 }, "wood"), { top = true })
			local cols = { { 236, 232, 222 }, { 48, 62, 100 }, { 176, 124, 76 }, { 30, 30, 34 }, { 166, 184, 160 }, { 214, 52, 56 } }
			for i, c in cols do
				local x = -W / 2 + 0.45 + (i - 1) * (W - 0.9) / 5
				k:box("Hook", 0.04, 0.25, 0.04, x, H - 0.25, 0, k:lit({ 190, 192, 196 }, "metal"))
				local long = i % 2 == 0
				k:box("Cloth", 0.18, if long then 2.6 else 1.9, 1.2, x, H - 0.4 - (if long then 1.3 else 0.95), 0, k:lit(c, "fabric"))
				k:box("Shoulder", 0.2, 0.12, 1.25, x, H - 0.42, 0, k:lit(c, "fabric"))
			end
			k:box("Box", 0.9, 0.5, 0.8, -0.9, 0.79, 0, k:lit({ 190, 160, 110 }, "cardboard"))
			k:box("Shoes", 0.8, 0.3, 0.5, 0.8, 0.69, 0, k:lit({ 236, 236, 236 }, "rubber"))
		end,
	})
end
