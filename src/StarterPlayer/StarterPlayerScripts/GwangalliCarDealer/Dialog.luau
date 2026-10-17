-- GwangalliCarDealer/Dialog (client): the conversation with a sales NPC ("딜러와 상담하기"). A bottom dialog box
-- (portrait, name / role, typewriter text, tap to skip) with choice buttons:
--   🚗 전체 차량 보기 · 🔥 이달의 특가 · 💰 예산에 맞는 차 추천 · 🔁 내 차 팔기 · 보상판매 (when the player owns a
--   car) · 🏁 시승 예약 · 🔑 하루 렌트 · 🧾 내 차 관리 (the garage's own panel) · 👋 그냥 둘러볼게요
-- The greeting depends on the dealer's memory (first visit / back again / tested a car / owner / garage full).
--   Dialog.open(npcInfo)   Dialog.close()   Dialog.isOpen()   Dialog.line(npcInfo, key, vars) (one bubble line)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Dialog = {}

local player = Players.LocalPlayer
local ctx: any
local Ui: any
local C: any
local U: any
local Lines: any

local gui: ScreenGui
local box: Frame
local portrait: TextLabel
local portraitRing: Frame
local nameLbl: TextLabel
local roleLbl: TextLabel
local textLbl: TextLabel
local skipHint: TextLabel
local choiceArea: ScrollingFrame
local closeBtn: any

local isOpen = false
local session = 0
local npc: any = nil
local pending: ((string?) -> ())? = nil
local typing = false
local skipTyping = false

local function voice(): string
	return (npc and npc.voice) or "consult"
end

local function line(key: string, vars: { [string]: any }?): string
	return Lines.get(voice(), key, vars)
end

-------------------------------------------------------------------------------------------------
-- layout
-------------------------------------------------------------------------------------------------
local function layout()
	if not box then
		return
	end
	local m = Ui.metrics()
	local W = math.min(980, m.w - 24)
	local portraitMode = m.portrait and m.w < 700
	local H = if portraitMode then math.min(340, m.h * 0.5) elseif m.compact then math.clamp(m.h * 0.5, 176, 214) else 236
	box.Size = UDim2.fromOffset(W, H)
	box.Position = UDim2.new(0.5, 0, 1, -12)
	local leftW = if portraitMode then W - 28 else math.floor((W - 28) * 0.54)
	local textTop = if m.compact then 50 else 58
	local textArea = box:FindFirstChild("TextArea") :: Frame
	textArea.Size = UDim2.fromOffset(leftW, if portraitMode then 120 else H - 28)
	choiceArea.Position = if portraitMode then UDim2.fromOffset(14, 14 + 128) else UDim2.fromOffset(14 + leftW + 12, 14)
	choiceArea.Size = if portraitMode then UDim2.fromOffset(W - 28, H - 28 - 128) else UDim2.fromOffset(W - 28 - leftW - 12, H - 28)
	portraitRing.Size = UDim2.fromOffset(if m.compact then 40 else 46, if m.compact then 40 else 46)
	portrait.TextSize = if m.compact then 22 else 26
	nameLbl.Position = UDim2.fromOffset(if m.compact then 50 else 56, 2)
	roleLbl.Position = UDim2.fromOffset(if m.compact then 50 else 56, if m.compact then 22 else 26)
	textLbl.Position = UDim2.fromOffset(0, textTop)
	textLbl.Size = UDim2.new(1, 0, 1, -textTop - 16)
	textLbl.TextSize = if m.compact then 15 else 17
	local grid = choiceArea:FindFirstChildOfClass("UIGridLayout")
	if grid then
		local cols = if portraitMode or (m.compact and choiceArea.AbsoluteSize.X > 300) then 2 else 1
		local cw = (choiceArea.Size.X.Offset - (cols - 1) * 8 - 6) / cols
		grid.CellSize = UDim2.fromOffset(cw, if m.compact then 40 else 44)
	end
end

local function build()
	gui = Ui.screen("GwangalliCarDealerDialog", C.UI.order.dialog)
	box = Ui.glass(gui, { Name = "Box", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Ui.C.bg2, BackgroundTransparency = 0.04 })
	Ui.grad(box, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 220), 90)
	local accent = Ui.frame(box, { Name = "Accent", Size = UDim2.new(0, 64, 0, 3), Position = UDim2.fromOffset(18, 0), BackgroundTransparency = 0, BackgroundColor3 = Ui.C.accent })
	Ui.corner(accent, 2)
	local textArea = Ui.frame(box, { Name = "TextArea", Position = UDim2.fromOffset(14, 14) })
	portraitRing = Ui.frame(textArea, { Name = "Portrait", BackgroundTransparency = 0, BackgroundColor3 = Ui.C.accentSoft })
	Ui.corner(portraitRing, 999)
	Ui.stroke(portraitRing, Ui.C.accent, 2, 0.1)
	portrait = Ui.label(portraitRing, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Text = "👩‍💼" })
	nameLbl = Ui.label(textArea, { Font = Ui.F.bold, TextSize = 17, Size = UDim2.new(1, -60, 0, 22) })
	roleLbl = Ui.label(textArea, { Font = Ui.F.med, TextSize = 12, TextColor3 = Ui.C.accent, Size = UDim2.new(1, -60, 0, 16) })
	textLbl = Ui.label(textArea, { Font = Ui.F.med, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "", LineHeight = 1.15 })
	skipHint = Ui.label(textArea, { Text = "▼", Font = Ui.F.bold, TextSize = 12, TextColor3 = Ui.C.faint, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(20, 14), TextXAlignment = Enum.TextXAlignment.Right, Visible = false })
	local tap = Ui.make("TextButton", { Name = "Skip", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = false, ZIndex = 3 }, textArea)
	tap.Activated:Connect(function()
		if typing then
			skipTyping = true
		end
	end)
	choiceArea = Ui.scroll(box, { Name = "Choices", AutomaticCanvasSize = Enum.AutomaticSize.Y })
	Ui.make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, CellSize = UDim2.fromOffset(200, 44) }, choiceArea)
	Ui.pad(choiceArea, 0, 6, 0, 2)
	closeBtn = Ui.button(box, { name = "Close", text = "✕", style = "ghost", size = UDim2.fromOffset(34, 34), anchor = Vector2.new(1, 0), pos = UDim2.new(1, -8, 0, 8), textSize = 14, radius = 17, z = 5 })
	closeBtn.onClick(function()
		Dialog.close()
	end)
	Ui.onLayout(layout)
	layout()
