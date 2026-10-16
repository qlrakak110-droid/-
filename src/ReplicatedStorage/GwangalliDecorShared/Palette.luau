--!strict
-- GwangalliDecorShared/Palette: curated colours (이름 있는 색), finishing materials (재질), light colours
-- and the colour codecs (hex "RRGGBB" <-> {r, g, b} <-> Color3, HSV). Pure: no instances.
--   Palette.SWATCHES[group]     ordered { {key, name, rgb} }  (fabric · wood · metal · stone · bold · pastel)
--   Palette.MATERIALS[key]      { name = "가죽", enum = "Leather", fallback = "SmoothPlastic" }
--   Palette.LIGHTS              lamp light colours (전구색 · 주광색 · 핑크 · ...)
--   Palette.hex(rgb) / Palette.unhex(s) / Palette.color3(rgb) / Palette.hsv(rgb) / Palette.fromHsv(h, s, v)

local Palette = {}

export type RGB = { number }

local function clamp255(v: number): number
	return math.clamp(math.floor(v + 0.5), 0, 255)
end

function Palette.rgb(r: number, g: number, b: number): RGB
	return { clamp255(r), clamp255(g), clamp255(b) }
end

function Palette.hex(c: RGB): string
	return string.format("%02x%02x%02x", clamp255(c[1]), clamp255(c[2]), clamp255(c[3]))
end

-- "RRGGBB" (6 hex digits, case-insensitive) -> rgb, else nil
function Palette.unhex(s: any): RGB?
	if type(s) ~= "string" or #s ~= 6 or not string.match(s, "^%x%x%x%x%x%x$") then
		return nil
	end
	return {
		tonumber(string.sub(s, 1, 2), 16) :: number,
		tonumber(string.sub(s, 3, 4), 16) :: number,
		tonumber(string.sub(s, 5, 6), 16) :: number,
	}
end

function Palette.color3(c: RGB): Color3
	return Color3.fromRGB(clamp255(c[1]), clamp255(c[2]), clamp255(c[3]))
end

function Palette.fromColor3(c: Color3): RGB
	return { clamp255(c.R * 255), clamp255(c.G * 255), clamp255(c.B * 255) }
end

-- h, s, v in 0..1
function Palette.hsv(c: RGB): (number, number, number)
	local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 1e-6 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if mx > 1e-6 then d / mx else 0
	return h, s, mx
end

function Palette.fromHsv(h: number, s: number, v: number): RGB
	h = (h % 1) * 6
	s = math.clamp(s, 0, 1)
	v = math.clamp(v, 0, 1)
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return { clamp255(r * 255), clamp255(g * 255), clamp255(b * 255) }
end

-- multiplies brightness (k < 1 darker), keeps hue
function Palette.shade(c: RGB, k: number): RGB
	return { clamp255(c[1] * k), clamp255(c[2] * k), clamp255(c[3] * k) }
end

-- mixes towards `o` by t (0..1)
function Palette.mix(c: RGB, o: RGB, t: number): RGB
	return { clamp255(c[1] + (o[1] - c[1]) * t), clamp255(c[2] + (o[2] - c[2]) * t), clamp255(c[3] + (o[3] - c[3]) * t) }
end

function Palette.luma(c: RGB): number
	return (0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]) / 255
end

