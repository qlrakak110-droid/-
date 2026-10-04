-- GwangalliBuildings/Palette: facade styles (exterior looks per building), interior finishes and the
-- 인테리어 themes players pick (벽지 / 바닥 / 조명). Colours are {r, g, b}; materials are names
-- (Kit.mat resolves them with fallbacks). Pure data.

local Palette = {}

-------------------------------------------------------------------------------------------------
-- Facade styles. Every building picks one style and the seed varies the tones inside it, so two
-- buildings of the same archetype never look copy-pasted.
-------------------------------------------------------------------------------------------------
Palette.STYLES = {
	modern_tile = {
		name = "신축 포세린 타일",
		wall = { mat = "CeramicTiles", tones = { { 228, 226, 220 }, { 214, 212, 206 }, { 236, 233, 226 } } },
		accent = { mat = "SmoothPlastic", tones = { { 62, 66, 74 }, { 86, 90, 98 }, { 46, 52, 62 } } },
		base = { mat = "Granite", tones = { { 92, 92, 96 }, { 110, 106, 102 } } },
		frame = { 54, 58, 64 },
		glass = { color = { 120, 158, 176 }, tr = 0.42, refl = 0.12 },
		rail = "glass",
		roof = { mat = "Concrete", color = { 150, 150, 148 } },
	},
	curtain_glass = {
		name = "커튼월 유리",
		wall = { mat = "Glass", tones = { { 72, 118, 134 }, { 64, 104, 128 }, { 84, 128, 140 } } },
		accent = { mat = "Metal", tones = { { 168, 174, 180 }, { 140, 146, 154 } } },
		base = { mat = "Granite", tones = { { 64, 64, 68 }, { 80, 78, 76 } } },
		frame = { 150, 156, 162 },
		glass = { color = { 70, 116, 132 }, tr = 0.35, refl = 0.25 },
		rail = "glass",
		roof = { mat = "Concrete", color = { 140, 142, 144 } },
		curtain = true,
	},
	red_brick = {
		name = "적벽돌",
		wall = { mat = "Brick", tones = { { 146, 70, 52 }, { 158, 82, 60 }, { 132, 64, 50 } } },
		accent = { mat = "SmoothPlastic", tones = { { 232, 228, 218 }, { 220, 214, 200 } } },
		base = { mat = "Concrete", tones = { { 150, 146, 140 } } },
		frame = { 214, 210, 200 },
		glass = { color = { 110, 138, 150 }, tr = 0.4, refl = 0.08 },
		rail = "metal",
		roof = { mat = "Concrete", color = { 92, 140, 104 } }, -- green waterproof paint (옥상 방수 페인트)
	},
	old_tile = {
		name = "90년대 소형 타일",
		wall = { mat = "CeramicTiles", tones = { { 216, 196, 172 }, { 204, 186, 166 }, { 222, 206, 184 } } },
		accent = { mat = "SmoothPlastic", tones = { { 150, 92, 70 }, { 120, 84, 70 } } },
		base = { mat = "Concrete", tones = { { 130, 126, 120 } } },
		frame = { 196, 196, 190 },
		glass = { color = { 120, 140, 146 }, tr = 0.38, refl = 0.05 },
		rail = "metal",
		roof = { mat = "Concrete", color = { 84, 132, 98 } },
	},
	commercial = {
		name = "근생 상가",
		wall = { mat = "Concrete", tones = { { 200, 200, 196 }, { 186, 188, 190 }, { 210, 206, 196 } } },
		accent = { mat = "Metal", tones = { { 70, 74, 80 }, { 110, 112, 118 } } },
		base = { mat = "Granite", tones = { { 70, 68, 66 } } },
		frame = { 60, 64, 70 },
		glass = { color = { 96, 128, 140 }, tr = 0.38, refl = 0.15 },
		rail = "metal",
		roof = { mat = "Concrete", color = { 146, 146, 144 } },
	},
	hotel_stone = {
		name = "석재 + 브론즈",
		wall = { mat = "Limestone", tones = { { 214, 202, 182 }, { 204, 192, 172 } } },
		accent = { mat = "Metal", tones = { { 120, 96, 66 }, { 98, 80, 58 } } },
		base = { mat = "Granite", tones = { { 52, 50, 50 } } },
		frame = { 112, 90, 62 },
		glass = { color = { 92, 110, 120 }, tr = 0.35, refl = 0.2 },
		rail = "glass",
		roof = { mat = "Concrete", color = { 150, 148, 144 } },
	},
	wood_warm = {
		name = "우드 + 블랙 스틸",
		wall = { mat = "WoodPlanks", tones = { { 96, 66, 44 }, { 110, 76, 50 } } },
		accent = { mat = "Metal", tones = { { 34, 34, 36 }, { 44, 42, 40 } } },
		base = { mat = "Brick", tones = { { 70, 60, 56 } } },
		frame = { 30, 30, 32 },
		glass = { color = { 120, 110, 96 }, tr = 0.35, refl = 0.06 },
		rail = "metal",
		roof = { mat = "Concrete", color = { 120, 118, 114 } },
	},
	white_minimal = {
		name = "화이트 미니멀",
		wall = { mat = "Plaster", tones = { { 242, 240, 236 }, { 236, 234, 230 } } },
		accent = { mat = "Wood", tones = { { 176, 136, 96 }, { 160, 124, 88 } } },
		base = { mat = "Concrete", tones = { { 190, 188, 184 } } },
		frame = { 40, 40, 42 },
		glass = { color = { 150, 180, 190 }, tr = 0.3, refl = 0.08 },
		rail = "glass",
		roof = { mat = "WoodPlanks", color = { 150, 116, 84 } },
	},
}

