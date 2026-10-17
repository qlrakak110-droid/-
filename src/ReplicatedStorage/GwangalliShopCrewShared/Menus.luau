-- GwangalliShopCrewShared/Menus: what the staff sell at counters ShopLife does not run (홈플러스 POS, 빵집 POS,
-- 호텔 프런트, PC방 · 노래방 카운터, 거리의 대여소 ...). ShopLife shops always use ShopLife's own menu
-- (StreetShops) instead: these lists only exist so that every counter staff can actually sell something real.
--   Menus.forKind(kind) -> { Item }?     kind = ShopStaff kind (cvs, mart, cafe, bakery, pharmacy, pub, food, game,
--                                        hotel, rental, beauty ...) or a venue kind (pc, karaoke)
--   Menus.item(kind, id) -> Item?
-- Item = { id, name, price, icon, dish (FoodKit builder for the held item), tint?, kind = "food" | "drink" | "goods",
--          effect = { Satiety?, Energy?, Fun?, Hygiene? } (GwangalliBuildings Needs), bites, here (can be eaten in) }
-- No alcohol anywhere (the build is alcohol-free).

local Menus = {}

local function I(id: string, name: string, price: number, icon: string, dish: string, kind: string, effect: any, extra: any?): any
	local it = { id = id, name = name, price = price, icon = icon, dish = dish, kind = kind, effect = effect, bites = 3, here = kind ~= "goods" }
	for k, v in extra or {} do
		it[k] = v
	end
	return it
end

