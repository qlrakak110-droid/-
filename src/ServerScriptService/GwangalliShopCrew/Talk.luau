-- GwangalliShopCrew/Talk: server-authoritative dialogs with the crew and with the place's own staff (augmented).
-- The server builds every dialog node, remembers which choice ids it offered (a token per node) and runs the
-- actions itself: a client can only pick one of the offered ids, near the staff, before the node expires.
--   Talk.init(Shared, Bridge, Net, mods)   mods = { Crew, Rig, Serve, Regulars, Sites, Lines }
--   Talk.setResolver(fn(id) -> Target?)    the director resolves crew rigs + augmented staff by id
--   Talk.open(p, T)        a player pressed 대화하기 (ProximityPrompt, server side) or tapped a name tag
--   Talk.push(p, crew, R, ctx)   the waiter at the table: "주문하시겠어요?" (welcome) / "더 필요하신 거?" (check)
--   Talk.closeFor(id)      the staff left: close its open dialogs
-- Target = { id, kind = "crew" | "staff", root, persona, role, shopKey?, shopName?, shopType?, flow?, menuKey?,
--            crew?, R?, aug? = { menuKind?, venue?, model } }
-- Remote ops: "talk" { crew = id } -> { ok, dialog }   "choose" { crew, token, choice } -> { ok, dialog? | close }

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Talk = {}

local Shared: any = nil
local Config: any = nil
local Bridge: any = nil
local Net: any = nil
local Util: any = nil
local Lines: any = nil
local Crew: any = nil
local Rig: any = nil
local Serve: any = nil
local Regulars: any = nil
local Sites: any = nil
local Menus: any = nil

local resolve: (string) -> any? = function()
	return nil
end
local sessions: { [Player]: any } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local buys: { [Player]: { number } } = {}
local lastPush: { [Player]: number } = {}
local tokenSerial = 0

-- types whose bill is paid at the table (포차 · 펍 · 구이 · 해산물: the owner comes over)
local PAY_AT_TABLE = { pocha = true, pub = true, grill = true, seafood = true, rawfish = true }

function Talk.init(S: any, B: any, N: any, mods: any)
	Shared, Config, Bridge, Net, Util, Lines, Menus = S, S.Config, B, N, S.Util, S.Lines, S.Menus
	Crew, Rig, Serve, Regulars, Sites = mods.Crew, mods.Rig, mods.Serve, mods.Regulars, mods.Sites
	Players.PlayerRemoving:Connect(function(p)
		sessions[p] = nil
		cooldowns[p] = nil
		buys[p] = nil
		lastPush[p] = nil
	end)
	Net.on("talk", function(p, d)
		local id = Util.cleanString(d.crew, 48)
		if not id then
			return { ok = false }
		end
		local T = resolve(id)
		if not T then
			return { ok = false, msg = "지금은 대화할 수 없어요" }
		end
		local dlg = Talk.open(p, T, true)
		return if dlg then { ok = true, dialog = dlg } else { ok = false, msg = "조금 더 가까이 가서 말을 걸어 주세요" }
	end)
	Net.on("choose", function(p, d)
		return Talk.choose(p, d)
	end)
	Net.on("close", function(p, d)
		local s = sessions[p]
		if s and type(d.token) == "number" and s.token == d.token then
			Talk.endSession(p)
		end
		return { ok = true }
	end)
	-- dialogs whose player walked away close on their own
	task.spawn(function()
		while true do
			task.wait(1)
			for p, s in sessions do
				local T = resolve(s.id)
				local pp = Bridge.posOf(p)
				if not T or not pp or not T.root or not T.root.Parent or (pp - T.root.Position).Magnitude > Config.TALK_CLOSE_R or os.clock() > s.expires then
					Net.fire(p, "dialog.close", { token = s.token })
					Talk.endSession(p)
				end
			end
		end
	end)
end

function Talk.setResolver(fn: (string) -> any?)
	resolve = fn
end

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function lineT(T: any, key: string, vars: any?): string?
	return Lines.get(key, { dialect = T.persona and T.persona.dialect or "std", type = T.shopType, vars = vars })
end

local function sayT(T: any, text: string?, tone: string?, dur: number?)
	if not text then
		return
	end
	if T.R then
		Rig.say(T.R, text, dur, tone)
	elseif T.root and T.root.Parent then
		Net.fireNear(T.root.Position, Config.SAY_R, "say", { id = T.id, text = text, dur = dur or 3.6, tone = tone or "plain" })
	end
end

local function emoteT(T: any, name: string)
	if T.R then
		Rig.emote(T.R, name)
	elseif T.aug and T.aug.model and T.aug.model.Parent and T.aug.model:GetAttribute("NpcId") then
		T.aug.model:SetAttribute("NpcEmote", string.format("%s#%d#%.2f", name, math.random(1, 1e6), workspace:GetServerTimeNow()))
	end
end

local function talkTo(T: any, uid: number)
	if T.R then
		Rig.talk(T.R, uid)
		Rig.face(T.R, (function()
			local p = Bridge.playerById(uid)
			return p and Bridge.posOf(p)
		end)())
	elseif T.aug and T.aug.model and T.aug.model.Parent and T.aug.model:GetAttribute("NpcId") then
		T.aug.model:SetAttribute("NpcTalk", uid)
	end
end

