--!nocheck
-- GwangalliGameplay/WorkStore: the CONVENIENCE STORE station system (GS25 광안리점, job gs25, track cvs)
-- of the 알바 simulation. Driven by Work.luau (shift, pay, client state) like WorkCafe; the customers
-- are WorkCustomers' NPCs (this module gives them the path, the basket and the counter).
--
--   출근: 계산대 옆 근태 단말기 → 조끼 유니폼 (Work) → 계산대:
--     손님이 매대에서 고른 상품을 카운터에 올림 (진열대 재고가 실제로 줄어듦) → 상품마다 스캔 (가끔
--     바코드 인식 실패 → 수동 입력: 가격 고르기) → 술·담배는 신분증 확인 (미성년자 → 판매 거절) →
--     봉투 여쭤보기 (유상 50원) → 결제 (카드 꽂기 / 현금 받고 거스름돈 고르기: 금고 시재가 실제로 맞고
--     틀림) → 봉투 포장 → 물건·영수증 드리기 → 다음 손님
--   업무: 창고에서 카테고리 박스 → 진열대 채우기 (손님이 고를수록 줄어듦) · 쓰레기통 (계산마다 차오름
--     → 봉투 빼서 창고 분리수거함) · 바닥 (손님이 흘림 / 비 오는 날 젖은 발자국 → 창고 대걸레) ·
--     택배 접수 Lv2 (저울 → 요금 → 운송장 → 보관, 20kg 초과 거절) · 담배 Lv2 (번호 선반) ·
--     진상 환불 Lv3 (영수증 확인 → 환불 / 규정 안내) · 재고 발주 Lv3 (창고 박스가 유한해짐 → POS 발주,
--     40초 뒤 입고) · 마감 시재 정산 Lv4 (금고 세기) · 신입 교육 Lv5 (후배 질문)
--   랜덤 상황: POS 먹통 (재부팅 순서) · 정전 (창고 차단기 → 재부팅) · 취객 소동 · 진상 환불 · 단체 학생 ·
--     유통기한 지난 상품 · 흘린 음료
--
-- Positions: the GS25 build's GwJobStation anchors (Job = "gs25": counter, counter_items,
-- counter_scanned, queue1..3, door_in / door_out, front, browse1..4 (+ Path), backroom, chiller,
-- slot_food / slot_snack / slot_drink / slot_life); FALLBACK = the same points as offsets in the
-- "GS25 광안리점" Destination frame (measured from the current build) when an anchor is missing.
-- Money: every sale is the store's; the worker earns per sale (WS.cvsPerf) + tasks, mistakes only cut
-- the performance part (W.penalty).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CVS = {}
CVS.kind = "cvs"
CVS.unitPerOrder = true

local C: any
local WS: any
local Props: any
local Orders: any
local W: any
local Lines: any = nil
local rng = Random.new()

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

function CVS.init(cfg: any, ws: any, props: any, orders: any, work: any)
	C = cfg
	WS = ws
	Props = props
	Orders = orders
	W = work
	local lm = ReplicatedStorage:FindFirstChild("GwangalliWorkLines")
	if lm then
		local ok, res = pcall(require, lm)
		if ok then
			Lines = res
		end
	end
end

local function customers(): any
	return W.customers()
end

-------------------------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------------------------
-- Destination-frame offsets of the anchors (lx, ly, lz); ly relative to the Destination part
local FALLBACK = {
	counter = { -2.4, 0.4, -24.0 },
	counter_items = { -2.3, 4.0, -20.9 },
	counter_scanned = { 0.6, 4.0, -20.9 },
	queue1 = { -2.7, 0.4, -17.8 },
	queue2 = { -2.8, 0.4, -14.8 },
	queue3 = { -2.2, 0.4, -11.9 },
	door_out = { -0.1, 0.4, 5.3 },
	door_in = { 0.1, 0.4, -6.7 },
	front = { 2.7, 0.4, -14.4 },
	aisle1 = { 14.0, 0.4, -14.2 },
	aisle2 = { 22.5, 0.4, -14.1 },
	aisle3 = { 32.7, 0.4, -13.9 },
	b3mid = { 14.6, 0.4, -50.4 },
	browse1 = { 14.3, 0.4, -32.4 },
	browse2 = { 22.7, 0.4, -26.3 },
	browse3 = { 18.4, 0.4, -51.0 },
	browse4 = { 33.1, 0.4, -32.1 },
	backroom = { 10.8, 0.4, -65.7 },
	chiller = { 0.6, 0.4, -41.7 },
	slot_food = { 10.4, 1.1, -48.7 },
	slot_snack = { 18.9, 1.1, -48.5 },
	slot_drink = { 26.8, 1.1, -16.0 },
	slot_life = { 27.4, 1.1, -48.3 },
}
local BROWSE_PATH = { browse1 = { "front", "aisle1" }, browse2 = { "front", "aisle1", "aisle2" }, browse3 = { "front", "aisle1", "b3mid" }, browse4 = { "front", "aisle1", "aisle2", "aisle3" } }
local BROWSE_CAT = { browse1 = "food", browse2 = "snack", browse3 = "snack", browse4 = "life" }

local function anchors(): { [string]: BasePart }
	local out = {}
	for _, inst in CollectionService:GetTagged("GwJobStation") do
		if inst:IsA("BasePart") and inst:GetAttribute("Job") == "gs25" and type(inst:GetAttribute("Station")) == "string" then
			out[inst:GetAttribute("Station")] = inst
		end
	end
	return out
end

-- the CFrame of an anchor (its centre) or the fallback offset
local function acf(store: any, id: string): CFrame
	local a = store.anchors[id]
	if a and a.Parent then
		return a.CFrame
	end
	local f = FALLBACK[id] or { 0, 0.4, 0 }
	return store.cf * CFrame.new(f[1], f[2], f[3])
end

-- feet position (anchors are 1-stud cubes 0.5 above the floor)
local function feet(store: any, id: string): Vector3
	return acf(store, id).Position - Vector3.new(0, 0.5, 0)
end

local function catDef(id: string): any
	for _, c in C.CVS.categories do
		if c.id == id then
			return c
		end
	end
	return C.CVS.categories[1]
end

local function productsOf(cat: string, adultOk: boolean): { any }
	local out = {}
	for _, p in C.CVS.products do
		if p.cat == cat and (adultOk or not p.adult) then
			table.insert(out, p)
		end
	end
	return out
end

local function wonS(n: number): string
	return WS.won(n)
end

-------------------------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------------------------
local function unlocked(store: any, duty: string): boolean
	return WS.unlocked("cvs", duty, store.level or 1)
end

local function addStationDef(store: any, id: string, label: string, pos: Vector3, extra: any?)
	local s = { id = id, label = label, pos = pos }
	if extra then
		for k, v in extra do
			s[k] = v
		end
	end
	table.insert(store.stationList, s)
	return s
end

local function shelfLabel(store: any, cat: string): string
	local def = catDef(cat)
	return string.format("%s %d/%d", def.label, store.shelf[cat] or 0, C.CVS.shelfCapacity)
end

local function refreshVisuals(store: any)
	local v = store.visual
	if not v then
		return
	end
	-- shelf rows: one small box per unit
	for cat, row in v.shelfRows or {} do
		local n = store.shelf[cat] or 0
		for i, p in row do
			p.Transparency = if i <= n then 0 else 1
		end
		if v.shelfLabels[cat] then
			local low = n <= C.CVS.shelfCapacity * 0.3
			v.shelfLabels[cat].Text = shelfLabel(store, cat) .. (if low then " ⚠️" else "")
			v.shelfLabels[cat].TextColor3 = if n == 0 then Color3.fromRGB(255, 110, 100) elseif low then Color3.fromRGB(255, 210, 90) else Color3.fromRGB(235, 240, 248)
		end
	end
	-- backroom boxes
	if v.backroomBoxes then
		local i = 0
		for _, c in C.CVS.categories do
			local n = math.min(4, if store.backroom[c.id] == math.huge then 3 else store.backroom[c.id] or 0)
			for k = 1, 4 do
				i += 1
				local b = v.backroomBoxes[i]
				if b then
					b.Transparency = if k <= n then 0 else 1
				end
			end
		end
		local parts = {}
		for _, c in C.CVS.categories do
			local n = store.backroom[c.id]
			table.insert(parts, string.format("%s %s", c.label, if n == math.huge then "∞" else tostring(n)))
		end
		v.backroomLabel.Text = "창고 박스 · " .. table.concat(parts, " · ")
	end
	if v.binFill then
		local f = math.clamp(store.trash / C.CVS.trashMax, 0, 1)
		local h = math.max(0.05, 2.0 * f)
		v.binFill.Size = Vector3.new(1.3, h, 1.3)
		v.binFill.CFrame = CFrame.new(v.binBase + Vector3.new(0, 0.1 + h / 2, 0))
		v.binFill.Transparency = if store.trash <= 0 then 1 else 0
		v.binLabel.Text = string.format("쓰레기 %d/%d%s", store.trash, C.CVS.trashMax, if store.trash >= C.CVS.trashMax then " · 꽉 참!" elseif store.trashBag then " · 봉투 없음" else "")
	end
	if v.posScreen then
		local text, col = "OPEN", Color3.fromRGB(110, 240, 160)
		local ev = store.event
		if not store.open then
			text, col = "CLOSED", Color3.fromRGB(150, 150, 160)
		elseif ev and (ev.kind == "pos" or ev.kind == "power") then
			text, col = if ev.kind == "power" then "⚡ 전원 없음" else "⚠️ ERROR 0x3F\n응답 없음", Color3.fromRGB(255, 110, 100)
		elseif store.counterTx then
			local tx = store.tx[store.counterTx]
			if tx then
				text = string.format("%s\n합계 %s", tx.typeLabel or "계산", wonS(tx.total or 0))
				col = Color3.fromRGB(255, 220, 120)
			end
		end
		v.posScreen.Text = text
		v.posScreen.TextColor3 = col
	end
	if v.scaleScreen then
		local tx = store.counterTx and store.tx[store.counterTx]
		v.scaleScreen.Text = if tx and tx.type == "parcel" and tx.weighed then string.format("%.1f kg", tx.kg) else "0.0 kg"
	end
	if v.breakerLight then
		local ev = store.event
		v.breakerLight.Color = if ev and ev.kind == "power" and not ev.breakerUp then Color3.fromRGB(240, 60, 50) else Color3.fromRGB(60, 220, 110)
	end
end
CVS.refreshVisuals = refreshVisuals

