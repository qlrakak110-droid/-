-- GwangalliBuildings/Menus: what every shop sells and what the food does. Pure data shared by the
-- server (prices are only ever trusted from here) and the client (menus, receipts).
-- effect: { Satiety, Energy, Hygiene, Fun } deltas for this system's needs; stats: deltas sent to
-- the life game's GwangalliGameplayAPI "addStats" when it exists (stamina / happiness / popularity).

local Menus = {}

-- 편의점 GW25 ---------------------------------------------------------------------------------
Menus.CVS = {
	{ id = "samgak", name = "참치마요 삼각김밥", price = 1300, cat = "food", color = { 240, 240, 236 }, effect = { Satiety = 14 } },
	{ id = "dosirak", name = "제육 도시락", price = 5500, cat = "food", heat = true, color = { 230, 120, 60 }, effect = { Satiety = 38, Energy = 4 }, stats = { stamina = 0.3 } },
	{ id = "cupramen", name = "컵라면 (큰사발)", price = 1600, cat = "food", noodle = true, color = { 220, 40, 40 }, effect = { Satiety = 26, Fun = 3 } },
	{ id = "kimbap", name = "참치 김밥", price = 3200, cat = "food", color = { 30, 40, 30 }, effect = { Satiety = 22 } },
	{ id = "banana_milk", name = "바나나맛 우유", price = 1700, cat = "drink", color = { 250, 214, 70 }, effect = { Satiety = 6, Fun = 4 }, stats = { happiness = 0.3 } },
	{ id = "cola", name = "콜라 500ml", price = 2300, cat = "drink", color = { 180, 20, 30 }, effect = { Energy = 6, Fun = 2 } },
	{ id = "coffee_can", name = "캔커피", price = 1500, cat = "drink", color = { 120, 80, 50 }, effect = { Energy = 12 } },
	{ id = "water", name = "생수 500ml", price = 900, cat = "drink", color = { 160, 210, 250 }, effect = { Energy = 2, Hygiene = 1 } },
	{ id = "icecream", name = "메로나", price = 1200, cat = "snack", color = { 150, 230, 120 }, effect = { Fun = 8 }, stats = { happiness = 0.2 } },
	{ id = "chips", name = "새우깡", price = 1500, cat = "snack", color = { 250, 140, 40 }, effect = { Satiety = 8, Fun = 4 } },
	{ id = "choco", name = "초코파이", price = 600, cat = "snack", color = { 110, 60, 40 }, effect = { Satiety = 6, Fun = 3 } },
	{ id = "toothbrush", name = "칫솔 세트", price = 2500, cat = "goods", color = { 80, 160, 220 }, effect = { Hygiene = 10 } },
}

-- 부산 돼지국밥 (후불) ------------------------------------------------------------------------
Menus.GUKBAP = {
	{ id = "dwaeji", name = "돼지국밥", price = 9000, desc = "뽀얀 사골 육수 + 수육 듬뿍", effect = { Satiety = 60, Energy = 10 }, stats = { stamina = 1 } },
	{ id = "sundae", name = "순대국밥", price = 9500, desc = "순대 + 내장 반반", effect = { Satiety = 60, Energy = 8 }, stats = { stamina = 1 } },
	{ id = "seokkeo", name = "섞어국밥", price = 10000, desc = "고기 + 순대 + 내장", effect = { Satiety = 64, Energy = 10 }, stats = { stamina = 1 } },
	{ id = "suyuk", name = "수육백반", price = 13000, desc = "수육 한 접시 + 국 + 밥", effect = { Satiety = 72, Energy = 12 }, stats = { stamina = 1.2, happiness = 0.5 } },
	{ id = "milmyeon", name = "부산 밀면 (여름)", price = 8500, desc = "새콤달콤 시원한 육수", effect = { Satiety = 50, Fun = 6 } },
}
Menus.GUKBAP_SIDES = { "부추무침", "깍두기", "김치", "새우젓", "다대기", "양파 · 고추" }

