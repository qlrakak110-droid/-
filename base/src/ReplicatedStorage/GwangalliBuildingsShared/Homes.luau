-- GwangalliBuildings/Homes: the 내집마련 ladder (tiers, prices) and the metadata of every unit
-- template (sizes, room counts) shared by the server builders, the housing service and the realtor UI.
--
-- Ladder: 원룸 -> 빌라 -> 오피스텔 -> 아파트 -> 펜트하우스. With Config.LADDER_REQUIRED a player may
-- buy a home of tier N only when they own (or once owned) tier N-1. Moving up sells the old home back
-- at Config.TRADE_IN of its price.

local Homes = {}

Homes.TIERS = {
	{ id = "oneroom", name = "원룸", base = 1500000, icon = "🛏️", desc = "첫 독립! 작지만 내 공간" },
	{ id = "villa", name = "빌라", base = 4000000, icon = "🏘️", desc = "방이 생겼다, 투룸 · 쓰리룸" },
	{ id = "officetel", name = "오피스텔", base = 7000000, icon = "🏢", desc = "역세권 신축, 보안 · 편의점 1층" },
	{ id = "apartment", name = "아파트", base = 12000000, icon = "🏙️", desc = "엘리베이터 · 지하주차장 · 관리사무소" },
	{ id = "penthouse", name = "펜트하우스", base = 48000000, icon = "🌊", desc = "최상층 통창 오션뷰 + 루프 테라스" },
}
Homes.TIER_INDEX = {}
for i, t in Homes.TIERS do
	Homes.TIER_INDEX[t.id] = i
end

-- unit templates. w = width along the corridor (unit-local x), d = depth from the entrance wall
-- (unit-local z). mul = price multiplier inside the tier.
Homes.TEMPLATES = {
	oneroom_studio = { name = "원룸 (분리형)", tier = "oneroom", type = "원룸", w = 14, d = 22, rooms = 1, baths = 1, mul = 1.0 },
	villa_rooftop = { name = "옥탑방", tier = "oneroom", type = "옥탑 원룸", w = 18, d = 16, rooms = 1, baths = 1, mul = 0.85 },
	villa_2room = { name = "빌라 투룸", tier = "villa", type = "투룸", w = 26, d = 24, rooms = 2, baths = 1, mul = 1.0 },
	villa_3room = { name = "빌라 쓰리룸", tier = "villa", type = "쓰리룸", w = 26, d = 24, rooms = 3, baths = 1, mul = 1.2 },
	officetel_a = { name = "오피스텔 원룸형", tier = "officetel", type = "원룸형", w = 14, d = 20, rooms = 1, baths = 1, mul = 1.0 },
	officetel_b = { name = "오피스텔 1.5룸", tier = "officetel", type = "1.5룸", w = 20, d = 20, rooms = 2, baths = 1, mul = 1.3 },
	apt_1room = { name = "아파트 원룸형", tier = "apartment", type = "원룸", w = 16, d = 30, rooms = 1, baths = 1, mul = 0.72 },
	apt_2room = { name = "아파트 투룸", tier = "apartment", type = "투룸", w = 24, d = 30, rooms = 2, baths = 1, mul = 0.86 },
	apt_3room = { name = "아파트 3룸 (84㎡형)", tier = "apartment", type = "3룸", w = 32, d = 30, rooms = 3, baths = 2, mul = 1.0 },
	apt_penthouse = { name = "오션뷰 펜트하우스", tier = "penthouse", type = "펜트하우스", w = 96, d = 30, rooms = 4, baths = 3, mul = 1.0 },
	-- hotel rooms: rented through the front desk, never sold (hotel = true)
	hotel_standard = { name = "스탠다드 더블", hotel = true, type = "객실", w = 12.5, d = 21, rooms = 1, baths = 1, mul = 0 },
	hotel_deluxe = { name = "디럭스 오션뷰", hotel = true, type = "객실", w = 14.4, d = 21, rooms = 1, baths = 1, mul = 0 },
	hotel_suite = { name = "로열 스위트", hotel = true, type = "스위트", w = 25, d = 21, rooms = 2, baths = 1, mul = 0 },
}

-- price of a concrete unit: tier base x template x floor premium x view x age
function Homes.price(templateId: string, floor: number, view: string?, wear: number?): number
	local t = Homes.TEMPLATES[templateId]
	if not t or t.hotel then
		return 0
	end
	local tier = Homes.TIERS[Homes.TIER_INDEX[t.tier]]
	local p = tier.base * t.mul
	p *= 1 + math.max(0, floor - 2) * 0.015
	if view == "ocean" then
		p *= 1.12
	elseif view == "street" then
		p *= 0.96
	end
	p *= 1 - 0.25 * math.clamp(wear or 0, 0, 1)
	return math.floor(p / 10000 + 0.5) * 10000
end

function Homes.tierIndex(tierId: string?): number
	return if tierId then (Homes.TIER_INDEX[tierId] or 0) else 0
end

-- may a player whose highest owned tier is `maxTier` buy a home of `tierId`?
function Homes.canClimb(maxTier: string?, tierId: string, ladder: boolean): (boolean, string?)
	if not ladder then
		return true
	end
	local have = Homes.tierIndex(maxTier)
	local want = Homes.tierIndex(tierId)
	if want <= have + 1 then
		return true
	end
	local need = Homes.TIERS[want - 1]
	return false, string.format("먼저 %s을(를) 마련해야 해요 (내집마련 단계)", need.name)
end

return Homes
