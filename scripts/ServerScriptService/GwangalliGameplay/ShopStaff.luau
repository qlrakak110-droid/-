--!nocheck
-- GwangalliGameplay/ShopStaff (server, feature module; owner: npc_mind · NPC session): a staff NPC behind
-- the counter of every shop in the map (편의점 점원, 카페 바리스타, 약사, 식당 사장님, 호텔 프런트 ...).
--
--   * SITES: found once in the place. A storefront is a Model with a `ShopFloor` child; its cashier
--     anchor is the first of ANCHORS (PosBase, CashierPanel, OrderKiosk, FrontDesk, BackBar, POS,
--     BarCounter, 바 카운터, ShopCounter-tagged, Counter) inside it. Landmark counters outside any storefront
--     (홈플러스 POS, 홍미당 POS, 브롱스 BarCounter, 빵집 POS ...) are sites too. Storefronts with no counter
--     (offices, homes) get nobody. The staff stands behind the counter (away from the door / window,
--     toward the back wall) on the floor, facing the door.
--   * SKIPPED: a counter that already has somebody (GwShopClerk / VenueStaff / HospitalStaff /
--     GarageStaff rigs, the key NPCs of NPC.luau in workspace.GwangalliNPCs) within STAFF_R studs.
--     The static GwShopClerk rigs of the 7 street shops get the NPC attributes instead (animated by
--     GwangalliNPCClient) and the same prompt.
--   * STREAMING: rigs exist only while a player is within ON_R studs (off beyond OFF_R), at most
--     MAX_ACTIVE at a time (the nearest first): ~400 storefronts cost nothing far away.
--   * LIFE: a work act per shop kind (teller / wipe / typing / cup / cook ...) that changes every
--     20-40 s; "어서 오세요" once a minute when a player walks up to the counter; a ProximityPrompt
--     "말 걸기" -> a short line from the shop kind's bank (greet / small talk / menu), facing the player.
--   * BOUNDARY: no pay, no orders, no job logic (the 알바 session / Customers own those); no HUD.
--     The rigs use the NPC.luau attribute contract (NpcId / NpcKind "shop" / NpcGround / NpcAct /
--     NpcYaw / NpcLeg / NpcEmote) and GwangalliNPCLooks.
--   API: ctx.shopStaff = ShopStaff; ShopStaff.sites() -> { site... }, ShopStaff.active() -> n,
--   ShopStaff.status() (debug).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ShopStaff = {}

local ON_R, OFF_R = 150, 180
local MAX_ACTIVE = 36
local STAFF_R = 9
local GREET_R = 11

