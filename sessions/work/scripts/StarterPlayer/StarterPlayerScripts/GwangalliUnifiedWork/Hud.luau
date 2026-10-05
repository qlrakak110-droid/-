--!nocheck
-- GwangalliUnifiedWork/Hud: the on-shift work HUD (server `state` pushes, ~0.6 s).
--   top bar   job · Lv / 직급 · phase chips + progress · time left · 예상 정산 · XP
--   hint      the current goal ("▶ 다음 할 일") — the world marker (Marker.luau) points at its station
--   left      kind card (편의점 계산대 / 배달 주문 / 이벤트 / 시재) · order tickets (items, options,
--             patience timer) · stock bars · close-task checklist
--   right     held item · nearby stations with big action buttons; an action with dur > 0.3 s fills
--             a hold bar for that long before it is sent (cancelled if the action disappears)
--   bottom    퇴근 · 힌트 단계
-- Every section is rebuilt only when its data signature changes. Korean text, ≥ 44 px touch targets.

local U = require(script.Parent:WaitForChild("UI"))
local C = U.C

local Hud = {}
Hud.__index = Hud

local STATE_LABEL = { received = "접수", preparing = "준비 중", ready = "완성 · 호출", delivered = "전달" }
local STATE_COLOR = { received = C.gold, preparing = C.cyan, ready = C.green }
local PERSONA_ICON = { normal = "🙂", hurry = "⏱️", drunk = "🥴", karen = "😤", student = "🎒", regular = "😊" }

