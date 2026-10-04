-- GwangalliClubShow/Ui (client): the fallback screens of the club show layer, built only with the
-- GwangalliUI kit (until the HUD owner wires its own sheet - docs/CLUB_SHOW.md):
--   * door entry sheet (Club.server ClubRemote "door" / "quote"): walk-in fee or "테이블 예약 입장",
--     wallet line, the MD's guest-list hint; pays with ClubRemote ("doorPay", option)
--   * bottle menu sheet (ShowEvent "menu"): tiers with prices against the wallet, confirm bar with
--     the balance after, "✨ 합석 이벤트" button when the table may ask for it -> ShowRequest
--   * receipt / status toasts (ShowEvent "order", "booking", "toast")
--   * the 합석 action card (top-right slot): 짠 / 같이 춤 / 번호 교환 / 잘 가요 -> ShowRequest "act"
--   * a short black fade when the server walks the player back out of the club
-- Sheets are modal on touch (character controls paused while open, HideGwangalliHUD set).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = {}

local C: any
local S: any
local K: any
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local host: Frame? = nil
local sheet: any = nil
local sheetKind = "" -- "door" | "menu"
local sheetSide = ""
local controlsOff = false
local actionCard: Frame? = nil
local actionButtons: { [string]: TextButton } = {}
local fade: Frame? = nil