-- 광안 숯불갈비 (후불) ------------------------------------------------------------------------
Menus.BBQ = {
	{ id = "samgyup", name = "생삼겹살 (160g)", price = 16000, meat = true, raw = { 238, 170, 170 }, fat = { 250, 236, 230 }, effect = { Satiety = 9 }, stats = { happiness = 0.25 } },
	{ id = "moksal", name = "생목살 (160g)", price = 16000, meat = true, raw = { 220, 120, 120 }, fat = { 240, 200, 196 }, effect = { Satiety = 9 }, stats = { happiness = 0.25 } },
	{ id = "galbi", name = "양념 돼지갈비 (250g)", price = 17000, meat = true, raw = { 160, 74, 50 }, fat = { 190, 110, 80 }, effect = { Satiety = 10 }, stats = { happiness = 0.3 } },
	{ id = "hangjeong", name = "항정살 (150g)", price = 19000, meat = true, raw = { 244, 196, 190 }, fat = { 252, 240, 236 }, effect = { Satiety = 9 }, stats = { happiness = 0.3 } },
	{ id = "rice", name = "공기밥", price = 1000, effect = { Satiety = 15 } },
	{ id = "doenjang", name = "된장찌개", price = 3000, effect = { Satiety = 18, Energy = 4 } },
	{ id = "naengmyeon", name = "후식 냉면", price = 5000, effect = { Satiety = 22, Fun = 4 } },
	{ id = "cider", name = "사이다", price = 2000, effect = { Energy = 4, Fun = 2 } },
}

-- 바다 카페 (선불, 진동벨) --------------------------------------------------------------------
Menus.CAFE = {
	{ id = "americano", name = "아이스 아메리카노", price = 4500, cup = "ice", color = { 60, 36, 20 }, effect = { Energy = 22 }, stats = { happiness = 0.3 } },
	{ id = "hot_americano", name = "아메리카노 (HOT)", price = 4500, cup = "hot", color = { 60, 36, 20 }, effect = { Energy = 22 } },
	{ id = "latte", name = "카페 라떼", price = 5000, cup = "ice", color = { 200, 160, 120 }, effect = { Energy = 16, Satiety = 4 } },
	{ id = "vanilla", name = "바닐라 라떼", price = 5500, cup = "ice", color = { 230, 200, 160 }, effect = { Energy = 14, Fun = 4 } },
	{ id = "greentea", name = "녹차 라떼", price = 5500, cup = "ice", color = { 140, 190, 110 }, effect = { Energy = 8, Fun = 4 } },
	{ id = "lemonade", name = "제주 레몬에이드", price = 6000, cup = "ice", color = { 250, 240, 120 }, effect = { Fun = 8 }, stats = { happiness = 0.4 } },
	{ id = "cake", name = "딸기 생크림 케이크", price = 6500, cup = "plate", color = { 250, 236, 236 }, effect = { Satiety = 14, Fun = 8 }, stats = { happiness = 0.5 } },
}

-- PC방 -----------------------------------------------------------------------------------------
Menus.PC_TICKETS = {
	{ id = "h1", name = "1시간 이용권", price = 1500, minutes = 1 },
	{ id = "h3", name = "3시간 이용권 (+30분)", price = 4000, minutes = 3.5 },
}
Menus.PC_FOOD = {
	{ id = "jjapa", name = "짜파게티", price = 4500, effect = { Satiety = 30, Fun = 4 } },
	{ id = "ramen", name = "라면 + 계란", price = 4000, effect = { Satiety = 28 } },
	{ id = "nugget", name = "치킨너겟", price = 5000, effect = { Satiety = 20, Fun = 4 } },
	{ id = "ade", name = "블루레몬 에이드", price = 3000, effect = { Energy = 8, Fun = 3 } },
}
Menus.PC_GAMES = {
	{ id = "aim", name = "에임 트레이너", desc = "30초 동안 과녁을 맞혀요" },
	{ id = "rhythm", name = "리듬 탭", desc = "떨어지는 노트에 맞춰 탭!" },
}