-- cashier anchors, best first (a storefront's `Counter` is often the back food counter)
local ANCHORS = { "PosBase", "CashierPanel", "OrderKiosk", "FrontDesk", "BackBar", "POS", "BarCounter", "바 카운터", "안내 · 접수 카운터", "Counter" }
local ANCHOR_RANK: { [string]: number } = {}
for i, n in ANCHORS do
	ANCHOR_RANK[n] = i
end
-- landmark counters outside storefronts (a `Counter` alone there is too often furniture)
local LOOSE = { PosBase = true, POS = true, BarCounter = true, ["바 카운터"] = true, FrontDesk = true, CashierPanel = true, ["안내 · 접수 카운터"] = true }

-- shop kinds: name keywords (first hit wins), look, acts, label, lines
local KINDS = {
	{ k = "cvs", keys = { "GS25", "CU", "7-ELEVEn", "세븐일레븐", "emart24", "이마트24", "편의점", "미니스톱" }, style = { "casual", "apron" }, acts = { "teller", "typing", "teller", "wipe" }, label = "편의점 점원" },
	{ k = "mart", keys = { "홈플러스", "마트", "슈퍼", "market", "Market" }, style = { "apron" }, acts = { "teller", "typing" }, label = "마트 계산원" },
	{ k = "cafe", keys = { "COFFEE", "Coffee", "coffee", "커피", "카페", "CAFE", "Cafe", "스타벅스", "STARBUCKS", "PASCUCCI", "COMPOSE", "TWOSOME", "투썸", "이디야", "EDIYA", "빽다방", "메가", "MEGA" }, style = { "apron" }, acts = { "cup", "wipe", "teller", "cup" }, label = "바리스타" },
	{ k = "bakery", keys = { "빵", "베이커리", "Bakery", "BAKERY", "제과", "홍미당", "fondx", "파리바게뜨", "뚜레쥬르" }, style = { "apron", "chef" }, acts = { "teller", "wipe", "cup" }, label = "빵집 직원" },
	{ k = "pharmacy", keys = { "약국", "PHARM", "Pharm" }, style = { "doctor" }, acts = { "teller", "typing", "clipboard" }, label = "약사" },
	{ k = "beauty", keys = { "OLIVE", "올리브영", "화장품", "랄라블라", "코스메틱" }, style = { "trendy", "apron" }, acts = { "teller", "wipe", "typing" }, label = "매장 직원" },
	{ k = "hotel", keys = { "호텔", "HOTEL", "Hotel", "모텔", "레지던스", "게스트하우스", "리조트" }, style = { "suit", "reception" }, acts = { "typing", "teller", "behind" }, label = "프런트 직원" },
	{ k = "pub", keys = { "펍", "PUB", "Pub", "포차", "호프", "맥주", "BEER", "Beer", "브루잉", "브롱스", "BAR", "Bar", "바 ", "이자카야", "술집" }, style = { "black", "apron" }, acts = { "wipe", "cup", "arms_crossed", "wipe" }, label = "바텐더" },
	{ k = "food", keys = { "SUBWAY", "버거", "BURGER", "Burger", "치킨", "국밥", "분식", "떡볶이", "식당", "회", "횟집", "고기", "갈비", "삼겹", "냉면", "밀면", "돈까스", "초밥", "스시", "라멘", "피자", "PIZZA", "김밥", "족발", "곱창", "반점", "짜장", "F&B", "푸드", "FOOD", "Food", "키친", "Kitchen" }, style = { "chef", "apron" }, acts = { "cook", "chop", "wipe", "teller" }, label = "사장님" },
	{ k = "fashion", keys = { "옷", "의류", "편집숍", "ZARA", "UNIQLO", "유니클로", "SPAO", "스파오", "TOPTEN", "탑텐", "ABC", "슈즈", "신발", "패션", "clothing", "부티크" }, style = { "trendy", "street" }, acts = { "behind", "teller", "hips" }, label = "매장 직원" },
	{ k = "salon", keys = { "헤어", "미용", "HAIR", "Hair", "salon", "네일", "NAIL" }, style = { "black", "trendy" }, acts = { "behind", "teller", "phone" }, label = "헤어 디자이너" },
	{ k = "game", keys = { "PC방", "PC", "노래", "코인", "게임", "오락", "당구", "볼링", "VR" }, style = { "hoodie", "casual" }, acts = { "typing", "phone", "teller" }, label = "알바생" },
	{ k = "phone", keys = { "휴대폰", "통신", "SKT", "KT", "LG U", "폰" }, style = { "office" }, acts = { "typing", "teller" }, label = "상담원" },
	{ k = "realty", keys = { "부동산", "공인중개" }, style = { "office", "suit" }, acts = { "typing", "phone" }, label = "중개사" },
	{ k = "bank", keys = { "은행", "BANK", "Bank", "ATM" }, style = { "suit", "office" }, acts = { "teller", "typing" }, label = "은행원" },
	{ k = "rental", keys = { "대여", "렌탈", "SUP", "서프", "레포츠", "파라솔", "비치바" }, style = { "surf", "sporty" }, acts = { "arms_crossed", "teller", "lean" }, label = "대여소 직원" },
	{ k = "shop", keys = {}, style = { "casual", "apron", "office" }, acts = { "teller", "wipe", "behind" }, label = "점원" },
}
local KIND_BY: { [string]: any } = {}
for _, d in KINDS do
	KIND_BY[d.k] = d
end

-- what they say (the Busan ones drop a "-예 / -능교" in now and then: see busan())
local LINES = {
	cvs = {
		greet = { "어서 오세요~", "어서 오세요! 봉투 필요하시면 말씀하세요.", "안녕하세요~ 1+1 행사 중이에요." },
		talk = { "삼각김밥은 오늘 새로 들어왔어요.", "결제는 카드도 되고 페이도 돼요.", "음료는 뒤쪽 냉장고에 있어요.", "밤에는 좀 한가해요 ㅎㅎ", "포인트 적립하시겠어요?" },
	},
	mart = {
		greet = { "어서 오세요~", "안녕하세요! 오늘 과일 세일해요." },
		talk = { "계산은 이쪽에서 도와드릴게요.", "장바구니는 입구에 있어요.", "봉투 20원이에요.", "오늘 우유 1+1이에요." },
	},
	cafe = {
		greet = { "어서 오세요! 주문 도와드릴게요.", "안녕하세요~ 뭐 드릴까요?", "어서 오세요~" },
		talk = { "오늘은 아이스 아메리카노가 제일 잘 나가요.", "시즌 메뉴 한번 드셔 보세요!", "진동벨 울리면 픽업대로 와 주세요.", "드시고 가세요, 가져가세요?", "샷 추가 500원이에요." },
	},
	bakery = {
		greet = { "어서 오세요~ 방금 나왔어요!", "안녕하세요! 빵 따끈따끈해요." },
		talk = { "소금빵이 제일 인기예요.", "쟁반이랑 집게는 저기 있어요.", "오후엔 금방 다 팔려요.", "포장해 드릴까요?" },
	},
	pharmacy = {
		greet = { "어서 오세요. 어디가 불편하세요?", "안녕하세요~" },
		talk = { "식후 30분에 드세요.", "처방전 있으시면 주세요.", "감기약은 졸릴 수 있어요.", "물 많이 드시고 푹 쉬세요." },
	},
	beauty = {
		greet = { "어서 오세요~ 천천히 둘러보세요!", "안녕하세요~ 오늘 세일 많이 해요." },
		talk = { "테스터 써 보셔도 돼요.", "이거 요즘 제일 잘 나가요.", "멤버십 있으세요?", "선크림은 이쪽이에요." },
	},
	hotel = {
		greet = { "어서 오십시오. 체크인 도와드릴까요?", "안녕하세요, 프런트입니다." },
		talk = { "체크인은 오후 3시부터입니다.", "오션뷰 객실은 오늘 만실이에요.", "조식은 7시부터 10시까지입니다.", "짐은 맡겨 두셔도 됩니다." },
	},
	pub = {
		greet = { "어서 오세요~ 몇 분이세요?", "어서 와요! 오늘 생맥 시원해요." },
		talk = { "오늘 수제 맥주 새로 들어왔어요.", "안주는 감자튀김이 제일 잘 나가요.", "광안대교 보면서 한잔하기 딱이죠.", "신분증 확인 좀 할게요~" },
	},
	food = {
		greet = { "어서 오이소~ 몇 분이세요?", "어서 오세요! 앉고 싶은 데 앉으세요.", "어서 오세요~" },
		talk = { "오늘은 이게 제일 맛있어요.", "곱빼기도 돼요!", "포장도 됩니다.", "조금만 기다리시면 금방 나와요.", "맛있게 드세요~" },
	},
	fashion = {
		greet = { "어서 오세요~ 편하게 보세요!", "안녕하세요~ 신상 들어왔어요." },
		talk = { "피팅룸은 저쪽이에요.", "이거 사이즈 다 있어요.", "요즘 이 스타일 많이 찾으세요.", "교환은 일주일 안에 가능해요." },
	},
	salon = {
		greet = { "어서 오세요~ 예약하셨어요?", "안녕하세요~ 커트세요, 펌이세요?" },
		talk = { "오늘은 예약이 좀 꽉 찼어요.", "이 머리 진짜 잘 어울리실 것 같아요.", "샴푸부터 해 드릴게요.", "드라이까지 해 드려요." },
	},
	game = {
		greet = { "어서 오세요~", "자리 아무 데나 앉으시면 돼요." },
		talk = { "충전은 카운터에서 해 드려요.", "컵라면도 팔아요.", "요즘 다들 이 게임만 해요.", "음료는 저기 냉장고에 있어요." },
	},
	phone = {
		greet = { "어서 오세요~ 상담 도와드릴까요?" },
		talk = { "요금제 바꾸시면 더 싸요.", "신규 가입하시면 사은품 드려요.", "기기 변경이세요?" },
	},
	realty = {
		greet = { "어서 오세요. 집 보러 오셨어요?" },
		talk = { "광안리 오션뷰는 좀 비싸요.", "월세 매물 몇 개 있어요.", "언제쯤 입주하시게요?" },
	},
	bank = {
		greet = { "어서 오세요. 번호표 뽑아 주세요." },
		talk = { "통장 개설 도와드릴까요?", "ATM은 24시간이에요.", "신분증 준비해 주세요." },
	},
	rental = {
		greet = { "어서 오세요! 뭐 빌리러 오셨어요?", "안녕하세요~" },
		talk = { "SUP 한 시간에 2만 원이에요.", "구명조끼는 꼭 입으셔야 돼요.", "파라솔은 하루 단위예요.", "오늘 바다 잔잔해서 딱 좋아요." },
	},
	shop = {
		greet = { "어서 오세요~", "안녕하세요~ 천천히 보세요." },
		talk = { "찾으시는 거 있으세요?", "그건 저쪽에 있어요.", "계산은 여기서 해 드릴게요.", "오늘 날씨 좋네요~" },
	},
}
local BUSY = { "잠시만요~", "네, 금방 갈게요!", "앗, 잠깐만요." }
local BYE = { "감사합니다~ 또 오세요!", "안녕히 가세요~", "좋은 하루 되세요!" }

local ctx: any
local Looks: any = nil
local rng = Random.new()
local sites: { any } = {}
local active = 0
local npcFolder: Instance
local serial = 0
local scanned = false

local function now(): number
	return os.clock()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function pick(list: { any }): any
	return list[rng:NextInteger(1, #list)]
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function kindOf(name: string, anchorName: string?): any
	for _, d in KINDS do
		for _, key in d.keys do
			if string.find(name, key, 1, true) then
				return d
			end
		end
	end
	if anchorName == "FrontDesk" then
		return KIND_BY.hotel
	elseif anchorName == "BackBar" or anchorName == "BarCounter" then
		return KIND_BY.pub
	end
	return KIND_BY.shop
end

-------------------------------------------------------------------------------------------------
-- Site discovery
-------------------------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function floorAt(p: Vector3, top: number, ignore: { Instance }): number?
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(p.X, top, p.Z), Vector3.new(0, -14, 0), rayParams)
	return hit and hit.Position.Y or nil
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

-- a standing spot is free: nothing solid at chest height (a 1.6 x 2.6 x 1.6 box)
local function clear(p: Vector3, ignore: { Instance }): boolean
	overlap.FilterDescendantsInstances = ignore
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 2.6, 0)), Vector3.new(1.6, 2.6, 1.6), overlap)
	end)
	if not ok then
		return true
	end
	for _, q in parts do
		if q.CanCollide and q.Transparency < 0.95 then
			return false
		end
	end
	return true