function Hud.new(gui: ScreenGui, send: (any) -> ()): any
	local self = setmetatable({}, Hud)
	self.send = send
	self.sigs = {}
	self.pending = nil
	local root = U.frame(gui, { Name = "WorkHud", Size = UDim2.fromScale(1, 1), Visible = false })
	self.root = root
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1280
	self.narrow = vw < 760
	-- top bar (compact: the NPC bubbles at the counter sit right below it)
	local top = U.frame(root, { Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.new(if self.narrow then 0.62 else 0.44, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.bg, BackgroundTransparency = 0.12 })
	U.make("UISizeConstraint", { MaxSize = Vector2.new(560, 300), MinSize = Vector2.new(280, 0) }, top)
	U.corner(top, 12)
	U.stroke(top)
	U.pad(top, 10, 10, 5, 6)
	U.list(top, 3)
	self.title = U.text(top, { Name = "Title", Font = U.BOLD, TextSize = 14, LayoutOrder = 1 })
	self.meta = U.text(top, { Name = "Meta", TextSize = 12, TextColor3 = C.sub, LayoutOrder = 2 })
	self.phaseBar = U.bar(top, 4, { LayoutOrder = 3 })
	self.xpBar = U.bar(top, 2, { LayoutOrder = 4 })
	self.xpBar.set(0, C.violet)
	local hint = U.frame(top, { Name = "Hint", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(40, 32, 6), BackgroundTransparency = 0.1, LayoutOrder = 5 })
	U.corner(hint, 8)
	U.stroke(hint, C.gold, 0.45)
	U.pad(hint, 8, 8, 4, 4)
	self.hint = U.text(hint, { Name = "Text", Font = U.BOLD, TextSize = 14, TextColor3 = Color3.fromRGB(255, 226, 150) })
	self.hintFrame = hint
	-- left column
	-- (x 84: the game's own menu column sits at the left edge; the joystick below y ~ 480)
	local left = U.make("ScrollingFrame", { Name = "Left", Position = UDim2.new(0, 84, 0, 124), Size = UDim2.new(0, if self.narrow then 200 else 250, 1, -300), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, root)
	U.list(left, 6)
	self.left = left
	self.kindBox = U.frame(left, { Name = "Kind", Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	U.list(self.kindBox, 6)
	self.ticketBox = U.frame(left, { Name = "Tickets", Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	U.list(self.ticketBox, 6)
	self.stockBox = U.frame(left, { Name = "Stock", Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
	U.list(self.stockBox, 6)
	-- right column
	-- action panel: bottom centre (the joystick is bottom-left, jump / phone bottom-right)
	local right = U.make("ScrollingFrame", { Name = "Right", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, if self.narrow then 40 else 0, 1, -26), Size = UDim2.new(if self.narrow then 0.42 else 0.34, 0, 0.46, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, root)
	U.make("UISizeConstraint", { MaxSize = Vector2.new(420, 2000), MinSize = Vector2.new(220, 0) }, right)
	local rl = U.list(right, 6)
	rl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	self.right = right
	self.heldBox = U.frame(right, { Name = "Held", Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	U.list(self.heldBox, 6)
	self.nearBox = U.frame(right, { Name = "Near", Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	U.list(self.nearBox, 6)
	local bottom = U.frame(right, { Name = "Bottom", Size = UDim2.new(1, -6, 0, 46), LayoutOrder = 3 })
	U.list(bottom, 6, true)
	self.endBtn = U.button(bottom, "🏁 퇴근", function()
		self:onEnd()
	end, { Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(90, 40, 50) })
	self.hintBtn = U.button(bottom, "💡 힌트", function()
		local lv = ((self.state and self.state.hints) or 1) - 1
		if lv < 0 then
			lv = 2
		end
		self.send({ op = "hints", level = lv })
	end, { Size = UDim2.new(0.5, -3, 1, 0) })
	-- hold progress loop
	task.spawn(function()
		while root.Parent do
			task.wait(0.05)
			self:stepPending()
		end
	end)
	return self
end

function Hud:show(on: boolean)
	self.root.Visible = on
	if not on then
		self.pending = nil
	end
end

-------------------------------------------------------------------------------------------------
-- sections
-------------------------------------------------------------------------------------------------
function Hud:changed(key: string, v: any): boolean
	local s = U.sig(v)
	if self.sigs[key] == s then
		return false
	end
	self.sigs[key] = s
	return true
end

function Hud:renderTop(p: any)
	local lv = p.level or 1
	local phase = if p.state == "commute" then "🚶 출근 중" else ("● " .. (p.phaseLabel or ""))
	self.title.Text = string.format("%s %s · Lv.%d %s   %s", p.icon or "💼", p.title or "근무", lv, p.rank or "", phase)
	if p.state == "commute" then
		self.phaseBar.frame.Visible = false
		self.meta.Text = string.format("%s · 출퇴근 단말기에서 출근 체크 · %s", p.place or "", p.levelTitle or "")
	else
		self.phaseBar.frame.Visible = true
		local total = math.max(1, p.length or 1)
		self.phaseBar.set((p.elapsed or 0) / total, if p.overtime then C.orange else C.cyan)
		local tl = if p.overtime then "⏰ 근무 시간 끝 · 마감 정리" else "⏱ " .. U.clock(p.timeLeft or 0)
		self.meta.Text = string.format("%s · 예상 정산 %s · 완료 %d건%s%s", tl, U.won(p.estimate or 0), p.units or 0, if (p.mistakes or 0) > 0 then string.format(" · 실수 %d", p.mistakes) else "", if p.lastOrders and not p.overtime then " · 라스트 오더" else "")
	end
	self.xpBar.set(p.xpProgress or 0, C.violet)
	self.hintBtn.Text = string.format("💡 힌트 %s", ({ [0] = "끔", [1] = "짧게", [2] = "자세히" })[p.hints or 1] or "")
	self.endBtn.Text = if p.state == "commute" then "✖️ 출근 취소" elseif p.canFinish then "🏁 퇴근 (정산)" else "🏁 퇴근"
end

function Hud:renderHint(p: any)
	local h = p.hint
	if h and h.text then
		self.hintFrame.Visible = true
		self.hint.Text = "▶ " .. h.text
	else
		self.hintFrame.Visible = false
	end
end

local function line(parent: Instance, text: string, props: any?): TextLabel
	local pr = props or {}
	pr.Text = text
	return U.text(parent, pr)
end

local function chip(parent: Instance, text: string, color: Color3, order: number?): TextLabel
	local t = U.text(parent, { Text = text, TextSize = 12, Font = U.BOLD, TextColor3 = Color3.fromRGB(20, 20, 24), BackgroundColor3 = color, BackgroundTransparency = 0, Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = order or 0 })
	U.corner(t, 6)
	U.pad(t, 6, 6, 0, 0)
	return t
end

function Hud:renderKind(p: any)
	local ex = p.extra
	if not self:changed("kind", ex) then
		return
	end
	U.clear(self.kindBox)
	if not ex then
		return
	end
	if ex.kind == "cvs" then
		if ex.event then
			local e = ex.event
			local card = U.card(self.kindBox, { BackgroundColor3 = Color3.fromRGB(70, 24, 28), LayoutOrder = 1 })
			U.list(card, 3)
			line(card, "⚠️ " .. (e.label or "상황 발생"), { Font = U.BOLD, TextSize = 15, TextColor3 = Color3.fromRGB(255, 200, 190) })
			if e.text then
				line(card, e.text, { TextSize = 13 })
			end
			for i, s in e.steps or {} do
				line(card, string.format("%s %d. %s", if s.done then "✅" elseif s.cur then "▶" else "▫️", i, s.label), { TextSize = 13, TextColor3 = if s.done then C.faint elseif s.cur then C.gold else C.text })
			end
		end
		if ex.tx then
			local t = ex.tx
			local card = U.card(self.kindBox, { LayoutOrder = 2 })
			U.list(card, 3)
			line(card, string.format("🧾 %s · %s", t.title or "계산", t.who or "손님"), { Font = U.BOLD, TextSize = 15 })
			for _, it in t.items or {} do
				local mark = if it.removed then "🚫" elseif it.done then "✅" elseif it.warn then "⚠️" else "▫️"
				line(card, string.format("%s %s%s", mark, it.text, if it.price then "  " .. U.won(it.price) else ""), { TextSize = 13, TextColor3 = if it.done or it.removed then C.faint else C.text })
			end
			if t.steps and #t.steps > 0 then
				local parts = {}
				for _, st in t.steps do
					table.insert(parts, if st.cur then "【" .. st.label .. "】" else st.label)
				end
				line(card, table.concat(parts, " → "), { TextSize = 12, TextColor3 = C.gold })
			end
			for _, k in { "id", "pay", "weight", "refund", "rule" } do
				if t[k] then
					line(card, t[k], { TextSize = 13, TextColor3 = C.cyan })
				end
			end
			if t.rates then
				line(card, "요금표 · " .. table.concat(t.rates, " / "), { TextSize = 12, TextColor3 = C.sub })
			end
			line(card, "합계 " .. U.won(t.total or 0), { Font = U.BOLD, TextSize = 16, TextColor3 = C.gold })
		end
		if ex.till then
			local card = U.card(self.kindBox, { LayoutOrder = 3 })
			U.list(card, 3)
			line(card, "💴 금고 시재 세기", { Font = U.BOLD })
			for _, n in ex.till.notes do
				line(card, n, { TextSize = 13 })
			end
			line(card, "장부상 " .. U.won(ex.till.book or 0) .. " · 실제 합계를 고르세요", { TextSize = 12, TextColor3 = C.sub })
		end
		if ex.drunk then
			local card = U.card(self.kindBox, { LayoutOrder = 4, BackgroundColor3 = Color3.fromRGB(60, 40, 10) })
			line(card, "🥴 취객 소동 · 가까이 가서 물 → 출구 안내 (방치하면 진열대가 쓰러져요)", { TextSize = 13 })
		end
	elseif ex.kind == "delivery" then
		local o = ex.order
		local card = U.card(self.kindBox, { LayoutOrder = 1 })
		U.list(card, 3)
		local tags = {}
		table.insert(tags, "🚶 " .. (ex.modeLabel or "도보"))
		if ex.rain then
			table.insert(tags, "🌧️ 우천 할증")
		end
		if not o then
			line(card, "📱 배달 앱 · 콜 " .. tostring(ex.calls or 0) .. "개", { Font = U.BOLD, TextSize = 15 })
			line(card, "오른쪽 아래 📱 배달 앱에서 콜을 잡아요 (거리 · 단가 · 제한 시간)", { TextSize = 13, TextColor3 = C.sub })
			line(card, table.concat(tags, " · "), { TextSize = 12, TextColor3 = C.cyan })
			return
		end
		line(card, string.format("%s %s", if o.kind == "quick" then "📦" else "🛵", o.item or "배달"), { Font = U.BOLD, TextSize = 15 })
		local t2 = {}
		if o.premium then
			table.insert(t2, "💎 프리미엄 (차량)")
		end
		if o.group then
			table.insert(t2, "👥 단체 " .. #o.drops .. "곳")
		end
		if o.soup then
			table.insert(t2, "🍲 국물 주의")
		end
		if o.fragile then
			table.insert(t2, "🍰 파손 주의")
		end
		if #t2 > 0 then
			line(card, table.concat(t2, " · "), { TextSize = 12, TextColor3 = C.gold })
		end
		line(card, string.format("픽업 %s · %s", o.from or "", U.won(o.pay or 0)), { TextSize = 13, TextColor3 = C.sub })
		if not o.picked then
			if o.cooking then
				line(card, string.format("🍳 조리 중 %d초 · 식당으로 이동", o.cooking), { TextSize = 13, TextColor3 = C.orange })
			end
			for i, s in o.pack or {} do
				line(card, string.format("%s %s", if s.done then "✅" else "▫️", s.label), { TextSize = 13, TextColor3 = if s.done then C.faint else C.text })
			end
		else
			for _, d in o.drops or {} do
				line(card, string.format("%s %s%s", if d.done then "✅" elseif d.cur then "▶" else "▫️", d.room, if d.absent then " (부재 · 문 앞)" else ""), { TextSize = 13, TextColor3 = if d.cur then C.gold elseif d.done then C.faint else C.text })
			end
			local left = o.left or 0
			line(card, if left >= 0 then string.format("⏱ %d초 남음", left) else string.format("⏰ %d초 지각 (지급액 감소)", -left), { Font = U.BOLD, TextSize = 16, TextColor3 = if left < 0 then C.red elseif left < 20 then C.orange else C.green })
			line(card, string.format("🍱 음식 상태 %d%%", o.condition or 100), { TextSize = 13 })
			local b = U.bar(card, 6)
			local cond = (o.condition or 100) / 100
			b.set(cond, if cond > 0.8 then C.green elseif cond > 0.5 then C.orange else C.red)
		end
		line(card, table.concat(tags, " · "), { TextSize = 12, TextColor3 = C.cyan })
	end
end

function Hud:renderTickets(p: any)
	local list = {}
	for i, o in p.orders or {} do
		if i > (if self.narrow then 3 else 4) then
			break
		end
		table.insert(list, o)
	end
	-- the timers change every push: rebuild at most once a second for them
	local key = { list = list, focus = p.focus }
	local now = os.clock()
	if not self:changed("tickets", key) and now - (self.ticketAt or 0) < 1 then
		return
	end
	self.sigs.tickets = U.sig(key)
	self.ticketAt = now
	U.clear(self.ticketBox)
	for i, o in list do
		local focused = o.id == p.focus
		local card = U.make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i }, self.ticketBox)
		U.corner(card, 12)
		U.stroke(card, if focused then C.gold else Color3.new(1, 1, 1), if focused then 0.1 else 0.86)
		U.pad(card, 8)
		U.list(card, 2)
		local oid = o.id
		card.Activated:Connect(function()
			self.send({ op = "focus", order = oid })
		end)
		local head = string.format("#%s %s", tostring(o.number or "?"), o.name or ((PERSONA_ICON[o.persona or ""] or "🙂") .. " 손님"))
		line(card, head, { Font = U.BOLD, TextSize = 14 })
		local row = U.frame(card, { Size = UDim2.new(1, 0, 0, 20) })
		U.list(row, 4, true)
		chip(row, if not o.confirmed and o.kind == "cafe" then "POS 대기" else (STATE_LABEL[o.state] or o.state), if not o.confirmed and o.kind == "cafe" then C.orange else (STATE_COLOR[o.state] or C.card2), 1)
		if o.group then
			chip(row, "단체", C.violet, 2)
		end
		if o.strict then
			chip(row, "까다로움", C.red, 3)
		end
		if (o.remakes or 0) > 0 then
			chip(row, "다시 만들기", C.magenta, 4)
		end
		for _, it in o.items or {} do
			line(card, string.format("%s %s", if it.placed then "✅" else "▫️", it.text or "?"), { TextSize = 13, TextColor3 = if it.placed then C.faint else C.text })
			if it.prev then
				line(card, "   (변경 전: " .. it.prev .. ")", { TextSize = 11, TextColor3 = C.faint })
			end
		end
		if o.changeText then
			line(card, "✏️ " .. o.changeText, { TextSize = 12, TextColor3 = C.magenta })
		end
		if o.state ~= "ready" then
			local frac = (o.left or 0) / math.max(1, o.patience or 1)
			local b = U.bar(card, 5)
			b.set(frac, if frac > 0.5 then C.green elseif frac > 0.25 then C.orange else C.red)
			line(card, string.format("손님 인내심 %d초", o.left or 0), { TextSize = 11, TextColor3 = C.sub })
		end
	end
	if p.test and #list > 0 then
		line(self.ticketBox, "🧪 테스트 손님 모드 (NPC 손님 연결 전)", { TextSize = 11, TextColor3 = C.violet, LayoutOrder = 99 })
	end
end

function Hud:renderStock(p: any)
	if not self:changed("stock", { p.stock, p.close }) then
		return
	end
	U.clear(self.stockBox)
	if p.stock and #p.stock > 0 then
		local card = U.card(self.stockBox, { LayoutOrder = 1 })
		U.list(card, 3)
		line(card, "📦 재고", { Font = U.BOLD, TextSize = 13 })
		for _, s in p.stock do
			local row = U.frame(card, { Size = UDim2.new(1, 0, 0, 16) })
			U.text(row, { Text = string.format("%s %d/%d", s.label, s.n or 0, s.max or 0), TextSize = 12, Size = UDim2.new(0.58, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextColor3 = if s.low then C.orange else C.sub, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
			local b = U.bar(row, 6, { Position = UDim2.new(0.6, 0, 0.5, -3), Size = UDim2.new(0.4, 0, 0, 6) })
			local frac = (s.n or 0) / math.max(1, s.max or 1)
			b.set(frac, if s.inverse then (if frac > 0.8 then C.red elseif frac > 0.5 then C.orange else C.green) else (if s.low then C.orange else C.green))
		end
	end
	if p.close and #p.close > 0 then
		local card = U.card(self.stockBox, { LayoutOrder = 2, BackgroundColor3 = Color3.fromRGB(34, 26, 60) })
		U.list(card, 3)
		line(card, "🌙 마감 체크리스트", { Font = U.BOLD, TextSize = 13 })
		for _, c in p.close do
			line(card, string.format("%s %s", if c.done then "✅" else "▫️", c.label), { TextSize = 13, TextColor3 = if c.done then C.faint else C.text })
		end
	end
end

function Hud:renderHeld(p: any)
	if not self:changed("held", p.held) then
		return
	end
	U.clear(self.heldBox)
	for i, h in p.held or {} do
		local card = U.card(self.heldBox, { LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(16, 40, 46) })
		U.list(card, 2)
		line(card, "✋ " .. tostring(h.title or h.label or h.kind or "물건"), { Font = U.BOLD, TextSize = 14 })
		if h.target then
			line(card, "주문: " .. h.target, { TextSize = 12, TextColor3 = C.cyan })
		end
		if h.parts and #h.parts > 0 then
			line(card, "들어간 것: " .. table.concat(h.parts, " ") .. (if h.lid then " 🔒" else ""), { TextSize = 13 })
		end
		for _, pr in h.problems or {} do
			line(card, "⚠️ " .. pr, { TextSize = 12, TextColor3 = C.orange })
		end
		if h.spilled then
			line(card, "💦 쏟았어요 · 버리고 다시", { TextSize = 12, TextColor3 = C.red })
		end
	end
end

function Hud:renderNear(p: any)
	local view = {}
	for _, st in p.near or {} do
		table.insert(view, st)
	end
	if not self:changed("near", { view, p.state }) then
		self:attachPending()
		return
	end
	U.clear(self.nearBox)
	self.buttons = {}
	if #view == 0 then
		local card = U.card(self.nearBox, { LayoutOrder = 1 })
		line(card, if p.state == "commute" then "출퇴근 단말기 가까이 가면 출근 버튼이 나와요" else "안내된 장소로 가까이 가면 작업 버튼이 나와요", { TextSize = 13, TextColor3 = C.sub })
	end
	for si, st in view do
		local card = U.card(self.nearBox, { LayoutOrder = si })
		U.list(card, 5)
		line(card, "📍 " .. (st.label or st.id), { Font = U.BOLD, TextSize = 13, TextColor3 = C.cyan })
		local n = 0
		for _, a in st.actions or {} do
			n += 1
			if n > 8 then
				break
			end
			local enabled = a.enabled ~= false and a.id ~= "none" and a.id ~= "wait"
			local text = string.format("%s %s", a.icon or "", a.label or a.id)
			if not enabled and a.reason then
				text ..= "\n" .. a.reason
			end
			local b = U.button(card, text, nil, { TextSize = if enabled then 15 else 13, BackgroundColor3 = if enabled then (if n == 1 then Color3.fromRGB(26, 92, 110) else C.card2) else Color3.fromRGB(28, 30, 40), TextColor3 = if enabled then C.text else C.faint, AutoButtonColor = enabled, Size = UDim2.new(1, 0, 0, if not enabled and a.reason then 52 else 46) })
			if enabled then
				local stationId, act, dur = st.id, a.id, tonumber(a.dur) or 0
				b.Activated:Connect(function()
					self:press(stationId, act, dur, a.arg)
				end)
				self.buttons[stationId .. "|" .. act] = b
			end
		end
	end
	self:attachPending()
end

-------------------------------------------------------------------------------------------------
-- actions with hold time
-------------------------------------------------------------------------------------------------
function Hud:press(station: string, action: string, dur: number, arg: any?)
	if self.pending then
		return
	end
	if dur <= 0.3 then
		self.send({ op = "act", station = station, action = action, arg = arg })
		return
	end
	self.pending = { station = station, action = action, arg = arg, t0 = os.clock(), dur = dur }
	self:attachPending()
end

function Hud:attachPending()
	local pd = self.pending
	if not pd then
		return
	end
	local b = self.buttons and self.buttons[pd.station .. "|" .. pd.action]
	if not b then
		-- the action is gone (moved away / state changed): cancel
		self.pending = nil
		return
	end
	if pd.fill and pd.fill.Parent == b then
		return
	end
	pd.fill = U.frame(b, { Name = "Hold", BackgroundColor3 = C.gold, BackgroundTransparency = 0.55, Size = UDim2.fromScale(0, 1), ZIndex = (b.ZIndex or 1) + 1 })
	U.corner(pd.fill, 10)
end

function Hud:stepPending()
	local pd = self.pending
	if not pd then
		return
	end
	local t = (os.clock() - pd.t0) / math.max(0.05, pd.dur)
	if pd.fill and pd.fill.Parent then
		pd.fill.Size = UDim2.fromScale(math.clamp(t, 0, 1), 1)
	end
	if t >= 1 then
		self.pending = nil
		if pd.fill then
			pd.fill:Destroy()
		end
		self.send({ op = "act", station = pd.station, action = pd.action, arg = pd.arg })
	end
end

function Hud:onEnd()
	local p = self.state
	if not p then
		return
	end
	if p.state == "commute" then
		self.send({ op = "cancel" })
	elseif self.onEndRequest then
		self.onEndRequest(p)
	end
end

function Hud:update(p: any)
	self.state = p
	self:show(true)
	self:renderTop(p)
	self:renderHint(p)
	self:renderKind(p)
	self:renderTickets(p)
	self:renderStock(p)
	self:renderHeld(p)
	self:renderNear(p)
end

-- a short text summary of what is on screen (debug API)
function Hud:summary(): string
	local out = { self.title.Text, self.meta.Text, if self.hintFrame.Visible then self.hint.Text else "" }
	for k in self.buttons or {} do
		table.insert(out, "btn " .. k)
	end
	return table.concat(out, "\n")
end

return Hud
