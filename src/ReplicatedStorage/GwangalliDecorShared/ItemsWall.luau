--!strict
-- GwangalliDecorShared/ItemsWall: 벽장식 — 액자 · 거울 · 벽시계 · 커튼 · 블라인드 · 선반 · 마크라메 · 타공판.
-- Wall pieces: back face at z = D/2 (touches the wall), front = -Z. Curtains / blinds open and close.
-- The clock's hands (ClockHour / ClockMinute) are turned to the real time by the client.

return function(D: any)
	local S = D.slot
	local FRAME = { "wood", "metal", "gloss" }

	-- 광안대교 야경 액자 ---------------------------------------------------------------------------
	D.item({
		id = "wl_bridge_art", cat = "wall", name = "광안대교 야경 아트 액자", price = 120000, decor = 5, style = "modern", place = "wall",
		size = { 4.4, 2.8, 0.25 }, tags = { "액자", "그림", "광안대교", "야경" }, toggle = false,
		slots = { S("frame", "액자", "black", FRAME), S("sky", "하늘", { 20, 26, 66 }, { "plastic" }) },
		build = function(k, W, H, Dp)
			k:frame(W, H, Dp, 0, H / 2, Dp / 2, "frame")
			local z = Dp / 2 - 0.06
			k:box("Sky", W - 0.3, H - 0.3, 0.03, 0, H / 2, z, "sky", { solid = true })
			k:box("Glow", W - 0.3, 0.5, 0.03, 0, 0.55, z - 0.01, k:mx("sky", { 255, 120, 160 }, 0.35))
			k:box("Sea", W - 0.3, 0.55, 0.03, 0, 0.42, z - 0.02, k:mx("sky", { 10, 40, 80 }, 0.4))
			local deck = 0.95
			k:box("Deck", W - 0.3, 0.06, 0.02, 0, deck, z - 0.03, k:lit({ 61, 214, 245 }, "neon"), { glow = true })
			for _, tx in { -1.0, 1.0 } do
				k:box("Tower", 0.08, 1.3, 0.02, tx, deck + 0.6, z - 0.03, k:lit({ 220, 230, 255 }, "neon"), { glow = true })
				for i = 1, 4 do
					local dx = i * 0.22
					for _, sx in { -1, 1 } do
						k:box("Cable", 0.02, 0.6, 0.015, tx + sx * dx * 0.55, deck + 0.42, z - 0.035, k:lit({ 255, 79, 163 }, "neon"), { glow = true, rz = sx * (18 + i * 9) })
					end
				end
			end
			for i = 0, 9 do
				k:box("Reflect", 0.12, 0.02, 0.015, -1.8 + i * 0.4, 0.32 + (i % 3) * 0.06, z - 0.035, k:lit(if i % 2 == 0 then { 61, 214, 245 } else { 255, 79, 163 }, "neon"), { glow = true })
			end
			k:cyl("Moon", 0.03, 0.28, 1.5, H - 0.6, z - 0.02, "z", k:lit({ 255, 246, 220 }, "neon"), { glow = true })
		end,
	})

	-- 골드 앤틱 거울 -------------------------------------------------------------------------------
	D.item({
		id = "wl_mirror_gold", cat = "wall", name = "골드 아치 앤틱 거울", price = 340000, decor = 6, style = "luxury", place = "wall",
		size = { 2.6, 4.6, 0.3 }, tags = { "거울", "아치", "골드", "호텔" },
		slots = { S("frame", "프레임", "gold", { "metal", "brushed", "wood" }) },
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.12
			k:box("FrameSide", 0.2, H - 1.3, 0.24, -W / 2 + 0.1, (H - 1.3) / 2, z, "frame", { solid = true })
			k:box("FrameSide", 0.2, H - 1.3, 0.24, W / 2 - 0.1, (H - 1.3) / 2, z, "frame", { solid = true })
			k:box("FrameBottom", W, 0.2, 0.24, 0, 0.1, z, "frame")
			k:cyl("Arch", 0.24, W, 0, H - 1.3, z, "z", "frame")
			k:box("Mirror", W - 0.35, H - 1.45, 0.04, 0, (H - 1.3) / 2 + 0.05, Dp / 2 - 0.2, k:lit({ 210, 220, 226 }, "glass"), { t = 0.05, rf = 0.6 })
			k:cyl("MirrorArch", 0.04, W - 0.35, 0, H - 1.3, Dp / 2 - 0.2, "z", k:lit({ 210, 220, 226 }, "glass"), { t = 0.05, rf = 0.6 })
			k:box("Back", W - 0.2, H - 1.3, 0.04, 0, (H - 1.3) / 2, Dp / 2 - 0.02, k:sh("frame", 0.5))
			for i = 0, 4 do
				k:ball("Bead", 0.12, -W / 2 + 0.3 + i * (W - 0.6) / 4, 0.24, z - 0.12, "frame")
			end
		end,
	})

	-- 갤러리 월 ------------------------------------------------------------------------------------
	D.item({
		id = "wl_gallery", cat = "wall", name = "갤러리 월 액자 5종", price = 160000, decor = 6, style = "trendy", place = "wall",
		size = { 5.0, 3.4, 0.2 }, tags = { "액자", "갤러리", "포스터", "그림" },
		slots = { S("frame", "액자", "oak", FRAME), S("accent", "포인트 색", "terracotta", { "plastic" }) },
		build = function(k, W, H, Dp)
			local zb = Dp / 2
			local arts = {
				{ -1.65, 2.1, 1.5, 2.2 }, { -0.1, 2.5, 1.2, 1.4 }, { -0.1, 0.85, 1.2, 1.4 }, { 1.45, 2.2, 1.6, 1.2 }, { 1.45, 0.95, 1.0, 1.0 },
			}
			for i, a in arts do
				k:frame(a[3], a[4], Dp, a[1], a[2], zb, "frame", k:lit({ 246, 244, 238 }))
				local z = zb - 0.07
				if i == 1 then
					k:cyl("Sun", 0.03, 0.7, a[1], a[2] + 0.2, z, "z", "accent")
					k:box("Hill", 1.1, 0.4, 0.03, a[1], a[2] - 0.6, z, k:lit({ 120, 140, 100 }))
				elseif i == 2 then
					k:box("Line", 0.06, 0.9, 0.03, a[1] - 0.2, a[2], z, k:lit({ 30, 30, 34 }), { rz = 20 })
					k:cyl("Dot", 0.03, 0.3, a[1] + 0.25, a[2] + 0.2, z, "z", "accent")
				elseif i == 3 then
					k:box("Block", 0.4, 0.6, 0.03, a[1] - 0.2, a[2], z, k:lit({ 214, 162, 58 }))
					k:box("Block", 0.4, 0.4, 0.03, a[1] + 0.22, a[2] - 0.1, z, k:lit({ 48, 62, 100 }))
				elseif i == 4 then
					for j = 0, 2 do
						k:box("Wave", 1.2, 0.08, 0.03, a[1], a[2] - 0.3 + j * 0.25, z, k:lit({ 60, 120, 190 }), { rz = (j - 1) * 6 })
					end
				else
					k:box("Leaf", 0.5, 0.18, 0.03, a[1], a[2], z, k:lit({ 80, 130, 80 }), { rz = 40 })
				end
			end
		end,
	})

	-- 원목 벽시계 -----------------------------------------------------------------------------------
	D.item({
		id = "wl_clock", cat = "wall", name = "원목 벽시계 (실제 시간)", price = 58000, decor = 3, style = "natural", place = "wall",
		size = { 1.9, 1.9, 0.25 }, tags = { "시계", "벽시계", "원목" },
		slots = { S("wood", "몸체", "oak", { "wood", "metal", "gloss" }), S("hands", "시곗바늘", "black", { "metal" }) },
		build = function(k, W, H, Dp)
			local cy = H / 2
			k:cyl("Body", 0.18, W, 0, cy, Dp / 2 - 0.09, "z", "wood", { solid = true })
			k:cyl("Face", 0.02, W - 0.25, 0, cy, Dp / 2 - 0.19, "z", k:lit({ 246, 244, 238 }))
			for i = 0, 11 do
				local a = math.rad(i * 30)
				local r = (W - 0.45) / 2
				local big = i % 3 == 0
				k:box("Tick", 0.05, if big then 0.18 else 0.1, 0.02, math.sin(a) * r, cy + math.cos(a) * r, Dp / 2 - 0.21, "hands", { rz = -i * 30 })
			end
			k:box("ClockHour", 0.07, 0.45, 0.02, 0, cy + 0.2, Dp / 2 - 0.23, "hands")
			k:box("ClockMinute", 0.05, 0.68, 0.02, 0, cy + 0.32, Dp / 2 - 0.24, "hands")
			k:cyl("Pin", 0.06, 0.1, 0, cy, Dp / 2 - 0.25, "z", k:lit({ 214, 52, 56 }, "metal"))
		end,
	})

	-- 린넨 커튼 -------------------------------------------------------------------------------------
	D.item({
		id = "wl_curtain_linen", cat = "wall", name = "린넨 암막 커튼 (양쪽)", price = 140000, decor = 4, style = "natural", place = "wall",
		size = { 6.0, 6.6, 0.7 }, tags = { "커튼", "암막", "린넨", "창문" },
		uses = { open = "커튼 걷기", close = "커튼 치기" },
		slots = { S("fabric", "커튼", "oatmeal", { "fabric", "velvet" }), S("rod", "봉", "matteblack", { "metal", "brushed", "wood" }) },
		build = function(k, W, H, Dp)
			k:cyl("Rod", W, 0.1, 0, H - 0.15, Dp / 2 - 0.3, "x", "rod", { solid = true })
			for _, sx in { -1, 1 } do
				k:ball("Finial", 0.18, sx * W / 2, H - 0.15, Dp / 2 - 0.3, "rod")
				k:box("Bracket", 0.08, 0.08, 0.3, sx * (W / 2 - 0.3), H - 0.15, Dp / 2 - 0.15, "rod")
			end
			local n = 6
			local pw = (W / 2 - 0.1) / n
			for _, side in { -1, 1 } do
				for i = 0, n - 1 do
					local xc = side * (0.05 + pw * (i + 0.5))
					local zc = Dp / 2 - 0.3 + (if i % 2 == 0 then -0.06 else 0.06)
					local idx = k:box("Pleat", pw + 0.03, H - 0.35, 0.08, xc, (H - 0.35) / 2 + 0.05, zc, if i % 2 == 0 then "fabric" else k:sh("fabric", 0.9))
					-- open: packed at the side
					local xo = side * (W / 2 - 0.12 - (n - 1 - i) * 0.09)
					k:pose(idx, CFrame.new(xo, (H - 0.35) / 2 + 0.05, zc + (if i % 2 == 0 then -0.05 else 0.05)), Vector3.new(0.12, H - 0.35, 0.16))
				end
			end
		end,
	})

	-- 우드 블라인드 ---------------------------------------------------------------------------------
	D.item({
		id = "wl_blind_wood", cat = "wall", name = "우드 블라인드", price = 98000, decor = 3, style = "natural", place = "wall",
		size = { 4.2, 5.0, 0.4 }, tags = { "블라인드", "창문", "원목" },
		uses = { open = "블라인드 올리기", close = "블라인드 내리기" },
		slots = { S("wood", "슬랫", "birch", { "wood", "plastic", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("HeadRail", W, 0.25, 0.3, 0, H - 0.125, Dp / 2 - 0.15, k:sh("wood", 0.9), { solid = true })
			local n = 18
			local step = (H - 0.5) / n
			local idxs = {}
			for i = 0, n - 1 do
				local y = H - 0.4 - i * step
				local idx = k:box("Slat", W - 0.1, 0.04, 0.26, 0, y, Dp / 2 - 0.15, "wood", { rx = 12 })
				table.insert(idxs, idx)
				k:pose(idx, CFrame.new(0, H - 0.32 - i * 0.045, Dp / 2 - 0.15) * CFrame.Angles(math.rad(80), 0, 0))
			end
			k:box("BottomRail", W - 0.05, 0.1, 0.28, 0, 0.12, Dp / 2 - 0.15, k:sh("wood", 0.85))
			local br = #idxs
			local _ = br
			for _, sx in { -1, 1 } do
				k:box("Ladder", 0.04, H - 0.4, 0.02, sx * (W / 2 - 0.5), H / 2, Dp / 2 - 0.29, k:lit({ 236, 232, 222 }, "fabric"))
			end
			k:box("Cord", 0.03, 2.0, 0.03, W / 2 - 0.2, H - 1.2, Dp / 2 - 0.32, k:lit({ 236, 232, 222 }, "fabric"))
		end,
	})

	-- 플로팅 선반 -----------------------------------------------------------------------------------
	D.item({
		id = "wl_shelf_float", cat = "wall", name = "플로팅 벽 선반 3단", price = 89000, decor = 4, style = "modern", place = "wall",
		size = { 3.6, 3.4, 0.9 }, tags = { "선반", "벽선반", "책", "수납" },
		slots = { S("wood", "선반", "walnut", { "wood", "gloss", "metal" }) },
		build = function(k, W, H, Dp)
			for i = 0, 2 do
				local y = 0.15 + i * 1.5
				local w = W - (i % 2) * 0.8
				local x = (i % 2) * 0.4
				k:box("Board", w, 0.15, Dp - 0.05, x, y, 0, "wood", { solid = true, top = true })
				if i == 0 then
					k:books(x - w / 2 + 0.2, x + 0.4, y + 0.075, 0, 0.6, 0.9, 3)
					local soil = k:pot(x + 1.0, 0, 0.42, 0.4, k:lit({ 238, 236, 230 }, "ceramic"), true, y + 0.075)
					k:foliage(x + 1.0, soil + 0.2, 0, 0.22, 5, k:lit({ 90, 140, 80 }, "leafy"))
				elseif i == 1 then
					k:frame(0.8, 1.0, 0.08, x - 0.6, y + 0.58, 0.1, k:lit({ 30, 30, 34 }), k:lit({ 200, 180, 150 }))
					k:cyl("Vase", 0.7, 0.32, x + 0.6, y + 0.43, 0, "y", k:lit({ 190, 104, 74 }, "ceramic"))
				else
					k:books(x - w / 2 + 0.3, x - 0.2, y + 0.075, 0, 0.6, 0.8, 7)
					k:ball("Globe", 0.5, x + 0.8, y + 0.4, 0, k:lit({ 60, 120, 190 }, "gloss"))
				end
			end
		end,
	})

	-- 마크라메 태피스트리 ---------------------------------------------------------------------------
	D.item({
		id = "wl_macrame", cat = "wall", name = "마크라메 태피스트리", price = 64000, decor = 3, style = "cozy", place = "wall",
		size = { 2.4, 3.6, 0.2 }, tags = { "마크라메", "태피스트리", "보헤미안" },
		slots = { S("rope", "실", "ivory", { "fabric" }), S("wood", "봉", "teak", { "wood" }) },
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.08
			k:cyl("Dowel", W, 0.12, 0, H - 0.1, z, "x", "wood", { solid = true })
			for i = 0, 11 do
				local x = -W / 2 + 0.2 + i * (W - 0.4) / 11
				local len = 2.3 + math.abs(i - 5.5) * -0.12 + 0.6
				k:box("Cord", 0.06, len, 0.05, x, H - 0.15 - len / 2, z, "rope")
				k:box("Fringe", 0.08, 0.6, 0.04, x, H - 0.15 - len - 0.3, z, k:sh("rope", 0.95))
			end
			for row = 0, 3 do
				for i = 0, 5 - row do
					local x = -W / 2 + 0.4 + row * 0.17 + i * 0.34
					k:box("Knot", 0.2, 0.14, 0.08, x, H - 0.5 - row * 0.3, z - 0.03, k:sh("rope", 0.9), { rz = 45 })
				end
			end
		end,
	})

	-- 타공판 ---------------------------------------------------------------------------------------
	D.item({
		id = "wl_pegboard", cat = "wall", name = "타공판 수납 보드", price = 72000, decor = 3, style = "trendy", place = "wall",
		size = { 3.0, 3.0, 0.7 }, tags = { "타공판", "수납", "데스크테리어" },
		slots = { S("board", "보드", "mint", { "plastic", "wood", "metal" }) },
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.05
			k:box("Board", W, H, 0.08, 0, H / 2, z, "board", { solid = true })
			for i = 0, 6 do
				for j = 0, 6 do
					k:cyl("Hole", 0.02, 0.07, -W / 2 + 0.3 + i * 0.4, 0.3 + j * 0.4, z - 0.05, "z", k:sh("board", 0.6))
				end
			end
			k:box("Shelf", 1.4, 0.06, 0.45, -0.5, 1.1, z - 0.25, k:lit({ 236, 232, 224 }), { top = true })
			k:cyl("Cup", 0.3, 0.26, -0.9, 1.28, z - 0.25, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			local soil = k:pot(-0.3, z - 0.25, 0.3, 0.28, k:lit({ 214, 162, 58 }, "ceramic"), true, 1.13)
			k:foliage(-0.3, soil + 0.15, z - 0.25, 0.15, 4, k:lit({ 90, 150, 80 }, "leafy"))
			k:box("Scissors", 0.08, 0.5, 0.04, 0.8, 2.0, z - 0.1, k:lit({ 214, 52, 56 }))
			k:box("Ruler", 0.12, 1.0, 0.03, 1.1, 1.9, z - 0.09, k:lit({ 236, 220, 160 }, "wood"))
			k:box("Basket", 0.8, 0.4, 0.35, 0.8, 0.75, z - 0.22, k:lit({ 40, 40, 44 }, "metal"))
			k:frame(0.7, 0.9, 0.05, 0.2, 2.3, z - 0.04, k:lit({ 30, 30, 34 }), k:lit({ 240, 176, 196 }))
		end,
	})

	-- 전구 포토 가랜드 -------------------------------------------------------------------------------
	D.item({
		id = "wl_photo_string", cat = "wall", name = "전구 포토 가랜드", price = 36000, decor = 3, style = "cozy", place = "wall",
		size = { 5.0, 1.6, 0.25 }, tags = { "가랜드", "전구", "사진", "감성" }, light = "warm", glow = true,
		slots = {},
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.1
			local n = 8
			local first
			for i = 0, n do
				local t = i / n
				local x = -W / 2 + t * W
				local sag = math.sin(t * math.pi) * 0.5
				local y = H - 0.2 - sag
				if i < n then
					local t2 = (i + 1) / n
					local x2 = -W / 2 + t2 * W
					local y2 = H - 0.2 - math.sin(t2 * math.pi) * 0.5
					local ang = math.deg(math.atan2(y2 - y, x2 - x))
					k:cyl("Wire", math.sqrt((x2 - x) ^ 2 + (y2 - y) ^ 2), 0.03, (x + x2) / 2, (y + y2) / 2, z, "x", k:lit({ 40, 40, 40 }), { rz = ang })
				end
				local b = k:ball("Bulb", 0.14, x, y - 0.1, z, "light", { glow = true })
				if i == 4 then
					first = b
				end
				if i % 2 == 1 then
					k:box("Photo", 0.42, 0.52, 0.02, x, y - 0.45, z - 0.02, k:lit({ 246, 246, 244 }), { rz = (i % 3 - 1) * 6 })
					k:box("Pic", 0.34, 0.34, 0.01, x, y - 0.41, z - 0.035, k:lit(({ { 120, 170, 210 }, { 230, 170, 130 }, { 160, 200, 150 }, { 220, 150, 180 } })[(i // 2) % 4 + 1]), { rz = (i % 3 - 1) * 6 })
					k:box("Clip", 0.06, 0.12, 0.04, x, y - 0.18, z - 0.03, k:lit({ 200, 160, 110 }, "wood"))
				end
			end
			if first then
				k:light(first, 9, 0.5)
			end
		end,
	})

	-- 추상화 캔버스 ---------------------------------------------------------------------------------
	D.item({
		id = "wl_canvas", cat = "wall", name = "대형 추상화 캔버스", price = 210000, decor = 6, style = "luxury", place = "wall",
		size = { 4.0, 5.0, 0.2 }, tags = { "그림", "캔버스", "추상화", "아트" },
		slots = { S("c1", "색 1", "navy", { "plastic" }), S("c2", "색 2", "mustard", { "plastic" }), S("c3", "색 3", "blush", { "plastic" }) },
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.1
			k:box("Canvas", W, H, 0.18, 0, H / 2, z + 0.01, k:lit({ 244, 240, 232 }, "fabric"), { solid = true })
			local zf = Dp / 2 - 0.2
			k:box("Block", 2.2, 2.6, 0.02, -0.6, H / 2 + 0.6, zf, "c1")
			k:cyl("Circle", 0.02, 1.8, 0.7, H / 2 - 0.4, zf - 0.005, "z", "c2")
			k:box("Stroke", 3.0, 0.25, 0.02, 0.2, 1.0, zf - 0.01, "c3", { rz = 14 })
			k:box("Stroke", 0.18, 2.0, 0.02, 1.4, H / 2 + 1.0, zf - 0.01, k:lit({ 30, 30, 34 }))
			k:box("Edge", W, 0.04, 0.2, 0, H - 0.02, z, k:lit({ 220, 214, 204 }, "wood"))
		end,
	})
end
