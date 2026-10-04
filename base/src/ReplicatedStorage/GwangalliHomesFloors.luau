-- GwangalliHomesFloors (F): 내집마련 v2 — real Korean floor plans per layout, the floor tables of
-- every residential building (which layout sits on which floor, view value, price by floor) and the
-- runtime helpers for per-floor window views, hallway door numbers and the elevator ride effect.
-- OWNER: floors key (docs/homes_contract.md). build/venues/homes*.luau builds one template per
-- layout (ServerStorage.GwangalliHomes."HomeUnit_<layoutId>") and the building lobbies / halls
-- (Workspace.Gwangalli.homes.Buildings) from this data; the plan-driven templates read
-- F.layouts[id].plan, so the 2D plan the phone shows IS the 3D unit.
--
-- LAYOUT IDS: the five original templates keep their tier key as layout id (goshiwon, oneroom,
-- officetel, apartment, penthouse) — they ARE each tier's default layout, so "HomeUnit_<tierKey>"
-- needs no alias copy and old saves keep their furniture slots. New layouts have their own ids.
-- PLAN: rectangles in metres, origin = top-left of the plan, x to the right, y "down" from the
-- window / view facade toward the entrance; `level = 2` marks an upper level (복층 / 다락);
-- `room` is the template Room id (themes; several rects may share one), `label` the Korean name.
-- `windows` = facade segments { x0, y0, x1, y1 }, `entrance` = { x, y } of the front door.
--
-- No instances are created and no Roblox services are touched at require time (Lune build + tests).
-- Runtime helpers (Roblox only, call with instances): F.findTemplate, F.prepareInstance (server,
-- after the clone is pivoted), F.applyFloorView, F.prepareHall (client), F.rideEffect (client).

local F = {}
F.VERSION = 2
F.FOLDER = "GwangalliHomes"
F.M_PER_STUD = 0.3

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function r2(v: number): number
	return math.floor(v * 100 + 0.5) / 100
end

-------------------------------------------------------------------------------------------------
-- Extra room ids used by the new layouts (the decor UI merges these with HS.ROOM_NAMES)
-------------------------------------------------------------------------------------------------
F.ROOM_NAMES = {
	kids = { name = "작은방 2", icon = "🧸" },
	guest = { name = "알파룸", icon = "🛋️" },
	utility = { name = "다용도실", icon = "🧺" },
	wine = { name = "와인셀러", icon = "🍷" },
}
F.ROOM_ORDER_EXTRA = { "kids", "guest", "utility" }

-------------------------------------------------------------------------------------------------
-- Layouts
-------------------------------------------------------------------------------------------------
local function rect(room: string, label: string, x: number, y: number, w: number, h: number, extra: any?): any
	local t = { room = room, label = label, x = x, y = y, w = w, h = h }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

F.LAYOUT_ORDER = {
	"goshiwon", "goshiwon_inner",
	"oneroom", "oneroom_split", "oneroom_loft",
	"officetel_studio", "officetel_15", "officetel", "officetel_terrace",
	"apt59a", "apartment", "apt84b", "apt114",
	"penthouse",
}

