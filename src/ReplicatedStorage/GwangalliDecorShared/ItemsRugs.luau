--!strict
-- GwangalliDecorShared/ItemsRugs: 러그·카펫 — flat pieces that lie on the floor (or on another rug) and
-- that furniture can stand on. Patterns are thin inlay parts just above the base.

return function(D: any)
	local S = D.slot
	local RUG = { "fabric", "carpet", "velvet" }

	D.item({
		id = "rg_wave", cat = "rugs", name = "광안리 파도 러그", price = 129000, decor = 4, style = "modern", place = "rug",
		size = { 7.0, 0.12, 5.0 }, tags = { "러그", "카펫", "파도", "바다" },
		slots = { S("base", "바탕", "ivory", RUG), S("wave", "파도", "cobalt", RUG) },
		build = function(k, W, H, Dp)
			k:box("Rug", W, 0.06, Dp, 0, 0.03, 0, "base", { top = true })
			for i = 0, 5 do
				local z = -Dp / 2 + 0.7 + i * 0.7
				for j = 0, 6 do
					local x = -W / 2 + 0.6 + j * 0.97
					k:box("Wave", 0.7, 0.02, 0.12, x, 0.07, z + math.sin(j * 1.3 + i) * 0.12, if i % 2 == 0 then "wave" else k:mx("wave", { 255, 255, 255 }, 0.45), { ry = (j % 2) * 30 - 15 })
				end
			end
			k:box("Fringe", 0.12, 0.04, Dp, -W / 2 - 0.06, 0.02, 0, k:sh("base", 0.95))
			k:box("Fringe", 0.12, 0.04, Dp, W / 2 + 0.06, 0.02, 0, k:sh("base", 0.95))
		end,
	})

	D.item({
		id = "rg_jute", cat = "rugs", name = "황마 원형 러그", price = 89000, decor = 3, style = "natural", place = "rug",
		size = { 5.0, 0.1, 5.0 }, tags = { "러그", "원형", "황마", "내추럴" },
		slots = { S("jute", "황마", { 196, 160, 110 }, { "fabric", "rattan" }) },
		build = function(k, W, H, Dp)
			k:cyl("Rug", 0.06, W, 0, 0.03, 0, "y", "jute", { top = true })
			for i = 1, 5 do
				k:cyl("Braid", 0.02, W - i * 0.8, 0, 0.065, 0, "y", if i % 2 == 0 then k:sh("jute", 0.85) else k:sh("jute", 1.08))
			end
		end,
	})

	D.item({
		id = "rg_checker", cat = "rugs", name = "체커보드 러그", price = 99000, decor = 4, style = "trendy", place = "rug",
		size = { 6.0, 0.1, 4.0 }, tags = { "러그", "체크", "레트로", "트렌디" },
		slots = { S("a", "색 1", "butter", RUG), S("b", "색 2", "lavender", RUG) },
		build = function(k, W, H, Dp)
			k:box("Rug", W, 0.05, Dp, 0, 0.025, 0, "a", { top = true })
			local n, m = 6, 4
			for i = 0, n - 1 do
				for j = 0, m - 1 do
					if (i + j) % 2 == 1 then
						k:box("Tile", W / n - 0.02, 0.02, Dp / m - 0.02, -W / 2 + (i + 0.5) * W / n, 0.055, -Dp / 2 + (j + 0.5) * Dp / m, "b")
					end
				end
			end
		end,
	})

	D.item({
		id = "rg_persian", cat = "rugs", name = "페르시안 러그", price = 690000, decor = 8, style = "classic", place = "rug",
		size = { 8.0, 0.12, 5.6 }, tags = { "러그", "페르시안", "카펫", "호텔" },
		slots = { S("field", "바탕", "burgundy", RUG), S("border", "테두리", "navy", RUG), S("motif", "문양", "mustard", RUG) },
		build = function(k, W, H, Dp)
			k:box("Rug", W, 0.06, Dp, 0, 0.03, 0, "border", { top = true })
			k:box("Field", W - 1.0, 0.02, Dp - 1.0, 0, 0.07, 0, "field")
			k:box("Line", W - 0.6, 0.015, 0.08, 0, 0.072, -Dp / 2 + 0.3, "motif")
			k:box("Line", W - 0.6, 0.015, 0.08, 0, 0.072, Dp / 2 - 0.3, "motif")
			k:box("Line", 0.08, 0.015, Dp - 0.6, -W / 2 + 0.3, 0.072, 0, "motif")
			k:box("Line", 0.08, 0.015, Dp - 0.6, W / 2 - 0.3, 0.072, 0, "motif")
			k:box("Medallion", 1.6, 0.02, 1.6, 0, 0.085, 0, "motif", { ry = 45 })
			k:box("MedallionIn", 1.0, 0.02, 1.0, 0, 0.095, 0, "border", { ry = 45 })
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					k:box("Corner", 0.9, 0.02, 0.9, sx * (W / 2 - 1.2), 0.085, sz * (Dp / 2 - 1.1), "motif", { ry = 45 })
				end
				for i = 0, 9 do
					k:box("Fringe", 0.3, 0.03, 0.06, sx * (W / 2 + 0.12), 0.02, -Dp / 2 + 0.3 + i * (Dp - 0.6) / 9, k:lit({ 236, 228, 210 }, "fabric"))
				end
			end
		end,
	})

	D.item({
		id = "rg_playmat", cat = "rugs", name = "도톰한 놀이매트", price = 159000, decor = 2, style = "kids", place = "rug",
		size = { 6.0, 0.25, 4.0 }, tags = { "놀이매트", "매트", "아이", "층간소음" },
		slots = { S("mat", "매트", "mint", { "plastic", "rubber" }), S("pattern", "그림", "sky", { "plastic" }) },
		build = function(k, W, H, Dp)
			k:box("Mat", W, 0.2, Dp, 0, 0.1, 0, "mat", { top = true })
			k:box("Road", W - 1.2, 0.02, 0.5, 0, 0.21, 0.6, k:lit({ 90, 94, 100 }))
			for i = 0, 5 do
				k:box("Dash", 0.35, 0.01, 0.06, -W / 2 + 1.0 + i * 0.8, 0.225, 0.6, k:lit({ 246, 230, 120 }))
			end
			k:cyl("Pond", 0.02, 1.4, -1.6, 0.21, -0.9, "y", "pattern")
			k:box("House", 0.8, 0.02, 0.7, 1.6, 0.21, -0.9, k:lit({ 240, 176, 196 }))
			k:box("Roof", 0.6, 0.02, 0.6, 1.6, 0.215, -1.35, k:lit({ 214, 52, 56 }), { ry = 45 })
		end,
	})

	D.item({
		id = "rg_shag", cat = "rugs", name = "샤기 러그 (롱파일)", price = 119000, decor = 3, style = "cozy", place = "rug",
		size = { 6.0, 0.25, 4.4 }, tags = { "러그", "샤기", "털", "포근" },
		slots = { S("pile", "털", "greige", RUG) },
		build = function(k, W, H, Dp)
			k:box("Rug", W, 0.1, Dp, 0, 0.05, 0, "pile", { top = true })
			for i = 0, 9 do
				for j = 0, 6 do
					k:box("Tuft", 0.5, 0.1, 0.5, -W / 2 + 0.35 + i * 0.59, 0.12, -Dp / 2 + 0.35 + j * 0.62, if (i + j) % 3 == 0 then k:sh("pile", 1.06) else k:sh("pile", 0.96), { ry = (i * 37 + j * 11) % 45 })
				end
			end
		end,
	})

	D.item({
		id = "rg_runner", cat = "rugs", name = "킬림 복도 러너", price = 69000, decor = 2, style = "natural", place = "rug",
		size = { 2.4, 0.08, 8.0 }, tags = { "러너", "복도", "킬림", "현관" },
		slots = { S("base", "바탕", "terracotta", RUG), S("motif", "문양", "ivory", RUG) },
		build = function(k, W, H, Dp)
			k:box("Rug", W, 0.05, Dp, 0, 0.025, 0, "base", { top = true })
			for i = 0, 6 do
				local z = -Dp / 2 + 0.7 + i * 1.1
				k:box("Diamond", 0.8, 0.015, 0.8, 0, 0.055, z, "motif", { ry = 45 })
				k:box("DiamondIn", 0.4, 0.015, 0.4, 0, 0.06, z, "base", { ry = 45 })
			end
			k:box("Stripe", 0.08, 0.015, Dp - 0.3, -W / 2 + 0.2, 0.055, 0, "motif")
			k:box("Stripe", 0.08, 0.015, Dp - 0.3, W / 2 - 0.2, 0.055, 0, "motif")
		end,
	})

	D.item({
		id = "rg_round_wool", cat = "rugs", name = "울 원형 러그 (투톤)", price = 149000, decor = 3, style = "modern", place = "rug",
		size = { 4.4, 0.1, 4.4 }, tags = { "러그", "원형", "울" },
		slots = { S("outer", "바깥", "sage", RUG), S("inner", "안쪽", "oatmeal", RUG) },
		build = function(k, W, H, Dp)
			k:cyl("Rug", 0.06, W, 0, 0.03, 0, "y", "outer", { top = true })
			k:cyl("Inner", 0.02, W * 0.62, 0, 0.07, 0, "y", "inner")
			k:cyl("Dot", 0.02, W * 0.2, 0, 0.08, 0, "y", "outer")
		end,
	})

	D.item({
		id = "rg_stripe", cat = "rugs", name = "스트라이프 면 러그", price = 59000, decor = 2, style = "cozy", place = "rug",
		size = { 5.0, 0.08, 3.4 }, tags = { "러그", "스트라이프", "면" },
		slots = { S("a", "바탕", "white", RUG), S("b", "줄무늬", "navy", RUG) },
		build = function(k, W, H, Dp)
			k:box("Rug", W, 0.05, Dp, 0, 0.025, 0, "a", { top = true })
			for i = 0, 6 do
				k:box("Stripe", 0.28, 0.015, Dp - 0.1, -W / 2 + 0.45 + i * 0.68, 0.055, 0, if i % 3 == 1 then k:lit({ 214, 52, 56 }, "fabric") else "b")
			end
		end,
	})

	D.item({
		id = "rg_tatami", cat = "rugs", name = "다다미 매트 2장", price = 99000, decor = 3, style = "natural", place = "rug",
		size = { 5.8, 0.2, 5.8 }, tags = { "다다미", "매트", "좌식", "일본" },
		slots = { S("straw", "다다미", { 200, 196, 140 }, { "fabric", "rattan" }), S("edge", "테두리", "black", { "fabric" }) },
		build = function(k, W, H, Dp)
			for i = 0, 1 do
				local x = -W / 4 + i * W / 2
				k:box("Mat", W / 2 - 0.05, 0.16, Dp, x, 0.08, 0, "straw", { top = true })
				k:box("Edge", 0.12, 0.17, Dp, x - W / 4 + 0.08, 0.085, 0, "edge")
				k:box("Edge", 0.12, 0.17, Dp, x + W / 4 - 0.08, 0.085, 0, "edge")
				for j = 0, 11 do
					k:box("Weave", W / 2 - 0.35, 0.01, 0.03, x, 0.165, -Dp / 2 + 0.25 + j * 0.48, k:sh("straw", 0.9))
				end
			end
		end,
	})
end
