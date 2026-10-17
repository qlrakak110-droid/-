-- GwangalliShopCrewShared/Personas: who works where. Pure data + deterministic picks (the same shop always has
-- the same people: seed = shop key + role).
--   Personas.roster(shopType, ctx) -> { RoleDef }   ctx = { tables = n, flow = "table" | ..., staffed = bool }
--       staffed = a ShopStaff / GwShopClerk / venue staff already works the counter (no cashier of ours then)
--   Personas.make(shopKey, shopType, def) -> Persona
--       { role, title, given, family, full, label, look = { body, age, style }, dialect, icon, color?, speed }
--   Personas.forStaff(kind, label, seedKey) -> Persona-like table for augmented staff (existing rigs)
--   Personas.ROLES -> role ids        Personas.TYPES -> the ShopLife types that have a roster
-- RoleDef = { role, title, body?, age?, style?, dialect?, icon?, optional? ("cashier": only when nobody else
--   works the counter), minTables? }

local Util = require(script.Parent:WaitForChild("Util"))

local Personas = {}

Personas.ROLES = { "cook", "waiter", "cashier", "barista", "floor", "stocker", "baker", "stylist", "pharmacist" }

-- roles per ShopLife type (StreetShops.TYPES keys). Types not listed get no crew of their own (ShopStaff,
-- GwShopClerk and venue staff work them; this add-on only gives those people a real conversation)
local R: { [string]: { any } } = {
	soup = {
		{ role = "cook", title = "사장님", body = "f", age = "middle", style = "chef", dialect = "busan", icon = "👩‍🍳" },
		{ role = "waiter", title = "홀 이모", body = "f", age = "middle", style = "apron", dialect = "busan", icon = "🙋‍♀️" },
		{ role = "cashier", title = "카운터 알바", age = "young", style = "apron", dialect = "std", icon = "🧾", optional = true },
	},
	noodle = {
		{ role = "cook", title = "주방장", body = "m", age = "adult", style = "chef", dialect = "std", icon = "🧑‍🍳" },
		{ role = "waiter", title = "홀 알바", age = "young", style = "apron", dialect = "std", icon = "🙋" },
		{ role = "cashier", title = "카운터 알바", age = "young", style = "apron", dialect = "std", icon = "🧾", optional = true },
	},
	katsu = {
		{ role = "cook", title = "셰프", body = "m", age = "adult", style = "chef", dialect = "std", icon = "🧑‍🍳" },
		{ role = "waiter", title = "홀 알바", age = "young", style = "apron", dialect = "std", icon = "🙋" },
		{ role = "cashier", title = "카운터 알바", age = "young", style = "apron", dialect = "std", icon = "🧾", optional = true },
	},
	chinese = {
		{ role = "cook", title = "주방장", body = "m", age = "middle", style = "chef", dialect = "std", icon = "🧑‍🍳" },
		{ role = "waiter", title = "홀 알바", age = "young", style = "apron", dialect = "std", icon = "🙋" },
		{ role = "cashier", title = "사모님", body = "f", age = "middle", style = "apron", dialect = "busan", icon = "🧾", optional = true },
	},
	grill = {
		{ role = "cook", title = "이모", body = "f", age = "middle", style = "apron", dialect = "busan", icon = "🔥" },
		{ role = "waiter", title = "막내 알바", age = "young", style = "apron", dialect = "std", icon = "🙋" },
	},
	pocha = {
		{ role = "cook", title = "포차 이모", body = "f", age = "senior", style = "apron", dialect = "busan", icon = "🏮" },
		{ role = "waiter", title = "막내 알바", age = "young", style = "street", dialect = "std", icon = "🙋" },
	},
	rawfish = {
		{ role = "cook", title = "사장님", body = "m", age = "middle", style = "fisher", dialect = "busan", icon = "🐟" },
		{ role = "waiter", title = "이모", body = "f", age = "middle", style = "apron", dialect = "busan", icon = "🙋‍♀️" },
	},
	seafood = {
		{ role = "cook", title = "사장님", body = "m", age = "middle", style = "fisher", dialect = "busan", icon = "🦀" },
		{ role = "waiter", title = "이모", body = "f", age = "middle", style = "apron", dialect = "busan", icon = "🙋‍♀️" },
	},
	chicken = {
		{ role = "cook", title = "사장님", body = "m", age = "adult", style = "chef", dialect = "std", icon = "🍗" },
		{ role = "waiter", title = "홀 알바", age = "young", style = "apron", dialect = "std", icon = "🙋" },
		{ role = "cashier", title = "카운터 알바", age = "young", style = "apron", dialect = "std", icon = "🧾", optional = true },
	},
	pub = {
		{ role = "cook", title = "호프 사장님", body = "m", age = "adult", style = "black", dialect = "busan", icon = "🍹" },
		{ role = "waiter", title = "서버", age = "young", style = "black", dialect = "std", icon = "🙋" },
	},
	snack = {
		{ role = "cook", title = "분식 이모", body = "f", age = "middle", style = "apron", dialect = "busan", icon = "🍢" },
		{ role = "waiter", title = "알바", age = "young", style = "apron", dialect = "std", icon = "🙋", minTables = 2 },
	},
	cafe = {
		{ role = "barista", title = "바리스타", age = "young", style = "apron", dialect = "std", icon = "☕" },
		{ role = "floor", title = "매장 알바", age = "young", style = "apron", dialect = "std", icon = "🧽", minTables = 4 },
	},
	burger = {
		{ role = "cook", title = "주방 크루", age = "young", style = "apron", dialect = "std", icon = "🍔" },
		{ role = "floor", title = "홀 크루", age = "young", style = "apron", dialect = "std", icon = "🧽", minTables = 4 },
	},
	dessert = {
		{ role = "cook", title = "점원", body = "f", age = "young", style = "apron", dialect = "std", icon = "🍨" },
	},
	bakery = {
		{ role = "baker", title = "제빵사", age = "adult", style = "chef", dialect = "std", icon = "🥐" },
	},
	cvs = {
		{ role = "stocker", title = "편의점 알바", age = "young", style = "casual", dialect = "std", icon = "📦" },
	},
	retail = {
		{ role = "stocker", title = "매장 직원", age = "young", style = "trendy", dialect = "std", icon = "🛍️" },
	},
	salon = {
		{ role = "stylist", title = "디자이너", age = "young", style = "black", dialect = "std", icon = "💇" },
	},
	pharmacy = {
		{ role = "pharmacist", title = "약사님", age = "middle", style = "doctor", dialect = "std", icon = "💊", optional = true },
	},
}
Personas.ROSTER = R
Personas.TYPES = {}
for t in R do
	table.insert(Personas.TYPES, t)