F.layouts = {
	-- 고시원 ------------------------------------------------------------------------------------------
	goshiwon = {
		label = "창문형 1인실 · 개인 샤워실", short = "창문형", area = 7.8, rooms = 1, baths = 1,
		balcony = false, duplex = false, tierKey = "goshiwon", listing = "goshiwon", view = "alley",
		kitchen = "책상 겸 간이주방", ceiling = 2.34,
		features = { "바깥 창문 (골목뷰)", "개인 샤워실 + 변기", "붙박이 책상 · 미니냉장고", "벽걸이 에어컨" },
		plan = {
			rect("main", "방", 0, 0, 2.16, 2.67),
			rect("main", "현관", 0, 2.67, 1.29, 0.93),
			rect("bath", "샤워실", 1.29, 2.67, 0.87, 0.93),
		},
		windows = { { 1.23, 0, 1.92, 0 } }, entrance = { x = 0.5, y = 3.6 },
	},
	goshiwon_inner = {
		label = "내창형 미니룸 (창문 없는 방)", short = "내창형", area = 6.3, rooms = 1, baths = 1,
		balcony = false, duplex = false, tierKey = "goshiwon", listing = "goshiwon", view = "none",
		kitchen = "책상 겸 간이주방", ceiling = 2.34,
		features = { "복도 쪽 내창 (환기창)", "개인 샤워부스", "가성비 최고 · 조용함", "천장 환풍기" },
		plan = {
			rect("main", "방", 0, 0, 2.1, 2.1),
			rect("main", "현관", 0, 2.1, 1.2, 0.9),
			rect("bath", "샤워실", 1.2, 2.1, 0.9, 0.9),
		},
		windows = {}, innerWindow = true, entrance = { x = 0.6, y = 3.0 },
	},
	-- 원룸 -------------------------------------------------------------------------------------------
	oneroom = {
		label = "오픈형 원룸 26㎡", short = "오픈형", area = 26, rooms = 1, baths = 1,
		balcony = false, duplex = false, tierKey = "oneroom", listing = "oneroom", view = "alley",
		kitchen = "일자형 2구 인덕션", ceiling = 2.37,
		features = { "풀옵션 (세탁기·냉장고·에어컨)", "이중창 + 방범창", "붙박이장", "현관 센서등" },
		plan = {
			rect("main", "방", 0, 0, 4.62, 3.6),
			rect("main", "방", 4.62, 0, 1.38, 2.88),
			rect("kitchen", "주방", 0, 3.6, 3.24, 1.2),
			rect("entry", "현관", 3.24, 3.6, 1.38, 1.2),
			rect("bath", "욕실", 4.62, 2.88, 1.38, 1.92),
		},
		windows = { { 1.62, 0, 4.38, 0 } }, entrance = { x = 3.75, y = 4.8 },
	},
	oneroom_split = {
		label = "분리형 원룸 30㎡ (주방 분리)", short = "분리형", area = 30, rooms = 1, baths = 1,
		balcony = false, duplex = false, tierKey = "oneroom", listing = "oneroom", view = "alley",
		kitchen = "일자형 + 미닫이 중문 분리", ceiling = 2.37,
		features = { "주방·현관과 방 사이 미닫이문", "요리해도 냄새가 방에 덜 배요", "통창 + 커튼", "드럼세탁기 빌트인" },
		plan = {
			rect("main", "방", 0, 0, 6.0, 3.3),
			rect("kitchen", "주방", 0, 3.3, 3.0, 2.1),
			rect("entry", "현관", 3.0, 3.3, 1.5, 2.1),
			rect("bath", "욕실", 4.5, 3.3, 1.5, 2.1),
		},
		windows = { { 0.9, 0, 5.1, 0 } }, entrance = { x = 3.75, y = 5.4 },
	},
	oneroom_loft = {
		label = "복층 원룸 27㎡ + 다락", short = "복층", area = 27, rooms = 1, baths = 1,
		balcony = false, duplex = true, tierKey = "oneroom", listing = "oneroom", view = "alley",
		kitchen = "일자형 (복층 아래)", ceiling = 4.6,
		features = { "층고 4.6m 거실 + 다락 침실", "원목 계단", "높은 창으로 하늘이 보여요", "꼭대기층 전용" },
		plan = {
			rect("main", "거실 (층고 4.6m)", 0, 0, 5.4, 3.3),
			rect("kitchen", "주방", 0, 3.3, 3.3, 2.7),
			rect("bath", "욕실", 3.3, 3.3, 2.1, 1.5),
			rect("entry", "현관", 3.3, 4.8, 2.1, 1.2),
			rect("loft", "다락 침실", 0, 3.0, 5.4, 3.0, { level = 2 }),
		},
		windows = { { 0.6, 0, 4.8, 0 } }, entrance = { x = 4.35, y = 6.0 },
	},
	-- 오피스텔 -------------------------------------------------------------------------------------------
	officetel_studio = {
		label = "스튜디오형 29㎡", short = "스튜디오", area = 29, rooms = 1, baths = 1,
		balcony = false, duplex = false, tierKey = "officetel", listing = "officetel", view = "sea",
		kitchen = "일자형 빌트인", ceiling = 2.4,
		features = { "전면 통창 (바다 방향)", "빌트인 냉장고·세탁기", "시스템 에어컨", "월패드 · 무인택배" },
		plan = {
			rect("main", "방·거실", 0, 0, 7.5, 2.7),
			rect("kitchen", "주방", 0, 2.7, 3.6, 1.5),
			rect("bath", "욕실", 3.6, 2.7, 1.8, 1.5),
			rect("entry", "현관", 5.4, 2.7, 2.1, 1.5),
		},
		windows = { { 0.2, 0, 7.3, 0 } }, entrance = { x = 6.45, y = 4.2 },
	},
	officetel_15 = {
		label = "1.5룸 42㎡ (침실 분리)", short = "1.5룸", area = 42, rooms = 2, baths = 1,
		balcony = false, duplex = false, tierKey = "officetel", listing = "officetel", view = "sea",
		kitchen = "ㄱ자 + 홈바", ceiling = 2.4,
		features = { "유리 슬라이딩 도어로 침실 분리", "거실 + 침실 각각 바다 창", "ㄱ자 주방", "시스템 에어컨 2대" },
		plan = {
			rect("bedroom", "침실", 0, 0, 3.0, 3.3),
			rect("living", "거실", 3.0, 0, 5.4, 3.3),
			rect("kitchen", "주방", 0, 3.3, 4.5, 2.1),
			rect("entry", "현관", 4.5, 3.3, 1.8, 2.1),
			rect("bath", "욕실", 6.3, 3.3, 2.1, 2.1),
		},
		windows = { { 0.3, 0, 2.7, 0 }, { 3.3, 0, 8.1, 0 } }, entrance = { x = 5.4, y = 5.4 },
	},
	officetel = {
		label = "복층형 46㎡ (층고 4.8m)", short = "복층", area = 46, rooms = 1, baths = 1,
		balcony = false, duplex = true, tierKey = "officetel", listing = "officetel", view = "sea",
		kitchen = "일자형 (복층 아래)", ceiling = 4.8,
		features = { "층고 4.8m 커튼월 통창", "복층 침실 + 유리 난간", "아트월 + 65\" TV", "광안대교가 보여요" },
		plan = {
			rect("living", "거실 (층고 4.8m)", 0, 0, 9.0, 3.0),
			rect("kitchen", "주방", 0, 3.0, 5.52, 2.1),
			rect("bath", "욕실", 5.52, 3.0, 1.68, 2.1),
			rect("entry", "현관", 7.2, 3.0, 1.8, 2.1),
			rect("loft", "복층 침실", 0, 3.0, 9.0, 2.1, { level = 2 }),
		},
		windows = { { 0.18, 0, 8.82, 0 } }, entrance = { x = 8.04, y = 5.1 },
	},
	officetel_terrace = {
		label = "복층 테라스 46㎡ + 테라스 27㎡", short = "테라스", area = 46, rooms = 1, baths = 1,
		balcony = true, duplex = true, tierKey = "officetel", listing = "officetel", view = "sea",
		kitchen = "일자형 (복층 아래)", ceiling = 4.8,
		features = { "바다 앞 전용 테라스 (선베드·테이블)", "층고 4.8m 복층", "최상층 3개 층 한정", "광안대교 야경 정면" },
		plan = {
			rect("terrace", "테라스", 0, 0, 9.0, 3.0),
			rect("living", "거실 (층고 4.8m)", 0, 3.0, 9.0, 3.0),
			rect("kitchen", "주방", 0, 6.0, 5.52, 2.1),
			rect("bath", "욕실", 5.52, 6.0, 1.68, 2.1),
			rect("entry", "현관", 7.2, 6.0, 1.8, 2.1),
			rect("loft", "복층 침실", 0, 6.0, 9.0, 2.1, { level = 2 }),
		},
		windows = { { 0.18, 3.0, 8.82, 3.0 } }, entrance = { x = 8.04, y = 8.1 },
	},
	-- 아파트 (광안자이) --------------------------------------------------------------------------------------
	apt59a = {
		label = "59㎡ A타입 · 판상형 3베이", short = "59A", area = 59, rooms = 3, baths = 2,
		balcony = true, duplex = false, tierKey = "apartment", listing = "xi_apt", view = "sea",
		orient = "판상형", kitchen = "ㄱ자", ceiling = 2.34,
		features = { "방 3 · 욕실 2 (안방 욕실)", "거실 확장형 + 안방 발코니", "ㄱ자 주방 + 다용도실", "현관 중문 · 월패드" },
		plan = {
			rect("veranda", "발코니", 0, 0, 3.3, 1.2),
			rect("bedroom", "안방", 0, 1.2, 3.3, 3.9),
			rect("master_bath", "안방 욕실", 0, 5.1, 1.8, 2.1),
			rect("dress", "드레스룸", 1.8, 5.1, 1.5, 2.1),
			rect("living", "거실", 3.3, 0, 3.9, 4.8),
			rect("kitchen", "주방·식당", 3.3, 4.8, 3.9, 2.4),
			rect("utility", "다용도실", 3.3, 7.2, 1.8, 1.2),
			rect("entry", "현관", 5.1, 7.2, 2.1, 1.2),
			rect("study", "작은방", 7.2, 0, 3.0, 3.3),
			rect("living", "복도", 7.2, 3.3, 1.2, 2.1),
			rect("bath", "욕실", 8.4, 3.3, 1.8, 2.1),
			rect("kids", "작은방 2", 7.2, 5.4, 3.0, 3.0),
		},
		windows = { { 0.2, 0, 3.1, 0 }, { 3.5, 0, 7.0, 0 }, { 7.6, 0, 9.8, 0 }, { 7.8, 8.4, 9.6, 8.4 }, { 3.5, 8.4, 4.9, 8.4 } },
		entrance = { x = 6.15, y = 8.4 },
	},
	apartment = {
		label = "84㎡ A타입 · 판상형", short = "84A", area = 84, rooms = 2, baths = 2,
		balcony = true, duplex = false, tierKey = "apartment", listing = "xi_apt", view = "sea",
		orient = "판상형", kitchen = "ㄱ자 + 아일랜드", ceiling = 2.34,
		features = { "우물천장 거실 + 아트월", "아일랜드 주방 + 양문형·김치냉장고", "안방 드레스룸 + 욕실", "베란다 (세탁·건조)" },
		plan = {
			rect("veranda", "베란다", 0, 0, 3.9, 1.2),
			rect("bedroom", "안방", 0, 1.2, 3.9, 5.4),
			rect("living", "거실", 3.9, 1.2, 4.8, 4.2),
			rect("study", "작은방", 8.7, 1.2, 3.3, 3.6),
			rect("kitchen", "복도", 8.7, 4.8, 1.2, 0.6),
			rect("kitchen", "주방·식당", 3.9, 5.4, 6.0, 4.8),
			rect("bath", "욕실", 9.9, 4.8, 2.1, 2.4),
			rect("entry", "현관", 9.9, 7.2, 2.1, 3.0),
			rect("master_bath", "안방 욕실", 0, 6.6, 2.1, 3.6),
			rect("dress", "드레스룸", 2.1, 6.6, 1.8, 3.6),
		},
		windows = { { 0.24, 0, 3.66, 0 }, { 4.08, 1.2, 8.52, 1.2 }, { 9.3, 1.2, 11.4, 1.2 } },
		entrance = { x = 11.0, y = 10.2 },
	},
	apt84b = {
		label = "84㎡ B타입 · 타워형 코너", short = "84B", area = 84, rooms = 3, baths = 2,
		balcony = false, duplex = false, tierKey = "apartment", listing = "xi_apt", view = "sea",
		orient = "타워형", kitchen = "ㄷ자", ceiling = 2.34,
		features = { "2면 개방 코너 거실 (파노라마 뷰)", "ㄷ자 주방 + 팬트리", "안방 드레스룸 + 욕실", "방 3개 모두 창" },
		plan = {
			rect("bedroom", "안방", 0, 0, 3.6, 4.2),
			rect("master_bath", "안방 욕실", 0, 4.2, 1.8, 2.1),
			rect("dress", "드레스룸", 1.8, 4.2, 1.8, 2.1),
			rect("kids", "작은방 2", 0, 6.3, 3.6, 2.7),
			rect("study", "작은방", 3.6, 0, 3.0, 3.3),
			rect("living", "복도", 3.6, 3.3, 3.0, 1.2),
			rect("bath", "욕실", 3.6, 4.5, 1.8, 2.1),
			rect("living", "복도", 5.4, 4.5, 1.2, 2.1),
			rect("entry", "현관", 3.6, 6.6, 3.0, 2.4),
			rect("living", "거실", 6.6, 0, 4.8, 4.8),
			rect("kitchen", "주방·식당", 6.6, 4.8, 4.8, 3.3),
			rect("kitchen", "팬트리", 6.6, 8.1, 1.8, 0.9),
			rect("utility", "다용도실", 8.4, 8.1, 3.0, 0.9),
		},
		windows = { { 6.9, 0, 11.1, 0 }, { 11.4, 0.3, 11.4, 4.5 }, { 11.4, 5.4, 11.4, 7.5 }, { 0.3, 0, 3.3, 0 }, { 3.9, 0, 6.3, 0 }, { 0, 6.8, 0, 8.6 } },
		entrance = { x = 5.1, y = 9.0 },
	},
	apt114 = {
		label = "114㎡ · 4베이 판상형", short = "114", area = 114, rooms = 4, baths = 2,
		balcony = true, duplex = false, tierKey = "apartment", listing = "xi_apt", view = "sea",
		orient = "판상형", kitchen = "ㄱ자 + 대형 아일랜드", ceiling = 2.4,
		features = { "4베이 (방 3 + 거실 전면 배치)", "대형 아일랜드 + 6인 식탁", "현관 옆 알파룸", "드레스룸 + 팬트리 + 다용도실" },
		plan = {
			rect("veranda", "발코니", 0, 0, 3.9, 1.2),
			rect("bedroom", "안방", 0, 1.2, 3.9, 4.2),
			rect("dress", "드레스룸", 0, 5.4, 2.1, 2.4),
			rect("master_bath", "안방 욕실", 2.1, 5.4, 1.8, 2.4),
			rect("living", "거실", 3.9, 0, 4.8, 5.4),
			rect("kitchen", "주방·식당", 3.9, 5.4, 4.8, 3.3),
			rect("utility", "다용도실", 3.9, 8.7, 2.4, 1.5),
			rect("kitchen", "팬트리", 6.3, 8.7, 2.4, 1.5),
			rect("study", "작은방", 8.7, 0, 3.0, 3.6),
			rect("kids", "작은방 2", 11.7, 0, 3.0, 3.6),
			rect("living", "복도", 8.7, 3.6, 6.0, 1.2),
			rect("living", "복도", 8.7, 4.8, 2.4, 2.4),
			rect("bath", "욕실", 11.1, 4.8, 3.6, 2.1),
			rect("entry", "현관", 8.7, 7.2, 2.4, 3.0),
			rect("guest", "알파룸", 11.1, 6.9, 3.6, 3.3),
		},
		windows = { { 0.2, 0, 3.7, 0 }, { 4.1, 0, 8.5, 0 }, { 9.0, 0, 11.4, 0 }, { 12.0, 0, 14.4, 0 }, { 11.4, 10.2, 14.4, 10.2 }, { 4.1, 10.2, 6.1, 10.2 } },
		entrance = { x = 9.9, y = 10.2 },
	},
	-- 펜트하우스 ---------------------------------------------------------------------------------------------
	penthouse = {
		label = "펜트하우스 198㎡ · 복층 오션뷰", short = "펜트하우스", area = 198, rooms = 2, baths = 3,
		balcony = true, duplex = true, tierKey = "penthouse", listing = "aqua_ph", view = "sea",
		kitchen = "아일랜드 + 바 카운터", ceiling = 5.4,
		features = { "층고 5.4m 통유리 거실", "테라스 자쿠지 + 선베드", "복층 마스터 스위트 + 욕조", "와인셀러 · 그랜드 피아노" },
		plan = {
			rect("terrace", "테라스 (자쿠지)", 0, 0, 18.0, 4.2),
			rect("dining", "다이닝·바", 0, 4.2, 5.4, 4.2),
			rect("kitchen", "주방", 0, 8.4, 5.4, 3.6),
			rect("living", "거실 (층고 5.4m)", 5.4, 4.2, 7.2, 6.45),
			rect("entry", "현관 홀", 5.4, 10.65, 7.2, 1.35),
			rect("study", "서재", 12.6, 4.2, 5.4, 5.4),
			rect("wine", "와인셀러·파우더", 12.6, 9.6, 5.4, 2.4),
			rect("bedroom", "마스터 스위트", 12.6, 4.2, 5.4, 5.1, { level = 2 }),
			rect("dress", "드레스룸", 12.6, 9.3, 2.7, 2.7, { level = 2 }),
			rect("master_bath", "마스터 욕실", 15.3, 9.3, 2.7, 2.7, { level = 2 }),
		},
		windows = { { 0, 4.2, 18.0, 4.2 } }, entrance = { x = 9.0, y = 12.0 },
	},
}

