-- GwangalliFeatures/CashGive (owner: money): money with a player standing next to you.
--   * a local ProximityPrompt "돈 주고받기" (G / ButtonY) on every other player's character opens their
--     person card: 💵 현금 건네기 · 💸 계좌로 보내기 (transfer flow) · 🙏 송금 요청 (request flow) ·
--     요청 차단 toggle
--   * 현금 건네기: amount from the cash in your wallet -> "건네기" -> the other player gets an interactive
--     banner (받기 / 거절, 20 s ring) -> on 받기 both see a banknote fly from hand to hand
--   flows: "cashgive" {to = userId}, "person" {to = userId}
-- Server: BankRequest cashOffer / cashAnswer / cashCancel / block, BankEvent cashOffer / cashResolved.

local Players = game:GetService("Players")

local M = {}
M.flows = { "cashgive", "person" }

local F: any
local K: any
local G: any
local FK: any
local flow: any

local player = Players.LocalPlayer

local GIVE = { min = 1000, max = 500000, radius = 12, ttl = 20 }
local st: any = { target = nil, amount = 0, cash = nil, offerId = nil, blocked = {} }
local prompts: { [Player]: ProximityPrompt } = {}

local function nameOf(p: Player?): string
	if not p then
		return "?"
	end
	return if p.DisplayName ~= "" then p.DisplayName else p.Name
end