-------------------------------------------------------------------------------------------------
-- Named swatches (shown as the curated row above the HSV picker)
-------------------------------------------------------------------------------------------------
Palette.SWATCH_GROUPS = {
	{ id = "neutral", name = "뉴트럴" },
	{ id = "fabric", name = "패브릭" },
	{ id = "wood", name = "우드" },
	{ id = "metal", name = "메탈" },
	{ id = "stone", name = "스톤" },
	{ id = "bold", name = "포인트" },
	{ id = "pastel", name = "파스텔" },
}
Palette.SWATCHES = {
	neutral = {
		{ "white", "퓨어 화이트", { 246, 246, 244 } },
		{ "ivory", "아이보리", { 240, 234, 220 } },
		{ "greige", "그레이지", { 196, 188, 176 } },
		{ "lightgrey", "라이트 그레이", { 196, 198, 202 } },
		{ "grey", "그레이", { 140, 142, 148 } },
		{ "charcoal", "차콜", { 64, 66, 72 } },
		{ "black", "블랙", { 30, 30, 34 } },
	},
	fabric = {
		{ "oatmeal", "오트밀", { 222, 210, 188 } },
		{ "camel", "카멜", { 176, 124, 76 } },
		{ "terracotta", "테라코타", { 190, 104, 74 } },
		{ "olive", "올리브", { 116, 124, 78 } },
		{ "sage", "세이지", { 166, 184, 160 } },
		{ "navy", "네이비", { 48, 62, 100 } },
		{ "burgundy", "버건디", { 118, 36, 52 } },
		{ "mustard", "머스타드", { 214, 162, 58 } },
		{ "teal", "딥 틸", { 34, 104, 110 } },
		{ "blush", "블러쉬 핑크", { 232, 188, 190 } },
	},
	wood = {
		{ "birch", "버치", { 226, 204, 168 } },
		{ "oak", "내추럴 오크", { 200, 164, 118 } },
		{ "teak", "티크", { 160, 110, 66 } },
		{ "walnut", "월넛", { 98, 64, 42 } },
		{ "ebony", "에보니", { 48, 36, 30 } },
		{ "whitewash", "화이트워시", { 232, 226, 214 } },
	},
	metal = {
		{ "chrome", "크롬", { 210, 212, 216 } },
		{ "brass", "브라스", { 198, 158, 92 } },
		{ "gold", "골드", { 214, 176, 64 } },
		{ "copper", "코퍼", { 184, 112, 76 } },
		{ "gunmetal", "건메탈", { 70, 74, 80 } },
		{ "matteblack", "무광 블랙", { 36, 36, 40 } },
	},
	stone = {
		{ "carrara", "카라라 화이트", { 236, 236, 232 } },
		{ "travertine", "트래버틴", { 214, 196, 166 } },
		{ "nero", "네로 마퀴나", { 40, 40, 44 } },
		{ "verde", "베르데 그린", { 46, 84, 70 } },
		{ "concrete", "콘크리트", { 168, 168, 164 } },
	},
	bold = {
		{ "red", "레드", { 214, 52, 56 } },
		{ "orange", "오렌지", { 240, 128, 40 } },
		{ "yellow", "옐로", { 246, 206, 60 } },
		{ "green", "그린", { 64, 168, 90 } },
		{ "cobalt", "코발트", { 40, 84, 196 } },
		{ "purple", "퍼플", { 120, 72, 180 } },
		{ "magenta", "광안 마젠타", { 255, 79, 163 } },
		{ "cyan", "광안 시안", { 61, 214, 245 } },
	},
	pastel = {
		{ "mint", "민트", { 176, 226, 206 } },
		{ "sky", "스카이", { 176, 208, 238 } },
		{ "lavender", "라벤더", { 206, 190, 236 } },
		{ "peach", "피치", { 250, 200, 170 } },
		{ "butter", "버터", { 250, 234, 170 } },
		{ "rose", "로즈", { 240, 176, 196 } },
	},
}

-- swatch key -> { key, name, rgb, group }
Palette.BY_KEY = {} :: { [string]: { key: string, name: string, rgb: RGB, group: string } }
for _, g in Palette.SWATCH_GROUPS do
	for _, s in (Palette.SWATCHES :: any)[g.id] do
		Palette.BY_KEY[s[1]] = { key = s[1], name = s[2], rgb = s[3], group = g.id }
	end
end

