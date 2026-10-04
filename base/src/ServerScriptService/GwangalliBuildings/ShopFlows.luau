-- ShopFlows: every shop works like a real one (server-authoritative; prices only from Shared.Menus).
--   편의점 GW25    상품 집기 (장바구니) -> 계산 (영수증) -> 봉투에서 꺼내기 -> 전자레인지 / 온수 (컵라면) -> 먹기
--   부산 돼지국밥  키오스크 주문 -> 조리 -> "N번 손님!" -> 음식 받기 -> 자리에 앉아 먹기 -> 계산 (후불)
--   광안 숯불갈비  테이블 앉기 -> 주문 -> 고기 서빙 -> 굽기 (불판 위로) -> 뒤집기 -> 먹기 -> 계산 (후불)
--   바다 카페      주문 (선불) -> 진동벨 -> 음료 받기 -> 자리 이용 -> 빈 컵 반납
--   PC방          이용권 구매 -> 자리 앉기 -> 로그인 / 게임 -> 음식 주문 (자리로 배달)
--   노래방        방 결제 -> 방 문 열림 -> 리모컨으로 곡 선택 -> 가사 · 조명 · 점수
--   당구장        테이블 대여 -> 큐 받기 -> 4구 샷 (물리 시뮬레이션 리플레이) -> 점수판
--   호텔          체크인 (객실 타입) -> 카드키 -> 객실 문 -> 체크아웃
--   부동산        매물 상담 (Housing)
-- Leaving a 후불 restaurant with an open bill walks you back to the counter (Config.DINE_AND_DASH_RETURN);
-- leaving the convenience store with unpaid goods puts them back on the shelf.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Kit = Shared.Kit
local Menus = Shared.Menus
local Util = Shared.Util
local Billiards = Shared.Billiards

local ShopFlows = {}

local Registry: any
local services: any

type Session = {
	shopId: string,
	kind: string,
	cart: { any },
	bag: { any },
	bill: number,
	billShop: string?,
	order: any?,
	readyAt: number?,
	ready: boolean,
	number: number?,
	tableKey: string?,
	pcTime: number,
	pcSeat: any?,
	dashWarned: number,
	cafeSeatT: number?,
	cafeBonus: boolean?,
}

local sessions: { [Player]: Session } = {}
local orderNo: { [string]: number } = {}
local points: { [Instance]: { prompt: ProximityPrompt? } } = {}
local bbqTables: { [string]: any } = {} -- "shopId:table" -> { player, pieces = {}, model }
local rentals: { [string]: any } = {} -- room / table keys -> { player, until, kind }
local hotelBooks: { [string]: any } = {} -- unitId -> { player, until }
local billiardSims: { [string]: any } = {}

local function now(): number
	return Registry.now()
end

local function sessionFor(p: Player, shop: any): Session
	local s = sessions[p]
	if not s then
		s = { shopId = shop.id, kind = shop.kind, cart = {}, bag = {}, bill = 0, ready = false, pcTime = 0, dashWarned = 0 }
		sessions[p] = s
	end
	if s.shopId ~= shop.id and s.bill <= 0 and #s.cart == 0 then
		s.shopId = shop.id
		s.kind = shop.kind
	end
	return s
end

local function shopOf(inst: Instance): any
	local id = inst:GetAttribute("ShopId")
	return Registry.shop(id)
end

-- inside the shop's walk-in box (frame + W x D, padded)
local function inShop(p: Player, shop: any, pad: number?): boolean
	local pos = Registry.pos(p)
	if not pos or not shop.model then
		return false
	end
	local frame = shop.model:GetAttribute("Frame")
	if typeof(frame) ~= "CFrame" then
		return false
	end
	local l = frame:PointToObjectSpace(pos)
	local g = pad or 1
	return l.X > -g and l.X < shop.w + g and l.Z > -g and l.Z < shop.d + g and l.Y > -2 and l.Y < shop.fl.h + 2
end

local function find(list: { any }, id: any): any?
	return Menus.find(list, id)
end

local function payLabel(shop: any): string
	return shop.name or "가게"
end