end
table.sort(Personas.TYPES)

-- name pools ------------------------------------------------------------------------------------------
local FAMILY = { "김", "이", "박", "최", "정", "강", "조", "윤", "장", "임", "한", "오", "서", "신", "권" }
local GIVEN = {
	f_old = { "순자", "미숙", "영희", "정자", "경숙", "명희", "옥순", "말순", "춘자", "미경", "복순", "숙희" },
	f_young = { "지수", "서연", "수빈", "민지", "하은", "예린", "유나", "채원", "다은", "지민", "소율", "가은" },
	m_old = { "철수", "영수", "상훈", "동욱", "재석", "성호", "기철", "만수", "병철", "정훈", "덕배", "용팔" },
	m_young = { "민준", "하준", "도윤", "지호", "현우", "준서", "태윤", "시우", "건우", "은호", "재민", "유찬" },
}

local SPEED = { cook = 5.5, waiter = 7.0, cashier = 6.0, barista = 5.8, floor = 6.2, stocker = 5.6, baker = 5.4, stylist = 5.6, pharmacist = 5.4 }

-- the roles a shop of this type gets
function Personas.roster(shopType: string, ctx: any?): { any }
	local c = ctx or {}
	local out = {}
	for _, def in R[shopType] or {} do
		local ok = true
		if def.optional and c.staffed then
			ok = false
		end
		if def.minTables and (tonumber(c.tables) or 0) < def.minTables then
			ok = false
		end
		if def.role == "waiter" and c.flow ~= nil and c.flow ~= "table" and (tonumber(c.tables) or 0) < 2 then
			ok = false
		end
		if ok then
			table.insert(out, def)
		end
	end
	return out
end

function Personas.make(shopKey: string, shopType: string, def: any): any
	local seed = Util.hash(tostring(shopKey) .. "|" .. tostring(def.role))
	local r = Util.rng(seed)
	local body = def.body or (if r() < 0.55 then "f" else "m")
	local age = def.age or "young"
	local old = age == "middle" or age == "senior" or age == "adult"
	local pool = GIVEN[body .. (if old then "_old" else "_young")]
	local given = Util.pick(pool, r) :: string
	local family = Util.pick(FAMILY, r) :: string
	return {
		role = def.role,
		title = def.title,
		given = given,
		family = family,
		full = family .. given,
		label = def.title,
		look = { body = body, age = age, style = def.style or "apron" },
		dialect = def.dialect or "std",
		icon = def.icon or "🙂",
		speed = SPEED[def.role] or 6,
		type = shopType,
		seed = seed,
	}
end

-- augmented staff (a ShopStaff counter rig / GwShopClerk / VenueStaff): their label stays, we add a voice
local STAFF_KIND_DIALECT = { food = "busan", pharmacy = "std", game = "std", cvs = "std", cafe = "std", pub = "std", salon = "std" }
function Personas.forStaff(kind: string?, label: string?, seedKey: string): any
	local seed = Util.hash(seedKey)
	local r = Util.rng(seed)
	local lbl = if type(label) == "string" and label ~= "" then label else "직원"
	local busan = STAFF_KIND_DIALECT[kind or ""] == "busan" or string.find(lbl, "이모", 1, true) ~= nil or string.find(lbl, "사장", 1, true) ~= nil
	local body = if string.find(lbl, "이모", 1, true) then "f" else (if r() < 0.5 then "f" else "m")
	local given = Util.pick(GIVEN[body .. "_young"], r) :: string
	if busan then
		given = Util.pick(GIVEN[body .. "_old"], r) :: string
	end
	local family = Util.pick(FAMILY, r) :: string
	return {
		role = "staff",
		kind = kind or "shop",
		title = lbl,
		given = given,
		family = family,
		full = family .. given,
		label = lbl,
		dialect = if busan and r() < 0.85 then "busan" else "std",
		icon = "🙂",
		seed = seed,
	}
end

return Personas