end

-- the door / window side of a storefront (the staff faces it)
local function frontOf(model: Instance, anchor: BasePart): Vector3?
	local best: Vector3? = nil
	for _, d in model:GetDescendants() do
		local n = d.Name
		if (n == "AutoDoor" or n == "Door" or n == "ShopWindow" or string.sub(n, 1, 9) == "AutoDoor_") then
			local p = if d:IsA("BasePart") then d.Position elseif d:IsA("Model") then d:GetPivot().Position else nil
			if p and (not best or flat(p, anchor.Position) < flat(best, anchor.Position)) then
				best = p
			end
		end
	end
	return best
end

local function backOf(model: Instance): Vector3?
	local w = model:FindFirstChild("ShopBackWall", true)
	return if w and w:IsA("BasePart") then w.Position else nil
end

-- behind the counter: away from the front (or toward the back wall), just past the counter's half
-- depth; tries the other side / a little to the sides when that spot is blocked
local function standSpot(model: Instance, anchor: BasePart, floorY: number?): (Vector3?, Vector3?)
	local front = frontOf(model, anchor)
	local back = backOf(model)
	local a = anchor.Position
	local dir: Vector3
	if front and flat(front, a) > 1 then
		dir = Vector3.new(a.X - front.X, 0, a.Z - front.Z).Unit
	elseif back and flat(back, a) > 1 then
		dir = Vector3.new(back.X - a.X, 0, back.Z - a.Z).Unit
	else
		dir = -Vector3.new(anchor.CFrame.LookVector.X, 0, anchor.CFrame.LookVector.Z).Unit
	end
	-- the counter's half extent along dir
	local cf = anchor.CFrame
	local s = anchor.Size / 2
	local half = math.abs(cf.RightVector:Dot(dir)) * s.X + math.abs(cf.UpVector:Dot(dir)) * s.Y + math.abs(cf.LookVector:Dot(dir)) * s.Z
	local ignore = { anchor }
	local side = dir:Cross(Vector3.yAxis)
	for _, off in { { 1, 0 }, { 1, 1.4 }, { 1, -1.4 }, { 1.4, 0 }, { -1, 0 } } do
		local d = dir * off[1]
		local p = a + d * (half + 1.7) + side * off[2]
		local fy = floorY or floorAt(p, a.Y + 1, { anchor, npcFolder })
		if fy and math.abs(fy - (a.Y - s.Y)) < 9 then
			local feet = Vector3.new(p.X, fy, p.Z)
			if clear(feet, ignore) then
				return feet, -d
			end
		end
	end
	return nil, nil