-- derived fields
for id, l in F.layouts do
	l.id = id
	l.template = "HomeUnit_" .. id
	l.pyeong = math.floor(l.area / 3.3058 + 0.5)
	local w, h = 0, 0
	for _, r in l.plan do
		w = math.max(w, r.x + r.w)
		h = math.max(h, r.y + r.h)
	end
	l.planW, l.planH = r2(w), r2(h)
	l.default = (id == l.tierKey)
end
-- 공급 평형 names for the apartments (what Korean listings call them)
F.layouts.apt59a.typeName = "25평형"
F.layouts.apartment.typeName = "34평형"
F.layouts.apt84b.typeName = "34평형"
F.layouts.apt114.typeName = "45평형"
F.layouts.penthouse.typeName = "60평형"

-- Default layout of each tier (its template is "HomeUnit_<tierKey>").
F.TIER_DEFAULT = { goshiwon = "goshiwon", oneroom = "oneroom", officetel = "officetel", apartment = "apartment", penthouse = "penthouse" }

function F.layoutOf(id: any): any?
	return if type(id) == "string" then F.layouts[id] else nil
end

function F.layoutsOfTier(tierKey: string): { string }
	local out = {}
	for _, id in F.LAYOUT_ORDER do
		local l = F.layouts[id]
		if l and l.tierKey == tierKey then
			table.insert(out, id)
		end
	end
	return out
