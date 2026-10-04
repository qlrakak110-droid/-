-- GwangalliHomesShared (HS): the 내집마련 인테리어 extension of GwangalliGameplayShared (G).
--   * room list / theme catalog: 벽지 (6) · 바닥 (4) · 조명 (5) per room, priced by home tier
--   * extra furniture catalog (>= 40 procedurally built variants: 가전 / 커튼 / 장식 + more sofas,
--     beds, tables, chairs, lamps, plants, rugs, art, shelves, a projector TV and a gaming desk),
--     each with a pure spec builder in the G.furnitureSpec format (parts = boxes / cylinders / balls)
--   * the saved record extension of a home unit (d.housing.units[listingId]):
--       slots[sid] = variantId        (G, unchanged)
--       rot[sid]   = 1 | 2 | 3        quarter turns of a generated piece (0 = omitted)
--       walls[room] / floors[room] / lights[room] = theme id   (omitted = the template's own look)
--     Old saves have none of these fields: every reader treats a missing table as empty.
--   * HS.extend(G): called by GwangalliGameplayShared at the end of its own require (it hands G over;
--     this module never requires G, so there is no cycle). It registers the catalog, the new home
--     interaction kind "interior", the HomeAction names, and wraps G.sanitizeHousing / G.housingView /
--     G.homeDecor / G.furnitureSpec so every existing caller sees the extended data. G.HOMES = HS.
-- No instances are created here and no Roblox globals are touched at require time (Lune tests).
--
-- TEMPLATE CONTRACT ADDITIONS (build/venues/homes_kit.luau):
--   * shell / fixture parts carry attribute Room = <room id> and Surface = "wall" | "floor" | "light";
--     Light instances carry Room. The server recolours them for the saved themes (Color + Material
--     only, no textures), remembering the original look in OrigColor / OrigMaterial attributes.
--   * FurnitureSlot models may carry Rotate = true (the piece can be turned in 90-degree steps).
--   * a HomeInteract part with Kind "interior" (the wall tablet at the 현관) opens the decorating mode
--     for the owner and the read-only 집 구경 mode for guests.

local HS = {}
HS.VERSION = 2

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-------------------------------------------------------------------------------------------------
-- Rooms
-------------------------------------------------------------------------------------------------
HS.ROOM_ORDER = { "living", "main", "dining", "kitchen", "bedroom", "loft", "study", "dress", "bath", "master_bath", "entry", "veranda", "terrace" }
HS.ROOM_NAMES = {
	living = { name = "거실", icon = "🛋️" },
	dining = { name = "다이닝·바", icon = "🍷" },
	kitchen = { name = "주방", icon = "🍳" },
	bedroom = { name = "침실", icon = "🛏️" },
	loft = { name = "복층 침실", icon = "🪜" },
	study = { name = "서재·작은방", icon = "📚" },
	dress = { name = "드레스룸", icon = "👗" },
	bath = { name = "욕실", icon = "🚿" },
	master_bath = { name = "안방 욕실", icon = "🛁" },
	entry = { name = "현관", icon = "🚪" },
	veranda = { name = "베란다", icon = "🌿" },
	terrace = { name = "테라스", icon = "🌊" },
	main = { name = "방", icon = "🏠" },
}
-- smaller rooms cost less to redo
HS.ROOM_FACTOR = { entry = 0.5, bath = 0.6, master_bath = 0.6, dress = 0.6, veranda = 0.6, loft = 0.8, study = 0.8, dining = 0.9 }
HS.TIER_MULT = { goshiwon = 1, oneroom = 1.4, officetel = 2, apartment = 2.8, penthouse = 4 }

function HS.roomInfo(id: string): any
	return HS.ROOM_NAMES[id] or { name = id, icon = "🏠" }
end

-- Sorts room ids by HS.ROOM_ORDER (unknown ids last, alphabetical).
function HS.sortRooms(ids: { string }): { string }
	local rank = {}
	for i, id in HS.ROOM_ORDER do
		rank[id] = i
	end
	local out = table.clone(ids)
	table.sort(out, function(a, b)
		local ra, rb = rank[a] or 99, rank[b] or 99
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return out
end

-------------------------------------------------------------------------------------------------
-- Theme catalog (Material + Color only)
-------------------------------------------------------------------------------------------------
HS.THEME_KINDS = { "wall", "floor", "light" }
HS.THEME_KIND_NAMES = { wall = { name = "벽지", icon = "🎨" }, floor = { name = "바닥", icon = "🪵" }, light = { name = "조명", icon = "💡" } }
HS.WALLPAPER_ORDER = { "silk_ivory", "warm_beige", "sage_green", "dusty_blue", "concrete", "wood_panel" }
HS.WALLPAPERS = {
	silk_ivory = { name = "실크 아이보리", desc = "기본 실크벽지보다 한 톤 밝은 화이트", color = { 244, 242, 236 }, material = "Plaster", price = 120000, decor = 1 },
	warm_beige = { name = "웜 베이지", desc = "따뜻한 베이지 합지", color = { 226, 212, 190 }, material = "Plaster", price = 150000, decor = 2 },
	sage_green = { name = "세이지 그린", desc = "차분한 올리브 톤 포인트", color = { 190, 204, 184 }, material = "Plaster", price = 180000, decor = 3 },
	dusty_blue = { name = "더스티 블루", desc = "바다 느낌의 회청색", color = { 172, 190, 208 }, material = "Plaster", price = 180000, decor = 3 },
	concrete = { name = "노출 콘크리트", desc = "인더스트리얼 무드", color = { 170, 170, 166 }, material = "Concrete", price = 260000, decor = 4 },
	wood_panel = { name = "월넛 우드패널", desc = "호텔 스위트 느낌의 목재 패널", color = { 112, 80, 56 }, material = "WoodPlanks", price = 420000, decor = 6 },
}
HS.FLOOR_ORDER = { "oak", "walnut", "porcelain", "grey_tile" }
HS.FLOORS = {
	oak = { name = "강마루 오크", desc = "밝은 원목 강마루", color = { 192, 156, 112 }, material = "WoodPlanks", price = 280000, decor = 2 },
	walnut = { name = "월넛 헤링본", desc = "짙은 월넛 톤", color = { 104, 72, 50 }, material = "WoodPlanks", price = 420000, decor = 4 },
	porcelain = { name = "포세린 타일", desc = "호텔식 화이트 포세린", color = { 228, 226, 222 }, material = "Marble", price = 560000, decor = 6 },
	grey_tile = { name = "그레이 타일", desc = "모던 그레이 타일", color = { 146, 146, 144 }, material = "CeramicTiles", price = 380000, decor = 4 },
}
HS.LIGHT_ORDER = { "warm", "neutral", "cool", "amber", "violet" }
HS.LIGHTS = {
	warm = { name = "전구색 3000K", desc = "아늑한 노란빛", color = { 255, 214, 160 }, price = 30000, decor = 1 },
	neutral = { name = "주백색 4000K", desc = "자연광에 가까운 빛", color = { 255, 238, 214 }, price = 30000, decor = 1 },
	cool = { name = "주광색 6500K", desc = "밝고 선명한 흰빛", color = { 236, 244, 255 }, price = 30000, decor = 1 },
	amber = { name = "무드 앰버", desc = "카페 같은 오렌지 무드", color = { 255, 168, 92 }, price = 60000, decor = 3 },
	violet = { name = "네온 바이올렛", desc = "광안대교 야경 톤", color = { 196, 150, 255 }, price = 60000, decor = 3 },
}

function HS.themeCatalog(kind: string): ({ string }, { [string]: any })
	if kind == "wall" then
		return HS.WALLPAPER_ORDER, HS.WALLPAPERS
	elseif kind == "floor" then
		return HS.FLOOR_ORDER, HS.FLOORS
	elseif kind == "light" then
		return HS.LIGHT_ORDER, HS.LIGHTS
	end
	return {}, {}
end

function HS.themeDef(kind: string, id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	local _, t = HS.themeCatalog(kind)
	return t[id]
end

-- Price of a theme for a room of a tier ("default" = back to the template's look, free).
function HS.themePrice(kind: string, id: string, tierKey: string?, room: string?): number
	if id == "default" then
		return 0
	end
	local def = HS.themeDef(kind, id)
	if not def then
		return 0
	end
	local mult = HS.TIER_MULT[tierKey or ""] or 1
	local rf = HS.ROOM_FACTOR[room or ""] or 1
	return math.floor(def.price * mult * rf / 1000 + 0.5) * 1000
end

-------------------------------------------------------------------------------------------------
-- Saved unit record (pure)
-------------------------------------------------------------------------------------------------
local function cleanKey(k: any, maxLen: number): string?
	if type(k) ~= "string" or #k == 0 or #k > maxLen then
		return nil
	end
	return k
end

-- The unit record of the current home, with the extension tables present (creates it).
function HS.unitOf(d: any, listingId: string): any
	local h = d.housing
	if type(h) ~= "table" then
		return nil
	end
	local u = h.units[listingId]
	if not u then
		u = { slots = {} }
		h.units[listingId] = u
	end
	u.rot = u.rot or {}
	u.walls = u.walls or {}
	u.floors = u.floors or {}
	u.lights = u.lights or {}
	return u
end

function HS.rotOf(unit: any, slotId: string): number
	local r = type(unit) == "table" and type(unit.rot) == "table" and unit.rot[slotId] or 0
	return if isFiniteNumber(r) then math.clamp(math.floor(r), 0, 3) else 0
end

-- Sets the quarter turns of a slot (0 clears). Returns ok, reason ("noHome").
function HS.setRot(d: any, slotId: string, rot: number): (boolean, string?)
	if not d.home then
		return false, "noHome"
	end
	local u = HS.unitOf(d, d.home.listingId)
	if not u then
		return false, "noHome"
	end
	local r = math.clamp(math.floor(rot), 0, 3)
	u.rot[slotId] = if r == 0 then nil else r
	return true, nil
end

local function themeTable(unit: any, kind: string): any?
	if type(unit) ~= "table" then
		return nil
	end
	if kind == "wall" then
		return unit.walls
	elseif kind == "floor" then
		return unit.floors
	elseif kind == "light" then
		return unit.lights
	end
	return nil
end

-- { wall = id | false, floor = id | false, light = id | false } of a room.
function HS.themeOf(unit: any, room: string): any
	local out = {}
	for _, kind in HS.THEME_KINDS do
		local t = themeTable(unit, kind)
		out[kind] = (t and t[room]) or false
	end
	return out
end

-- Applies a theme to the saved record (after the caller charged the price). "default" clears it.
function HS.saveTheme(d: any, room: string, kind: string, id: string): boolean
	if not d.home then
		return false
	end
	local u = HS.unitOf(d, d.home.listingId)
	local t = u and themeTable(u, kind)
	if not t then
		return false
	end
	t[room] = if id == "default" then nil else id
	return true
end

-- Validates and copies the extension fields of a raw saved unit into the sanitised one.
function HS.sanitizeUnit(raw: any, unit: any)
	if type(raw) ~= "table" or type(unit) ~= "table" then
		return
	end
	if type(raw.rot) == "table" then
		local rot = {}
		local n = 0
		for sid, r in raw.rot do
			if cleanKey(sid, 40) and isFiniteNumber(r) and n < 40 then
				local q = math.floor(r)
				if q >= 1 and q <= 3 then
					rot[sid] = q
					n += 1
				end
			end
		end
		unit.rot = rot
	end
	for _, kind in HS.THEME_KINDS do
		local field = if kind == "wall" then "walls" elseif kind == "floor" then "floors" else "lights"
		local src = raw[field]
		if type(src) == "table" then
			local out = {}
			local n = 0
			for room, id in src do
				if cleanKey(room, 24) and HS.themeDef(kind, id) and n < 24 then
					out[room] = id
					n += 1
				end
			end
			unit[field] = out
		end
	end
end

-- Decor points of the themes of the current home.
function HS.themeDecor(d: any): number
	local h = d.housing
	if type(h) ~= "table" or not d.home then
		return 0
	end
	local u = h.units and h.units[d.home.listingId]
	if type(u) ~= "table" then
		return 0
	end
	local s = 0
	for _, kind in HS.THEME_KINDS do
		local t = themeTable(u, kind)
		if t then
			for _, id in t do
				local def = HS.themeDef(kind, id)
				if def then
					s += def.decor
				end
			end
		end
	end
	return s
end

-------------------------------------------------------------------------------------------------
-- Catalog groups shown in the decorating UI (category chips)
-------------------------------------------------------------------------------------------------
HS.CATEGORY_GROUPS = {
	{ id = "sofa", name = "소파", icon = "🛋️", cats = { "sofa" } },
	{ id = "bed", name = "침대", icon = "🛏️", cats = { "bed" } },
	{ id = "table", name = "테이블·의자", icon = "🪑", cats = { "table", "chair", "desk" } },
	{ id = "lamp", name = "조명", icon = "💡", cats = { "lamp" } },
	{ id = "rug", name = "러그", icon = "🧶", cats = { "rug" } },
	{ id = "deco", name = "장식·식물", icon = "🪴", cats = { "plant", "art", "deco", "shelf" } },
	{ id = "appliance", name = "가전", icon = "📺", cats = { "tv", "appliance" } },
	{ id = "curtain", name = "커튼", icon = "🪟", cats = { "curtain" } },
}

function HS.groupOf(category: string): any?
	for _, g in HS.CATEGORY_GROUPS do
		for _, c in g.cats do
			if c == category then
				return g
			end
		end
	end
	return nil
end

-- Categories whose pieces may be turned (used by the builder as the slot default; a slot can override).
HS.ROTATABLE_CATEGORIES = { chair = true, plant = true, lamp = true, rug = true, table = true, deco = true, appliance = true }

-- Real lights (PointLight) that placed furniture may add to one home instance (mobile budget; the
-- template itself carries at most 4). Further glowing pieces keep their Neon look without a light.
HS.FURNITURE_LIGHTS = 3
HS.REFUND = 0.5 -- 교체 시 기존 가구 환불율 (= G.FURNITURE_RESALE)
HS.COMPLIMENT_COOLDOWN = 600 -- s between two 칭찬 from the same guest to the same owner

-- May a slot show quarter turn `rot` (0..3)? Generated pieces are rebuilt in the swapped envelope for
-- odd turns, so they always stay inside the footprint; the template's default piece is turned as is,
-- so a long one (|w - d| > 1 stud) only flips 180 degrees.
function HS.rotationAllowed(canRotate: boolean, isDefault: boolean, w: number, d: number, rot: number): boolean
	if type(rot) ~= "number" or rot ~= rot then
		return false
	end
	local r = math.floor(rot) % 4
	if r == 0 then
		return true
	end
	if not canRotate then
		return false
	end
	if isDefault and r % 2 == 1 and math.abs((w or 0) - (d or 0)) > 1 then
		return false
	end
	return true
end

-- Next allowed quarter turn after `rot` (wraps; returns rot itself when nothing else is allowed).
function HS.nextRotation(canRotate: boolean, isDefault: boolean, w: number, d: number, rot: number): number
	for i = 1, 3 do
		local r = (math.floor(rot or 0) + i) % 4
		if HS.rotationAllowed(canRotate, isDefault, w, d, r) then
			return r
		end
	end
	return math.floor(rot or 0) % 4
end

-- Buys / places `variantId` in a slot of the current home (pure, mutates the profile `d`). With
-- `sellOld` the piece being replaced is sold back at HS.REFUND (bank) BEFORE paying, so the refund
-- helps to pay; otherwise it goes to 창고 (G.placeFurniture). Returns ok, info | reason where
-- info = { bought, price, displaced?, refund }, reason as G.placeFurniture.
function HS.buyFurniture(G: any, d: any, slotId: string, slotCategory: string, variantId: string, sellOld: boolean?, now: number?): (boolean, any)
	if not d.home then
		return false, "noHome"
	end
	local f = G.FURNITURE[variantId]
	if not f then
		return false, "unknown"
	end
	if f.category ~= slotCategory then
		return false, "category"
	end
	local h = G.ensureHousing(d)
	local u = h.units[d.home.listingId]
	local current = u and u.slots[slotId] or nil
	if current == variantId then
		return false, "same"
	end
	local refund = 0
	if sellOld and current then
		local fromStorage = (h.storage[variantId] or 0) > 0
		if not fromStorage then
			local resale = G.furnitureResale(current)
			if (d.bank or 0) + resale < f.price and (d.cash or 0) < f.price then
				return false, "insufficient"
			end
		end
		local okS, amt = G.sellSlot(d, slotId, now)
		if okS then
			refund = amt
		end
	end
	local ok, info = G.placeFurniture(d, slotId, slotCategory, variantId, now)
	if not ok then
		return false, info
	end
	info.refund = refund
	if refund > 0 then
		info.displaced = current
		info.sold = true
	end
	return true, info
end

-------------------------------------------------------------------------------------------------
-- Spec helpers (same frame as G.furnitureSpec: origin = slot bottom centre, X right, Y up, front -Z)
-------------------------------------------------------------------------------------------------
local function part(spec: any, name: string, shape: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	local p: any = {
		name = name,
		shape = shape,
		size = { math.max(0.05, sx), math.max(0.05, sy), math.max(0.05, sz) },
		pos = { x, y, z },
		color = color,
		material = material,
	}
	if opts then
		for k, v in opts do
			p[k] = v
		end
	end
	table.insert(spec.parts, p)
	return #spec.parts
end
local function box(spec: any, name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	return part(spec, name, "Block", sx, sy, sz, x, y, z, color, material, opts)
end
-- vertical cylinder (height h, diameter dia) centred at (x, y, z)
local function vcyl(spec: any, name: string, h: number, dia: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	local o = opts or {}
	o.rot = { 0, 0, 90 }
	return part(spec, name, "Cylinder", h, dia, dia, x, y, z, color, material, o)
end
-- cylinder along Z (length l) centred at (x, y, z)
local function zcyl(spec: any, name: string, l: number, dia: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	local o = opts or {}
	o.rot = { 0, 90, 0 }
	return part(spec, name, "Cylinder", l, dia, dia, x, y, z, color, material, o)
end
-- cylinder along X
local function xcyl(spec: any, name: string, l: number, dia: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	return part(spec, name, "Cylinder", l, dia, dia, x, y, z, color, material, opts)
end
local function ball(spec: any, name: string, dia: number, x: number, y: number, z: number, color: { number }, material: string, opts: { [string]: any }?): number
	return part(spec, name, "Ball", dia, dia, dia, x, y, z, color, material, opts)
end
local function shade(c: { number }, k: number): { number }
	return { math.clamp(math.floor(c[1] * k), 0, 255), math.clamp(math.floor(c[2] * k), 0, 255), math.clamp(math.floor(c[3] * k), 0, 255) }
end
local function legs4(spec: any, W: number, D: number, h: number, inset: number, thick: number, color: { number }, material: string, round: boolean)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - inset), sz * (D / 2 - inset)
			if round then
				vcyl(spec, "Leg", h, thick, x, h / 2, z, color, material)
			else
				box(spec, "Leg", thick, h, thick, x, h / 2, z, color, material)
			end
		end
	end
end
local function light(spec: any, idx: number, range: number, brightness: number, color: { number })
	spec.lights = spec.lights or {}
	table.insert(spec.lights, { part = idx, range = range, brightness = brightness, color = color })
end

local WHITE, BLACK, CHARCOAL = { 240, 240, 238 }, { 28, 28, 32 }, { 56, 58, 64 }
local CHROME, BRASS, GOLD = { 206, 208, 212 }, { 196, 156, 96 }, { 212, 175, 55 }
local OAK, WALNUT, CREAM = { 200, 168, 124 }, { 96, 62, 40 }, { 238, 232, 220 }
local GLASS = { 200, 220, 228 }

-------------------------------------------------------------------------------------------------
-- Catalog entries: F(id, category, style, name, price, decor, main, accent, detail?, extra?)
-------------------------------------------------------------------------------------------------
HS.FURNITURE_ORDER = {}
HS.FURNITURE = {}
HS.BUILDERS = {} :: { [string]: (any, number, number, number, any) -> () }

local function F(id: string, category: string, style: string, name: string, price: number, decor: number, main: { number }, accent: { number }, detail: { number }?, build: (any, number, number, number, any) -> ())
	HS.FURNITURE[id] = { name = name, category = category, style = style, price = price, decor = decor, main = main, accent = accent, detail = detail or accent, ext = true }
	table.insert(HS.FURNITURE_ORDER, id)
	HS.BUILDERS[id] = build
end

-- 가전 ---------------------------------------------------------------------------------------------
F("ap_purifier", "appliance", "modern", "공기청정기 (타워형)", 350000, 2, WHITE, { 150, 154, 158 }, { 90, 180, 255 }, function(s, W, H, D, v)
	local w = math.min(W, D, 1.2)
	local h = math.min(H, 2.4)
	box(s, "Body", w, h - 0.1, w, 0, 0.05 + (h - 0.1) / 2, 0, v.main, "SmoothPlastic", { collide = true })
	vcyl(s, "Grille", 0.06, w * 0.8, 0, h - 0.02, 0, v.accent, "SmoothPlastic")
	local led = box(s, "LED", w * 0.5, 0.08, 0.04, 0, h - 0.4, -w / 2 - 0.01, v.detail, "Neon")
	light(s, led, 5, 0.4, v.detail)
end)
F("ap_standac", "appliance", "modern", "스탠드 에어컨 (무풍형)", 1800000, 4, WHITE, { 214, 216, 218 }, { 80, 200, 255 }, function(s, W, H, D, v)
	local w = math.min(W, 1.4)
	local d = math.min(D, 1.1)
	local h = math.min(H, 6)
	box(s, "Body", w, h - 0.1, d, 0, 0.1 + (h - 0.1) / 2, 0, v.main, "SmoothPlastic", { collide = true })
	box(s, "Base", w - 0.1, 0.1, d - 0.1, 0, 0.05, 0, CHARCOAL, "SmoothPlastic")
	box(s, "Vent", w * 0.84, h * 0.4, 0.03, 0, h * 0.72, -d / 2 - 0.01, v.accent, "SmoothPlastic")
	zcyl(s, "Ring", 0.04, 0.7, 0, h * 0.42, -d / 2 - 0.02, { 186, 190, 194 }, "SmoothPlastic")
	box(s, "Display", 0.4, 0.14, 0.03, 0, h * 0.3, -d / 2 - 0.02, v.detail, "Neon")
end)
F("ap_speaker", "appliance", "trendy", "블루투스 스피커 + 스탠드", 420000, 3, CHARCOAL, BLACK, { 61, 214, 245 }, function(s, W, H, D, v)
	local h = math.min(H, 3.6)
	for i = 0, 2 do
		local a = i * 2.094
		box(s, "TripodLeg", 0.08, h * 0.65, 0.08, math.sin(a) * 0.45, h * 0.3, math.cos(a) * 0.45, v.accent, "Metal", { rot = { math.deg(math.cos(a)) * 0.12, 0, -math.deg(math.sin(a)) * 0.12 } })
	end
	box(s, "Speaker", 1.1, 1.3, 0.9, 0, h * 0.6 + 0.65, 0, v.main, "Fabric", { collide = true })
	local ring = zcyl(s, "Ring", 0.04, 0.6, 0, h * 0.6 + 0.65, -0.47, v.detail, "Neon")
	light(s, ring, 4, 0.3, v.detail)
end)
F("ap_fan", "appliance", "ikea", "서큘레이터 선풍기", 60000, 1, WHITE, { 60, 62, 66 }, { 200, 214, 230 }, function(s, W, H, D, v)
	local h = math.min(H, 3)
	vcyl(s, "Base", 0.15, 1.0, 0, 0.075, 0, v.main, "SmoothPlastic")
	vcyl(s, "Pole", h - 0.8, 0.12, 0, 0.15 + (h - 0.8) / 2, 0, v.main, "SmoothPlastic")
	zcyl(s, "Motor", 0.4, 0.45, 0, h - 0.3, 0.1, v.main, "SmoothPlastic")
	zcyl(s, "Guard", 0.18, 1.5, 0, h - 0.3, -0.2, v.detail, "SmoothPlastic", { transparency = 0.45 })
	box(s, "Blade", 1.2, 0.3, 0.02, 0, h - 0.3, -0.2, v.accent, "SmoothPlastic", { rot = { 0, 0, 35 } })
	box(s, "Blade", 1.2, 0.3, 0.02, 0, h - 0.3, -0.2, v.accent, "SmoothPlastic", { rot = { 0, 0, -55 } })
end)
F("ap_styler", "appliance", "luxury", "의류관리기 (스타일러)", 1900000, 4, { 44, 42, 48 }, BLACK, { 150, 160, 170 }, function(s, W, H, D, v)
	local w, d, h = math.min(W, 1.7), math.min(D, 2.0), math.min(H, 6.2)
	box(s, "Body", w, h, d, 0, h / 2, 0, v.main, "SmoothPlastic", { collide = true })
	box(s, "MirrorDoor", w - 0.14, h - 0.3, 0.04, 0, h / 2, -d / 2 - 0.02, v.detail, "Glass", { reflectance = 0.55 })
	box(s, "Handle", 0.08, h * 0.5, 0.1, w / 2 - 0.2, h / 2, -d / 2 - 0.07, v.accent, "Metal")
end)
F("ap_winecooler", "appliance", "luxury", "와인 셀러 (24병)", 1200000, 4, BLACK, { 70, 70, 76 }, { 255, 170, 90 }, function(s, W, H, D, v)
	local w, d, h = math.min(W, 1.8), math.min(D, 1.8), math.min(H, 3.2)
	box(s, "Body", w, h, d, 0, h / 2, 0, v.main, "SmoothPlastic", { collide = true })
	local glow = box(s, "Interior", w - 0.3, h - 0.4, 0.05, 0, h / 2, -d / 2 + 0.1, v.detail, "Neon", { transparency = 0.3 })
	light(s, glow, 4, 0.35, v.detail)
	for i = 0, 2 do
		local y = 0.5 + i * (h - 0.8) / 3
		for j = -1, 1 do
			zcyl(s, "Bottle", 0.9, 0.22, j * (w / 4), y + 0.3, -d / 2 + 0.45, { 60, 24, 32 }, "Glass")
		end
	end
	box(s, "Door", w - 0.1, h - 0.1, 0.04, 0, h / 2, -d / 2 - 0.02, GLASS, "Glass", { transparency = 0.55 })
	box(s, "Handle", 0.06, h * 0.6, 0.08, w / 2 - 0.2, h / 2, -d / 2 - 0.06, CHROME, "Metal")
end)
F("ap_robot", "appliance", "modern", "로봇청소기 + 충전 도크", 390000, 1, WHITE, CHARCOAL, { 90, 220, 180 }, function(s, W, H, D, v)
	local _ = H
	box(s, "Dock", 0.8, 0.9, 0.3, 0, 0.45, D / 2 - 0.2, v.accent, "SmoothPlastic")
	vcyl(s, "Robot", 0.3, math.min(W, 1.1), 0, 0.15, D / 2 - 0.8, v.main, "SmoothPlastic")
	vcyl(s, "Lidar", 0.08, 0.25, 0, 0.34, D / 2 - 0.8, v.accent, "SmoothPlastic")
	box(s, "LED", 0.3, 0.05, 0.03, 0, 0.6, D / 2 - 0.37, v.detail, "Neon")
end)
F("ap_coffee", "appliance", "cozy", "캡슐 커피머신 + 미니 바", 250000, 2, OAK, BLACK, { 236, 226, 206 }, function(s, W, H, D, v)
	local w, d = math.min(W, 1.6), math.min(D, 1.2)
	local h = math.min(H * 0.5, 2.6)
	box(s, "Top", w, 0.12, d, 0, h, 0, v.main, "Wood", { collide = true })
	legs4(s, w, d, h - 0.06, 0.12, 0.1, v.accent, "Metal", false)
	box(s, "Machine", 0.55, 0.9, 0.7, -w / 4, h + 0.51, 0.05, v.accent, "SmoothPlastic")
	box(s, "Lever", 0.12, 0.08, 0.5, -w / 4, h + 0.98, -0.1, CHROME, "Metal")
	for i = 0, 1 do
		vcyl(s, "Cup", 0.3, 0.3, w / 4 - 0.25 + i * 0.4, h + 0.21, -0.1, v.detail, "SmoothPlastic")
	end
	box(s, "Capsules", 0.5, 0.3, 0.3, w / 4, h + 0.21, 0.3, { 120, 40, 60 }, "SmoothPlastic")
end)

-- 커튼 (W = window width + overlap, H = rail height; the wall is on +Z) -------------------------------
local function curtainPanels(s: any, W: number, H: number, D: number, color: { number }, pw: number, z: number, thick: number)
	for _, side in { -1, 1 } do
		local x = side * (W / 2 - pw / 2)
		box(s, "Curtain", pw, H - 0.35, thick, x, 0.15 + (H - 0.35) / 2, z, color, "Fabric", { collide = false })
		box(s, "Fold", pw - 0.4, H - 0.4, thick * 0.6, x + side * 0.05, 0.15 + (H - 0.4) / 2, z - thick * 0.7, shade(color, 0.93), "Fabric")
	end
	local _ = D
end
F("cu_linen", "curtain", "cozy", "린넨 커튼 (아이보리)", 180000, 2, { 232, 224, 208 }, CHARCOAL, { 246, 244, 238 }, function(s, W, H, D, v)
	xcyl(s, "Rail", W + 0.4, 0.1, 0, H - 0.12, D / 2 - 0.3, v.accent, "Metal")
	curtainPanels(s, W, H, D, v.main, math.max(1.2, W * 0.2), D / 2 - 0.45, 0.25)
end)
F("cu_blackout", "curtain", "modern", "암막 커튼 (차콜)", 260000, 2, { 70, 72, 78 }, { 40, 40, 42 }, { 90, 92, 98 }, function(s, W, H, D, v)
	box(s, "RailBox", W + 0.5, 0.3, 0.4, 0, H - 0.15, D / 2 - 0.3, v.accent, "SmoothPlastic")
	curtainPanels(s, W, H, D, v.main, math.max(1.6, W * 0.26), D / 2 - 0.55, 0.3)
end)
F("cu_sheer", "curtain", "ikea", "쉬어 커튼 (화이트)", 90000, 1, { 248, 246, 240 }, WHITE, { 236, 236, 232 }, function(s, W, H, D, v)
	xcyl(s, "Rail", W + 0.4, 0.08, 0, H - 0.12, D / 2 - 0.3, v.accent, "SmoothPlastic")
	box(s, "Sheer", W, H - 0.35, 0.06, 0, 0.15 + (H - 0.35) / 2, D / 2 - 0.4, v.main, "Fabric", { transparency = 0.5 })
	for i = 1, math.max(2, math.floor(W / 1.6)) do
		local x = -W / 2 + (i - 0.5) * W / math.max(2, math.floor(W / 1.6))
		box(s, "Wave", 0.5, H - 0.5, 0.05, x, 0.2 + (H - 0.5) / 2, D / 2 - 0.47, v.detail, "Fabric", { transparency = 0.45 })
	end
end)
F("cu_velvet", "curtain", "luxury", "벨벳 커튼 (네이비) + 골드 레일", 650000, 5, { 36, 48, 84 }, GOLD, { 212, 175, 55 }, function(s, W, H, D, v)
	xcyl(s, "Rail", W + 0.6, 0.14, 0, H - 0.1, D / 2 - 0.3, v.accent, "Metal")
	for _, side in { -1, 1 } do
		ball(s, "Finial", 0.3, side * (W / 2 + 0.3), H - 0.1, D / 2 - 0.3, v.accent, "Metal")
	end
	curtainPanels(s, W, H, D, v.main, math.max(1.6, W * 0.24), D / 2 - 0.5, 0.3)
	for _, side in { -1, 1 } do
		box(s, "Tieback", math.max(1.6, W * 0.24) + 0.1, 0.18, 0.45, side * (W / 2 - math.max(1.6, W * 0.24) / 2), H * 0.42, D / 2 - 0.5, v.detail, "Metal")
	end
end)
F("cu_wood_blind", "curtain", "modern", "우드 블라인드", 320000, 3, { 150, 112, 76 }, { 120, 88, 58 }, { 60, 60, 62 }, function(s, W, H, D, v)
	box(s, "HeadBox", W, 0.3, 0.35, 0, H - 0.15, D / 2 - 0.25, v.accent, "Wood")
	local n = 8
	local drop = H * 0.72
	for i = 1, n do
		local y = H - 0.3 - (i - 0.5) * drop / n
		box(s, "Slat", W - 0.2, 0.05, 0.3, 0, y, D / 2 - 0.25, v.main, "Wood", { rot = { 28, 0, 0 } })
	end
	box(s, "Cord", 0.03, drop, 0.03, W / 2 - 0.3, H - 0.3 - drop / 2, D / 2 - 0.08, v.detail, "SmoothPlastic")
end)
F("cu_roller", "curtain", "ikea", "롤스크린 (그레이)", 70000, 1, { 196, 196, 198 }, WHITE, { 60, 60, 62 }, function(s, W, H, D, v)
	xcyl(s, "Roll", W, 0.3, 0, H - 0.15, D / 2 - 0.22, v.accent, "SmoothPlastic")
	box(s, "Screen", W - 0.1, H * 0.6, 0.04, 0, H - 0.3 - H * 0.3, D / 2 - 0.2, v.main, "Fabric")
	box(s, "Bar", W - 0.1, 0.08, 0.08, 0, H - 0.3 - H * 0.6, D / 2 - 0.2, v.detail, "Metal")
end)

-- 장식 ---------------------------------------------------------------------------------------------
F("dc_sculpture", "deco", "luxury", "추상 조형 오브제 (대리석 받침)", 900000, 5, { 236, 232, 226 }, GOLD, BLACK, function(s, W, H, D, v)
	local w = math.min(W, D, 1.4)
	box(s, "Plinth", w, 2.2, w, 0, 1.1, 0, v.main, "Marble", { collide = true })
	ball(s, "Sphere", w * 0.6, 0, 2.2 + w * 0.3 + 0.1, 0, v.accent, "Metal")
	box(s, "Blade", 0.12, math.min(H - 2.4, 2.0), w * 0.7, 0, 2.3 + math.min(H - 2.4, 2.0) / 2, 0, v.detail, "Metal", { rot = { 0, 35, 12 } })
end)
F("dc_candles", "deco", "cozy", "캔들 트레이 세트", 45000, 1, { 236, 228, 212 }, { 60, 60, 62 }, { 255, 200, 120 }, function(s, W, H, D, v)
	local _ = H
	box(s, "Stand", math.min(W, 1.2), 1.6, math.min(D, 0.8), 0, 0.8, 0, OAK, "Wood", { collide = true })
	box(s, "Tray", math.min(W, 1.2) - 0.1, 0.06, math.min(D, 0.8) - 0.1, 0, 1.63, 0, v.accent, "Metal")
	local hs = { 0.5, 0.8, 0.35 }
	for i, h in hs do
		local x = (i - 2) * 0.32
		vcyl(s, "Candle", h, 0.24, x, 1.66 + h / 2, (i - 2) * 0.1, v.main, "SmoothPlastic")
		local fl = ball(s, "Flame", 0.09, x, 1.66 + h + 0.06, (i - 2) * 0.1, v.detail, "Neon")
		if i == 2 then
			light(s, fl, 5, 0.5, v.detail)
		end
	end
end)
F("dc_vase", "deco", "cozy", "유리 화병 + 튤립", 60000, 2, GLASS, { 70, 130, 70 }, { 240, 110, 130 }, function(s, W, H, D, v)
	local _ = H
	box(s, "Stand", math.min(W, 1.1), 2.0, math.min(D, 1.1), 0, 1.0, 0, WHITE, "SmoothPlastic", { collide = true })
	vcyl(s, "Vase", 1.1, 0.5, 0, 2.55, 0, v.main, "Glass", { transparency = 0.4 })
	for i = -1, 1 do
		box(s, "Stem", 0.04, 1.3, 0.04, i * 0.12, 3.5, i * 0.08, v.accent, "SmoothPlastic", { rot = { 0, 0, i * 12 } })
		ball(s, "Tulip", 0.26, i * 0.28, 4.2, i * 0.1, if i == 0 then { 255, 196, 90 } else v.detail, "SmoothPlastic")
	end
end)
F("dc_floorclock", "deco", "modern", "플로어 시계 (슬림)", 280000, 3, WALNUT, BRASS, WHITE, function(s, W, H, D, v)
	local h = math.min(H, 6)
	box(s, "Case", 0.9, h, math.min(D, 0.7), 0, h / 2, 0, v.main, "Wood", { collide = true })
	zcyl(s, "Face", 0.05, 0.7, 0, h - 0.7, -math.min(D, 0.7) / 2 - 0.02, v.detail, "SmoothPlastic")
	box(s, "Hand", 0.04, 0.3, 0.02, 0, h - 0.56, -math.min(D, 0.7) / 2 - 0.05, BLACK, "SmoothPlastic")
	box(s, "Hand", 0.04, 0.22, 0.02, 0.08, h - 0.68, -math.min(D, 0.7) / 2 - 0.05, BLACK, "SmoothPlastic", { rot = { 0, 0, 70 } })
	vcyl(s, "Pendulum", h * 0.45, 0.06, 0, h * 0.45, 0, v.accent, "Metal")
	ball(s, "Bob", 0.3, 0, h * 0.22, 0, v.accent, "Metal")
	local _ = W
end)
F("dc_ledtree", "deco", "trendy", "LED 미니 트리", 120000, 3, { 40, 96, 54 }, { 110, 80, 50 }, { 255, 214, 120 }, function(s, W, H, D, v)
	local _ = D
	local h = math.min(H, 3.6)
	vcyl(s, "Pot", 0.5, 0.9, 0, 0.25, 0, v.accent, "Slate")
	vcyl(s, "Tier", h * 0.35, math.min(W, 1.6), 0, 0.5 + h * 0.175, 0, v.main, "Grass")
	vcyl(s, "Tier", h * 0.3, math.min(W, 1.6) * 0.72, 0, 0.5 + h * 0.5, 0, shade(v.main, 1.08), "Grass")
	vcyl(s, "Tier", h * 0.25, math.min(W, 1.6) * 0.42, 0, 0.5 + h * 0.77, 0, shade(v.main, 1.15), "Grass")
	for i = 0, 5 do
		local a = i * 1.05
		local r = 0.3 + (i % 3) * 0.2
		local y = 0.8 + i * (h - 1.2) / 6
		local b = ball(s, "Bulb", 0.12, math.cos(a) * r, y, math.sin(a) * r, if i % 2 == 0 then v.detail else { 255, 120, 160 }, "Neon")
		if i == 2 then
			light(s, b, 5, 0.5, v.detail)
		end
	end
	ball(s, "Star", 0.22, 0, 0.5 + h * 0.9 + 0.1, 0, v.detail, "Neon")
end)
F("dc_books", "deco", "modern", "아트북 스택 + 오브제", 85000, 2, { 236, 232, 222 }, { 40, 60, 90 }, { 200, 160, 90 }, function(s, W, H, D, v)
	local _ = H
	box(s, "Stand", math.min(W, 1.3), 1.4, math.min(D, 1.0), 0, 0.7, 0, CHARCOAL, "SmoothPlastic", { collide = true })
	local cols = { v.main, v.accent, { 200, 60, 60 }, v.main }
	for i = 1, 4 do
		box(s, "Book", 0.9 - i * 0.05, 0.14, 0.7, (i % 2) * 0.05, 1.4 + (i - 0.5) * 0.14, 0, cols[i], "SmoothPlastic", { rot = { 0, (i % 2) * 8, 0 } })
	end
	ball(s, "Objet", 0.32, 0.1, 1.4 + 0.56 + 0.16, 0, v.detail, "Metal")
end)
F("dc_diffuser", "deco", "cozy", "디퓨저 + 우드 트레이", 40000, 1, { 230, 214, 180 }, OAK, { 180, 160, 130 }, function(s, W, H, D, v)
	local _ = H
	box(s, "Stand", math.min(W, 1.0), 1.5, math.min(D, 0.9), 0, 0.75, 0, WHITE, "SmoothPlastic", { collide = true })
	box(s, "Tray", 0.8, 0.05, 0.6, 0, 1.525, 0, v.accent, "Wood")
	box(s, "Bottle", 0.3, 0.45, 0.3, -0.15, 1.78, 0, v.main, "Glass", { transparency = 0.25 })
	for i = -1, 1 do
		box(s, "Stick", 0.02, 0.7, 0.02, -0.15 + i * 0.05, 2.3, i * 0.04, v.detail, "SmoothPlastic", { rot = { i * 12, 0, i * 10 } })
	end
	vcyl(s, "Candle", 0.3, 0.28, 0.2, 1.7, 0.05, { 236, 230, 220 }, "SmoothPlastic")
end)
F("dc_figures", "deco", "trendy", "피규어 진열 큐브 (LED)", 210000, 3, BLACK, GLASS, { 61, 214, 245 }, function(s, W, H, D, v)
	local w = math.min(W, D, 1.3)
	local h = math.min(H, 2.6)
	box(s, "Base", w, 0.3, w, 0, 0.15, 0, v.main, "SmoothPlastic", { collide = true })
	local led = box(s, "LEDBase", w - 0.2, 0.04, w - 0.2, 0, 0.32, 0, v.detail, "Neon")
	light(s, led, 4, 0.3, v.detail)
	box(s, "Cube", w - 0.1, h - 0.4, w - 0.1, 0, 0.34 + (h - 0.4) / 2, 0, v.accent, "Glass", { transparency = 0.6 })
	local cols = { { 255, 90, 90 }, { 90, 150, 255 }, { 255, 210, 80 } }
	for i, c in cols do
		box(s, "Figure", 0.22, 0.6, 0.22, (i - 2) * 0.32, 0.64, 0, c, "SmoothPlastic")
		ball(s, "FigureHead", 0.22, (i - 2) * 0.32, 1.02, 0, { 250, 220, 200 }, "SmoothPlastic")
	end
end)
F("dc_mirror", "deco", "modern", "전신 거울 (스탠딩)", 150000, 2, { 40, 40, 42 }, GLASS, WHITE, function(s, W, H, D, v)
	local h = math.min(H, 5.6)
	local w = math.min(W, 1.8)
	box(s, "Frame", w, h, 0.08, 0, h / 2 + 0.05, 0.05, v.main, "Metal", { rot = { -6, 0, 0 }, collide = true })
	box(s, "Mirror", w - 0.14, h - 0.14, 0.03, 0, h / 2 + 0.05, -0.01, v.accent, "Glass", { rot = { -6, 0, 0 }, reflectance = 0.6 })
	local _ = D
end)

-- 소파 ---------------------------------------------------------------------------------------------
F("sofa_boucle_modular", "sofa", "cozy", "부클레 모듈 소파", 1600000, 8, { 238, 232, 220 }, { 220, 210, 192 }, { 170, 150, 120 }, function(s, W, H, D, v)
	local seatTop = math.min(1.35, H * 0.45)
	local n = if W > 7 then 3 else 2
	local mw = W / n
	for i = 1, n do
		local x = -W / 2 + mw * (i - 0.5)
		box(s, "Module", mw - 0.08, seatTop, D, x, seatTop / 2, 0, v.main, "Fabric", { collide = true })
		box(s, "Back", mw - 0.08, math.min(H, 2.5) - seatTop, 0.9, x, seatTop + (math.min(H, 2.5) - seatTop) / 2, D / 2 - 0.45, shade(v.main, 0.97), "Fabric", { collide = true })
	end
	box(s, "Arm", 0.7, math.min(H, 1.9), D, -W / 2 + 0.35, math.min(H, 1.9) / 2, 0, v.accent, "Fabric", { collide = true })
	box(s, "Pillow", 1.1, 1.0, 0.35, W / 2 - 1.4, seatTop + 0.5, D / 2 - 1.1, v.detail, "Fabric")
	box(s, "Throw", 1.6, 0.12, D - 0.6, -W / 2 + 1.6, seatTop + 0.06, 0, v.detail, "Fabric")
	s.seat = { pos = { 0, seatTop, -0.3 } }
end)
F("sofa_recliner", "sofa", "modern", "전동 리클라이너 소파 (2인)", 2400000, 7, { 64, 66, 72 }, BLACK, { 120, 124, 130 }, function(s, W, H, D, v)
	local seatTop = math.min(1.5, H * 0.5)
	local w2 = (W - 1.0) / 2
	for _, side in { -1, 1 } do
		local x = side * (w2 / 2 + 0.5)
		box(s, "Seat", w2, seatTop - 0.2, D - 0.6, x, 0.2 + (seatTop - 0.2) / 2, 0, v.main, "Leather", { collide = true })
		box(s, "Back", w2, math.min(H, 3.2) - seatTop, 0.9, x, seatTop + (math.min(H, 3.2) - seatTop) / 2, D / 2 - 0.45, v.main, "Leather", { collide = true })
		box(s, "Headrest", w2 - 0.3, 0.6, 0.5, x, math.min(H, 3.2) - 0.2, D / 2 - 0.7, shade(v.main, 1.1), "Leather")
		box(s, "Footrest", w2 - 0.3, 0.3, 1.3, x, seatTop - 0.5, -D / 2 - 0.4, v.main, "Leather")
	end
	box(s, "Console", 1.0, seatTop + 0.3, D - 0.6, 0, (seatTop + 0.3) / 2, 0, v.accent, "SmoothPlastic", { collide = true })
	vcyl(s, "Cup", 0.05, 0.5, 0, seatTop + 0.33, -0.3, v.detail, "Metal")
	box(s, "Base", W - 0.4, 0.2, D - 0.8, 0, 0.1, 0, v.accent, "SmoothPlastic")
	s.seat = { pos = { -(w2 / 2 + 0.5), seatTop, -0.2 } }
end)
F("sofa_rattan", "sofa", "cozy", "라탄 2인 소파", 520000, 4, { 170, 130, 84 }, { 232, 220, 200 }, { 110, 140, 110 }, function(s, W, H, D, v)
	local seatTop = math.min(1.5, H * 0.5)
	legs4(s, W, D, 0.5, 0.3, 0.2, shade(v.main, 0.8), "Wood", true)
	box(s, "Frame", W, 0.5, D, 0, 0.75, 0, v.main, "Wood", { collide = true })
	box(s, "Back", W, math.min(H, 2.8) - 1.0, 0.3, 0, 1.0 + (math.min(H, 2.8) - 1.0) / 2, D / 2 - 0.15, v.main, "Wood", { collide = true })
	for _, side in { -1, 1 } do
		box(s, "Arm", 0.3, 1.4, D, side * (W / 2 - 0.15), 1.7, 0, v.main, "Wood", { collide = true })
	end
	box(s, "Cushion", W - 0.7, seatTop - 1.0, D - 0.5, 0, 1.0 + (seatTop - 1.0) / 2, -0.1, v.accent, "Fabric")
	box(s, "BackCushion", W - 0.7, 1.3, 0.4, 0, seatTop + 0.65, D / 2 - 0.5, v.accent, "Fabric")
	box(s, "Pillow", 1.0, 0.9, 0.3, W / 2 - 1.1, seatTop + 0.45, D / 2 - 0.8, v.detail, "Fabric")
	s.seat = { pos = { 0, seatTop, -0.2 } }
end)

-- 침대 ---------------------------------------------------------------------------------------------
F("bed_platform_low", "bed", "modern", "저상형 플랫폼 침대 (LED)", 980000, 5, { 196, 196, 200 }, WALNUT, { 255, 214, 160 }, function(s, W, H, D, v)
	box(s, "Platform", W, 0.5, D, 0, 0.25, 0, v.accent, "Wood", { collide = true })
	local led = box(s, "LEDStrip", W - 0.2, 0.04, D - 0.2, 0, 0.08, 0, v.detail, "Neon", { transparency = 0.2 })
	light(s, led, 8, 0.5, v.detail)
	box(s, "Mattress", W - 0.8, 0.7, D - 1.2, 0, 0.85, -0.3, { 246, 246, 248 }, "Fabric", { collide = true })
	box(s, "Duvet", W - 0.7, 0.2, (D - 1.2) * 0.62, 0, 1.3, -D / 2 + 0.75 + (D - 1.2) * 0.31, v.main, "Fabric")
	box(s, "Headboard", W, math.min(H, 2.6) - 0.5, 0.3, 0, 0.5 + (math.min(H, 2.6) - 0.5) / 2, D / 2 - 0.15, v.accent, "Wood", { collide = true })
	for i = 1, 2 do
		box(s, "Pillow", (W - 1.2) / 2 - 0.2, 0.35, 1.0, -W / 4 + (i - 1) * W / 2 + (if i == 1 then 0.1 else -0.1), 1.37, D / 2 - 1.1, { 250, 250, 252 }, "Fabric")
	end
	s.bed = { pos = { 0, 1.2, -0.3 } }
end)
F("bed_canopy", "bed", "luxury", "캐노피 침대 (화이트)", 3600000, 11, { 246, 244, 240 }, { 232, 226, 214 }, GOLD, function(s, W, H, D, v)
	local h = math.min(H, 7.5)
	box(s, "Frame", W, 0.9, D, 0, 0.45, 0, v.accent, "Fabric", { collide = true })
	box(s, "Mattress", W - 0.4, 0.75, D - 0.8, 0, 1.27, -0.2, { 246, 246, 248 }, "Fabric", { collide = true })
	box(s, "Duvet", W - 0.3, 0.22, (D - 0.8) * 0.6, 0, 1.75, -D / 2 + 0.6 + (D - 0.8) * 0.3, v.main, "Fabric")
	box(s, "Headboard", W, 2.8, 0.3, 0, 1.4, D / 2 - 0.15, v.accent, "Fabric", { collide = true })
	legs4(s, W, D, h, 0.15, 0.14, v.detail, "Metal", false)
	box(s, "TopRail", W, 0.08, 0.08, 0, h - 0.04, -D / 2 + 0.15, v.detail, "Metal")
	box(s, "TopRail", W, 0.08, 0.08, 0, h - 0.04, D / 2 - 0.15, v.detail, "Metal")
	box(s, "TopRail", 0.08, 0.08, D, -W / 2 + 0.15, h - 0.04, 0, v.detail, "Metal")
	box(s, "TopRail", 0.08, 0.08, D, W / 2 - 0.15, h - 0.04, 0, v.detail, "Metal")
	for _, sx in { -1, 1 } do
		box(s, "Drape", 0.6, h - 0.2, 0.08, sx * (W / 2 - 0.45), h / 2, -D / 2 + 0.2, { 250, 250, 248 }, "Fabric", { transparency = 0.45 })
	end
	for i = 1, 2 do
		box(s, "Pillow", (W - 1.0) / 2 - 0.2, 0.4, 1.1, -W / 4 + (i - 1) * W / 2, 1.85, D / 2 - 1.0, { 250, 250, 252 }, "Fabric")
	end
	s.bed = { pos = { 0, 1.65, -0.2 } }
end)
F("bed_bunk", "bed", "ikea", "2층 침대 (원목)", 420000, 3, { 120, 160, 200 }, OAK, { 236, 100, 90 }, function(s, W, H, D, v)
	local h = math.min(H, 7.2)
	legs4(s, W, D, h, 0.15, 0.25, v.accent, "Wood", false)
	for lvl, y in { 0.9, h - 2.4 } do
		box(s, "Frame", W, 0.35, D, 0, y, 0, v.accent, "Wood", { collide = true })
		box(s, "Mattress", W - 0.4, 0.5, D - 0.4, 0, y + 0.42, 0, { 246, 246, 248 }, "Fabric", { collide = true })
		box(s, "Duvet", W - 0.3, 0.16, (D - 0.4) * 0.6, 0, y + 0.75, -D / 2 + 0.3 + (D - 0.4) * 0.3, if lvl == 1 then v.main else v.detail, "Fabric")
		box(s, "Pillow", W * 0.5, 0.3, 0.9, 0, y + 0.8, D / 2 - 0.8, { 250, 250, 252 }, "Fabric")
	end
	box(s, "Rail", W - 0.5, 0.1, 0.1, 0, h - 1.4, -D / 2 + 0.1, v.accent, "Wood")
	for i = 1, 5 do
		box(s, "Ladder", 0.7, 0.08, 0.08, W / 2 - 0.5, 0.6 + i * (h - 2.6) / 5, -D / 2 - 0.3, v.accent, "Wood")
	end
	box(s, "LadderRail", 0.08, h - 2.2, 0.08, W / 2 - 0.85, (h - 2.2) / 2 + 0.4, -D / 2 - 0.3, v.accent, "Wood")
	box(s, "LadderRail", 0.08, h - 2.2, 0.08, W / 2 - 0.15, (h - 2.2) / 2 + 0.4, -D / 2 - 0.3, v.accent, "Wood")
	s.bed = { pos = { 0, 1.4, 0 } }
end)

-- 테이블 ---------------------------------------------------------------------------------------------
F("table_lowfloor", "table", "cozy", "좌식 원목 테이블 + 쿠션", 140000, 2, OAK, { 214, 196, 170 }, { 120, 140, 170 }, function(s, W, H, D, v)
	local _ = H
	local tw, td = math.min(W, 4.0), math.min(D, 2.2)
	box(s, "Top", tw, 0.12, td, 0, 1.1, 0, v.main, "Wood", { collide = true })
	legs4(s, tw, td, 1.04, 0.3, 0.18, v.main, "Wood", false)
	for _, side in { -1, 1 } do
		local z = side * (td / 2 + 0.6)
		if math.abs(z) + 0.6 <= D / 2 + 0.3 then
			box(s, "Cushion", 1.4, 0.3, 1.2, 0, 0.15, z, if side < 0 then v.accent else v.detail, "Fabric")
		end
	end
	vcyl(s, "Teapot", 0.5, 0.5, -0.6, 1.41, 0, { 236, 236, 232 }, "SmoothPlastic")
	vcyl(s, "Cup", 0.25, 0.3, 0.6, 1.285, 0.2, { 236, 236, 232 }, "SmoothPlastic")
end)
F("table_glass", "table", "modern", "글라스 다이닝 테이블 (2인)", 1100000, 6, GLASS, CHROME, WHITE, function(s, W, H, D, v)
	local tw, td = math.min(W, 4.6), math.min(D, 2.8)
	box(s, "Top", tw, 0.1, td, 0, 2.5, 0, v.main, "Glass", { transparency = 0.4, collide = true })
	legs4(s, tw, td, 2.45, 0.25, 0.12, v.accent, "Metal", true)
	for _, sx in { -1, 1 } do
		local x = sx * (tw / 2 + 0.4)
		if math.abs(x) + 0.8 <= W / 2 + 0.6 then
			box(s, "ChairSeat", 1.4, 0.15, 1.4, x, 1.5, 0, v.detail, "SmoothPlastic", { collide = true })
			box(s, "ChairBack", 0.12, 1.5, 1.4, x + sx * 0.64, 2.3, 0, v.detail, "SmoothPlastic")
			legs4(s, 1.4, 1.4, 1.45, 0.1, 0.08, v.accent, "Metal", true)
			-- legs4 centred at the origin: move them under the chair
			for i = #s.parts - 3, #s.parts do
				s.parts[i].pos[1] += x
			end
		end
	end
	local _ = H
	s.seat = { pos = { -(tw / 2 + 0.4), 1.5, 0 } }
end)
F("table_side_set", "table", "modern", "사이드 테이블 세트 (네스팅)", 190000, 2, BLACK, GOLD, { 236, 232, 226 }, function(s, W, H, D, v)
	local _ = H
	local _ = D
	vcyl(s, "Top", 0.1, math.min(W * 0.6, 2.0), -W * 0.15, 1.7, 0, v.main, "Metal", { collide = true })
	vcyl(s, "Stem", 1.65, 0.12, -W * 0.15, 0.83, 0, v.accent, "Metal")
	vcyl(s, "Base", 0.06, 1.2, -W * 0.15, 0.03, 0, v.main, "Metal")
	vcyl(s, "Top", 0.1, math.min(W * 0.45, 1.5), W * 0.3, 1.35, 0.2, v.detail, "Marble", { collide = true })
	vcyl(s, "Stem", 1.3, 0.1, W * 0.3, 0.65, 0.2, v.accent, "Metal")
	vcyl(s, "Base", 0.06, 0.9, W * 0.3, 0.03, 0.2, v.accent, "Metal")
	vcyl(s, "Mug", 0.3, 0.3, -W * 0.15, 1.9, 0, { 236, 236, 232 }, "SmoothPlastic")
end)

-- 의자 ---------------------------------------------------------------------------------------------
F("chair_beanbag", "chair", "cozy", "빈백 소파 (머스타드)", 95000, 2, { 214, 160, 60 }, { 190, 140, 50 }, { 236, 226, 206 }, function(s, W, H, D, v)
	local _ = H
	local dia = math.min(W, D, 2.6)
	ball(s, "Bag", dia, 0, dia * 0.42, 0, v.main, "Fabric", { collide = true })
	ball(s, "Fold", dia * 0.7, 0, dia * 0.72, dia * 0.28, v.accent, "Fabric")
	box(s, "Tag", 0.3, 0.2, 0.05, dia * 0.3, dia * 0.5, -dia * 0.38, v.detail, "Fabric")
	s.seat = { pos = { 0, dia * 0.55, -0.2 } }
end)
F("chair_rocking", "chair", "cozy", "라탄 흔들의자", 260000, 3, { 170, 130, 84 }, { 232, 220, 200 }, { 120, 88, 58 }, function(s, W, H, D, v)
	local w = math.min(W, 2.0)
	for _, sx in { -1, 1 } do
		box(s, "Rocker", 0.1, 0.12, math.min(D, 2.6), sx * (w / 2 - 0.08), 0.06, 0, v.detail, "Wood")
		box(s, "Post", 0.1, 1.3, 0.1, sx * (w / 2 - 0.08), 0.75, -0.6, v.main, "Wood")
		box(s, "Post", 0.1, 1.3, 0.1, sx * (w / 2 - 0.08), 0.75, 0.6, v.main, "Wood")
		box(s, "ArmRest", 0.12, 0.1, 1.6, sx * (w / 2 - 0.08), 2.1, 0.1, v.main, "Wood")
		box(s, "ArmPost", 0.1, 0.8, 0.1, sx * (w / 2 - 0.08), 1.7, -0.5, v.main, "Wood")
	end
	box(s, "Seat", w - 0.1, 0.15, 1.5, 0, 1.4, 0, v.main, "Wood", { collide = true })
	box(s, "Back", w - 0.1, math.min(H, 3.4) - 1.4, 0.15, 0, 1.4 + (math.min(H, 3.4) - 1.4) / 2, 0.68, v.main, "Wood", { rot = { -10, 0, 0 }, collide = true })
	box(s, "Cushion", w - 0.4, 0.2, 1.2, 0, 1.57, -0.05, v.accent, "Fabric")
	s.seat = { pos = { 0, 1.55, 0 } }
end)
F("chair_barstool_set", "chair", "modern", "바 스툴 2개 (블랙)", 240000, 2, BLACK, CHROME, { 150, 110, 80 }, function(s, W, H, D, v)
	local sh = math.min(H - 0.3, 2.6)
	for i = -1, 1, 2 do
		local x = i * math.min(W / 4, 0.75)
		vcyl(s, "Foot", 0.08, 1.3, x, 0.04, 0, v.main, "Metal")
		vcyl(s, "Post", sh - 0.2, 0.2, x, sh / 2, 0, v.accent, "Metal")
		vcyl(s, "FootRing", 0.06, 1.0, x, sh * 0.35, 0, v.accent, "Metal")
		vcyl(s, "Seat", 0.25, 1.3, x, sh - 0.12, 0, v.detail, "Leather", { collide = true })
		box(s, "Back", 1.1, 0.8, 0.12, x, sh + 0.4, 0.55, v.detail, "Leather")
	end
	local _ = D
	s.seat = { pos = { -math.min(W / 4, 0.75), sh, 0 } }
end)
F("chair_gaming", "chair", "trendy", "게이밍 체어 (RGB)", 380000, 3, BLACK, { 200, 40, 60 }, { 255, 60, 120 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	for i = 0, 4 do
		local a = i * 1.2566
		box(s, "Star", 0.14, 0.12, 1.1, math.sin(a) * 0.55, 0.2, math.cos(a) * 0.55, v.main, "SmoothPlastic", { rot = { 0, math.deg(a), 0 } })
	end
	vcyl(s, "Lift", 1.2, 0.2, 0, 0.8, 0, CHARCOAL, "Metal")
	box(s, "Seat", 1.7, 0.4, 1.7, 0, 1.6, 0, v.main, "Leather", { collide = true })
	box(s, "SeatTrim", 1.72, 0.1, 1.72, 0, 1.4, 0, v.accent, "Leather")
	box(s, "Back", 1.7, math.min(H, 4.4) - 1.8, 0.3, 0, 1.8 + (math.min(H, 4.4) - 1.8) / 2, 0.7, v.main, "Leather", { rot = { -6, 0, 0 }, collide = true })
	box(s, "BackStripe", 0.3, math.min(H, 4.4) - 2.2, 0.05, -0.5, 1.9 + (math.min(H, 4.4) - 2.2) / 2, 0.52, v.accent, "Leather", { rot = { -6, 0, 0 } })
	box(s, "BackStripe", 0.3, math.min(H, 4.4) - 2.2, 0.05, 0.5, 1.9 + (math.min(H, 4.4) - 2.2) / 2, 0.52, v.accent, "Leather", { rot = { -6, 0, 0 } })
	local rgb = box(s, "RGB", 0.08, math.min(H, 4.4) - 2.4, 0.06, 0, 2.0 + (math.min(H, 4.4) - 2.4) / 2, 0.86, v.detail, "Neon", { rot = { -6, 0, 0 } })
	light(s, rgb, 5, 0.4, v.detail)
	for _, sx in { -1, 1 } do
		box(s, "Arm", 0.2, 0.15, 1.0, sx * 0.95, 2.3, -0.1, v.main, "SmoothPlastic")
		box(s, "ArmPost", 0.15, 0.6, 0.15, sx * 0.95, 1.95, 0.2, v.main, "SmoothPlastic")
	end
	s.seat = { pos = { 0, 1.8, 0 } }
end)

-- 조명 ---------------------------------------------------------------------------------------------
F("lamp_moon", "lamp", "trendy", "달 무드등 (3D 문라이트)", 55000, 2, { 250, 236, 200 }, { 60, 60, 62 }, { 255, 230, 180 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	local _ = H
	box(s, "Stand", 1.0, 1.4, 1.0, 0, 0.7, 0, v.accent, "Wood", { collide = true })
	box(s, "Cradle", 0.6, 0.12, 0.6, 0, 1.46, 0, v.accent, "Wood")
	local moon = ball(s, "Moon", 1.1, 0, 2.05, 0, v.main, "Neon")
	light(s, moon, 9, 0.6, v.detail)
end)
F("lamp_tripod", "lamp", "modern", "트라이포드 스탠드 (드럼 쉐이드)", 240000, 3, { 236, 232, 222 }, { 120, 88, 58 }, { 255, 224, 180 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	local h = math.min(H, 5.4)
	for i = 0, 2 do
		local a = i * 2.094 + 0.3
		box(s, "Leg", 0.1, h - 1.2, 0.1, math.sin(a) * 0.5, (h - 1.2) / 2, math.cos(a) * 0.5, v.accent, "Wood", { rot = { math.cos(a) * 11, 0, -math.sin(a) * 11 } })
	end
	vcyl(s, "Shade", 1.2, 1.5, 0, h - 0.6, 0, v.main, "Fabric")
	local bulb = vcyl(s, "Glow", 1.0, 1.3, 0, h - 0.6, 0, v.detail, "Neon", { transparency = 0.25 })
	light(s, bulb, 11, 0.7, v.detail)
end)
F("lamp_neon_tube", "lamp", "trendy", "네온 튜브 스탠드 (3색)", 180000, 3, { 255, 79, 163 }, { 40, 40, 42 }, { 61, 214, 245 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	local h = math.min(H, 4.8)
	box(s, "Base", 1.2, 0.15, 1.2, 0, 0.075, 0, v.accent, "Metal", { collide = true })
	local cols = { v.main, v.detail, { 139, 108, 255 } }
	for i, c in cols do
		local t = vcyl(s, "Tube", h - 0.3 - (i - 1) * 0.5, 0.12, (i - 2) * 0.3, 0.15 + (h - 0.3 - (i - 1) * 0.5) / 2, (i - 2) * 0.12, c, "Neon")
		if i == 1 then
			light(s, t, 10, 0.7, c)
		end
	end
end)

-- 식물 ---------------------------------------------------------------------------------------------
F("plant_cactus_set", "plant", "cozy", "선인장 3종 세트 (테라코타)", 45000, 1, { 86, 140, 76 }, { 196, 110, 70 }, { 230, 190, 100 }, function(s, W, H, D, v)
	local _ = H
	local _ = D
	local offs = { { -0.5, 0.1, 0.6, 1.1 }, { 0.2, -0.3, 0.5, 0.7 }, { 0.6, 0.35, 0.4, 0.5 } }
	for i, o in offs do
		local x, z, pw, ph = o[1] * math.min(W, 1.8) / 1.6, o[2], o[3], o[4]
		vcyl(s, "Pot", pw * 0.9, pw, x, pw * 0.45, z, v.accent, "Slate")
		vcyl(s, "Cactus", ph, pw * 0.5, x, pw * 0.9 + ph / 2, z, v.main, "Grass")
		if i == 1 then
			vcyl(s, "Arm", 0.4, 0.2, x + 0.3, pw * 0.9 + ph * 0.6, z, v.main, "Grass", { rot = { 0, 0, 0 } })
		end
		if i == 3 then
			ball(s, "Flower", 0.18, x, pw * 0.9 + ph + 0.05, z, v.detail, "SmoothPlastic")
		end
	end
end)
F("plant_eucalyptus", "plant", "cozy", "유칼립투스 화병", 70000, 2, { 140, 170, 140 }, GLASS, { 110, 150, 120 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	local _ = H
	box(s, "Stand", 1.1, 1.8, 1.1, 0, 0.9, 0, WHITE, "SmoothPlastic", { collide = true })
	vcyl(s, "Vase", 1.2, 0.6, 0, 2.4, 0, v.accent, "Glass", { transparency = 0.4 })
	for i = -1, 1 do
		box(s, "Stem", 0.04, 1.6, 0.04, i * 0.15, 3.6, i * 0.1, v.detail, "SmoothPlastic", { rot = { i * 8, 0, i * 14 } })
		ball(s, "Leaves", 0.5, i * 0.42, 4.1 + (i % 2) * 0.3, i * 0.2, v.main, "LeafyGrass")
		ball(s, "Leaves", 0.4, i * 0.25, 4.5 - (i % 2) * 0.2, -i * 0.15, shade(v.main, 1.08), "LeafyGrass")
	end
end)
F("plant_hanging", "plant", "trendy", "행잉 플랜트 스탠드", 160000, 3, { 80, 140, 80 }, BLACK, { 230, 220, 200 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	local h = math.min(H, 6)
	vcyl(s, "Base", 0.1, 1.2, 0, 0.05, 0, v.accent, "Metal", { collide = true })
	vcyl(s, "Pole", h - 0.1, 0.1, -0.35, h / 2, 0, v.accent, "Metal")
	box(s, "Hook", 0.9, 0.08, 0.08, 0.1, h - 0.06, 0, v.accent, "Metal")
	box(s, "Rope", 0.04, 1.2, 0.04, 0.5, h - 0.7, 0, v.detail, "Fabric")
	vcyl(s, "Pot", 0.9, 1.1, 0.5, h - 1.75, 0, v.detail, "Fabric")
	ball(s, "Leaves", 1.3, 0.5, h - 1.2, 0, v.main, "LeafyGrass")
	box(s, "Trail", 0.3, 1.6, 0.3, 0.9, h - 2.4, 0.1, shade(v.main, 0.9), "LeafyGrass", { rot = { 0, 0, -12 } })
	box(s, "Trail", 0.25, 1.2, 0.25, 0.2, h - 2.3, -0.3, shade(v.main, 1.1), "LeafyGrass", { rot = { 10, 0, 8 } })
end)

-- 러그 ---------------------------------------------------------------------------------------------
F("rug_checker", "rug", "trendy", "체커보드 러그", 180000, 3, { 236, 232, 222 }, { 40, 40, 44 }, { 200, 196, 186 }, function(s, W, H, D, v)
	local _ = H
	local cols, rows = 4, 3
	local cw, ch = (W - 0.4) / cols, (D - 0.4) / rows
	box(s, "Border", W, 0.06, D, 0, 0.03, 0, v.detail, "Fabric")
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			if (i + j) % 2 == 0 then
				box(s, "Check", cw, 0.03, ch, -W / 2 + 0.2 + cw * (i + 0.5), 0.075, -D / 2 + 0.2 + ch * (j + 0.5), v.accent, "Fabric")
			end
		end
	end
	box(s, "Field", W - 0.4, 0.02, D - 0.4, 0, 0.07, 0, v.main, "Fabric")
end)
F("rug_shaggy_round", "rug", "cozy", "샤기 라운드 러그 (크림)", 120000, 2, { 240, 234, 222 }, { 226, 216, 198 }, { 214, 200, 176 }, function(s, W, H, D, v)
	local _ = H
	local dia = math.min(W, D)
	vcyl(s, "Rug", 0.14, dia, 0, 0.07, 0, v.main, "Fabric")
	vcyl(s, "Ring", 0.04, dia * 0.7, 0, 0.16, 0, v.accent, "Fabric")
	vcyl(s, "Center", 0.02, dia * 0.35, 0, 0.19, 0, v.detail, "Fabric")
end)

-- 액자·아트 (wall on +Z, hung in front of it toward -Z) -----------------------------------------------
F("art_neon_sign", "art", "trendy", "네온 사인 (GWANGAN NIGHT)", 420000, 5, { 255, 79, 163 }, { 30, 30, 34 }, { 61, 214, 245 }, function(s, W, H, D, v)
	local _ = D
	box(s, "Backing", W, H, 0.1, 0, H / 2, 0.05, v.accent, "SmoothPlastic", { transparency = 0.2 })
	local strips = { { -W * 0.3, H * 0.62, W * 0.3, 0.1, 0 }, { -W * 0.3, H * 0.38, W * 0.5, 0.1, 0 }, { W * 0.2, H * 0.55, 0.1, H * 0.4, 0 }, { W * 0.32, H * 0.62, W * 0.22, 0.1, -20 } }
	for i, st in strips do
		local p = box(s, "Neon", st[3], st[4], 0.1, st[1], st[2], -0.08, if i % 2 == 0 then v.detail else v.main, "Neon", { rot = { 0, 0, st[5] } })
		if i == 1 then
			light(s, p, 10, 0.8, v.main)
		end
	end
	box(s, "Neon", W * 0.5, 0.08, 0.1, 0, H * 0.18, -0.08, v.main, "Neon")
end)
F("art_poster_set", "art", "ikea", "포스터 3종 세트 (바다·달·커피)", 60000, 2, { 236, 232, 222 }, { 40, 40, 44 }, { 60, 110, 150 }, function(s, W, H, D, v)
	local _ = D
	local pw = (W - 0.4) / 3
	local cols = { v.detail, { 255, 210, 120 }, { 150, 100, 70 } }
	for i = 1, 3 do
		local x = -W / 2 + 0.2 + pw * (i - 0.5)
		box(s, "Frame", pw - 0.15, H - 0.2, 0.1, x, H / 2, 0.05, v.accent, "Wood")
		box(s, "Poster", pw - 0.4, H - 0.45, 0.03, x, H / 2, -0.02, v.main, "SmoothPlastic")
		if i == 2 then
			ball(s, "Moon", math.min(pw, H) * 0.35, x, H * 0.55, -0.06, cols[i], "SmoothPlastic")
		else
			box(s, "Motif", pw - 0.7, (H - 0.45) * 0.4, 0.02, x, H * 0.45, -0.04, cols[i], "SmoothPlastic")
		end
	end
end)
F("art_led_mirror", "art", "modern", "LED 라운드 거울", 390000, 4, GLASS, { 60, 60, 62 }, { 255, 240, 220 }, function(s, W, H, D, v)
	local _ = D
	local dia = math.min(W, H) - 0.1
	local halo = zcyl(s, "Halo", 0.06, dia + 0.3, 0, H / 2, 0.06, v.detail, "Neon")
	light(s, halo, 8, 0.5, v.detail)
	zcyl(s, "Frame", 0.08, dia + 0.05, 0, H / 2, -0.02, v.accent, "Metal")
	zcyl(s, "Mirror", 0.04, dia - 0.1, 0, H / 2, -0.07, v.main, "Glass", { reflectance = 0.6 })
end)

-- 수납·선반 (wall on +Z) ---------------------------------------------------------------------------
F("shelf_glass_cabinet", "shelf", "luxury", "유리 장식장 (LED)", 1900000, 8, BLACK, GLASS, { 255, 214, 160 }, function(s, W, H, D, v)
	box(s, "Back", W, H, 0.1, 0, H / 2, D / 2 - 0.05, v.main, "SmoothPlastic", { collide = true })
	box(s, "Side", 0.1, H, D, -W / 2 + 0.05, H / 2, 0, v.main, "Metal", { collide = true })
	box(s, "Side", 0.1, H, D, W / 2 - 0.05, H / 2, 0, v.main, "Metal", { collide = true })
	box(s, "Top", W, 0.1, D, 0, H - 0.05, 0, v.main, "Metal")
	box(s, "Base", W, 0.4, D, 0, 0.2, 0, v.main, "Metal", { collide = true })
	local rows = 3
	local items = { { 236, 230, 220 }, { 212, 175, 55 }, { 40, 60, 90 }, { 150, 40, 70 } }
	for i = 1, rows do
		local y = 0.4 + (H - 0.5) * i / (rows + 1)
		box(s, "Shelf", W - 0.2, 0.06, D - 0.15, 0, y, 0, v.accent, "Glass", { transparency = 0.45 })
		local led = box(s, "LED", W - 0.4, 0.03, 0.05, 0, y + 0.035, D / 2 - 0.12, v.detail, "Neon")
		if i == 2 then
			light(s, led, 6, 0.4, v.detail)
		end
		for j = 1, 2 do
			local c = items[((i + j) % #items) + 1]
			if (i + j) % 2 == 0 then
				vcyl(s, "Item", 0.7, 0.32, -W / 4 + (j - 1) * W / 2, y + 0.38, 0, c, "Glass")
			else
				box(s, "Item", 0.4, 0.5, 0.3, -W / 4 + (j - 1) * W / 2, y + 0.28, 0, c, "SmoothPlastic")
			end
		end
	end
	box(s, "Door", W - 0.2, H - 0.6, 0.03, 0, 0.4 + (H - 0.6) / 2, -D / 2 + 0.03, v.accent, "Glass", { transparency = 0.7 })
end)
F("shelf_record", "shelf", "trendy", "레코드 선반 + 턴테이블", 680000, 5, OAK, BLACK, { 200, 60, 60 }, function(s, W, H, D, v)
	local h = math.min(H, 2.8)
	box(s, "Body", W, h, D, 0, h / 2, 0, v.main, "Wood", { collide = true })
	box(s, "Divider", 0.08, h - 0.2, D - 0.1, 0, h / 2, 0, shade(v.main, 0.9), "Wood")
	for i = 1, 6 do
		local x = -W / 2 + 0.35 + (i - 1) * (W / 2 - 0.6) / 5
		box(s, "Record", 0.09, h - 0.5, D - 0.4, x, (h - 0.5) / 2 + 0.2, -0.05, if i % 3 == 0 then v.detail elseif i % 3 == 1 then v.accent else { 236, 232, 222 }, "SmoothPlastic", { rot = { 0, 0, -6 } })
	end
	box(s, "Records", W / 2 - 0.4, h - 0.5, D - 0.5, W / 4, (h - 0.5) / 2 + 0.2, 0, shade(v.accent, 1.4), "SmoothPlastic")
	box(s, "Turntable", math.min(W / 2 - 0.2, 1.8), 0.25, math.min(D - 0.2, 1.5), -W / 4, h + 0.125, 0, v.accent, "SmoothPlastic")
	vcyl(s, "Platter", 0.05, 1.2, -W / 4, h + 0.28, 0, v.detail, "SmoothPlastic")
	box(s, "Tonearm", 0.06, 0.05, 0.9, -W / 4 + 0.6, h + 0.33, 0.2, CHROME, "Metal", { rot = { 0, 25, 0 } })
	box(s, "Speaker", 0.9, 1.4, 0.9, W / 4, h + 0.7, 0, v.accent, "Fabric")
end)

-- TV / 책상 ----------------------------------------------------------------------------------------
F("tv_projector", "tv", "trendy", "빔 프로젝터 + 100인치 스크린", 1500000, 6, { 246, 246, 248 }, BLACK, { 70, 72, 80 }, function(s, W, H, D, v)
	box(s, "Cabinet", W * 0.7, 1.4, math.min(D, 1.4), 0, 0.7, 0, v.detail, "SmoothPlastic", { collide = true })
	box(s, "ScreenCase", W, 0.3, 0.3, 0, H - 0.15, D / 2 - 0.2, v.accent, "Metal")
	local scr = box(s, "Screen", W - 0.3, H - 2.0, 0.06, 0, 1.6 + (H - 2.0) / 2, D / 2 - 0.2, v.main, "SmoothPlastic")
	box(s, "ScreenBar", W - 0.3, 0.1, 0.1, 0, 1.55, D / 2 - 0.2, v.accent, "Metal")
	box(s, "Projector", 0.9, 0.4, 0.8, 0, 1.6, -0.1, v.accent, "SmoothPlastic")
	zcyl(s, "Lens", 0.1, 0.3, 0.25, 1.62, -0.52, { 40, 60, 90 }, "Glass")
	box(s, "Soundbar", W * 0.5, 0.25, 0.3, 0, 1.52, -0.45, v.detail, "SmoothPlastic")
	s.screen = scr
end)
F("desk_gaming", "desk", "trendy", "게이밍 데스크 (RGB)", 560000, 4, BLACK, { 40, 40, 44 }, { 61, 214, 245 }, function(s, W, H, D, v)
	box(s, "Top", W, 0.12, D, 0, 2.5, 0, v.main, "SmoothPlastic", { collide = true })
	local rgb = box(s, "RGBEdge", W - 0.2, 0.04, 0.04, 0, 2.42, -D / 2 + 0.02, v.detail, "Neon")
	light(s, rgb, 6, 0.5, v.detail)
	box(s, "Leg", 0.3, 2.44, D - 0.3, -W / 2 + 0.25, 1.22, 0, v.accent, "Metal", { collide = true })
	box(s, "Leg", 0.3, 2.44, D - 0.3, W / 2 - 0.25, 1.22, 0, v.accent, "Metal", { collide = true })
	for i = -1, 1 do
		box(s, "Monitor", W * 0.28, W * 0.17, 0.08, i * W * 0.28, 2.56 + 0.5 + W * 0.085, D / 2 - 0.35 + math.abs(i) * 0.08, v.accent, "SmoothPlastic", { rot = { 0, -i * 22, 0 } })
		box(s, "MonitorScreen", W * 0.26, W * 0.15, 0.03, i * W * 0.275, 2.56 + 0.5 + W * 0.085, D / 2 - 0.4 + math.abs(i) * 0.08, if i == 0 then { 40, 70, 110 } else { 70, 40, 110 }, "Neon", { rot = { 0, -i * 22, 0 } })
	end
	box(s, "MonitorStand", 0.6, 0.5, 0.3, 0, 2.81, D / 2 - 0.4, v.accent, "Metal")
	box(s, "Keyboard", 1.6, 0.06, 0.55, 0, 2.59, -D / 2 + 0.6, v.accent, "SmoothPlastic")
	box(s, "KeyGlow", 1.5, 0.02, 0.45, 0, 2.63, -D / 2 + 0.6, { 255, 79, 163 }, "Neon", { transparency = 0.3 })
	box(s, "Mouse", 0.25, 0.1, 0.4, 1.1, 2.61, -D / 2 + 0.6, v.accent, "SmoothPlastic")
	box(s, "Tower", 0.9, 1.9, 1.6, W / 2 - 0.9, 0.95, 0.1, v.main, "SmoothPlastic", { collide = true })
	box(s, "TowerGlass", 0.03, 1.6, 1.3, W / 2 - 1.36, 0.95, 0.1, v.detail, "Neon", { transparency = 0.5 })
end)

-- 주방 (v2) -----------------------------------------------------------------------------------------
F("kt_fridge", "kitchen", "modern", "양문형 냉장고 (메탈)", 2400000, 4, { 206, 210, 214 }, { 60, 62, 66 }, { 90, 200, 255 }, function(s, W, H, D, v)
	local w, h, d = math.min(W, 3.0), math.min(H, 6.2), math.min(D, 2.4)
	box(s, "Body", w, h, d - 0.1, 0, h / 2, 0.05, v.main, "Metal", { collide = true })
	box(s, "DoorL", w / 2 - 0.04, h - 0.1, 0.1, -w / 4, h / 2, -d / 2 + 0.05, v.main, "Metal")
	box(s, "DoorR", w / 2 - 0.04, h - 0.1, 0.1, w / 4, h / 2, -d / 2 + 0.05, shade(v.main, 0.96), "Metal")
	box(s, "Gap", 0.03, h - 0.1, 0.12, 0, h / 2, -d / 2 + 0.04, v.accent, "SmoothPlastic")
	for _, sx in { -1, 1 } do
		box(s, "Handle", 0.08, h * 0.45, 0.1, sx * 0.14, h * 0.55, -d / 2 - 0.06, v.accent, "Metal")
	end
	box(s, "Display", 0.5, 0.26, 0.02, -w / 4, h * 0.66, -d / 2 - 0.01, v.detail, "Neon")
end)
F("kt_kimchi", "kitchen", "modern", "김치냉장고 (스탠드형)", 1500000, 3, { 232, 226, 220 }, { 120, 116, 112 }, { 200, 120, 90 }, function(s, W, H, D, v)
	local w, h, d = math.min(W, 2.0), math.min(H, 5.6), math.min(D, 2.3)
	box(s, "Body", w, h, d, 0, h / 2, 0, v.main, "SmoothPlastic", { collide = true })
	for _, y in { h * 0.78, h * 0.5, h * 0.24 } do
		box(s, "Seam", w - 0.1, 0.03, 0.04, 0, y + h * 0.13, -d / 2 - 0.01, v.accent, "SmoothPlastic")
		box(s, "Handle", w * 0.5, 0.08, 0.1, 0, y + h * 0.1, -d / 2 - 0.05, v.accent, "Metal")
	end
	box(s, "Panel", 0.4, 0.2, 0.02, w / 2 - 0.35, h - 0.3, -d / 2 - 0.02, v.detail, "Neon")
end)
F("kt_microwave", "kitchen", "ikea", "전자레인지 + 밥솥 세트", 260000, 2, WHITE, CHARCOAL, { 255, 170, 80 }, function(s, W, H, D, v)
	local _ = H
	local d = math.min(D, 1.2)
	box(s, "Microwave", 1.1, 0.7, d, -W / 2 + 0.6, 0.35, 0, v.main, "SmoothPlastic", { collide = true })
	box(s, "Door", 0.75, 0.55, 0.03, -W / 2 + 0.48, 0.36, -d / 2 - 0.01, v.accent, "Glass", { transparency = 0.3 })
	box(s, "Keypad", 0.2, 0.5, 0.03, -W / 2 + 1.02, 0.36, -d / 2 - 0.01, CHARCOAL, "SmoothPlastic")
	box(s, "Time", 0.14, 0.08, 0.02, -W / 2 + 1.02, 0.55, -d / 2 - 0.03, v.detail, "Neon")
	vcyl(s, "Cooker", 0.6, 0.62, W / 2 - 0.36, 0.3, 0, { 236, 232, 228 }, "SmoothPlastic", { collide = true })
	vcyl(s, "Lid", 0.08, 0.6, W / 2 - 0.36, 0.64, 0, CHARCOAL, "SmoothPlastic")
	box(s, "CookerLED", 0.16, 0.05, 0.02, W / 2 - 0.36, 0.4, -0.32, v.detail, "Neon")
end)
F("kt_island", "kitchen", "luxury", "아일랜드 식탁 + 바 스툴", 3200000, 9, { 240, 238, 234 }, { 70, 64, 60 }, { 196, 156, 96 }, function(s, W, H, D, v)
	local _ = H
	local w, d = math.min(W, 6.4), math.min(D, 3.2)
	local ch = 3.0
	box(s, "Base", w - 0.4, ch - 0.12, d - 1.0, 0, (ch - 0.12) / 2, 0.3, v.accent, "Wood", { collide = true })
	box(s, "Top", w, 0.14, d - 0.4, 0, ch - 0.05, 0.1, v.main, "Marble", { collide = true })
	box(s, "Kick", w - 0.5, 0.2, 0.05, 0, 0.1, 0.3 - (d - 1.0) / 2 - 0.02, BLACK, "SmoothPlastic")
	for i = -1, 1, 2 do
		local x = i * w * 0.24
		vcyl(s, "StoolSeat", 0.18, 1.0, x, 2.1, -d / 2 + 0.5, CREAM, "Fabric", { collide = true })
		vcyl(s, "StoolPole", 1.9, 0.12, x, 1.05, -d / 2 + 0.5, v.detail, "Metal")
		vcyl(s, "StoolBase", 0.06, 0.8, x, 0.03, -d / 2 + 0.5, v.detail, "Metal")
	end
	box(s, "Bowl", 0.8, 0.3, 0.8, w * 0.3, ch + 0.17, 0.2, { 240, 240, 236 }, "SmoothPlastic")
	for i = 0, 2 do
		ball(s, "Fruit", 0.28, w * 0.3 - 0.2 + i * 0.2, ch + 0.38, 0.2 + (i % 2) * 0.1, if i == 1 then { 240, 180, 40 } else { 200, 40, 40 }, "SmoothPlastic")
	end
end)
F("kt_dishrack", "kitchen", "cozy", "식기 건조대 + 그릇", 55000, 1, CHROME, { 236, 232, 224 }, { 120, 160, 190 }, function(s, W, H, D, v)
	local _ = H
	local w, d = math.min(W, 1.6), math.min(D, 1.0)
	box(s, "Tray", w, 0.06, d, 0, 0.03, 0, v.main, "Metal", { collide = true })
	for _, sx in { -1, 1 } do
		box(s, "Rail", 0.04, 0.5, d, sx * (w / 2 - 0.05), 0.3, 0, v.main, "Metal")
	end
	for i = 0, 3 do
		xcyl(s, "Plate", 0.05, 0.7, -w / 2 + 0.3 + i * 0.14, 0.42, 0, if i % 2 == 0 then v.accent else v.detail, "SmoothPlastic")
	end
	vcyl(s, "Cup", 0.3, 0.26, w / 2 - 0.3, 0.21, -0.2, v.detail, "SmoothPlastic")
	vcyl(s, "Cup", 0.3, 0.26, w / 2 - 0.3, 0.21, 0.2, v.accent, "SmoothPlastic")
end)

-- 욕실 (v2) -----------------------------------------------------------------------------------------
F("bt_cabinet", "bath", "modern", "욕실 수납장 (거울 도어)", 280000, 2, WHITE, GLASS, CHROME, function(s, W, H, D, v)
	local w, h, d = math.min(W, 2.2), math.min(H, 2.6), math.min(D, 0.6)
	box(s, "Body", w, h, d - 0.04, 0, h / 2, 0.02, v.main, "SmoothPlastic", { collide = true })
	box(s, "Mirror", w - 0.12, h - 0.12, 0.03, 0, h / 2, -d / 2 + 0.01, v.accent, "Glass")
	box(s, "Shelf", w - 0.1, 0.06, d - 0.1, 0, 0.03, 0, v.main, "SmoothPlastic")
	box(s, "LED", w - 0.3, 0.04, 0.04, 0, h - 0.04, -d / 2, { 255, 244, 226 }, "Neon")
end)
F("bt_towel", "bath", "cozy", "수건 선반 + 호텔 수건", 90000, 2, CHROME, { 246, 244, 238 }, { 180, 200, 220 }, function(s, W, H, D, v)
	local _ = H
	local w, d = math.min(W, 2.4), math.min(D, 0.8)
	box(s, "Shelf", w, 0.06, d, 0, 1.3, 0, v.main, "Metal", { collide = true })
	xcyl(s, "Bar", w - 0.1, 0.06, 0, 0.9, -d / 2 + 0.1, v.main, "Metal")
	for _, sx in { -1, 1 } do
		box(s, "Bracket", 0.06, 0.6, d, sx * (w / 2 - 0.1), 1.0, 0, v.main, "Metal")
	end
	for i = 0, 3 do
		zcyl(s, "Towel", d - 0.15, 0.36, -w / 2 + 0.35 + i * 0.55, 1.52, 0, if i % 2 == 0 then v.accent else v.detail, "Fabric")
	end
	box(s, "Hanging", w * 0.6, 0.8, 0.06, 0, 0.55, -d / 2 + 0.12, v.accent, "Fabric")
end)
F("bt_mat", "bath", "cozy", "규조토 발매트", 35000, 1, { 214, 206, 190 }, { 190, 180, 160 }, WHITE, function(s, W, H, D, v)
	local _ = H
	box(s, "Mat", math.min(W, 2.4), 0.06, math.min(D, 1.6), 0, 0.03, 0, v.main, "Slate", { collide = true })
	box(s, "Line", math.min(W, 2.4) - 0.3, 0.01, 0.06, 0, 0.065, 0, v.accent, "SmoothPlastic")
end)
F("bt_basket", "bath", "cozy", "라탄 빨래 바구니", 45000, 1, { 176, 136, 90 }, { 236, 232, 224 }, { 120, 160, 200 }, function(s, W, H, D, v)
	local _ = W
	local _ = D
	local h = math.min(H, 1.8)
	vcyl(s, "Basket", h, 1.2, 0, h / 2, 0, v.main, "Wood", { collide = true })
	vcyl(s, "Rim", 0.1, 1.26, 0, h - 0.05, 0, shade(v.main, 0.85), "Wood")
	ball(s, "Laundry", 0.8, 0.1, h - 0.05, 0, v.accent, "Fabric")
	ball(s, "Laundry", 0.6, -0.2, h + 0.05, 0.15, v.detail, "Fabric")
end)
F("bt_toiletries", "bath", "modern", "욕실 소품 세트 (디스펜서·칫솔컵)", 40000, 1, WHITE, { 90, 140, 160 }, { 236, 200, 120 }, function(s, W, H, D, v)
	local _ = H
	local _ = D
	box(s, "Tray", math.min(W, 1.2), 0.05, 0.5, 0, 0.025, 0, { 60, 60, 62 }, "Slate", { collide = true })
	vcyl(s, "Dispenser", 0.55, 0.28, -0.35, 0.33, 0, v.main, "SmoothPlastic")
	box(s, "Pump", 0.06, 0.14, 0.14, -0.35, 0.67, -0.04, CHROME, "Metal")
	vcyl(s, "Cup", 0.4, 0.26, 0.05, 0.25, 0, v.accent, "SmoothPlastic")
	for _, i in { -1, 1 } do
		box(s, "Brush", 0.04, 0.5, 0.04, 0.05 + i * 0.05, 0.6, 0, if i < 0 then v.detail else { 120, 200, 140 }, "SmoothPlastic", { rot = { 0, 0, i * 8 } })
	end
	vcyl(s, "Bottle", 0.45, 0.22, 0.4, 0.28, 0.05, v.detail, "SmoothPlastic")
end)

-- TV · 콘솔 (v2) ------------------------------------------------------------------------------------
F("tv_wall", "tv", "luxury", "벽걸이 75인치 TV + 사운드바", 3800000, 8, { 24, 24, 28 }, BLACK, { 70, 72, 80 }, function(s, W, H, D, v)
	local w = math.min(W, 7.0)
	local h = math.min(H, 4.2)
	local d = math.min(D, 0.35)
	box(s, "Frame", w, h * 0.78, 0.12, 0, h * 0.22 + h * 0.39, d / 2 - 0.08, v.main, "SmoothPlastic", { collide = true })
	s.screen = box(s, "TVScreen", w - 0.12, h * 0.78 - 0.12, 0.02, 0, h * 0.22 + h * 0.39, d / 2 - 0.15, { 12, 12, 16 }, "Glass")
	box(s, "Soundbar", w * 0.62, 0.3, 0.3, 0, 0.15, d / 2 - 0.15, v.accent, "Fabric")
	box(s, "BarLED", 0.12, 0.04, 0.02, w * 0.25, 0.2, d / 2 - 0.31, { 255, 255, 255 }, "Neon")
end)
F("ap_console", "appliance", "trendy", "게임 콘솔 + 무선 패드 2개", 620000, 3, WHITE, BLACK, { 61, 140, 255 }, function(s, W, H, D, v)
	local _ = H
	local _ = W
	local _ = D
	box(s, "Console", 0.4, 1.3, 1.0, -0.5, 0.65, 0, v.main, "SmoothPlastic", { collide = true })
	box(s, "Core", 0.12, 1.2, 0.9, -0.5, 0.65, 0, v.accent, "SmoothPlastic")
	box(s, "LightBar", 0.02, 0.9, 0.04, -0.29, 0.65, -0.48, v.detail, "Neon")
	for i = 0, 1 do
		local x = 0.15 + i * 0.5
		box(s, "Pad", 0.42, 0.1, 0.26, x, 0.05, -0.1 + i * 0.12, if i == 0 then v.main else v.accent, "SmoothPlastic", { rot = { 0, i * 20 - 10, 0 } })
		ball(s, "Stick", 0.08, x - 0.08, 0.12, -0.1 + i * 0.12, BLACK, "SmoothPlastic")
	end
end)

-- 장식 (v2): 어항 · 쿠션 · 벽시계 · 벽 선반 · 벽거울 · 포토 액자 ------------------------------------------
F("dc_aquarium", "deco", "luxury", "열대어 수초 어항 + 캐비닛", 1300000, 7, GLASS, { 40, 40, 44 }, { 80, 170, 255 }, function(s, W, H, D, v)
	local _ = H
	local w, d = math.min(W, 3.2), math.min(D, 1.4)
	local base = 2.2
	box(s, "Stand", w, base, d, 0, base / 2, 0, v.accent, "Wood", { collide = true })
	local th = 1.9
	box(s, "Gravel", w - 0.12, 0.2, d - 0.12, 0, base + 0.12, 0, { 214, 196, 160 }, "Pebble")
	box(s, "Water", w - 0.14, th - 0.35, d - 0.14, 0, base + 0.2 + (th - 0.35) / 2, 0, { 60, 140, 200 }, "Glass", { transparency = 0.55 })
	box(s, "Tank", w, th, d, 0, base + th / 2, 0, v.main, "Glass", { transparency = 0.8 })
	box(s, "Lid", w, 0.1, d, 0, base + th + 0.05, 0, v.accent, "SmoothPlastic")
	for i = -2, 2 do
		local ph = 0.6 + ((i + 3) % 3) * 0.35
		box(s, "Weed", 0.1, ph, 0.1, i * (w / 6), base + 0.22 + ph / 2, 0.25 - (i % 2) * 0.3, { 50, 150, 80 }, "Grass", { rot = { 0, 0, i * 6 } })
	end
	local fish = { { 255, 120, 40 }, { 255, 230, 80 }, { 80, 200, 255 } }
	for i, c in fish do
		ball(s, "Fish", 0.2, -w / 4 + (i - 1) * w / 4, base + 0.8 + (i % 2) * 0.4, -0.1 + (i - 2) * 0.12, c, "Neon")
	end
	local glow = box(s, "TankLight", w - 0.3, 0.04, 0.2, 0, base + th - 0.02, 0, v.detail, "Neon")
	light(s, glow, 6, 0.6, v.detail)
end)
F("dc_cushions", "deco", "cozy", "쿠션 3종 세트", 60000, 1, { 214, 160, 60 }, { 236, 228, 212 }, { 120, 140, 170 }, function(s, W, H, D, v)
	local _ = H
	local _ = D
	local cols = { v.main, v.accent, v.detail }
	for i, c in cols do
		local x = (i - 2) * math.min(W, 1.8) / 3.2
		box(s, "Cushion", 0.62, 0.62, 0.22, x, 0.34, (i - 2) * 0.06, c, "Fabric", { rot = { -14, (i - 2) * 12, (i - 2) * 6 }, collide = true })
	end
end)
F("dc_wallclock", "deco", "cozy", "원목 벽시계", 75000, 2, OAK, BLACK, WHITE, function(s, W, H, D, v)
	local _ = W
	local _ = H
	local d = math.min(D, 0.2)
	zcyl(s, "Face", d, 1.5, 0, 0.8, 0, v.detail, "SmoothPlastic", { collide = true })
	zcyl(s, "Rim", d * 0.6, 1.6, 0, 0.8, d * 0.2, v.main, "Wood")
	box(s, "HourHand", 0.06, 0.4, 0.02, 0.06, 0.94, -d / 2 - 0.02, v.accent, "SmoothPlastic", { rot = { 0, 0, -30 } })
	box(s, "MinuteHand", 0.04, 0.6, 0.02, -0.1, 1.05, -d / 2 - 0.03, v.accent, "SmoothPlastic", { rot = { 0, 0, 20 } })
	for i = 0, 3 do
		local a = i * math.pi / 2
		box(s, "Tick", 0.06, 0.16, 0.02, math.sin(a) * 0.62, 0.8 + math.cos(a) * 0.62, -d / 2 - 0.01, v.accent, "SmoothPlastic", { rot = { 0, 0, -i * 90 } })
	end
end)
F("dc_wallshelf", "deco", "modern", "벽 선반 + 소품", 120000, 2, OAK, { 60, 60, 62 }, { 90, 150, 110 }, function(s, W, H, D, v)
	local _ = H
	local w, d = math.min(W, 3.0), math.min(D, 0.8)
	box(s, "Board", w, 0.12, d, 0, 0.3, 0, v.main, "Wood", { collide = true })
	box(s, "Rail", w - 0.4, 0.2, 0.06, 0, 0.16, d / 2 - 0.03, v.accent, "Metal")
	for i = 0, 3 do
		local bh = 0.7 - (i % 2) * 0.12
		box(s, "Book", 0.12, bh, d - 0.25, -w / 2 + 0.3 + i * 0.15, 0.36 + bh / 2, 0, if i % 2 == 0 then { 40, 60, 90 } else { 200, 160, 90 }, "SmoothPlastic")
	end
	vcyl(s, "Pot", 0.4, 0.36, w / 2 - 0.4, 0.56, 0, WHITE, "SmoothPlastic")
	ball(s, "Leaves", 0.55, w / 2 - 0.4, 0.95, 0, v.detail, "LeafyGrass")
	box(s, "Frame", 0.6, 0.75, 0.05, 0.2, 0.74, d / 2 - 0.12, BLACK, "SmoothPlastic", { rot = { -8, 0, 0 } })
end)
F("dc_mirror_wall", "deco", "cozy", "아치형 벽거울 (골드)", 240000, 3, BRASS, GLASS, WHITE, function(s, W, H, D, v)
	local w = math.min(W, 2.0)
	local h = math.min(H, 3.8)
	local d = math.min(D, 0.15)
	local body = h - w / 2
	box(s, "Frame", w, body, d, 0, body / 2, 0, v.main, "Metal", { collide = true })
	zcyl(s, "Arch", d, w, 0, body, 0, v.main, "Metal")
	box(s, "Mirror", w - 0.16, body, 0.02, 0, body / 2 + 0.04, -d / 2 - 0.005, v.accent, "Glass")
	zcyl(s, "MirrorTop", 0.02, w - 0.16, 0, body, -d / 2 - 0.005, v.accent, "Glass")
end)
F("dc_photo_frames", "deco", "cozy", "포토 액자 3종 (광안리 여행)", 35000, 1, WHITE, BLACK, { 90, 170, 220 }, function(s, W, H, D, v)
	local _ = H
	local _ = D
	local defs = { { -0.5, 0.7, 0.55 }, { 0.05, 0.9, 0.7 }, { 0.55, 0.6, 0.5 } }
	for i, f in defs do
		local x, h, w = f[1] * math.min(W, 1.6) / 1.6, f[2], f[3]
		box(s, "Frame", w, h, 0.06, x, h / 2 + 0.02, 0.05 * (i - 2), if i == 2 then v.accent else v.main, "Wood", { rot = { -10, (i - 2) * 10, 0 }, collide = true })
		box(s, "Photo", w - 0.12, h - 0.12, 0.02, x, h / 2 + 0.02, 0.05 * (i - 2) - 0.04, if i == 1 then v.detail else { 255, 190, 120 }, "SmoothPlastic", { rot = { -10, (i - 2) * 10, 0 } })
	end
end)

-------------------------------------------------------------------------------------------------
-- Spec builder for the extended variants (same output shape as G.furnitureSpec)
-------------------------------------------------------------------------------------------------
function HS.spec(variantId: string, W: number, H: number, D: number): any?
	local v = HS.FURNITURE[variantId]
	local build = HS.BUILDERS[variantId]
	if not v or not build then
		return nil
	end
	local spec = { parts = {}, variant = variantId, category = v.category, size = { W, H, D } }
	build(spec, W, H, D, v)
	return spec
end

-------------------------------------------------------------------------------------------------
-- v2: FREE PLACEMENT (자유 배치) — catalog, colourways, placement kinds, specs, bounds, records
--   Every G.FURNITURE variant (>= 100: the slot catalog + the extension + the v2 kitchen / bath /
--   wall items above) can be placed anywhere inside the unit:
--     kind "floor"  stands on the floor or on any surface the server's down-ray finds
--     kind "small"  same, and when it stands on a table / shelf / counter its pedestal ("Stand") is
--                   dropped so it sits on the surface (stacked = true)
--     kind "wall"   hangs on a wall (back = +Z against the wall, front = the wall's normal)
--     kind "rug"    flat on the floor, never counts as an overlap
--   Saved record (d.housing.units[listingId].items, cap HS.DECOR.CAP):
--     { u = uid, i = itemId, v = colourway (1 = the item's own colours), x, y, z (studs, UnitRoot
--       frame), r = yaw degrees, m = room id, s = true when stacked }
-------------------------------------------------------------------------------------------------
local GG: any = nil -- G, set by HS.extend

HS.DECOR = {
	CAP = 200, -- placed items per home
	PART_CAP = 2600, -- parts of placed items per home instance (mobile budget)
	LIGHTS = 3, -- real PointLights placed items may add per home (more glow pieces keep their Neon)
	ROOM_LIGHTS = 4, -- never more than 4 lights in one room (template + placed)
	REFUND = 0.5, -- 판매 환불율
	FRESH_SECONDS = 600, -- bought in this visit less than 10 min ago: removing refunds 100 % (= undo)
	TRASH_SECONDS = 600, -- removed pieces can be restored (undo) for 10 min at the same price
	OVERLAP_MAX = 0.35, -- max share of the smaller footprint two pieces may overlap
	MAX_HEIGHT = 14, -- studs above the room floor
	BATCH_MAX = 40, -- uids per remove / restore request
	GRID = { 0.5, 1, 0 }, -- snap steps offered by the editor (0 = off)
	ROT_STEP = 15,
}

HS.EXTRA_CATEGORIES_V2 = {
	kitchen = { name = "주방", icon = "🍳", size = { 2.4, 5, 2.2 } },
	bath = { name = "욕실", icon = "🛁", size = { 1.6, 2, 1 } },
}

-- natural envelope W x H x D of a piece placed freely (else the category's default size)
HS.ITEM_SIZE = {
	kt_fridge = { 3.0, 6.2, 2.4 }, kt_kimchi = { 2.0, 5.6, 2.3 }, kt_microwave = { 1.8, 1.0, 1.2 }, kt_island = { 6.4, 3.4, 3.2 },
	kt_dishrack = { 1.6, 0.9, 1.0 }, bt_cabinet = { 2.2, 2.6, 0.6 }, bt_towel = { 2.4, 1.8, 0.8 }, bt_mat = { 2.4, 0.08, 1.6 },
	bt_basket = { 1.4, 1.8, 1.4 }, bt_toiletries = { 1.2, 0.8, 0.6 }, tv_wall = { 7.0, 4.2, 0.35 }, ap_console = { 1.6, 1.4, 1.0 },
	dc_aquarium = { 3.2, 4.4, 1.4 }, dc_cushions = { 1.8, 1.0, 0.8 }, dc_wallclock = { 1.6, 1.6, 0.2 }, dc_wallshelf = { 3.0, 1.4, 0.8 },
	dc_mirror_wall = { 2.0, 3.8, 0.15 }, dc_photo_frames = { 1.6, 1.0, 0.5 }, tv_projector = { 8, 6.4, 1.6 }, ap_robot = { 1.4, 1.0, 2.2 },
}

HS.PLACE_BY_CATEGORY = { art = "wall", curtain = "wall", rug = "rug" }
HS.PLACE_BY_ITEM = {
	tv_wall = "wall", bt_cabinet = "wall", bt_towel = "wall", dc_wallclock = "wall", dc_wallshelf = "wall", dc_mirror_wall = "wall",
	bt_mat = "rug",
	dc_candles = "small", dc_vase = "small", dc_books = "small", dc_diffuser = "small", dc_figures = "small", plant_cactus_set = "small",
	plant_eucalyptus = "small", lamp_moon = "small", kt_microwave = "small", kt_dishrack = "small", bt_toiletries = "small",
	ap_console = "small", dc_cushions = "small", dc_photo_frames = "small", dc_aquarium = "small",
}

function HS.placeKind(itemId: string): string
	local k = HS.PLACE_BY_ITEM[itemId]
	if k then
		return k
	end
	local f = GG and GG.FURNITURE[itemId]
	return (f and HS.PLACE_BY_CATEGORY[f.category]) or "floor"
end

-- Catalog tabs of the free placement editor (every category appears in exactly one tab).
HS.CATALOG_TABS = {
	{ id = "sofa", name = "소파·의자", icon = "🛋️", cats = { "sofa", "chair" } },
	{ id = "bed", name = "침대", icon = "🛏️", cats = { "bed" } },
	{ id = "table", name = "테이블·책상", icon = "🍽️", cats = { "table", "desk" } },
	{ id = "storage", name = "수납", icon = "📚", cats = { "shelf" } },
	{ id = "lamp", name = "조명", icon = "💡", cats = { "lamp" } },
	{ id = "rug", name = "러그", icon = "🧶", cats = { "rug" } },
	{ id = "plant", name = "식물", icon = "🪴", cats = { "plant" } },
	{ id = "deco", name = "소품·벽장식", icon = "🖼️", cats = { "deco", "art" } },
	{ id = "tv", name = "TV·가전", icon = "📺", cats = { "tv", "appliance" } },
	{ id = "kitchen", name = "주방", icon = "🍳", cats = { "kitchen" } },
	{ id = "bath", name = "욕실", icon = "🛁", cats = { "bath" } },
	{ id = "curtain", name = "커튼", icon = "🪟", cats = { "curtain" } },
}

-- Item ids of a catalog tab, cheapest first.
function HS.catalogTab(tabId: string): { string }
	local out = {}
	local G = GG
	if not G then
		return out
	end
	local cats = {}
	for _, t in HS.CATALOG_TABS do
		if t.id == tabId then
			for _, c in t.cats do
				cats[c] = true
			end
		end
	end
	for _, id in G.FURNITURE_ORDER do
		local f = G.FURNITURE[id]
		if f and cats[f.category] then
			table.insert(out, id)
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = G.FURNITURE[a].price, G.FURNITURE[b].price
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	return out
end

function HS.catalogCount(): number
	local n = 0
	if GG then
		for _, t in HS.CATALOG_TABS do
			n += #HS.catalogTab(t.id)
		end
	end
	return n
end

-- Colourways ------------------------------------------------------------------------------------
local PAL = {
	fabric = { { "그레이", { 150, 152, 158 } }, { "네이비", { 52, 66, 104 } }, { "카멜", { 176, 120, 70 } }, { "올리브", { 112, 122, 76 } }, { "크림", { 236, 228, 212 } } },
	bedding = { { "퓨어 화이트", { 246, 246, 248 } }, { "세이지", { 168, 190, 168 } }, { "블러쉬 핑크", { 234, 192, 196 } }, { "차콜", { 74, 76, 82 } } },
	wood = { { "오크", { 200, 168, 124 } }, { "월넛", { 96, 62, 40 } }, { "화이트", { 238, 238, 236 } }, { "블랙", { 38, 38, 42 } } },
	metal = { { "화이트", { 240, 240, 238 } }, { "실버", { 192, 196, 202 } }, { "블랙", { 34, 34, 38 } }, { "민트", { 172, 222, 204 } } },
	lamp = { { "아이보리", { 246, 240, 226 } }, { "블랙", { 40, 40, 44 } }, { "브라스", { 196, 156, 96 } } },
	rug = { { "베이지", { 222, 206, 176 } }, { "그레이", { 150, 150, 152 } }, { "네이비", { 52, 62, 96 } }, { "테라코타", { 186, 104, 76 } } },
	pot = { { "화이트 화분", { 238, 236, 230 } }, { "테라코타", { 196, 110, 70 } }, { "블랙 화분", { 40, 40, 44 } } },
	curtain = { { "아이보리", { 236, 228, 210 } }, { "차콜", { 74, 76, 82 } }, { "세이지", { 168, 186, 160 } }, { "더스티 핑크", { 220, 176, 176 } } },
	deco = { { "화이트", { 240, 240, 238 } }, { "블랙", { 36, 36, 40 } }, { "골드", { 212, 175, 55 } } },
}
HS.PALETTES = PAL
HS.CAT_PALETTE = {
	sofa = "fabric", chair = "fabric", bed = "bedding", table = "wood", desk = "wood", shelf = "wood", lamp = "lamp", rug = "rug",
	plant = "pot", curtain = "curtain", tv = "metal", appliance = "metal", kitchen = "metal", bath = "metal", deco = "deco", art = "deco",
}
HS.PALETTE_FIELD = { plant = "accent", art = "accent" } -- which colour of the piece a colourway replaces (else main)

local function paletteOf(itemId: string): ({ any }?, string)
	local f = GG and GG.FURNITURE[itemId]
	if not f then
		return nil, "main"
	end
	return PAL[HS.CAT_PALETTE[f.category] or ""], HS.PALETTE_FIELD[f.category] or "main"
end

-- Number of colourways of a piece (1 = only its own colours).
function HS.colorwayCount(itemId: string): number
	local pal = paletteOf(itemId)
	return 1 + (if pal then #pal else 0)
end

-- { name, color = {r,g,b} } of colourway `cw` (1 = 기본).
function HS.colorway(itemId: string, cw: number?): any
	local f = GG and GG.FURNITURE[itemId]
	local c = math.floor(tonumber(cw) or 1)
	local pal, field = paletteOf(itemId)
	if c <= 1 or not pal or not pal[c - 1] then
		return { name = "기본", color = f and (if field == "accent" then f.accent else f.main) or { 200, 200, 200 } }
	end
	return { name = pal[c - 1][1], color = pal[c - 1][2] }
end

function HS.clampColorway(itemId: string, cw: any): number
	local n = HS.colorwayCount(itemId)
	local c = if type(cw) == "number" and cw == cw then math.floor(cw) else 1
	return math.clamp(c, 1, n)
end

-- The furniture definition with colourway `cw` applied (a copy; cw 1 = the catalog entry itself).
function HS.itemDef(itemId: string, cw: number?): any?
	local f = GG and GG.FURNITURE[itemId]
	if not f then
		return nil
	end
	local c = HS.clampColorway(itemId, cw)
	if c <= 1 then
		return f
	end
	local pal, field = paletteOf(itemId)
	local copy = table.clone(f)
	if pal and pal[c - 1] then
		copy[field] = pal[c - 1][2]
	end
	return copy
end

function HS.itemSize(itemId: string): { number }
	local s = HS.ITEM_SIZE[itemId]
	if s then
		return s
	end
	local f = GG and GG.FURNITURE[itemId]
	local c = f and GG.FURNITURE_CATEGORIES[f.category]
	return (c and c.size) or { 2, 2, 2 }
end

-- Drops the pedestal ("Stand" part standing on the floor) and lowers the rest onto the surface.
local function stripStand(spec: any)
	local idx, top = nil, 0
	for i, p in spec.parts do
		if p.name == "Stand" and (p.pos[2] - p.size[2] / 2) <= 0.06 then
			idx, top = i, p.pos[2] + p.size[2] / 2
			break
		end
	end
	if not idx then
		return
	end
	table.remove(spec.parts, idx)
	for _, p in spec.parts do
		p.pos = { p.pos[1], p.pos[2] - top, p.pos[3] }
	end
	if spec.lights then
		local keep = {}
		for _, l in spec.lights do
			if l.part ~= idx then
				table.insert(keep, { part = if l.part > idx then l.part - 1 else l.part, range = l.range, brightness = l.brightness, color = l.color })
			end
		end
		spec.lights = keep
	end
	if spec.screen then
		spec.screen = if spec.screen == idx then nil elseif spec.screen > idx then spec.screen - 1 else spec.screen
	end
	if spec.seat then
		spec.seat = { pos = { spec.seat.pos[1], spec.seat.pos[2] - top, spec.seat.pos[3] }, facing = spec.seat.facing }
	end
	if spec.bed then
		spec.bed = { pos = { spec.bed.pos[1], spec.bed.pos[2] - top, spec.bed.pos[3] } }
	end
	spec.stacked = true
end

-- Spec of a freely placed piece (G.furnitureSpec format). stacked: on a surface (pedestal dropped).
function HS.itemSpec(itemId: string, cw: number?, stacked: boolean?): any?
	local G = GG
	local f = G and G.FURNITURE[itemId]
	if not f then
		return nil
	end
	local def = HS.itemDef(itemId, cw)
	local sz = HS.itemSize(itemId)
	local w, h, d = sz[1], sz[2], sz[3]
	local spec: any = { parts = {}, variant = itemId, category = f.category, size = { w, h, d } }
	local build = HS.BUILDERS[itemId]
	local ok, err = pcall(function()
		if build then
			build(spec, w, h, d, def)
		else
			local gen = G.FURNITURE_GEN and G.FURNITURE_GEN[f.category]
			if gen then
				gen(spec, w, h, d, def, def.style)
			end
		end
	end)
	if not ok then
		warn("[GwangalliHomesShared] item spec " .. itemId .. ": " .. tostring(err))
		return nil
	end
	if #spec.parts == 0 then
		return nil
	end
	if stacked and HS.placeKind(itemId) == "small" then
		stripStand(spec)
	end
	return spec
end

-- Axis-aligned bounds of a spec in its own frame: { x0, y0, z0, x1, y1, z1 } (rotated parts are
-- bounded conservatively; vertical / Z cylinders exactly).
local boundsCache: { [string]: { number } } = {}
function HS.specBounds(spec: any): { number }
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for _, p in spec.parts do
		local hx, hy, hz = p.size[1] / 2, p.size[2] / 2, p.size[3] / 2
		local r = p.rot
		if r and (r[1] ~= 0 or r[2] ~= 0 or r[3] ~= 0) then
			if r[1] == 0 and r[2] == 0 and math.abs(r[3]) == 90 then
				hx, hy = hy, hx
			elseif r[1] == 0 and r[3] == 0 and math.abs(r[2]) == 90 then
				hx, hz = hz, hx
			else
				local m = math.max(hx, hy, hz)
				hx, hy, hz = m, m, m
			end
		end
		local px, py, pz = p.pos[1], p.pos[2], p.pos[3]
		x0, y0, z0 = math.min(x0, px - hx), math.min(y0, py - hy), math.min(z0, pz - hz)
		x1, y1, z1 = math.max(x1, px + hx), math.max(y1, py + hy), math.max(z1, pz + hz)
	end
	if x0 == math.huge then
		return { -0.5, 0, -0.5, 0.5, 1, 0.5 }
	end
	return { x0, math.max(0, y0), z0, x1, y1, z1 }
end

-- Cached bounds of a piece (colourways never change the geometry).
function HS.itemBounds(itemId: string, stacked: boolean?): { number }
	local key = itemId .. (if stacked then "|s" else "")
	local b = boundsCache[key]
	if not b then
		local spec = HS.itemSpec(itemId, 1, stacked)
		b = if spec then HS.specBounds(spec) else { -0.5, 0, -0.5, 0.5, 1, 0.5 }
		boundsCache[key] = b
	end
	return b
end

function HS.itemPartCount(itemId: string, stacked: boolean?): number
	local spec = HS.itemSpec(itemId, 1, stacked)
	if not spec then
		return 0
	end
	return #spec.parts + (if spec.seat then 1 else 0)
end

-- Footprint box of a placed piece in the unit frame: { cx, cz, hw, hd, ry (radians), y0, y1, rug }.
function HS.decorBox(itemId: string, stacked: boolean?, x: number, y: number, z: number, rDeg: number): any
	local b = HS.itemBounds(itemId, stacked)
	local ry = math.rad(rDeg or 0)
	local c, s = math.cos(ry), math.sin(ry)
	local bx, bz = (b[1] + b[4]) / 2, (b[3] + b[6]) / 2
	return {
		cx = x + bx * c + bz * s,
		cz = z - bx * s + bz * c,
		hw = math.max(0.05, (b[4] - b[1]) / 2),
		hd = math.max(0.05, (b[6] - b[3]) / 2),
		ry = ry,
		y0 = y + b[2],
		y1 = y + b[5],
		rug = HS.placeKind(itemId) == "rug",
	}
end

-- Box corners (XZ) of a decorBox: { {x, z} x4 }.
function HS.boxCorners(bx: any): { { number } }
	local c, s = math.cos(bx.ry), math.sin(bx.ry)
	local out = {}
	for _, k in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local lx, lz = k[1] * bx.hw, k[2] * bx.hd
		table.insert(out, { bx.cx + lx * c + lz * s, bx.cz - lx * s + lz * c })
	end
	return out
end

local function insideBox(bx: any, x: number, z: number): boolean
	local dx, dz = x - bx.cx, z - bx.cz
	local c, s = math.cos(-bx.ry), math.sin(-bx.ry)
	local lx, lz = dx * c + dz * s, -dx * s + dz * c
	return math.abs(lx) <= bx.hw and math.abs(lz) <= bx.hd
end

-- Share (0..1) of the smaller footprint covered by the other box (0 when their heights do not
-- meet or either is a rug). 5 x 5 samples: cheap and symmetric enough for a validity check.
function HS.overlapFrac(a: any, b: any): number
	if a.rug or b.rug then
		return 0
	end
	if math.min(a.y1, b.y1) - math.max(a.y0, b.y0) < 0.15 then
		return 0
	end
	local small, big = a, b
	if a.hw * a.hd > b.hw * b.hd then
		small, big = b, a
	end
	local c, s = math.cos(small.ry), math.sin(small.ry)
	local hits = 0
	for i = 0, 4 do
		for j = 0, 4 do
			local lx = ((i + 0.5) / 5 * 2 - 1) * small.hw
			local lz = ((j + 0.5) / 5 * 2 - 1) * small.hd
			if insideBox(big, small.cx + lx * c + lz * s, small.cz - lx * s + lz * c) then
				hits += 1
			end
		end
	end
	return hits / 25
end

-- Checks a candidate against the other placed pieces of a unit: ok, reason ("cap" | "overlap"),
-- conflicting uid. cand = { i, x, y, z, r, s }; ignore = uid being moved (or nil for a new piece).
function HS.checkOverlap(items: { any }, cand: any, ignore: number?): (boolean, string?, number?)
	local a = HS.decorBox(cand.i, cand.s, cand.x, cand.y, cand.z, cand.r)
	for _, it in items do
		if it.u ~= ignore then
			local b = HS.decorBox(it.i, it.s, it.x, it.y, it.z, it.r)
			if HS.overlapFrac(a, b) > HS.DECOR.OVERLAP_MAX then
				return false, "overlap", it.u
			end
		end
	end
	return true, nil, nil
end

-- Records ---------------------------------------------------------------------------------------
function HS.decorItems(unit: any): { any }
	if type(unit) ~= "table" then
		return {}
	end
	if type(unit.items) ~= "table" then
		unit.items = {}
	end
	return unit.items
end

function HS.findItem(unit: any, uid: number): (number?, any)
	for i, it in HS.decorItems(unit) do
		if it.u == uid then
			return i, it
		end
	end
	return nil, nil
end

local function round2(v: number): number
	return math.floor(v * 100 + 0.5) / 100
end

-- Adds a piece (after the caller charged it). Returns the stored record (with its new uid).
function HS.addItem(unit: any, rec: any): any
	local items = HS.decorItems(unit)
	local uid = math.max(1, math.floor(tonumber(unit.nextUid) or 1))
	for _, it in items do
		if it.u >= uid then
			uid = it.u + 1
		end
	end
	unit.nextUid = uid + 1
	local r = {
		u = uid,
		i = rec.i,
		v = HS.clampColorway(rec.i, rec.v),
		x = round2(rec.x),
		y = round2(rec.y),
		z = round2(rec.z),
		r = round2((rec.r or 0) % 360),
		m = rec.m,
		s = if rec.s then true else nil,
	}
	table.insert(items, r)
	return r
end

function HS.removeItem(unit: any, uid: number): any?
	local i, it = HS.findItem(unit, uid)
	if i then
		table.remove(HS.decorItems(unit), i)
	end
	return it
end

-- Decor points / resale value of the placed pieces of a unit record.
function HS.itemsDecor(unit: any): number
	local s = 0
	for _, it in (type(unit) == "table" and type(unit.items) == "table" and unit.items or {}) do
		local f = GG and GG.FURNITURE[it.i]
		if f then
			s += f.decor
		end
	end
	return s
end

function HS.itemsValue(unit: any): number
	local v = 0
	for _, it in (type(unit) == "table" and type(unit.items) == "table" and unit.items or {}) do
		local f = GG and GG.FURNITURE[it.i]
		if f then
			v += math.floor(f.price * HS.DECOR.REFUND)
		end
	end
	return v
end

-- Validates the free-placement fields of a raw saved unit into the sanitised one.
function HS.sanitizeItems(raw: any, unit: any)
	if type(raw) ~= "table" or type(unit) ~= "table" or type(raw.items) ~= "table" then
		return
	end
	local G = GG
	local out, seen = {}, {}
	local maxUid = 0
	for _, it in raw.items do
		if #out >= HS.DECOR.CAP then
			break
		end
		if type(it) == "table" and type(it.i) == "string" and G and G.FURNITURE[it.i] then
			local u = tonumber(it.u)
			local x, y, z, r = tonumber(it.x), tonumber(it.y), tonumber(it.z), tonumber(it.r)
			if u and u == u and u >= 1 and not seen[math.floor(u)] and isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z) and isFiniteNumber(r or 0) then
				local uid = math.floor(u)
				seen[uid] = true
				maxUid = math.max(maxUid, uid)
				table.insert(out, {
					u = uid,
					i = it.i,
					v = HS.clampColorway(it.i, it.v),
					x = round2(math.clamp(x :: number, -400, 400)),
					y = round2(math.clamp(y :: number, -60, 120)),
					z = round2(math.clamp(z :: number, -400, 400)),
					r = round2(((r or 0) :: number) % 360),
					m = cleanKey(it.m, 24),
					s = if it.s == true then true else nil,
				})
			end
		end
	end
	unit.items = out
	unit.nextUid = math.max(maxUid + 1, math.floor(tonumber(raw.nextUid) or 1))
	local likes = tonumber(raw.likes)
	if likes and likes == likes then
		unit.likes = math.clamp(math.floor(likes), 0, 1e6)
	end
end

-------------------------------------------------------------------------------------------------
-- v2: FLOORS / UNITS (층·호수) — wraps ReplicatedStorage.GwangalliHomesFloors (owner: floors) with
-- fallbacks, so every listing always has a building table even before that module exists.
-- choice = { floor, unit, layoutId, priceMult, view } (what G.rentHome / buyHome / buyHomeWithLoan
-- and the saved address use).
-------------------------------------------------------------------------------------------------
local floorsMod: any = nil
local floorsTried = -math.huge
function HS.setFloors(mod: any)
	floorsMod = mod
	floorsTried = math.huge
end

function HS.floors(): any?
	if floorsMod then
		return floorsMod
	end
	local now = os.clock()
	if now - floorsTried < 5 then
		return nil
	end
	floorsTried = now
	local ok, res = pcall(function()
		local scr: any = script
		if typeof(scr) == "Instance" and scr.Parent then
			local m = scr.Parent:FindFirstChild("GwangalliHomesFloors")
			if m and m:IsA("ModuleScript") then
				return require(m) :: any
			end
		end
		return nil
	end)
	if ok and type(res) == "table" then
		floorsMod = res
	end
	return floorsMod
end

HS.FALLBACK_FLOORS = { goshiwon = { 3, 4, 6 }, oneroom = { 2, 5, 4 }, officetel = { 3, 20, 4 }, apartment = { 2, 30, 4 }, penthouse = { 37, 38, 2 } } -- first, last, units per floor
HS.FALLBACK_LAYOUT = {
	goshiwon = { label = "고시원 1인실", area = 7, rooms = 1, baths = 1, balcony = false, duplex = false, plan = { { room = "main", x = 0, y = 0, w = 2.2, h = 2.6 }, { room = "bath", x = 2.2, y = 1.4, w = 1.0, h = 1.2 } } },
	oneroom = { label = "원룸 분리형 23㎡", area = 23, rooms = 1, baths = 1, balcony = false, duplex = false, plan = { { room = "main", x = 0, y = 0, w = 4.2, h = 3.6 }, { room = "kitchen", x = 0, y = 3.6, w = 2.6, h = 1.6 }, { room = "bath", x = 2.6, y = 3.6, w = 1.6, h = 1.6 }, { room = "entry", x = 4.2, y = 3.6, w = 1.0, h = 1.6 } } },
	officetel = { label = "오피스텔 복층 33㎡", area = 33, rooms = 1, baths = 1, balcony = false, duplex = true, plan = { { room = "living", x = 0, y = 0, w = 4.6, h = 3.8 }, { room = "kitchen", x = 0, y = 3.8, w = 2.8, h = 1.8 }, { room = "bath", x = 2.8, y = 3.8, w = 1.8, h = 1.8 }, { room = "loft", x = 4.6, y = 0, w = 2.0, h = 3.8 } } },
	apartment = { label = "84㎡ 판상형 (30평)", area = 84, rooms = 3, baths = 2, balcony = true, duplex = false, plan = { { room = "living", x = 0, y = 0, w = 5.4, h = 4.4 }, { room = "kitchen", x = 5.4, y = 0, w = 3.2, h = 4.4 }, { room = "bedroom", x = 0, y = 4.4, w = 3.8, h = 3.6 }, { room = "study", x = 3.8, y = 4.4, w = 2.8, h = 3.0 }, { room = "bath", x = 6.6, y = 4.4, w = 2.0, h = 2.0 }, { room = "entry", x = 6.6, y = 6.4, w = 2.0, h = 1.6 }, { room = "veranda", x = 0, y = -1.4, w = 8.6, h = 1.4 } } },
	penthouse = { label = "펜트하우스 복층 198㎡", area = 198, rooms = 4, baths = 3, balcony = true, duplex = true, plan = { { room = "living", x = 0, y = 0, w = 8.0, h = 6.0 }, { room = "dining", x = 8.0, y = 0, w = 4.0, h = 6.0 }, { room = "bedroom", x = 0, y = 6.0, w = 5.0, h = 4.2 }, { room = "dress", x = 5.0, y = 6.0, w = 2.4, h = 4.2 }, { room = "master_bath", x = 7.4, y = 6.0, w = 2.6, h = 2.6 }, { room = "kitchen", x = 10.0, y = 6.0, w = 2.0, h = 4.2 }, { room = "terrace", x = 0, y = -3.0, w = 12.0, h = 3.0 } } },
}

-- Layout definition (Floors module first, else the tier fallback when layoutId is a tier key).
function HS.layout(layoutId: any): any?
	if type(layoutId) ~= "string" then
		return nil
	end
	local F = HS.floors()
	local def = F and type(F.layouts) == "table" and F.layouts[layoutId] or nil
	if type(def) == "table" then
		return def
	end
	local fb = HS.FALLBACK_LAYOUT[layoutId]
	if fb then
		local t = GG and GG.HOME_TIERS[layoutId]
		return { template = "HomeUnit_" .. layoutId, label = fb.label, area = fb.area, rooms = fb.rooms, baths = fb.baths, balcony = fb.balcony, duplex = fb.duplex, tierKey = layoutId, plan = fb.plan, fallback = true, tierName = t and t.name }
	end
	return nil
end

local fbBuildings: { [string]: any } = {}
local function fallbackBuilding(listingId: string): any?
	local G = GG
	local l = G and G.LISTINGS[listingId]
	if not l then
		return nil
	end
	local cached = fbBuildings[listingId]
	if cached then
		return cached
	end
	local spec = HS.FALLBACK_FLOORS[l.tierKey] or { 2, 5, 3 }
	local floors = {}
	for fl = spec[1], spec[2] do
		local units = {}
		for u = 1, spec[3] do
			local view = math.clamp((fl - spec[1] + 1) / math.max(1, spec[2] - spec[1] + 1), 0, 1)
			local side = if u == 1 or u == spec[3] then 0.08 else 0
			table.insert(units, { unit = string.format("%d%02d", fl, u), layout = l.tierKey, view = math.clamp(view * 0.85 + side, 0, 1), priceMult = math.floor((0.92 + view * 0.22 + side) * 100 + 0.5) / 100 })
		end
		table.insert(floors, { floor = fl, units = units })
	end
	local b = { site = l.place, floors = floors, fallback = true }
	fbBuildings[listingId] = b
	return b
end

-- Building table of a listing: { site, floors = { {floor, units = { {unit, layout, view, priceMult} } } } }.
function HS.building(listingId: string): any?
	local F = HS.floors()
	local b = F and type(F.buildings) == "table" and F.buildings[listingId] or nil
	if type(b) == "table" and type(b.floors) == "table" and #b.floors > 0 then
		return b
	end
	return fallbackBuilding(listingId)
end

-- The unit row (validated) of a listing: { floor, unit, layout, view, priceMult } or nil.
function HS.unitRow(listingId: string, floor: any, unit: any): any?
	local fl = tonumber(floor)
	if not fl or type(unit) ~= "string" or #unit == 0 or #unit > 8 then
		return nil
	end
	local F = HS.floors()
	if F and type(F.unitFor) == "function" then
		local ok, row = pcall(F.unitFor, listingId, fl, unit)
		if ok and type(row) == "table" and type(row.layout) == "string" then
			return { floor = fl, unit = unit, layout = row.layout, view = math.clamp(tonumber(row.view) or 0.5, 0, 1), priceMult = math.clamp(tonumber(row.priceMult) or 1, 0.5, 3) }
		end
	end
	local b = HS.building(listingId)
	for _, f in (b and b.floors or {}) do
		if f.floor == fl then
			for _, u in f.units or {} do
				if u.unit == unit then
					return { floor = fl, unit = unit, layout = u.layout, view = math.clamp(tonumber(u.view) or 0.5, 0, 1), priceMult = math.clamp(tonumber(u.priceMult) or 1, 0.5, 3) }
				end
			end
		end
	end
	return nil
end

-- choice for G.rentHome / buyHome / buyHomeWithLoan (nil = unknown unit).
function HS.choiceFor(listingId: string, floor: any, unit: any): any?
	local row = HS.unitRow(listingId, floor, unit)
	if not row then
		return nil
	end
	return { floor = row.floor, unit = row.unit, layoutId = row.layout, priceMult = row.priceMult, view = row.view }
end

-- A sensible default unit (migrated saves, the classic 계약 buttons): Floors' defaultUnit, else the
-- middle floor's first unit. priceMult of a default unit is always 1 (no surprise price change).
function HS.defaultChoice(listingId: string): any?
	local F = HS.floors()
	if F and type(F.defaultUnit) == "function" then
		local ok, fl, un = pcall(F.defaultUnit, listingId)
		if ok then
			local c = HS.choiceFor(listingId, fl, un)
			if c then
				c.priceMult = 1
				return c
			end
		end
	end
	local b = HS.building(listingId)
	if not b or #b.floors == 0 then
		return nil
	end
	local f = b.floors[math.max(1, math.ceil(#b.floors / 2))]
	local u = f and f.units and f.units[1]
	if not u then
		return nil
	end
	return { floor = f.floor, unit = u.unit, layoutId = u.layout, priceMult = 1, view = math.clamp(tonumber(u.view) or 0.5, 0, 1) }
end

-- base * the unit's multiplier (Floors' priceFor when present, else rounded to 100원).
function HS.scalePrice(listingId: string, choice: any?, base: number): number
	if type(choice) ~= "table" or not isFiniteNumber(choice.priceMult) or choice.priceMult == 1 or base <= 0 then
		return base
	end
	local F = HS.floors()
	if F and type(F.priceFor) == "function" and choice.floor and choice.unit then
		local ok, v = pcall(F.priceFor, listingId, choice.floor, choice.unit, base)
		if ok and isFiniteNumber(v) and v > 0 and math.abs(v / base - choice.priceMult) < 0.05 then
			return math.floor(v / 100 + 0.5) * 100
		end
	end
	return math.floor(base * math.clamp(choice.priceMult, 0.5, 3) / 100 + 0.5) * 100
end

-- Template name for a home: the layout's template, else the tier's.
function HS.templateNames(tierKey: string, layoutId: any): { string }
	local out = {}
	local lay = HS.layout(layoutId)
	if lay and type(lay.template) == "string" then
		table.insert(out, lay.template)
	end
	if type(layoutId) == "string" then
		table.insert(out, "HomeUnit_" .. layoutId)
	end
	table.insert(out, "HomeUnit_" .. tierKey)
	return out
end

-- "광안자이 1502호" style address line.
function HS.addressText(listingId: string, unit: any): string
	local l = GG and GG.LISTINGS[listingId]
	local name = l and l.name or "내 집"
	if type(unit) == "string" and #unit > 0 then
		return string.format("%s %s호", name, unit)
	end
	return name
end

-- 0..1 view -> "★★★☆☆"
function HS.viewStars(view: any): string
	local n = math.clamp(math.floor((tonumber(view) or 0) * 5 + 0.5), 1, 5)
	return string.rep("★", n) .. string.rep("☆", 5 - n)
end

function HS.sanitizeAddress(raw: any): any?
	local G = GG
	if type(raw) ~= "table" or type(raw.listingId) ~= "string" or not (G and G.LISTINGS[raw.listingId]) then
		return nil
	end
	local fl = tonumber(raw.floor)
	return {
		listingId = raw.listingId,
		floor = if fl and fl == fl then math.clamp(math.floor(fl), -5, 200) else nil,
		unit = if type(raw.unit) == "string" and #raw.unit > 0 and #raw.unit <= 8 then raw.unit else nil,
		layoutId = cleanKey(raw.layoutId, 40),
		priceMult = if isFiniteNumber(raw.priceMult) then math.clamp(raw.priceMult, 0.5, 3) else 1,
		view = if isFiniteNumber(raw.view) then math.clamp(raw.view, 0, 1) else nil,
	}
end

-------------------------------------------------------------------------------------------------
-- v2: themes — more 벽지 / 바닥 / 조명 (appended to the v1 catalog; ids stay valid in old saves)
-------------------------------------------------------------------------------------------------
do
	local function add(order: { string }, t: { [string]: any }, id: string, def: any)
		if not t[id] then
			t[id] = def
			table.insert(order, id)
		end
	end
	add(HS.WALLPAPER_ORDER, HS.WALLPAPERS, "pastel_pink", { name = "파스텔 핑크", desc = "벚꽃 같은 은은한 핑크", color = { 238, 210, 210 }, material = "Plaster", price = 180000, decor = 3 })
	add(HS.WALLPAPER_ORDER, HS.WALLPAPERS, "mint", { name = "민트 그린", desc = "산뜻한 민트 페인트", color = { 198, 228, 214 }, material = "Plaster", price = 180000, decor = 3 })
	add(HS.WALLPAPER_ORDER, HS.WALLPAPERS, "charcoal", { name = "차콜 포인트", desc = "갤러리 같은 짙은 회색", color = { 72, 74, 80 }, material = "Plaster", price = 220000, decor = 4 })
	add(HS.WALLPAPER_ORDER, HS.WALLPAPERS, "terracotta", { name = "테라코타", desc = "지중해 감성 오렌지 브라운", color = { 196, 128, 98 }, material = "Plaster", price = 220000, decor = 4 })
	add(HS.WALLPAPER_ORDER, HS.WALLPAPERS, "subway_tile", { name = "서브웨이 타일", desc = "카페 주방 같은 화이트 타일", color = { 238, 238, 234 }, material = "CeramicTiles", price = 300000, decor = 4 })
	add(HS.WALLPAPER_ORDER, HS.WALLPAPERS, "brick_white", { name = "화이트 벽돌", desc = "성수동 카페 느낌", color = { 232, 228, 220 }, material = "Brick", price = 340000, decor = 5 })
	add(HS.FLOOR_ORDER, HS.FLOORS, "white_oak", { name = "화이트 오크", desc = "북유럽풍 밝은 원목", color = { 222, 198, 162 }, material = "WoodPlanks", price = 320000, decor = 3 })
	add(HS.FLOOR_ORDER, HS.FLOORS, "terrazzo", { name = "테라조", desc = "알갱이 무늬 인조석", color = { 216, 212, 206 }, material = "Granite", price = 480000, decor = 5 })
	add(HS.FLOOR_ORDER, HS.FLOORS, "black_marble", { name = "블랙 마블", desc = "호텔 로비 같은 검정 대리석", color = { 44, 44, 48 }, material = "Marble", price = 720000, decor = 7 })
	add(HS.FLOOR_ORDER, HS.FLOORS, "carpet_grey", { name = "그레이 카펫", desc = "포근한 카펫 마감", color = { 124, 124, 130 }, material = "Fabric", price = 260000, decor = 2 })
	add(HS.FLOOR_ORDER, HS.FLOORS, "hex_tile", { name = "헥사곤 타일", desc = "욕실·현관용 육각 타일", color = { 236, 232, 226 }, material = "CeramicTiles", price = 400000, decor = 4 })
	add(HS.LIGHT_ORDER, HS.LIGHTS, "daylight", { name = "태양광 5000K", desc = "낮처럼 밝고 깨끗한 빛", color = { 255, 246, 232 }, price = 30000, decor = 1 })
	add(HS.LIGHT_ORDER, HS.LIGHTS, "pink", { name = "핑크 무드", desc = "인스타 감성 핑크 조명", color = { 255, 176, 204 }, price = 60000, decor = 3 })
	add(HS.LIGHT_ORDER, HS.LIGHTS, "sunset", { name = "선셋 오렌지", desc = "광안리 노을 톤", color = { 255, 146, 96 }, price = 60000, decor = 3 })
end

-------------------------------------------------------------------------------------------------
-- Registration into G (called once from GwangalliGameplayShared)
-------------------------------------------------------------------------------------------------
HS.EXTRA_CATEGORIES = {
	appliance = { name = "가전", icon = "🔌", size = { 1.6, 6, 1.6 } },
	curtain = { name = "커튼", icon = "🪟", size = { 8, 7.6, 0.8 } },
	deco = { name = "장식", icon = "🕯️", size = { 1.6, 3, 1.6 } },
}
HS.EXTRA_STYLES = {
	cozy = { name = "코지", color = { 230, 170, 110 } },
	trendy = { name = "트렌디", color = { 255, 79, 163 } },
}

function HS.extend(G: any)
	if G.HOMES == HS then
		return
	end
	G.HOMES = HS
	GG = G
	-- categories / styles
	for _, src in { HS.EXTRA_CATEGORIES, HS.EXTRA_CATEGORIES_V2 } do
		for id, c in src do
			if not G.FURNITURE_CATEGORIES[id] then
				G.FURNITURE_CATEGORIES[id] = c
				table.insert(G.FURNITURE_CATEGORY_ORDER, id)
			end
		end
	end
	for id, st in HS.EXTRA_STYLES do
		if not G.FURNITURE_STYLES[id] then
			G.FURNITURE_STYLES[id] = st
			table.insert(G.FURNITURE_STYLE_ORDER, id)
		end
	end
	-- generators for the new categories (G.validateHousing asks the generator table)
	if type(G.FURNITURE_GEN) == "table" then
		for _, src in { HS.EXTRA_CATEGORIES, HS.EXTRA_CATEGORIES_V2 } do
			for id in src do
				G.FURNITURE_GEN[id] = G.FURNITURE_GEN[id] or function(spec: any, W: number, H: number, D: number, v: any)
					-- an extension variant always has its own builder; this is only reached for ids
					-- registered later without one: a plain block of the variant's main colour
					box(spec, "Block", W * 0.6, math.min(H, 2), D * 0.6, 0, math.min(H, 2) / 2, 0, v.main or WHITE, "SmoothPlastic", { collide = true })
				end
			end
		end
	end
	-- catalog
	for _, id in HS.FURNITURE_ORDER do
		if not G.FURNITURE[id] then
			G.FURNITURE[id] = HS.FURNITURE[id]
			table.insert(G.FURNITURE_ORDER, id)
		end
	end
	-- 창고 holds the free-placed pieces too when moving out
	G.HOME_STORAGE_MAX = math.max(G.HOME_STORAGE_MAX or 60, HS.DECOR.CAP)
	-- spec: the extension builders first, then G's generators
	local baseSpec = G.furnitureSpec
	G.furnitureSpec = function(variantId: string, W: number?, H: number?, D: number?): any?
		local v = HS.FURNITURE[variantId]
		if v and HS.BUILDERS[variantId] then
			local c = G.FURNITURE_CATEGORIES[v.category]
			local w = if isFiniteNumber(W) and (W :: number) > 0.2 then W :: number else c.size[1]
			local h = if isFiniteNumber(H) and (H :: number) > 0.05 then H :: number else c.size[2]
			local d = if isFiniteNumber(D) and (D :: number) > 0.05 then D :: number else c.size[3]
			return HS.spec(variantId, w, h, d)
		end
		return baseSpec(variantId, W, H, D)
	end
	-- home interaction kind + actions
	if not G.HOME_KINDS.interior then
		G.HOME_KINDS.interior = { action = "인테리어 꾸미기", object = "인테리어 패널", guest = true }
		table.insert(G.HOME_KIND_ORDER, "interior")
	end
	G.HOME_ACTIONS.rotateSlot = G.HOME_ACTIONS.rotateSlot or 0.3
	G.HOME_ACTIONS.setTheme = G.HOME_ACTIONS.setTheme or 0.5
	G.HOME_ACTIONS.openInterior = G.HOME_ACTIONS.openInterior or 0.5
	G.HOME_ACTIONS.tour = G.HOME_ACTIONS.tour or 2
	G.HOME_ACTIONS.compliment = G.HOME_ACTIONS.compliment or 2
	-- v2 actions (cooldown seconds per action; Housing adds a token bucket for the decor ones)
	G.HOME_ACTIONS.contract = G.HOME_ACTIONS.contract or 1.5
	G.HOME_ACTIONS.decorPlace = G.HOME_ACTIONS.decorPlace or 0.12
	G.HOME_ACTIONS.decorMove = G.HOME_ACTIONS.decorMove or 0.08
	G.HOME_ACTIONS.decorRemove = G.HOME_ACTIONS.decorRemove or 0.12
	G.HOME_ACTIONS.decorRestore = G.HOME_ACTIONS.decorRestore or 0.12
	G.HOME_ACTIONS.decorColor = G.HOME_ACTIONS.decorColor or 0.1
	G.HOME_ACTIONS.decorOpen = G.HOME_ACTIONS.decorOpen or 0.5
	G.HOME_ACTIONS.likeHome = G.HOME_ACTIONS.likeHome or 1
	G.HOME_ACTIONS.revealDone = G.HOME_ACTIONS.revealDone or 1
	-- unit prices: Floors' priceFor rounding when present
	local basePrices = G.homePrices
	if type(basePrices) == "function" then
		G.homePrices = function(listingId: string, choice: any?): any
			local p = basePrices(listingId, choice)
			local l = G.LISTINGS[listingId]
			if l and type(choice) == "table" and p.mult ~= 1 then
				p.deposit = HS.scalePrice(listingId, choice, l.deposit or 0)
				p.rentPerDay = if l.kind == "rent" then HS.scalePrice(listingId, choice, l.rentPerDay or 0) else 0
				p.price = HS.scalePrice(listingId, choice, l.price or 0)
			end
			return p
		end
	end
	-- saved record: keep the extension fields (themes, quarter turns, free pieces, address)
	local baseSanitize = G.sanitizeHousing
	G.sanitizeHousing = function(raw: any): any
		local h = baseSanitize(raw)
		if type(raw) == "table" and type(raw.units) == "table" then
			for lid, u in h.units do
				HS.sanitizeUnit(raw.units[lid], u)
				HS.sanitizeItems(raw.units[lid], u)
			end
		end
		h.address = if type(raw) == "table" then HS.sanitizeAddress(raw.address) else nil
		return h
	end
	-- after load: re-attach the address (floor / unit / layout) to d.home; migrate old saves
	local baseReconcile = G.reconcileHousing
	G.reconcileHousing = function(d: any)
		baseReconcile(d)
		local home = d.home
		if type(home) ~= "table" then
			if type(d.housing) == "table" then
				d.housing.address = nil
			end
			return
		end
		local a = type(d.housing) == "table" and d.housing.address or nil
		if type(a) == "table" and a.listingId == home.listingId and a.unit then
			home.floor, home.unit, home.layoutId, home.priceMult, home.view = a.floor, a.unit, a.layoutId, a.priceMult or 1, a.view
		else
			local c = HS.defaultChoice(home.listingId)
			if c then
				home.floor, home.unit, home.layoutId, home.priceMult, home.view = c.floor, c.unit, c.layoutId, 1, c.view
			end
		end
		if not HS.layout(home.layoutId) then
			local l = G.LISTINGS[home.listingId]
			home.layoutId = l and l.tierKey or home.layoutId
		end
		if type(G.setHomeAddress) == "function" then
			G.setHomeAddress(d)
		end
	end
	-- moving out: free-placed pieces go to 창고 too (over the cap they are sold at 50 %)
	local baseMoveOut = G.moveOutFurniture
	G.moveOutFurniture = function(d: any, listingId: string, now: number?): (number, number)
		local h = G.ensureHousing(d)
		local u = h.units[listingId]
		local moved, sold = 0, 0
		if type(u) == "table" and type(u.items) == "table" then
			local n = 0
			for _, c in h.storage do
				n += c
			end
			for _, it in u.items do
				local f = G.FURNITURE[it.i]
				if f then
					if n < G.HOME_STORAGE_MAX then
						h.storage[it.i] = (h.storage[it.i] or 0) + 1
						n += 1
						moved += 1
					else
						local amt = math.floor(f.price * HS.DECOR.REFUND)
						G.ledger(d, "bank", amt, "가구 판매 (이사) · " .. f.name, now)
						sold += amt
					end
				end
			end
			u.items = {}
		end
		local m2, s2 = baseMoveOut(d, listingId, now)
		return moved + m2, sold + s2
	end
	local baseValue = G.furnitureValue
	G.furnitureValue = function(d: any): number
		local v = baseValue(d)
		local h = d.housing
		local u = d.home and type(h) == "table" and h.units and h.units[d.home.listingId] or nil
		return v + HS.itemsValue(u)
	end
	-- decor: themes + free pieces count
	local baseDecor = G.homeDecor
	G.homeDecor = function(d: any): number
		local h = d.housing
		local u = d.home and type(h) == "table" and h.units and h.units[d.home.listingId] or nil
		return baseDecor(d) + HS.themeDecor(d) + HS.itemsDecor(u)
	end
	-- client view: rotation + themes + free pieces + address of the current home
	local baseView = G.housingView
	G.housingView = function(d: any): any
		local v = baseView(d)
		local lid = d.home and d.home.listingId
		local h = d.housing
		local u = lid and type(h) == "table" and h.units and h.units[lid] or nil
		local rot, walls, floors, lights = {}, {}, {}, {}
		if type(u) == "table" then
			for sid, r in u.rot or {} do
				rot[sid] = r
			end
			for room, id in u.walls or {} do
				walls[room] = id
			end
			for room, id in u.floors or {} do
				floors[room] = id
			end
			for room, id in u.lights or {} do
				lights[room] = id
			end
		end
		v.rot = rot
		v.walls = walls
		v.floors = floors
		v.lights = lights
		v.themeDecor = HS.themeDecor(d)
		v.itemCount = if type(u) == "table" and type(u.items) == "table" then #u.items else 0
		v.itemCap = HS.DECOR.CAP
		v.likes = if type(u) == "table" then (u.likes or 0) else 0
		local home = d.home
		if home then
			local lay = HS.layout(home.layoutId)
			v.address = { listingId = home.listingId, floor = home.floor or false, unit = home.unit or false, layoutId = home.layoutId or false, label = lay and lay.label or false, area = lay and lay.area or false, view = home.view or false, priceMult = home.priceMult or 1 }
		else
			v.address = false
		end
		return v
	end
end

return HS