-- 노래방 ---------------------------------------------------------------------------------------
Menus.KARAOKE_ROOMS = {
	{ id = "small", name = "2~3인 룸 (30분)", price = 8000, seconds = 600 },
	{ id = "party", name = "파티룸 (30분)", price = 15000, seconds = 600 },
}
-- original songs (no copyrighted lyrics): title, artist, bpm, lines
Menus.SONGS = {
	{
		no = 10241,
		title = "광안리 밤바다",
		artist = "오션 브리즈",
		bpm = 92,
		lines = { "다리 위로 불빛이 번지면", "파도는 내 이름을 불러", "광안리 밤바다 너와 걷던 길", "모래 위에 남긴 약속", "다시 여름이 오면 만나자", "광안대교 불빛 아래서" },
	},
	{
		no = 10377,
		title = "돼지국밥 블루스",
		artist = "서면 밴드",
		bpm = 78,
		lines = { "새벽 세 시 국밥집 앞에", "김 서린 유리창 너머로", "부추 한 젓가락 새우젓 조금", "오늘도 수고했다 나에게", "뜨끈한 국물 한 숟갈에", "다 괜찮아질 거야" },
	},
	{
		no = 10512,
		title = "갈매기 댄스",
		artist = "민락 크루",
		bpm = 128,
		lines = { "끼룩 끼룩 날개를 펴고", "해변 따라 달려가자", "손을 들어 하늘 높이", "갈매기처럼 춤을 춰", "모두 함께 점프 점프", "광안리가 들썩들썩" },
	},
	{
		no = 10688,
		title = "엘리베이터",
		artist = "윤하늘",
		bpm = 104,
		lines = { "12층 버튼을 누르고", "숫자가 올라갈수록", "심장이 빨라져", "문이 열리면 네가 있을까", "띵 하고 울리는 순간", "우리 이야기가 시작돼" },
	},
	{
		no = 10801,
		title = "원룸",
		artist = "김바다",
		bpm = 86,
		lines = { "작은 창문 하나 있는 방", "컵라면 하나에 웃던 밤", "언젠가는 바다가 보이는", "넓은 집에 살 거라고", "오늘도 열심히 살아낸", "나를 안아주고 싶어" },
	},
}

-- 당구장 ---------------------------------------------------------------------------------------
Menus.BILLIARDS = {
	{ id = "t10", name = "4구 테이블 (10분)", price = 3000, seconds = 600 },
}

-- 호텔 -----------------------------------------------------------------------------------------
Menus.HOTEL_ROOMS = {
	{ id = "standard", name = "스탠다드 더블", price = 39000, desc = "시티뷰 · 퀸 침대 · 샤워부스" },
	{ id = "deluxe", name = "디럭스 오션뷰", price = 79000, desc = "오션뷰 · 킹 침대 · 욕조" },
	{ id = "suite", name = "로열 스위트", price = 190000, desc = "거실 + 침실 · 파노라마 오션뷰" },
}
Menus.ROOM_SERVICE = {
	{ id = "club_sandwich", name = "클럽 샌드위치", price = 18000, effect = { Satiety = 40, Fun = 4 } },
	{ id = "fruit", name = "제철 과일 플래터", price = 22000, effect = { Satiety = 20, Fun = 6 }, stats = { happiness = 0.5 } },
	{ id = "minibar", name = "미니바 음료", price = 6000, effect = { Energy = 8 } },
}

-- 냉장고 (homes): free snacks from your own fridge
Menus.FRIDGE = {
	{ id = "milk", name = "우유 한 잔", effect = { Satiety = 6, Energy = 2 } },
	{ id = "kimchi_rice", name = "김치볶음밥 (데우기)", heat = true, effect = { Satiety = 30 } },
	{ id = "fruit", name = "사과", effect = { Satiety = 8, Fun = 2 } },
	{ id = "cider", name = "사이다", effect = { Energy = 4, Fun = 3 } },
	{ id = "egg", name = "삶은 계란", effect = { Satiety = 10 } },
}

-- every orderable item by shop kind -> list
Menus.BY_KIND = {
	cvs = Menus.CVS,
	gukbap = Menus.GUKBAP,
	bbq = Menus.BBQ,
	cafe = Menus.CAFE,
	pcbang = Menus.PC_FOOD,
	karaoke = Menus.KARAOKE_ROOMS,
	billiards = Menus.BILLIARDS,
	hotel = Menus.HOTEL_ROOMS,
}

function Menus.find(list: { any }, id: any): any?
	for _, e in list do
		if e.id == id then
			return e
		end
	end
	return nil
end

return Menus