end

-- somebody already works at this counter (static clerks / venue staff / key NPCs)
local staffAt: { Vector3 } = {}
local jobAt: { Vector3 } = {}
-- stores the 알바 jobs / NPC customers run (GwangalliCustomerShared.SITES): no extra staff there
local JOB_SITES = { ["스타벅스 광안리점"] = true, ["GS25 광안리점"] = true }
local function collectStaff()
	table.clear(staffAt)
	table.clear(jobAt)
	for _, tag in { "GwShopClerk", "VenueStaff", "HospitalStaff", "GarageStaff", "GwInteractRig" } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				table.insert(staffAt, m:GetPivot().Position)
			elseif m:IsA("BasePart") then
				table.insert(staffAt, m.Position)
			end
		end
	end
	-- the 알바 job counters (GwJobStation parts; the Customers sites starbucks / gs25): the player works there
	for _, part in CollectionService:GetTagged("GwJobStation") do
		if part:IsA("BasePart") then
			table.insert(staffAt, part.Position)
		end
	end
	for _, d in CollectionService:GetTagged("Destination") do
		local nm = d:IsA("BasePart") and d:GetAttribute("DisplayName")
		if JOB_SITES[nm] then
			table.insert(jobAt, d.Position)
		end
	end
	for _, m in npcFolder:GetChildren() do
		local k = m:IsA("Model") and m:GetAttribute("NpcKind")
		if k == "key" or (k == "street" and m:GetAttribute("NpcPost")) then
			table.insert(staffAt, m:GetPivot().Position)
		end
	end