-------------------------------------------------------------------------------------------------
-- Interior finishes used by the templates (common areas) and the starting look of units
-------------------------------------------------------------------------------------------------
Palette.FINISH = {
	lobbyFloor = { mat = "Marble", color = { 222, 218, 210 } },
	lobbyWall = { mat = "Plaster", color = { 236, 232, 224 } },
	lobbyStone = { mat = "Granite", color = { 64, 62, 62 } },
	corridorFloor = { mat = "CeramicTiles", color = { 196, 192, 184 } },
	corridorWall = { mat = "Plaster", color = { 232, 230, 224 } },
	stairFloor = { mat = "Concrete", color = { 150, 150, 146 } },
	stairWall = { mat = "Plaster", color = { 222, 220, 212 } },
	stairNose = { 236, 196, 70 },
	ceiling = { mat = "Plaster", color = { 244, 244, 240 } },
	parkingFloor = { mat = "Concrete", color = { 112, 132, 120 } }, -- 에폭시 바닥 (green-grey)
	parkingWall = { mat = "Concrete", color = { 188, 186, 180 } },
	toiletTile = { mat = "CeramicTiles", color = { 232, 234, 236 } },
	toiletFloor = { mat = "CeramicTiles", color = { 120, 124, 128 } },
	bathTile = { mat = "CeramicTiles", color = { 238, 238, 236 } },
	bathFloor = { mat = "Slate", color = { 140, 140, 140 } },
	kitchen = { mat = "SmoothPlastic", color = { 246, 246, 244 } },
	counterTop = { mat = "Marble", color = { 236, 236, 232 } },
	door = { mat = "Wood", color = { 196, 168, 132 } },
	unitDoor = { mat = "Metal", color = { 86, 92, 100 } },
	fireDoor = { mat = "Metal", color = { 150, 154, 158 } },
	metal = { mat = "Metal", color = { 168, 172, 176 } },
	steel = { mat = "Metal", color = { 196, 198, 200 } },
	black = { mat = "SmoothPlastic", color = { 28, 28, 30 } },
	white = { mat = "SmoothPlastic", color = { 245, 245, 243 } },
}

