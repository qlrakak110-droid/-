--!strict
-- GwangalliDecorShared/ItemsStorage: 수납 — 사다리 선반 · 책장 · 옷장 (문 열기) · 서랍장 · 큐브 수납장 ·
-- 사이드보드 · 신발장 · 유리 장식장 · 벽 수납장 · 수납 바구니. Shelves carry stacked pieces (top surfaces).

return function(D: any)
	local S = D.slot
	local WOOD = { "wood", "planks", "gloss" }
	local MET = { "metal", "brushed" }

	D.item({
		id = "st_ladder", cat = "storage", name = "사다리 선반 5단", price = 79000, decor = 3, style = "natural", place = "floor",
		size = { 2.4, 6.0, 1.8 }, tags = { "선반", "사다리", "책장", "수납" },
		slots = { S("wood", "프레임", "oak", WOOD) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				k:box("Rail", 0.14, 6.1, 0.18, sx * (W / 2 - 0.07), 3.0, 0.2, "wood", { rx = -10, solid = true })
			end
			for i = 0, 4 do
				local y = 0.3 + i * 1.25
				local d = 1.6 - i * 0.22
				local z = -0.3 + i * 0.22
				k:box("Shelf", W - 0.28, 0.1, d, 0, y, z - d / 2 + 0.75, "wood", { top = true, solid = true })
			end
			k:books(-0.9, 0.2, 1.6, -0.05, 0.6, 0.75, 5)
			local soil = k:pot(0.6, -0.4, 0.5, 0.45, k:lit({ 238, 236, 230 }, "ceramic"), true, 0.35)
			k:foliage(0.6, soil + 0.25, -0.4, 0.3, 6, k:lit({ 90, 140, 80 }, "leafy"))
			k:box("Basket", 1.0, 0.5, 0.8, -0.4, 0.6, -0.25, k:lit({ 200, 170, 120 }, "rattan"))
			k:cyl("Vase", 0.5, 0.25, 0.5, 4.06, 0.3, "y", k:lit({ 190, 104, 74 }, "ceramic"))
		end,
	})

	D.item({
		id = "st_bookcase", cat = "storage", name = "원목 오픈 책장 (5칸)", price = 239000, decor = 4, style = "classic", place = "floor",
		size = { 3.8, 6.4, 1.3 }, tags = { "책장", "책", "수납", "서재" },
		slots = { S("wood", "책장", "walnut", WOOD) },
		build = function(k, W, H, Dp)
			k:box("Back", W, H, 0.08, 0, H / 2, Dp / 2 - 0.04, k:sh("wood", 0.85), { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Side", 0.12, H, Dp, sx * (W / 2 - 0.06), H / 2, 0, "wood", { solid = true })
			end
			for i = 0, 5 do
				local y = 0.06 + i * (H - 0.12) / 5
				k:box("Shelf", W - 0.24, 0.12, Dp - 0.1, 0, y, 0, "wood", { top = i == 5, solid = true })
				if i < 5 then
					k:books(-W / 2 + 0.2, W / 2 - 0.3 - (i % 2) * 0.9, y + 0.06, -0.05, 0.9, 0.9, i * 3 + 1)
					if i % 2 == 1 then
						k:ball("Deco", 0.4, W / 2 - 0.6, y + 0.26, -0.1, k:lit({ 214, 176, 64 }, "metal"))
					end
				end
			end
		end,
	})

	D.item({
		id = "st_wardrobe", cat = "storage", name = "2도어 옷장", price = 590000, decor = 4, style = "modern", place = "floor",
		size = { 4.0, 6.8, 2.0 }, tags = { "옷장", "장롱", "수납", "드레스룸" },
		uses = { open = "옷장 열기", close = "옷장 닫기" },
		slots = { S("body", "본체", "white", WOOD), S("handle", "손잡이", "brass", MET) },
		build = function(k, W, H, Dp)
			k:box("Carcass", W, H, Dp - 0.12, 0, H / 2, 0.06, k:sh("body", 0.95), { solid = true })
			k:box("Inside", W - 0.2, H - 0.3, 0.05, 0, H / 2, -Dp / 2 + 0.25, k:lit({ 220, 210, 196 }, "wood"))
			k:cyl("Rail", W - 0.3, 0.08, 0, H - 0.8, 0, "x", k:lit({ 200, 202, 206 }, "metal"))
			local cols = { { 236, 240, 246 }, { 60, 70, 90 }, { 176, 124, 76 }, { 214, 52, 56 }, { 30, 30, 34 } }
			for i = 0, 4 do
				k:box("Cloth", 0.5, 2.4, 0.08, -1.3 + i * 0.6, H - 2.1, 0, k:lit(cols[i + 1], "fabric"), { ry = 85 })
			end
			k:box("Drawer", W - 0.3, 0.8, Dp - 0.5, 0, 0.6, 0.0, k:sh("body", 0.9))
			for _, sx in { -1, 1 } do
				local d = k:box("Door", W / 2 - 0.04, H - 0.1, 0.1, sx * W / 4, H / 2, -Dp / 2 + 0.05, "body")
				local h = k:box("Handle", 0.06, 1.4, 0.08, sx * 0.18, H / 2 + 0.3, -Dp / 2 - 0.04, "handle")
				k:hinge({ d, h }, sx * W / 2, 0, -Dp / 2, "y", -sx * 105)
			end
			k:box("Cornice", W + 0.1, 0.15, Dp + 0.05, 0, H - 0.075, 0, k:sh("body", 0.92), { top = true })
		end,
	})

	D.item({
		id = "st_drawer5", cat = "storage", name = "5단 서랍장", price = 289000, decor = 3, style = "natural", place = "floor",
		size = { 2.6, 4.2, 1.6 }, tags = { "서랍장", "수납", "침실" },
		slots = { S("wood", "본체", "birch", WOOD), S("knob", "손잡이", "matteblack", MET) },
		build = function(k, W, H, Dp)
			k:legs(W - 0.2, Dp - 0.2, 0.35, 0.12, 0.14, "knob", true)
			k:box("Body", W, H - 0.35, Dp, 0, 0.35 + (H - 0.35) / 2, 0, "wood", { solid = true })
			k:box("Top", W + 0.05, 0.08, Dp + 0.05, 0, H - 0.04, 0, k:sh("wood", 1.05), { top = true })
			local dh = (H - 0.5) / 5
			for i = 0, 4 do
				k:front(W - 0.1, dh, 0, 0.42 + dh * (i + 0.5), -Dp / 2, k:sh("wood", 1.03), "knob")
			end
			local soil = k:pot(0.7, 0, 0.45, 0.4, k:lit({ 238, 236, 230 }, "ceramic"), true, H)
			k:foliage(0.7, soil + 0.25, 0, 0.25, 5, k:lit({ 90, 140, 80 }, "leafy"))
		end,
	})

	D.item({
		id = "st_cube", cat = "storage", name = "큐브 수납장 3x3", price = 149000, decor = 3, style = "modern", place = "floor",
		size = { 3.6, 3.6, 1.3 }, tags = { "수납장", "큐브", "정리", "칼렉스" },
		slots = { S("body", "본체", "white", WOOD), S("box", "수납함", "sage", { "fabric", "rattan" }) },
		build = function(k, W, H, Dp)
			k:box("Back", W, H, 0.06, 0, H / 2, Dp / 2 - 0.03, k:sh("body", 0.92), { solid = true })
			for i = 0, 3 do
				local t = -W / 2 + 0.06 + i * (W - 0.12) / 3
				k:box("V", 0.12, H, Dp, t, H / 2, 0, "body", { solid = true })
				k:box("H", W, 0.12, Dp, 0, 0.06 + i * (H - 0.12) / 3, 0, "body", { solid = true, top = i == 3 })
			end
			local c = (W - 0.12) / 3
			for i = 0, 2 do
				for j = 0, 2 do
					local x = -W / 2 + 0.06 + c * (i + 0.5)
					local y = 0.06 + c * (j + 0.5)
					if (i + j) % 2 == 0 then
						k:box("Bin", c - 0.2, c - 0.2, Dp - 0.2, x, y - 0.03, -0.05, if j == 1 then k:sh("box", 0.9) else "box")
						k:box("Pull", 0.3, 0.08, 0.04, x, y + 0.25, -Dp / 2 + 0.03, k:lit({ 200, 170, 120 }, "fabric"))
					elseif j == 2 then
						k:books(x - c / 2 + 0.1, x + c / 2 - 0.1, y - c / 2 + 0.06, -0.05, 0.8, 0.8, i + j)
					end
				end
			end
		end,
	})

	D.item({
		id = "st_sideboard", cat = "storage", name = "미드센추리 사이드보드", price = 520000, decor = 5, style = "classic", place = "floor",
		size = { 5.2, 2.6, 1.6 }, tags = { "사이드보드", "거실장", "수납" },
		uses = { open = "문 열기", close = "문 닫기" },
		slots = { S("wood", "본체", "teak", WOOD), S("legs", "다리", "walnut", { "wood", "metal" }) },
		build = function(k, W, H, Dp)
			k:splayLegs(W - 0.4, Dp - 0.3, 0.7, 0.3, 0.14, "legs", 6)
			k:box("Body", W, H - 0.7, Dp, 0, 0.7 + (H - 0.7) / 2, 0, "wood", { solid = true })
			k:box("Top", W + 0.04, 0.08, Dp + 0.04, 0, H - 0.04, 0, k:sh("wood", 1.05), { top = true })
			local dw = W / 4
			for i = 0, 3 do
				local x = -W / 2 + dw * (i + 0.5)
				if i == 1 or i == 2 then
					for j = 0, 2 do
						k:front(dw, (H - 0.8) / 3, x, 0.75 + (H - 0.8) / 3 * (j + 0.5), -Dp / 2, k:sh("wood", 1.02), k:lit({ 198, 158, 92 }, "metal"))
					end
				else
					local d = k:box("Door", dw - 0.06, H - 0.86, 0.06, x, 0.72 + (H - 0.8) / 2, -Dp / 2 - 0.03, k:sh("wood", 1.08))
					local sx = if i == 0 then -1 else 1
					k:hinge({ d }, x + sx * dw / 2, 0, -Dp / 2, "y", -sx * 100)
					k:box("Slat", dw - 0.3, 0.04, 0.02, x, 1.6, -Dp / 2 - 0.07, k:sh("wood", 0.8))
				end
			end
			k:cyl("Vase", 0.9, 0.4, -1.8, H + 0.45, 0, "y", k:lit({ 46, 84, 70 }, "ceramic"))
			k:books(1.0, 1.9, H, 0, 0.7, 0.45, 2)
		end,
	})

	D.item({
		id = "st_shoe", cat = "storage", name = "슬림 신발장", price = 189000, decor = 2, style = "modern", place = "floor",
		size = { 3.4, 3.6, 1.0 }, tags = { "신발장", "현관", "수납" },
		uses = { open = "신발장 열기", close = "신발장 닫기" },
		slots = { S("body", "본체", "greige", WOOD) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp, 0, H / 2, 0, "body", { solid = true })
			k:box("Top", W + 0.04, 0.08, Dp + 0.04, 0, H - 0.04, 0, k:sh("body", 1.05), { top = true })
			for _, sx in { -1, 1 } do
				for j = 0, 1 do
					local y0 = 0.1 + j * (H - 0.2) / 2
					local d = k:box("Flap", W / 2 - 0.06, (H - 0.2) / 2 - 0.06, 0.06, sx * W / 4, y0 + (H - 0.2) / 4, -Dp / 2 - 0.03, k:sh("body", 1.04))
					k:hinge({ d }, sx * W / 4, y0, -Dp / 2, "x", -50)
					k:box("Grip", W / 2 - 0.5, 0.05, 0.05, sx * W / 4, y0 + (H - 0.2) / 2 - 0.16, -Dp / 2 - 0.07, k:lit({ 40, 40, 44 }, "metal"))
				end
			end
			k:box("Tray", 1.1, 0.06, 0.6, -0.9, H + 0.03, 0, k:lit({ 160, 116, 76 }, "wood"))
			k:box("Keys", 0.25, 0.05, 0.12, -0.9, H + 0.08, 0, k:lit({ 200, 202, 206 }, "metal"))
		end,
	})

	D.item({
		id = "st_glass_cabinet", cat = "storage", name = "유리 장식장 (조명)", price = 690000, decor = 6, style = "luxury", place = "floor",
		size = { 2.8, 6.2, 1.4 }, tags = { "장식장", "진열장", "유리", "피규어" }, light = "warm",
		uses = { open = "장식장 열기", close = "장식장 닫기" },
		slots = { S("frame", "프레임", "matteblack", { "metal", "brushed", "wood" }) },
		build = function(k, W, H, Dp)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:box("Post", 0.1, H, 0.1, sx * (W / 2 - 0.05), H / 2, sz * (Dp / 2 - 0.05), "frame", { solid = true })
				end
			end
			k:box("Back", W - 0.1, H - 0.2, 0.04, 0, H / 2, Dp / 2 - 0.05, k:lit({ 40, 40, 44 }, "gloss"))
			for i = 0, 4 do
				k:box("Shelf", W - 0.1, 0.06, Dp - 0.1, 0, 0.1 + i * (H - 0.2) / 4, 0, k:lit({ 220, 232, 236 }, "glass"), { t = 0.3, top = i == 4 })
			end
			local objs = { { 214, 176, 64 }, { 246, 246, 244 }, { 60, 120, 190 }, { 214, 52, 56 } }
			for i = 0, 3 do
				local y = 0.13 + i * (H - 0.2) / 4
				k:cyl("Vase", 0.6, 0.35, -0.6, y + 0.3, 0, "y", k:lit(objs[i + 1], "ceramic"))
				k:ball("Orb", 0.4, 0.5, y + 0.2, 0, k:lit(objs[(i + 2) % 4 + 1], "glass"), { t = 0.15 })
				k:box("Figure", 0.25, 0.7, 0.25, 0, y + 0.35, 0.1, k:lit(objs[(i + 1) % 4 + 1], "gloss"))
			end
			local led = k:box("LED", W - 0.3, 0.04, 0.1, 0, H - 0.18, -0.2, "light", { glow = true })
			k:light(led, 7, 0.6, { spot = true, face = "Bottom", angle = 100 })
			local door = k:box("Glass", W - 0.12, H - 0.15, 0.04, 0, H / 2, -Dp / 2 + 0.02, k:lit({ 220, 232, 236 }, "glass"), { t = 0.7 })
			k:hinge({ door }, -W / 2 + 0.05, 0, -Dp / 2, "y", 100)
		end,
	})

	D.item({
		id = "st_wall_cabinet", cat = "storage", name = "벽걸이 수납장", price = 129000, decor = 2, style = "modern", place = "wall",
		size = { 3.0, 1.6, 1.0 }, tags = { "수납장", "벽", "주방", "욕실" },
		uses = { open = "문 열기", close = "문 닫기" },
		slots = { S("body", "본체", "sage", WOOD) },
		build = function(k, W, H, Dp)
			k:box("Body", W, H, Dp - 0.06, 0, H / 2, 0.03, k:sh("body", 0.92), { solid = true })
			for _, sx in { -1, 1 } do
				local d = k:box("Door", W / 2 - 0.04, H - 0.06, 0.06, sx * W / 4, H / 2, -Dp / 2 + 0.03, "body")
				local h = k:box("Knob", 0.12, 0.12, 0.08, sx * 0.25, H / 2, -Dp / 2 - 0.04, k:lit({ 198, 158, 92 }, "metal"))
				k:hinge({ d, h }, sx * W / 2, 0, -Dp / 2, "y", -sx * 100)
			end
			k:box("Bottom", W, 0.06, Dp, 0, 0.03, 0, k:sh("body", 0.85), { top = true })
			k:cyl("Jar", 0.5, 0.35, -0.8, 0.31, 0, "y", k:lit({ 220, 230, 236 }, "glass"), { t = 0.3 })
			k:cyl("Mug", 0.4, 0.3, 0.6, 0.26, 0, "y", k:lit({ 246, 246, 244 }, "ceramic"))
		end,
	})

	D.item({
		id = "st_baskets", cat = "storage", name = "라탄 수납 바구니 3종", price = 45000, decor = 2, style = "natural", place = "floor",
		size = { 3.0, 1.4, 1.2 }, tags = { "바구니", "라탄", "수납", "정리" },
		slots = { S("rattan", "바구니", "teak", { "rattan", "fabric" }) },
		build = function(k, W, H, Dp)
			local sizes = { { -1.0, 1.0, 1.3 }, { 0.15, 0.85, 1.0 }, { 1.1, 0.7, 0.75 } }
			for i, s in sizes do
				k:box("Basket", s[2], s[3], s[2], s[1], s[3] / 2, 0, if i == 2 then k:sh("rattan", 0.9) else "rattan", { solid = true })
				k:box("Band", s[2] + 0.02, 0.08, s[2] + 0.02, s[1], s[3] - 0.15, 0, k:sh("rattan", 0.7))
			end
			k:box("Blanket", 0.8, 0.3, 0.7, -1.0, 1.35, 0, k:lit({ 222, 210, 188 }, "fabric"))
		end,
	})
end
