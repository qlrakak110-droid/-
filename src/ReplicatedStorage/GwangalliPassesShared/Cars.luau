-- GwangalliPassesShared/Cars: the 프리미엄 차고 catalog (pure data) + handling specs + paints.
-- Each car is its own VehicleKind ("gw_*"), so the rig, the driver's controller and the server speed check all
-- read the same VS.Specs entry (both peers add it at start: Cars.install(VS)). Never police / taxi / ambulance.
--   body = "hyper" | "super"   our own part-built body (CarBodies)
--   base = "luxury" | "suv"    a clone of that kind's drive template (the map's G80 / Tucson) + a body kit

local Cars = {}

Cars.LIST = {
	{
		key = "hyper",
		kind = "gw_hyper",
		label = "광안 GT-X",
		class = "하이퍼카",
		glyph = "🏎️",
		body = "hyper",
		paint = "purple",
		glow = Color3.fromRGB(170, 90, 255),
		blurb = "미드십 하이퍼카 · 카본 리어윙 · 네온 라이트 블레이드",
		spec = { base = "luxury", topKmh = 210, reverseKmh = 30, accel = 34, brake = 58, drive = "AWD", mass = 168, gripF = 0.36, gripR = 0.37, steerLow = 33, steerHigh = 8, E = 0.26, U = 0.45, z = 0.66, hbGrip = 0.14, roll = 0.72 },
		seats = 2,
	},
	{
		key = "super",
		kind = "gw_super",
		label = "광안 GT",
		class = "슈퍼카",
		glyph = "🏁",
		body = "super",
		paint = "candy_red",
		glow = Color3.fromRGB(255, 70, 70),
		blurb = "프런트 엔진 GT 쿠페 · 덕테일 · 쿼드 머플러",
		spec = { base = "luxury", topKmh = 195, reverseKmh = 30, accel = 31, brake = 55, drive = "RWD", mass = 170, gripF = 0.35, gripR = 0.35, steerLow = 34, steerHigh = 8.5, E = 0.27, U = 0.48, z = 0.64, hbGrip = 0.13, roll = 0.68 },
		seats = 2,
	},
	{
		key = "vip",
		kind = "gw_vip",
		label = "VIP 블랙 에디션",
		class = "VIP 세단",
		glyph = "🖤",
		base = "luxury",
		paint = "matte_black",
		glow = Color3.fromRGB(255, 236, 200),
		blurb = "플래그십 세단 VIP 사양 · 짙은 썬팅 · 골드 번호판 프레임",
		spec = { base = "luxury", topKmh = 178, accel = 29, brake = 52, drive = "RWD", gripF = 0.32, gripR = 0.33, steerHigh = 9.5, z = 0.7 },
		interior = "g80",
		seats = 5,
	},
	{
		key = "offroad",
		kind = "gw_offroad",
		label = "몬스터 오프로더",
		class = "오프로더",
		glyph = "🛻",
		base = "suv",
		paint = "sand",
		glow = Color3.fromRGB(255, 190, 90),
		blurb = "리프트업 SUV · 루프 라이트바 · 불바 · 스노클",
		spec = { base = "suv", topKmh = 145, accel = 22, brake = 46, drive = "AWD", gripF = 0.34, gripR = 0.35, E = 0.42, U = 0.85, z = 0.5, roll = 0.66 },
		interior = "tucson",
		lift = 0.9,
		tyreGrow = 0.55,
		seats = 5,
	},
}

Cars.BY_KEY = {}
Cars.BY_KIND = {}
for i, c in Cars.LIST do
	c.order = i
	Cars.BY_KEY[c.key] = c
	Cars.BY_KIND[c.kind] = c
end

function Cars.get(key: any): any
	return if type(key) == "string" then Cars.BY_KEY[key] else nil
end

function Cars.carId(key: string): string
	return "gwp_" .. key
end

-- "gwp_hyper" -> "hyper"
function Cars.keyOfId(id: any): string?
	if type(id) ~= "string" or string.sub(id, 1, 4) ~= "gwp_" then
		return nil
	end
	local k = string.sub(id, 5)
	return if Cars.BY_KEY[k] then k else nil