local function cooling(p: Player, id: string): boolean
	local cd = Config.CHOICE_CD[id]
	if not cd then
		return false
	end
	local c = cooldowns[p]
	if not c then
		c = {}
		cooldowns[p] = c
	end
	local t = os.clock()
	if c[id] and t - c[id] < cd then
		return true
	end
	c[id] = t
	return false
end

local function close(p: Player, T: any, key: string?, vars: any?): any
	if key then
		sayT(T, lineT(T, key, vars), "plain", 3)
	end
	Talk.endSession(p)
	return { ok = true, close = true }
end

local function itemOf(T: any, id: any): any?
	local SS = Bridge.SS
	if SS and T.menuKey then
		local ok, it = pcall(SS.item, T.menuKey, id)
		if ok then
			return it
		end
	end
	return nil
end

local function shopMenu(T: any): { any }
	local SS = Bridge.SS
	if SS and T.menuKey then
		local ok, list = pcall(SS.menu, T.menuKey)
		if ok and type(list) == "table" then
			return list
		end
	end
	return {}
end

local function recommendOf(T: any): any?
	local list = shopMenu(T)
	if #list == 0 then
		local m = T.aug and Menus.forKind(T.aug.menuKind)
		if m and #m > 0 then
			return m[(Util.hash(Util.dayKey() .. T.id) % #m) + 1]
		end
		return nil
	end
	local mains = {}
	for _, it in list do
		if it.cat == "main" or it.cat == nil then
			table.insert(mains, it)
		end
	end
	if #mains == 0 then
		mains = list
	end
	return mains[(Util.hash(Util.dayKey() .. (T.shopKey or T.id)) % #mains) + 1]
end

local function menuText(list: { any }, max: number): string
	local out = {}
	for i, it in list do
		if i > max then
			table.insert(out, string.format("… 외 %d가지", #list - max))
			break
		end
		table.insert(out, string.format("%s %s %s", it.icon or "•", it.name, Util.won(it.price or 0)))
	end
	return "\n" .. table.concat(out, "\n")
end

local function context(p: Player, T: any): any
	local c: any = { uid = p.UserId }
	if T.shopKey then
		local key, tableId, seatId = Bridge.seatOf(p)
		c.seated = key == T.shopKey and tableId ~= nil
		c.table = if c.seated then tableId else nil
		c.seat = if c.seated then seatId else nil
		c.bill, c.billLines = Bridge.bill(p, T.shopKey)
		c.dishes = Bridge.dishesOfPlayer(p, T.shopKey)
		c.view = Regulars.view(p.UserId, T.shopKey)
		c.orders = Serve.playerOrders(p.UserId, T.shopKey)
	else
		c.bill, c.billLines, c.dishes, c.orders = 0, {}, {}, {}
		c.view = Regulars.view(p.UserId, T.id)
	end
	c.banchanType = T.shopKey ~= nil and Bridge.SS ~= nil and Bridge.SS.TYPES[T.shopType or ""] ~= nil and Bridge.SS.TYPES[T.shopType].banchan ~= nil
	return c
end

local function C(id: string, label: string, style: string?): any
	return { id = id, label = label, style = style or "secondary" }
end

-------------------------------------------------------------------------------------------------
-- nodes
-------------------------------------------------------------------------------------------------
local NODES: { [string]: (Player, any, any) -> (string?, { any }) } = {}

local function rootChoices(p: Player, T: any, c: any): { any }
	local ch = {}
	local role = T.role
	local flow = T.flow
	local hasFood = #c.dishes > 0 or #c.orders > 0
	if T.shopKey and role == "waiter" then
		if c.seated then
			table.insert(ch, C("order", if hasFood then "🔔 추가 주문할게요" else "🔔 주문할게요", "primary"))
			table.insert(ch, C("menu", "📋 메뉴판 보기"))
			if c.banchanType and hasFood then
				table.insert(ch, C("refill", "💧 물 · 반찬 더 주세요"))
			else
				table.insert(ch, C("water", "💧 물 좀 주세요"))
			end
			table.insert(ch, C("pay", "🧾 계산할게요"))
		else
			table.insert(ch, C("seat", "🪑 자리 있어요?", "primary"))
			table.insert(ch, C("takeout", "🥡 포장 주문할게요"))
			table.insert(ch, C("menu", "📋 메뉴판 보기"))
		end
	elseif T.shopKey and (role == "cook" or role == "baker") and flow ~= "kiosk" and flow ~= "counter" and flow ~= "pick" then
		table.insert(ch, C("whatcook", "🍳 뭐 만드세요?", "primary"))
		table.insert(ch, C("taste", "😋 맛있는 냄새 나요!"))
		table.insert(ch, C("recommend", "👍 추천 메뉴 있어요?"))
		table.insert(ch, C("menu", "📋 메뉴판 보기"))
	elseif T.shopKey and flow == "table" then
		-- the cashier of a table shop
		if c.bill > 0 then
			table.insert(ch, C("paynow", "🧾 계산할게요", "primary"))
			table.insert(ch, C("receipt", "📃 영수증 보여 주세요"))
		end
		table.insert(ch, C("takeout", "🥡 포장 주문할게요"))
		table.insert(ch, C("menu", "📋 메뉴판 보기"))
		table.insert(ch, C("recommend", "👍 추천 메뉴 있어요?"))
	elseif T.shopKey and (flow == "kiosk" or flow == "counter") then
		table.insert(ch, C("order", if flow == "kiosk" then "☕ 주문할게요" else "🛒 주문할게요", "primary"))
		table.insert(ch, C("hereTogo", "🥡 포장도 되나요?"))
		table.insert(ch, C("recommend", "👍 추천 메뉴 있어요?"))
		if c.bill > 0 then
			table.insert(ch, C("paynow", "🧾 계산할게요"))
		end
	elseif T.shopKey and flow == "pick" then
		table.insert(ch, C("checkout", "🧺 계산할게요", "primary"))
		table.insert(ch, C("find", "🔎 물건 찾고 있어요"))
		table.insert(ch, C("menu", "📋 뭐 파세요?"))
	elseif T.shopKey and flow == "service" then
		if T.shopType == "pharmacy" or T.shopType == "clinic" then
			table.insert(ch, C("service", "💊 증상 상담 받을게요", "primary"))
			table.insert(ch, C("advice", "🙋 요즘 뭐가 좋아요?"))
		elseif T.shopType == "salon" then
			table.insert(ch, C("service", "💇 시술 받을게요", "primary"))
			table.insert(ch, C("trend", "✂️ 요즘 유행하는 스타일?"))
		else
			table.insert(ch, C("service", "🛎️ 도와주세요", "primary"))
		end
		table.insert(ch, C("menu", "📋 가격표 보기"))
	elseif T.aug and T.aug.menuKind and Menus.forKind(T.aug.menuKind) then
		table.insert(ch, C("buy", "🛒 살게요", "primary"))
		table.insert(ch, C("menulist", "📋 메뉴 보기"))
		table.insert(ch, C("recommend", "👍 추천해 주세요"))
		if T.aug.venue then
			table.insert(ch, C("info", "ℹ️ 이용 안내"))
		end
	elseif T.aug and T.aug.venue then
		table.insert(ch, C("info", "ℹ️ 이용 안내", "primary"))
		if T.aug.spot then
			table.insert(ch, C("orderspot", "📍 주문은 어디서 해요?"))
		end
	end
	table.insert(ch, C("more", "💬 이야기하기"))
	table.insert(ch, C("close", "괜찮아요", "ghost"))
	return ch
end

NODES.root = function(p, T, c)
	local key = "rootStaff"
	if T.shopKey then
		if T.role == "waiter" then
			key = if c.seated then "rootSeated" else "rootStanding"
		elseif T.role == "cook" then
			key = "rootCook"
		elseif T.flow == "kiosk" or T.flow == "counter" then
			key = "rootCounter"
		elseif T.role == "cashier" then
			key = "rootCashier"
		end
	else
		key = "helloStaff"
	end
	local text = lineT(T, key)
	local v = c.view
	if v and v.level >= Config.REGULAR.nameLevel and not c.namedOnce then
		c.namedOnce = true
		text = lineT(T, "greetNamed", { name = p.DisplayName }) or text
	end
	return text, rootChoices(p, T, c)
end

NODES.welcome = function(_p, T, c)
	local ch = { C("order", "🔔 주문할게요", "primary"), C("recommend", "👍 추천해 주세요"), C("later", "🙂 조금 있다가요", "ghost") }
	local _ = c
	return lineT(T, "askOrder"), ch
end

NODES.check = function(_p, T, c)
	local ch = { C("order", "🔔 추가 주문할게요", "primary") }
	if c.banchanType then
		table.insert(ch, C("refill", "💧 물 · 반찬 더 주세요"))
	else
		table.insert(ch, C("water", "💧 물 좀 주세요"))
	end
	table.insert(ch, C("pay", "🧾 계산할게요"))
	table.insert(ch, C("praise", "😋 너무 맛있어요!"))
	table.insert(ch, C("later", "괜찮아요", "ghost"))
	return lineT(T, "checkOn"), ch
end

NODES.refill = function(_p, T, _c)
	return lineT(T, "rootSeated"), { C("water", "💧 물 좀 주세요"), C("banchan", "🥢 반찬 더 주세요"), C("back", "↩ 돌아가기", "ghost") }
end

NODES.more = function(_p, T, c)
	local ch = {
		C("chat", "☺️ 이런저런 이야기"),
		C("dirs", "🗺️ 길 좀 물어볼게요"),
		C("praise", "👍 칭찬하기"),
		C("complain", "😟 불편한 점 말하기"),
		C("tip", "💰 팁 드리기"),
	}
	if T.shopKey and Config.REGULAR.enabled then
		table.insert(ch, C("card", "🏅 내 단골 카드"))
	end
	table.insert(ch, C("back", "↩ 돌아가기", "ghost"))
	local _ = c
	return lineT(T, "rootStaff"), ch
end

NODES.complain = function(_p, T, _c)
	local _ = T
	return "네… 어떤 점이 불편하셨어요? 말씀해 주시면 바로 고칠게요.", {
		C("c_slow", "⏰ 음식이 너무 늦어요"),
		C("c_taste", "😖 맛이 좀 아쉬워요"),
		C("c_noise", "🔊 좀 시끄러워요"),
		C("c_service", "🙁 응대가 아쉬워요"),
		C("back", "↩ 돌아가기", "ghost"),
	}
end

NODES.tip = function(_p, T, _c)
	local ch = {}
	for _, a in Config.TIP.amounts do
		table.insert(ch, C("tip_" .. a, "💵 " .. Util.won(a)))
	end
	table.insert(ch, C("back", "↩ 돌아가기", "ghost"))
	return lineT(T, "tipAsk"), ch
end

NODES.dirs = function(p, T, c)
	local list = {}
	local from = T.root.Position
	for _, d in Bridge.destinations() do
		table.insert(list, { name = d.name, pos = d.pos, dist = (Vector3.new(d.pos.X, 0, d.pos.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude })
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	local pick = {}
	for _, d in list do
		if #pick >= 4 then
			break
		end
		table.insert(pick, d)
	end
	-- the beach is always on the list (the question every visitor asks)
	for _, d in list do
		if string.find(d.name, "해수욕장", 1, true) and not table.find(pick, d) then
			table.insert(pick, d)
			break
		end
	end
	c.dirs = pick
	local ch = {}
	for i, d in pick do
		table.insert(ch, C("d_" .. i, string.format("📍 %s · %s", d.name, Util.meters(d.dist))))
	end
	table.insert(ch, C("back", "↩ 돌아가기", "ghost"))
	if #pick == 0 then
		return lineT(T, "directionsNone"), { C("back", "↩ 돌아가기", "ghost") }
	end
	local _ = p
	return lineT(T, "directionsIntro"), ch
end

NODES.buy = function(_p, T, c)
	local list = Menus.forKind(T.aug and T.aug.menuKind) or {}
	local ch = {}
	for i, it in list do
		if i > 5 then
			break
		end
		table.insert(ch, C("b_" .. it.id, string.format("%s %s · %s", it.icon, it.name, Util.won(it.price))))
	end
	table.insert(ch, C("back", "↩ 돌아가기", "ghost"))
	local _ = c
	return lineT(T, "buyAsk"), ch
end

NODES.buyWhere = function(_p, T, c)
	local it = c.buyItem
	if not it then
		return lineT(T, "buyAsk"), { C("back", "↩ 돌아가기", "ghost") }
	end
	return lineT(T, "saleHere"), {
		C("here_" .. it.id, "🍽️ 여기서 먹을게요", "primary"),
		C("togo_" .. it.id, "🥡 가져갈게요"),
		C("back", "↩ 돌아가기", "ghost"),
	}
end

-------------------------------------------------------------------------------------------------
-- rendering + sessions
-------------------------------------------------------------------------------------------------
local function colorOf(T: any): any
	local c = T.R and T.R.model and T.R.model:GetAttribute(Shared.ATTR.Color)
	if type(c) == "string" then
		local r, g, b = string.match(c, "^(%d+),(%d+),(%d+)$")
		if r then
			return { tonumber(r), tonumber(g), tonumber(b) }
		end
	end
	return { 61, 214, 245 }
end

local function render(p: Player, T: any, s: any, node: string, text: string?, timer: number?): any
	local fn = NODES[node] or NODES.root
	local t, choices = fn(p, T, s.ctx)
	tokenSerial += 1
	s.token = tokenSerial
	s.node = node
	s.ids = {}
	for _, ch in choices do
		s.ids[ch.id] = true
	end
	s.expires = os.clock() + Config.DIALOG_TTL
	local sub = {}
	if T.persona and T.persona.full and T.persona.full ~= "" then
		table.insert(sub, T.persona.full)
	end
	if T.shopName and T.shopName ~= "" then
		table.insert(sub, T.shopName)
	end
	return {
		crewId = T.id,
		name = T.persona and T.persona.title or "직원",
		role = table.concat(sub, " · "),
		icon = T.persona and T.persona.icon or "🙂",
		color = colorOf(T),
		text = text or t or "네~",
		choices = choices,
		token = s.token,
		timer = if timer then { total = timer } else nil,
		pushed = s.pushed == true,
	}
end

function Talk.endSession(p: Player)
	local s = sessions[p]
	if not s then
		return
	end
	sessions[p] = nil
	local T = resolve(s.id)
	if T then
		if T.R then
			Rig.talk(T.R, 0)
		elseif T.aug and T.aug.model and T.aug.model.Parent and T.aug.model:GetAttribute("NpcId") then
			T.aug.model:SetAttribute("NpcTalk", 0)
		end
	end
end

local function near(p: Player, T: any, r: number): boolean
	local pp = Bridge.posOf(p)
	if not pp or not T.root or not T.root.Parent then
		return false
	end
	return (pp - T.root.Position).Magnitude <= r and math.abs(pp.Y - T.root.Position.Y) < 7
end

function Talk.open(p: Player, T: any, viaRemote: boolean?): any?
	if not near(p, T, Config.TALK_R) then
		return nil
	end
	local s = { id = T.id, ctx = context(p, T), pushed = false }
	sessions[p] = s
	talkTo(T, p.UserId)
	local dlg = render(p, T, s, "root")
	if not viaRemote then
		Net.fire(p, "dialog", dlg)
	end
	return dlg
end

function Talk.push(p: Player, crew: any, R: any, ctxName: string)
	local t = os.clock()
	if lastPush[p] and t - lastPush[p] < Config.PUSH_GAP then
		return
	end
	if sessions[p] then
		return -- already talking
	end
	local T = resolve(R.id)
	if not T or not near(p, T, Config.TALK_CLOSE_R) then
		return
	end
	lastPush[p] = t
	local s = { id = T.id, ctx = context(p, T), pushed = true }
	sessions[p] = s
	local _ = crew
	Net.fire(p, "dialog", render(p, T, s, if ctxName == "check" then "check" else "welcome", nil, 10))
end

function Talk.closeFor(id: string)
	for p, s in sessions do
		if s.id == id then
			Net.fire(p, "dialog.close", { token = s.token })
			sessions[p] = nil
		end
	end
end

-------------------------------------------------------------------------------------------------
-- actions
-------------------------------------------------------------------------------------------------
local function reply(p: Player, T: any, s: any, node: string, text: string?): any
	local old = s.ctx or {}
	s.ctx = context(p, T)
	-- keep the per-session bits (the item being bought, the places offered, the name already said)
	s.ctx.buyItem = old.buyItem
	s.ctx.dirs = old.dirs
	s.ctx.namedOnce = old.namedOnce
	return { ok = true, dialog = render(p, T, s, node, text) }
end

local function waiterOf(T: any): any?
	if T.crew then
		return Crew.waiter(T.crew)
	end
	return nil
end

local function mood(T: any, delta: number)
	if T.crew then
		local m = T.crew.moodRef
		m.v = math.clamp(m.v + delta, Config.MOOD.min, Config.MOOD.max)
	end
end

local function smallTalk(p: Player, T: any, c: any): string?
	local opts = {}
	local v = c.view
	if v and v.visits >= 2 then
		table.insert(opts, { "smallRegular", { count = v.visits, name = p.DisplayName } })
	elseif v and v.visits == 0 then
		table.insert(opts, { "smallFirst" })
	end
	local m = T.crew and T.crew.moodRef.v
	if m and m < 40 then
		table.insert(opts, { "smallMoodLow" })
	elseif m and m > 85 then
		table.insert(opts, { "smallMoodHigh" })
	end
	local part = Util.partOfDay(Lighting.ClockTime)
	local key = ({ dawn = "smallDawn", morning = "smallMorning", lunch = "smallLunch", afternoon = "smallAfternoon", evening = "smallEvening", night = "smallNight" })[part]
	table.insert(opts, { key })
	local w = workspace:GetAttribute("Weather") or workspace:GetAttribute("GwWeather")
	if type(w) == "string" then
		local wl = string.lower(w)
		if string.find(wl, "rain") or string.find(w, "비") then
			table.insert(opts, { "smallRain" })
		elseif string.find(wl, "cloud") or string.find(w, "흐") then
			table.insert(opts, { "smallCloudy" })
		elseif string.find(wl, "clear") or string.find(wl, "sun") or string.find(w, "맑") then
			table.insert(opts, { "smallClear" })
		end
	end
	local o = opts[math.random(1, #opts)]
	return lineT(T, o[1], o[2])
end

local ACT: { [string]: (Player, any, any, string) -> any } = {}

ACT.close = function(p, T, _s)
	return close(p, T, "goodbyeDialog")
end
ACT.later = function(p, T, _s)
	return close(p, T, "later")
end
ACT.back = function(p, T, s)
	return reply(p, T, s, "root")
end
ACT.more = function(p, T, s)
	return reply(p, T, s, "more")
end
ACT.refill = function(p, T, s)
	return reply(p, T, s, "refill")
end
ACT.complain = function(p, T, s)
	return reply(p, T, s, "complain")
end
ACT.tip = function(p, T, s)
	return reply(p, T, s, "tip")
end
ACT.dirs = function(p, T, s)
	return reply(p, T, s, "dirs")
end
ACT.buy = function(p, T, s)
	return reply(p, T, s, "buy")
end

-- ordering through ShopLife's own menus ------------------------------------------------------------
ACT.order = function(p, T, s)
	local c = s.ctx
	if not T.shopKey then
		return reply(p, T, s, "root")
	end
	if T.flow == "table" then
		if c.seated then
			local r = Bridge.lifeAct(p, "order")
			if r and r.ok == false and r.msg then
				return reply(p, T, s, "root", r.msg)
			end
			if T.crew then
				Crew.takingOrder(T.crew, p.UserId)
			end
			return close(p, T, "orderOpen")
		end
		-- standing in a table shop: sit first (or order to take away)
		return reply(p, T, s, "root", lineT(T, "sitFirst"))
	end
	Bridge.lifePrompt(p, T.shopKey, "order")
	return close(p, T, if T.flow == "kiosk" then "orderHowKiosk" else "orderHowCounter")
end

ACT.takeout = function(p, T, s)
	if not T.shopKey then
		return reply(p, T, s, "root")
	end
	Bridge.lifePrompt(p, T.shopKey, "order")
	return close(p, T, if T.flow == "table" then "takeoutTable" else "takeout")
end

ACT.hereTogo = function(p, T, s)
	return reply(p, T, s, "root", lineT(T, "takeout"))
end

ACT.menu = function(p, T, s)
	if T.shopKey then
		Bridge.lifePrompt(p, T.shopKey, "menuboard")
		return close(p, T, "menuIntro")
	end
	return ACT.menulist(p, T, s, "menulist")
end

ACT.menulist = function(p, T, s)
	local list = (T.aug and Menus.forKind(T.aug.menuKind)) or shopMenu(T)
	if #list == 0 then
		return reply(p, T, s, "root", lineT(T, "saleNone"))
	end
	return reply(p, T, s, "root", lineT(T, "menuList", { menu = menuText(list, 6) }))
end

ACT.recommend = function(p, T, s)
	local it = recommendOf(T)
	if not it then
		return reply(p, T, s, s.node or "root", lineT(T, "recommendNone"))
	end
	return reply(p, T, s, if s.node == "welcome" then "welcome" else "root", lineT(T, "recommend", { item = it.name, desc = it.desc or "정말 맛있어요", price = Util.won(it.price or 0) }))
end

ACT.checkout = function(p, T, _s)
	Bridge.lifePrompt(p, T.shopKey, "checkout")
	return close(p, T, "payHere")
end

ACT.service = function(p, T, _s)
	Bridge.lifePrompt(p, T.shopKey, "service")
	return close(p, T, "goodbyeDialog")
end

ACT.find = function(p, T, s)
	return reply(p, T, s, "root", lineT(T, "findItem"))
end

ACT.advice = function(p, T, s)
	return reply(p, T, s, "root", lineT(T, "advicePharmacy"))
end

ACT.trend = function(p, T, s)
	return reply(p, T, s, "root", lineT(T, "trendSalon"))
end

ACT.info = function(p, T, s)
	local v = T.aug and T.aug.venue
	local key = if v == "pc" then "infoPc" elseif v == "karaoke" then "infoKaraoke" elseif v == "hotel" then "infoHotel" elseif v == "rental" then "infoRental" elseif v == "office" then "infoOffice" else "infoGame"
	return reply(p, T, s, "root", lineT(T, key))
end

ACT.orderspot = function(p, T, s)
	local spot = T.aug and T.aug.spot
	if spot and spot.part and spot.part.Parent then
		Net.fire(p, "point", { kind = "place", pos = spot.part.Position, label = spot.label or "주문하는 곳", seconds = 12 })
		return reply(p, T, s, "root", lineT(T, "orderAtCounter", { place = spot.label or "카운터" }))
	end
	return reply(p, T, s, "root", lineT(T, "infoGame"))
end

-- table service -----------------------------------------------------------------------------------
ACT.water = function(p, T, s)
	if cooling(p, "water") then
		return reply(p, T, s, "root", lineT(T, "waterWait"))
	end
	local w = waiterOf(T) or T.R
	if w then
		Rig.carry(w, "water")
		Rig.act(w, "cup")
		Rig.emote(w, "give")
		task.delay(1.8, function()
			if Rig.alive(w) then
				Rig.carry(w, "")
				if w.act == "cup" then
					Rig.act(w, if w.role == "waiter" then "behind" else "idle")
				end
			end
		end)
	end
	Bridge.needs(p, { Energy = 3 }, "시원한 물")
	return close(p, T, "waterPour")
end

ACT.banchan = function(p, T, s)
	if cooling(p, "banchan") then
		return reply(p, T, s, "root", lineT(T, "banchanNone"))
	end
	local r = Bridge.lifeAct(p, "banchan")
	if r and r.ok == false then
		return reply(p, T, s, "root", if type(r.msg) == "string" and r.msg ~= "" then r.msg else lineT(T, "banchanNone"))
	end
	local w = waiterOf(T) or T.R
	if w then
		Rig.emote(w, "give")
	end
	return close(p, T, "banchan")
end

ACT.pay = function(p, T, s)
	local c = s.ctx
	if not T.shopKey then
		return reply(p, T, s, "root")
	end
	if c.bill <= 0 then
		return reply(p, T, s, "root", lineT(T, "receiptNone"))
	end
	if PAY_AT_TABLE[T.shopType or ""] or not T.crew or not Crew.rigOf(T.crew, "cashier") then
		Bridge.lifePrompt(p, T.shopKey, "pay")
		return close(p, T, "payHere")
	end
	-- the cashier takes it at the counter
	local K = T.crew.site.spots.K
	if K then
		Net.fire(p, "point", { kind = "place", pos = K.pos, label = "계산대", seconds = 10 })
	end
	local cashier = Crew.rigOf(T.crew, "cashier")
	if cashier then
		Rig.emote(cashier, "beckon")
	end
	return close(p, T, "payWay")
end

ACT.paynow = function(p, T, s)
	local c = s.ctx
	if c.bill <= 0 then
		return reply(p, T, s, "root", lineT(T, "receiptNone"))
	end
	Bridge.lifePrompt(p, T.shopKey, "pay")
	return close(p, T, "payHere")
end

ACT.receipt = function(p, T, s)
	local c = s.ctx
	if c.bill <= 0 then
		return reply(p, T, s, "root", lineT(T, "receiptNone"))
	end
	local rows = {}
	for _, ln in c.billLines do
		table.insert(rows, string.format("• %s ×%d  %s", ln.name, ln.qty, Util.won(ln.price * ln.qty)))
	end
	Net.fire(p, "receipt", { shop = T.shopKey, shopName = T.shopName, items = c.billLines, total = c.bill, preview = true, staff = T.persona.title })
	return reply(p, T, s, "root", (lineT(T, "receipt") or "") .. "\n" .. table.concat(rows, "\n") .. "\n합계 " .. Util.won(c.bill))
end

ACT.seat = function(p, T, s)
	if not T.crew then
		return reply(p, T, s, "root", lineT(T, "seatNone"))
	end
	local free = Crew.freeTables(T.crew)
	local pp = Bridge.posOf(p)
	local best, bd = nil, math.huge
	for _, id in free do
		local tb = T.crew.site.tableById[id]
		if tb and pp then
			local d = (tb.center - pp).Magnitude
			if d < bd then
				best, bd = tb, d
			end
		end
	end
	if not best then
		return reply(p, T, s, "root", lineT(T, "seatNone"))
	end
	Net.fire(p, "point", { kind = "table", shop = T.shopKey, table = best.id, pos = best.center, label = "빈 자리", seconds = 6 })
	local w = waiterOf(T)
	if w then
		Crew.enqueue(T.crew, "waiter", Crew.jobs.point(best.id))
	end
	return close(p, T, "seatFree", { table = best.id })
end

-- the kitchen ---------------------------------------------------------------------------------------
ACT.whatcook = function(p, T, s)
	local cooking = nil
	if T.shopKey then
		for _, o in Serve.playerOrders(p.UserId, T.shopKey) do
			if o.phase == "cooking" then
				cooking = o
			end
		end
		if not cooking then
			for _, o in Serve.readyFor(T.shopKey) do
				cooking = o
			end
		end
	end
	if cooking then
		return reply(p, T, s, "root", lineT(T, "whatCooking", { item = cooking.name }))
	end
	return reply(p, T, s, "root", lineT(T, "whatCookingNone"))
end

ACT.taste = function(p, T, s)
	local key = T.shopKey or T.id
	if Regulars.dayFlag(p, "taste", key) then
		return reply(p, T, s, "root", lineT(T, "tasteDone"))
	end
	Regulars.setDayFlag(p, "taste", key)
	emoteT(T, "give")
	Bridge.needs(p, { Satiety = 3, Fun = 2 }, "맛보기")
	return reply(p, T, s, "root", lineT(T, "taste"))
end

-- feelings ------------------------------------------------------------------------------------------
ACT.chat = function(p, T, s)
	return reply(p, T, s, "more", smallTalk(p, T, s.ctx))
end

ACT.praise = function(p, T, s)
	local c = s.ctx
	if cooling(p, "praise") then
		return reply(p, T, s, s.node, lineT(T, "compliment"))
	end
	mood(T, Config.MOOD.compliment)
	Regulars.friend(p, T.shopKey or T.id, Config.FRIEND.compliment, "compliment")
	emoteT(T, if math.random() < 0.5 then "shy" else "bow")
	local ate = false
	for _, d in c.dishes do
		if d.done or d.left < 0.7 then
			ate = true
		end
	end
	return reply(p, T, s, "more", lineT(T, if ate then "complimentFood" else "compliment"))
end

local function complain(p: Player, T: any, s: any, key: string): any
	mood(T, Config.MOOD.complaint)
	Regulars.friend(p, T.shopKey or T.id, Config.FRIEND.complaint, "complaint")
	emoteT(T, "bow")
	local text = lineT(T, key)
	-- slow food: a tray that is ready goes out now
	if key == "complainSlow" and T.shopKey then
		for _, o in Serve.playerOrders(p.UserId, T.shopKey) do
			if o.phase == "ready" and o.dest == "table" and not o.served and not o.claimed then
				Serve.serveNow(o, "complaint")
			end
		end
	end
	-- once a day: a small 서비스 to make up for it
	local dayKey = T.shopKey or T.id
	if not Regulars.dayFlag(p, "sorry", dayKey) then
		Regulars.setDayFlag(p, "sorry", dayKey)
		Bridge.needs(p, { Fun = 3, Energy = 2 }, "사과의 서비스")
		text = (text or "") .. " " .. (lineT(T, "apologyGift") or "")
	end
	return reply(p, T, s, "more", text)
end

ACT.c_slow = function(p, T, s)
	return complain(p, T, s, "complainSlow")
end
ACT.c_taste = function(p, T, s)
	return complain(p, T, s, "complainTaste")
end
ACT.c_noise = function(p, T, s)
	return complain(p, T, s, "complainNoise")
end
ACT.c_service = function(p, T, s)
	return complain(p, T, s, "complainService")
end

ACT.card = function(p, T, s)
	if not T.shopKey then
		return reply(p, T, s, "more")
	end
	local card = Regulars.card(p, T.shopKey, T.shopName or "", T.persona and T.persona.icon)
	Net.fire(p, "card", card)
	return reply(p, T, s, "more", lineT(T, if card.visits > 0 then "cardShow" else "cardFirst"))
end

-- tips: politely refused first (it is Korea), given when the player insists ---------------------------------
local function tipAction(p: Player, T: any, s: any, amount: number, force: boolean): any
	if not table.find(Config.TIP.amounts, amount) then
		return reply(p, T, s, "more")
	end
	if Regulars.tipsToday(p) >= Config.TIP.perDay then
		return reply(p, T, s, "more", lineT(T, "tipLimit"))
	end
	if not force then
		emoteT(T, "shy")
		local text = lineT(T, "tipRefuse")
		local r = reply(p, T, s, "tip", text)
		-- offer "그래도 드릴게요" for this amount
		local d = r.dialog
		table.insert(d.choices, 1, C("tipf_" .. amount, "🙏 그래도 받아 주세요 (" .. Util.won(amount) .. ")", "primary"))
		s.ids["tipf_" .. amount] = true
		return r
	end
	local ok = Bridge.spend(p, amount, "팁 · " .. (T.shopName or T.persona.title or "직원"))
	if not ok then
		return reply(p, T, s, "more", lineT(T, "noMoney"))
	end
	Regulars.addTip(p)
	mood(T, Config.MOOD.tip)
	Regulars.friend(p, T.shopKey or T.id, Config.FRIEND.tip, "tip")
	emoteT(T, "bow")
	Bridge.toast(p, string.format("💰 팁 %s을 드렸어요", Util.won(amount)), "ok")
	return reply(p, T, s, "more", lineT(T, "tipThanks"))
end

-- buying at a counter ShopLife does not run ---------------------------------------------------------------
local function buyAllowed(p: Player): boolean
	local t = os.clock()
	local list = buys[p] or {}
	local keep = {}
	for _, x in list do
		if t - x < 60 then
			table.insert(keep, x)
		end
	end
	buys[p] = keep
	return #keep < Config.COUNTER.perMinute
end

local function sell(p: Player, T: any, s: any, it: any, here: boolean): any
	if not buyAllowed(p) then
		return reply(p, T, s, "root", lineT(T, "buyLimit"))
	end
	if not here then
		local held = Bridge.held(p)
		if held and held.state ~= "empty" and not held.trash then
			return reply(p, T, s, "root", lineT(T, "saleHands"))
		end
	end
	local sname = (T.shopName and T.shopName ~= "" and T.shopName) or (T.persona and T.persona.title) or "가게"
	local label = string.format("%s · %s", sname, it.name)
	local ok, msg = Bridge.spend(p, it.price, label)
	if not ok then
		return reply(p, T, s, "root", msg or lineT(T, "noMoney"))
	end
	table.insert(buys[p], os.clock())
	emoteT(T, "give")
	local given = false
	if not here then
		given = Bridge.give(p, {
			id = "crew_" .. it.id,
			label = it.name,
			kind = if it.kind == "drink" then "drink" else "food",
			visual = { d = it.dish, t = it.tint },
			sips = it.bites or 3,
			sipsMax = it.bites or 3,
			style = if it.kind == "drink" then "sip" else "hand",
			effect = it.effect,
			edible = it.kind ~= "goods" or it.dish == "medicine",
		})
	end
	if not given then
		-- eaten / used right here (or no held-item system in this place)
		Bridge.needs(p, it.effect or {}, it.name)
	end
	Bridge.track(p, "shop_buy", 1)
	Net.fire(p, "receipt", { shopName = sname, items = { { name = it.name, qty = 1, price = it.price } }, total = it.price, staff = T.persona and T.persona.title })
	return close(p, T, if here or not given then "saleDone" else "saleTakeout", { item = it.name })
end

-------------------------------------------------------------------------------------------------
-- the remote
-------------------------------------------------------------------------------------------------
function Talk.choose(p: Player, d: any): any
	local id = Util.cleanString(d.crew, 48)
	local choice = Util.cleanString(d.choice, 24)
	local token = d.token
	if not id or not choice or type(token) ~= "number" or not string.match(choice, "^[%w_]+$") then
		return { ok = false, close = true }
	end
	local s = sessions[p]
	if not s or s.id ~= id or s.token ~= token or os.clock() > s.expires or not s.ids[choice] then
		return { ok = false, close = true }
	end
	local T = resolve(id)
	if not T then
		Talk.endSession(p)
		return { ok = false, close = true }
	end
	if not near(p, T, Config.TALK_CLOSE_R) then
		Talk.endSession(p)
		return { ok = true, close = true, toast = lineT(T, "tooFar") }
	end
	s.pushed = false
	local f = ACT[choice]
	if f then
		return f(p, T, s, choice)
	end
	-- parametrised ids
	local amt = string.match(choice, "^tip_(%d+)$")
	if amt then
		return tipAction(p, T, s, tonumber(amt) :: number, false)
	end
	amt = string.match(choice, "^tipf_(%d+)$")
	if amt then
		return tipAction(p, T, s, tonumber(amt) :: number, true)
	end
	local di = string.match(choice, "^d_(%d+)$")
	if di then
		local dest = s.ctx.dirs and s.ctx.dirs[tonumber(di) :: number]
		if not dest then
			return reply(p, T, s, "more")
		end
		local from = T.root.Position
		local dv = dest.pos - from
		Net.fire(p, "point", { kind = "place", pos = dest.pos, label = dest.name, seconds = 30 })
		local text
		if dest.dist < 40 then
			text = lineT(T, "directionsHere", { place = dest.name })
		else
			text = lineT(T, "directionsAnswer", { place = dest.name, dir = Util.compass(dv.X, dv.Z), dist = Util.meters(dest.dist), mins = Util.walkMinutes(dest.dist) })
		end
		emoteT(T, "point_proc")
		return reply(p, T, s, "more", text)
	end
	local bid = string.match(choice, "^b_([%w_]+)$")
	if bid then
		local it = Menus.item(T.aug and T.aug.menuKind, bid)
		if not it then
			return reply(p, T, s, "root")
		end
		if not it.here then
			return sell(p, T, s, it, false)
		end
		s.ctx.buyItem = it
		local r = reply(p, T, s, "buyWhere")
		return r
	end
	local hid = string.match(choice, "^here_([%w_]+)$")
	if hid then
		local it = Menus.item(T.aug and T.aug.menuKind, hid)
		return if it then sell(p, T, s, it, true) else reply(p, T, s, "root")
	end
	local tid = string.match(choice, "^togo_([%w_]+)$")
	if tid then
		local it = Menus.item(T.aug and T.aug.menuKind, tid)
		return if it then sell(p, T, s, it, false) else reply(p, T, s, "root")
	end
	return reply(p, T, s, "root")
end

function Talk.count(): number
	local n = 0
	for _ in sessions do
		n += 1
	end
	return n
end

return Talk