end

-------------------------------------------------------------------------------------------------
-- talking
-------------------------------------------------------------------------------------------------
local function clearChoices()
	for _, c in choiceArea:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
end

local function typeText(text: string, my: number)
	textLbl.Text = text
	local n = utf8.len(text) or #text
	local okG = pcall(function()
		textLbl.MaxVisibleGraphemes = 0
	end)
	if not okG or Ui.reduced() then
		pcall(function()
			textLbl.MaxVisibleGraphemes = -1
		end)
		return
	end
	typing = true
	skipTyping = false
	skipHint.Visible = false
	if npc then
		ctx.NpcFx.talk(npc.id, "talk")
	end
	local shown = 0
	local t0 = os.clock()
	while shown < n and not skipTyping and my == session and isOpen do
		task.wait()
		shown = math.floor((os.clock() - t0) * C.UI.typeSpeed)
		textLbl.MaxVisibleGraphemes = math.min(shown, n)
	end
	textLbl.MaxVisibleGraphemes = -1
	typing = false
	if npc then
		ctx.NpcFx.talk(npc.id, "listen")
	end
end

-- Says `text` and shows `choices` ({ id, label, style? }); yields until one is picked (nil when closed).
local function ask(text: string, choices: { any }): string?
	local my = session
	clearChoices()
	typeText(text, my)
	if my ~= session or not isOpen then
		return nil
	end
	local first: GuiObject? = nil
	for i, ch in choices do
		local b = Ui.button(choiceArea, {
			name = "Choice_" .. ch.id,
			text = ch.label,
			style = ch.style or (if i == 1 then "primary" else "secondary"),
			order = i,
			textSize = if Ui.metrics().compact then 13 else 14,
			align = Enum.TextXAlignment.Left,
		})
		b.onClick(function()
			if pending and my == session then
				local p = pending
				pending = nil
				p(ch.id)
			end
		end)
		if not Ui.reduced() then
			b.inst.BackgroundTransparency = 1
			Ui.tween(b.inst, 0.18 + i * 0.03, { BackgroundTransparency = if (ch.style or (if i == 1 then "primary" else "secondary")) == "ghost" then 0.4 else 0 })
		end
		first = first or b.inst
	end
	choiceArea.CanvasPosition = Vector2.zero
	Ui.select(first)
	local result: string? = nil
	local done = false
	pending = function(id: string?)
		result = id
		done = true
	end
	while not done and my == session and isOpen do
		task.wait()
	end
	pending = nil
	if my ~= session then
		return nil
	end
	return result
