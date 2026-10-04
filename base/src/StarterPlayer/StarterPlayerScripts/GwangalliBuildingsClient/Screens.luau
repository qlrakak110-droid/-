-- Screens: every sheet / chip the server asks for through events.
--   toast, money, needs.delta, timer, fx, pose, waypoint
--   shop.open (menu / receipt / hotel / songs / bbq / billiards), shop.ready, cafe.seat, bag
--   menu (fridge), wallpad, pc.open
--   home.listings (부동산 · 분양 사무소), home.update, home.ring
-- plus the HOLD chip (먹기 / 버리기) driven by the player's GwB_Hold* attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Util = Shared.Util
local UI = require(script.Parent:WaitForChild("UI"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local Screens = {}

local player = Players.LocalPlayer
local C = UI.C
local won = Util.won

-------------------------------------------------------------------------------------------------
-- shop sheets
-------------------------------------------------------------------------------------------------
local function menuSheet(d: any)
	local s = UI.sheet({ title = d.title or "메뉴", sub = d.note, h = 420, kind = "shop" })
	for _, it in d.menu or {} do
		local sub = it.desc
		if not sub and it.minutes then
			sub = string.format("PC 이용 %d분", math.floor(it.minutes * Config.PC_MINUTES_PER_TICKET + 0.5))
		elseif not sub and it.seconds then
			sub = "이용 시간 " .. Util.clock(it.seconds)
		end
		UI.row(s.body, {
			title = it.name,
			sub = sub,
			right = if it.price and it.price > 0 then won(it.price) else "무료",
			onClick = function()
				Sfx.ui("tap")
				local res = Net.call("shop.order", { shopId = d.shopId, item = it.id })
				if res.ok then
					Sfx.ui("success")
					if not d.keepOpen then
						s.close()
					end
				else
					Sfx.ui("error")
				end
			end,
		})
	end
end

local function receiptSheet(d: any)
	local s = UI.sheet({ title = "🧾 " .. (d.title or "계산"), sub = "영수증", h = 400, footer = true, kind = "shop" })
	local total = tonumber(d.total) or 0
	local counts: { [string]: { name: string, n: number, price: number } } = {}
	local orderList = {}
	for _, it in d.items or {} do
		local key = if type(it) == "table" then (it.id or it.name) else tostring(it)
		local name = if type(it) == "table" then (it.name or key) else key
		local price = if type(it) == "table" then (tonumber(it.price) or 0) else 0
		if not counts[key] then
			counts[key] = { name = name, n = 0, price = price }
			table.insert(orderList, key)
		end
		counts[key].n += 1
	end
	for _, k in orderList do
		local c = counts[k]
		UI.row(s.body, { title = c.name .. (if c.n > 1 then " × " .. c.n else ""), right = won(c.price * c.n), h = 40 })
	end
	if #orderList == 0 then
		UI.label(s.body, "주문하신 내역", { color = C.sub, size = 14 })
	end
	UI.row(s.body, { title = "합계", right = won(total), accent = true, h = 46 })
	UI.button(s.footer, "💳 " .. won(total) .. " 결제", function()
		local res = Net.call("shop.pay", { shopId = d.shopId, action = d.action })
		if res.ok then
			Sfx.ui("money")
			s.close()
		else
			Sfx.ui("error")
		end
	end, { style = "ok", size = UDim2.new(0.62, 0, 0, 48) })
	UI.button(s.footer, "취소", function()
		s.close()
	end, { style = "ghost", size = UDim2.new(0.34, 0, 0, 48) })
end

local function hotelSheet(d: any)
	local s = UI.sheet({ title = "🏨 " .. (d.title or "프런트"), sub = "체크인 · 체크아웃", h = 420, kind = "shop" })
	if d.booked then
		UI.row(s.body, { title = "투숙 중: " .. tostring(d.bookedLabel or d.booked), sub = "객실 카드키가 휴대폰에 등록되어 있어요", icon = "🔑", accent = true })
		UI.button(s.body, "체크아웃", function()
			local res = Net.call("shop.hotel", { shopId = d.shopId, action = "checkout" })
			if res.ok then
				s.close()
			end
		end, { style = "ghost" })
	end
	for _, it in d.menu or {} do
		UI.row(s.body, {
			title = it.name,
			sub = it.desc,
			right = won(it.price),
			icon = "🛏️",
			onClick = function()
				local res = Net.call("shop.hotel", { shopId = d.shopId, room = it.id })
				if res.ok then
					Sfx.ui("success")
					s.close()
				end
			end,
		})
	end
end

local function songsSheet(d: any)
	local s = UI.sheet({ title = "🎤 " .. tostring(d.roomNo or "") .. "번방 노래방", sub = "남은 시간 " .. Util.clock(tonumber(d.remaining) or 0), h = 420, kind = "shop" })
	for _, song in d.songs or {} do
		UI.row(s.body, {
			title = string.format("%d  %s", song.no or 0, song.title or ""),
			sub = song.artist,
			icon = "🎵",
			onClick = function()
				local res = Net.call("shop.karaokeSong", { shopId = d.shopId, roomNo = d.roomNo, song = song.no })
				if res.ok then
					s.close()
				end
			end,
		})
	end
end

-------------------------------------------------------------------------------------------------
-- 부동산 (realtor) · 분양 사무소
-------------------------------------------------------------------------------------------------
local realtor: any = nil -- { data, tier }

local function tierIndex(tiers: { any }, id: string?): number
	for i, t in tiers do
		if t.id == id then
			return i
		end
	end
	return 0
end

local openListings: (any, number?) -> ()

local function listingDetail(l: any, back: () -> ())
	local s = UI.sheet({ title = string.format("%s %s", l.building, l.number), sub = string.format("%s · %s", l.name, l.type), h = 430, footer = true, kind = "home" })
	UI.row(s.body, { title = "매매가", right = won(l.price), icon = "💰", accent = true })
	UI.row(s.body, { title = "전용면적", right = tostring(l.area), icon = "📐" })
	UI.row(s.body, { title = "방 / 욕실", right = string.format("방 %d · 욕실 %d", l.rooms or 1, l.baths or 1), icon = "🚪" })
	UI.row(s.body, { title = "층", right = tostring(l.floor), icon = "🏢" })
	if l.view then
		UI.row(s.body, { title = "전망", right = tostring(l.view), icon = "🌊" })
	end
	if l.owned then
		UI.label(s.body, if l.mine then "🏠 내 집이에요" else ("거주 중: " .. tostring(l.ownerName or "다른 주민")), { color = C.sub, size = 14 })
	end
	UI.button(s.footer, "◀ 목록", back, { style = "ghost", size = UDim2.new(0.28, 0, 0, 48) })
	if not l.owned then
		UI.button(s.footer, "👀 둘러보기", function()
			local res = Net.call("home.tour", { unitId = l.id })
			if res.ok then
				s.close()
			end
		end, { style = "ghost", size = UDim2.new(0.33, 0, 0, 48) })
		UI.button(s.footer, "구매하기", function()
			local res = Net.call("home.buy", { unitId = l.id })
			if res.ok then
				s.close()
			else
				Sfx.ui("error")
			end
		end, { style = "gold", size = UDim2.new(0.33, 0, 0, 48) })
	elseif l.mine then
		UI.button(s.footer, "🏠 집으로 가기", function()
			local res = Net.call("home.enter", {})
			if res.ok then
				s.close()
			end
		end, { style = "primary", size = UDim2.new(0.66, 0, 0, 48) })
	end
end

openListings = function(d: any, tier: number?)
	local tiers = d.tiers or {}
	local me = d.me or {}
	local myTier = tierIndex(tiers, me.tier)
	local sel = tier or math.clamp(myTier + 1, 1, math.max(1, #tiers))
	realtor = { data = d, tier = sel }
	local sub = string.format("보유 %s · %s", won(tonumber(me.balance) or 0), if me.label then ("내 집: " .. me.label) else "아직 집이 없어요")
	local s = UI.sheet({ title = "🏠 부동산 · 내 집 마련", sub = sub, h = 470, w = 500, kind = "home" })
	local names = {}
	for i, t in tiers do
		names[i] = (t.icon or "") .. " " .. t.name
	end
	UI.tabs(s.body, names, sel, function(i)
		openListings(d, i)
	end)
	local t = tiers[sel]
	if t then
		local can = not me.ladder or sel <= myTier + 1 or sel <= tierIndex(tiers, me.maxTier) + 1
		UI.label(s.body, string.format("%s  ·  %s~", t.desc or "", won(t.base or 0)), { color = C.sub, size = 13 })
		if not can then
			UI.label(s.body, "🔒 " .. (tiers[sel - 1] and tiers[sel - 1].name or "이전 단계") .. "을(를) 먼저 마련해야 해요", { color = C.warn, size = 14, bold = true })
		end
		local shown = 0
		for _, l in d.listings or {} do
			if l.tier == t.id then
				shown += 1
				if shown > 40 then
					break
				end
				local state = if l.mine then "내 집" elseif l.owned then "거주 중" else won(l.price)
				UI.row(s.body, {
					title = string.format("%s %s", l.building, l.number),
					sub = string.format("%s · %s · %s층%s", l.type, tostring(l.area), tostring(l.floor), if l.view then " · " .. tostring(l.view) else ""),
					right = state,
					rightColor = if l.mine then C.ok elseif l.owned then C.sub else C.gold,
					disabled = l.owned and not l.mine,
					onClick = function()
						listingDetail(l, function()
							openListings(d, sel)
						end)
					end,
				})
			end
		end
		if shown == 0 then
			UI.label(s.body, "이 단계의 매물이 없어요", { color = C.sub })
		end
	end
	if me.canTest then
		UI.button(s.body, "🧪 테스트 자금 받기 (" .. won(Config.TEST_MONEY_GRANT) .. ")", function()
			local res = Net.call("home.testMoney", {})
			if res.ok then
				local again = Net.request("home.listings", { buildingId = d.buildingId })
				if again.ok then
					again.tiers = again.tiers or d.tiers
					again.buildingId = d.buildingId
					openListings(again, sel)
				end
			end
		end, { style = "ghost" })
	end
end

-------------------------------------------------------------------------------------------------
-- HOLD chip (먹기 / 버리기) + bag
-------------------------------------------------------------------------------------------------
local holdChip: Frame? = nil
local function refreshHold()
	local id = player:GetAttribute("GwB_Hold")
	if holdChip then
		holdChip:Destroy()
		holdChip = nil
	end
	if not id then
		return
	end
	local root = UI.root()
	if not root then
		return
	end
	local label = tostring(player:GetAttribute("GwB_HoldLabel") or id)
	local state = player:GetAttribute("GwB_HoldState")
	local edible = player:GetAttribute("GwB_HoldEat") ~= false
	local f = UI.frame(root, {
		Name = "Hold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0, 360, 0, 52),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.08,
		ZIndex = 10,
	})
	UI.corner(f, 26)
	UI.stroke(f, C.line, 1, 0.3)
	local l = UI.label(f, "✋ " .. label .. (if state == "raw" then " (조리 전)" elseif state == "cooking" then " (조리 중…)" else ""), { size = 14, bold = true })
	l.Position = UDim2.new(0, 18, 0, 0)
	l.Size = UDim2.new(1, -190, 1, 0)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if edible and state ~= "raw" and state ~= "cooking" then
		local b = UI.button(f, "먹기", function()
			Net.call("hold.use", { action = "eat" })
		end, { style = "ok", size = UDim2.new(0, 76, 0, 40) })
		b.Position = UDim2.new(1, -168, 0, 6)
	end
	local b2 = UI.button(f, "내려놓기", function()
		Net.call("hold.use", { action = "drop" })
	end, { style = "ghost", size = UDim2.new(0, 84, 0, 40), textSize = 14 })
	b2.Position = UDim2.new(1, -90, 0, 6)
	holdChip = f
end

local function bagSheet(bag: { any })
	if #bag == 0 then
		UI.closeSheet("bag")
		return
	end
	local s = UI.sheet({ title = "🛍️ 봉투", sub = "꺼내서 들고 먹어요", h = 360, w = 380, kind = "bag" })
	for i, id in bag do
		local it = Shared.Menus.find(Shared.Menus.CVS, id)
		UI.row(s.body, {
			title = if it then it.name else tostring(id),
			sub = if it and it.heat then "전자레인지에 데워요" elseif it and it.noodle then "온수기에서 물 붓기" else nil,
			right = "꺼내기",
			rightColor = C.accent,
			onClick = function()
				local res = Net.call("shop.bagTake", { index = i })
				if res.ok then
					s.close()
				end
			end,
		})
	end
end

-------------------------------------------------------------------------------------------------
-- poses
-------------------------------------------------------------------------------------------------
local lying: { conn: RBXScriptConnection?, chip: Instance? }? = nil
local function endLie(sendServer: boolean)
	local L = lying
	lying = nil
	if L then
		if L.conn then
			L.conn:Disconnect()
		end
		if L.chip then
			L.chip:Destroy()
		end
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root then
		root.Anchored = false
	end
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if sendServer then
		Net.request("pose.end", {})
	end
end

local function startLie(cf: CFrame)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	endLie(false)
	hum.PlatformStand = true
	-- LieSpot is the root pose itself: face up (look = +Y), head toward the headboard
	root.CFrame = cf
	root.Anchored = true
	local chip = UI.button(UI.root(), "🛏️ 일어나기", function()
		endLie(true)
	end, { style = "primary", size = UDim2.new(0, 160, 0, 48) })
	chip.AnchorPoint = Vector2.new(0.5, 1)
	chip.Position = UDim2.new(0.5, 0, 1, -76)
	local conn = hum.Jumping:Connect(function(active)
		if active then
			endLie(true)
		end
	end)
	lying = { conn = conn, chip = chip }
end

-------------------------------------------------------------------------------------------------
-- 월패드 (home control panel) + fridge
-------------------------------------------------------------------------------------------------
local function wallpadSheet(d: any)
	local s = UI.sheet({ title = "📟 월패드", sub = string.format("%s %s", tostring(d.building or ""), tostring(d.label or "")), h = 380, w = 380, kind = "wallpad" })
	local function act(a: string)
		Net.call("wallpad.action", { unitId = d.unitId, action = a })
	end
	UI.row(s.body, { title = "💡 전체 조명 켜기", onClick = function()
		act("lightsOn")
	end })
	UI.row(s.body, { title = "🌙 전체 조명 끄기 (외출)", onClick = function()
		act("lightsOff")
	end })
	UI.row(s.body, { title = "🛋️ 인테리어 모드 (가구 · 벽지 · 바닥 · 조명)", onClick = function()
		s.close()
		if Screens.hooks.decor then
			Screens.hooks.decor()
		end
	end })
	UI.row(s.body, { title = "🛗 엘리베이터 호출", onClick = function()
		act("elevator")
	end })
	UI.row(s.body, { title = "🎉 집들이 모드 켜기 (누구나 입장)", onClick = function()
		Net.call("home.openHouse", { on = true })
	end })
	UI.row(s.body, { title = "🔒 집들이 모드 끄기", onClick = function()
		Net.call("home.openHouse", { on = false })
	end })
end

local function fridgeSheet(d: any)
	local s = UI.sheet({ title = "🧊 " .. (d.title or "냉장고"), sub = "꺼내 먹기", h = 360, w = 380, kind = "fridge" })
	for _, it in d.items or {} do
		UI.row(s.body, {
			title = it.name,
			sub = if it.heat then "전자레인지에 데워 먹어요" else nil,
			right = "꺼내기",
			rightColor = C.accent,
			onClick = function()
				local res = Net.call("fx.use", { fixture = d.fixture, item = it.id })
				if res.ok then
					s.close()
				end
			end,
		})
	end
end

-------------------------------------------------------------------------------------------------
function Screens.start()
	Net.on("toast", function(d)
		UI.toast(d.text, d.kind)
		if d.kind == "warn" then
			Sfx.ui("error")
		end
	end)
	Net.on("money", function(d)
		local delta = tonumber(d.delta) or 0
		if delta ~= 0 then
			UI.toast(string.format("%s %s%s", if delta > 0 then "💰" else "💳", if delta > 0 then "+" else "-", won(math.abs(delta))) .. (if d.label then "  " .. tostring(d.label) else ""), if delta > 0 then "ok" else "info")
			Sfx.ui("money")
		end
	end)
	Net.on("needs.delta", function(d)
		if type(d.text) == "string" and d.text ~= "" then
			UI.toast(d.text, "ok")
		end
	end)
	Net.on("timer", function(d)
		UI.timer(tostring(d.label or "타이머"), tonumber(d.seconds) or 5)
	end)
	Net.on("fx", function(d)
		if d.kind == "sleep" then
			UI.fade(tonumber(d.seconds) or 4, "💤 쿨쿨…")
		elseif d.kind == "celebrate" or d.kind == "score" then
			UI.banner(tostring(d.label or "🎉"), 3.5)
			Sfx.ui("success")
		elseif d.kind == "eat" then
			UI.toast("😋 " .. tostring(d.label or "냠냠"), "ok")
		end
	end)
	Net.on("pose", function(d)
		if d.mode == "lie" and typeof(d.cf) == "CFrame" then
			startLie(d.cf)
		else
			endLie(false)
		end
	end)
	Net.on("waypoint", function(d)
		UI.toast("📍 " .. tostring(d.label or "목적지") .. " 로 이동하세요", "info")
	end)
	Net.on("shop.open", function(d)
		Sfx.ui("open")
		if d.view == "menu" then
			menuSheet(d)
		elseif d.view == "receipt" then
			receiptSheet(d)
		elseif d.view == "hotel" then
			hotelSheet(d)
		elseif d.view == "songs" then
			songsSheet(d)
		elseif Screens.views[d.view] then
			Screens.views[d.view](d)
		else
			UI.toast("이 화면은 준비 중이에요", "info")
		end
	end)
	Net.on("shop.ready", function(d)
		Sfx.ui("notify")
		UI.banner(string.format("📳 %s번 고객님, %s 나왔습니다!", tostring(d.number or ""), tostring(d.name or "주문하신 메뉴")), 3)
	end)
	Net.on("bag", function(d)
		bagSheet(d.bag or {})
	end)
	Net.on("menu", function(d)
		if d.kind == "fridge" then
			fridgeSheet(d)
		end
	end)
	Net.on("wallpad", wallpadSheet)
	Net.on("home.listings", function(d)
		openListings(d, nil)
	end)
	Net.on("home.update", function(d)
		if realtor and UI.current() and UI.current().kind == "home" then
			UI.closeSheet("home")
		end
		if d.label then
			UI.toast("🏠 내 집: " .. tostring(d.label), "ok")
		end
	end)
	Net.on("home.ring", function(d)
		Sfx.at("doorbell", workspace.CurrentCamera, { volume = 0.7 })
		local s = UI.sheet({ title = "🔔 띵동~", sub = tostring(d.from or "누군가") .. "님이 초인종을 눌렀어요", h = 200, w = 360, footer = true, kind = "ring" })
		UI.button(s.footer, "문 열어주기 (초대)", function()
			Net.call("home.invite", { userId = d.userId })
			s.close()
		end, { style = "ok", size = UDim2.new(0.6, 0, 0, 48) })
		UI.button(s.footer, "무시", function()
			s.close()
		end, { style = "ghost", size = UDim2.new(0.36, 0, 0, 48) })
	end)
	Net.on("cafe.seat", function()
		UI.toast("☕ 자리를 잡았어요. 음료를 마시며 쉬어 가요", "ok")
	end)
	Net.on("pc.open", function(d)
		if Screens.views.pc then
			Screens.views.pc(d)
		else
			UI.toast("🖥️ PC가 켜졌어요" .. (if d.remaining then " · 남은 시간 " .. Util.clock(tonumber(d.remaining) or 0) else ""), "ok")
		end
	end)
	player:GetAttributeChangedSignal("GwB_Hold"):Connect(refreshHold)
	player:GetAttributeChangedSignal("GwB_HoldState"):Connect(refreshHold)
	player:GetAttributeChangedSignal("GwB_HoldLabel"):Connect(refreshHold)
	refreshHold()
	player.CharacterAdded:Connect(function()
		endLie(false)
	end)
end

function Screens.openListings(d: any)
	openListings(d, nil)
end

-- extra views registered by other modules (bbq grill, billiards table, PC screen)
Screens.views = {} :: { [string]: (any) -> () }
Screens.hooks = {} :: { [string]: () -> () }

return Screens