end

function F.templateName(layoutId: string): string
	return "HomeUnit_" .. tostring(layoutId)
end

-------------------------------------------------------------------------------------------------
-- Buildings (generated floor tables)
-------------------------------------------------------------------------------------------------
-- Every G.LISTINGS id. site = the entrance Destination name (build/venues/homes_entry.luau SITES).
-- floorH = metres per storey (window altitude for the per-floor view).
F.BUILDING_ORDER = { "goshiwon", "oneroom", "officetel", "xi_apt", "aqua_ph" }

local AREA_FACTOR = {
	goshiwon = 1.0, goshiwon_inner = 0.82,
	oneroom = 1.0, oneroom_split = 1.06, oneroom_loft = 1.2,
	officetel_studio = 0.72, officetel_15 = 0.9, officetel = 1.0, officetel_terrace = 1.32,
	apt59a = 0.72, apartment = 1.0, apt84b = 1.04, apt114 = 1.38,
	penthouse = 1.0,
}
F.AREA_FACTOR = AREA_FACTOR

local function unitName(floor: number, index: number): string
	return string.format("%d%02d", floor, index)
end
F.unitNameOf = unitName

-- spec.units(floor) -> { { layout, side, view } } for that floor; spec.floorFactor(floor)
local function makeBuilding(listingId: string, spec: any): any
	local b = {
		listingId = listingId,
		name = spec.name, dong = spec.dong, site = spec.site, kind = spec.kind,
		floorH = spec.floorH, elevator = spec.elevator, lobby = spec.lobby,
		hallDoors = 0, floors = {},
	}
	local rawDefault = nil
	for _, floor in spec.floorList do
		local list = spec.units(floor)
		local units = {}
		for i, u in list do
			local view = math.clamp(u.view, 0, 1)
			local raw = (AREA_FACTOR[u.layout] or 1) * spec.floorFactor(floor) * (0.9 + 0.2 * view)
			local row = { unit = unitName(floor, i), floor = floor, index = i, layout = u.layout, view = r2(view), side = u.side, raw = raw }
			row.label = row.unit .. "호"
			table.insert(units, row)
			if floor == spec.default.floor and row.unit == spec.default.unit then
				rawDefault = raw
			end
		end
		b.hallDoors = math.max(b.hallDoors, #units)
		table.insert(b.floors, { floor = floor, units = units })
	end
	local norm = rawDefault or 1
	for _, f in b.floors do
		for _, row in f.units do
			row.priceMult = r2(row.raw / norm)
			row.raw = nil
		end
	end
	b.default = { floor = spec.default.floor, unit = spec.default.unit }
	b.minFloor = b.floors[1] and b.floors[1].floor or 1
	b.maxFloor = b.floors[#b.floors] and b.floors[#b.floors].floor or 1
	return b
end

local function range(a: number, b: number): { number }
	local t = {}
	for i = a, b do
		table.insert(t, i)
	end
	return t
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

F.buildings = {}

-- 광안 고시텔 (황령하우스 3-4층): 10 rooms per floor, 01-05 창문형 on the street side, 06-10 내창형
F.buildings.goshiwon = makeBuilding("goshiwon", {
	name = "광안 고시텔", dong = "황령하우스", site = "광안 고시텔 (황령하우스 3F)", kind = "goshiwon",
	floorH = 2.7, elevator = false, lobby = "goshiwon",
	floorList = { 3, 4 },
	default = { floor = 3, unit = "301" },
	floorFactor = function(f: number): number
		return if f >= 4 then 1.02 else 1.0
	end,
	units = function(f: number)
		local t = {}
		for i = 1, 10 do
			if i <= 5 then
				table.insert(t, { layout = "goshiwon", side = "street", view = 0.16 + (f - 3) * 0.04 + (i == 1 and 0.04 or 0) })
			else
				table.insert(t, { layout = "goshiwon_inner", side = "inner", view = 0.0 })
			end
		end
		return t
	end,
})

-- 미성맨션 (필로티 빌라, 2-5층): 4 units on 2-4F, the top floor has two 복층 원룸 (attic lofts)
F.buildings.oneroom = makeBuilding("oneroom", {
	name = "미성맨션", dong = "미성맨션", site = "미성맨션 원룸 (광안동)", kind = "villa",
	floorH = 2.8, elevator = true, lobby = "villa",
	floorList = range(2, 5),
	default = { floor = 3, unit = "301" },
	floorFactor = function(f: number): number
		return 0.97 + (f - 2) * 0.02
	end,
	units = function(f: number)
		local front = 0.22 + (f - 2) * 0.07
		local back = 0.1 + (f - 2) * 0.05
		if f == 5 then
			return {
				{ layout = "oneroom_loft", side = "street", view = front + 0.08 },
				{ layout = "oneroom_loft", side = "street", view = front + 0.05 },
				{ layout = "oneroom_split", side = "back", view = back },
			}
		end
		return {
			{ layout = "oneroom", side = "street", view = front },
			{ layout = "oneroom_split", side = "street", view = front - 0.02 },
			{ layout = "oneroom_split", side = "back", view = back },
			{ layout = "oneroom", side = "back", view = back - 0.02 },
		}
	end,
})

-- 테라스타오션 오피스텔 (3-20층, 복도형 6호): sea side 01-04, city side 05-06
F.buildings.officetel = makeBuilding("officetel", {
	name = "테라스타오션", dong = "오피스텔동", site = "테라스타오션", kind = "officetel",
	floorH = 3.2, elevator = true, lobby = "officetel",
	floorList = range(3, 20),
	default = { floor = 12, unit = "1201" },
	floorFactor = function(f: number): number
		return lerp(0.92, 1.06, (f - 3) / 17)
	end,
	units = function(f: number)
		local t = (f - 3) / 17
		local sea = lerp(0.42, 0.95, t)
		local city = lerp(0.18, 0.5, t)
		if f >= 18 then
			return {
				{ layout = "officetel_terrace", side = "sea", view = sea + 0.05 },
				{ layout = "officetel_terrace", side = "sea", view = sea + 0.03 },
				{ layout = "officetel", side = "sea", view = sea },
				{ layout = "officetel", side = "sea", view = sea - 0.03 },
				{ layout = "officetel_15", side = "city", view = city },
				{ layout = "officetel_studio", side = "city", view = city - 0.02 },
			}
		elseif f >= 12 then
			return {
				{ layout = "officetel", side = "sea", view = sea + 0.02 },
				{ layout = "officetel", side = "sea", view = sea },
				{ layout = "officetel_15", side = "sea", view = sea - 0.02 },
				{ layout = "officetel_studio", side = "sea", view = sea - 0.04 },
				{ layout = "officetel_15", side = "city", view = city },
				{ layout = "officetel_studio", side = "city", view = city - 0.02 },
			}
		end
		return {
			{ layout = "officetel_15", side = "sea", view = sea + 0.02 },
			{ layout = "officetel_15", side = "sea", view = sea },
			{ layout = "officetel_studio", side = "sea", view = sea - 0.02 },
			{ layout = "officetel_studio", side = "sea", view = sea - 0.04 },
			{ layout = "officetel_studio", side = "city", view = city },
			{ layout = "officetel_studio", side = "city", view = city - 0.02 },
		}
	end,
})

-- 광안자이 101동 (2-30층, 4호 조합 타워형 코어): the layout mix changes by floor band
--   2-9F  59A / 84A / 84A / 59A      10-19F 84A / 84A / 84B / 84B (corner)
--   20-29F 84B / 114 / 114 / 84B     30F    114 (최상층 복층형 펜트 대신 2세대)
F.buildings.xi_apt = makeBuilding("xi_apt", {
	name = "광안자이", dong = "101동", site = "광안자이 (정문)", kind = "apartment",
	floorH = 2.9, elevator = true, lobby = "apartment",
	floorList = range(2, 30),
	default = { floor = 15, unit = "1502" },
	floorFactor = function(f: number): number
		local ff = lerp(0.86, 1.06, (f - 2) / 27)
		if f == 30 then
			ff += 0.06 -- 최상층 프리미엄
		end
		return ff
	end,
	units = function(f: number)
		local t = (f - 2) / 28
		local center = lerp(0.3, 0.98, t)
		local side = lerp(0.18, 0.78, t)
		local corner = lerp(0.24, 0.9, t)
		if f <= 4 then
			center -= 0.1 -- 저층: 앞 동·상가에 가려요
			side -= 0.08
		end
		if f == 30 then
			return {
				{ layout = "apt114", side = "sea", view = 1.0 },
				{ layout = "apt114", side = "sea", view = 0.98 },
			}
		elseif f >= 20 then
			return {
				{ layout = "apt84b", side = "corner", view = corner },
				{ layout = "apt114", side = "sea", view = center },
				{ layout = "apt114", side = "sea", view = center - 0.02 },
				{ layout = "apt84b", side = "corner", view = corner - 0.03 },
			}
		elseif f >= 10 then
			return {
				{ layout = "apartment", side = "side", view = side },
				{ layout = "apartment", side = "sea", view = center },
				{ layout = "apt84b", side = "sea", view = center - 0.02 },
				{ layout = "apt84b", side = "corner", view = corner },
			}
		end
		return {
			{ layout = "apt59a", side = "side", view = side },
			{ layout = "apartment", side = "sea", view = center },
			{ layout = "apartment", side = "sea", view = center - 0.02 },
			{ layout = "apt59a", side = "side", view = side - 0.03 },
		}
	end,
})

-- 아쿠아펠리스 펜트하우스 레지던스: duplex units on 20/21, 22/23, 24/25F (2 per level)
F.buildings.aqua_ph = makeBuilding("aqua_ph", {
	name = "아쿠아펠리스 레지던스", dong = "펜트하우스동", site = "호텔 아쿠아펠리스", kind = "penthouse",
	floorH = 3.6, elevator = true, lobby = "penthouse",
	floorList = { 20, 22, 24 },
	default = { floor = 22, unit = "2201" },
	floorFactor = function(f: number): number
		return if f >= 24 then 1.12 elseif f >= 22 then 1.0 else 0.94
	end,
	units = function(f: number)
		local v = if f >= 24 then 1.0 elseif f >= 22 then 0.94 else 0.88
		return {
			{ layout = "penthouse", side = "sea", view = v },
			{ layout = "penthouse", side = "beach", view = v - 0.04 },
		}
	end,
})

-- lookup index: idx[listingId][unitName] = row
local idx: { [string]: { [string]: any } } = {}
for id, b in F.buildings do
	local m = {}
	for _, f in b.floors do
		for _, row in f.units do
			m[row.unit] = row
		end
	end
	idx[id] = m
end

-------------------------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------------------------
function F.buildingOf(listingId: any): any?
	return if type(listingId) == "string" then F.buildings[listingId] else nil
end

function F.floorRow(listingId: string, floor: any): any?
	local b = F.buildings[listingId]
	local n = tonumber(floor)
	if not b or not n then
		return nil
	end
	for _, f in b.floors do
		if f.floor == n then
			return f
		end
	end
	return nil
end

function F.floorsOf(listingId: string): { number }
	local out = {}
	local b = F.buildings[listingId]
	if b then
		for _, f in b.floors do
			table.insert(out, f.floor)
		end
	end
	return out
end

-- unit: "1502" | 1502 | the 1-based index on that floor (numbers < 100). Returns the unit row
-- { unit, floor, index, layout, view, priceMult, side, label } or nil.
function F.unitFor(listingId: string, floor: any, unit: any): any?
	local m = idx[listingId]
	if not m then
		return nil
	end
	if type(unit) == "number" and unit >= 1 and unit < 100 and isNum(unit) then
		local f = F.floorRow(listingId, floor)
		return f and f.units[math.floor(unit)] or nil
	end
	local key = tostring(unit or "")
	key = string.gsub(key, "호$", "")
	local row = m[key]
	if row and (floor == nil or tonumber(floor) == row.floor) then
		return row
	end
	return nil
end

-- basePrice * priceMult, rounded (>= 1,000,000 -> 10,000 / >= 10,000 -> 100 / else 10).
function F.priceFor(listingId: string, floor: any, unit: any, basePrice: number): number
	if not isNum(basePrice) then
		return 0
	end
	local row = F.unitFor(listingId, floor, unit)
	local mult = row and row.priceMult or 1
	local v = basePrice * mult
	local step = if basePrice >= 1000000 then 10000 elseif basePrice >= 10000 then 100 else 10
	if basePrice <= 0 then
		return 0
	end
	return math.max(step, math.floor(v / step + 0.5) * step)
end

-- A sensible default unit for migrated saves: floor, unit (its layout is the tier's default).
function F.defaultUnit(listingId: string): (number?, string?)
	local b = F.buildings[listingId]
	if not b then
		return nil, nil
	end
	return b.default.floor, b.default.unit
end

function F.defaultLayout(tierKey: string): string
	return F.TIER_DEFAULT[tierKey] or tierKey
end

function F.unitLabel(listingId: string, floor: any, unit: any): string
	local b = F.buildings[listingId]
	local row = F.unitFor(listingId, floor, unit)
	local name = b and b.name or tostring(listingId)
	local u = row and row.label or (tostring(unit or "") .. "호")
	if b and b.dong and b.dong ~= b.name then
		return string.format("%s %s %s", name, b.dong, u)
	end
	return string.format("%s %s", name, u)
end

-- 1..5 view stars from the 0..1 view value.
function F.viewStars(view: number?): number
	return math.clamp(math.floor((view or 0) * 5 + 0.5), 1, 5)
end

-- Window altitude (metres above the street) of a floor.
function F.altitudeOf(listingId: string, floor: number): number
	local b = F.buildings[listingId]
	local h = b and b.floorH or 3
	return (math.max(1, floor) - 1) * h + 1.5
end

-- Availability-free summary rows for UIs: { {floor, units = { {unit, layout, label, view, stars, priceMult} } } }
function F.marketRows(listingId: string): { any }
	local out = {}
	local b = F.buildings[listingId]
	if not b then
		return out
	end
	for _, f in b.floors do
		local units = {}
		for _, row in f.units do
			local l = F.layouts[row.layout]
			table.insert(units, { unit = row.unit, layout = row.layout, label = l and l.label or row.layout, short = l and l.short or row.layout, view = row.view, stars = F.viewStars(row.view), priceMult = row.priceMult, side = row.side })
		end
		table.insert(out, { floor = f.floor, units = units })
	end
	return out
end

-- Self-check (Lune tests / build): returns ok, { problems }.
function F.validate(G: any?): (boolean, { string })
	local errs = {}
	local function bad(msg: string)
		table.insert(errs, msg)
	end
	for _, id in F.LAYOUT_ORDER do
		local l = F.layouts[id]
		if not l then
			bad("LAYOUT_ORDER lists unknown layout " .. id)
		elseif type(l.plan) ~= "table" or #l.plan == 0 then
			bad("layout " .. id .. " has no plan")
		end
	end
	for id, l in F.layouts do
		if not table.find(F.LAYOUT_ORDER, id) then
			bad("layout " .. id .. " missing from LAYOUT_ORDER")
		end
		if not F.TIER_DEFAULT[l.tierKey] then
			bad("layout " .. id .. " has unknown tierKey " .. tostring(l.tierKey))
		end
	end
	for _, lid in F.BUILDING_ORDER do
		local b = F.buildings[lid]
		if not b then
			bad("no building for listing " .. lid)
			continue
		end
		local seen = {}
		for _, f in b.floors do
			for _, row in f.units do
				if not F.layouts[row.layout] then
					bad(string.format("%s %s: unknown layout %s", lid, row.unit, tostring(row.layout)))
				elseif G and G.LISTINGS and G.LISTINGS[lid] and F.layouts[row.layout].tierKey ~= G.LISTINGS[lid].tierKey then
					bad(string.format("%s %s: layout %s is not of tier %s", lid, row.unit, row.layout, tostring(G.LISTINGS[lid].tierKey)))
				end
				if seen[row.unit] then
					bad(lid .. " duplicate unit " .. row.unit)
				end
				seen[row.unit] = true
				if not (isNum(row.priceMult) and row.priceMult > 0.3 and row.priceMult < 3) then
					bad(lid .. " " .. row.unit .. " priceMult out of range")
				end
			end
		end
		local d = F.unitFor(lid, b.default.floor, b.default.unit)
		if not d then
			bad(lid .. " default unit missing")
		elseif d.priceMult ~= 1 then
			bad(lid .. " default unit priceMult ~= 1 (" .. tostring(d.priceMult) .. ")")
		elseif F.layouts[d.layout] and F.layouts[d.layout].tierKey ~= d.layout then
			bad(lid .. " default unit is not on the tier's default layout")
		end
	end
	if G and G.LISTINGS then
		for lid in G.LISTINGS do
			if not F.buildings[lid] then
				bad("G.LISTINGS id without a building: " .. lid)
			end
		end
	end
	return #errs == 0, errs
end

-------------------------------------------------------------------------------------------------
-- Runtime (Roblox instances only)
-------------------------------------------------------------------------------------------------
-- Template Model for a layout: "HomeUnit_<layoutId>", else the tier default (tierKey or the
-- layout's tier), else nil.
function F.findTemplate(folder: any, layoutId: string?, tierKey: string?): any?
	if not folder then
		return nil
	end
	local l = layoutId and F.layouts[layoutId]
	local names = {}
	if layoutId then
		table.insert(names, "HomeUnit_" .. layoutId)
	end
	local tk = tierKey or (l and l.tierKey)
	if tk then
		table.insert(names, "HomeUnit_" .. tk)
	end
	for _, n in names do
		local m = folder:FindFirstChild(n)
		if m and m:IsA("Model") then
			return m
		end
	end
	return nil
end

-- Re-projects the window-view miniature of a unit for `floor` (the template's Backdrop carries
-- ViewMode = "mini" | "alley", ViewFloor (floor it was built for), ViewStep (studs of eye height
-- per floor), ViewFar, ViewZEye; parts with attribute ViewFixed never move). A miniature point
-- at local depth z sits at y = eye + (Y - E) * s with s = 1 - (zEye - z) / far, so a new eye
-- height E + dE moves it by -dE * s: an exact shear of the picture (the horizon stays at eye
-- height, near rooftops sink below the sill on high floors, neighbours tower on low floors).
-- Alley views (true scale) simply move down by dE. Idempotent (ViewApplied remembers the floor).
function F.applyFloorView(model: any, floor: any): boolean
	local n = tonumber(floor)
	if not model or not n then
		return false
	end
	local view = model:FindFirstChild("Backdrop")
	local root = model.PrimaryPart or model:FindFirstChild("UnitRoot")
	if not view or not root then
		return false
	end
	local mode = view:GetAttribute("ViewMode")
	local built = view:GetAttribute("ViewFloor")
	local step = view:GetAttribute("ViewStep")
	if (mode ~= "mini" and mode ~= "alley") or not isNum(built) or not isNum(step) then
		return false
	end
	local minF, maxF = view:GetAttribute("ViewMinFloor"), view:GetAttribute("ViewMaxFloor")
	if isNum(minF) then
		n = math.max(n, minF)
	end
	if isNum(maxF) then
		n = math.min(n, maxF)
	end
	local cur = view:GetAttribute("ViewApplied")
	if not isNum(cur) then
		cur = built
	end
	local dE = (n - cur) * step
	if math.abs(dE) < 0.01 then
		view:SetAttribute("ViewApplied", n)
		return true
	end
	local rootCf = root.CFrame
	local far = view:GetAttribute("ViewFar") or 180
	local zEye = view:GetAttribute("ViewZEye") or 0
	local c = -dE / far -- y += a + c * z
	local a = -dE + dE * zEye / far
	for _, d in view:GetDescendants() do
		if not d:IsA("BasePart") or d:GetAttribute("ViewFixed") then
			continue
		end
		local rel = rootCf:ToObjectSpace(d.CFrame)
		if mode == "alley" then
			d.CFrame = rootCf * (CFrame.new(0, -dE, 0) * rel)
			continue
		end
		local p = rel.Position
		local np = Vector3.new(p.X, p.Y + a + c * p.Z, p.Z)
		local isBlock = not d:IsA("Part") or d.Shape == Enum.PartType.Block
		if not isBlock then
			d.CFrame = rootCf * (CFrame.new(np) * (rel - rel.Position))
			continue
		end
		local s = d.Size
		local axes = { rel.XVector * s.X, rel.YVector * s.Y, rel.ZVector * s.Z }
		local t = {}
		for i, v in axes do
			t[i] = Vector3.new(v.X, v.Y + c * v.Z, v.Z)
		end
		-- order the axes by transformed length, rebuild an orthonormal frame around the two longest
		local order = { 1, 2, 3 }
		table.sort(order, function(i, j)
			return t[i].Magnitude > t[j].Magnitude
		end)
		local i1, i2, i3 = order[1], order[2], order[3]
		local e1 = t[i1].Unit
		local v2 = t[i2] - e1 * t[i2]:Dot(e1)
		if v2.Magnitude < 1e-6 then
			d.CFrame = rootCf * (CFrame.new(np) * (rel - rel.Position))
			continue
		end
		local e2 = v2.Unit
		local e3 = e1:Cross(e2)
		if e3:Dot(t[i3]) < 0 then
			e3 = -e3
		end
		local ax = {}
		ax[i1], ax[i2], ax[i3] = e1, e2, e3
		local size = {}
		size[i1] = t[i1].Magnitude
		size[i2] = v2.Magnitude
		size[i3] = math.max(0.05, math.abs(t[i3]:Dot(e3)))
		-- a box is symmetric under axis negation, so Z = X x Y is fine either way
		local cf = CFrame.fromMatrix(np, ax[1], ax[2])
		d.Size = Vector3.new(math.max(0.05, size[1]), math.max(0.05, size[2]), math.max(0.05, size[3]))
		d.CFrame = rootCf * cf
	end
	view:SetAttribute("ViewApplied", n)
	return true
end

-- Server, after the instance clone is pivoted: per-floor view + the unit's own signs (TextLabels
-- with attribute UnitSign = "label" | "unit" | "floor" inside the template, e.g. the 월패드 screen).
function F.prepareInstance(model: any, listingId: string, floor: any, unit: any): boolean
	if not model then
		return false
	end
	local row = F.unitFor(listingId, floor, unit)
	local fl = row and row.floor or tonumber(floor)
	if not fl then
		local df = F.defaultUnit(listingId)
		fl = df
	end
	if fl then
		pcall(F.applyFloorView, model, fl)
	end
	local b = F.buildings[listingId]
	local uName = row and row.unit or tostring(unit or "")
	local label = F.unitLabel(listingId, fl, uName)
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") then
			local kind = d:GetAttribute("UnitSign")
			if kind == "label" then
				d.Text = label
			elseif kind == "unit" then
				d.Text = uName .. "호"
			elseif kind == "floor" then
				d.Text = tostring(fl or "") .. "F"
			elseif kind == "building" then
				d.Text = b and (b.name .. (b.dong ~= b.name and (" " .. b.dong) or "")) or ""
			end
		end
	end
	model:SetAttribute("Floor", fl)
	model:SetAttribute("Unit", uName)
	return true
end

-- Client: shows the hall of a building as floor `floor` for this player: door numbers ("1502호"),
-- floor signs ("15F"), unused doors blanked; returns the door part of `myUnit` (HomeEntrance part
-- with attribute Unit = index) or nil. Hall parts: TextLabels with attribute HallSign = "door" (+
-- Unit = index) | "floor" | "floorBig"; door triggers tagged HomeEntrance with attribute Unit.
function F.prepareHall(hall: any, listingId: string, floor: any, myUnit: any): any?
	local f = F.floorRow(listingId, floor)
	if not hall or not f then
		return nil
	end
	local mine = F.unitFor(listingId, f.floor, myUnit)
	local myIndex = mine and mine.index or nil
	local door = nil
	for _, d in hall:GetDescendants() do
		if d:IsA("TextLabel") then
			local kind = d:GetAttribute("HallSign")
			if kind == "door" then
				local i = d:GetAttribute("Unit")
				local row = isNum(i) and f.units[i] or nil
				d.Text = if row then row.label else ""
			elseif kind == "floor" then
				d.Text = tostring(f.floor) .. "F"
			elseif kind == "floorBig" then
				d.Text = tostring(f.floor)
			end
		elseif d:IsA("BasePart") and myIndex and d:GetAttribute("Unit") == myIndex and d:HasTag("HomeEntrance") then
			door = d
		end
	end
	hall:SetAttribute("ShownFloor", f.floor)
	return door
end

-- Client: elevator ride. spec = {
--   car = Model (doors "DoorL" / "DoorR" BaseParts with Vector3 attribute OpenOffset in the
--         door's local space, TextLabel with attribute ElevatorSign = "floor"),
--   toCar = Model? (the car at the destination; defaults to `car`), from = n, to = n,
--   onMid = function() (teleport while the doors are shut), sound = true }
-- Doors close (0.7 s), the floor display counts (max ~2.6 s), ding, doors open at the
-- destination. Yields: call it inside task.spawn.
function F.rideEffect(spec: any): boolean
	local TweenService = game:GetService("TweenService")
	local car, toCar = spec.car, spec.toCar or spec.car
	local from, to = tonumber(spec.from) or 1, tonumber(spec.to) or 1
	local function doors(m: any): { any }
		local out = {}
		if not m then
			return out
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "DoorL" or d.Name == "DoorR") and typeof(d:GetAttribute("OpenOffset")) == "Vector3" then
				if d:GetAttribute("ClosedCF") == nil then
					d:SetAttribute("ClosedCF", d.CFrame)
				end
				table.insert(out, d)
			end
		end
		return out
	end
	local function setDoors(m: any, open: boolean, t: number)
		for _, d in doors(m) do
			local closed = d:GetAttribute("ClosedCF")
			if typeof(closed) == "CFrame" then
				local goal = if open then closed * CFrame.new(d:GetAttribute("OpenOffset")) else closed
				TweenService:Create(d, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = goal }):Play()
			end
		end
	end
	local function display(m: any, n: number, dir: number)
		if not m then
			return
		end
		for _, d in m:GetDescendants() do
			if d:IsA("TextLabel") and d:GetAttribute("ElevatorSign") == "floor" then
				d.Text = (if dir > 0 then "▲ " elseif dir < 0 then "▼ " else "") .. tostring(n)
			end
		end
	end
	local function sound(id: string, speed: number, vol: number)
		if spec.sound == false then
			return
		end
		local s = Instance.new("Sound")
		s.SoundId = id
		s.PlaybackSpeed = speed
		s.Volume = vol
		s.Parent = workspace.CurrentCamera or workspace
		s:Play()
		task.delay(3, function()
			s:Destroy()
		end)
	end
	sound("rbxasset://sounds/swoosh.wav", 0.55, 0.25)
	setDoors(car, false, 0.7)
	task.wait(0.75)
	local dir = if to > from then 1 elseif to < from then -1 else 0
	local steps = math.abs(to - from)
	local per = if steps > 0 then math.clamp(2.6 / steps, 0.06, 0.5) else 0
	local mid = math.floor(steps / 2)
	for k = 0, steps do
		local n = from + dir * k
		display(car, n, dir)
		display(toCar, n, dir)
		if k == mid and spec.onMid then
			pcall(spec.onMid)
		end
		if k < steps then
			task.wait(per)
		end
	end
	if steps == 0 and spec.onMid then
		pcall(spec.onMid)
	end
	display(toCar, to, 0)
	sound("rbxasset://sounds/electronicpingshort.wav", 1.25, 0.45)
	task.wait(0.25)
	sound("rbxasset://sounds/swoosh.wav", 0.6, 0.2)
	setDoors(toCar, true, 0.8)
	task.delay(4, function()
		setDoors(toCar, false, 0.8)
	end)
	return true
end

return F