end

-- Says a line, waits `secs` (or a tap), returns false when the dialog closed meanwhile.
local function say(text: string, secs: number?): boolean
	local my = session
	clearChoices()
	typeText(text, my)
	if my ~= session or not isOpen then
		return false
	end
	local t0 = os.clock()
	while os.clock() - t0 < (secs or 1.4) and my == session and isOpen do
		task.wait()
	end
	return my == session and isOpen
end

-------------------------------------------------------------------------------------------------
-- branches
-------------------------------------------------------------------------------------------------
local function openCatalog(opts: { [string]: any })
	Dialog.close()
	ctx.CatalogUI.open(opts)
end

local function specialBranch(): boolean
	local st = ctx.Net.state
	local names = {}
	local first: string? = nil
	for _, e in st.entries do
		if e.special then
			table.insert(names, e.name .. " " .. (if e.grade == "used" then "중고" else "신차"))
			first = first or e.id
		end
	end
	if #names == 0 then
		return say(line("special_none"), 2)
	end
	local snap = st.snap or {}
	local month = tonumber(string.match(snap.month or "", "%-(%d+)$")) or tonumber(os.date("%m")) or 1
	local pick = ask(line("special_intro", { month = month, list = table.concat(names, " · "), pct = U.pct(C.SPECIALS.rate), days = snap.daysLeft or 1 }), {
		{ id = "see", label = "🔥 특가 차량 보기" },
		{ id = "back", label = "↩ 다른 것도 물어볼게요", style = "ghost" },
	})
	if pick == "see" then
		openCatalog({ cat = "special", npc = npc })
		return false
	end
	return pick ~= nil
end

local function budgetBranch(): boolean
	local pick = ask(line("budget_ask"), {
		{ id = "50", label = "💵 50만 원 이하" },
		{ id = "150", label = "💵 150만 원 이하", style = "secondary" },
		{ id = "500", label = "💵 500만 원 이하", style = "secondary" },
		{ id = "any", label = "💎 상관없어요 · 제일 좋은 차", style = "secondary" },
		{ id = "back", label = "↩ 다음에 할게요", style = "ghost" },
	})
	if pick == nil then
		return false
	end
	if pick == "back" then
		return true
	end
	local budget = if pick == "any" then nil else (tonumber(pick) :: number) * 10000
	local bank, cash = ctx.Net.money()
	local e, how = ctx.S.Catalog.recommend(ctx.Net.state.entries, budget, { bank = bank, cash = cash })
	if not e then
		return say(line("budget_none"), 2)
	end
	local text
	if how == "full" then
		text = line("budget_full", { car = e.name, price = U.won(e.price) })
	elseif how == "loan" and e.loan then
		text = line("budget_loan", { car = e.name, down = U.won(e.loan.down), daily = U.won(e.loan.daily), days = e.loan.days })
	else
		local have = math.max(bank, cash)
		text = line("budget_save", { car = e.name, short = U.won(math.max(0, e.price - have)) })
	end
	local next = ask(text, {
		{ id = "see", label = "👀 그 차 자세히 보기" },
		{ id = "all", label = "🚗 전체 차량 보기", style = "secondary" },
		{ id = "back", label = "↩ 다른 질문", style = "ghost" },
	})
	if next == "see" then
		openCatalog({ entry = e.id, pick = e.id, npc = npc })
		return false
	elseif next == "all" then
		openCatalog({ cat = "all", pick = e.id, npc = npc })
		return false
	end
	return next ~= nil