local LISTS: { [string]: { any } } = {
	cvs = {
		I("samgak", "삼각김밥 (참치마요)", 1500, "🍙", "samgak", "food", { Satiety = 14 }),
		I("cupramen", "컵라면", 1800, "🍜", "cupramen", "food", { Satiety = 20 }, { bites = 4 }),
		I("banana", "바나나맛 우유", 1700, "🥛", "milk", "drink", { Satiety = 5, Energy = 3 }, { tint = "banana" }),
		I("water", "생수 500ml", 900, "💧", "water", "drink", { Energy = 4 }),
		I("hotbar", "핫바", 2500, "🌭", "hotbar", "food", { Satiety = 10 }),
		I("chips", "감자칩", 1700, "🥔", "chips", "food", { Satiety = 6, Fun = 2 }),
	},
	mart = {
		I("dosirak", "도시락 (제육)", 4900, "🍱", "dosirak", "food", { Satiety = 32 }, { bites = 5 }),
		I("kimbap", "참치 김밥", 3200, "🍙", "kimbap_roll", "food", { Satiety = 18 }),
		I("milk", "우유 1L", 2800, "🥛", "milk", "drink", { Satiety = 6 }),
		I("water", "생수 2L", 1200, "💧", "water", "drink", { Energy = 5 }),
		I("chocopie", "초코파이", 600, "🍫", "chocopie", "food", { Satiety = 5, Fun = 2 }),
	},
	cafe = {
		I("americano", "아이스 아메리카노", 3000, "🧊", "takeout_ice", "drink", { Energy = 12 }, { tint = "coffee" }),
		I("latte", "카페 라떼", 3800, "☕", "takeout_hot", "drink", { Energy = 9, Satiety = 3 }, { tint = "latte" }),
		I("ade", "자몽 에이드", 4500, "🍹", "takeout_ice", "drink", { Energy = 5, Fun = 3 }, { tint = "grapefruit" }),
		I("cookie", "초코칩 쿠키", 2500, "🍪", "cookie", "food", { Satiety = 6, Fun = 2 }),
	},
	bakery = {
		I("saltbread", "소금빵", 3200, "🥐", "bread", "food", { Satiety = 12 }, { tint = "salt" }),
		I("redbean", "단팥빵", 2200, "🍞", "bread", "food", { Satiety = 11 }, { tint = "redbean" }),
		I("cream", "생크림 카스텔라", 4500, "🍰", "cake", "food", { Satiety = 10, Fun = 3 }),
		I("milk", "흰 우유", 1500, "🥛", "milk", "drink", { Satiety = 4 }),
	},
	pharmacy = {
		I("fatigue", "피로회복제", 1000, "🧃", "medicine", "drink", { Energy = 14 }, { tint = "vitamin" }),
		I("digest", "소화제", 3000, "💊", "medicine", "goods", { Satiety = -6, Energy = 3 }),
		I("bandage", "밴드 (10매)", 2500, "🩹", "goods", "goods", { Hygiene = 5 }),
		I("mask", "마스크 (5매)", 3000, "😷", "goods", "goods", { Hygiene = 4 }),
	},
	beauty = {
		I("lipbalm", "립밤", 6000, "💄", "goods", "goods", { Fun = 4, Hygiene = 3 }),
		I("sunscreen", "선크림", 15000, "🧴", "goods", "goods", { Hygiene = 6 }),
		I("mask_sheet", "마스크팩 (5매)", 9000, "🧖", "goods", "goods", { Hygiene = 8, Fun = 2 }),
	},
	pub = {
		I("nabeer", "무알콜 맥주 (병)", 4000, "🍺", "beer_bottle", "drink", { Fun = 6 }, { tint = "zero" }),
		I("ade", "수제 레몬 에이드", 5500, "🍋", "glass", "drink", { Fun = 5, Energy = 3 }, { tint = "lemon" }),
		I("fries", "감자튀김", 6000, "🍟", "fries", "food", { Satiety = 14, Fun = 2 }),
		I("nachos", "나초 & 치즈", 7000, "🧀", "nachos", "food", { Satiety = 12, Fun = 3 }),
	},
	food = {
		I("kimbap", "김밥 한 줄", 3500, "🍙", "kimbap_roll", "food", { Satiety = 18 }),
		I("skewer", "어묵꼬치", 1500, "🍢", "skewer", "food", { Satiety = 7 }),
		I("drink", "탄산음료", 1500, "🥤", "can", "drink", { Energy = 4, Fun = 1 }, { tint = "cola" }),
	},
	game = {
		I("cupramen", "컵라면", 3500, "🍜", "cupramen", "food", { Satiety = 20 }, { bites = 4 }),
		I("jjapa", "짜파게티", 4000, "🍝", "cupramen", "food", { Satiety = 22 }, { bites = 4, tint = "jjapa" }),
		I("hotdog", "핫도그", 2500, "🌭", "sausage", "food", { Satiety = 10 }),
		I("soda", "탄산음료", 1500, "🥤", "can", "drink", { Energy = 4, Fun = 2 }, { tint = "cola" }),
	},
	karaoke = {
		I("soda", "탄산음료", 2000, "🥤", "can", "drink", { Energy = 4, Fun = 2 }, { tint = "cola" }),
		I("water", "생수", 1000, "💧", "water", "drink", { Energy = 4 }),
		I("snack", "과자 세트", 3000, "🍪", "chips", "food", { Satiety = 6, Fun = 3 }),
		I("icebar", "아이스크림", 1500, "🍦", "icebar", "food", { Satiety = 3, Fun = 3 }),
	},
	hotel = {
		I("water", "생수", 1000, "💧", "water", "drink", { Energy = 4 }),
		I("coffee", "드립 커피", 4000, "☕", "takeout_hot", "drink", { Energy = 10 }, { tint = "coffee" }),
		I("amenity", "어메니티 키트", 5000, "🧴", "goods", "goods", { Hygiene = 12 }),
	},
	rental = {
		I("water", "생수", 1000, "💧", "water", "drink", { Energy = 5 }),
		I("sunscreen", "선크림", 8000, "🧴", "goods", "goods", { Hygiene = 6 }),
		I("ade", "아이스 에이드", 3500, "🍹", "takeout_ice", "drink", { Energy = 6, Fun = 2 }, { tint = "lemon" }),
	},
}
LISTS.pc = LISTS.game
LISTS.shop = nil

Menus.LISTS = LISTS

function Menus.forKind(kind: string?): { any }?
	if type(kind) ~= "string" then
		return nil
	end
	return LISTS[kind]
end

function Menus.item(kind: string?, id: any): any?
	local list = Menus.forKind(kind)
	if not list or type(id) ~= "string" then
		return nil
	end
	for _, it in list do
		if it.id == id then
			return it
		end
	end
	return nil
end

return Menus