-------------------------------------------------------------------------------------------------
-- 편의점
-------------------------------------------------------------------------------------------------
local function cvsPick(p: Player, shop: any, point: BasePart)
	local s = sessionFor(p, shop)
	local id = point:GetAttribute("ProductId")
	local it = find(Menus.CVS, id)
	if not it then
		return
	end
	if #s.cart >= 10 then
		Registry.toast(p, "장바구니가 가득 찼어요 (최대 10개)", "warn")
		return
	end
	table.insert(s.cart, { id = it.id, name = it.name, price = it.price })
	-- hide one item of that section; restock later
	local section = point:GetAttribute("Section")
	local into = point.Parent
	if into then
		for _, d in into:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Section") == section and d:GetAttribute("ProductId") == id and d.Transparency < 0.5 then
				d.Transparency = 1
				task.delay(Config.CVS_RESTOCK, function()
					d.Transparency = 0
				end)
				break
			end
		end
	end
	local total = 0
	for _, c in s.cart do
		total += c.price
	end
	services.Interact.give(p, { id = "basket", label = string.format("장바구니 %d개 · %s", #s.cart, Util.won(total)), kind = "basket", edible = false })
	Registry.toast(p, "🧺 " .. it.name .. " 담았어요 (" .. Util.won(it.price) .. ")", "info")
end

local function cvsPayOpen(p: Player, shop: any)
	local s = sessions[p]
	if not s or #s.cart == 0 then
		Registry.toast(p, "장바구니가 비어 있어요. 진열대에서 상품을 담아요", "warn")
		return
	end
	local total = 0
	for _, c in s.cart do
		total += c.price
	end
	Registry.fire(p, "shop.open", { view = "receipt", shopId = shop.id, title = shop.name, items = s.cart, total = total, action = "cvsPay" })
end

local function cvsPay(p: Player, shop: any): any
	local s = sessions[p]
	if not s or #s.cart == 0 then
		return { ok = false, msg = "결제할 상품이 없어요" }
	end
	if not inShop(p, shop, 4) then
		return { ok = false, msg = "계산대 앞에서 결제해요" }
	end
	local total = 0
	for _, c in s.cart do
		total += c.price
	end
	local ok, msg = services.Economy.spend(p, total, payLabel(shop))
	if not ok then
		return { ok = false, msg = msg }
	end
	for _, c in s.cart do
		table.insert(s.bag, c.id)
	end
	s.cart = {}
	services.Interact.drop(p)
	local pos = shop.model and shop.model:FindFirstChild("Point_pay", true)
	if pos then
		pos:SetAttribute("Beep", now())
	end
	Registry.fire(p, "bag", { bag = s.bag })
	return { ok = true, msg = "결제 완료! 봉투에서 꺼내 먹어요 🛍️" }
end

local function bagTake(p: Player, index: number): any
	local s = sessions[p]
	if not s or not s.bag[index] then
		return { ok = false }
	end
	local id = table.remove(s.bag, index)
	local it = find(Menus.CVS, id)
	if not it then
		return { ok = false }
	end
	local kind = if it.cat == "drink" then "drink" elseif it.noodle then "noodle" else "food"
	local state = if it.heat or it.noodle then "raw" else "ready"
	services.Interact.give(p, {
		id = it.id,
		label = it.name,
		baseLabel = it.name,
		kind = kind,
		color = it.color,
		effect = it.effect,
		stats = it.stats,
		heat = it.heat,
		noodle = it.noodle,
		state = state,
		edible = it.cat ~= "goods",
	})
	if it.cat == "goods" then
		services.Interact.drop(p)
		services.Needs.apply(p, it.effect, nil, it.name)
	end
	if it.heat then
		Registry.toast(p, "🍱 전자레인지에 데워 먹어요", "info")
	elseif it.noodle then
		Registry.toast(p, "🍜 온수기에서 물을 부어요", "info")
	end
	Registry.fire(p, "bag", { bag = s.bag })
	return { ok = true }
end

-------------------------------------------------------------------------------------------------
-- 국밥 / 카페 / PC 음식: order -> ready -> pickup
-------------------------------------------------------------------------------------------------
local function nextNumber(shop: any): number
	orderNo[shop.id] = (orderNo[shop.id] or (if shop.kind == "cafe" then 100 else 0)) + 1
	return orderNo[shop.id]
end

local function setDisplay(shop: any, text: string)
	if not shop.model then
		return
	end
	for _, d in shop.model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("OrderDisplay") then
			local lbl = d:FindFirstChildWhichIsA("SurfaceGui")
			local t = lbl and lbl:FindFirstChildWhichIsA("TextLabel")
			if t then
				t.Text = text
			end
		end
	end
end

local function placeOrder(p: Player, shop: any, list: { any }, itemId: any, prepaid: boolean, cookSecs: number): any
	local it = find(list, itemId)
	if not it then
		return { ok = false, msg = "메뉴에 없는 음식이에요" }
	end
	local s = sessionFor(p, shop)
	if s.order and not s.ready then
		return { ok = false, msg = "이전 주문이 준비 중이에요" }
	end
	if prepaid then
		local ok, msg = services.Economy.spend(p, it.price, payLabel(shop) .. " · " .. it.name)
		if not ok then
			return { ok = false, msg = msg }
		end
	else
		s.bill += it.price
		s.billShop = shop.data.payShop or shop.id
	end
	local n = nextNumber(shop)
	s.order = it
	s.ready = false
	s.number = n
	s.readyAt = os.clock() + cookSecs
	s.shopId = shop.id
	s.kind = shop.kind
	local mine = s
	task.delay(cookSecs, function()
		if sessions[p] == mine and mine.order == it then
			mine.ready = true
			Registry.fire(p, "shop.ready", { shopId = shop.id, number = n, name = it.name, kind = shop.kind })
			if shop.kind == "cafe" then
				setDisplay(shop, "주문 번호\n" .. n .. " 번")
			end
			local pt = shop.model and shop.model:FindFirstChild("Point_pickup", true)
			if pt then
				pt:SetAttribute("Bell", now())
			end
		end
	end)
	return { ok = true, number = n, msg = string.format("주문 완료! 주문 번호 %d번 (%s)", n, if prepaid then "결제 완료" else "식사 후 계산") }
end

local function pickup(p: Player, shop: any)
	local s = sessions[p]
	local orderShopOk = s and (s.shopId == shop.id or (shop.data.orderShop and s.shopId == shop.data.orderShop))
	if not s or not s.order or not orderShopOk then
		Registry.toast(p, "주문 내역이 없어요. 먼저 주문해요", "warn")
		return
	end
	if not s.ready then
		Registry.toast(p, string.format("%d번 손님, 조금만 기다려 주세요! (%d초)", s.number or 0, math.max(1, math.ceil((s.readyAt or 0) - os.clock()))), "info")
		return
	end
	local it = s.order
	s.order = nil
	s.ready = false
	if shop.kind == "cafe" then
		setDisplay(shop, "주문 번호\n—")
		services.Interact.give(p, {
			id = it.id,
			label = it.name,
			kind = if it.cup == "plate" then "food" else "drink",
			color = it.color,
			effect = it.effect,
			stats = it.stats,
			onEat = function(pl: Player)
				services.Interact.give(pl, { id = "empty_cup", label = "빈 컵 (반납대에 반납)", kind = "drink", color = { 230, 230, 230 }, edible = false })
			end,
		})
		Registry.toast(p, "☕ " .. it.name .. " 나왔습니다! 자리에서 즐겨요", "ok")
	else
		services.Interact.give(p, { id = it.id, label = it.name, kind = "tray", color = { 246, 240, 226 }, effect = it.effect, stats = it.stats, mustSit = true })
		Registry.toast(p, "🍲 " .. it.name .. " 받았어요! 빈 자리에 앉아서 먹어요", "ok")
	end
end

local function payBill(p: Player, shop: any): any
	local s = sessions[p]
	if not s or s.bill <= 0 then
		return { ok = false, msg = "계산할 금액이 없어요" }
	end
	local billShop = s.billShop and Registry.shop(s.billShop)
	local label = payLabel(billShop or shop)
	local ok, msg = services.Economy.spend(p, s.bill, label)
	if not ok then
		return { ok = false, msg = msg }
	end
	local paid = s.bill
	s.bill = 0
	s.billShop = nil
	-- release a BBQ table
	if s.tableKey then
		local t = bbqTables[s.tableKey]
		if t and t.player == p then
			for _, pc in t.pieces do
				if pc.part then
					pc.part:Destroy()
				end
			end
			bbqTables[s.tableKey] = nil
		end
		s.tableKey = nil
	end
	return { ok = true, msg = string.format("%s 결제 완료. 맛있게 드셨어요? 또 오세요!", Util.won(paid)) }
end

-------------------------------------------------------------------------------------------------
-- 고깃집 (BBQ): table sessions, meat pieces, grilling simulation
-------------------------------------------------------------------------------------------------
local function tableModel(shop: any, tableId: number): Model?
	if not shop.model then
		return nil
	end
	for _, d in shop.model:GetDescendants() do
		if d:IsA("Model") and d.Name == "Table_" .. tableId and d:GetAttribute("ShopId") == shop.id then
			return d
		end
	end
	return nil
end

local RAW_C = Color3.fromRGB(238, 170, 170)
local DONE_C = Color3.fromRGB(176, 104, 56)
local BURNT_C = Color3.fromRGB(40, 28, 22)

local function meatColor(def: any, cook: number): Color3
	local raw = Kit.col(def.raw or { 238, 170, 170 })
	if cook < 1 then
		return raw:Lerp(DONE_C, math.clamp(cook, 0, 1))
	end
	return DONE_C:Lerp(BURNT_C, math.clamp((cook - 1) / 0.8, 0, 1))
end

local function bbqSit(p: Player, shop: any, point: BasePart)
	local tableId = point:GetAttribute("TableId")
	local key = shop.id .. ":" .. tostring(tableId)
	local t = bbqTables[key]
	if t and t.player ~= p and t.player.Parent then
		Registry.toast(p, "이미 다른 손님이 쓰는 테이블이에요", "warn")
		return
	end
	local s = sessionFor(p, shop)
	if s.tableKey and s.tableKey ~= key and bbqTables[s.tableKey] then
		Registry.toast(p, "이미 다른 테이블을 쓰고 있어요", "warn")
		return
	end
	local tm = tableModel(shop, tableId)
	if not tm then
		return
	end
	if not t then
		t = { player = p, pieces = {}, model = tm, shop = shop, tableId = tableId, nextId = 0 }
		bbqTables[key] = t
	end
	s.tableKey = key
	s.shopId = shop.id
	s.kind = "bbq"
	s.billShop = shop.data.payShop or shop.id
	services.Interact.sitOn(p, tm, nil)
	Registry.fire(p, "shop.open", { view = "bbq", shopId = shop.id, tableId = tableId, table = tm, menu = Menus.BBQ, bill = s.bill })
end

local function bbqPieceState(t: any): { any }
	local out = {}
	for id, pc in t.pieces do
		table.insert(out, { id = id, meat = pc.meat, name = pc.name, a = math.floor(pc.a * 100) / 100, b = math.floor(pc.b * 100) / 100, grill = pc.grill ~= nil, flipped = pc.flipped })
	end
	table.sort(out, function(x, y)
		return x.id < y.id
	end)
	return out
end

local function bbqPush(t: any)
	if t.player and t.player.Parent then
		local s = sessions[t.player]
		Registry.fire(t.player, "bbq.state", { pieces = bbqPieceState(t), bill = s and s.bill or 0 })
	end
end

local function placePiece(t: any, pc: any)
	local tm = t.model :: Model
	local part = pc.part
	if not part then
		return
	end
	if pc.grill then
		local center = tm:FindFirstChild("GrillCenter") :: BasePart?
		if center then
			local a = math.rad(pc.grill * 60)
			part.CFrame = center.CFrame * CFrame.new(math.cos(a) * 0.75, 0.08, math.sin(a) * 0.75) * CFrame.Angles(if pc.flipped then math.pi else 0, a, 0)
		end
	else
		local plate = tm:FindFirstChild("MeatPlate") :: BasePart?
		if plate then
			local k = pc.slot or 0
			part.CFrame = plate.CFrame * CFrame.new(((k % 3) - 1) * 0.35, 0.05 + math.floor(k / 3) * 0.12, 0) * CFrame.Angles(0, math.rad(20 * (k % 3)), 0)
		end
	end
	local up = if pc.flipped then pc.a else pc.b -- the side facing up is the one NOT on the grate
	part.Color = meatColor(pc.def, up)
end

local function bbqServe(t: any, def: any, qty: number)
	local n = Config.BBQ_PIECES * qty
	local slot = 0
	for _, pc in t.pieces do
		if not pc.grill then
			slot += 1
		end
	end
	for _ = 1, n do
		t.nextId += 1
		local id = t.nextId
		local part = Kit.part(t.model, CFrame.new(), Vector3.new(0.9, 0.12, 0.42), "SmoothPlastic", def.raw, { collide = false, name = "Meat_" .. id })
		part.CanQuery = true
		part:SetAttribute("PieceId", id)
		part:SetAttribute("MeatId", def.id)
		Kit.part(t.model, CFrame.new(), Vector3.new(0.9, 0.13, 0.1), "SmoothPlastic", def.fat or { 250, 236, 230 }, { collide = false, name = "Fat_" .. id })
		local fat = t.model:FindFirstChild("Fat_" .. id) :: BasePart
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = fat
		w.Parent = fat
		fat.Anchored = false
		fat.Massless = true
		local pc = { def = def, meat = def.id, name = def.name, a = 0, b = 0, grill = nil, flipped = false, part = part, slot = slot }
		slot += 1
		t.pieces[id] = pc
		placePiece(t, pc)
		fat.CFrame = part.CFrame * CFrame.new(0, 0.005, 0.16)
	end
	bbqPush(t)
end

local function grillSlotFree(t: any): number?
	local used = {}
	for _, pc in t.pieces do
		if pc.grill then
			used[pc.grill] = true
		end
	end
	for i = 0, 5 do
		if not used[i] then
			return i
		end
	end
	return nil
end

local function bbqAction(p: Player, d: any): any
	local s = sessions[p]
	local t = s and s.tableKey and bbqTables[s.tableKey]
	if not t or t.player ~= p then
		return { ok = false, msg = "테이블에 앉아서 해요" }
	end
	local pc = t.pieces[tonumber(d.piece) or -1]
	if d.action == "order" then
		local qty = math.clamp(math.floor(tonumber(d.qty) or 1), 1, 3)
		local it = find(Menus.BBQ, d.item)
		if not it then
			return { ok = false }
		end
		s.bill += it.price * qty
		if it.meat then
			Registry.toast(p, "주문 들어갑니다! " .. it.name .. " x" .. qty, "info")
			task.delay(Config.BBQ_SERVE, function()
				if bbqTables[s.tableKey or ""] == t then
					bbqServe(t, it, qty)
					Registry.toast(p, "🥩 고기 나왔습니다! 불판에 올려 구워요", "ok")
				end
			end)
		else
			task.delay(3, function()
				if p.Parent then
					services.Needs.apply(p, it.effect, it.stats, it.name)
					Registry.toast(p, "🍚 " .. it.name .. " 나왔어요 (바로 먹었어요)", "ok")
				end
			end)
		end
		bbqPush(t)
		return { ok = true, bill = s.bill }
	end
	if not pc then
		return { ok = false }
	end
	if d.action == "grill" then
		if pc.grill then
			pc.grill = nil
			local slot = 0
			for _, q in t.pieces do
				if not q.grill and q ~= pc then
					slot += 1
				end
			end
			pc.slot = slot
		else
			local slot = grillSlotFree(t)
			if not slot then
				return { ok = false, msg = "불판이 가득 찼어요" }
			end
			pc.grill = slot
		end
		placePiece(t, pc)
	elseif d.action == "flip" then
		if not pc.grill then
			return { ok = false, msg = "불판 위의 고기만 뒤집을 수 있어요" }
		end
		pc.flipped = not pc.flipped
		placePiece(t, pc)
		pc.part:SetAttribute("Flip", now())
	elseif d.action == "eat" then
		if pc.a < 0.6 or pc.b < 0.6 then
			return { ok = false, msg = "아직 덜 익었어요! 양면 다 노릇하게 구워요" }
		end
		local burnt = pc.a > 1.6 or pc.b > 1.6
		pc.part:Destroy()
		local fat = t.model:FindFirstChild("Fat_" .. tostring(d.piece))
		if fat then
			fat:Destroy()
		end
		t.pieces[tonumber(d.piece) :: number] = nil
		if burnt then
			services.Needs.apply(p, { Satiety = 3, Fun = -2 }, nil, "탄 고기")
			Registry.toast(p, "😖 너무 탔어요… 쓴맛", "warn")
		else
			services.Needs.apply(p, pc.def.effect, pc.def.stats, pc.name)
			local perfect = math.abs(pc.a - 1) < 0.25 and math.abs(pc.b - 1) < 0.25
			Registry.fire(p, "fx", { kind = "eat", label = if perfect then "완벽하게 구웠다! 😋" else "맛있다!" })
		end
	end
	bbqPush(t)
	return { ok = true }
end

local function bbqTick(dt: number)
	for _, t in bbqTables do
		local any = false
		for _, pc in t.pieces do
			if pc.grill then
				any = true
				local rate = Config.BBQ_COOK_RATE * dt
				if pc.flipped then
					pc.b += rate
				else
					pc.a += rate
				end
				placePiece(t, pc)
			end
		end
		local grate = t.model and t.model:FindFirstChild("Grate")
		if grate then
			grate:SetAttribute("Sizzle", any)
			for _, a in grate:GetChildren() do
				if a:IsA("Attachment") then
					a:SetAttribute("Active", any)
				end
			end
		end
		if any then
			t.pushAcc = (t.pushAcc or 0) + dt
			if t.pushAcc > 1 then
				t.pushAcc = 0
				bbqPush(t)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- 노래방 / 당구장 / PC방 / 호텔: rentals
-------------------------------------------------------------------------------------------------
local function rent(p: Player, key: string, seconds: number, kind: string, extra: any?)
	local r = { player = p, untilT = os.clock() + seconds, kind = kind }
	if extra then
		for k, v in extra do
			r[k] = v
		end
	end
	rentals[key] = r
	return r
end

local function rentalOf(key: string): any?
	local r = rentals[key]
	if r and (os.clock() > r.untilT or not r.player.Parent) then
		rentals[key] = nil
		return nil
	end
	return r
end

function ShopFlows.canEnterRoom(p: Player, key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	local r = rentalOf(key)
	if r and r.player == p then
		return true
	end
	local b = hotelBooks[key]
	if b and b.player == p and os.clock() < b.untilT then
		return true
	end
	-- an empty hotel room / karaoke room may be looked at by staff only
	return false
end

local function karaokeOrder(p: Player, shop: any, itemId: any): any
	local it = find(Menus.KARAOKE_ROOMS, itemId)
	if not it then
		return { ok = false }
	end
	for _, r in shop.data.rooms or {} do
		local key = shop.id .. ":" .. r.no
		local cur = rentalOf(key)
		if cur and cur.player == p then
			return { ok = false, msg = r.no .. "번방을 이미 쓰고 있어요" }
		end
	end
	local pick = nil
	for _, r in shop.data.rooms or {} do
		if not rentalOf(shop.id .. ":" .. r.no) then
			pick = r
			break
		end
	end
	if not pick then
		return { ok = false, msg = "빈 방이 없어요. 잠시 후 다시 와 주세요" }
	end
	local ok, msg = services.Economy.spend(p, it.price, payLabel(shop))
	if not ok then
		return { ok = false, msg = msg }
	end
	rent(p, shop.id .. ":" .. pick.no, it.seconds, "karaoke", { shop = shop, room = pick })
	if services.Streaming then
		services.Streaming.hold(shop.rec, shop.fl, it.seconds)
	end
	Registry.fire(p, "waypoint", { label = pick.no .. "번방", shopId = shop.id, roomNo = pick.no })
	return { ok = true, msg = string.format("🎤 %d번방으로 가세요! (%s)", pick.no, Util.clock(it.seconds)) }
end

local function karaokeScreen(shop: any, no: number): BasePart?
	if not shop.model then
		return nil
	end
	for _, d in shop.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "KaraokeScreen" and d:GetAttribute("RoomNo") == no then
			return d
		end
	end
	return nil
end

local function karaokeSong(p: Player, shop: any, no: number, songNo: number): any
	local r = rentalOf(shop.id .. ":" .. no)
	if not r or r.player ~= p then
		return { ok = false, msg = "이 방을 빌리지 않았어요" }
	end
	local song = nil
	for _, s in Menus.SONGS do
		if s.no == songNo then
			song = s
		end
	end
	if not song then
		return { ok = false }
	end
	local scr = karaokeScreen(shop, no)
	if not scr then
		return { ok = false, msg = "화면을 찾을 수 없어요" }
	end
	local beat = 60 / song.bpm
	local length = #song.lines * 8 * beat + 6
	scr:SetAttribute("SongNo", song.no)
	scr:SetAttribute("SongT0", now() + 3)
	scr:SetAttribute("SongLen", length)
	scr:SetAttribute("On", true)
	local props = scr.Parent
	if props then
		for _, d in props:GetDescendants() do
			if d:IsA("BasePart") and CollectionService:HasTag(d, "GwB_Spin") then
				d:SetAttribute("Rpm", 24)
			elseif d:IsA("Light") and d:GetAttribute("RoomNo") == no then
				d.Enabled = true
			elseif d:IsA("Attachment") and d:GetAttribute("SoundKey") then
				d:SetAttribute("Active", true)
			end
		end
	end
	local token = {}
	r.song = token
	task.delay(length + 3, function()
		if r.song ~= token then
			return
		end
		scr:SetAttribute("On", false)
		if props then
			for _, d in props:GetDescendants() do
				if d:IsA("BasePart") and CollectionService:HasTag(d, "GwB_Spin") then
					d:SetAttribute("Rpm", 0)
				elseif d:IsA("Attachment") and d:GetAttribute("SoundKey") then
					d:SetAttribute("Active", false)
				end
			end
		end
		local held = services.Interact.held(p)
		local score = math.random(72, 92) + (if held and held.id == "mic" then 8 else 0)
		score = math.min(100, score)
		scr:SetAttribute("Score", score)
		scr:SetAttribute("ScoreT", now())
		services.Needs.apply(p, { Fun = 15 + math.floor(score / 10) }, { happiness = 1 }, "노래 한 곡")
		Registry.fire(p, "fx", { kind = "score", label = string.format("🎤 %d점! %s", score, if score >= 95 then "가수 데뷔각!" elseif score >= 85 then "잘 불렀어요!" else "분위기 최고!") })
	end)
	return { ok = true, msg = "🎶 " .. song.title .. " - " .. song.artist }
end

local function billiardsRent(p: Player, shop: any, itemId: any): any
	local it = find(Menus.BILLIARDS, itemId) or Menus.BILLIARDS[1]
	local pick = nil
	for _, d in shop.model and shop.model:GetDescendants() or {} do
		if d:IsA("Model") and string.sub(d.Name, 1, 14) == "BilliardTable_" then
			local key = shop.id .. ":t" .. tostring(d:GetAttribute("TableId"))
			local cur = rentalOf(key)
			if cur and cur.player == p then
				return { ok = false, msg = "이미 테이블을 빌렸어요" }
			end
			if not cur and not pick then
				pick = d
			end
		end
	end
	if not pick then
		return { ok = false, msg = "빈 테이블이 없어요" }
	end
	local ok, msg = services.Economy.spend(p, it.price, payLabel(shop))
	if not ok then
		return { ok = false, msg = msg }
	end
	local key = shop.id .. ":t" .. tostring(pick:GetAttribute("TableId"))
	rent(p, key, it.seconds, "billiards", { shop = shop, table = pick })
	billiardSims[key] = Billiards.new()
	services.Interact.give(p, { id = "cue", label = "당구 큐", kind = "cue", edible = false })
	if services.Streaming then
		services.Streaming.hold(shop.rec, shop.fl, it.seconds)
	end
	return { ok = true, msg = string.format("🎱 %s번 테이블! 테이블에서 '샷 하기'", tostring(pick:GetAttribute("TableId"))) }
end

local function billiardsShot(p: Player, shop: any, tableId: number, angle: number, power: number): any
	local key = shop.id .. ":t" .. tostring(tableId)
	local r = rentalOf(key)
	if not r or r.player ~= p then
		return { ok = false, msg = "대여한 테이블이 아니에요" }
	end
	if r.busyUntil and os.clock() < r.busyUntil then
		return { ok = false, msg = "공이 아직 굴러가요" }
	end
	local sim = billiardSims[key] or Billiards.new()
	billiardSims[key] = sim
	local frames, result = Billiards.shoot(sim, 1, angle, math.clamp(power, 0, 1))
	local tm = r.table :: Model
	local dur = frames[#frames][1]
	r.busyUntil = os.clock() + dur + 0.3
	local hits = {}
	for k, v in result.hits do
		table.insert(hits, k)
	end
	for _, pl in Players:GetPlayers() do
		if Registry.near(pl, tm:GetPivot().Position, 90) then
			Registry.fire(pl, "billiards", { table = tm, frames = frames, score = result.score, total = sim.score, shots = sim.shots, foul = result.foul })
		end
	end
	task.delay(dur + 0.2, function()
		local center = tm:FindFirstChild("TableCenter") :: BasePart?
		if center then
			for b, ball in sim.balls do
				local bp = tm:FindFirstChild("Ball" .. b) :: BasePart?
				if bp then
					bp.CFrame = center.CFrame * CFrame.new(ball.x, Billiards.R, ball.z)
				end
			end
		end
		for _, d in tm:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Scoreboard") then
				local g = d:FindFirstChildWhichIsA("SurfaceGui")
				local t = g and g:FindFirstChildWhichIsA("TextLabel")
				if t then
					t.Text = string.format("%s번 테이블\n%d 점 / %d 샷", tostring(tableId), sim.score, sim.shots)
				end
			end
		end
		if result.score > 0 then
			services.Needs.apply(p, { Fun = 6 }, { happiness = 0.3 }, "4구 득점")
		end
	end)
	return { ok = true, score = result.score, total = sim.score, foul = result.foul, reds = result.reds }
end

local function pcOrder(p: Player, shop: any, itemId: any): any
	local t = find(Menus.PC_TICKETS, itemId)
	local s = sessionFor(p, shop)
	if t then
		local ok, msg = services.Economy.spend(p, t.price, payLabel(shop))
		if not ok then
			return { ok = false, msg = msg }
		end
		s.pcTime += t.minutes * Config.PC_MINUTES_PER_TICKET * 60
		p:SetAttribute("GwB_PcTime", s.pcTime)
		return { ok = true, msg = string.format("🎮 이용권 충전! 남은 시간 %s · 빈 자리에 앉아요", Util.clock(s.pcTime)) }
	end
	return placeOrder(p, shop, Menus.PC_FOOD, itemId, true, 15)
end

local function pcSit(p: Player, shop: any, point: BasePart)
	local s = sessionFor(p, shop)
	local seatNo = point:GetAttribute("SeatNo")
	local seat = nil
	for _, d in (point.Parent :: Instance):GetChildren() do
		if d:IsA("Seat") and d:GetAttribute("SeatNo") == seatNo then
			seat = d
		end
	end
	if seat and seat.Occupant and seat.Occupant.Parent ~= p.Character then
		Registry.toast(p, "다른 손님이 사용 중인 자리예요", "warn")
		return
	end
	if seat then
		local _, _, hum = Registry.char(p)
		if hum then
			seat.Disabled = false
			seat:Sit(hum)
			local conn
			conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				if seat.Occupant == nil then
					seat.Disabled = true
					if s.pcSeat == seatNo then
						s.pcSeat = nil
					end
					conn:Disconnect()
				end
			end)
		end
	end
	if s.pcTime <= 0 then
		Registry.toast(p, "카운터에서 이용권을 먼저 구매해요 (1시간 1,500원)", "warn")
		return
	end
	s.pcSeat = seatNo
	-- the monitor of that seat shows the login screen for everybody
	for _, d in shop.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Monitor" and d:GetAttribute("SeatNo") == seatNo then
			d:SetAttribute("On", true)
			d:SetAttribute("User", p.DisplayName)
		end
	end
	Registry.fire(p, "pc.open", { shopId = shop.id, seatNo = seatNo, remaining = s.pcTime })
end

local function hotelFree(rec: any, template: string): any?
	for _, u in rec.unitList do
		if u.template == template then
			local b = hotelBooks[u.id]
			if not b or os.clock() > b.untilT or not b.player.Parent then
				hotelBooks[u.id] = nil
				return u
			end
		end
	end
	return nil
end

local function hotelCheckin(p: Player, shop: any, roomType: any): any
	local MAP = { standard = "hotel_standard", deluxe = "hotel_deluxe", suite = "hotel_suite" }
	local it = find(Menus.HOTEL_ROOMS, roomType)
	if not it or not MAP[it.id] then
		return { ok = false }
	end
	for id, b in hotelBooks do
		if b.player == p and os.clock() < b.untilT then
			return { ok = false, msg = "이미 " .. (Registry.unit(id) and Registry.unit(id).label or "") .. "에 체크인했어요" }
		end
	end
	local u = hotelFree(shop.rec, MAP[it.id])
	if not u then
		return { ok = false, msg = "죄송합니다, 그 객실은 만실이에요" }
	end
	local ok, msg = services.Economy.spend(p, it.price, payLabel(shop) .. " · " .. it.name)
	if not ok then
		return { ok = false, msg = msg }
	end
	hotelBooks[u.id] = { player = p, untilT = os.clock() + Config.HOTEL_STAY_SECONDS }
	p:SetAttribute("GwB_HotelRoom", u.id)
	p:SetAttribute("GwB_HotelLabel", u.label)
	services.Interact.give(p, { id = "keycard", label = "카드키 " .. u.number .. "호", kind = "card", edible = false })
	Registry.fire(p, "waypoint", { label = u.number .. "호", unitId = u.id })
	return { ok = true, msg = string.format("🏨 %s 체크인 완료! %s층 %s호 · 엘리베이터를 이용하세요", it.name, u.floor, u.number) }
end

local function hotelCheckout(p: Player): any
	for id, b in hotelBooks do
		if b.player == p then
			hotelBooks[id] = nil
		end
	end
	p:SetAttribute("GwB_HotelRoom", nil)
	p:SetAttribute("GwB_HotelLabel", nil)
	local held = services.Interact.held(p)
	if held and held.id == "keycard" then
		services.Interact.drop(p)
	end
	return { ok = true, msg = "체크아웃 완료. 또 방문해 주세요!" }
end

-------------------------------------------------------------------------------------------------
-- points -> prompts
-------------------------------------------------------------------------------------------------
local POINT_TEXT = {
	cvs = { product = "담기", pay = "계산하기" },
	gukbap = { order = "주문하기 (키오스크)", pickup = "음식 받기", pay = "계산하기", table = "자리에 앉기" },
	bbq = { table = "테이블 앉기", pay = "계산하기" },
	cafe = { order = "주문하기", pickup = "음료 받기", ["return"] = "빈 컵 반납", table = "자리에 앉기" },
	pcbang = { counter = "이용권 · 음식 주문", pc = "자리 앉기 / 로그인" },
	karaoke = { counter = "노래방 결제", remote = "노래 선택 (리모컨)", mic = "마이크 잡기" },
	billiards = { counter = "테이블 대여", table = "샷 하기" },
	realtor = { realtor = "매물 상담" },
	hotel_lobby = { frontdesk = "체크인 / 체크아웃" },
	office = { office = "관리사무소 안내" },
}

local function onPoint(p: Player, point: BasePart)
	local shop = shopOf(point)
	if not shop or not point:IsDescendantOf(workspace) then
		return
	end
	if not Registry.near(p, point, 12) then
		return
	end
	local kind = shop.kind
	local pk = point:GetAttribute("Point")
	if kind == "cvs" then
		if pk == "product" then
			cvsPick(p, shop, point)
		elseif pk == "pay" then
			cvsPayOpen(p, shop)
		end
	elseif kind == "gukbap" then
		if pk == "order" then
			Registry.fire(p, "shop.open", { view = "menu", shopId = shop.id, title = shop.name, menu = Menus.GUKBAP, note = "식사 후 계산 (후불)", action = "order" })
		elseif pk == "pickup" then
			pickup(p, shop)
		elseif pk == "pay" then
			local s = sessions[p]
			Registry.fire(p, "shop.open", { view = "receipt", shopId = shop.id, title = shop.name, total = s and s.bill or 0, items = {}, action = "payBill" })
		elseif pk == "table" then
			local tm = point.Parent
			if tm then
				services.Interact.sitOn(p, tm, nil)
			end
		end
	elseif kind == "bbq" then
		if pk == "table" then
			bbqSit(p, shop, point)
		elseif pk == "pay" then
			local s = sessions[p]
			Registry.fire(p, "shop.open", { view = "receipt", shopId = shop.id, title = shop.name, total = s and s.bill or 0, items = {}, action = "payBill" })
		end
	elseif kind == "cafe" then
		local orderShop = if shop.data.orderShop then Registry.shop(shop.data.orderShop) else shop
		if pk == "order" then
			Registry.fire(p, "shop.open", { view = "menu", shopId = orderShop.id, title = orderShop.name, menu = Menus.CAFE, note = "선불 · 진동벨로 알려드려요", action = "order" })
		elseif pk == "pickup" then
			pickup(p, shop)
		elseif pk == "return" then
			local held = services.Interact.held(p)
			if held and held.id == "empty_cup" then
				services.Interact.drop(p)
				services.Needs.apply(p, { Fun = 1 }, { happiness = 0.2 }, "컵 반납")
				Registry.toast(p, "감사합니다 :) 또 오세요!", "ok")
			else
				Registry.toast(p, "다 마신 컵을 반납하는 곳이에요", "info")
			end
		elseif pk == "table" then
			local tm = point.Parent
			if tm then
				services.Interact.sitOn(p, tm, nil)
				local s = sessionFor(p, shop)
				s.cafeSeatT = os.clock()
				Registry.fire(p, "cafe.seat", { shopId = shop.id })
			end
		end
	elseif kind == "pcbang" then
		if pk == "counter" then
			local list = {}
			for _, t in Menus.PC_TICKETS do
				table.insert(list, t)
			end
			for _, f in Menus.PC_FOOD do
				table.insert(list, f)
			end
			local s = sessions[p]
			Registry.fire(p, "shop.open", { view = "menu", shopId = shop.id, title = shop.name, menu = list, note = "남은 시간 " .. Util.clock(s and s.pcTime or 0), action = "order" })
		elseif pk == "pc" then
			pcSit(p, shop, point)
		end
	elseif kind == "karaoke" then
		if pk == "counter" then
			Registry.fire(p, "shop.open", { view = "menu", shopId = shop.id, title = shop.name, menu = Menus.KARAOKE_ROOMS, note = "결제하면 빈 방 문이 열려요", action = "order" })
		elseif pk == "remote" then
			local no = point:GetAttribute("RoomNo")
			local r = rentalOf(shop.id .. ":" .. tostring(no))
			if not r or r.player ~= p then
				Registry.toast(p, "카운터에서 방을 먼저 결제해요", "warn")
				return
			end
			Registry.fire(p, "shop.open", { view = "songs", shopId = shop.id, roomNo = no, songs = Menus.SONGS, remaining = math.max(0, r.untilT - os.clock()) })
		elseif pk == "mic" then
			services.Interact.give(p, { id = "mic", label = "마이크", kind = "mic", edible = false })
		end
	elseif kind == "billiards" then
		if pk == "counter" then
			Registry.fire(p, "shop.open", { view = "menu", shopId = shop.id, title = shop.name, menu = Menus.BILLIARDS, note = "4구 · 흰 공으로 빨간 공 두 개를 맞히면 1점", action = "order" })
		elseif pk == "table" then
			local tid = point:GetAttribute("TableId")
			local r = rentalOf(shop.id .. ":t" .. tostring(tid))
			if not r or r.player ~= p then
				Registry.toast(p, "카운터에서 테이블을 먼저 대여해요", "warn")
				return
			end
			Registry.fire(p, "shop.open", { view = "billiards", shopId = shop.id, tableId = tid, table = r.table, remaining = math.max(0, r.untilT - os.clock()) })
		end
	elseif kind == "realtor" then
		if services.Housing then
			services.Housing.openRealtor(p, nil)
		end
	elseif kind == "office" then
		if services.Housing then
			services.Housing.openRealtor(p, shop.rec.id)
		end
	elseif kind == "hotel_lobby" then
		local booked = p:GetAttribute("GwB_HotelRoom")
		Registry.fire(p, "shop.open", { view = "hotel", shopId = shop.id, title = shop.name, menu = Menus.HOTEL_ROOMS, booked = booked, bookedLabel = p:GetAttribute("GwB_HotelLabel") })
	end
end

local function register(point: Instance)
	if not point:IsA("BasePart") or points[point] then
		return
	end
	local shop = shopOf(point)
	local pk = point:GetAttribute("Point") :: string
	local kind = point:GetAttribute("ShopKind") :: string?
	local texts = POINT_TEXT[kind or (shop and shop.kind) or ""]
	local text = texts and texts[pk]
	if not text then
		return
	end
	if pk == "product" then
		local it = find(Menus.CVS, point:GetAttribute("ProductId"))
		if it then
			text = string.format("담기 · %s", Util.won(it.price))
		end
	end
	local obj = ""
	if pk == "product" then
		local it = find(Menus.CVS, point:GetAttribute("ProductId"))
		obj = it and it.name or ""
	elseif shop then
		obj = shop.name or ""
	end
	local pr = Kit.prompt(point, text, obj, { dist = Config.SHOP_PROMPT_DIST, name = "ShopPrompt" })
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	pr.Triggered:Connect(function(p)
		local ok, err = pcall(onPoint, p, point)
		if not ok then
			warn("[GwangalliBuildings] shop point: " .. tostring(err))
		end
	end)
	points[point] = { prompt = pr }
end

-------------------------------------------------------------------------------------------------
-- watchdog: dine & dash, unpaid goods, cafe seat bonus, PC time
-------------------------------------------------------------------------------------------------
local function watch(dt: number)
	for p, s in sessions do
		if not p.Parent then
			sessions[p] = nil
			continue
		end
		local shop = Registry.shop(s.shopId)
		if not shop then
			continue
		end
		-- unpaid goods leaving the convenience store
		if shop.kind == "cvs" and #s.cart > 0 and not inShop(p, shop, 3) then
			s.cart = {}
			services.Interact.drop(p)
			Registry.toast(p, "계산하지 않은 상품은 진열대에 다시 놓았어요", "warn")
		end
		-- 후불: leaving with an open bill
		if s.bill > 0 and Config.DINE_AND_DASH_RETURN then
			local billShop = Registry.shop(s.billShop or s.shopId) or shop
			local inside = inShop(p, shop, 3) or inShop(p, billShop, 3)
			if not inside then
				local t = os.clock()
				if t - s.dashWarned > 6 then
					s.dashWarned = t
					local pay = billShop.model and billShop.model:FindFirstChild("Point_pay", true)
					if pay and pay:IsA("BasePart") then
						Registry.teleport(p, pay.CFrame * CFrame.new(0, 0.5, -2.5))
					end
					Registry.toast(p, "🧑‍🍳 사장님: 손님! 계산은 하고 가셔야죠~ (" .. Util.won(s.bill) .. ")", "warn")
				end
			end
		end
		-- cafe seat bonus (60 s of 여유)
		if s.cafeSeatT and not s.cafeBonus and os.clock() - s.cafeSeatT > 60 then
			local _, _, hum = Registry.char(p)
			if hum and hum.Sit then
				s.cafeBonus = true
				services.Needs.apply(p, { Fun = 10, Energy = 5 }, { happiness = 0.5 }, "카페에서 여유")
			else
				s.cafeSeatT = nil
			end
		end
		-- PC time runs while logged in at a seat
		if s.pcSeat and s.pcTime > 0 then
			s.pcTime = math.max(0, s.pcTime - dt)
			p:SetAttribute("GwB_PcTime", s.pcTime)
			if s.pcTime <= 0 then
				Registry.toast(p, "⏰ 이용 시간이 끝났어요. 카운터에서 충전해요", "warn")
				Registry.fire(p, "pc.close", {})
				s.pcSeat = nil
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- API / lifecycle
-------------------------------------------------------------------------------------------------
function ShopFlows.busyFloor(rec: any, fl: any): boolean
	for _, s in sessions do
		local shop = Registry.shop(s.shopId)
		if shop and shop.rec == rec and shop.fl == fl and (s.bill > 0 or s.order ~= nil or #s.cart > 0 or s.tableKey ~= nil or s.pcSeat ~= nil) then
			return true
		end
	end
	for _, r in rentals do
		if r.shop and r.shop.rec == rec and r.shop.fl == fl and os.clock() < r.untilT then
			return true
		end
	end
	for id, b in hotelBooks do
		local u = Registry.unit(id)
		if u and u.rec == rec and u.fl == fl and os.clock() < b.untilT then
			return true
		end
	end
	return false
end

function ShopFlows.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	CollectionService:GetInstanceAddedSignal("GwB_ShopPoint"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("GwB_ShopPoint"):Connect(function(i)
		points[i] = nil
	end)
	for _, i in CollectionService:GetTagged("GwB_ShopPoint") do
		register(i)
	end
	Registry.on("shop.order", function(p: Player, d: any)
		local shop = Registry.shop(d.shopId)
		if not shop then
			return { ok = false }
		end
		if not inShop(p, shop, 10) then
			return { ok = false, msg = "가게 안에서 주문해요" }
		end
		if shop.kind == "gukbap" then
			return placeOrder(p, shop, Menus.GUKBAP, d.item, false, Config.GUKBAP_COOK)
		elseif shop.kind == "cafe" then
			return placeOrder(p, shop, Menus.CAFE, d.item, true, Config.CAFE_BREW)
		elseif shop.kind == "pcbang" then
			return pcOrder(p, shop, d.item)
		elseif shop.kind == "karaoke" then
			return karaokeOrder(p, shop, d.item)
		elseif shop.kind == "billiards" then
			return billiardsRent(p, shop, d.item)
		end
		return { ok = false }
	end)
	Registry.on("shop.pay", function(p: Player, d: any)
		local shop = Registry.shop(d.shopId)
		if not shop then
			return { ok = false }
		end
		if d.action == "cvsPay" then
			return cvsPay(p, shop)
		end
		if not inShop(p, shop, 6) then
			return { ok = false, msg = "계산대에서 결제해요" }
		end
		return payBill(p, shop)
	end)
	Registry.on("shop.bagTake", function(p: Player, d: any)
		return bagTake(p, tonumber(d.index) or 0)
	end)
	Registry.on("shop.bbq", function(p: Player, d: any)
		return bbqAction(p, d)
	end)
	Registry.on("shop.karaokeSong", function(p: Player, d: any)
		local shop = Registry.shop(d.shopId)
		if not shop then
			return { ok = false }
		end
		return karaokeSong(p, shop, tonumber(d.roomNo) or 0, tonumber(d.song) or 0)
	end)
	Registry.on("shop.billiardsShot", function(p: Player, d: any)
		local shop = Registry.shop(d.shopId)
		if not shop or type(d.angle) ~= "number" or type(d.power) ~= "number" then
			return { ok = false }
		end
		return billiardsShot(p, shop, tonumber(d.tableId) or 0, d.angle, d.power)
	end)
	Registry.on("shop.pcGame", function(p: Player, d: any)
		local s = sessions[p]
		if not s or not s.pcSeat then
			return { ok = false }
		end
		local score = math.clamp(tonumber(d.score) or 0, 0, 100)
		services.Needs.apply(p, { Fun = 6 + math.floor(score / 20), Energy = -2 }, { happiness = 0.2 }, "게임 한 판")
		return { ok = true }
	end)
	Registry.on("shop.hotel", function(p: Player, d: any)
		local shop = Registry.shop(d.shopId)
		if not shop or not inShop(p, shop, 8) then
			return { ok = false, msg = "프런트에서 이용해요" }
		end
		if d.action == "checkout" then
			return hotelCheckout(p)
		end
		return hotelCheckin(p, shop, d.room)
	end)
	Registry.on("shop.bag", function(p: Player)
		local s = sessions[p]
		return { ok = true, bag = s and s.bag or {} }
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = sessions[p]
		if s and s.tableKey then
			local t = bbqTables[s.tableKey]
			if t then
				for _, pc in t.pieces do
					if pc.part then
						pc.part:Destroy()
					end
				end
				bbqTables[s.tableKey] = nil
			end
		end
		sessions[p] = nil
		for k, r in rentals do
			if r.player == p then
				rentals[k] = nil
			end
		end
		for k, b in hotelBooks do
			if b.player == p then
				hotelBooks[k] = nil
			end
		end
	end)
end

function ShopFlows.start()
	local acc = 0
	while true do
		local dt = task.wait(0.5)
		pcall(bbqTick, dt)
		acc += dt
		if acc >= 1 then
			pcall(watch, acc)
			acc = 0
		end
	end
end

return ShopFlows