end

local function tradeBranch(): boolean
	local cars = ctx.Net.ownedCars()
	if #cars == 0 then
		return say(line("trade_none"), 2)
	end
	local bonusRate = (ctx.Net.state.snap and ctx.Net.state.snap.tradeBonus) or 0
	local choices = {}
	for i, c in cars do
		if i > 4 then
			break
		end
		local remaining = if type(c.loan) == "table" then (c.loan.remaining or 0) else 0
		local payout = (c.sell or 0) - remaining
		table.insert(choices, { id = c.id, label = string.format("%s %s · 매입 %s", c.glyph or "🚗", c.label or "내 차", U.man(math.max(0, payout))), style = "secondary" })
	end
	table.insert(choices, { id = "newcar", label = "🔁 보상판매로 새 차 고르기", style = "primary" })
	table.insert(choices, { id = "back", label = "↩ 다음에 할게요", style = "ghost" })
	local pick = ask(line("trade_intro", { bonus = U.pct(bonusRate) }), choices)
	if pick == nil then
		return false
	end
	if pick == "back" then
		return true
	end
	if pick == "newcar" then
		openCatalog({ cat = "all", trade = true, npc = npc })
		return false
	end
	local car = nil
	for _, c in cars do
		if c.id == pick then
			car = c
		end
	end
	if not car then
		return true
	end
	local res = ctx.Contract.sell(car)
	if res and res.ok then
		ctx.Net.refresh()
		return say(line("sold", { car = car.label or "내 차" }), 2.2)
	elseif res and res.message and res.message ~= "" then
		return say(res.message, 2.4)
	end
	return true
end

local BLOCK_KEYS = { shift = "test_shift", taxi = "test_taxi", cuffed = "test_cuffed", dead = "test_cuffed", busy = "test_busy" }

local function testBranch(): boolean
	local choices = {}
	local seen = {}
	for _, e in ctx.Net.state.entries do
		if e.grade == "new" and not seen[e.kind] and #choices < 6 and (not e.model or e.available) then
			seen[e.kind] = true
			table.insert(choices, { id = e.id, label = string.format("%s %s", e.glyph or "🚗", e.short or e.name), style = "secondary" })
		end
	end
	table.insert(choices, { id = "catalog", label = "📖 카탈로그에서 고를게요", style = "primary" })
	table.insert(choices, { id = "back", label = "↩ 다음에 할게요", style = "ghost" })
	local pick = ask(line("test_ask"), choices)
	if pick == nil then
		return false
	end
	if pick == "back" then
		return true
	end
	if pick == "catalog" then
		openCatalog({ cat = "all", npc = npc })
		return false
	end
	local e = ctx.Net.state.byId[pick]
	if not e then
		return true
	end
	local res = ctx.TestHud.request(e, nil)
	if res.ok then
		local name = e.short or e.name
		say(line("test_go", { car = name }), 1.6)
		Dialog.close()
		return false
	end
	local key = BLOCK_KEYS[res.code or ""]
	if res.code == "cooldown" then
		local sec = tonumber(string.match(res.message or "", "(%d+)")) or 30
		return say(line("test_cooldown", { sec = sec }), 2.2)
	elseif key then
		return say(line(key), 2.2)
	end
	return say(res.message or "지금은 시승을 준비하지 못했어요", 2.4)