-- Korean name of a colour: the nearest named swatch (for item cards / toasts)
function Palette.nameOf(c: RGB): string
	local best, bd = "커스텀", math.huge
	for _, s in Palette.BY_KEY do
		local dr, dg, db = s.rgb[1] - c[1], s.rgb[2] - c[2], s.rgb[3] - c[3]
		local d = dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11
		if d < bd then
			best, bd = s.name, d
		end
	end
	if bd > 900 then
		return "커스텀"
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- Materials (재질 옵션). enum = Enum.Material name; fallback when the engine lacks it.
-------------------------------------------------------------------------------------------------
Palette.MATERIAL_ORDER = {
	"wood", "planks", "fabric", "velvet", "leather", "metal", "brushed", "marble", "granite", "glass",
	"plastic", "gloss", "ceramic", "concrete", "slate", "rattan", "plaster", "neon",
}
Palette.MATERIALS = {
	wood = { name = "원목", enum = "Wood", fallback = "Wood" },
	planks = { name = "우드 플랭크", enum = "WoodPlanks", fallback = "Wood" },
	fabric = { name = "패브릭", enum = "Fabric", fallback = "Fabric" },
	velvet = { name = "벨벳", enum = "Fabric", fallback = "Fabric", reflect = 0.03 },
	leather = { name = "가죽", enum = "Leather", fallback = "SmoothPlastic" },
	metal = { name = "메탈", enum = "Metal", fallback = "Metal" },
	brushed = { name = "브러시드 메탈", enum = "Foil", fallback = "Metal" },
	marble = { name = "대리석", enum = "Marble", fallback = "Marble" },
	granite = { name = "화강암", enum = "Granite", fallback = "Granite" },
	glass = { name = "유리", enum = "Glass", fallback = "Glass", transparency = 0.35 },
	plastic = { name = "무광 플라스틱", enum = "SmoothPlastic", fallback = "SmoothPlastic" },
	gloss = { name = "하이글로시", enum = "SmoothPlastic", fallback = "SmoothPlastic", reflect = 0.18 },
	ceramic = { name = "세라믹", enum = "CeramicTiles", fallback = "SmoothPlastic" },
	concrete = { name = "콘크리트", enum = "Concrete", fallback = "Concrete" },
	slate = { name = "슬레이트", enum = "Slate", fallback = "Slate" },
	rattan = { name = "라탄", enum = "Wood", fallback = "Wood" },
	plaster = { name = "플라스터", enum = "Plaster", fallback = "SmoothPlastic" },
	neon = { name = "네온", enum = "Neon", fallback = "Neon" },
	carpet = { name = "카펫", enum = "Carpet", fallback = "Fabric" },
	brick = { name = "벽돌", enum = "Brick", fallback = "Brick" },
	cobble = { name = "자갈", enum = "Cobblestone", fallback = "Cobblestone" },
	grass = { name = "잔디", enum = "Grass", fallback = "Grass" },
	leafy = { name = "잎", enum = "LeafyGrass", fallback = "Grass" },
	sand = { name = "모래", enum = "Sand", fallback = "Sand" },
	ice = { name = "얼음", enum = "Ice", fallback = "Glass" },
	foil = { name = "포일", enum = "Foil", fallback = "Metal" },
	pebble = { name = "조약돌", enum = "Pebble", fallback = "Slate" },
	cardboard = { name = "골판지", enum = "Cardboard", fallback = "SmoothPlastic" },
	rubber = { name = "고무", enum = "Rubber", fallback = "SmoothPlastic" },
	snow = { name = "눈", enum = "Snow", fallback = "Sand" },
	diamond = { name = "체크 철판", enum = "DiamondPlate", fallback = "Metal" },
}

-- Enum.Material for a material key (cached; engines without a material get its fallback)
local matCache: { [string]: any } = {}
function Palette.enumOf(key: string?): any
	local k = key or "plastic"
	local c = matCache[k]
	if c then
		return c
	end
	local def = (Palette.MATERIALS :: any)[k]
	local names = if def then { def.enum, def.fallback, "SmoothPlastic" } else { k, "SmoothPlastic" }
	local found: any = nil
	for _, n in names do
		local ok, m = pcall(function()
			return (Enum.Material :: any)[n]
		end)
		if ok and m then
			found = m
			break
		end
	end
	matCache[k] = found
	return found
end

-------------------------------------------------------------------------------------------------
-- Light colours (lamps: 색 바꾸기 cycles these; the colour panel offers them + HSV)
-------------------------------------------------------------------------------------------------
Palette.LIGHTS = {
	{ "warm", "전구색", { 255, 206, 150 } },
	{ "neutral", "주백색", { 255, 236, 210 } },
	{ "cool", "주광색", { 232, 242, 255 } },
	{ "amber", "앰버", { 255, 160, 80 } },
	{ "pink", "핑크", { 255, 120, 190 } },
	{ "violet", "바이올렛", { 176, 130, 255 } },
	{ "blue", "오션 블루", { 90, 170, 255 } },
	{ "green", "그린", { 110, 240, 150 } },
	{ "red", "레드", { 255, 80, 80 } },
}

return Palette