end

-- the VS spec of a premium car (a clone of its base kind with our overrides)
function Cars.specFor(VS: any, car: any): any
	local base = VS.Specs[car.spec.base] or VS.Specs.luxury or VS.Specs.sedan
	local s = table.clone(base)
	for k, v in car.spec do
		if k ~= "base" then
			s[k] = v
		end
	end
	s.label = car.label
	s.model = car.label .. " (" .. car.class .. ")"
	return s
end

-- adds the four kinds to a VehicleShared table (server: also drivable / callable)
function Cars.install(VS: any, drivable: boolean)
	if type(VS) ~= "table" or type(VS.Specs) ~= "table" then
		return false
	end
	for _, car in Cars.LIST do
		if VS.Specs[car.kind] == nil then
			VS.Specs[car.kind] = Cars.specFor(VS, car)
		end
		if drivable and type(VS.Drivable) == "table" then
			VS.Drivable[car.kind] = true
		end
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- paints: the 8 GS colours + 6 premium finishes. gs = the GwangalliGarageShared colour id used by other UIs.
---------------------------------------------------------------------------------------------------
Cars.PAINTS = {
	{ id = "white", name = "화이트", rgb = { 238, 239, 238 }, gs = "white" },
	{ id = "black", name = "블랙", rgb = { 18, 19, 21 }, gs = "black", refl = 0.12 },
	{ id = "silver", name = "실버", rgb = { 178, 182, 186 }, gs = "silver", refl = 0.1 },
	{ id = "grey", name = "그레이", rgb = { 96, 100, 104 }, gs = "grey" },
	{ id = "navy", name = "네이비", rgb = { 30, 48, 88 }, gs = "navy", refl = 0.08 },
	{ id = "red", name = "레드", rgb = { 150, 30, 34 }, gs = "red" },
	{ id = "beige", name = "베이지", rgb = { 192, 182, 162 }, gs = "beige" },
	{ id = "mint", name = "민트", rgb = { 142, 170, 160 }, gs = "mint" },
	{ id = "matte_black", name = "매트 블랙", rgb = { 28, 29, 32 }, gs = "black", mat = "SmoothPlastic", refl = 0, premium = true },
	{ id = "pearl", name = "펄 화이트", rgb = { 246, 244, 238 }, gs = "white", refl = 0.22, premium = true },
	{ id = "candy_red", name = "캔디 레드", rgb = { 196, 18, 36 }, gs = "red", refl = 0.18, premium = true },
	{ id = "lime", name = "네온 라임", rgb = { 170, 240, 40 }, gs = "mint", refl = 0.12, premium = true },
	{ id = "purple", name = "미드나잇 퍼플", rgb = { 74, 32, 140 }, gs = "navy", refl = 0.18, premium = true },
	{ id = "gold", name = "샴페인 골드", rgb = { 214, 176, 104 }, gs = "beige", refl = 0.2, premium = true },
	{ id = "sand", name = "샌드 카키", rgb = { 176, 154, 112 }, gs = "beige", premium = true },
}
Cars.PAINT_BY_ID = {}
for _, p in Cars.PAINTS do
	Cars.PAINT_BY_ID[p.id] = p
end

function Cars.paint(id: any): any
	return Cars.PAINT_BY_ID[id or ""] or Cars.PAINT_BY_ID.black
end

function Cars.paintColor(p: any): Color3
	return Color3.fromRGB(p.rgb[1], p.rgb[2], p.rgb[3])
end

-- a stable default plate per player and car ("부산12가 3456" style; VIP: "VIP 1234")
local HANGUL = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조" }
function Cars.defaultPlate(userId: number, key: string): string
	local seed = (math.abs(math.floor(tonumber(userId) or 0)) % 1000003) * 31 + #key * 7 + string.byte(key, 1)
	local rng = Random.new(seed)
	if key == "vip" then
		return string.format("VIP %04d", rng:NextInteger(1000, 9999))
	end
	return string.format("부산%02d%s %04d", rng:NextInteger(10, 99), HANGUL[rng:NextInteger(1, #HANGUL)], rng:NextInteger(1000, 9999))
end

return Cars