end

local function rentBranch(): boolean
	local snap = ctx.Net.state.snap or {}
	if snap.rentActive then
		return say(line("rent_have"), 2)
	end
	local e = ctx.Net.state.byId["rent"]
	if not e then
		return say(line("offline"), 2)
	end
	local GS = ctx.GS
	local kindLabel = (GS and GS.CATALOG and GS.CATALOG[e.kind] and GS.CATALOG[e.kind].label) or "경차"
	local pick = ask(line("rent_ask", { car = kindLabel, minutes = math.floor((e.rentSeconds or 2400) / 60), fee = U.won(e.price) }), {
		{ id = "yes", label = "🔑 " .. U.won(e.price) .. " · 렌트할게요" },
		{ id = "no", label = "↩ 괜찮아요", style = "ghost" },
	})
	if pick ~= "yes" then
		return pick ~= nil
	end
	clearChoices()
	local res = ctx.Net.call("rent", nil)
	if res.ok then
		ctx.Net.refresh()
		Ui.sfx("money")
		say(line("rent_done"), 2.2)
		Dialog.close()
		return false
	end
	return say(res.message or "렌트를 처리하지 못했어요", 2.4)
end

local function openGarage(tab: string)
	Dialog.close()
	local ev = player:FindFirstChild(ctx.S.NAMES.Garage.Open)
	if ev and ev:IsA("BindableEvent") then
		ev:Fire({ tab = tab })
	else
		Ui.toast({ kind = "info", icon = "🔧", title = "내 차 관리", body = "박사장님 책상의 '상담 · 렌트 · 내 차'에서 열 수 있어요" })
	end
end

-------------------------------------------------------------------------------------------------
-- open / close
-------------------------------------------------------------------------------------------------
local function greeting(h: any): string
	local c = h.ctx or {}
	local vars = { player = player.DisplayName, car = c.testedName or c.ownedName or "", owned = c.owned or 0, max = c.max or 3 }
	if c.garageReady == false then
		return line("offline")
	end
	if c.full then
		return line("greet_full", vars)
	end
	if c.testedName and not c.first then
		vars.car = c.testedName
		return line("greet_tested", vars)
	end
	if c.ownedName and (c.owned or 0) > 0 then
		vars.car = c.ownedName
		return line("greet_owner", vars)
	end
	if c.first or (c.visits or 0) <= 1 then
		return line("greet_first", vars)
	end
	return line("greet_back", vars)
end

local function mainChoices(h: any): { any }
	local c = h.ctx or {}
	local list = {
		{ id = "all", label = "🚗 전체 차량 보기", style = "primary" },
		{ id = "special", label = "🔥 이달의 특가", style = "secondary" },
		{ id = "budget", label = "💰 예산에 맞는 차 추천", style = "secondary" },
	}
	if c.canSell and C.TRADEIN.enabled then
		table.insert(list, { id = "trade", label = "🔁 내 차 팔기 · 보상판매", style = "secondary" })
	end
	table.insert(list, { id = "test", label = "🏁 시승 예약", style = "secondary" })
	table.insert(list, { id = "rent", label = "🔑 하루 렌트", style = "secondary" })
	if (c.owned or 0) > 0 then
		table.insert(list, { id = "mine", label = "🧾 내 차 관리", style = "secondary" })
	end
	table.insert(list, { id = "bye", label = "👋 그냥 둘러볼게요", style = "ghost" })
	return list
end