local function buildEquipment(store: any)
	local f = store.folder
	store.visual = { shelfRows = {}, shelfLabels = {} }
	local v = store.visual
	local dark, steel = Color3.fromRGB(40, 42, 46), Color3.fromRGB(150, 156, 162)
	local counterCF = acf(store, "counter")
	local itemsCF = acf(store, "counter_items")
	-- POS display (customer side readable), card terminal
	do
		local disp = Props.part(f, "CvsPosDisplay", Vector3.new(1.3, 0.85, 0.06), itemsCF * CFrame.new(1.7, 0.4, 1.2) * CFrame.Angles(0, math.rad(180), 0) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(14, 20, 30), { material = Enum.Material.Neon })
		v.posScreen = Props.screen(disp, "CLOSED", { face = Enum.NormalId.Front, color = Color3.fromRGB(150, 150, 160) })
		local back = Props.screen(disp, "", { face = Enum.NormalId.Back })
		local _ = back
		v.posPart = disp
		Props.label(disp, "POS 계산대", { name = "StationLabel", size = UDim2.fromOffset(110, 20), offset = Vector3.new(0, 1.0, 0), maxDistance = 18, bgTransparency = 0.35 })
		Props.part(f, "CvsCardReader", Vector3.new(0.35, 0.12, 0.55), itemsCF * CFrame.new(1.2, -0.42, -0.6), dark)
	end
	-- scale (택배)
	do
		local sc = Props.part(f, "CvsScale", Vector3.new(1.0, 0.12, 1.0), itemsCF * CFrame.new(-3.4, -0.44, 0), steel, { material = Enum.Material.Metal })
		local face = Props.part(f, "CvsScaleFace", Vector3.new(0.6, 0.3, 0.05), itemsCF * CFrame.new(-3.4, -0.25, 0.55), Color3.fromRGB(20, 30, 40), { material = Enum.Material.Neon })
		v.scaleScreen = Props.screen(face, "0.0 kg", { face = Enum.NormalId.Back, color = Color3.fromRGB(120, 240, 160), ppu = 80 })
		local _ = sc
	end
	-- cigarette rack behind the worker
	do
		local rack = Props.part(f, "CvsCigRack", Vector3.new(3.6, 1.6, 0.3), counterCF * CFrame.new(0, 2.8, 1.7), Color3.fromRGB(30, 30, 34))
		local lines = {}
		for _, cg in C.CVS.cigarettes do
			table.insert(lines, string.format("%d %s", cg.n, cg.name))
		end
		Props.screen(rack, table.concat(lines, "   "), { face = Enum.NormalId.Front, color = Color3.fromRGB(255, 230, 160), ppu = 40 })
	end
	-- shelf rows (one box per unit) + labels
	for _, c in C.CVS.categories do
		local cf = acf(store, c.shelf)
		local row = {}
		for i = 1, C.CVS.shelfCapacity do
			local x = (i - 5.5) * 0.42
			local p = Props.part(f, "CvsShelfItem_" .. c.id, Vector3.new(0.34, 0.5, 0.3), cf * CFrame.new(x, 0.15, -0.4), Props.rgb(c.color), { material = Enum.Material.SmoothPlastic })
			table.insert(row, p)
		end
		v.shelfRows[c.id] = row
		v.shelfLabels[c.id] = Props.label(row[5], shelfLabel(store, c.id), { name = "ShelfLabel", size = UDim2.fromOffset(120, 22), offset = Vector3.new(0, 1.6, 0), maxDistance = 30, bgTransparency = 0.3 })
	end
	-- backroom: box stacks per category, dumpster, mop bucket, breaker
	do
		local cf = acf(store, "backroom")
		v.backroomBoxes = {}
		local i = 0
		for ci, c in C.CVS.categories do
			for k = 1, 4 do
				i += 1
				local b = Props.part(f, "CvsStockBox", Vector3.new(1.2, 0.8, 1.0), cf * CFrame.new(-2.4 + (ci - 1) * 1.4, -0.1 + (k - 1) * 0.82, 2.0), Props.rgb(c.color):Lerp(Color3.fromRGB(196, 160, 110), 0.6), { material = Enum.Material.Cardboard })
				table.insert(v.backroomBoxes, b)
			end
		end
		v.backroomLabel = Props.label(v.backroomBoxes[2], "", { name = "BackroomLabel", size = UDim2.fromOffset(230, 22), offset = Vector3.new(1, 3.6, 0), maxDistance = 30, bgTransparency = 0.3 })
		local dump = Props.part(f, "CvsDumpster", Vector3.new(2.2, 1.8, 1.4), cf * CFrame.new(3.2, 0.4, 1.6), Color3.fromRGB(40, 120, 70))
		Props.label(dump, "분리수거함", { name = "StationLabel", size = UDim2.fromOffset(100, 20), offset = Vector3.new(0, 1.6, 0), maxDistance = 20, bgTransparency = 0.35 })
		local bucket = Props.cylinder(f, "CvsMopBucket", 0.8, 0.9, cf.Position + cf:VectorToWorldSpace(Vector3.new(-3.6, -0.1, -1.2)), Color3.fromRGB(240, 200, 40))
		Props.part(f, "CvsMopStick", Vector3.new(0.12, 3.6, 0.12), CFrame.new(bucket.Position + Vector3.new(0.1, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(8)), Color3.fromRGB(200, 200, 205))
		local brk = Props.part(f, "CvsBreaker", Vector3.new(0.9, 1.2, 0.2), cf * CFrame.new(0.2, 1.6, 3.0), Color3.fromRGB(170, 172, 178), { material = Enum.Material.Metal })
		v.breakerLight = Props.part(f, "CvsBreakerLight", Vector3.new(0.18, 0.18, 0.18), brk.CFrame * CFrame.new(0.25, 0.4, -0.12), Color3.fromRGB(60, 220, 110), { material = Enum.Material.Neon, shape = Enum.PartType.Ball })
		Props.label(brk, "두꺼비집 (차단기)", { name = "StationLabel", size = UDim2.fromOffset(110, 18), offset = Vector3.new(0, 1.1, 0), maxDistance = 16, bgTransparency = 0.35 })
	end
	-- trash bin by the door (inside)
	do
		local p = store.binPos
		v.binBase = p
		Props.cylinder(f, "CvsBin", 2.2, 1.5, p + Vector3.new(0, 1.1, 0), Color3.fromRGB(70, 74, 80), { transparency = 0.25 })
		v.binFill = Props.part(f, "CvsBinFill", Vector3.new(1.3, 0.1, 1.3), CFrame.new(p + Vector3.new(0, 0.15, 0)), Color3.fromRGB(120, 100, 80))
		local rim = Props.cylinder(f, "CvsBinRim", 0.08, 1.55, p + Vector3.new(0, 2.22, 0), dark)
		v.binLabel = Props.label(rim, "", { name = "BinLabel", size = UDim2.fromOffset(150, 20), offset = Vector3.new(0, 0.9, 0), maxDistance = 25, bgTransparency = 0.3 })
	end
	-- time clock (근태 단말기) beside the counter
	do
		local p = store.clockPos
		local rot = counterCF - counterCF.Position
		Props.part(f, "CvsTimeClockStand", Vector3.new(0.3, 3.4, 0.3), CFrame.new(p + Vector3.new(0, 1.7, 0)) * rot, Color3.fromRGB(58, 62, 70), { material = Enum.Material.Metal })
		local head = Props.part(f, "CvsTimeClock", Vector3.new(1.2, 0.9, 0.3), CFrame.new(p + Vector3.new(0, 3.8, 0)) * rot, Color3.fromRGB(28, 118, 214))
		Props.screen(head, "GS25\n근태 등록", { face = Enum.NormalId.Front })
		Props.label(head, "STAFF · 출퇴근", { name = "StaffSign", size = UDim2.fromOffset(110, 20), offset = Vector3.new(0, 1.0, 0), maxDistance = 30, bg = Color3.fromRGB(28, 118, 214) })
	end
end

function CVS.build(store: any)
	store.anchors = anchors()
	store.shelf = {}
	store.backroom = {}
	store.trash = 0
	store.trashBag = false -- the bag was taken out of the bin (a new one must go in → the bin is "봉투 없음")
	store.puddles = {}
	store.tx = {}
	store.counterTx = nil
	store.event = nil
	store.pending = {}
	store.close = {}
	store.till = C.CVS.tillStart
	store.tillBook = C.CVS.tillStart
	for _, c in C.CVS.categories do
		store.shelf[c.id] = C.CVS.shelfStart
		store.backroom[c.id] = math.huge
	end
	-- positions
	local counterCF = acf(store, "counter")
	store.counterPos = counterCF.Position - Vector3.new(0, 0.5, 0)
	store.clockPos = (counterCF * CFrame.new(-2.8, -0.5, 0.6)).Position
	local doorIn = feet(store, "door_in")
	local front = feet(store, "front")
	-- inside the door, beside the walkway (Destination frame: -x of the door line)
	store.binPos = doorIn + (front - doorIn) * 0.35 + store.cf.RightVector * 4.5
	store.stationList = {}
	addStationDef(store, "timeclock", "근태 단말기", store.clockPos)
	addStationDef(store, "counter", "계산대 (POS)", store.counterPos, { reach = 7 })
	local back = feet(store, "backroom")
	addStationDef(store, "backroom", "창고 (박스 · 대걸레)", back)
	addStationDef(store, "dumpster", "분리수거함", back + acf(store, "backroom"):VectorToWorldSpace(Vector3.new(3.2, 0, 1.6)), { reach = 6 })
	addStationDef(store, "breaker", "차단기", back + acf(store, "backroom"):VectorToWorldSpace(Vector3.new(0.2, 0, 3.0)), { reach = 5 })
	addStationDef(store, "chiller", "냉장 쇼케이스", feet(store, "chiller"))
	addStationDef(store, "bin", "쓰레기통", store.binPos, { reach = 6 })
	addStationDef(store, "floor", "매장 바닥", front, { reach = 6 })
	for _, c in C.CVS.categories do
		addStationDef(store, "shelf_" .. c.id, c.label .. " 진열대", acf(store, c.shelf).Position - Vector3.new(0, 1.2, 0), { reach = 7 })
	end
	buildEquipment(store)
	refreshVisuals(store)
end

function CVS.refreshLights(store: any)
	refreshVisuals(store)
end

-------------------------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------------------------
function CVS.activate(store: any)
	store.open = true
	for _, c in C.CVS.categories do
		store.shelf[c.id] = C.CVS.shelfStart
		store.backroom[c.id] = if unlocked(store, "reorder") then C.CVS.backroomBoxes else math.huge
	end
	store.close = {}
	for _, id in C.CVS.closeTasks do
		local need = C.CVS.closeTasksByLevel[id]
		if not need or (store.level or 1) >= need then
			store.close[id] = false
		end
	end
	store.trash = 2
	store.till = C.CVS.tillStart
	store.tillBook = C.CVS.tillStart
	store.nextEvent = os.clock() + rng:NextNumber(40, 60)
	store.event = nil
	store.drunk = nil
	refreshVisuals(store)
end

local function clearTx(store: any, oid: string)
	local tx = store.tx[oid]
	if not tx then
		return
	end
	for _, m in tx.models or {} do
		local item = store.items[m]
		if item then
			W.destroyItem(store, item)
		end
	end
	store.tx[oid] = nil
	if store.counterTx == oid then
		store.counterTx = nil
	end
end

function CVS.deactivate(store: any)
	store.open = false
	for oid in table.clone(store.tx) do
		clearTx(store, oid)
	end
	for _, item in store.items do
		W.destroyItem(store, item)
	end
	for _, p in store.puddles do
		if p.part then
			p.part:Destroy()
		end
		W.removeStation(store, "puddle:" .. p.id)
	end
	store.puddles = {}
	if store.drunk then
		W.removeStation(store, "drunk:" .. store.drunk.cid)
		store.drunk = nil
	end
	store.event = nil
	store.pending = {}
	refreshVisuals(store)
end

function CVS.releasePlayer(store: any, player: Player, _sess: any)
	for _, tx in store.tx do
		if tx.worker == player then
			tx.worker = nil
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Customers (WorkCustomers hooks)
-------------------------------------------------------------------------------------------------
function CVS.site(store: any): any
	local browse = {}
	for id, path in BROWSE_PATH do
		local pts = {}
		for _, pid in path do
			table.insert(pts, feet(store, pid))
		end
		local a = acf(store, id)
		table.insert(browse, { pos = a.Position - Vector3.new(0, 0.5, 0), path = pts, face = a.LookVector, cat = BROWSE_CAT[id], id = id })
	end
	table.sort(browse, function(a, b)
		return a.id < b.id
	end)
	return {
		kind = "cvs",
		door_out = feet(store, "door_out"),
		door_in = feet(store, "door_in"),
		browse = browse,
		queue = { feet(store, "queue1"), feet(store, "queue2"), feet(store, "queue3") },
		face = acf(store, "queue1").LookVector,
		exitVia = {},
		orderAtCounter = true,
	}
end

function CVS.customerPurpose(store: any, cust: any, _r: any): string?
	if cust.purpose then
		return cust.purpose
	end
	if cust.persona == "karen" and unlocked(store, "refund") and rng:NextNumber() < 0.5 then
		return "refund"
	end
	if (cust.persona == "normal" or cust.persona == "regular") and unlocked(store, "parcel") and rng:NextNumber() < 0.14 then
		return "parcel"
	end
	return nil
end

local function raining(): boolean
	return ReplicatedStorage:GetAttribute("GwWeather") == "rain"
end

-- the basket: picked from the shelves (stock goes down for real)
function CVS.customerBrowse(store: any, cust: any, _r: any)
	if cust.purpose or cust.leader then
		return
	end
	cust.items = cust.items or {}
	local want = ({ hurry = 1, drunk = 2, student = 3, regular = 2, karen = 2, normal = 2 })[cust.persona] or 2
	want = math.max(1, want + rand(3) - 2)
	local cats = { "food", "snack", "drink", "life" }
	if cust.persona == "student" then
		cats = { "snack", "snack", "drink", "food" }
	elseif cust.persona == "drunk" then
		cats = { "drink", "drink", "life", "food" }
	end
	local missed = nil
	for _ = 1, want do
		local cat = cats[rand(#cats)]
		if raining() and rng:NextNumber() < 0.3 then
			cat = "life"
		end
		local list = productsOf(cat, true)
		local pick = list[rand(#list)]
		if cust.persona == "drunk" and rng:NextNumber() < 0.6 then
			pick = WS.product(if rng:NextNumber() < 0.5 then "beer" elseif rng:NextNumber() < 0.5 then "soju" else "hangover") or pick
		elseif cust.persona == "student" and pick.adult and rng:NextNumber() < 0.6 then
			pick = WS.product("cola") or pick
		elseif pick.adult and cust.persona ~= "student" and rng:NextNumber() < 0.5 then
			pick = WS.product("water") or pick
		elseif raining() and cat == "life" and rng:NextNumber() < 0.6 then
			pick = WS.product("umbrella") or pick
		end
		if (store.shelf[pick.cat] or 0) > 0 then
			store.shelf[pick.cat] -= 1
			table.insert(cust.items, pick.id)
		else
			missed = catDef(pick.cat).label
		end
	end
	if missed then
		customers().sayText(store.id, cust.id, string.format("아 %s 다 떨어졌네…", missed), 4)
		W.storeToast(store, string.format("📉 %s 진열대가 비었어요 · 손님이 못 샀어요", missed), "warn")
	end
	refreshVisuals(store)
	W.dirty(store)
end

-- the order the customer places at the counter -> specs, info
function CVS.customerOrder(store: any, cust: any, _r: any): (any?, any?)
	if cust.purpose == "parcel" then
		local kg = math.floor(rng:NextNumber(0.4, 18) * 10 + 0.5) / 10
		if rng:NextNumber() < 0.18 then
			kg = math.floor(rng:NextNumber(20.6, 27) * 10 + 0.5) / 10
		end
		local dest = C.CVS.parcelDests[rand(#C.CVS.parcelDests)]
		return { { parcel = true, kg = kg, dest = dest } }, { noRemake = true, meta = { type = "parcel" }, group = false }
	elseif cust.purpose == "refund" then
		local list = C.CVS.products
		local p = list[rand(#list)]
		while p.adult do
			p = list[rand(#list)]
		end
		local receipt = rng:NextNumber() < 0.55
		local opened = rng:NextNumber() < 0.4
		return { { refund = p.id, receipt = receipt, opened = opened } }, { noRemake = true, meta = { type = "refund" }, group = false }
	end
	local specs = {}
	for _, pid in cust.items or {} do
		table.insert(specs, { pid = pid })
	end
	-- 담배 (Lv2): an adult asks for a pack by number
	if unlocked(store, "cigarettes") and (cust.persona == "normal" or cust.persona == "drunk" or cust.persona == "hurry") and rng:NextNumber() < 0.22 then
		local cg = C.CVS.cigarettes[rand(#C.CVS.cigarettes)]
		table.insert(specs, { cig = cg.n })
	end
	if #specs == 0 then
		-- nothing left on the shelves they wanted: grab something from any shelf with stock
		for _, c in C.CVS.categories do
			if (store.shelf[c.id] or 0) > 0 then
				local list = productsOf(c.id, false)
				local p = list[rand(#list)]
				store.shelf[c.id] -= 1
				table.insert(specs, { pid = p.id })
				refreshVisuals(store)
				break
			end
		end
	end
	if #specs == 0 then
		return {}, nil
	end
	return specs, { noRemake = true, meta = { type = "sale" }, group = #(cust.followers or {}) > 0 }
end

function CVS.genOrder(store: any, _r: any, _level: number, _group: boolean, cust: any?): { any }
	-- test-customer fallback (no NPC provider): a random basket straight from the shelves
	local specs = {}
	for _ = 1, 1 + rand(3) do
		local c = C.CVS.categories[rand(#C.CVS.categories)]
		if (store.shelf[c.id] or 0) > 0 then
			local list = productsOf(c.id, false)
			store.shelf[c.id] -= 1
			table.insert(specs, { pid = list[rand(#list)].id })
		end
	end
	if #specs == 0 then
		table.insert(specs, { pid = "gum" })
	end
	refreshVisuals(store)
	local _ = cust
	return specs
end

function CVS.validSpec(spec: any): boolean
	if type(spec) ~= "table" then
		return false
	end
	if spec.pid then
		return WS.product(spec.pid) ~= nil
	end
	if spec.cig then
		return type(spec.cig) == "number"
	end
	if spec.parcel then
		return type(spec.kg) == "number"
	end
	if spec.refund then
		return WS.product(spec.refund) ~= nil
	end
	return false
end

function CVS.orderLine(store: any, o: any, cust: any): string?
	local t = o.meta and o.meta.type
	local mem = store.lineMemo or {}
	store.lineMemo = mem
	if t == "parcel" then
		local sp = o.items[1].spec
		return string.format("택배 보내려고요! %s로요 (상자 하나)", sp.dest)
	elseif t == "refund" then
		return Lines and Lines.pick(mem, cust.persona, "refund", rand) or "환불해 주세요"
	end
	local line = Lines and Lines.pick(mem, cust.persona, "counter", rand) or "계산해 주세요"
	for _, it in o.items do
		if it.spec.cig then
			line ..= string.format(" 아, 그리고 담배 %d번 하나요", it.spec.cig)
		end
	end
	return line
end

-- events from WorkCustomers (a drunk wandering → may start trouble)
function CVS.customerEvent(store: any, cust: any, kind: string)
	if kind == "wander" and cust.persona == "drunk" and not store.drunk and store.open and (cust.forceWander or rng:NextNumber() < 0.6) then
		store.drunk = { cid = cust.id, since = os.clock(), water = false }
		customers().hold(store.id, cust.id, true)
		customers().say(store.id, cust.id, "trouble")
		W.addStation(store, { id = "drunk:" .. cust.id, label = "🥴 취객 손님", pos = cust.pos, reach = 7 })
		W.storeToast(store, "🥴 취객이 매장에서 소란을 피워요 · 가서 응대하세요", "warn")
	elseif kind == "leave" and store.drunk and store.drunk.cid == cust.id then
		W.removeStation(store, "drunk:" .. cust.id)
		store.drunk = nil
	end
end

-------------------------------------------------------------------------------------------------
-- Transactions
-------------------------------------------------------------------------------------------------
local TYPE_LABEL = { sale = "계산", parcel = "택배 접수", refund = "환불 요청" }

local function productText(p: any): string
	return string.format("%s %s %s", p.icon, p.name, wonS(p.price))
end

local function counterSlot(store: any, i: number, scanned: boolean): CFrame
	local base = acf(store, if scanned then "counter_scanned" else "counter_items")
	local row = (i - 1) % 4
	local col = (i - 1) // 4
	return base * CFrame.new(-0.9 + row * 0.6, -0.5, -0.3 + col * 0.6)
end

local function txTotal(tx: any): number
	local t = 0
	for _, it in tx.items do
		if it.scanned then
			t += it.charged or 0
		end
	end
	if tx.bag == true then
		t += C.CVS.bagPrice
	end
	if tx.type == "parcel" and tx.fee then
		t = tx.fee
	end
	return t
end

-- the counter transaction for a new order (models on the counter, hidden customer facts)
function CVS.onOrder(store: any, o: any)
	local t = (o.meta and o.meta.type) or "sale"
	local cust = customers() and customers().get(store.id, o.customerId)
	local persona = cust and cust.persona or "normal"
	local tx: any = { orderId = o.id, type = t, typeLabel = TYPE_LABEL[t], items = {}, models = {}, acc = 1, notes = {}, persona = persona, startedAt = os.clock(), total = 0 }
	if t == "sale" then
		local young = persona == "student"
		for i, it in o.items do
			local sp = it.spec
			if sp.pid then
				local p = WS.product(sp.pid)
				local e = { pid = p.id, name = p.name, icon = p.icon, price = p.price, adult = p.adult == true, fail = rng:NextNumber() < C.CVS.barcodeFailChance, scanned = false }
				table.insert(tx.items, e)
				it.text = productText(p)
				local item = W.newItem(store, "product", { color = p.color, shape = p.shape, size3 = if p.shape == "bottle" then Vector3.new(0.3, 0.8, 0.3) elseif p.shape == "can" then Vector3.new(0.28, 0.5, 0.28) else Vector3.new(0.45, 0.35, 0.3), text = p.name })
				Props.create(item, store.folder, counterSlot(store, i, false))
				e.model = item.id
				table.insert(tx.models, item.id)
				if p.adult then
					tx.adult = true
				end
			elseif sp.cig then
				local cg = C.CVS.cigarettes[sp.cig]
				local e = { cig = sp.cig, name = cg and cg.name or "담배", icon = "🚬", price = C.CVS.cigarettePrice, adult = true, scanned = false, fetched = false }
				table.insert(tx.items, e)
				it.text = string.format("🚬 담배 %d번 (%s)", sp.cig, e.name)
				tx.adult = true
			end
		end
		-- hidden facts: age, bag preference, payment
		tx.young = young or (tx.adult and rng:NextNumber() < 0.15)
		tx.minor = tx.adult and young and rng:NextNumber() < C.CVS.minorChance
		local yearNow = tonumber(os.date("%Y")) or 2026
		if tx.minor then
			tx.birth = yearNow - rng:NextInteger(16, 18)
		elseif tx.young then
			tx.birth = yearNow - rng:NextInteger(19, 22)
		else
			tx.birth = yearNow - rng:NextInteger(23, 60)
		end
		tx.wantBag = rng:NextNumber() < C.CVS.bagChance
		tx.method = if rng:NextNumber() < C.CVS.cashChance then "cash" else "card"
	elseif t == "parcel" then
		local sp = o.items[1].spec
		tx.kg = sp.kg
		tx.dest = sp.dest
		o.items[1].text = string.format("📦 택배 상자 → %s", sp.dest)
		local item = W.newItem(store, "box", { text = "택배", color = { 196, 160, 110 }, boxSize = Vector3.new(1.4, 1.0, 1.1) })
		Props.create(item, store.folder, counterSlot(store, 2, false))
		tx.box = item.id
		table.insert(tx.models, item.id)
	elseif t == "refund" then
		local sp = o.items[1].spec
		local p = WS.product(sp.refund)
		tx.pid = p.id
		tx.price = p.price
		tx.receipt = sp.receipt
		tx.opened = sp.opened
		o.items[1].text = string.format("↩️ 환불: %s %s", p.icon, p.name)
		local item = W.newItem(store, "product", { color = p.color, shape = p.shape, size3 = Vector3.new(0.45, 0.35, 0.3) })
		Props.create(item, store.folder, counterSlot(store, 1, false))
		table.insert(tx.models, item.id)
	end
	store.tx[o.id] = tx
	if not store.counterTx then
		store.counterTx = o.id
	end
	refreshVisuals(store)
end

local function custSay(store: any, o: any, situation: string, vars: any?, dur: number?)
	local cm = customers()
	if cm then
		cm.say(store.id, o.customerId, situation, vars, dur)
	end
end

local function custText(store: any, o: any, text: string, dur: number?)
	local cm = customers()
	if cm then
		cm.sayText(store.id, o.customerId, text, dur)
	end
end

local function allScanned(tx: any): boolean
	for _, it in tx.items do
		if not it.scanned and not it.removed then
			return false
		end
	end
	return true
end

-- what is left to do for a sale -> step id
local function saleStep(tx: any): string
	if not allScanned(tx) then
		return "scan"
	end
	if tx.adult and tx.idDecision == nil then
		return "id"
	end
	if tx.bag == nil then
		return "bag"
	end
	if not tx.paid then
		return "pay"
	end
	if tx.bag and not tx.packed then
		return "pack"
	end
	return "hand"
end
CVS.saleStep = saleStep

local STEP_TEXT = { scan = "상품 스캔", id = "신분증 확인", bag = "봉투 여쭤보기", pay = "결제", change = "거스름돈", pack = "봉투 포장", hand = "물건 · 영수증 드리기" }

local function finishTx(store: any, player: Player, o: any, line: string?)
	local tx = store.tx[o.id]
	if not tx then
		return
	end
	tx.done = true
	o.worker = player
	o.meta = o.meta or {}
	o.meta.line = line
	for _, it in o.items do
		it.itemId = it.itemId or ("cvs:" .. o.id)
	end
	Orders.call(o)
	Orders.receive(o.id)
end

function CVS.judge(store: any, o: any)
	local tx = store.tx[o.id]
	local acc = tx and math.clamp(tx.acc, 0, 1) or 0
	for _, it in o.items do
		it.accuracy = acc
		it.exact = acc >= 0.999
	end
end

function CVS.perfOf(_spec: any, o: any): number
	local t = o.meta and o.meta.type
	if t == "parcel" then
		return 900
	elseif t == "refund" then
		return 800
	end
	return WS.cvsPerf(#o.items)
end

function CVS.onResolved(store: any, o: any, _result: any)
	clearTx(store, o.id)
	store.trash = math.min(C.CVS.trashMax, store.trash + 1)
	-- the next customer's transaction becomes the counter one
	for oid in store.tx do
		if not store.counterTx then
			store.counterTx = oid
		end
	end
	refreshVisuals(store)
end

function CVS.onCancelled(store: any, o: any)
	local tx = store.tx[o.id]
	if tx and tx.type == "sale" then
		-- the products go back on the shelves (the customer left them)
		for _, it in tx.items do
			if it.pid then
				local p = WS.product(it.pid)
				if p then
					store.shelf[p.cat] = math.min(C.CVS.shelfCapacity, (store.shelf[p.cat] or 0) + 1)
				end
			end
		end
	end
	clearTx(store, o.id)
	for oid in store.tx do
		if not store.counterTx then
			store.counterTx = oid
		end
	end
	refreshVisuals(store)
end

-------------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------------
local function addPuddle(store: any, pos: Vector3, label: string?)
	local id = "p" .. tostring(math.floor(os.clock() * 1000) % 1000000)
	local part = Props.part(store.folder, "CvsPuddle", Vector3.new(0.06, 2.6, 2.6), CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 190, 210), { shape = Enum.PartType.Cylinder, transparency = 0.35 })
	local sign = Props.part(store.folder, "CvsWetSign", Vector3.new(0.9, 1.4, 0.1), CFrame.new(pos + Vector3.new(1.4, 0.7, 0)), Color3.fromRGB(250, 210, 40))
	sign.Transparency = 1
	table.insert(store.puddles, { id = id, part = part, sign = sign })
	W.addStation(store, { id = "puddle:" .. id, label = label or "바닥에 흘린 자국", pos = pos, reach = 6 })
end

local EVENTS = {
	{ id = "pos", w = 3 },
	{ id = "puddle", w = 3 },
	{ id = "drunk", w = 2 },
	{ id = "rush", w = 2 },
	{ id = "expiry", w = 2 },
	{ id = "refund", w = 2, duty = "refund" },
	{ id = "power", w = 1, duty = "reorder" }, -- Lv3+
	{ id = "trainee", w = 3, duty = "trainee" },
}

local function startEvent(store: any, id: string)
	local cm = customers()
	if id == "pos" then
		store.event = { kind = "pos", label = "POS 먹통", step = 1, steps = C.CVS.posRebootSteps, since = os.clock() }
		W.storeToast(store, "⚠️ POS가 멈췄어요! 계산대에서 재부팅 순서대로 처리하세요", "warn")
	elseif id == "power" then
		store.event = { kind = "power", label = "순간 정전", step = 0, steps = { "창고 차단기 올리기", "POS 재부팅" }, since = os.clock(), breakerUp = false }
		W.storeToast(store, "⚡ 순간 정전! 창고 두꺼비집(차단기)부터 확인하세요", "warn")
	elseif id == "expiry" then
		store.event = { kind = "expiry", label = "유통기한 경과 상품", step = 1, steps = { "쇼케이스 확인", "폐기 등록", "상품 빼기" }, since = os.clock() }
		W.storeToast(store, "🗓️ 냉장 쇼케이스에 유통기한 지난 상품이 있어요", "info")
	elseif id == "trainee" then
		local quiz = Lines and Lines.traineeQuiz
		if not quiz then
			return
		end
		local q = quiz[rand(#quiz)]
		store.event = { kind = "trainee", label = "신입 교육", quiz = q, since = os.clock() }
		W.storeToast(store, "🧑‍🎓 신입 알바: \"" .. q.q .. "\" (계산대에서 알려 주기)", "info")
	elseif id == "puddle" then
		local fr = feet(store, if rng:NextNumber() < 0.5 then "aisle1" else "front")
		if raining() then
			fr = feet(store, "door_in") + Vector3.new(-2.5, 0, 0)
		end
		addPuddle(store, fr + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), if raining() then "젖은 발자국 (비)" else "흘린 음료")
		W.storeToast(store, if raining() then "🌧️ 입구 바닥이 젖었어요 · 미끄럼 주의! 대걸레로 닦기" else "💦 손님이 음료를 흘렸어요 · 대걸레로 닦기", "warn")
	elseif id == "drunk" and cm then
		cm.spawn(store, "drunk", { wander = true })
	elseif id == "rush" and cm then
		local c = cm.spawn(store, "student")
		if c then
			W.storeToast(store, "🎒 학생 손님들이 몰려와요!", "info")
		end
	elseif id == "refund" and cm then
		if cm.spawn(store, "karen", { purpose = "refund" }) then
			W.storeToast(store, "😤 표정이 안 좋은 손님이 들어와요…", "info")
		end
	end
	refreshVisuals(store)
	W.dirty(store)
end

-------------------------------------------------------------------------------------------------
-- Action list for a station
-------------------------------------------------------------------------------------------------
local function A(id: string, label: string, dur: number, enabled: boolean, reason: string?, icon: string?): any
	return { id = id, label = label, dur = dur, enabled = enabled, reason = reason, icon = icon }
end

local function heldItem(store: any, sess: any): any?
	local id = sess.held[1]
	return id and store.items[id] or nil
end

local function counterActions(store: any, sess: any, out: { any })
	local ev = store.event
	if ev and ev.kind == "pos" then
		for i, step in ev.steps do
			if i >= ev.step then
				local waiting = i == 2 and ev.bootUntil and os.clock() < ev.bootUntil
				table.insert(out, A("reboot:" .. i, (if i == ev.step then "▶ " else "") .. step .. (if waiting then string.format(" (%d초)", math.ceil(ev.bootUntil - os.clock())) else ""), if i == 1 then 1.6 else 0.6, not waiting, if waiting then "부팅 중…" else nil, "🖥️"))
			end
		end
		return
	end
	if ev and ev.kind == "power" then
		if ev.breakerUp then
			table.insert(out, A("reboot:power", "POS 재부팅 (전원 복구됨)", 1.2, true, nil, "🖥️"))
		else
			table.insert(out, A("none", "전원이 나갔어요 · 창고 차단기부터", 0, false, nil, "⚡"))
		end
		return
	end
	local oid = store.counterTx
	local tx = oid and store.tx[oid]
	local o = oid and Orders.get(oid)
	if not tx or not o or tx.done then
		-- idle counter: trainee / 발주 / 시재
		if ev and ev.kind == "trainee" then
			for i, ch in ev.quiz.choices do
				table.insert(out, A("train:" .. i, ch, 0.4, true, nil, "🧑‍🎓"))
			end
		end
		if unlocked(store, "reorder") and W.phaseOf(store) ~= "close" then
			for _, c in C.CVS.categories do
				local n = store.backroom[c.id]
				local pending = 0
				for _, pz in store.pending do
					if pz.cat == c.id then
						pending += pz.n
					end
				end
				if n ~= math.huge and n <= 1 then
					table.insert(out, A("reorder:" .. c.id, string.format("발주: %s 박스 2개 (창고 %d%s)", c.label, n, if pending > 0 then string.format(" · 입고 대기 %d", pending) else ""), 0.8, pending == 0, if pending > 0 then "이미 발주했어요" else nil, "📋"))
				end
			end
		end
		if store.close.count_till == false and W.phaseOf(store) == "close" then
			if not store.tillCount then
				table.insert(out, A("till_count", "마감 시재 정산 (금고 세기)", 1.6, true, nil, "💴"))
			else
				for i, v in store.tillCount.options do
					table.insert(out, A("till:" .. i, string.format("금고 합계 %s", wonS(v)), 0.5, true, nil, "💴"))
				end
			end
		end
		if #out == 0 then
			table.insert(out, A("none", "계산할 손님이 없어요", 0, false, nil, "🧾"))
		end
		return
	end
	if tx.type == "sale" then
		local step = saleStep(tx)
		if step == "scan" then
			local n = 0
			for i, it in tx.items do
				if not it.scanned and not it.removed and n < 4 then
					n += 1
					if it.cig then
						if not it.fetched then
							-- pick the pack from the rack by number: 3 choices (fixed per item)
							if not it.opts then
								local opts = { it.cig }
								while #opts < 3 do
									local k = rand(#C.CVS.cigarettes)
									if not table.find(opts, k) then
										table.insert(opts, k)
									end
								end
								table.sort(opts)
								it.opts = opts
							end
							for _, k in it.opts do
								local cg = C.CVS.cigarettes[k]
								table.insert(out, A(string.format("cig:%d:%d", i, k), string.format("담배 %d번 %s 꺼내기", k, cg.name), 0.5, true, nil, "🚬"))
							end
						end
					elseif it.failed and not it.manual then
						if not it.opts then
							local p = WS.product(it.pid)
							local opts = { p.price }
							for _, d in { 300, -200, 500, -500, 1000 } do
								if #opts >= 3 then
									break
								end
								local v = p.price + d
								if v > 0 and not table.find(opts, v) and rng:NextNumber() < 0.7 then
									table.insert(opts, v)
								end
							end
							while #opts < 3 do
								table.insert(opts, p.price + 700 * #opts)
							end
							table.sort(opts)
							it.opts = opts
						end
						for _, v in it.opts do
							table.insert(out, A(string.format("manual:%d:%d", i, v), string.format("수동 입력 %s %s", it.name, wonS(v)), 0.5, true, nil, "⌨️"))
						end
					else
						table.insert(out, A("scan:" .. i, string.format("%s %s 스캔", it.icon, it.name), 0.35, true, nil, "📟"))
					end
				end
			end
		elseif step == "id" then
			if not tx.idShown then
				table.insert(out, A("id_ask", "신분증 보여 주시겠어요?", 0.6, true, nil, "🪪"))
				table.insert(out, A("id_skip", "확인 없이 판매", 0.3, true, nil, "⏩"))
			else
				table.insert(out, A("id_ok", string.format("성인 확인 · 판매 (%d년생)", tx.birth), 0.4, true, nil, "✅"))
				table.insert(out, A("id_refuse", "판매 거절 (술·담배 빼기)", 0.6, true, nil, "🚫"))
			end
		elseif step == "bag" then
			if not tx.bagAsked then
				table.insert(out, A("bag_ask", "봉투 필요하세요? (50원)", 0.4, true, nil, "🛍️"))
			end
			table.insert(out, A("bag_yes", "봉투 추가 (+50원)", 0.3, true, nil, "🛍️"))
			table.insert(out, A("bag_no", "봉투 없이", 0.3, true, nil, "🙅"))
		elseif step == "pay" then
			if tx.cashTaken then
				for i, v in tx.changeOpts do
					table.insert(out, A("change:" .. i, string.format("거스름돈 %s 드리기", wonS(v)), 0.5, true, nil, "💵"))
				end
			else
				table.insert(out, A("pay_card", string.format("카드 결제 %s (카드 꽂기)", wonS(txTotal(tx))), 1.0, true, nil, "💳"))
				table.insert(out, A("pay_cash", "현금 받기", 0.5, true, nil, "💵"))
			end
		elseif step == "pack" then
			table.insert(out, A("pack", "봉투에 담기 (무거운 것부터)", 1.0, true, nil, "🛍️"))
		elseif step == "hand" then
			table.insert(out, A("hand", "물건 · 영수증 드리기", 0.4, true, nil, "🧾"))
		end
	elseif tx.type == "parcel" then
		if not tx.weighed then
			table.insert(out, A("weigh", "저울에 올려 무게 재기", 1.0, true, nil, "⚖️"))
		elseif tx.fee == nil and not tx.refused then
			for i, b in C.CVS.parcelRates do
				table.insert(out, A("fee:" .. i, string.format("%s 요금 %s", b.label, wonS(b.price)), 0.4, true, nil, "🏷️"))
			end
			table.insert(out, A("parcel_refuse", "접수 거절 (20kg 초과)", 0.4, true, nil, "🚫"))
		elseif tx.fee and not tx.labeled then
			table.insert(out, A("label", "운송장 출력 · 부착", 0.8, true, nil, "🖨️"))
		elseif tx.labeled then
			table.insert(out, A("parcel_store", "카드 결제 후 보관함에 넣기", 1.0, true, nil, "📦"))
		end
	elseif tx.type == "refund" then
		if not tx.checked then
			table.insert(out, A("rf_check", "영수증 · 상품 상태 확인", 0.8, true, nil, "🔎"))
		else
			table.insert(out, A("rf_refund", "환불 처리", 0.8, true, nil, "↩️"))
			table.insert(out, A("rf_refuse", "정중히 거절 (규정 안내)", 0.6, true, nil, "🙇"))
			table.insert(out, A("rf_manager", "점장님께 전화 연결", 0.8, true, nil, "📞"))
		end
	end
end

function CVS.actions(store: any, player: Player, sess: any, station: string): { any }
	local out = {}
	if not store.open then
		return out
	end
	local h = heldItem(store, sess)
	if station == "timeclock" then
		table.insert(out, A("clockout", "퇴근하기 (정산)", 0.3, true, nil, "🏁"))
		return out
	end
	if station == "counter" then
		if h and h.kind ~= "product" then
			table.insert(out, A("none", "손에 든 걸 먼저 내려놓아요", 0, false, nil, "✋"))
			return out
		end
		counterActions(store, sess, out)
		return out
	end
	if station == "backroom" then
		if h then
			table.insert(out, A("putback", (h.text or "물건") .. " 내려놓기", 0.3, true, nil, "📦"))
			return out
		end
		for _, c in C.CVS.categories do
			local n = store.backroom[c.id]
			local s = store.shelf[c.id] or 0
			local reason = nil
			if n ~= math.huge and n <= 0 then
				reason = "창고에 없음 · 계산대에서 발주"
			elseif s >= C.CVS.shelfCapacity then
				reason = "진열대가 가득 차 있어요"
			end
			table.insert(out, A("box:" .. c.id, string.format("%s 박스 들기%s", c.label, if s <= C.CVS.shelfCapacity * 0.3 then " ⚠️" else ""), 0.5, reason == nil, reason, "📦"))
		end
		table.insert(out, A("mop", "대걸레 들기", 0.3, true, nil, "🧹"))
		return out
	end
	if string.sub(station, 1, 6) == "shelf_" then
		local cat = string.sub(station, 7)
		if h and h.kind == "box" and h.cat == cat then
			table.insert(out, A("stock", string.format("%s 진열하기 (%d → %d)", catDef(cat).label, store.shelf[cat], math.min(C.CVS.shelfCapacity, store.shelf[cat] + C.CVS.boxSize)), 1.4, true, nil, "🧺"))
		elseif h and h.kind == "box" then
			table.insert(out, A("none", string.format("%s 박스는 %s 진열대로", catDef(h.cat).label, catDef(h.cat).label), 0, false, nil, "📦"))
		end
		if W.phaseOf(store) == "close" and store.close.face_shelves == false and not h then
			local low = nil
			for _, c in C.CVS.categories do
				if (store.shelf[c.id] or 0) < C.CVS.shelfCapacity * 0.5 then
					low = c
				end
			end
			table.insert(out, A("face", "매대 정리 (상품 앞으로 당기기)", 1.4, low == nil, if low then string.format("%s 진열이 부족해요 (%d/%d)", low.label, store.shelf[low.id], C.CVS.shelfCapacity) else nil, "🧹"))
		end
		if #out == 0 then
			table.insert(out, A("none", shelfLabel(store, cat) .. " · 창고 박스로 채워요", 0, false, nil, "🧺"))
		end
		return out
	end
	if station == "bin" then
		if h then
			table.insert(out, A("none", "손을 비우고 와요", 0, false, nil, "🗑️"))
		elseif store.trashBag then
			table.insert(out, A("none", "봉투를 분리수거함에 버리고 새 봉투 끼우기", 0, false, nil, "🗑️"))
		else
			local closing = W.phaseOf(store) == "close" and store.close.trash_out == false
			table.insert(out, A("trash_take", string.format("쓰레기 봉투 빼기 (%d/%d)", store.trash, C.CVS.trashMax), 1.0, store.trash >= 3 or closing, if store.trash < 3 and not closing then "아직 여유 있어요" else nil, "🗑️"))
		end
		return out
	end
	if station == "dumpster" then
		if h and h.kind == "bag" then
			table.insert(out, A("dump", "분리수거 · 새 봉투 챙기기", 1.0, true, nil, "♻️"))
		else
			table.insert(out, A("none", "쓰레기 봉투를 들고 와요", 0, false, nil, "♻️"))
		end
		return out
	end
	if station == "breaker" then
		local ev = store.event
		if ev and ev.kind == "power" and not ev.breakerUp then
			table.insert(out, A("breaker", "차단기 올리기", 1.2, true, nil, "⚡"))
		else
			table.insert(out, A("none", "차단기 정상", 0, false, nil, "⚡"))
		end
		return out
	end
	if station == "chiller" then
		local ev = store.event
		if ev and ev.kind == "expiry" then
			local labels = { "유통기한 확인 (쇼케이스)", "폐기 등록 (PDA)", "폐기 상품 빼서 창고로" }
			for i = ev.step, #labels do
				table.insert(out, A("expiry:" .. i, (if i == ev.step then "▶ " else "") .. labels[i], 0.8, true, nil, "🗓️"))
			end
		else
			table.insert(out, A("none", "냉장 쇼케이스 정상", 0, false, nil, "🧊"))
		end
		return out
	end
	if station == "floor" then
		if W.phaseOf(store) == "close" and store.close.mop_floor == false then
			local reason = if not h or h.kind ~= "mop" then "창고에서 대걸레를 들고 와요" elseif #store.puddles > 0 then "흘린 자국부터 닦아요" else nil
			table.insert(out, A("mop_close", "매장 바닥 대걸레질 (마감)", 2.0, reason == nil, reason, "🧹"))
		else
			table.insert(out, A("none", "매장 바닥", 0, false, nil, "🧹"))
		end
		return out
	end
	if string.sub(station, 1, 7) == "puddle:" then
		if h and h.kind == "mop" then
			table.insert(out, A("wipe", "대걸레로 닦기", 1.4, true, nil, "🧹"))
		else
			table.insert(out, A("none", "창고에서 대걸레를 들고 와요", 0, false, nil, "🧹"))
		end
		return out
	end
	if string.sub(station, 1, 6) == "drunk:" then
		local d = store.drunk
		if d then
			table.insert(out, A("dk_water", "생수 한 병 건네기 (진열대 -1)", 0.8, not d.water and (store.shelf.drink or 0) > 0, if d.water then "이미 드렸어요" elseif (store.shelf.drink or 0) <= 0 then "음료 진열대가 비었어요" else nil, "💧"))
			table.insert(out, A("dk_guide", "정중하게 출구로 안내", 1.2, true, nil, "🙇"))
			table.insert(out, A("dk_police", "112 신고", 0.8, true, nil, "🚓"))
		end
		return out
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Perform an action (server truth). -> ok, message?
-------------------------------------------------------------------------------------------------
local function mistake(store: any, player: Player, sess: any, tx: any?, cost: number, label: string, text: string?, penalty: number?)
	if tx then
		tx.acc -= cost
		table.insert(tx.notes, label)
	end
	if penalty and penalty > 0 then
		W.penalty(player, sess, label, penalty, text)
	else
		sess.mistakes = (sess.mistakes or 0) + 1
		W.toast(player, text or ("⚠️ " .. label), "warn", { sound = "error" })
	end
end

local function eventDone(store: any, player: Player, sess: any, perf: number, label: string, good: boolean?)
	store.event = nil
	W.unit(player, sess, { perf = perf, accuracy = if good == false then 0.6 else 1, exact = good ~= false, fast = true }, label, C.XP.event)
	refreshVisuals(store)
end

function CVS.act(store: any, player: Player, sess: any, station: string, action: string, _arg: any?): (boolean, string?)
	local valid = false
	for _, a in CVS.actions(store, player, sess, station) do
		if a.id == action then
			if not a.enabled then
				return false, a.reason or "지금은 할 수 없어요"
			end
			valid = true
			break
		end
	end
	if not valid then
		return false, "지금은 할 수 없어요"
	end
	local parts = string.split(action, ":")
	local verb = parts[1]
	local h = heldItem(store, sess)
	local at = W.stationPart(store, station)
	local oid = store.counterTx
	local tx = oid and store.tx[oid]
	local o = oid and Orders.get(oid)
	if tx then
		tx.worker = player
	end
	if verb == "clockout" then
		W.requestEnd(player)
		return true
	elseif verb == "reboot" then
		local ev = store.event
		if parts[2] == "power" then
			eventDone(store, player, sess, 700, "⚡ 정전 복구 완료")
			W.storeToast(store, "✅ 전원 · POS 복구 완료", "good")
			return true
		end
		local i = tonumber(parts[2])
		if i ~= ev.step then
			mistake(store, player, sess, nil, 0, "재부팅 순서", string.format("🖥️ 순서가 달라요 · 먼저: %s", ev.steps[ev.step]))
			return true
		end
		Props.sound(store.visual.posPart, "tap", 0.5)
		ev.step += 1
		if ev.step == 2 then
			ev.bootUntil = os.clock() + 5
		end
		if ev.step > #ev.steps then
			eventDone(store, player, sess, 600, "🖥️ POS 복구 완료")
			W.storeToast(store, "✅ POS 정상 작동", "good")
		end
		refreshVisuals(store)
		return true
	elseif verb == "breaker" then
		store.event.breakerUp = true
		Props.sound(at, "place", 0.6)
		W.toast(player, "⚡ 차단기를 올렸어요 · 이제 계산대 POS 재부팅", "good")
		refreshVisuals(store)
		return true
	elseif verb == "expiry" then
		local ev = store.event
		local i = tonumber(parts[2])
		if i ~= ev.step then
			mistake(store, player, sess, nil, 0, "순서", "🗓️ 먼저 확인부터 해요")
			return true
		end
		ev.step += 1
		if ev.step > 3 then
			eventDone(store, player, sess, 500, "🗓️ 폐기 처리 완료")
		end
		return true
	elseif verb == "train" then
		local ev = store.event
		local i = tonumber(parts[2])
		if i == ev.quiz.answer then
			W.toast(player, "🧑‍🎓 신입: \"아하, 감사합니다 선배님!\"", "good")
			eventDone(store, player, sess, 900, "신입 교육 완료")
		else
			W.toast(player, "🧑‍🎓 신입: \"헉… 그래도 돼요? 점장님이 아니라던데…\"", "warn")
			eventDone(store, player, sess, 300, "신입 교육 (잘못 알려 줌)", false)
		end
		return true
	elseif verb == "reorder" then
		local cat = parts[2]
		table.insert(store.pending, { cat = cat, n = 2, at = os.clock() + C.CVS.orderArriveSeconds })
		W.task(player, sess, "shelf", C.CVS.perfTask * 0.5)
		W.toast(player, string.format("📋 %s 박스 2개 발주 · %d초 뒤 창고 입고", catDef(cat).label, C.CVS.orderArriveSeconds), "info")
		return true
	elseif verb == "till_count" then
		local actual = store.till
		local opts = { actual }
		for _, d in { 1000, -1000, 5000, -500, 10000 } do
			if #opts >= 3 then
				break
			end
			if rng:NextNumber() < 0.7 then
				table.insert(opts, actual + d)
			end
		end
		while #opts < 3 do
			table.insert(opts, actual + 2000 * #opts)
		end
		for k = #opts, 2, -1 do
			local j = rand(k)
			opts[k], opts[j] = opts[j], opts[k]
		end
		store.tillCount = { options = opts, notes = WS.noteCount(actual), book = store.tillBook }
		return true
	elseif verb == "till" then
		local v = store.tillCount.options[tonumber(parts[2])]
		if v == store.till then
			local diff = store.till - store.tillBook
			if diff == 0 then
				W.toast(player, "💴 시재 일치! 마감 정산 완료", "good")
			else
				W.toast(player, string.format("💴 시재 %s %s · 그대로 보고했어요", if diff > 0 then "초과" else "부족", wonS(math.abs(diff))), "warn")
			end
			store.tillCount = nil
			W.closeTask(store, player, sess, "count_till")
		else
			mistake(store, player, sess, nil, 0, "시재 계산 오류", "💴 다시 세어 보세요 · 합계가 안 맞아요", 500)
			store.tillCount = nil
		end
		return true
	elseif verb == "putback" then
		W.drop(player, sess)
		return true
	elseif verb == "box" then
		local cat = parts[2]
		if store.backroom[cat] ~= math.huge then
			store.backroom[cat] -= 1
		end
		local def = catDef(cat)
		local item = W.newItem(store, "box", { cat = cat, text = def.label .. " 박스", color = def.color, boxSize = Vector3.new(1.6, 1.0, 1.1) })
		Props.create(item, store.folder, CFrame.new(at and at.Position or store.cf.Position))
		W.hold(player, sess, item)
		refreshVisuals(store)
		return true
	elseif verb == "mop" then
		local item = W.newItem(store, "mop", { color = { 200, 200, 205 }, size3 = Vector3.new(0.14, 3.6, 0.14), text = "대걸레" })
		Props.create(item, store.folder, CFrame.new(at and at.Position or store.cf.Position))
		W.hold(player, sess, item)
		return true
	elseif verb == "stock" then
		local cat = h.cat
		local before = store.shelf[cat]
		store.shelf[cat] = math.min(C.CVS.shelfCapacity, before + C.CVS.boxSize)
		W.dropDestroy(player, sess)
		Props.sound(at, "place", 0.5)
		W.task(player, sess, "shelf", C.CVS.perfTask * (if before <= C.CVS.shelfCapacity * 0.3 then 1.25 else 1))
		refreshVisuals(store)
		return true
	elseif verb == "face" then
		W.closeTask(store, player, sess, "face_shelves")
		return true
	elseif verb == "trash_take" then
		local item = W.newItem(store, "bag", { color = { 30, 30, 34 }, sealed = true, text = "쓰레기 봉투" })
		Props.create(item, store.folder, CFrame.new(store.binPos + Vector3.new(0, 1, 0)))
		W.hold(player, sess, item)
		store.trashBag = true
		store.trashWasClose = W.phaseOf(store) == "close"
		store.trash = 0
		refreshVisuals(store)
		return true
	elseif verb == "dump" then
		W.dropDestroy(player, sess)
		store.trashBag = false
		Props.sound(at, "place", 0.6)
		if W.phaseOf(store) == "close" and store.close.trash_out == false then
			W.closeTask(store, player, sess, "trash_out")
		else
			W.task(player, sess, "trash", C.CVS.perfTask * 0.75)
		end
		refreshVisuals(store)
		return true
	elseif verb == "wipe" then
		local id = string.sub(station, 8)
		for k, p in store.puddles do
			if p.id == id then
				if p.part then
					p.part:Destroy()
				end
				if p.sign then
					p.sign:Destroy()
				end
				table.remove(store.puddles, k)
				break
			end
		end
		W.removeStation(store, station)
		W.task(player, sess, "mop", C.CVS.perfTask)
		return true
	elseif verb == "mop_close" then
		W.closeTask(store, player, sess, "mop_floor")
		return true
	elseif verb == "dk_water" then
		local d = store.drunk
		d.water = true
		store.shelf.drink = math.max(0, (store.shelf.drink or 0) - 1)
		customers().sayText(store.id, d.cid, "어어… 물… 고마워잉… 히끅", 4)
		refreshVisuals(store)
		return true
	elseif verb == "dk_guide" or verb == "dk_police" then
		local d = store.drunk
		local cid = d.cid
		W.removeStation(store, "drunk:" .. cid)
		store.drunk = nil
		if verb == "dk_police" then
			customers().sayText(store.id, cid, "아 뭐여~ 경찰? 알았어, 간다 가…", 4)
			customers().hold(store.id, cid, false)
			customers().release(store.id, cid, nil)
			W.unit(player, sess, { perf = 500, accuracy = 0.7, exact = false, fast = true }, "🚓 취객 신고 처리 (조금 과했어요)", C.XP.event)
		elseif d.water or rng:NextNumber() < 0.55 then
			customers().hold(store.id, cid, false)
			customers().release(store.id, cid, "calmed")
			W.unit(player, sess, { perf = 900, accuracy = 1, exact = d.water, fast = true }, if d.water then "🙇 취객 응대 완벽!" else "🙇 취객 안내 완료", C.XP.event)
		else
			-- not yet: he sits down again
			store.drunk = { cid = cid, since = os.clock(), water = false, tries = (d.tries or 0) + 1 }
			W.addStation(store, { id = "drunk:" .. cid, label = "🥴 취객 손님", pos = (customers().get(store.id, cid) or { pos = at and at.Position or store.cf.Position }).pos, reach = 7 })
			customers().say(store.id, cid, "trouble")
			W.toast(player, "🥴 아직 말이 안 통해요… 물이라도 한 병 드려 볼까요?", "info")
		end
		return true
	end
	-- counter transaction actions
	if not tx or not o then
		return false, "계산 중인 손님이 없어요"
	end
	if verb == "scan" then
		local i = tonumber(parts[2])
		local it = tx.items[i]
		if it.fail and not it.failed then
			it.failed = true
			Props.sound(store.visual.posPart, "error", 0.4)
			W.toast(player, string.format("📟 %s 바코드가 안 찍혀요 · 수동 입력", it.name), "warn")
			return true
		end
		it.scanned = true
		it.charged = it.price
		local item = it.model and store.items[it.model]
		if item then
			Props.put(item, store.folder, counterSlot(store, i, true))
		end
		Props.sound(store.visual.posPart, "scan", 0.5, 1.2)
		tx.total = txTotal(tx)
		if allScanned(tx) then
			if tx.adult and not tx.idDecision then
				if tx.young then
					W.toast(player, "🪪 술·담배가 있어요 · 앳된 손님이에요. 신분증 확인!", "info")
				end
			end
		end
		refreshVisuals(store)
		return true
	elseif verb == "manual" then
		local i, v = tonumber(parts[2]), tonumber(parts[3])
		local it = tx.items[i]
		it.manual = true
		it.scanned = true
		it.charged = v
		local item = it.model and store.items[it.model]
		if item then
			Props.put(item, store.folder, counterSlot(store, i, true))
		end
		if v ~= it.price then
			mistake(store, player, sess, tx, 0.3, "수동 입력 가격 오류", string.format("⌨️ %s 가격이 틀렸어요 (정가 %s)", it.name, wonS(it.price)), math.abs(v - it.price))
		else
			Props.sound(store.visual.posPart, "scan", 0.5)
		end
		tx.total = txTotal(tx)
		refreshVisuals(store)
		return true
	elseif verb == "cig" then
		local i, k = tonumber(parts[2]), tonumber(parts[3])
		local it = tx.items[i]
		it.fetched = true
		it.scanned = true
		it.charged = it.price
		if k ~= it.cig then
			mistake(store, player, sess, tx, 0.3, "담배 번호 오류", string.format("🚬 손님: \"%d번이요, %d번!\" (다시 꺼냈어요)", it.cig, it.cig))
		end
		tx.total = txTotal(tx)
		refreshVisuals(store)
		return true
	elseif verb == "id_ask" then
		tx.idShown = true
		local line = if tx.minor and Lines then Lines.pick(store.lineMemo or {}, "student", "idShow", rand) elseif Lines then Lines.pick(store.lineMemo or {}, "normal", "idShow", rand) else "여기요"
		custText(store, o, string.format("%s\n🪪 주민등록증 · %d년생", line or "", tx.birth), 7)
		return true
	elseif verb == "id_skip" or verb == "id_ok" then
		tx.idDecision = "sold"
		if tx.minor then
			mistake(store, player, sess, tx, 1, "미성년자 술·담배 판매", "🚨 미성년자에게 술·담배를 팔았어요! (영업정지 사유) 성과급 크게 차감", 5000)
		elseif verb == "id_skip" and tx.young then
			mistake(store, player, sess, tx, 0.2, "신분증 미확인", "🪪 앳된 손님은 꼭 신분증을 확인해요 (이번엔 성인이었어요)")
		end
		return true
	elseif verb == "id_refuse" then
		tx.idDecision = "refused"
		for _, it in tx.items do
			if it.adult then
				it.removed = true
				it.scanned = false
				it.charged = 0
				local item = it.model and store.items[it.model]
				if item then
					W.destroyItem(store, item)
				end
				-- the bottle goes back on the shelf
				local p = it.pid and WS.product(it.pid)
				if p then
					store.shelf[p.cat] = math.min(C.CVS.shelfCapacity, (store.shelf[p.cat] or 0) + 1)
				end
			end
		end
		if tx.minor then
			custSay(store, o, "refused")
			W.toast(player, "👍 미성년자 판매 거절 · 잘했어요!", "good")
			tx.idGood = true
		else
			tx.acc -= 0.4
			table.insert(tx.notes, "성인에게 판매 거절")
			custText(store, o, "아니 저 성인인데요?! " .. tx.birth .. "년생이라니까요", 5)
			W.toast(player, string.format("🪪 %d년생은 성인이에요 (만 19세 기준 연도 확인)", tx.birth), "warn")
		end
		-- nothing left: the customer leaves without buying
		local any = false
		for _, it in tx.items do
			if not it.removed then
				any = true
			end
		end
		if not any then
			tx.acc = if tx.minor then 1 else tx.acc
			finishTx(store, player, o, if tx.minor then "refused" else "angry")
			return true
		end
		tx.total = txTotal(tx)
		refreshVisuals(store)
		return true
	elseif verb == "bag_ask" then
		tx.bagAsked = true
		custSay(store, o, if tx.wantBag then "bagAsk" else "bagNo")
		return true
	elseif verb == "bag_yes" or verb == "bag_no" then
		tx.bag = verb == "bag_yes"
		if not tx.bagAsked and tx.bag ~= tx.wantBag then
			mistake(store, player, sess, tx, 0.15, "봉투 확인 안 함", if tx.bag then "🛍️ 손님: \"봉투 필요 없다니까요…\" (먼저 여쭤봐요)" else "🛍️ 손님: \"봉투 주셔야죠…\" (먼저 여쭤봐요)")
			tx.bag = tx.wantBag
		elseif tx.bagAsked and tx.bag ~= tx.wantBag then
			mistake(store, player, sess, tx, 0.2, "봉투 잘못", "🛍️ 손님 말과 다르게 했어요")
			tx.bag = tx.wantBag
		end
		tx.total = txTotal(tx)
		-- the customer gets the payment out
		if tx.method == "cash" then
			tx.paidNote = WS.cashPaid(tx.total, rand)
			custSay(store, o, "cash", { money = wonS(tx.paidNote) })
		else
			custSay(store, o, "card")
		end
		refreshVisuals(store)
		return true
	elseif verb == "pay_card" then
		if tx.method ~= "card" then
			mistake(store, player, sess, tx, 0.05, "결제 수단 확인", string.format("💵 손님은 현금 %s을 내밀었어요", wonS(tx.paidNote or 0)))
			return true
		end
		tx.paid = true
		Props.sound(store.visual.posPart, "ready", 0.5)
		store.tillBook += 0 -- card: no cash in the drawer
		W.toast(player, "💳 결제 완료 · 영수증 출력", "info")
		return true
	elseif verb == "pay_cash" then
		if tx.method ~= "cash" then
			mistake(store, player, sess, tx, 0.05, "결제 수단 확인", "💳 손님은 카드를 내밀었어요")
			return true
		end
		tx.cashTaken = true
		tx.changeOpts, tx.changeRight = WS.changeOptions(tx.total, tx.paidNote, rand)
		return true
	elseif verb == "change" then
		local i = tonumber(parts[2])
		local given = tx.changeOpts[i]
		local right = tx.paidNote - tx.total
		store.till += tx.paidNote - given
		store.tillBook += tx.total
		tx.paid = true
		if given ~= right then
			local diff = given - right
			mistake(store, player, sess, tx, 0.5, "거스름돈 오류", string.format("💵 거스름돈이 %s %s 틀렸어요! (정답 %s)", wonS(math.abs(diff)), if diff > 0 then "많이" else "적게", wonS(right)), math.abs(diff))
			if diff < 0 then
				custText(store, o, "저기요, 거스름돈 덜 주셨는데요?", 5)
			end
		else
			Props.sound(store.visual.posPart, "coin", 0.5)
		end
		return true
	elseif verb == "pack" then
		tx.packed = true
		local item = W.newItem(store, "bag", { color = { 245, 245, 245 }, text = "봉투" })
		Props.create(item, store.folder, counterSlot(store, 2, true))
		table.insert(tx.models, item.id)
		for _, it in tx.items do
			local m = it.model and store.items[it.model]
			if m then
				Props.destroy(m)
			end
		end
		Props.sound(at, "pickup", 0.4)
		return true
	elseif verb == "hand" then
		finishTx(store, player, o, nil)
		return true
	elseif verb == "weigh" then
		tx.weighed = true
		local item = tx.box and store.items[tx.box]
		if item then
			Props.put(item, store.folder, acf(store, "counter_items") * CFrame.new(-3.4, -0.38, 0))
			item.text = string.format("%.1fkg", tx.kg)
			Props.refresh(item)
		end
		Props.sound(store.visual.posPart, "scan", 0.4)
		W.toast(player, string.format("⚖️ %.1f kg · %s행", tx.kg, tx.dest), "info")
		refreshVisuals(store)
		return true
	elseif verb == "fee" then
		local i = tonumber(parts[2])
		local right = WS.parcelBand(tx.kg)
		if not right then
			mistake(store, player, sess, tx, 0.6, "20kg 초과 택배 접수", string.format("📦 %.1fkg은 접수 불가예요 (20kg 초과) · 다시 거절했어요", tx.kg), 1000)
			tx.refused = true
			finishTx(store, player, o, "ok")
			return true
		end
		tx.fee = C.CVS.parcelRates[i].price
		if i ~= right then
			mistake(store, player, sess, tx, 0.3, "택배 요금 오류", string.format("🏷️ %.1fkg은 %s 요금이에요", tx.kg, C.CVS.parcelRates[right].label), math.abs(tx.fee - C.CVS.parcelRates[right].price))
			tx.fee = C.CVS.parcelRates[right].price
		end
		tx.total = tx.fee
		refreshVisuals(store)
		return true
	elseif verb == "parcel_refuse" then
		tx.refused = true
		if WS.parcelBand(tx.kg) then
			mistake(store, player, sess, tx, 0.6, "접수 가능한 택배 거절", string.format("📦 %.1fkg은 접수할 수 있었어요", tx.kg))
			finishTx(store, player, o, "angry")
		else
			custText(store, o, "아 20kg 넘으면 안 돼요? 우체국 가야겠네…", 5)
			W.toast(player, "👍 20kg 초과 · 정중히 거절했어요", "good")
			finishTx(store, player, o, "ok")
		end
		return true
	elseif verb == "label" then
		tx.labeled = true
		Props.sound(store.visual.posPart, "ready", 0.4)
		return true
	elseif verb == "parcel_store" then
		Props.sound(at, "place", 0.5)
		finishTx(store, player, o, nil)
		return true
	elseif verb == "rf_check" then
		tx.checked = true
		custText(store, o, string.format("%s · %s", if tx.receipt then "🧾 영수증 있음" else "🧾 영수증 없음 (\"버렸죠 당연히\")", if tx.opened then "📦 개봉함" else "📦 미개봉"), 7)
		return true
	elseif verb == "rf_refund" or verb == "rf_refuse" or verb == "rf_manager" then
		local should = tx.receipt and not tx.opened
		local line = nil
		if verb == "rf_manager" then
			tx.acc = 0.75
			line = "ok"
			W.toast(player, "📞 점장님: \"규정대로 하면 돼~\" (스스로 판단하면 더 좋아요)", "info")
		elseif verb == "rf_refund" then
			if should then
				line = "refundOk"
				store.tillBook -= 0
			else
				mistake(store, player, sess, tx, 0.6, "규정 외 환불", string.format("↩️ %s 상품은 환불 대상이 아니에요", if not tx.receipt then "영수증 없는" else "개봉한"), tx.price)
				line = "refundOk"
			end
		else
			if should then
				mistake(store, player, sess, tx, 0.5, "환불 가능한 건 거절", "🙇 영수증 있고 미개봉이면 환불해 드려야 해요")
				line = "refundNo"
			else
				line = "refundNo"
				custSay(store, o, "argue")
				W.toast(player, "👍 규정대로 정중히 안내했어요 · 진상 응대 성공", "good")
			end
		end
		if line == "refundNo" then
			-- a short argument at the counter before she leaves
			tx.done = true
			task.delay(3, function()
				if Orders.get(o.id) and WS.isOpen(o.state) then
					finishTx(store, player, o, line)
				end
			end)
		else
			finishTx(store, player, o, line)
		end
		return true
	end
	return false, "알 수 없는 작업"
end

-------------------------------------------------------------------------------------------------
-- Tick: events, deliveries of reorders, the drunk, rain footprints
-------------------------------------------------------------------------------------------------
function CVS.tick(store: any, now: number)
	if not store.open then
		return
	end
	local changed = false
	-- reorders arrive
	for i = #store.pending, 1, -1 do
		local pz = store.pending[i]
		if now >= pz.at then
			table.remove(store.pending, i)
			if store.backroom[pz.cat] ~= math.huge then
				store.backroom[pz.cat] += pz.n
			end
			W.storeToast(store, string.format("🚚 발주한 %s 박스 %d개 입고 (창고)", catDef(pz.cat).label, pz.n), "info")
			changed = true
		end
	end
	-- the counter transaction: oldest open one
	if not store.counterTx or not store.tx[store.counterTx] then
		store.counterTx = nil
		local best = nil
		for oid, tx in store.tx do
			if not best or tx.startedAt < best.startedAt then
				best = tx
			end
		end
		if best then
			store.counterTx = best.orderId
			changed = true
		end
	end
	-- the drunk knocks things over when ignored
	if store.drunk and now - store.drunk.since > 45 then
		local cid = store.drunk.cid
		W.removeStation(store, "drunk:" .. cid)
		store.drunk = nil
		store.shelf.drink = math.max(0, (store.shelf.drink or 0) - 3)
		local c = customers().get(store.id, cid)
		if c then
			addPuddle(store, c.pos + Vector3.new(1.5, 0, 0), "깨진 병 · 흘린 술")
		end
		customers().hold(store.id, cid, false)
		customers().release(store.id, cid, nil)
		W.storeToast(store, "💥 방치된 취객이 진열대를 넘어뜨리고 나갔어요 · 바닥 정리!", "bad")
		changed = true
	end
	-- random events (피크 타임 중심)
	local phase = W.phaseOf(store)
	if not store.event and now >= (store.nextEvent or 0) and phase ~= "prep" then
		local ev = C.CVS.eventEvery
		store.nextEvent = now + rng:NextNumber(ev[1], ev[2])
		local list = {}
		local total = 0
		for _, e in EVENTS do
			if not e.duty or unlocked(store, e.duty) then
				local w = e.w
				if e.id == "puddle" and raining() then
					w *= 2
				end
				if phase == "close" and (e.id == "rush" or e.id == "drunk" or e.id == "refund") then
					w *= 0.3
				end
				table.insert(list, { id = e.id, w = w })
				total += w
			end
		end
		local r = rng:NextNumber() * total
		for _, e in list do
			r -= e.w
			if r <= 0 then
				startEvent(store, e.id)
				break
			end
		end
		changed = true
	end
	-- an event nobody handles fades (no punishment beyond the waiting customers)
	if store.event and now - store.event.since > 120 and store.event.kind ~= "pos" and store.event.kind ~= "power" then
		store.event = nil
		changed = true
	end
	if changed then
		refreshVisuals(store)
		W.dirty(store)
	end
end

-------------------------------------------------------------------------------------------------
-- Hints, close tasks, views
-------------------------------------------------------------------------------------------------
CVS.CLOSE_LABEL = {
	mop_floor = "매장 바닥 대걸레질",
	face_shelves = "매대 정리 (진열 50% 이상)",
	trash_out = "쓰레기 봉투 분리수거",
	count_till = "시재 정산 (금고 세기)",
}

function CVS.hint(store: any, sess: any): (string?, string?)
	local h = heldItem(store, sess)
	local phase = W.phaseOf(store)
	if h and h.kind == "box" then
		return string.format("%s → %s 진열대에 채우기", h.text, catDef(h.cat).label), "shelf_" .. h.cat
	end
	if h and h.kind == "bag" then
		return "쓰레기 봉투 → 창고 분리수거함", "dumpster"
	end
	if h and h.kind == "mop" then
		if #store.puddles > 0 then
			return "흘린 자국 닦기", "puddle:" .. store.puddles[1].id
		end
		if phase == "close" and store.close.mop_floor == false then
			return "마감: 매장 바닥 대걸레질", "floor"
		end
		return "대걸레는 창고에 두기", "backroom"
	end
	local ev = store.event
	if ev and ev.kind == "power" and not ev.breakerUp then
		return "⚡ 정전: 창고 차단기 올리기", "breaker"
	end
	if ev and (ev.kind == "pos" or ev.kind == "power") then
		return "🖥️ POS 재부팅: " .. (if ev.kind == "pos" then ev.steps[ev.step] or "" else "POS 재부팅"), "counter"
	end
	if store.drunk then
		return "🥴 취객 응대 (물 → 출구 안내)", "drunk:" .. store.drunk.cid
	end
	local tx = store.counterTx and store.tx[store.counterTx]
	if tx and not tx.done then
		if tx.type == "sale" then
			local step = saleStep(tx)
			local extra = ""
			if step == "pay" then
				extra = if tx.method == "cash" then string.format(" · 현금 %s 받음", wonS(tx.paidNote or 0)) else " · 손님은 카드"
			elseif step == "id" then
				extra = if tx.young then " · 앳된 손님!" else ""
			end
			return string.format("계산대: %s%s (합계 %s)", STEP_TEXT[step] or step, extra, wonS(txTotal(tx))), "counter"
		elseif tx.type == "parcel" then
			return if not tx.weighed then "택배: 저울에 올리기" elseif not tx.fee then string.format("택배: %.1fkg 요금 고르기 (20kg 초과는 거절)", tx.kg) else "택배: 운송장 → 보관", "counter"
		else
			return if tx.checked then "환불: 영수증 있고 미개봉이면 환불, 아니면 정중히 거절" else "환불: 영수증 · 상품 상태부터 확인", "counter"
		end
	end
	if #store.puddles > 0 then
		return "바닥에 흘린 자국 · 창고에서 대걸레 들기", "backroom"
	end
	if ev and ev.kind == "expiry" then
		return "🗓️ 냉장 쇼케이스 유통기한 처리", "chiller"
	end
	if ev and ev.kind == "trainee" then
		return "🧑‍🎓 신입 질문에 답해 주기 (계산대)", "counter"
	end
	if store.trash >= C.CVS.trashMax - 2 then
		return "쓰레기통이 거의 찼어요 · 봉투 빼기", "bin"
	end
	local low, lowN = nil, math.huge
	for _, c in C.CVS.categories do
		local n = store.shelf[c.id] or 0
		if n <= C.CVS.shelfCapacity * 0.3 and n < lowN then
			low, lowN = c, n
		end
	end
	if low then
		if store.backroom[low.id] ~= math.huge and store.backroom[low.id] <= 0 then
			return string.format("%s 창고 재고 없음 · 계산대에서 발주", low.label), "counter"
		end
		return string.format("%s 진열대 %d/%d · 창고에서 박스", low.label, lowN, C.CVS.shelfCapacity), "backroom"
	end
	if phase == "close" then
		for _, id in C.CVS.closeTasks do
			if store.close[id] == false then
				local where = ({ mop_floor = "backroom", face_shelves = "shelf_food", trash_out = "bin", count_till = "counter" })[id]
				return "마감: " .. CVS.CLOSE_LABEL[id], where
			end
		end
		return "마감 완료 · 근태 단말기에서 퇴근 (정산)", "timeclock"
	end
	return "계산대에서 손님 기다리기 · 틈틈이 진열 확인", "counter"
end

function CVS.closeTasks(store: any): { any }
	local out = {}
	for _, id in C.CVS.closeTasks do
		if store.close[id] ~= nil then
			table.insert(out, { id = id, label = CVS.CLOSE_LABEL[id], done = store.close[id] == true })
		end
	end
	return out
end

function CVS.stockView(store: any): { any }
	local out = {}
	for _, c in C.CVS.categories do
		local n = store.shelf[c.id] or 0
		local b = store.backroom[c.id]
		table.insert(out, { id = c.id, label = c.label .. (if b ~= math.huge then string.format(" (창고 %d)", b) else ""), n = n, max = C.CVS.shelfCapacity, low = n <= C.CVS.shelfCapacity * 0.3 })
	end
	table.insert(out, { id = "trash", label = "쓰레기통", n = store.trash, max = C.CVS.trashMax, low = store.trash >= C.CVS.trashMax - 2, inverse = true })
	return out
end

function CVS.itemView(_store: any, item: any): any
	if item.kind == "box" then
		return { kind = "box", title = item.text or "박스" }
	elseif item.kind == "bag" then
		return { kind = "bag", title = item.text or "봉투" }
	elseif item.kind == "mop" then
		return { kind = "mop", title = "대걸레" }
	end
	return { kind = item.kind, title = item.text or item.kind }
end

-- the counter card / event card for the HUD
function CVS.extraView(store: any, _player: Player, _sess: any): any
	local out: any = { kind = "cvs" }
	local tx = store.counterTx and store.tx[store.counterTx]
	local o = tx and Orders.get(tx.orderId)
	if tx and o then
		local cust = customers() and customers().get(store.id, o.customerId)
		local v: any = { type = tx.type, title = string.format("%s #%d", tx.typeLabel or "계산", o.number), who = cust and string.format("%s %s", cust.pdef.icon or "", cust.pdef.label or "") or o.name, total = txTotal(tx), items = {}, steps = {} }
		if tx.type == "sale" then
			for _, it in tx.items do
				table.insert(v.items, { text = string.format("%s %s", it.icon, it.name), price = it.charged or it.price, done = it.scanned, removed = it.removed, warn = (it.failed and not it.manual) or it.adult })
			end
			local cur = saleStep(tx)
			for _, st in { "scan", "id", "bag", "pay", "pack", "hand" } do
				if (st ~= "id" or tx.adult) and (st ~= "pack" or tx.bag ~= false) then
					table.insert(v.steps, { id = st, label = STEP_TEXT[st], cur = st == cur })
				end
			end
			if tx.idShown then
				v.id = string.format("🪪 %d년생 (%s)", tx.birth, if (tonumber(os.date("%Y")) or 2026) - tx.birth >= 19 then "성인 연도" else "미성년 연도")
			end
			if tx.method and (tx.bag ~= nil) then
				v.pay = if tx.method == "cash" then string.format("💵 현금 %s 냄", wonS(tx.paidNote or 0)) else "💳 카드"
			end
		elseif tx.type == "parcel" then
			table.insert(v.items, { text = string.format("📦 택배 → %s", tx.dest), done = tx.labeled })
			if tx.weighed then
				v.weight = string.format("⚖️ %.1f kg (20kg 초과 접수 불가)", tx.kg)
			end
			v.rates = {}
			for _, b in C.CVS.parcelRates do
				table.insert(v.rates, string.format("%s %s", b.label, wonS(b.price)))
			end
		elseif tx.type == "refund" then
			local p = WS.product(tx.pid)
			table.insert(v.items, { text = string.format("↩️ %s %s", p.icon, p.name), price = p.price })
			if tx.checked then
				v.refund = string.format("%s · %s", if tx.receipt then "영수증 있음" else "영수증 없음", if tx.opened then "개봉" else "미개봉")
			end
			v.rule = "환불 규정: 영수증 + 미개봉 상품만"
		end
		out.tx = v
	end
	local ev = store.event
	if ev then
		local e: any = { kind = ev.kind, label = ev.label }
		if ev.steps then
			e.steps = {}
			for i, s in ev.steps do
				table.insert(e.steps, { label = s, done = (ev.step or 0) > i or (ev.kind == "power" and i == 1 and ev.breakerUp), cur = ev.step == i })
			end
		end
		if ev.quiz then
			e.text = "🧑‍🎓 " .. ev.quiz.q
		end
		out.event = e
	end
	if store.drunk then
		out.drunk = true
	end
	if store.tillCount then
		local lines = {}
		for _, n in store.tillCount.notes do
			table.insert(lines, string.format("%s × %d", wonS(n.value), n.n))
		end
		out.till = { notes = lines, book = store.tillCount.book }
	end
	return out
end

return CVS