local function setControls(enabled: boolean)
	if enabled == not controlsOff then
		return
	end
	controlsOff = not enabled
	pcall(function()
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			local controls = (require(pm) :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function ensureGui(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliClubShowUI"
	g.DisplayOrder = 46
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local h = Instance.new("Frame")
	h.Name = "Host"
	h.BackgroundTransparency = 1
	h.Size = UDim2.fromScale(1, 1)
	h.Parent = g
	g.Parent = pg
	gui, host = g, h
	return g
end

local function landscape(): boolean
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	return vp.X > vp.Y
end

local function closeSheet()
	if sheet and sheet.isOpen() then
		sheet.close()
	end
end

local function onSheetClosed()
	setControls(true)
	if gui then
		gui:SetAttribute("HideGwangalliHUD", false)
	end
	sheetKind = ""
end

-- a fresh sheet each time the side changes (rotation); content cleared per open
local function openSheet(kind: string, title: string, subtitle: string?): Frame?
	if not K or not ensureGui() or not host then
		return nil
	end
	local side = if landscape() then "right" else "bottom"
	if not sheet or sheetSide ~= side then
		if sheet then
			pcall(function()
				sheet.close(true)
				sheet.frame:Destroy()
				if sheet.dim then
					sheet.dim:Destroy()
				end
			end)
		end
		local width: any = 0.42
		if side == "right" and C.Layout then
			local ok, r = pcall(C.Layout.rect, "sheetRight")
			if ok and type(r) == "table" and r.w then
				width = math.floor(r.w)
			end
		end
		sheet = K.BottomSheet(host, { name = "ClubShowSheet", title = title, subtitle = subtitle, side = side, width = width, height = 0.68, zIndex = 40, onClose = onSheetClosed })
		sheetSide = side
	end
	for _, ch in sheet.content:GetChildren() do
		ch:Destroy()
	end
	sheet.setTitle(title, subtitle)
	sheetKind = kind
	sheet.open()
	setControls(false)
	if gui then
		gui:SetAttribute("HideGwangalliHUD", true)
	end
	return sheet.content
end

local function list(parent: Instance, pad: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, pad or 8)
	l.Parent = parent
	return l
end

local function walletText(cash: any, bank: any): string
	if type(cash) ~= "number" and type(bank) ~= "number" then
		return "💳 결제: 통장(체크카드) 먼저, 부족하면 현금"
	end
	return string.format("💵 현금 %s   🏦 통장 %s", C.won(cash or 0), C.won(bank or 0))
end

local function caption(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	local t = K.text(parent, {
		Name = "Caption",
		Text = text,
		TextSize = K.Type.caption,
		TextColor3 = color or K.Color.sub,
		Size = UDim2.new(1, 0, 0, 18),
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
	})
	return t
end

---------------------------------------------------------------------------------------------------
-- Door entry sheet
---------------------------------------------------------------------------------------------------
local doorUi: any = nil

local function clubRemote(): RemoteEvent?
	local names = C.Club.Names or {}
	local r = ReplicatedStorage:FindFirstChild(names.Remote or "ClubRemote")
	return if r and r:IsA("RemoteEvent") then r else nil
end

function Ui.doorSheet(p: any)
	local wb = math.floor(((p.wristbandSeconds or 1440) / 60) + 0.5)
	local content = openSheet("door", "CLUB OCEAN 입장 🎟️", string.format("%s 밤 · 팔찌 차면 %d분 동안 재입장 무료", if p.weekend then "주말" else "평일", wb))
	if not content then
		return
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -58)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 3
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = content
	list(scroll, 8)
	caption(scroll, walletText(p.cash, p.bank), 1, K.Color.text)
	local selected = "ticket"
	local rows: { [string]: any } = {}
	local prices: { [string]: number } = {}
	local payBtn: TextButton
	local errLabel: TextLabel
	local function refresh()
		for id, r in rows do
			local on = id == selected
			r.row.BackgroundColor3 = if on then K.Color.card2 else K.Color.card
			local st = r.row:FindFirstChild("SelStroke")
			if st then
				(st :: UIStroke).Transparency = if on then 0.1 else 0.9
			end
		end
		local price = prices[selected] or 0
		payBtn.Text = if p.priced == false then "입장하기 (오늘 무료 이벤트)" else string.format("결제하고 입장 · %s", C.won(price))
		local total = (p.cash or 0) + (p.bank or 0)
		local can = p.priced == false or type(p.cash) ~= "number" or total >= price
		K.setButtonEnabled(payBtn, can)
		errLabel.Text = if can then "" else "잔액이 부족해요 · 알바하고 다시 와요 💪"
	end
	for i, opt in p.options or {} do
		local isTable = opt.id == "table"
		local tableItem = isTable and S.item(opt.set or "basic")
		prices[opt.id] = opt.price
		local r = K.ListRow(scroll, {
			name = "Opt_" .. opt.id,
			icon = if isTable then "🧊" else "🎟️",
			iconColor = if isTable then K.Color.cyan else K.Color.magenta,
			title = if isTable then "테이블 예약 입장" else "입장권",
			subtitle = if isTable then string.format("%s + 테이블 · 입장료 면제", tableItem and S.label(tableItem, nil) or "기본 세트") else "팔찌 · 재입장 무료",
			trailing = C.won(opt.price),
			trailingColor = K.Color.gold,
			height = 60,
			order = 10 + i,
			onClick = function()
				selected = opt.id
				K.feedback("tap")
				refresh()
			end,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Name = "SelStroke"
		stroke.Color = K.Color.gold
		stroke.Thickness = 1.5
		stroke.Transparency = 0.9
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = r.row
		rows[opt.id] = r
	end
	if type(p.mdCover) == "number" then
		caption(scroll, string.format("💡 MD 태양에게 말하면 게스트 리스트 (스타일 좋으면 무료 · 아니면 %s)", C.won(p.mdCover)), 40)
	end
	caption(scroll, "VIP(외모 60↑) · 테이블 예약자 · 친구 찬스는 무료 입장", 41)
	errLabel = caption(scroll, "", 42, K.Color.red)
	payBtn = K.Button(content, {
		name = "Pay",
		text = "결제하고 입장",
		style = "gold",
		size = UDim2.new(1, 0, 0, 48),
		position = UDim2.new(0, 0, 1, -50),
		onClick = function()
			local r = clubRemote()
			if not r then
				return
			end
			K.setButtonLoading(payBtn, true, "결제 중…")
			pcall(function()
				r:FireServer("doorPay", selected)
			end)
			task.delay(9, function()
				if doorUi and doorUi.pay == payBtn then
					K.setButtonLoading(payBtn, false)
				end
			end)
		end,
	})
	doorUi = { pay = payBtn, err = errLabel, refresh = refresh }
	refresh()
end

-- server answers on the door (ClubRemote "door")
function Ui.doorResult(p: any)
	local state = p.state
	if state == "quote" then
		Ui.doorSheet(p)
		return
	end
	if doorUi then
		pcall(K.setButtonLoading, doorUi.pay, false)
	end
	if state == "paid" or state == "granted" then
		if sheetKind == "door" then
			closeSheet()
		end
		if state == "granted" then
			local why = ({ vip = "VIP 패스", guest = "게스트 리스트", table = "테이블 예약", friend = "친구 찬스", event = "무료 입장 이벤트" })[p.reason or ""] or "무료 입장"
			C.toast("입장 확인 · " .. why .. " 🎟️", "가드가 길을 비켜 줬어요. 즐거운 밤 보내세요!", "🎟️", "club")
		elseif p.table then
			C.toast(string.format("테이블 %s 예약 완료 🧊", p.table), "들어가서 테이블 프롬프트로 앉으세요", "🧊", "club")
		end
	elseif state == "valid" then
		if sheetKind == "door" then
			closeSheet()
		end
		C.toast("팔찌 확인 · 재입장 🎟️", "오늘 밤은 팔찌로 자유롭게 들어갈 수 있어요", "🎟️", "club")
	elseif state == "nofunds" then
		if doorUi then
			doorUi.err.Text = string.format("잔액이 부족해요 (%s 필요) · 통장 + 현금", C.won(p.price or 0))
		end
		K.feedback("error")
	elseif state == "error" then
		C.toast("결제를 처리하지 못했어요", "잠시 후 다시 해 주세요", "⚠️", "warn")
	elseif state == "far" then
		C.toast("가드 앞에서 결제해 주세요", "입구에서 '입장하기'", "🖐️", "warn")
	elseif state == "eject" then
		Ui.fade()
		C.toast("팔찌 없이 입장 불가 🖐️", "가드가 입구로 안내했어요 · '입장하기'로 팔찌를 받아요", "🖐️", "warn")
	end
end

function Ui.fade()
	if not ensureGui() or not gui then
		return
	end
	local f = fade
	if not f or not f.Parent then
		local nf = Instance.new("Frame")
		nf.Name = "Fade"
		nf.BackgroundColor3 = Color3.new(0, 0, 0)
		nf.BackgroundTransparency = 1
		nf.BorderSizePixel = 0
		nf.Size = UDim2.new(1, 0, 1, 80)
		nf.Position = UDim2.fromOffset(0, -60)
		nf.ZIndex = 100
		nf.Active = false
		nf.Parent = gui
		fade = nf
		f = nf
	end
	local fr = f :: Frame
	fr.BackgroundTransparency = 0.05
	C.tween(fr, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.15)
end

---------------------------------------------------------------------------------------------------
-- Bottle menu sheet
---------------------------------------------------------------------------------------------------
local menuState: any = nil

local function showRequest(): RemoteEvent?
	local f = ReplicatedStorage:FindFirstChild(S.Folder)
	local r = f and f:FindFirstChild(S.Remote.Request)
	return if r and r:IsA("RemoteEvent") then r else nil
end

function Ui.request(op: string, a: any?, b: any?)
	local r = showRequest()
	if r then
		pcall(function()
			r:FireServer(op, a, b)
		end)
	end
end

function Ui.menu(p: any)
	local sub = p.label or p.table
	if p.owned then
		sub = string.format("내 테이블 · %s", p.label or p.table)
	elseif p.takenBy then
		sub = string.format("%s님 테이블이에요", p.takenBy)
	end
	if p.showBusy then
		sub ..= " · 퍼레이드 진행 중 (주문은 대기열)"
	end
	local content = openSheet("menu", if p.aa then "테이블 서비스 ✨" else "보틀 서비스 🍾", sub)
	if not content then
		return
	end
	local total = (p.cash or 0) + (p.bank or 0)
	local priced = p.priced ~= false
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -76)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 3
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = content
	list(scroll, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = scroll
	caption(scroll, if priced then walletText(p.cash, p.bank) else "🎉 오늘은 이벤트 무료 서비스", 1, K.Color.text)
	if p.booking == "available" then
		K.Button(scroll, {
			name = "Booking",
			text = "✨ 합석 이벤트 신청 (MD가 새 친구들을 데려와요)",
			style = "bridge",
			size = UDim2.new(1, 0, 0, 46),
			order = 2,
			onClick = function()
				Ui.request("booking", p.table)
				closeSheet()
			end,
		})
	elseif p.booking == "running" then
		caption(scroll, "✨ 합석 이벤트 진행 중이에요", 2, K.Color.gold)
	elseif p.booking == "cooldown" then
		caption(scroll, "✨ 합석 이벤트는 조금 쉬었다가 다시 신청할 수 있어요", 2)
	elseif p.booking == "locked" then
		caption(scroll, "✨ 보드카 세트 이상 주문하면 합석 이벤트를 신청할 수 있어요", 2)
	end
	local selected: string? = nil
	local rows: { [string]: any } = {}
	local orderBtn: TextButton
	local after: TextLabel
	local function refresh()
		for id, r in rows do
			local on = id == selected
			local st = r.row:FindFirstChild("SelStroke")
			if st then
				(st :: UIStroke).Transparency = if on then 0.05 elseif r.parade then 0.55 else 0.9
			end
			r.row.BackgroundColor3 = if on then K.Color.card2 else K.Color.card
		end
		local item = selected and S.item(selected)
		if not item then
			orderBtn.Text = "메뉴를 골라 주세요"
			K.setButtonEnabled(orderBtn, false)
			after.Text = if (p.cooldown or 0) > 0 then string.format("다음 주문까지 %d초", p.cooldown) else ""
			return
		end
		local price = 0
		for _, it in p.items do
			if it.id == selected then
				price = it.price
			end
		end
		orderBtn.Text = if priced then string.format("주문하기 · %s", C.won(price)) else "주문하기 (무료)"
		local can = not priced or type(p.cash) ~= "number" or total >= price
		K.setButtonEnabled(orderBtn, can and p.takenBy == nil)
		if not can then
			after.Text = "잔액이 부족해요 (통장 + 현금)"
		elseif priced and type(p.cash) == "number" then
			after.Text = string.format("결제 후 잔액 %s · 통장 먼저 결제", C.won(total - price))
		else
			after.Text = ""
		end
	end
	for i, it in p.items or {} do
		local afford = not priced or type(p.cash) ~= "number" or total >= it.price
		local badge = if it.tier >= 5 then " · 🎆 풀코스" elseif it.booking then " · ✨ 합석" elseif it.parade then " · 🎆 퍼레이드" else ""
		local r = K.ListRow(scroll, {
			name = "Item_" .. it.id,
			icon = it.icon,
			iconColor = if it.tier >= 4 then K.Color.gold elseif it.tier >= 2 then K.Color.magenta else K.Color.cyan,
			title = it.label .. badge,
			subtitle = if afford then it.desc else ("잔액 부족 · " .. it.desc),
			trailing = if priced then C.won(it.price) else "무료",
			trailingColor = if afford then K.Color.gold else K.Color.faint,
			trailingWidth = 104,
			height = 62,
			order = 10 + i,
			onClick = function()
				selected = it.id
				K.feedback("tap")
				refresh()
			end,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Name = "SelStroke"
		stroke.Color = K.Color.gold
		stroke.Thickness = 1.5
		stroke.Transparency = if it.parade then 0.55 else 0.9
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = r.row
		if not afford then
			r.title.TextTransparency = 0.45
		end
		r.parade = it.parade
		rows[it.id] = r
	end
	caption(scroll, if p.aa then "모든 메뉴는 무알콜 음료예요 · 가격은 서버가 정해요" else "가격은 서버가 정해요 · 영수증은 알림으로 와요", 90)
	orderBtn = K.Button(content, {
		name = "Order",
		text = "메뉴를 골라 주세요",
		style = "gold",
		size = UDim2.new(1, 0, 0, 48),
		position = UDim2.new(0, 0, 1, -68),
		onClick = function()
			if not selected then
				return
			end
			K.setButtonLoading(orderBtn, true, "주문 중…")
			Ui.request("order", p.table, selected)
			task.delay(1.2, closeSheet)
		end,
	})
	after = K.text(content, {
		Name = "After",
		Text = "",
		TextSize = K.Type.micro,
		TextColor3 = K.Color.sub,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, -2),
		Size = UDim2.new(1, -4, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	menuState = { table = p.table }
	refresh()
end

local ORDER_TEXT = {
	wait = { "잠시 후에 다시 주문할 수 있어요", "⏳" },
	busy = { "이 테이블은 방금 주문이 들어갔어요", "⏳" },
	taken = { "다른 손님 테이블이에요", "🙅" },
	other = { "이미 다른 테이블을 쓰고 있어요", "🙅" },
	paying = { "결제 처리 중이에요…", "💳" },
	far = { "테이블 가까이에서 주문해 주세요", "🚶" },
	nofunds = { "잔액이 부족해요 (통장 + 현금)", "💸" },
	error = { "주문을 처리하지 못했어요. 다시 해 주세요", "⚠️" },
	showfull = { "퍼레이드 대기열이 가득 찼어요. 잠시 후에 주문해 주세요", "⏳" },
}

function Ui.order(p: any)
	local status = p.status
	if status == "ok" or status == "queued" or status == "served" then
		local body = if status == "queued" then string.format("퍼레이드 대기 %d초 · 순서가 오면 출발해요", p.wait or 0) elseif status == "served" then "테이블로 바로 나가요" elseif (p.tier or 1) >= 2 then "퍼레이드 출발! LED 월을 봐요 ✨" else "곧 테이블로 나가요"
		local price = if p.free then "무료" else C.won(p.price or 0)
		C.toast(string.format("영수증 · %s · %s", p.table or "", price), string.format("%s %s · %s", p.icon or "🍾", p.label or "", body), p.icon or "🍾", "money")
		if p.booking == "available" then
			task.delay(4, function()
				C.toast("✨ 합석 이벤트 신청 가능", "테이블 메뉴에서 MD에게 새 친구들을 불러 달라고 해 봐요", "✨", "club")
			end)
		end
		return
	end
	local t = ORDER_TEXT[status]
	if t then
		local msg = t[1]
		if status == "wait" and p.wait then
			msg = string.format("%d초 뒤에 다시 주문할 수 있어요", p.wait)
		elseif status == "taken" and p.by then
			msg = string.format("%s님 테이블이에요", p.by)
		elseif status == "other" and p.mine then
			msg = string.format("내 테이블은 %s 이에요", p.mine)
		end
		C.toast(msg, nil, t[2], if status == "nofunds" or status == "error" then "warn" else "club")
	end
end

local BOOKING_TEXT = {
	started = { "✨ 합석 이벤트 시작!", "MD 태양이 새 친구들을 데리고 와요. 입구 쪽을 봐요!" },
	busy = { "지금 다른 테이블에서 합석 이벤트 중이에요", "조금만 기다려 주세요" },
	cooldown = { "합석 이벤트는 잠시 후에 다시 신청할 수 있어요", nil },
	locked = { "보드카 세트 이상 주문한 테이블만 신청할 수 있어요", nil },
	none = { "내 테이블에서만 신청할 수 있어요", nil },
	far = { "테이블 가까이에서 신청해 주세요", nil },
	notyet = { "친구들이 자리에 앉으면 할 수 있어요", nil },
	dancing = { "지금은 춤추는 중! 🕺", nil },
	numberDone = { "번호는 이미 교환했어요 📱", nil },
	running = { "합석 이벤트 진행 중이에요", nil },
}
function Ui.booking(p: any)
	local t = BOOKING_TEXT[p.status or ""]
	if t then
		C.toast(t[1], t[2], "✨", "club")
	end
end

---------------------------------------------------------------------------------------------------
-- 합석 action card (top-right slot)
---------------------------------------------------------------------------------------------------
local cardNames: TextLabel? = nil
function Ui.actions(on: boolean, names: string?, numberDone: boolean?)
	if not K then
		return
	end
	if not on then
		if actionCard then
			actionCard.Visible = false
		end
		return
	end
	if not ensureGui() or not gui then
		return
	end
	if not actionCard or not actionCard.Parent then
		local card = K.Panel(gui, { Name = "HapseokCard", Radius = K.Radius.lg })
		card.BackgroundColor3 = K.Color.glass
		card.BackgroundTransparency = 0.1
		card.Size = UDim2.fromOffset(240, 132)
		card.AnchorPoint = Vector2.new(1, 0)
		card.Position = UDim2.new(1, -8, 0, 70)
		card.ZIndex = 20
		local title = K.text(card, { Name = "Names", Text = "", TextSize = K.Type.caption, Font = K.Font.bold, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
		cardNames = title
		local grid = Instance.new("Frame")
		grid.Name = "Grid"
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(8, 28)
		grid.Size = UDim2.new(1, -16, 1, -34)
		grid.ZIndex = 21
		grid.Parent = card
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.new(0.5, -3, 0, 46)
		gl.CellPadding = UDim2.fromOffset(6, 6)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid
		local aa = S.allAges()
		for i, def in { { "cheers", S.cheersWord(aa), "gold" }, { "dance", "같이 춤 💃", "bridge" }, { "number", "번호 교환 📱", "tonal" }, { "bye", "잘 가요 👋", "secondary" } } do
			local kind = def[1]
			local b = K.Button(grid, {
				name = "Act_" .. kind,
				text = def[2],
				style = def[3],
				order = i,
				textSize = K.Type.caption,
				zIndex = 22,
				onClick = function()
					Ui.request("act", kind)
				end,
			})
			actionButtons[kind] = b
		end
		actionCard = card
		if C.Layout then
			local function place()
				local ok, r = pcall(C.Layout.rect, "topRight")
				if ok and type(r) == "table" and r.w and r.w > 0 then
					local w = math.clamp(r.w, 200, 260)
					card.Size = UDim2.fromOffset(w, 132)
					card.Position = UDim2.fromOffset(r.x + r.w, r.y)
				end
			end
			pcall(function()
				C.Layout.onChanged(place)
			end)
		end
	end
	local card = actionCard :: Frame
	if cardNames then
		cardNames.Text = "✨ 합석 중 · " .. (names or "")
	end
	local nb = actionButtons.number
	if nb then
		K.setButtonEnabled(nb, not numberDone)
	end
	if not card.Visible then
		card.Visible = true
		pcall(K.pop, card)
	end
end

function Ui.init(core: any)
	C = core
	S = core.S
	K = core.K
	if not K then
		warn("[GwangalliClubShow] GwangalliUI missing; club show screens disabled")
	end
end

return Ui