local function bindKeys(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority("GwCarDealerDialogBack", function(_, state)
			if state == Enum.UserInputState.Begin then
				if UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Pass
				end
				Dialog.close()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 3000, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("GwCarDealerDialogBack")
	end
end

function Dialog.isOpen(): boolean
	return isOpen
end

function Dialog.close()
	if not isOpen then
		return
	end
	isOpen = false
	session += 1
	if pending then
		local p = pending
		pending = nil
		p(nil)
	end
	if npc then
		ctx.NpcFx.talk(npc.id, nil)
	end
	ctx.NpcFx.focus(nil)
	bindKeys(false)
	Ui.controls("dialog", true)
	Ui.deselect(gui)
	if Ui.reduced() then
		Ui.show(gui, false)
	else
		Ui.tween(box, 0.18, { Position = UDim2.new(0.5, 0, 1, 40) })
		task.delay(0.18, function()
			if not isOpen then
				Ui.show(gui, false)
			end
		end)
	end
	Ui.sfx("close")
end

function Dialog.open(info: any)
	if not gui then
		build()
	end
	if ctx.CatalogUI.isOpen() then
		ctx.CatalogUI.close()
	end
	if isOpen then
		Dialog.close()
	end
	session += 1
	local my = session
	isOpen = true
	npc = info
	portrait.Text = info.icon or "🧑‍💼"
	nameLbl.Text = info.name or "딜러"
	roleLbl.Text = (info.role or "영업 담당") .. " · 광안 오토"
	textLbl.Text = ""
	clearChoices()
	layout()
	Ui.show(gui, true)
	if not Ui.reduced() then
		box.Position = UDim2.new(0.5, 0, 1, 40)
		Ui.tween(box, 0.24, { Position = UDim2.new(0.5, 0, 1, -12) })
	end
	Ui.sfx("open")
	Ui.controls("dialog", false)
	bindKeys(true)
	ctx.NpcFx.focus(info.id)
	-- walk-away watcher
	task.spawn(function()
		while isOpen and my == session do
			task.wait(0.4)
			local pos = ctx.NpcFx.position(info.id)
			local ch = player.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if pos and r and (r :: BasePart).Position and ((r :: BasePart).Position - pos).Magnitude > 26 then
				Dialog.close()
			end
		end
	end)
	task.spawn(function()
		textLbl.Text = line("loading")
		local h = ctx.Net.call("hello", { npc = info.id })
		if my ~= session then
			return
		end
		ctx.Net.refresh()
		if my ~= session then
			return
		end
		if not h.ok then
			h = { ctx = { garageReady = false } }
		end
		local text = greeting(h)
		while isOpen and my == session do
			local pick = ask(text, mainChoices(h))
			if pick == nil or my ~= session then
				return
			end
			local keep = true
			if pick == "all" then
				openCatalog({ cat = info.tab or "all", npc = info })
				return
			elseif pick == "special" then
				keep = specialBranch()
			elseif pick == "budget" then
				keep = budgetBranch()
			elseif pick == "trade" then
				keep = tradeBranch()
			elseif pick == "test" then
				keep = testBranch()
			elseif pick == "rent" then
				keep = rentBranch()
			elseif pick == "mine" then
				say(line("mine"), 1.2)
				openGarage("mine")
				return
			elseif pick == "bye" then
				say(line("bye"), 1.4)
				Dialog.close()
				ctx.NpcFx.say(info.id, "천천히 둘러보세요 😊", 2.5)
				return
			end
			if not keep or my ~= session or not isOpen then
				return
			end
			text = line("menu")
		end
	end)
end

-- A single line from a dealer (no dialog box): the NPC bubble, or a toast when the NPC is not streamed in.
function Dialog.line(info: any, key: string, vars: { [string]: any }?)
	local v = (info and info.voice) or "consult"
	local text = Lines.get(v, key, vars)
	if info and ctx.NpcFx.find(info.id) then
		ctx.NpcFx.say(info.id, text, 4)
	else
		Ui.toast({ kind = "info", icon = (info and info.icon) or "💬", title = (info and info.name) or "광안 오토", body = text })
	end
end

function Dialog.init(c: any)
	ctx = c
	Ui = c.Ui
	C = c.C
	U = c.S.Util
	Lines = c.S.Lines
	player.CharacterAdded:Connect(function()
		Dialog.close()
	end)
end

return Dialog
