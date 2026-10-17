--!strict
-- GwangalliDecorShared/ItemsSeason: 시즌·파티 — 풍선 아치 · 미러볼 · 파티 테이블 · 가랜드 · 케이크 ·
-- 크리스마스 트리 · 할로윈 호박 · 연등 · 눈사람 · 추석 송편 상 · 복주머니 · 생일 풍선 숫자.

return function(D: any)
	local S = D.slot

	D.item({
		id = "ss_balloon_arch", cat = "season", name = "집들이 풍선 아치", price = 79000, decor = 5, style = "season", place = "floor",
		size = { 6.4, 6.4, 1.4 }, tags = { "풍선", "파티", "집들이", "생일" },
		slots = { S("a", "풍선 1", "blush", { "gloss", "plastic" }), S("b", "풍선 2", "white", { "gloss", "plastic" }), S("c", "풍선 3", "gold", { "gloss", "foil" }) },
		build = function(k, W, H, Dp)
			k:box("BaseL", 0.8, 0.3, 0.8, -W / 2 + 0.4, 0.15, 0, k:lit({ 236, 232, 224 }), { solid = true })
			k:box("BaseR", 0.8, 0.3, 0.8, W / 2 - 0.4, 0.15, 0, k:lit({ 236, 232, 224 }), { solid = true })
			local paints = { "a", "b", "c" }
			local n = 26
			for i = 0, n do
				local t = i / n
				local a = math.pi * t
				local x = -math.cos(a) * (W / 2 - 0.6)
				local y = 0.6 + math.sin(a) * (H - 1.3)
				local off = ((i * 0.618) % 1 - 0.5) * 0.35
				k:ball("Balloon", 0.85 + (i % 3) * 0.12, x, y, off, paints[i % 3 + 1])
				if i % 2 == 0 then
					k:ball("Balloon", 0.55, x + 0.2, y + 0.25, -off - 0.25, paints[(i + 1) % 3 + 1])
				end
			end
		end,
	})

	D.item({
		id = "ss_mirrorball", cat = "season", name = "회전 미러볼", price = 89000, decor = 4, style = "trendy", place = "ceiling",
		size = { 1.6, 2.4, 1.6 }, tags = { "미러볼", "파티", "클럽", "디스코" }, light = "violet",
		slots = {},
		build = function(k, W, H, Dp)
			k:cyl("Motor", 0.3, 0.4, 0, H - 0.15, 0, "y", k:lit({ 30, 30, 34 }, "metal"))
			k:cyl("Chain", 0.7, 0.04, 0, H - 0.65, 0, "y", k:lit({ 200, 202, 206 }, "metal"))
			k:ball("MirrorBall", 1.4, 0, 0.7, 0, k:lit({ 220, 224, 232 }, "foil"), { rf = 0.6, solid = true })
			for i = 0, 15 do
				local a = i * 2.39996
				local yy = ((i * 0.37) % 1) * 1.1 - 0.55
				local r = math.sqrt(math.max(0, 0.49 - yy * yy))
				k:box("Facet", 0.22, 0.22, 0.04, math.cos(a) * r, 0.7 + yy, math.sin(a) * r, k:lit({ 245, 248, 255 }, "glass"), { rf = 0.8, ry = -math.deg(a) + 90 })
			end
			local sp = k:ball("Spot", 0.2, 0, H - 0.4, 0.3, "light", { glow = true })
			k:light(sp, 18, 1.2, { spot = true, face = "Bottom", angle = 120 })
		end,
	})

	D.item({
		id = "ss_party_table", cat = "season", name = "집들이 파티 테이블 (치킨 · 피자)", price = 129000, decor = 5, style = "season", place = "floor",
		size = { 5.0, 3.0, 2.6 }, tags = { "파티", "테이블", "음식", "집들이", "치킨" },
		slots = { S("cloth", "테이블보", "white", { "fabric" }), S("accent", "포인트", "magenta", { "plastic", "foil" }) },
		build = function(k, W, H, Dp)
			k:legs(W - 0.3, Dp - 0.3, 2.3, 0.15, 0.15, k:lit({ 40, 40, 44 }, "metal"), true)
			k:box("Top", W, 0.1, Dp, 0, 2.35, 0, k:lit({ 200, 164, 118 }, "wood"), { solid = true, top = true })
			k:box("Cloth", W + 0.1, 0.04, Dp + 0.1, 0, 2.42, 0, "cloth")
			k:box("Skirt", W + 0.1, 0.8, 0.04, 0, 2.02, -Dp / 2 - 0.05, "cloth")
			k:box("Box", 1.4, 0.15, 1.4, -1.4, 2.52, 0, k:lit({ 240, 230, 210 }, "cardboard"))
			k:cyl("Pizza", 0.06, 1.25, -1.4, 2.62, 0, "y", k:lit({ 226, 160, 70 }))
			for i = 0, 5 do
				k:ball("Pepperoni", 0.16, -1.4 + math.cos(i) * 0.35, 2.66, math.sin(i) * 0.35, k:lit({ 190, 60, 50 }))
			end
			k:cyl("Bucket", 0.7, 0.8, 0.3, 2.79, 0, "y", k:lit({ 214, 52, 56 }))
			for i = 0, 4 do
				k:ball("Chicken", 0.3, 0.3 + math.cos(i * 1.3) * 0.2, 3.2, math.sin(i * 1.3) * 0.2, k:lit({ 196, 120, 50 }))
			end
			for i = 0, 2 do
				k:cyl("Cola", 0.55, 0.22, 1.3 + i * 0.35, 2.71, -0.5, "y", k:lit({ 60, 30, 20 }, "glass"), { t = 0.2 })
				k:cyl("Cup", 0.35, 0.25, 1.4 + i * 0.35, 2.61, 0.5, "y", "accent")
			end
		end,
	})

	D.item({
		id = "ss_garland", cat = "season", name = "HAPPY HOUSEWARMING 가랜드", price = 19000, decor = 3, style = "season", place = "wall",
		size = { 6.0, 1.6, 0.2 }, tags = { "가랜드", "파티", "집들이", "배너" },
		slots = { S("a", "깃발 1", "mint", { "fabric", "plastic" }), S("b", "깃발 2", "peach", { "fabric", "plastic" }) },
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.08
			local n = 12
			for i = 0, n - 1 do
				local t = (i + 0.5) / n
				local x = -W / 2 + t * W
				local y = H - 0.25 - math.sin(t * math.pi) * 0.45
				k:box("Flag", 0.4, 0.55, 0.02, x, y - 0.3, z, if i % 2 == 0 then "a" else "b", { rz = (t - 0.5) * 20 })
				k:box("Tip", 0.28, 0.28, 0.02, x, y - 0.58, z, if i % 2 == 0 then "a" else "b", { rz = 45 })
				k:box("Letter", 0.18, 0.2, 0.01, x, y - 0.3, z - 0.02, k:lit({ 255, 255, 255 }))
			end
			k:cyl("String", W, 0.03, 0, H - 0.4, z + 0.02, "x", k:lit({ 236, 232, 222 }, "fabric"))
		end,
	})

	D.item({
		id = "ss_cake", cat = "season", name = "3단 축하 케이크", price = 49000, decor = 3, style = "season", place = "surface",
		size = { 1.2, 1.6, 1.2 }, tags = { "케이크", "생일", "파티", "디저트" }, light = "warm",
		slots = { S("cream", "크림", "white", { "plastic", "fabric" }), S("berry", "장식", "red", { "gloss" }) },
		build = function(k, W, H, Dp)
			k:cyl("Plate", 0.06, 1.2, 0, 0.03, 0, "y", k:lit({ 246, 246, 244 }, "ceramic"), { solid = true })
			for i = 0, 2 do
				local dia = 1.0 - i * 0.25
				k:cyl("Tier", 0.35, dia, 0, 0.06 + 0.175 + i * 0.35, 0, "y", if i == 1 then k:mx("cream", { 240, 176, 196 }, 0.5) else "cream")
				for j = 0, 5 do
					local a = j * math.pi / 3
					k:ball("Berry", 0.1, math.cos(a) * dia / 2 * 0.8, 0.06 + 0.35 + i * 0.35, math.sin(a) * dia / 2 * 0.8, "berry")
				end
			end
			for i = -1, 1 do
				k:cyl("Candle", 0.3, 0.05, i * 0.12, 1.26, 0, "y", k:lit({ 120, 190, 240 }))
				local f = k:ball("Flame", 0.08, i * 0.12, 1.45, 0, "light", { glow = true })
				if i == 0 then
					k:light(f, 6, 0.5)
				end
			end
		end,
	})

	D.item({
		id = "ss_xmas_tree", cat = "season", name = "크리스마스 트리 (오너먼트)", price = 169000, decor = 7, style = "season", place = "floor",
		size = { 3.4, 7.0, 3.4 }, tags = { "크리스마스", "트리", "겨울", "연말" }, light = "warm",
		slots = { S("tree", "트리", { 40, 96, 60 }, { "leafy", "plastic" }), S("orn", "오너먼트", "red", { "gloss", "foil" }), S("orn2", "오너먼트 2", "gold", { "gloss", "foil" }) },
		build = function(k, W, H, Dp)
			k:cyl("Pot", 0.8, 1.2, 0, 0.4, 0, "y", k:lit({ 236, 232, 222 }, "fabric"), { solid = true })
			k:cyl("Trunk", 0.6, 0.3, 0, 1.0, 0, "y", k:lit({ 100, 70, 50 }, "wood"))
			for i = 0, 4 do
				local dia = 3.3 - i * 0.6
				local y = 1.3 + i * 1.05
				k:cyl("Layer", 1.3, dia, 0, y + 0.55, 0, "y", if i % 2 == 0 then "tree" else k:sh("tree", 1.1), { solid = i == 0 })
				k:cyl("Tip", 0.5, dia * 0.7, 0, y + 1.25, 0, "y", k:sh("tree", 0.92))
				for j = 0, 5 do
					local a = j * math.pi / 3 + i * 0.5
					k:ball("Ornament", 0.26, math.cos(a) * dia / 2, y + 0.3, math.sin(a) * dia / 2, if j % 2 == 0 then "orn" else "orn2")
					k:ball("Light", 0.12, math.cos(a + 0.5) * (dia / 2 - 0.05), y + 0.8, math.sin(a + 0.5) * (dia / 2 - 0.05), "light", { glow = true })
				end
			end
			local star = k:box("Star", 0.5, 0.5, 0.12, 0, H - 0.3, 0, "light", { glow = true, rz = 45 })
			k:light(star, 14, 0.9)
			for i = 0, 2 do
				k:box("Gift", 0.7, 0.55, 0.7, -0.9 + i * 0.9, 0.275, -1.1, k:lit(({ { 214, 52, 56 }, { 40, 84, 196 }, { 64, 168, 90 } })[i + 1]), { ry = i * 20 })
				k:box("Ribbon", 0.72, 0.56, 0.1, -0.9 + i * 0.9, 0.28, -1.1, k:lit({ 214, 176, 64 }, "foil"), { ry = i * 20 })
			end
		end,
	})

	D.item({
		id = "ss_pumpkin", cat = "season", name = "할로윈 호박등", price = 29000, decor = 3, style = "season", place = "surface",
		size = { 1.2, 1.2, 1.2 }, tags = { "할로윈", "호박", "잭오랜턴" }, light = "amber",
		slots = { S("pumpkin", "호박", "orange", { "plastic", "gloss" }) },
		build = function(k, W, H, Dp)
			for i = 0, 5 do
				local a = i * math.pi / 3
				k:ball("Lobe", 0.75, math.cos(a) * 0.2, 0.42, math.sin(a) * 0.2, if i % 2 == 0 then "pumpkin" else k:sh("pumpkin", 0.9), { solid = i == 0 })
			end
			k:cyl("Stem", 0.3, 0.12, 0, 0.92, 0, "y", k:lit({ 90, 110, 60 }))
			local face = k:box("EyeL", 0.16, 0.16, 0.05, -0.18, 0.55, -0.55, "light", { glow = true, rz = 45 })
			k:box("EyeR", 0.16, 0.16, 0.05, 0.18, 0.55, -0.55, "light", { glow = true, rz = 45 })
			k:box("Mouth", 0.4, 0.1, 0.05, 0, 0.32, -0.55, "light", { glow = true })
			k:light(face, 8, 0.8)
		end,
	})

	D.item({
		id = "ss_lotus_lantern", cat = "season", name = "연등 (부처님 오신 날)", price = 25000, decor = 3, style = "season", place = "ceiling",
		size = { 1.4, 2.8, 1.4 }, tags = { "연등", "전통", "등", "봄" }, light = { 255, 150, 170 },
		slots = { S("petal", "꽃잎", "rose", { "fabric", "plastic" }) },
		build = function(k, W, H, Dp)
			k:cyl("String", 1.2, 0.03, 0, H - 0.6, 0, "y", k:lit({ 236, 222, 190 }, "fabric"))
			local core = k:ball("Core", 1.0, 0, 1.0, 0, "light", { glow = true, t = 0.2 })
			for i = 0, 11 do
				local a = i * math.pi / 6
				k:box("Petal", 0.3, 0.5, 0.1, math.cos(a) * 0.45, 1.05 + (i % 2) * 0.15, math.sin(a) * 0.45, if i % 2 == 0 then "petal" else k:sh("petal", 1.1), { ry = -math.deg(a) + 90, rx = -25 })
			end
			k:cyl("Leaf", 0.08, 1.2, 0, 0.55, 0, "y", k:lit({ 80, 160, 90 }))
			for i = 0, 3 do
				k:box("Tassel", 0.06, 0.5, 0.06, (i - 1.5) * 0.12, 0.25, 0, k:lit({ 246, 206, 60 }, "fabric"))
			end
			k:light(core, 8, 0.6)
		end,
	})

	D.item({
		id = "ss_snowman", cat = "season", name = "눈사람 인형", price = 59000, decor = 3, style = "season", place = "floor",
		size = { 3.2, 3.6, 1.8 }, tags = { "눈사람", "겨울", "크리스마스" },
		slots = { S("scarf", "목도리", "red", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:ball("Body", 1.7, 0, 0.85, 0, k:lit({ 248, 250, 255 }, "snow"), { solid = true })
			k:ball("Head", 1.15, 0, 2.15, 0, k:lit({ 248, 250, 255 }, "snow"))
			k:cyl("Scarf", 0.25, 1.05, 0, 1.68, 0, "y", "scarf")
			k:box("ScarfTail", 0.25, 0.6, 0.08, 0.3, 1.35, -0.5, "scarf", { rz = 10 })
			k:cyl("Hat", 0.6, 0.65, 0, 2.95, 0, "y", k:lit({ 30, 30, 34 }))
			k:cyl("Brim", 0.08, 0.95, 0, 2.66, 0, "y", k:lit({ 30, 30, 34 }))
			k:cyl("Carrot", 0.4, 0.1, 0, 2.15, -0.7, "z", k:lit({ 240, 128, 40 }))
			for _, sx in { -1, 1 } do
				k:ball("Eye", 0.1, sx * 0.18, 2.3, -0.5, k:lit({ 20, 20, 22 }))
				k:cyl("Arm", 1.0, 0.06, sx * 1.1, 1.2, 0, "x", k:lit({ 100, 70, 50 }, "wood"), { rz = -sx * 25 })
			end
		end,
	})

	D.item({
		id = "ss_chuseok", cat = "season", name = "추석 송편 · 전 상차림", price = 69000, decor = 4, style = "season", place = "surface",
		size = { 2.4, 0.8, 1.6 }, tags = { "추석", "송편", "명절", "한식" },
		slots = { S("tray", "소반", "walnut", { "wood", "gloss" }) },
		build = function(k, W, H, Dp)
			k:box("Tray", W, 0.08, Dp, 0, 0.04, 0, "tray", { solid = true, top = true })
			k:box("Rim", W, 0.12, 0.06, 0, 0.1, -Dp / 2 + 0.03, k:sh("tray", 0.85))
			k:box("Rim", W, 0.12, 0.06, 0, 0.1, Dp / 2 - 0.03, k:sh("tray", 0.85))
			k:cyl("Plate", 0.06, 0.9, -0.6, 0.11, 0, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			local cols = { { 240, 236, 226 }, { 160, 200, 140 }, { 240, 176, 196 }, { 230, 210, 140 } }
			for i = 0, 8 do
				local a = i * 0.7
				k:ball("Songpyeon", 0.2, -0.6 + math.cos(a) * 0.25 * (i % 2 + 0.5), 0.2 + (i // 5) * 0.08, math.sin(a) * 0.25, k:lit(cols[i % 4 + 1]))
			end
			k:cyl("Plate", 0.06, 0.9, 0.6, 0.11, 0, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			for i = 0, 3 do
				k:cyl("Jeon", 0.05, 0.32, 0.45 + (i % 2) * 0.3, 0.17 + (i // 2) * 0.05, -0.15 + (i // 2) * 0.3, "y", k:lit({ 220, 170, 80 }))
			end
			k:cyl("Cup", 0.2, 0.22, 0, 0.18, 0.5, "y", k:lit({ 246, 246, 244 }, "ceramic"))
		end,
	})

	D.item({
		id = "ss_bokjumeoni", cat = "season", name = "설날 복주머니 장식", price = 22000, decor = 3, style = "season", place = "wall",
		size = { 1.4, 2.2, 1.3 }, tags = { "설날", "복주머니", "명절", "새해" },
		slots = { S("silk", "비단", "red", { "fabric", "velvet" }), S("knot", "매듭", "gold", { "fabric" }) },
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.62
			k:cyl("Hook", 0.15, 0.1, 0, H - 0.08, Dp / 2 - 0.07, "z", k:lit({ 200, 202, 206 }, "metal"))
			k:box("Strap", 0.06, 0.06, 0.55, 0, H - 0.08, Dp / 2 - 0.4, "knot")
			k:box("Cord", 0.05, 0.6, 0.05, 0, H - 0.4, z + 0.1, "knot")
			k:ball("Pouch", 1.2, 0, 0.8, z, "silk", { solid = true })
			k:cyl("Neck", 0.2, 0.55, 0, 1.35, z, "y", k:sh("silk", 0.9))
			k:box("Fold", 0.75, 0.2, 0.4, 0, 1.5, z, "silk")
			k:box("Knot", 0.3, 0.3, 0.12, 0, 1.3, z - 0.3, "knot", { rz = 45 })
			k:box("Tassel", 0.12, 0.6, 0.06, 0, 0.3, z - 0.15, "knot")
			k:box("Bok", 0.3, 0.3, 0.02, 0, 0.8, z - 0.6, "knot")
		end,
	})

	D.item({
		id = "ss_number_balloon", cat = "season", name = "생일 숫자 풍선 '25'", price = 18000, decor = 2, style = "season", place = "floor",
		size = { 2.8, 4.6, 0.8 }, tags = { "생일", "풍선", "숫자", "파티" },
		slots = { S("foil", "풍선", "gold", { "foil", "gloss" }) },
		build = function(k, W, H, Dp)
			k:box("Weight", 0.5, 0.3, 0.5, 0, 0.15, 0, k:lit({ 236, 232, 224 }), { solid = true })
			k:box("String", 0.03, 1.5, 0.03, 0, 1.05, 0, k:lit({ 236, 232, 224 }))
			local y0 = 1.8
			-- 2
			k:box("Seg", 0.9, 0.28, 0.4, -0.75, y0 + 2.5, 0, "foil")
			k:box("Seg", 0.28, 0.9, 0.4, -0.35, y0 + 2.0, 0, "foil")
			k:box("Seg", 0.9, 0.28, 0.4, -0.75, y0 + 1.45, 0, "foil", { rz = -30 })
			k:box("Seg", 0.28, 0.6, 0.4, -1.15, y0 + 0.8, 0, "foil")
			k:box("Seg", 0.9, 0.28, 0.4, -0.75, y0 + 0.3, 0, "foil")
			-- 5
			k:box("Seg", 0.9, 0.28, 0.4, 0.75, y0 + 2.5, 0, "foil")
			k:box("Seg", 0.28, 0.9, 0.4, 0.35, y0 + 2.0, 0, "foil")
			k:box("Seg", 0.9, 0.28, 0.4, 0.75, y0 + 1.5, 0, "foil")
			k:box("Seg", 0.28, 0.9, 0.4, 1.15, y0 + 0.95, 0, "foil")
			k:box("Seg", 0.9, 0.28, 0.4, 0.75, y0 + 0.3, 0, "foil")
		end,
	})
end