-------------------------------------------------------------------------------------------------
-- 인테리어 themes (homes): 벽지 (wall), 바닥 (floor), 조명 (light). price in 원.
-------------------------------------------------------------------------------------------------
Palette.WALLPAPER = {
	{ id = "silk_white", name = "화이트 실크", mat = "Plaster", color = { 244, 243, 239 }, price = 0 },
	{ id = "ivory", name = "아이보리", mat = "Plaster", color = { 238, 230, 212 }, price = 30000 },
	{ id = "greige", name = "그레이지", mat = "Plaster", color = { 206, 198, 186 }, price = 40000 },
	{ id = "mint", name = "민트", mat = "Plaster", color = { 196, 228, 214 }, price = 40000 },
	{ id = "lavender", name = "라벤더", mat = "Plaster", color = { 214, 204, 232 }, price = 40000 },
	{ id = "blush", name = "블러쉬 핑크", mat = "Plaster", color = { 238, 206, 204 }, price = 40000 },
	{ id = "navy", name = "네이비 포인트", mat = "Plaster", color = { 42, 56, 86 }, price = 50000 },
	{ id = "wood_panel", name = "우드 패널", mat = "WoodPlanks", color = { 176, 132, 92 }, price = 90000 },
	{ id = "concrete", name = "노출 콘크리트", mat = "Concrete", color = { 168, 168, 164 }, price = 80000 },
	{ id = "black", name = "블랙 매트", mat = "SmoothPlastic", color = { 40, 40, 42 }, price = 60000 },
	{ id = "brick_white", name = "화이트 벽돌", mat = "Brick", color = { 232, 228, 222 }, price = 90000 },
}

Palette.FLOORING = {
	{ id = "oak", name = "밝은 강마루", mat = "WoodPlanks", color = { 204, 168, 122 }, price = 0 },
	{ id = "walnut", name = "월넛 원목", mat = "WoodPlanks", color = { 104, 70, 46 }, price = 120000 },
	{ id = "ash_grey", name = "그레이 오크", mat = "WoodPlanks", color = { 160, 152, 140 }, price = 90000 },
	{ id = "jangpan", name = "노란 장판", mat = "SmoothPlastic", color = { 222, 190, 120 }, price = 20000 },
	{ id = "tile_grey", name = "포세린 타일", mat = "CeramicTiles", color = { 186, 184, 180 }, price = 100000 },
	{ id = "marble", name = "화이트 대리석", mat = "Marble", color = { 236, 234, 230 }, price = 200000 },
	{ id = "carpet", name = "그레이 카펫", mat = "Carpet", color = { 120, 120, 124 }, price = 70000 },
	{ id = "terrazzo", name = "테라조", mat = "Granite", color = { 214, 206, 196 }, price = 150000 },
}

Palette.LIGHTING = {
	{ id = "neutral", name = "주백색 (4000K)", color = { 255, 238, 214 }, brightness = 1.25, price = 0 },
	{ id = "cool", name = "주광색 (6500K)", color = { 226, 240, 255 }, brightness = 1.4, price = 10000 },
	{ id = "warm", name = "전구색 (2700K)", color = { 255, 196, 132 }, brightness = 1.1, price = 10000 },
	{ id = "mood_blue", name = "무드 블루", color = { 110, 140, 255 }, brightness = 0.9, price = 30000 },
	{ id = "mood_pink", name = "무드 핑크", color = { 255, 120, 190 }, brightness = 0.9, price = 30000 },
	{ id = "candle", name = "캔들 라이트", color = { 255, 150, 80 }, brightness = 0.7, price = 30000 },
}

function Palette.find(list: { any }, id: string?): any?
	for _, e in list do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- sign colour schemes (Korean street signage: bright panels, bold type)
Palette.SIGNS = {
	{ bg = { 200, 30, 40 }, fg = { 255, 255, 255 } },
	{ bg = { 20, 70, 160 }, fg = { 255, 255, 255 } },
	{ bg = { 250, 210, 40 }, fg = { 30, 30, 30 } },
	{ bg = { 20, 140, 90 }, fg = { 255, 255, 255 } },
	{ bg = { 255, 255, 255 }, fg = { 200, 30, 40 } },
	{ bg = { 30, 30, 34 }, fg = { 255, 200, 60 } },
	{ bg = { 120, 40, 160 }, fg = { 255, 230, 255 } },
	{ bg = { 255, 120, 20 }, fg = { 255, 255, 255 } },
}

return Palette