local function dist(userId: number): number?
	local p = Players:GetPlayerByUserId(userId)
	local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local b = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
		return (a.Position - b.Position).Magnitude
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------------------------
local function buildPerson(frame: Frame, fl: any): any
	local panes = FK.panes(frame, 0.42)
	local A, B = panes.a, panes.b
	local hero: Frame? = nil
	local nameL = K.text(A, { Name = "Name", Size = UDim2.new(1, 0, 0, 24), Text = "", Font = K.Font.bold, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local subL = K.text(A, { Name = "Sub", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local list = K.frame(B, { Name = "Actions", Size = UDim2.fromScale(1, 1), ZIndex = 24 })
	K.list(list, false, 8)
	local function action(name: string, icon: string, color: Color3, title: string, sub: string, order: number, fn: () -> ())
		local r = K.ListRow(list, { name = name, icon = icon, iconColor = color, title = title, subtitle = sub, chevron = true, height = 58, order = order, onClick = fn })
		return r
	end
	local cashRow = action("GiveCash", "💵", K.Color.teal, "현금 건네기", "지갑의 현금을 직접 건네요 (상대가 받기)", 1, function()
		fl.go("amount", {})
	end)
	action("Transfer", "💸", K.Color.cyan, "계좌로 보내기", "송금 · 수수료 0원", 2, function()
		local t = st.target
		fl.close()
		task.delay(0.2, function()
			F.open("transfer", { to = t.u, name = t.n })
		end)
	end)
	action("Request", "🙏", K.Color.gold, "송금 요청하기", "상대방 폰으로 요청이 가요", 3, function()
		local t = st.target
		fl.close()
		task.delay(0.2, function()
			F.open("request", { to = t.u, name = t.n })
		end)
	end)
	local blockRow = K.Card(list, { Name = "Block", Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 4, ZIndex = 24 })
	K.text(blockRow, { Name = "L", Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -90, 0, 18), Text = "요청·현금 받지 않기", Font = K.Font.bold, TextSize = K.Type.bodySm, ZIndex = 25 })
	K.text(blockRow, { Name = "S", Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, -90, 0, 15), Text = "이 사람의 송금 요청 / 현금 / 송금을 막아요", TextColor3 = K.Color.faint, TextSize = K.Type.micro, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local toggle = K.Toggle(blockRow, { value = false, color = K.Color.red, onChange = function(v: boolean)
		local t = st.target
		if not t then
			return
		end
		st.blocked[t.u] = v or nil
		local r = FK.call("block", { userId = t.u, on = v })
		if r.ok then
			K.toast({ kind = "info", title = if v then "차단했어요" else "차단을 풀었어요", body = t.n .. (if v then "님의 요청과 현금을 받지 않아요" else "님과 다시 주고받을 수 있어요"), icon = if v then "🚫" else "✅" })
		end
	end })
	toggle.button.AnchorPoint = Vector2.new(1, 0.5)
	toggle.button.Position = UDim2.new(1, -8, 0.5, 0)
	local page = { title = "돈 주고받기", subtitle = "" }
	local lastWide = false
	function page.layout(wide: boolean, w: number, h: number)
		lastWide = wide
		panes.layout(wide, w, h, 150)
		local ah = A.Size.Y.Offset
		local y0 = if wide then math.max(0, math.floor(ah / 2 - 70)) else 4
		if hero then
			hero.Position = UDim2.new(0.5, 0, 0, y0)
		end
		nameL.Position = UDim2.fromOffset(0, y0 + 80)
		subL.Position = UDim2.fromOffset(0, y0 + 106)
	end
	function page.show(_args: any)
		local t = st.target
		if hero then
			hero:Destroy()
		end
		hero = FK.avatar(A, 72, t.u, t.n)
		local hf = hero :: Frame
		hf.AnchorPoint = Vector2.new(0.5, 0)
		nameL.Text = t.n
		local d = dist(t.u)
		subL.Text = "@" .. (t.un or t.n) .. (if d then " · " .. FK.distText(d) else "")
		local near = d ~= nil and d <= GIVE.radius
		cashRow.subtitle.Text = if near then "지갑의 현금을 직접 건네요 (상대가 받기)" else "더 가까이 가야 건넬 수 있어요 (" .. K.meters(GIVE.radius) .. ")"
		toggle.set(st.blocked[t.u] == true, true)
		page.subtitle = "같은 서버 · 근처"
		fl.setTitle(page.title, page.subtitle)
		page.layout(lastWide, fl.size())
	end
	return page
end

local function buildAmount(frame: Frame, fl: any): any
	local panes = FK.panes(frame, 0.5)
	local A, B = panes.a, panes.b
	local toL = K.text(A, { Name = "To", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, ZIndex = 25, TextTruncate = Enum.TextTruncate.AtEnd })
	local amountV = FK.amountView(A, { height = 68, placeholder = "얼마를 건넬까요?" })
	local info = K.text(A, { Name = "Info", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
	local chipsRow = K.frame(A, { Name = "Quick", Size = UDim2.new(1, 0, 0, 44), ZIndex = 24 })
	K.list(chipsRow, true, 6)
	local padHost = K.frame(B, { Name = "PadHost", ZIndex = 24 })
	local giveBtn: TextButton
	local function validate(): boolean
		local n = st.amount
		local cash = st.cash or math.huge
		local ok = false
		if n <= 0 then
			amountV.setHint("건넬 현금을 입력해 주세요", K.Color.sub)
		elseif n < GIVE.min then
			amountV.setHint("1,000원부터 건넬 수 있어요", K.Color.orange)
		elseif n > GIVE.max then
			amountV.setHint("한 번에 최대 " .. K.wonShort(GIVE.max) .. "까지 건넬 수 있어요", K.Color.red)
		elseif n > cash then
			amountV.setHint("지갑에 현금이 부족해요 · " .. K.won(cash), K.Color.red)
		else
			amountV.setHint(FK.koreanWon(n) .. " 건네기", K.Color.teal)
			ok = true
		end
		K.setButtonEnabled(giveBtn, ok)
		return ok
	end
	local function setAmount(n: number, pop: boolean?)
		st.amount = math.max(0, math.floor(n))
		amountV.set(st.amount, pop)
		validate()
	end
	for i, def in { { "+1천", 1000 }, { "+5천", 5000 }, { "+1만", 10000 }, { "+5만", 50000 }, { "전부", -1 } } do
		K.Chip(chipsRow, { name = "Q" .. i, text = def[1], order = i, minWidth = 48, onClick = function()
			if def[2] < 0 then
				setAmount(math.min(st.cash or 0, GIVE.max), true)
			else
				setAmount(math.min(st.amount + def[2], GIVE.max), true)
			end
		end })
	end
	local pad = FK.keypad(padHost, { onKey = function(k: string)
		if k == "back" then
			setAmount(st.amount // 10)
		elseif k == "clear" then
			setAmount(0)
		else
			local n = tonumber((if st.amount > 0 then tostring(st.amount) else "") .. k) or 0
			if n > 9999999 then
				amountV.error("금액이 너무 커요")
				return
			end
			setAmount(n, true)
		end
	end })
	giveBtn = K.Button(frame, { name = "Give", text = "💵 건네기", style = "success", zIndex = 25, onClick = function()
		if not validate() then
			amountV.error(amountV.hint.Text)
			return
		end
		K.setButtonLoading(giveBtn, true, "건네는 중…")
		local r = FK.call("cashOffer", { to = st.target.u, amount = st.amount, rid = FK.rid() })
		K.setButtonLoading(giveBtn, false)
		if r.ok then
			st.offerId = r.offerId
			fl.go("wait", { expiresIn = r.expiresIn })
		else
			amountV.error(r.message)
		end
	end })
	local page = { title = "현금 건네기", subtitle = "" }
	local lastWide = false
	function page.layout(wide: boolean, w: number, h: number)
		lastWide = wide
		local p = 12
		if wide then
			panes.layout(true, w, h, 0)
			amountV.frame.Position = UDim2.fromOffset(4, 30)
			info.Position = UDim2.fromOffset(4, 100)
			chipsRow.Position = UDim2.fromOffset(0, 120)
			giveBtn.Size = UDim2.fromOffset(A.Size.X.Offset, 48)
			giveBtn.Position = UDim2.fromOffset(p, h - p - 48)
			padHost.Size = UDim2.fromScale(1, 1)
			pad.layout(B.Size.X.Offset, B.Size.Y.Offset)
		else
			panes.layout(false, w, h, 172)
			amountV.frame.Position = UDim2.fromOffset(4, 30)
			info.Position = UDim2.fromOffset(4, 100)
			chipsRow.Position = UDim2.fromOffset(0, 120)
			giveBtn.Size = UDim2.fromOffset(w - p * 2, 48)
			giveBtn.Position = UDim2.fromOffset(p, h - p - 48)
			local bh = B.Size.Y.Offset - 60
			padHost.Size = UDim2.new(1, 0, 0, bh)
			pad.layout(B.Size.X.Offset, bh)
		end
	end
	function page.show(_args: any)
		local t = st.target
		toL.Text = t.n .. "님에게 현금 건네기"
		page.subtitle = "상대가 '받기'를 눌러야 건네져요"
		fl.setTitle(page.title, page.subtitle)
		setAmount(0)
		info.Text = "지갑 확인 중…"
		page.layout(lastWide, fl.size())
		task.spawn(function()
			local s = FK.call("summary", {})
			if s.ok then
				st.cash = s.cash
				GIVE.min = s.giveMin or GIVE.min
				GIVE.max = s.giveMax or GIVE.max
				info.Text = string.format("💵 내 현금 %s · 한 번에 최대 %s", K.won(s.cash), K.wonShort(GIVE.max))
				validate()
			else
				info.Text = s.message
			end
		end)
	end
	return page
end

local function buildWait(frame: Frame, fl: any): any
	local holder = K.frame(frame, { Name = "Wait", Size = UDim2.fromScale(1, 1), ZIndex = 24 })
	local av: Frame? = nil
	local ring = K.Ring(holder, { size = 96, thickness = 4, color = K.Color.teal, text = "" })
	ring.frame.AnchorPoint = Vector2.new(0.5, 0)
	FK.raise(ring.frame, 26)
	local titleL = K.text(holder, { Name = "Title", Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 0), Text = "", Font = K.Font.bold, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local subL = K.text(holder, { Name = "Sub", Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 0), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local cancel = K.Button(holder, { name = "Cancel", text = "취소", style = "secondary", size = UDim2.fromOffset(160, 44), zIndex = 25, onClick = function()
		if st.offerId then
			FK.call("cashCancel", { offerId = st.offerId, rid = FK.rid() })
			st.offerId = nil
		end
		fl.back()
	end })
	cancel.AnchorPoint = Vector2.new(0.5, 0)
	local serial = 0
	local page = { title = "건네는 중", subtitle = "", back = false }
	function page.layout(_wide: boolean, _w: number, h: number)
		local y0 = math.max(4, math.floor(h / 2 - 110))
		ring.frame.Position = UDim2.new(0.5, 0, 0, y0)
		if av then
			av.Position = UDim2.new(0.5, 0, 0, y0 + 12)
		end
		titleL.Position = UDim2.new(0, 12, 0, y0 + 108)
		subL.Position = UDim2.new(0, 12, 0, y0 + 136)
		cancel.Position = UDim2.new(0.5, 0, 0, y0 + 166)
	end
	function page.show(args: any)
		local t = st.target
		if av then
			av:Destroy()
		end
		av = FK.avatar(holder, 72, t.u, t.n)
		local a = av :: Frame
		a.AnchorPoint = Vector2.new(0.5, 0)
		titleL.Text = t.n .. "님이 받기를 기다려요"
		subL.Text = string.format("💵 %s · 상대 화면에 '받기' 버튼이 떴어요", K.won(st.amount))
		page.layout(false, fl.size())
		serial += 1
		local mine = serial
		local ttl = tonumber(args.expiresIn) or GIVE.ttl
		local t0 = os.clock()
		local track = ring.frame:FindFirstChild("Track")
		local trackStroke = track and track:FindFirstChildOfClass("UIStroke")
		if trackStroke then
			K.breathe(trackStroke, true, 0.3, 0.9)
		end
		task.spawn(function()
			while serial == mine and fl.current() == "wait" do
				local left = ttl - (os.clock() - t0)
				ring.set(math.max(0, left / ttl))
				if left <= -2 then
					-- the server's expiry event normally arrives first
					st.offerId = nil
					K.toast({ kind = "info", title = "응답이 없어요", body = t.n .. "님이 받지 않아서 현금을 그대로 뒀어요", icon = "⌛" })
					fl.back()
					break
				end
				task.wait(0.2)
			end
		end)
	end
	function page.hide()
		serial += 1
	end
	return page
end

local function buildDone(frame: Frame, fl: any): any
	local holder = K.frame(frame, { Name = "Done", Size = UDim2.fromScale(1, 1), ZIndex = 24 })
	local check = FK.checkmark(holder, 76, K.Color.teal)
	check.frame.AnchorPoint = Vector2.new(0.5, 0)
	local titleL = K.text(holder, { Name = "Title", Size = UDim2.new(1, -24, 0, 26), Text = "", Font = K.Font.bold, TextSize = K.Type.title, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local subL = K.text(holder, { Name = "Sub", Size = UDim2.new(1, -24, 0, 18), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	local ok = K.Button(holder, { name = "Ok", text = "확인", style = "primary", size = UDim2.fromOffset(180, 46), zIndex = 25, onClick = function()
		fl.close()
	end })
	ok.AnchorPoint = Vector2.new(0.5, 0)
	local page = { title = "", subtitle = "", back = false }
	function page.layout(_wide: boolean, _w: number, h: number)
		local y0 = math.max(4, math.floor(h / 2 - 100))
		check.frame.Position = UDim2.new(0.5, 0, 0, y0)
		titleL.Position = UDim2.new(0, 12, 0, y0 + 88)
		subL.Position = UDim2.new(0, 12, 0, y0 + 118)
		ok.Position = UDim2.new(0.5, 0, 0, y0 + 148)
	end
	function page.show(args: any)
		titleL.Text = string.format("현금 %s을 건넸어요", K.won(args.amount or st.amount))
		subL.Text = string.format("%s님이 받았어요 · 내 현금 %s", (st.target and st.target.n) or "", K.won(args.cash or 0))
		page.layout(false, fl.size())
		check.play()
		task.delay(0.2, function()
			FK.confetti(fl.card, 12)
		end)
		K.feedback("money")
	end
	return page
end

-------------------------------------------------------------------------------------------------
-- Prompts on other players
-------------------------------------------------------------------------------------------------
local function attachPrompt(other: Player, character: Model)
	local old = prompts[other]
	if old then
		old:Destroy()
		prompts[other] = nil
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) or other.Parent ~= Players then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "GwangalliMoneyPrompt"
	p.ActionText = "돈 주고받기"
	p.ObjectText = nameOf(other)
	p.HoldDuration = 0.25
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.G
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.UIOffset = Vector2.new(0, 36)
	p.Enabled = not F.isModal()
	p.Triggered:Connect(function()
		F.open("person", { to = other.UserId })
	end)
	p.Parent = root
	prompts[other] = p
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(ch)
		attachPrompt(other, ch)
	end)
	if other.Character then
		task.spawn(attachPrompt, other, other.Character)
	end
end

-------------------------------------------------------------------------------------------------
-- Entry points + events
-------------------------------------------------------------------------------------------------
local function targetOf(args: any): any?
	local u = tonumber(args.to)
	if not u or u == player.UserId then
		return nil
	end
	local p = Players:GetPlayerByUserId(u)
	if not p then
		K.toast({ kind = "warn", title = "돈 주고받기", body = "그 사람은 이 서버에 없어요" })
		return nil
	end
	return { u = u, n = nameOf(p), un = p.Name }
end

function M.open(flowId: string, args: any)
	local t = targetOf(args)
	if not t then
		return
	end
	st.target = t
	st.amount = 0
	st.offerId = nil
	if flowId == "cashgive" then
		flow.open("amount", {})
	else
		flow.open("person", {})
	end
end

function M.close()
	if flow then
		flow.close()
	end
end

function M.isOpen(): boolean
	return flow ~= nil and flow.isOpen()
end

local function onEvent(e: any)
	if type(e) ~= "table" then
		return
	end
	if e.kind == "cashOffer" and type(e.offer) == "table" then
		local o = e.offer
		if type(o.id) ~= "string" or type(o.amount) ~= "number" then
			return
		end
		FK.incoming({
			id = "cash_" .. o.id,
			userId = o.fromId,
			name = o.fromName,
			color = K.Color.teal,
			title = string.format("💵 현금 %s", K.won(o.amount)),
			body = string.format("%s님이 현금을 건네요", tostring(o.fromName)),
			timeout = math.min(GIVE.ttl, tonumber(o.expiresIn) or GIVE.ttl),
			secondary = { text = "거절", onClick = function()
				FK.call("cashAnswer", { offerId = o.id, accept = false, rid = FK.rid() })
			end },
			primary = { text = "받기", style = "success", onClick = function()
				local r = FK.call("cashAnswer", { offerId = o.id, accept = true, rid = FK.rid() })
				if r.ok and r.accepted then
					K.toast({ kind = "money", title = string.format("현금 %s을 받았어요", K.won(r.amount or o.amount)), body = string.format("%s님이 건넸어요 · 내 현금 %s", tostring(o.fromName), K.won(r.cash or 0)), icon = "💵" })
					FK.bill(o.fromId, player.UserId, 3)
				else
					K.toast({ kind = "error", title = "현금을 받지 못했어요", body = r.message })
				end
			end },
		})
	elseif e.kind == "cashResolved" then
		if type(e.offerId) == "string" then
			FK.dismissIncoming("cash_" .. e.offerId)
		end
		local mine = st.offerId ~= nil and e.offerId == st.offerId
		if e.accepted and mine then
			st.offerId = nil
			FK.bill(player.UserId, e.toId or 0, 3)
			flow.replace("done", { amount = e.amount, cash = e.cash })
		elseif mine and (e.declined or e.failed or e.expired or e.cancelled) then
			st.offerId = nil
			local who = (st.target and st.target.n) or "상대방"
			local body = if e.declined then who .. "님이 거절했어요" elseif e.expired then who .. "님이 받지 않았어요" elseif e.failed then (if G then G.bankMessage(e.failed) else "건네지 못했어요") else who .. "님이 떠났어요"
			K.toast({ kind = "info", title = "현금을 건네지 못했어요", body = body, icon = "💵" })
			if flow.isOpen() and flow.current() == "wait" then
				flow.back()
			end
		elseif e.cancelled and not mine then
			K.toast({ kind = "info", title = "현금 건네기가 취소됐어요", body = tostring(e.fromName or "상대방") .. "님이 취소했어요", icon = "💵" })
		end
	end
end

function M.init(ctx: any)
	F = ctx
	K = ctx.K
	G = ctx.G
	FK = require(script.Parent:WaitForChild("FeatureKit"))
	FK.bind(ctx)
	if G and G.BANK then
		GIVE.min = G.BANK.giveMin
		GIVE.max = G.BANK.giveMax
		GIVE.radius = G.BANK.giveRadius
		GIVE.ttl = G.BANK.offerTTL
	end
	flow = FK.Flow("cash", { title = "돈 주고받기", accent = K.Color.teal })
	flow.page("person", buildPerson)
	flow.page("amount", buildAmount)
	flow.page("wait", buildWait)
	flow.page("done", buildDone)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p)
		local pr = prompts[p]
		if pr then
			pr:Destroy()
			prompts[p] = nil
		end
		if st.target and st.target.u == p.UserId and flow.isOpen() then
			flow.close()
			K.toast({ kind = "info", title = "돈 주고받기", body = nameOf(p) .. "님이 서버를 떠났어요" })
		end
	end)
	-- no prompts over an open flow (they would steal the E / G keys and the taps)
	F.on("modal", function(on: boolean)
		for _, pr in prompts do
			pr.Enabled = not on
		end
	end)
	task.spawn(function()
		local ev = F.remote("BankEvent", 60)
		if ev and ev:IsA("RemoteEvent") then
			ev.OnClientEvent:Connect(function(e: any)
				local ok, err = pcall(onEvent, e)
				if not ok then
					warn("[GwangalliFeatures] cash event: " .. tostring(err))
				end
			end)
		end
	end)
end

return M
