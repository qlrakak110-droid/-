--!strict
-- GwangalliDecorShared/Catalog: the 자유 배치 furniture catalog (>= 150 procedurally built pieces in 14
-- categories), colour / material slots, specs, exact bounds, collision boxes, stacking surfaces,
-- interactions, search (초성 too), sorting, 스타일 세트.
--   Catalog.CATEGORIES / Catalog.STYLES / Catalog.ORDER (item ids) / Catalog.get(id)
--   Catalog.resolve(def, c?, m?) -> slots { [key] = { rgb, mat } }    c = { [slotIndex] = "RRGGBB" | false }
--   Catalog.spec(id, c?, m?, st?) -> spec (Kit format) | nil
--   Catalog.bounds(id) -> { x0, y0, z0, x1, y1, z1 } (exact, closed state, item frame)
--   Catalog.boxes(id) -> { { cf, half } } collision boxes      Catalog.tops(id) -> stacking surfaces
--   Catalog.partCount(id) / lightCount(id) / uses(id) / list(cat, opts) / search(q) / price(id)
-- Item files (ItemsLiving ... ItemsKids) register pieces through Catalog.define (see D below).

local Palette = require(script.Parent:WaitForChild("Palette"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Text = require(script.Parent:WaitForChild("Text"))

local Catalog = {}

Catalog.CATEGORIES = {
	{ id = "living", name = "거실", icon = "🛋️" },
	{ id = "bedroom", name = "침실", icon = "🛏️" },
	{ id = "kitchen", name = "주방", icon = "🍳" },
	{ id = "bath", name = "욕실", icon = "🛁" },
	{ id = "lighting", name = "조명", icon = "💡" },
	{ id = "plants", name = "식물", icon = "🪴" },
	{ id = "wall", name = "벽장식", icon = "🖼️" },
	{ id = "tech", name = "가전·전자", icon = "📺" },
	{ id = "rugs", name = "러그·카펫", icon = "🧶" },
	{ id = "storage", name = "수납", icon = "📚" },
	{ id = "hobby", name = "취미·게임", icon = "🎮" },
	{ id = "veranda", name = "베란다", icon = "🌿" },
	{ id = "season", name = "시즌·파티", icon = "🎉" },
	{ id = "kids", name = "아이·펫", icon = "🧸" },
}
Catalog.CAT_BY_ID = {} :: { [string]: any }
for i, c in Catalog.CATEGORIES do
	c.order = i
	Catalog.CAT_BY_ID[c.id] = c
end

Catalog.STYLES = {
	{ id = "modern", name = "모던" },
	{ id = "natural", name = "내추럴" },
	{ id = "cozy", name = "코지" },
	{ id = "luxury", name = "럭셔리" },
	{ id = "trendy", name = "트렌디" },
	{ id = "classic", name = "클래식" },
	{ id = "kids", name = "키즈" },
	{ id = "season", name = "시즌" },
}
Catalog.STYLE_BY_ID = {} :: { [string]: any }
for _, s in Catalog.STYLES do
	Catalog.STYLE_BY_ID[s.id] = s
end

Catalog.ITEMS = {} :: { [string]: any }
Catalog.ORDER = {} :: { string }

-------------------------------------------------------------------------------------------------
-- Registration API handed to the item files
-------------------------------------------------------------------------------------------------
local D = {}

-- colour slot: key, Korean label, default colour (swatch key or rgb), material keys (first = default)
function D.slot(key: string, label: string, default: any, mats: { string }?): any
	local rgb = if type(default) == "string" then (Palette.BY_KEY[default] and Palette.BY_KEY[default].rgb or { 200, 200, 200 }) else default
	return { key = key, label = label, rgb = rgb, mats = mats or { "plastic" } }
end

local VALID_PLACE = { floor = true, surface = true, wall = true, ceiling = true, rug = true }

-- def = { id, cat, name, price, decor, style, place, size = {w, h, d}, slots, build(k, W, H, D),
--         light = rgb | swatch key (adds the "light" slot), uses = { open = "문 열기" ... }, tags, desc }
function D.item(def: any)
	assert(type(def.id) == "string" and not Catalog.ITEMS[def.id], "duplicate / bad item id " .. tostring(def.id))
	assert(Catalog.CAT_BY_ID[def.cat], "bad category " .. tostring(def.cat) .. " for " .. def.id)
	assert(VALID_PLACE[def.place], "bad place kind for " .. def.id)
	assert(type(def.build) == "function", "no builder for " .. def.id)
	def.slots = def.slots or {}
	if def.light then
		local rgb = if type(def.light) == "string" then nil else def.light
		if not rgb then
			for _, l in Palette.LIGHTS do
				if l[1] == def.light then
					rgb = l[3]
				end
			end
		end
		table.insert(def.slots, { key = "light", label = "빛 색", rgb = rgb or { 255, 206, 150 }, mats = { "neon" }, isLight = true })
	end
	def.slotIndex = {}
	for i, s in def.slots do
		def.slotIndex[s.key] = i
	end
	def.style = def.style or "modern"
	def.decor = def.decor or 1
	def.size = def.size or { 2, 2, 2 }
	def.tags = def.tags or {}
	def.order = #Catalog.ORDER + 1
	Catalog.ITEMS[def.id] = def
	table.insert(Catalog.ORDER, def.id)
end

Catalog.D = D
D.Palette = Palette

-------------------------------------------------------------------------------------------------
-- Colour / material resolution
-------------------------------------------------------------------------------------------------
-- c[i] = "RRGGBB" | false (default), m[i] = material index into the slot's mats (1 = default)
function Catalog.resolve(def: any, c: { any }?, m: { any }?): { [string]: any }
	local out = {}
	for i, s in def.slots do
		local rgb = s.rgb
		local hx = c and c[i]
		if type(hx) == "string" then
			rgb = Palette.unhex(hx) or rgb
		end
		local mi = m and m[i]
		local mat = s.mats[1]
		if type(mi) == "number" and s.mats[mi] then
			mat = s.mats[mi]
		end
		out[s.key] = { rgb = rgb, mat = mat }
	end
	return out
end

function Catalog.get(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	return Catalog.ITEMS[id]
end

local function build(def: any, c: { any }?, m: { any }?, st: any?): any?
	local slots = Catalog.resolve(def, c, m)
	local k = Kit.new(slots, st)
	local W, H, Dd = def.size[1], def.size[2], def.size[3]
	local ok, err = pcall(def.build, k, W, H, Dd)
	if not ok then
		warn("[GwangalliDecorShared] item " .. def.id .. " build failed: " .. tostring(err))
		return nil
	end
	local spec = k:spec()
	if #spec.parts == 0 then
		return nil
	end
	spec.id = def.id
	return spec
end

-- spec cache: default looks are cached for good; custom looks in a small ring
local defaultCache: { [string]: any } = {}
local ring: { [string]: any } = {}
local ringKeys: { string } = {}

local function lookKey(c: { any }?, m: { any }?, st: any?): string
	local parts = {}
	if c then
		for i = 1, 6 do
			parts[#parts + 1] = if type(c[i]) == "string" then c[i] else "-"
		end
	end
	if m then
		for i = 1, 6 do
			parts[#parts + 1] = tostring(m[i] or 1)
		end
	end
	if st and st.op then
		parts[#parts + 1] = "op"
	end
	return table.concat(parts, ".")
end

function Catalog.spec(id: string, c: { any }?, m: { any }?, st: any?): any?
	local def = Catalog.ITEMS[id]
	if not def then
		return nil
	end
	local key = lookKey(c, m, nil)
	if key == "" or not string.find(key, "[^%-%.1]") then
		local s = defaultCache[id]
		if s == nil then
			s = build(def, nil, nil, nil) or false
			defaultCache[id] = s
		end
		return if s then s else nil
	end
	local full = id .. "|" .. key
	local s = ring[full]
	if s then
		return s
	end
	s = build(def, c, m, st)
	if s then
		ring[full] = s
		table.insert(ringKeys, full)
		if #ringKeys > 64 then
			ring[table.remove(ringKeys, 1) :: string] = nil
		end
	end
	return s
end

-------------------------------------------------------------------------------------------------
-- Exact bounds / collision boxes / surfaces (closed state, default look: geometry never depends on
-- colours or materials)
-------------------------------------------------------------------------------------------------
-- world-axis half extents of a part (exact for blocks, balls and cylinders under any rotation)
function Catalog.partExtent(p: any): Vector3
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.cf:GetComponents()
	local s = p.size
	if p.shape == "Ball" then
		local r = math.min(s.X, s.Y, s.Z) / 2
		return Vector3.new(r, r, r)
	elseif p.shape == "Cylinder" then
		local hl, r = s.X / 2, math.min(s.Y, s.Z) / 2
		local ax, ay, az = r00, r10, r20 -- the cylinder axis = the part's X axis
		return Vector3.new(
			math.abs(ax) * hl + r * math.sqrt(math.max(0, 1 - ax * ax)),
			math.abs(ay) * hl + r * math.sqrt(math.max(0, 1 - ay * ay)),
			math.abs(az) * hl + r * math.sqrt(math.max(0, 1 - az * az))
		)
	end
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	return Vector3.new(
		math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz,
		math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz,
		math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	)
end

local geoCache: { [string]: any } = {}

local function geometry(id: string): any
	local g = geoCache[id]
	if g then
		return g
	end
	local spec = Catalog.spec(id)
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	local boxes, tops = {}, {}
	local nParts, nLights = 0, 0
	if spec then
		for _, p in spec.parts do
			local e = Catalog.partExtent(p)
			local c = p.cf.Position
			x0, y0, z0 = math.min(x0, c.X - e.X), math.min(y0, c.Y - e.Y), math.min(z0, c.Z - e.Z)
			x1, y1, z1 = math.max(x1, c.X + e.X), math.max(y1, c.Y + e.Y), math.max(z1, c.Z + e.Z)
			if p.solid then
				table.insert(boxes, { cf = p.cf, half = p.size / 2 })
			end
			if p.top then
				table.insert(tops, { cf = p.cf, half = p.size / 2 })
			end
		end
		nParts = #spec.parts + #spec.seats
		nLights = #spec.lights
	end
	if x0 == math.huge then
		x0, y0, z0, x1, y1, z1 = -0.5, 0, -0.5, 0.5, 1, 0.5
	end
	local b = { x0, math.max(y0, -0.02), z0, x1, y1, z1 }
	if #boxes == 0 then
		-- no part marked solid: the whole piece is one box
		table.insert(boxes, {
			cf = CFrame.new((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2),
			half = Vector3.new((b[4] - b[1]) / 2, (b[5] - b[2]) / 2, (b[6] - b[3]) / 2),
		})
	end
	g = { bounds = b, boxes = boxes, tops = tops, parts = nParts, lights = nLights, spec = spec }
	geoCache[id] = g
	return g
end

function Catalog.bounds(id: string): { number }
	return geometry(id).bounds
end

function Catalog.boxes(id: string): { any }
	return geometry(id).boxes
end

function Catalog.tops(id: string): { any }
	return geometry(id).tops
end

function Catalog.partCount(id: string): number
	return geometry(id).parts
end

function Catalog.lightCount(id: string): number
	return geometry(id).lights
end

-- centre CFrame + half size of the exact bounds (item frame)
function Catalog.box(id: string): (CFrame, Vector3)
	local b = Catalog.bounds(id)
	return CFrame.new((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2), Vector3.new((b[4] - b[1]) / 2, (b[5] - b[2]) / 2, (b[6] - b[3]) / 2)
end

-- size in studs (exact bounds)
function Catalog.dims(id: string): Vector3
	local b = Catalog.bounds(id)
	return Vector3.new(b[4] - b[1], b[5] - b[2], b[6] - b[3])
end

-------------------------------------------------------------------------------------------------
-- Interactions of a piece (what ProximityPrompts / the inspect card offer)
-------------------------------------------------------------------------------------------------
function Catalog.uses(id: string): { [string]: any }
	local def = Catalog.ITEMS[id]
	local g = geometry(id)
	local spec = g.spec
	local out: { [string]: any } = {}
	if not def or not spec then
		return out
	end
	for _, s in spec.seats do
		if s.lie then
			out.lie = true
		else
			out.sit = true
		end
	end
	local hasScreen = false
	for _, p in spec.parts do
		if p.screen then
			hasScreen = true
		end
	end
	if hasScreen then
		out.tv = true
	elseif #spec.lights > 0 or def.glow then
		out.lamp = def.toggle ~= false
	end
	if spec.hasPose then
		out.open = def.uses and def.uses.open or "열기"
		out.close = def.uses and def.uses.close or "닫기"
	end
	if spec.speaker then
		out.music = true
	end
	if spec.fire then
		out.fire = true
	end
	if spec.tank then
		out.feed = true
	end
	return out
end

-- does any colour slot carry a light colour?
function Catalog.lightSlot(id: string): number?
	local def = Catalog.ITEMS[id]
	if not def then
		return nil
	end
	return def.slotIndex.light
end

-------------------------------------------------------------------------------------------------
-- Browsing
-------------------------------------------------------------------------------------------------
local searchIndex: { [string]: { name: string, cho: string, tags: string } } = {}

local function indexOf(id: string): any
	local s = searchIndex[id]
	if s then
		return s
	end
	local def = Catalog.ITEMS[id]
	local cat = Catalog.CAT_BY_ID[def.cat]
	local st = Catalog.STYLE_BY_ID[def.style]
	local tags = table.concat(def.tags, " ") .. " " .. cat.name .. " " .. (st and st.name or "")
	s = { name = string.lower(def.name), cho = Text.chosung(def.name), tags = string.lower(tags), tagsCho = Text.chosung(tags) }
	searchIndex[id] = s
	return s
end

-- item ids matching a free-text query (Korean names, tags, category / style names, 초성)
function Catalog.search(q: string, pool: { string }?): { string }
	local query = string.lower(Text.clip(q, 24))
	local src = pool or Catalog.ORDER
	if query == "" then
		return table.clone(src)
	end
	local cho = Text.isChosungQuery(query)
	local terms = string.split(query, " ")
	local out = {}
	for _, id in src do
		local s = indexOf(id)
		local hit = true
		for _, t in terms do
			if t ~= "" then
				local found
				if cho then
					found = string.find(string.gsub(s.cho, " ", ""), (string.gsub(t, " ", "")), 1, true) ~= nil or string.find(s.tagsCho, t, 1, true) ~= nil
				else
					found = string.find(s.name, t, 1, true) ~= nil or string.find(s.tags, t, 1, true) ~= nil or string.find(id, t, 1, true) ~= nil
				end
				if not found then
					hit = false
					break
				end
			end
		end
		if hit then
			table.insert(out, id)
		end
	end
	return out
end

-- opts = { style = id?, sort = "price" | "priceDesc" | "decor" | "new", query = string? }
function Catalog.list(cat: string?, opts: any?): { string }
	local o = opts or {}
	local out = {}
	for _, id in Catalog.ORDER do
		local def = Catalog.ITEMS[id]
		if (cat == nil or cat == "all" or def.cat == cat) and (o.style == nil or o.style == "all" or def.style == o.style) then
			table.insert(out, id)
		end
	end
	if o.query and o.query ~= "" then
		out = Catalog.search(o.query, out)
	end
	local sort = o.sort or "price"
	table.sort(out, function(a, b)
		local da, db = Catalog.ITEMS[a], Catalog.ITEMS[b]
		if sort == "priceDesc" then
			if da.price ~= db.price then
				return da.price > db.price
			end
		elseif sort == "decor" then
			if da.decor ~= db.decor then
				return da.decor > db.decor
			end
		elseif sort == "new" then
			return da.order > db.order
		else
			if da.price ~= db.price then
				return da.price < db.price
			end
		end
		return da.order < db.order
	end)
	return out
end

function Catalog.price(id: string): number
	local def = Catalog.ITEMS[id]
	return def and def.price or 0
end

function Catalog.resale(id: string, rate: number): number
	return math.floor(Catalog.price(id) * rate / 100) * 100
end

-- Korean label of a piece's current look ("모던 카우치 · 카멜 가죽")
function Catalog.lookName(id: string, c: { any }?, m: { any }?): string
	local def = Catalog.ITEMS[id]
	if not def or #def.slots == 0 then
		return ""
	end
	local s = def.slots[1]
	local rgb = s.rgb
	if c and type(c[1]) == "string" then
		rgb = Palette.unhex(c[1]) or rgb
	end
	local mat = s.mats[(m and m[1]) or 1] or s.mats[1]
	local md = (Palette.MATERIALS :: any)[mat]
	return Palette.nameOf(rgb) .. (if md and #s.mats > 1 then " " .. md.name else "")
end

-------------------------------------------------------------------------------------------------
-- Item files
-------------------------------------------------------------------------------------------------
Catalog.FILES = {
	"ItemsLiving", "ItemsBedroom", "ItemsKitchen", "ItemsBath", "ItemsLighting", "ItemsPlants", "ItemsWall",
	"ItemsTech", "ItemsRugs", "ItemsStorage", "ItemsHobby", "ItemsVeranda", "ItemsSeason", "ItemsKids",
}
for _, name in Catalog.FILES do
	local m = script.Parent:FindFirstChild(name) or script.Parent:WaitForChild(name, 10)
	if m then
		local ok, fn = pcall(require, m)
		if ok and type(fn) == "function" then
			local okR, err = pcall(fn, D)
			if not okR then
				warn("[GwangalliDecorShared] " .. name .. ": " .. tostring(err))
			end
		else
			warn("[GwangalliDecorShared] " .. name .. " failed to load: " .. tostring(fn))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- 스타일 세트 (shopping lists; ids are checked, missing ones dropped)
-------------------------------------------------------------------------------------------------
local RAW_SETS = {
	{ id = "ocean", name = "광안리 오션 미니멀", icon = "🌊", desc = "화이트 · 블루 톤으로 바다 뷰를 살린 미니멀", items = { "lv_sofa_modular", "lv_coffee_round", "rg_wave", "lt_floor_arc", "pl_olive", "wl_bridge_art", "tc_tv_frame" } },
	{ id = "wood", name = "따뜻한 우드 원룸", icon = "🪵", desc = "원목 가구와 린넨으로 채운 아늑한 원룸", items = { "bd_wood_queen", "bd_nightstand_oak", "lv_coffee_oak", "lt_table_linen", "rg_jute", "pl_fiddle", "st_ladder" } },
	{ id = "gamer", name = "트렌디 게이밍 룸", icon = "🎮", desc = "RGB 조명과 듀얼 모니터 데스크", items = { "hb_gaming_desk", "hb_gaming_chair", "lt_neon_wall", "tc_console", "rg_checker", "hb_arcade", "lt_led_strip" } },
	{ id = "hotel", name = "호텔 스위트 럭셔리", icon = "🏨", desc = "벨벳 · 대리석 · 골드로 꾸민 호텔 스위트", items = { "lv_chesterfield", "lv_coffee_marble", "lt_chandelier", "bd_canopy", "rg_persian", "wl_mirror_gold", "lv_fireplace" } },
	{ id = "jungle", name = "플랜테리어 정글", icon = "🌿", desc = "식물로 가득 찬 초록 거실", items = { "pl_monstera", "pl_strelitzia", "pl_hanging_pothos", "pl_snake", "pl_cactus_trio", "vr_planter_box", "lv_rattan_chair" } },
	{ id = "cafe", name = "홈카페 키친", icon = "☕", desc = "커피머신과 우드 선반이 있는 홈카페", items = { "kt_coffee_station", "kt_bistro_set", "kt_wall_shelf", "kt_pendant_trio", "pl_herb_pots", "kt_cake_stand" } },
	{ id = "kids", name = "꿈나라 키즈룸", icon = "🧸", desc = "아이와 반려동물이 함께 쓰는 방", items = { "kd_car_bed", "kd_tent", "kd_toy_chest", "kd_bear_big", "kd_cat_tower", "rg_playmat" } },
	{ id = "party", name = "집들이 파티", icon = "🎉", desc = "미러볼과 풍선으로 집들이 준비 끝", items = { "ss_balloon_arch", "ss_mirrorball", "ss_party_table", "ss_garland", "tc_speaker_tower", "ss_cake" } },
}
Catalog.SETS = {}
for _, s in RAW_SETS do
	local items = {}
	local total = 0
	for _, id in s.items do
		if Catalog.ITEMS[id] then
			table.insert(items, id)
			total += Catalog.ITEMS[id].price
		end
	end
	if #items >= 3 then
		table.insert(Catalog.SETS, { id = s.id, name = s.name, icon = s.icon, desc = s.desc, items = items, total = total })
	end
end

return Catalog
