--!strict
-- GwangalliDecorShared/ItemsPlants: 식물 — 몬스테라 · 떡갈고무나무 · 올리브 · 극락조 · 산세베리아 · 선인장 ·
-- 행잉 스킨답서스 · 허브 · 분재 · 대나무 · 모스 액자. Pots take a colour + material.

return function(D: any)
	local S = D.slot
	local POT = { "ceramic", "concrete", "rattan", "plastic", "gloss" }
	local LEAF = { 74, 128, 72 }

	D.item({
		id = "pl_monstera", cat = "plants", name = "몬스테라 대형 화분", price = 89000, decor = 4, style = "natural", place = "floor",
		size = { 3.0, 4.6, 3.0 }, tags = { "식물", "화분", "몬스테라", "플랜테리어" },
		slots = { S("pot", "화분", "white", POT), S("leaf", "잎", LEAF, { "leafy", "plastic" }) },
		build = function(k, W, H, Dp)
			local soil = k:pot(0, 0, 1.3, 1.3, "pot", true)
			k:cyl("Stake", 2.4, 0.1, 0, soil + 1.1, 0, "y", k:lit({ 120, 92, 60 }, "wood"))
			k:leaves(0, soil + 1.9, 0, 1.6, 9, "leaf")
			k:leaves(0, soil + 1.2, 0, 1.2, 6, k:shp("leaf", 1.1))
		end,
	})

	D.item({
		id = "pl_fiddle", cat = "plants", name = "떡갈고무나무", price = 120000, decor = 4, style = "natural", place = "floor",
		size = { 2.4, 6.4, 2.4 }, tags = { "식물", "화분", "나무", "플랜테리어" },
		slots = { S("pot", "화분", "terracotta", POT), S("leaf", "잎", { 60, 110, 58 }, { "leafy", "plastic" }) },
		build = function(k, W, H, Dp)
			local soil = k:pot(0, 0, 1.2, 1.2, "pot", true)
			k:cyl("Trunk", 3.4, 0.2, 0, soil + 1.7, 0, "y", k:lit({ 110, 86, 62 }, "wood"))
			for i = 0, 13 do
				local a = i * 2.39996
				local y = soil + 2.0 + (i / 13) * 3.0
				local r = 0.55 - (i / 13) * 0.25
				k:box("Leaf", 0.75, 0.05, 0.95, math.cos(a) * r, y, math.sin(a) * r, if i % 2 == 0 then "leaf" else k:sh("leaf", 0.85), { rx = 35, ry = math.deg(a) })
			end
		end,
	})

	D.item({
		id = "pl_olive", cat = "plants", name = "올리브 나무", price = 150000, decor = 5, style = "natural", place = "floor",
		size = { 2.8, 6.0, 2.8 }, tags = { "식물", "올리브", "나무", "지중해" },
		slots = { S("pot", "화분", "travertine", POT), S("leaf", "잎", { 132, 150, 110 }, { "leafy", "plastic" }) },
		build = function(k, W, H, Dp)
			local soil = k:pot(0, 0, 1.4, 1.4, "pot", false)
			k:cyl("Trunk", 2.2, 0.24, 0, soil + 1.1, 0, "y", k:lit({ 120, 100, 80 }, "wood"), { rz = 6 })
			k:cyl("Branch", 1.4, 0.12, 0.35, soil + 2.4, 0, "y", k:lit({ 120, 100, 80 }, "wood"), { rz = -30 })
			k:cyl("Branch", 1.3, 0.12, -0.3, soil + 2.5, 0.2, "y", k:lit({ 120, 100, 80 }, "wood"), { rz = 28, rx = 10 })
			k:foliage(0.1, soil + 3.4, 0, 0.75, 16, "leaf", 1.5)
			k:foliage(0.7, soil + 2.9, 0.2, 0.5, 6, k:shp("leaf", 1.12))
		end,
	})

	D.item({
		id = "pl_strelitzia", cat = "plants", name = "극락조화", price = 135000, decor = 5, style = "luxury", place = "floor",
		size = { 3.0, 6.2, 3.0 }, tags = { "식물", "극락조", "플랜테리어", "호텔" },
		slots = { S("pot", "화분", "charcoal", POT), S("leaf", "잎", { 52, 106, 70 }, { "leafy", "plastic" }) },
		build = function(k, W, H, Dp)
			local soil = k:pot(0, 0, 1.3, 1.5, "pot", true)
			for i = 0, 8 do
				local a = i * 40 + (i % 2) * 15
				local ar = math.rad(a)
				local len = 3.2 + (i % 3) * 0.5
				k:cyl("Stem", len, 0.07, math.sin(ar) * 0.35, soil + len / 2, math.cos(ar) * 0.35, "y", k:lit({ 90, 120, 70 }), { rx = math.cos(ar) * 12, rz = -math.sin(ar) * 12 })
				k:box("Leaf", 0.6, 1.9, 0.05, math.sin(ar) * 0.75, soil + len + 0.5, math.cos(ar) * 0.75, if i % 2 == 0 then "leaf" else k:sh("leaf", 0.88), { ry = a, rx = math.cos(ar) * 18, rz = -math.sin(ar) * 18 })
			end
		end,
	})

	D.item({
		id = "pl_snake", cat = "plants", name = "산세베리아", price = 45000, decor = 3, style = "modern", place = "floor",
		size = { 1.4, 3.2, 1.4 }, tags = { "식물", "산세베리아", "공기정화" },
		slots = { S("pot", "화분", "black", POT), S("leaf", "잎", { 70, 110, 70 }, { "leafy", "plastic" }) },
		build = function(k, W, H, Dp)
			local soil = k:pot(0, 0, 1.0, 1.0, "pot", false)
			for i = 0, 9 do
				local a = i * 2.39996
				local h = 1.4 + ((i * 0.618) % 1) * 0.9
				local x, z = math.cos(a) * 0.25, math.sin(a) * 0.25
				k:box("Leaf", 0.22, h, 0.05, x, soil + h / 2, z, if i % 3 == 0 then k:mx("leaf", { 220, 210, 120 }, 0.35) else "leaf", { ry = math.deg(a), rx = math.cos(a) * 6, rz = math.sin(a) * 6 })
			end
		end,
	})

	D.item({
		id = "pl_cactus_trio", cat = "plants", name = "미니 선인장 3종", price = 25000, decor = 2, style = "trendy", place = "surface",
		size = { 1.6, 1.3, 0.7 }, tags = { "식물", "선인장", "다육이" },
		slots = { S("pot", "화분", "peach", POT) },
		build = function(k, W, H, Dp)
			for i = -1, 1 do
				local x = i * 0.55
				local soil = k:pot(x, 0, 0.42, 0.38, if i == 0 then "pot" else k:shp("pot", 0.85 + i * 0.1), true)
				if i == -1 then
					k:cyl("Cactus", 0.7, 0.24, x, soil + 0.35, 0, "y", k:lit({ 80, 140, 90 }))
					k:ball("Top", 0.24, x, soil + 0.7, 0, k:lit({ 80, 140, 90 }))
					k:cyl("Arm", 0.3, 0.12, x + 0.13, soil + 0.45, 0, "y", k:lit({ 80, 140, 90 }), { rz = -20 })
				elseif i == 0 then
					k:ball("Ball", 0.36, x, soil + 0.16, 0, k:lit({ 96, 150, 96 }))
					k:ball("Flower", 0.1, x, soil + 0.36, 0, k:lit({ 250, 120, 160 }))
				else
					for j = 0, 4 do
						local a = math.rad(j * 72)
						k:box("Leaf", 0.1, 0.06, 0.2, x + math.cos(a) * 0.08, soil + 0.05, math.sin(a) * 0.08, k:lit({ 150, 190, 150 }), { ry = j * 72, rx = 25 })
					end
				end
			end
		end,
	})

	D.item({
		id = "pl_hanging_pothos", cat = "plants", name = "행잉 스킨답서스", price = 39000, decor = 3, style = "natural", place = "ceiling",
		size = { 1.8, 3.4, 1.8 }, tags = { "식물", "행잉", "플랜테리어", "마크라메" },
		slots = { S("pot", "화분", "white", POT), S("rope", "마크라메", "oatmeal", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:cyl("Hook", 0.1, 0.3, 0, H - 0.05, 0, "y", k:lit({ 200, 200, 204 }, "metal"))
			for i = 0, 3 do
				local a = math.rad(i * 90 + 45)
				k:cyl("Rope", 1.9, 0.04, math.cos(a) * 0.22, H - 1.0, math.sin(a) * 0.22, "y", "rope", { rx = math.sin(a) * 7, rz = -math.cos(a) * 7 })
			end
			local soil = k:pot(0, 0, 0.9, 0.7, "pot", true, 1.2)
			k:foliage(0, soil + 0.2, 0, 0.45, 8, k:lit({ 90, 150, 70 }, "leafy"))
			for i = 0, 5 do
				local a = i * 1.05
				local len = 1.0 + (i % 3) * 0.3
				k:cyl("Vine", len, 0.05, math.cos(a) * 0.5, soil - len / 2 + 0.1, math.sin(a) * 0.5, "y", k:lit({ 70, 120, 60 }))
				for j = 1, 3 do
					k:box("Leaf", 0.22, 0.03, 0.18, math.cos(a) * 0.55, soil + 0.1 - j * len / 3, math.sin(a) * 0.55, k:lit({ 110, 170, 80 }, "leafy"), { rx = 60, ry = math.deg(a) })
				end
			end
		end,
	})

	D.item({
		id = "pl_herb_pots", cat = "plants", name = "허브 화분 트레이 (바질 · 로즈마리)", price = 32000, decor = 2, style = "cozy", place = "surface",
		size = { 1.8, 1.0, 0.7 }, tags = { "식물", "허브", "주방", "홈카페" },
		slots = { S("tray", "트레이", "oak", { "wood", "metal" }), S("pot", "화분", "terracotta", POT) },
		build = function(k, W, H, Dp)
			k:box("Tray", W, 0.08, Dp, 0, 0.04, 0, "tray", { solid = true })
			for i = -1, 1 do
				local soil = k:pot(i * 0.58, 0, 0.45, 0.42, "pot", true, 0.08)
				if i == 0 then
					for j = 0, 5 do
						k:cyl("Sprig", 0.5, 0.03, i * 0.58 + (j - 2.5) * 0.04, soil + 0.25, (j % 2) * 0.05, "y", k:lit({ 80, 110, 80 }), { rz = (j - 2.5) * 6 })
					end
				else
					k:foliage(i * 0.58, soil + 0.18, 0, 0.18, 6, k:lit(if i < 0 then { 70, 150, 70 } else { 110, 160, 90 }, "leafy"))
				end
			end
		end,
	})

	D.item({
		id = "pl_bonsai", cat = "plants", name = "소나무 분재", price = 210000, decor = 5, style = "classic", place = "surface",
		size = { 1.8, 1.6, 1.1 }, tags = { "식물", "분재", "소나무", "전통" },
		slots = { S("pot", "화분", "navy", { "ceramic", "gloss", "concrete" }) },
		build = function(k, W, H, Dp)
			k:box("Pot", 1.5, 0.3, 0.9, 0, 0.15, 0, "pot", { solid = true })
			k:box("Moss", 1.4, 0.05, 0.8, 0, 0.32, 0, k:lit({ 90, 120, 60 }, "grass"))
			k:cyl("Trunk", 0.8, 0.16, -0.1, 0.7, 0, "y", k:lit({ 100, 80, 64 }, "wood"), { rz = 25 })
			k:cyl("Trunk2", 0.7, 0.12, 0.15, 1.05, 0, "y", k:lit({ 100, 80, 64 }, "wood"), { rz = -40 })
			k:foliage(-0.45, 1.05, 0, 0.3, 6, k:lit({ 50, 90, 50 }, "leafy"), 1.4)
			k:foliage(0.45, 1.3, 0.05, 0.28, 6, k:lit({ 56, 98, 54 }, "leafy"), 1.4)
			k:box("Stone", 0.25, 0.15, 0.2, 0.45, 0.4, 0.2, k:lit({ 140, 140, 136 }, "slate"))
		end,
	})

	D.item({
		id = "pl_bamboo", cat = "plants", name = "관음죽 대형 화분", price = 98000, decor = 4, style = "natural", place = "floor",
		size = { 2.2, 5.8, 2.2 }, tags = { "식물", "대나무", "관음죽" },
		slots = { S("pot", "화분", "concrete", POT) },
		build = function(k, W, H, Dp)
			local soil = k:pot(0, 0, 1.1, 1.2, "pot", false)
			for i = 0, 6 do
				local a = i * 2.39996
				local h = 3.0 + (i % 3) * 0.7
				local x, z = math.cos(a) * 0.25, math.sin(a) * 0.25
				k:cyl("Cane", h, 0.1, x, soil + h / 2, z, "y", k:lit({ 120, 150, 80 }), { rx = math.sin(a) * 4, rz = -math.cos(a) * 4 })
				for j = 0, 3 do
					k:box("Leaf", 0.12, 0.04, 0.9, x + math.cos(a + j) * 0.3, soil + h - 0.4 + j * 0.15, z + math.sin(a + j) * 0.3, k:lit({ 80, 140, 70 }, "leafy"), { rx = 30, ry = math.deg(a) + j * 90 })
				end
			end
		end,
	})

	D.item({
		id = "pl_moss_frame", cat = "plants", name = "스칸디아 모스 액자", price = 68000, decor = 3, style = "natural", place = "wall",
		size = { 2.4, 2.4, 0.3 }, tags = { "식물", "모스", "액자", "벽장식" },
		slots = { S("frame", "액자", "walnut", { "wood", "metal" }), S("moss", "이끼", { 110, 150, 80 }, { "grass", "leafy" }) },
		build = function(k, W, H, Dp)
			k:frame(W, H, Dp, 0, H / 2, Dp / 2, "frame")
			k:box("Back", W - 0.2, H - 0.2, 0.06, 0, H / 2, Dp / 2 - 0.05, k:sh("frame", 0.6), { solid = true })
			for i = 0, 11 do
				local a = i * 2.39996
				local r = 0.25 + ((i * 0.618) % 1) * 0.65
				k:cyl("Moss", 0.14 + (i % 2) * 0.06, 0.45 + (i % 3) * 0.12, math.cos(a) * r, H / 2 + math.sin(a) * r, Dp / 2 - 0.16, "z", if i % 3 == 0 then k:shp("moss", 1.15) else "moss")
			end
		end,
	})
end
