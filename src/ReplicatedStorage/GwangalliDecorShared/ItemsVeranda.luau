--!strict
-- GwangalliDecorShared/ItemsVeranda: 베란다 · 테라스 — 플랜터 · 비스트로 세트 · 해먹 · 화로대 (불 피우기) ·
-- 바베큐 그릴 · 선베드 · 빨래 건조대 · 에그 체어 · 전구 줄조명 · 장독대.

return function(D: any)
	local S = D.slot
	local MET = { "metal", "brushed", "plastic" }

	D.item({
		id = "vr_planter_box", cat = "veranda", name = "원목 화단 플랜터 (꽃 · 허브)", price = 129000, decor = 4, style = "natural", place = "floor",
		size = { 4.4, 2.4, 1.6 }, tags = { "플랜터", "화단", "꽃", "베란다", "식물" },
		slots = { S("wood", "플랜터", "teak", { "wood", "planks", "concrete" }) },
		build = function(k, W, H, Dp)
			k:box("Box", W, 1.3, Dp, 0, 0.65, 0, "wood", { solid = true })
			for i = 0, 3 do
				k:box("Plank", W + 0.02, 0.05, Dp + 0.02, 0, 0.3 + i * 0.3, 0, k:sh("wood", 0.85))
			end
			k:box("Soil", W - 0.2, 0.08, Dp - 0.2, 0, 1.28, 0, k:lit({ 70, 52, 38 }, "slate"))
			local cols = { { 240, 120, 160 }, { 250, 220, 90 }, { 250, 250, 250 }, { 180, 120, 220 } }
			for i = 0, 7 do
				local x = -W / 2 + 0.4 + i * 0.5
				k:cyl("Stem", 0.7, 0.04, x, 1.65, (i % 2) * 0.3 - 0.15, "y", k:lit({ 80, 130, 70 }))
				k:ball("Bloom", 0.3, x, 2.05 + (i % 3) * 0.08, (i % 2) * 0.3 - 0.15, k:lit(cols[i % 4 + 1]))
				k:foliage(x, 1.45, (i % 2) * 0.3 - 0.15, 0.18, 3, k:lit({ 80, 140, 70 }, "leafy"))
			end
		end,
	})

	D.item({
		id = "vr_bistro", cat = "veranda", name = "철제 비스트로 테이블 세트", price = 159000, decor = 4, style = "classic", place = "floor",
		size = { 5.0, 3.0, 2.6 }, tags = { "비스트로", "테이블", "의자", "테라스", "카페" },
		slots = { S("metal", "철제", "sage", MET), S("top", "상판", "carrara", { "marble", "metal", "wood" }) },
		build = function(k, W, H, Dp)
			k:cyl("Top", 0.1, 1.9, 0, 2.4, 0, "y", "top", { solid = true, top = true })
			k:cyl("Pole", 2.3, 0.12, 0, 1.2, 0, "y", "metal")
			k:cyl("Foot", 0.08, 1.1, 0, 0.04, 0, "y", "metal")
			for _, sx in { -1, 1 } do
				local x = sx * 1.75
				k:cyl("Seat", 0.1, 1.3, x, 1.45, 0, "y", "metal", { solid = true })
				for i = 0, 3 do
					local a = math.rad(i * 90 + 45)
					k:cyl("ChairLeg", 1.5, 0.07, x + math.cos(a) * 0.45, 0.73, math.sin(a) * 0.45, "y", "metal", { rx = math.sin(a) * 4, rz = -math.cos(a) * 4 })
				end
				k:cyl("BackRing", 0.07, 1.2, x + sx * 0.6, 2.4, 0, "x", "metal", { rz = sx * 80 })
				for j = 0, 2 do
					k:box("BackBar", 0.06, 0.9, 0.06, x + sx * 0.6, 1.95, -0.35 + j * 0.35, "metal", { rz = sx * 10 })
				end
				k:seat(x, 1.55, 0, sx * -90)
			end
			k:cyl("Cup", 0.25, 0.22, 0.3, 2.58, 0.2, "y", k:lit({ 246, 246, 244 }, "ceramic"))
			k:cyl("Vase", 0.4, 0.18, -0.3, 2.65, -0.1, "y", k:lit({ 220, 230, 236 }, "glass"), { t = 0.3 })
			k:ball("Flower", 0.25, -0.3, 2.95, -0.1, k:lit({ 240, 120, 160 }))
		end,
	})

	D.item({
		id = "vr_hammock", cat = "veranda", name = "스탠드 해먹", price = 239000, decor = 4, style = "cozy", place = "floor",
		size = { 9.0, 3.8, 3.0 }, tags = { "해먹", "휴식", "테라스", "캠핑" },
		slots = { S("fabric", "해먹", "mustard", { "fabric" }), S("frame", "프레임", "teak", { "wood", "metal" }) },
		build = function(k, W, H, Dp)
			k:box("Base", W - 1.0, 0.25, 0.3, 0, 0.125, 0, "frame", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Foot", 0.3, 0.25, Dp, sx * (W / 2 - 1.2), 0.125, 0, "frame")
				k:box("Arm", 0.25, 3.8, 0.25, sx * (W / 2 - 0.9), 1.95, 0, "frame", { rz = sx * 25 })
			end
			k:box("Bed", W - 3.6, 0.12, Dp - 0.8, 0, 1.6, 0, "fabric", { solid = true })
			for _, sx in { -1, 1 } do
				k:box("Sling", 1.0, 0.1, Dp - 1.0, sx * (W / 2 - 2.4), 2.0, 0, k:sh("fabric", 0.92), { rz = -sx * 30 })
				k:box("Rope", 1.0, 0.04, 0.04, sx * (W / 2 - 1.5), 2.8, 0, k:lit({ 222, 210, 188 }, "fabric"), { rz = -sx * 35 })
			end
			for i = 0, 6 do
				k:box("Fringe", 0.06, 0.3, 0.04, -1.5 + i * 0.5, 1.45, -Dp / 2 + 0.4, k:sh("fabric", 1.08))
			end
			k:box("Pillow", 1.0, 0.3, 0.8, -1.8, 1.82, 0, k:lit({ 236, 232, 222 }, "fabric"))
			k:bed(0, 1.75, 0, 90)
		end,
	})

	D.item({
		id = "vr_firepit", cat = "veranda", name = "캠핑 화로대", price = 189000, decor = 5, style = "cozy", place = "floor",
		size = { 2.6, 1.8, 2.6 }, tags = { "화로", "불멍", "캠핑", "테라스" }, light = { 255, 140, 60 },
		uses = {},
		slots = { S("metal", "화로", "gunmetal", { "metal", "slate" }) },
		build = function(k, W, H, Dp)
			for i = 0, 2 do
				local a = math.rad(i * 120)
				k:box("Leg", 0.12, 0.8, 0.12, math.sin(a) * 0.9, 0.4, math.cos(a) * 0.9, "metal")
			end
			k:cyl("Bowl", 0.6, 2.4, 0, 1.0, 0, "y", "metal", { solid = true })
			k:cyl("BowlIn", 0.05, 2.1, 0, 1.31, 0, "y", k:lit({ 40, 36, 34 }, "slate"))
			for i = 0, 3 do
				local a = i * 50
				k:cyl("Log", 1.4, 0.25, 0, 1.45, 0, "x", k:lit({ 110, 76, 50 }, "wood"), { ry = a, rz = 8 })
			end
			local ember = k:box("Ember", 1.2, 0.08, 1.2, 0, 1.36, 0, "light", { glow = true })
			k:light(ember, 16, 1.6)
			k:fire(0, 1.75, 0, 1.2, 0.8, 1.2)
		end,
	})

	D.item({
		id = "vr_bbq", cat = "veranda", name = "바베큐 그릴 (삼겹살 OK)", price = 340000, decor = 3, style = "trendy", place = "floor",
		size = { 3.2, 3.6, 1.8 }, tags = { "바베큐", "그릴", "고기", "캠핑" },
		uses = { open = "뚜껑 열기", close = "뚜껑 닫기" },
		slots = { S("body", "본체", "black", { "metal", "gloss" }) },
		build = function(k, W, H, Dp)
			k:box("Cart", W, 0.1, Dp - 0.2, 0, 0.9, 0, k:lit({ 120, 124, 130 }, "metal"))
			k:legs(W - 0.1, Dp - 0.3, 2.1, 0.1, 0.1, k:lit({ 120, 124, 130 }, "metal"), true)
			k:box("Firebox", 2.0, 0.8, Dp - 0.3, 0, 2.5, 0, "body", { solid = true })
			k:box("Grate", 1.9, 0.04, Dp - 0.4, 0, 2.92, 0, k:lit({ 60, 60, 64 }, "metal"))
			for i = 0, 2 do
				k:box("Pork", 0.5, 0.06, 0.3, -0.5 + i * 0.5, 2.97, -0.1 + (i % 2) * 0.3, k:lit({ 220, 150, 120 }))
			end
			local lid = k:box("Lid", 2.0, 0.5, Dp - 0.3, 0, 3.15, 0, "body")
			local h = k:box("Handle", 1.0, 0.08, 0.1, 0, 3.25, -Dp / 2 + 0.05, k:lit({ 160, 116, 76 }, "wood"))
			k:hinge({ lid, h }, 0, 2.9, Dp / 2 - 0.15, "x", 80)
			k:box("Shelf", 0.6, 0.06, Dp - 0.4, W / 2 - 0.3, 2.6, 0, k:lit({ 160, 116, 76 }, "wood"), { top = true })
			k:cyl("Tank", 0.8, 0.5, -W / 2 + 0.4, 1.35, 0, "y", k:lit({ 214, 52, 56 }, "gloss"))
		end,
	})

	D.item({
		id = "vr_sunbed", cat = "veranda", name = "라탄 선베드", price = 259000, decor = 4, style = "luxury", place = "floor",
		size = { 2.6, 2.8, 6.4 }, tags = { "선베드", "라탄", "테라스", "휴양" },
		slots = { S("rattan", "프레임", "teak", { "rattan", "wood", "metal" }), S("pad", "쿠션", "white", { "fabric" }) },
		build = function(k, W, H, Dp)
			k:box("Frame", W, 0.5, Dp - 1.6, 0, 0.55, 0.6, "rattan", { solid = true })
			k:legs(W - 0.1, Dp - 1.8, 0.3, 0.1, 0.15, "rattan", false)
			k:box("Pad", W - 0.2, 0.3, Dp - 1.8, 0, 0.95, 0.6, "pad")
			k:box("Back", W - 0.2, 0.3, 2.0, 0, 1.75, -Dp / 2 + 0.95, "pad", { rx = 45 })
			k:box("BackFrame", W, 0.25, 2.0, 0, 1.6, -Dp / 2 + 0.85, "rattan", { rx = 45 })
			k:box("Towel", W - 0.6, 0.06, 1.2, 0, 1.14, 1.6, k:lit({ 61, 160, 220 }, "fabric"))
			k:bed(0, 1.15, 0.4, 180)
		end,
	})

	D.item({
		id = "vr_drying_rack", cat = "veranda", name = "접이식 빨래 건조대", price = 39000, decor = 1, style = "modern", place = "floor",
		size = { 4.6, 3.4, 1.8 }, tags = { "빨래", "건조대", "베란다", "생활" },
		slots = { S("metal", "프레임", "white", MET) },
		build = function(k, W, H, Dp)
			for _, sz in { -1, 1 } do
				k:box("Wing", W, 0.06, 0.06, 0, 3.0, sz * (Dp / 2 - 0.1), "metal")
				for i = 0, 8 do
					k:cyl("Rod", Dp - 0.2, 0.04, -W / 2 + 0.2 + i * (W - 0.4) / 8, 3.0, 0, "z", "metal")
				end
				for _, sx in { -1, 1 } do
					k:box("Leg", 0.06, 3.1, 0.06, sx * (W / 2 - 0.1), 1.5, sz * 0.4, "metal", { rx = sz * 10 })
				end
			end
			local cols = { { 236, 240, 246 }, { 61, 160, 220 }, { 240, 176, 196 }, { 60, 70, 90 }, { 246, 206, 60 } }
			for i = 0, 4 do
				k:box("Laundry", 0.7, 1.1 - (i % 2) * 0.3, 0.05, -1.8 + i * 0.9, 2.4 + (i % 2) * 0.15, 0, k:lit(cols[i + 1], "fabric"), { ry = 90 })
			end
		end,
	})

	D.item({
		id = "vr_egg_chair", cat = "veranda", name = "행잉 에그 체어", price = 390000, decor = 5, style = "cozy", place = "floor",
		size = { 3.0, 6.4, 3.0 }, tags = { "에그체어", "행잉체어", "라탄", "그네" },
		slots = { S("rattan", "바스켓", "teak", { "rattan", "metal" }), S("pad", "쿠션", "ivory", { "fabric", "velvet" }) },
		build = function(k, W, H, Dp)
			k:cyl("Base", 0.2, 2.2, 0, 0.1, 0, "y", k:lit({ 40, 40, 44 }, "metal"), { solid = true })
			k:cyl("Pole", 5.6, 0.18, 0, 3.0, 0.9, "y", k:lit({ 40, 40, 44 }, "metal"), { rx = -10 })
			k:box("Hook", 0.15, 0.15, 1.2, 0, 6.0, 0.4, k:lit({ 40, 40, 44 }, "metal"))
			k:cyl("Chain", 1.2, 0.06, 0, 5.4, 0, "y", k:lit({ 120, 124, 130 }, "metal"))
			k:ball("Egg", 2.6, 0, 2.9, 0, "rattan", { solid = true })
			k:box("Opening", 2.2, 2.2, 1.4, 0, 2.9, -0.9, k:lit({ 40, 30, 22 }, "wood"), { t = 0.2 })
			k:box("Cushion", 1.8, 0.4, 1.6, 0, 2.05, -0.2, "pad")
			k:box("Pillow", 1.0, 0.8, 0.3, 0, 2.6, 0.5, k:sh("pad", 0.92), { rx = -15 })
			k:seat(0, 2.25, -0.2)
		end,
	})

	D.item({
		id = "vr_string_lights", cat = "veranda", name = "테라스 전구 줄조명", price = 49000, decor = 3, style = "cozy", place = "wall",
		size = { 7.0, 1.4, 0.3 }, tags = { "줄조명", "전구", "테라스", "감성" }, light = "warm", glow = true,
		slots = {},
		build = function(k, W, H, Dp)
			local z = Dp / 2 - 0.12
			local n = 10
			local mid
			for i = 0, n do
				local t = i / n
				local x = -W / 2 + t * W
				local y = H - 0.15 - math.sin(t * math.pi) * 0.8
				if i < n then
					local t2 = (i + 1) / n
					local x2 = -W / 2 + t2 * W
					local y2 = H - 0.15 - math.sin(t2 * math.pi) * 0.8
					k:cyl("Wire", math.sqrt((x2 - x) ^ 2 + (y2 - y) ^ 2), 0.035, (x + x2) / 2, (y + y2) / 2, z, "x", k:lit({ 30, 30, 32 }), { rz = math.deg(math.atan2(y2 - y, x2 - x)) })
				end
				k:cyl("Socket", 0.12, 0.08, x, y - 0.08, z, "y", k:lit({ 30, 30, 32 }))
				local b = k:ball("Bulb", 0.22, x, y - 0.25, z, "light", { glow = true })
				if i == 5 then
					mid = b
				end
			end
			if mid then
				k:light(mid, 14, 0.8)
			end
		end,
	})

	D.item({
		id = "vr_jangdok", cat = "veranda", name = "장독대 항아리 3종", price = 120000, decor = 5, style = "classic", place = "floor",
		size = { 3.4, 2.2, 2.0 }, tags = { "장독", "항아리", "전통", "된장", "한옥" },
		slots = { S("clay", "옹기", { 104, 70, 50 }, { "ceramic", "gloss" }) },
		build = function(k, W, H, Dp)
			k:box("Stone", W, 0.2, Dp, 0, 0.1, 0, k:lit({ 150, 146, 140 }, "slate"), { solid = true })
			local jars = { { -1.0, 1.3, 1.8 }, { 0.2, 1.1, 1.5 }, { 1.15, 0.85, 1.1 } }
			for _, j in jars do
				k:ball("Jar", j[3], j[1], 0.2 + j[2] / 2, 0, "clay", { solid = true })
				k:cyl("Neck", 0.15, j[3] * 0.55, j[1], 0.2 + j[2] - 0.05, 0, "y", k:sh("clay", 0.9))
				k:cyl("Lid", 0.12, j[3] * 0.62, j[1], 0.2 + j[2] + 0.06, 0, "y", k:sh("clay", 0.8))
				k:ball("Knob", 0.15, j[1], 0.2 + j[2] + 0.15, 0, k:sh("clay", 0.8))
			end
		end,
	})
end