end

local function staffed(p: Vector3): boolean
	for _, q in jobAt do
		if flat(p, q) < 45 then
			return true
		end
	end
	for _, q in staffAt do
		if flat(p, q) < STAFF_R and math.abs(p.Y - q.Y) < 8 then
			return true
		end
	end
	return false
end

local function bestAnchor(model: Instance): BasePart?
	local best, bestR = nil, math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local r = ANCHOR_RANK[d.Name]
			if not r and CollectionService:HasTag(d, "ShopCounter") then
				r = 0.5
			end
			if r and r < bestR then
				best, bestR = d, r
			end
		end
	end
	return best
end

local function addSite(name: string, model: Instance, anchor: BasePart, floorY: number?)
	local feet, look = standSpot(model, anchor, floorY)
	if not feet then
		return
	end
	for _, s in sites do
		if flat(s.pos, feet) < 6 and math.abs(s.pos.Y - feet.Y) < 6 then
			return -- the same counter (two anchor parts)
		end
	end
	local kind = kindOf(name, anchor.Name)
	table.insert(sites, {
		id = "staff_" .. (#sites + 1),
		name = name,
		kind = kind,
		pos = feet,
		look = look,
		yaw = math.deg(math.atan2(-look.X, -look.Z)),
		counter = anchor.Position,
		model = nil,
		nextAct = 0,
		greetAt = 0,
		busyUntil = 0,
	})
end

local function scan()
	local root = workspace:FindFirstChild("Gwangalli") or workspace
	collectStaff()
	local seen: { [Instance]: boolean } = {}
	local n = 0
	-- 1) storefronts
	for _, d in root:GetDescendants() do
		n += 1
		if n % 4000 == 0 then
			task.wait()
		end
		if d.Name == "ShopFloor" and d:IsA("BasePart") and d.Parent and d.Parent:IsA("Model") then
			local model = d.Parent
			if not seen[model] then
				seen[model] = true
				local a = bestAnchor(model)
				if a and not staffed(a.Position) then
					addSite(model.Name, model, a, d.Position.Y + d.Size.Y / 2)
				end
			end
		end
	end
	-- 2) landmark counters (not inside a storefront)
	n = 0
	for _, d in root:GetDescendants() do
		n += 1
		if n % 4000 == 0 then
			task.wait()
		end
		if d:IsA("BasePart") and (LOOSE[d.Name] or CollectionService:HasTag(d, "ShopCounter")) then
			local m = d:FindFirstAncestorWhichIsA("Model")
			local inside = false
			local x = m
			while x and x ~= root do
				if seen[x] then
					inside = true
					break
				end
				x = x.Parent
			end
			if m and not inside and not staffed(d.Position) then
				-- name: the nearest ancestor that reads like a shop (skip Interior / Detail folders)
				local nm = m.Name
				local y = m
				while y and y ~= root and (string.find(y.Name, "Interior", 1, true) or y.Name == "Detail" or y.Name == "FitOut") do
					y = y.Parent
				end
				if y and y ~= root then
					nm = y.Name
				end
				addSite(nm, y or m, d, nil)
			end
		end
	end
	scanned = true
	print(string.format("[GwangalliShopStaff] %d shop counters found", #sites))
end

-------------------------------------------------------------------------------------------------
-- Rigs
-------------------------------------------------------------------------------------------------
local function setAct(s: any, a: string)
	if s.model then
		s.model:SetAttribute("NpcAct", a)
	end
end

local function emote(s: any, name: string)
	if s.model then
		serial += 1
		s.model:SetAttribute("NpcEmote", name .. "#" .. serial .. "#" .. string.format("%.2f", serverNow()))
	end
end

local function faceTo(s: any, p: Vector3?)
	if not s.model then
		return
	end
	if p then
		local d = p - s.pos
		if Vector3.new(d.X, 0, d.Z).Magnitude > 0.3 then
			s.model:SetAttribute("NpcYaw", math.deg(math.atan2(-d.X, -d.Z)))
			return
		end
	end
	s.model:SetAttribute("NpcYaw", s.yaw)
end

local function bubble(s: any): any?
	if s.bb and s.bb.gui.Parent then
		return s.bb
	end
	local head = s.model and s.model:FindFirstChild("Head")
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "StaffBubble"
	gui.Size = UDim2.fromOffset(220, 56)
	gui.StudsOffset = Vector3.new(0, 2.3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.LightInfluence = 0
	gui.Adornee = head
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.Size = UDim2.new(1, 0, 0, 15)
	tag.BackgroundTransparency = 1
	tag.TextColor3 = Color3.fromRGB(255, 230, 150)
	tag.TextStrokeTransparency = 0.5
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 12
	tag.Text = s.kind.label
	tag.Parent = gui
	local say = Instance.new("TextLabel")
	say.Name = "Say"
	say.Position = UDim2.fromOffset(0, 16)
	say.Size = UDim2.new(1, 0, 0, 34)
	say.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	say.BackgroundTransparency = 0.06
	say.TextColor3 = Color3.fromRGB(30, 30, 40)
	say.Font = Enum.Font.GothamMedium
	say.TextScaled = true
	say.TextWrapped = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = say
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 3), UDim.new(0, 3)
	pad.Parent = say
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 16
	lim.Parent = say
	say.Parent = gui
	gui.Enabled = false
	gui.Parent = head
	s.bb = { gui = gui, say = say }
	return s.bb
end

local function say(s: any, text: string, secs: number?)
	local b = bubble(s)
	if not b then
		return
	end
	b.say.Text = text
	b.gui.Enabled = true
	serial += 1
	local stamp = serial
	s.sayStamp = stamp
	task.delay(secs or 3.4, function()
		if s.sayStamp == stamp and b.gui.Parent then
			b.gui.Enabled = false
		end
	end)
end

local function linesOf(s: any): any
	return LINES[s.kind.k] or LINES.shop
end

local function onTalk(s: any, player: Player)
	if not s.model then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	faceTo(s, root and root.Position)
	local t = now()
	if t < s.busyUntil then
		say(s, pick(BUSY), 2.2)
		return
	end
	s.busyUntil = t + 2.5
	s.talks = (s.talks or 0) + 1
	local L = linesOf(s)
	local text
	if s.talks == 1 or t - (s.lastTalk or 0) > 90 then
		text = pick(L.greet)
		emote(s, "wave")
	elseif s.talks % 5 == 0 then
		text = pick(BYE)
		emote(s, "wave")
	else
		text = pick(L.talk)
	end
	s.lastTalk = t
	say(s, text, 3.6)
	setAct(s, "idle")
	s.nextAct = t + 6
end

local function buildRig(s: any): boolean
	if not Looks then
		return false
	end
	local ok, rig = pcall(function()
		local r = Random.new(#s.id * 7919 + math.floor(s.pos.X * 3 + s.pos.Z))
		local spec = Looks.random(s.id, {
			body = if r:NextNumber() < 0.55 then "f" else "m",
			age = if s.kind.k == "pharmacy" or s.kind.k == "realty" or s.kind.k == "food" then (if r:NextNumber() < 0.6 then "middle" else "adult") elseif s.kind.k == "game" or s.kind.k == "cvs" then "young" else (if r:NextNumber() < 0.6 then "young" else "adult"),
			style = s.kind.style[r:NextInteger(1, #s.kind.style)],
		})
		return Looks.build(spec, { name = "Staff_" .. s.id, anchored = true, shadow = false })
	end)
	if not ok or type(rig) ~= "table" or not rig.model then
		return false
	end
	local m = rig.model
	local ground = rig.ground or 3
	s.model = m
	m:SetAttribute("NpcId", s.id)
	m:SetAttribute("NpcKind", "shop")
	m:SetAttribute("NpcGround", ground)
	m:SetAttribute("NpcAct", pick(s.kind.acts))
	m:SetAttribute("NpcYaw", s.yaw)
	m:SetAttribute("ShopStaff", s.kind.label)
	local p = s.pos
	m:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", p.X, p.Y, p.Z, p.X, p.Y, p.Z, serverNow()))
	m:PivotTo(CFrame.new(p + Vector3.new(0, ground, 0)) * CFrame.Angles(0, math.rad(s.yaw), 0))
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	if root then
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "StaffTalk"
		pr.ActionText = "말 걸기"
		pr.ObjectText = s.kind.label
		pr.KeyboardKeyCode = Enum.KeyCode.E
		pr.HoldDuration = 0
		pr.MaxActivationDistance = 9
		pr.RequiresLineOfSight = false
		pr.Parent = root
		pr.Triggered:Connect(function(player)
			onTalk(s, player)
		end)
	end
	m.Parent = npcFolder
	s.nextAct = now() + rng:NextNumber(15, 35)
	active += 1
	return true
end

local function dropRig(s: any)
	if s.model then
		s.model:Destroy()
		s.model = nil
		s.bb = nil
		active -= 1
	end
end

-- the static clerks of the 7 GwShop street shops: animated + the same prompt
local function adoptClerks()
	for i, m in CollectionService:GetTagged("GwShopClerk") do
		if m:IsA("Model") and not m:GetAttribute("NpcId") then
			local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			if root then
				local cf = root.CFrame
				local fy = floorAt(cf.Position, cf.Position.Y, { m })
				local ground = if fy then math.clamp(cf.Position.Y - fy, 1.5, 5) else 3
				local feet = cf.Position - Vector3.new(0, ground, 0)
				local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				local yaw = if look.Magnitude > 0.1 then math.deg(math.atan2(-look.X, -look.Z)) else 0
				local role = tostring(m:GetAttribute("Role") or "clerk")
				local shopId = tostring(m:GetAttribute("ShopId") or "")
				local kind = if role == "cook" then KIND_BY.food elseif role == "stylist" then KIND_BY.salon elseif role == "pharmacist" then KIND_BY.pharmacy
					elseif shopId == "clothing" then KIND_BY.fashion elseif shopId == "surf" then KIND_BY.rental elseif shopId == "pharmacy" then KIND_BY.pharmacy
					elseif shopId == "salon" then KIND_BY.salon else KIND_BY.food
				local label = tostring(m:GetAttribute("NpcName") or kind.label)
				local s = { id = "clerk_" .. shopId .. "_" .. i, name = shopId, kind = { k = kind.k, label = label, acts = kind.acts, style = kind.style }, pos = feet, look = look, yaw = yaw, model = m, static = true, nextAct = now() + rng:NextNumber(10, 30), greetAt = 0, busyUntil = 0 }
				m:SetAttribute("NpcId", s.id)
				m:SetAttribute("NpcKind", "shop")
				m:SetAttribute("NpcGround", ground)
				m:SetAttribute("NpcAct", tostring(m:GetAttribute("Act") or pick(kind.acts)))
				m:SetAttribute("NpcYaw", yaw)
				local pr = Instance.new("ProximityPrompt")
				pr.Name = "StaffTalk"
				pr.ActionText = "말 걸기"
				pr.ObjectText = label
				pr.HoldDuration = 0
				pr.MaxActivationDistance = 9
				pr.RequiresLineOfSight = false
				pr.Parent = root
				pr.Triggered:Connect(function(player)
					onTalk(s, player)
				end)
				table.insert(sites, s)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Tick: streaming (nearest first) + life
-------------------------------------------------------------------------------------------------
local function playerSpots(): { Vector3 }
	local out = {}
	for _, pl in Players:GetPlayers() do
		local c = pl.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r then
			table.insert(out, (r :: BasePart).Position)
		end
	end
	return out
end

local function tick()
	if not scanned then
		return
	end
	local pps = playerSpots()
	local t = now()
	local want = {}
	for _, s in sites do
		local d = math.huge
		local nearP: Vector3? = nil
		for _, p in pps do
			local dd = flat(p, s.pos)
			if dd < d then
				d, nearP = dd, p
			end
		end
		s.dist = d
		if s.static then
			-- adopted clerks stay; only their life runs
		elseif s.model and d > OFF_R then
			dropRig(s)
		elseif not s.model and d < ON_R then
			table.insert(want, s)
		end
		-- life
		if s.model and d < 60 then
			if nearP and d < GREET_R and math.abs(nearP.Y - s.pos.Y) < 8 and t >= s.greetAt then
				s.greetAt = t + 60
				faceTo(s, nearP)
				say(s, pick(linesOf(s).greet), 3)
				s.nextAct = t + 5
			elseif t >= s.nextAct then
				s.nextAct = t + rng:NextNumber(20, 40)
				faceTo(s, nil)
				setAct(s, pick(s.kind.acts))
			end
		end
	end
	table.sort(want, function(a, b)
		return a.dist < b.dist
	end)
	for _, s in want do
		if active >= MAX_ACTIVE then
			-- full: a nearer counter takes the place of the farthest live one
			local far = nil
			for _, o in sites do
				if o.model and not o.static and (not far or o.dist > far.dist) then
					far = o
				end
			end
			if far and far.dist > s.dist + 20 then
				dropRig(far)
			else
				break
			end
		end
		buildRig(s)
	end
end

function ShopStaff.sites(): { any }
	return sites
end

function ShopStaff.active(): number
	return active
end

function ShopStaff.status(): any
	local byKind = {}
	for _, s in sites do
		byKind[s.kind.k] = (byKind[s.kind.k] or 0) + 1
	end
	return { sites = #sites, active = active, byKind = byKind, scanned = scanned }
end

function ShopStaff.init(context: any)
	ctx = context
	local m = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		Looks = if ok then res else nil
	end
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	npcFolder = f
	ctx.shopStaff = ShopStaff
	task.spawn(function()
		-- after the key NPCs (NPC.onDest) and the venues are placed
		task.wait(6)
		local ok, err = pcall(function()
			adoptClerks()
			scan()
		end)
		if not ok then
			warn("[GwangalliShopStaff] scan failed: " .. tostring(err))
			scanned = true
		end
		while true do
			local ok2, err2 = pcall(tick)
			if not ok2 then
				warn("[GwangalliShopStaff] tick: " .. tostring(err2))
			end
			task.wait(1.5)
		end
	end)
end

return ShopStaff
