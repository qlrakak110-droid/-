-- 인맥 (owner: npc_mind): everyone you have talked to on the street, with what you know about them.
--   list    연락처 (numbers you have) then 아는 사람 (met, no number yet): avatar, name (??? until they
--           told you), 관계 단계, 호감 / 신뢰 / 친밀 at a glance, last seen / where they are now
--   detail  호감도 신뢰도 분노도 공포도 친밀도 bars, the tastes you found out (좋아하는 음식 / 선물 /
--           취미, 싫어하는 음식), 📞 전화 · 💬 문자 · 📅 약속 when you have their number
--   chat    one bubble view for both channels:
--             문자  the saved thread (GwangalliMind "text" op: their reply comes after a typing delay)
--             전화  a live call ("call" op, then "say" on the call channel; "close" hangs up)
--           quick chips (인사 / 안부 / 농담 / 칭찬 / 뭐 해? / 사과 / 고백 …), 📅 약속 chips (밥 / 광안리 /
--           포차 / 당구장 / 카페 / 코노 / 볼링 / 바다 / 클럽 -> the "meet" op books it through the
--           relationships promise system) and a free text field.
-- Talks to ReplicatedStorage.GwangalliMind (MindTalk / MindGet / MindEvent) directly; the street-life
-- client caches the same views, this app does not depend on it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(ctx: any)
	local K, AppKit = ctx.K, ctx.AppKit

	local M: any = nil
	pcall(function()
		M = require(ReplicatedStorage:WaitForChild("GwangalliMindShared", 10) :: ModuleScript)
	end)
	local Social: any = nil
	pcall(function()
		Social = require(ReplicatedStorage:WaitForChild("GwangalliSocialShared", 10) :: ModuleScript)
	end)

	local ARCH_GLYPH = {
		police = "👮", student = "🎒", office = "💼", worker = "💼", drunk = "🍺", homeless = "🧥", punk = "😼",
		thug = "🕶️", fool = "🤪", clerk = "🏪", rich = "💎", tourist = "📸", elder = "👵", hothead = "😤", citizen = "🙂",
	}
	local STAT_ROWS = {
		{ key = "aff", label = "호감도", icon = "💗", color = Color3.fromRGB(255, 96, 160) },
		{ key = "tr", label = "신뢰도", icon = "🤝", color = Color3.fromRGB(90, 200, 255) },
		{ key = "an", label = "분노도", icon = "💢", color = Color3.fromRGB(255, 92, 80) },
		{ key = "fe", label = "공포도", icon = "😨", color = Color3.fromRGB(170, 140, 255) },
		{ key = "cl", label = "친밀도", icon = "🫶", color = Color3.fromRGB(255, 190, 70) },
	}
	local QUICK = {
		{ id = "greet", label = "👋 인사" },
		{ id = "how", label = "🙂 잘 지내?" },
		{ id = "doing", label = "❓ 뭐 해?" },
		{ id = "joke", label = "😂 농담" },
		{ id = "compliment", label = "😊 칭찬" },
		{ id = "food_q", label = "🍽️ 뭐 좋아해?" },
		{ id = "hobby_q", label = "🎨 취미" },
		{ id = "comfort", label = "🫂 위로" },
		{ id = "apologize", label = "🙏 사과" },
		{ id = "thank", label = "💐 고마워" },
		{ id = "flirt", label = "😏 작업" },
		{ id = "confess", label = "💘 고백" },
		{ id = "bye", label = "👋 잘 자" },
	}
	local MEET_KINDS = { "meal", "walk", "pocha", "billiards", "cafe", "karaoke", "bowling", "beach", "club" }

	local app = {}
	local visible = false
	local listView: Frame
	local listScroll: ScrollingFrame
	local detailView: Frame
	local detailHeader: any
	local detailScroll: ScrollingFrame
	local chatView: Frame
	local chatHeader: any
	local chatScroll: ScrollingFrame
	local chipBar: ScrollingFrame
	local inputBar: Frame
	local input: TextBox
	local snap: any = nil
	local snapAt = -1e9
	local views: { [string]: any } = {}
	local openId: string? = nil
	local chat: any = nil -- {id, mode = "text" | "call", msgs = {{me, text, sys}}, typing, since, meetMenu}

	local function folder(): Instance?
		return ReplicatedStorage:FindFirstChild((M and M.Folder) or "GwangalliMind")
	end
	local function remote(name: string): any
		local f = folder()
		return f and f:FindFirstChild(name)
	end
	local function invoke(op: string, payload: any): any
		local r = remote((M and M.Remote.Talk) or "MindTalk")
		if not r then
			return { ok = false, err = "offline" }
		end
		local ok, res = pcall(function()
			return r:InvokeServer(op, payload)
		end)
		return if ok and type(res) == "table" then res else { ok = false, err = "error" }
	end

	local function refreshSnap(force: boolean?): any
		if not force and snap and os.clock() - snapAt < 2 then
			return snap
		end
		local r = remote((M and M.Remote.Get) or "MindGet")
		if r then
			local ok, s = pcall(function()
				return r:InvokeServer()
			end)
			if ok and type(s) == "table" then
				snap, snapAt = s, os.clock()
				for id, v in (s.npcs or {}) do
					views[id] = v
				end
				for _, v in (s.contacts or {}) do
					views[v.id] = v
				end
			end
		end
		return snap
	end

	local function nameOf(v: any): string
		return if v and type(v.name) == "string" and v.name ~= "" then v.name else "???"
	end
	local function glyphOf(v: any): string
		if v and type(v.name) == "string" and v.name ~= "" then
			local first = utf8.offset(v.name, 2)
			return string.sub(v.name, 1, (first or (#v.name + 1)) - 1)
		end
		return ARCH_GLYPH[v and v.arch or ""] or "🙂"
	end
	local function stageColor(v: any): Color3
		local s = M and v and M.STAGES[v.stage or ""]
		local c = s and s.color or { 160, 160, 180 }
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local function n0(x: any): number
		return math.floor((tonumber(x) or 0) + 0.5)
	end
	local function ago(t: any): string
		local d = workspace:GetServerTimeNow() - (tonumber(t) or 0)
		if (tonumber(t) or 0) <= 0 then
			return ""
		elseif d < 90 then
			return "방금"
		elseif d < 3600 then
			return string.format("%d분 전", math.floor(d / 60))
		elseif d < 86400 then
			return string.format("%d시간 전", math.floor(d / 3600))
		end
		return string.format("%d일 전", math.floor(d / 86400))
	end

	---------------------------------------------------------------------------------------------------
	-- List
	---------------------------------------------------------------------------------------------------
	local function personRow(parent: Instance, v: any, order: number, last: boolean)
		local row = K.make("TextButton", { Name = "Person_" .. v.id, Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = order }, parent)
		local av = K.avatar(row, 42, glyphOf(v), stageColor(v))
		av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, 10, 0.5, 0)
		local title = nameOf(v) .. (if v.lover then " 💘" else "")
		local nameW = math.min(150, math.ceil(K.textSize(title, K.Type.bodySm, K.Font.bold).X) + 4)
		K.text(row, { Name = "Name", Position = UDim2.fromOffset(62, 11), Size = UDim2.fromOffset(nameW, 18), Text = title, Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(row, { Name = "Role", Position = UDim2.fromOffset(62 + nameW + 6, 12), Size = UDim2.new(1, -(62 + nameW + 6 + 84), 0, 16), Text = tostring(v.label or "") .. (if v.job and v.job ~= "" then " · " .. tostring(v.job) else ""), TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		local where = if v.where and v.where ~= "" then "📍 " .. tostring(v.where) else ago(v.last)
		K.text(row, { Name = "Stats", Position = UDim2.fromOffset(62, 33), Size = UDim2.new(1, -150, 0, 16), Text = string.format("💗%d  🤝%d  🫶%d%s", n0(v.aff), n0(v.tr), n0(v.cl), if (v.an or 0) >= 30 then "  💢" .. n0(v.an) else ""), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(row, { Name = "Where", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 33), Size = UDim2.fromOffset(110, 16), Text = where, TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
		local pill = K.Pill(row, { name = "Stage", text = tostring(v.stageIcon or "") .. " " .. tostring(v.stageLabel or ""), color = stageColor(v), height = 18 })
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.new(1, -12, 0, 10)
		if not last then
			K.frame(row, { Name = "Hairline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 62, 1, 0), Size = UDim2.new(1, -62, 0, 1), BackgroundTransparency = 0.93, BackgroundColor3 = K.Color.line })
		end
		K.pressable(row, { scale = 0.985 })
		row.Activated:Connect(function()
			app.openDetail(v.id)
		end)
		return row
	end

	local function renderList()
		AppKit.clear(listScroll)
		local s = refreshSnap(false)
		if not s then
			K.EmptyState(listScroll, { order = 1, icon = "📡", title = "아직 연결 중이에요", body = "잠시 후 다시 열어 주세요" })
			return
		end
		local contacts, known, seen = {}, {}, {}
		for _, v in (s.contacts or {}) do
			table.insert(contacts, v)
			seen[v.id] = true
		end
		for id, v in (s.npcs or {}) do
			if not seen[id] then
				table.insert(known, v)
			end
		end
		local function rank(a: any, b: any): boolean
			if (a.lover == true) ~= (b.lover == true) then
				return a.lover == true
			end
			local wa, wb = (a.aff or 0) + (a.cl or 0), (b.aff or 0) + (b.cl or 0)
			if wa ~= wb then
				return wa > wb
			end
			return (a.last or 0) > (b.last or 0)
		end
		table.sort(contacts, rank)
		table.sort(known, function(a, b)
			return (a.last or 0) > (b.last or 0)
		end)
		local order = 0
		local function section(title: string, list: { any })
			if #list == 0 then
				return
			end
			order += 1
			K.SectionHeader(listScroll, { title = title, order = order })
			order += 1
			local card = K.Card(listScroll, { Name = "Group", Size = UDim2.new(1, 0, 0, #list * 64), LayoutOrder = order, ClipsDescendants = true })
			K.list(card, false, 0)
			local rows = {}
			for i, v in list do
				table.insert(rows, personRow(card, v, i, i == #list))
			end
			K.stagger(rows)
		end
		if #contacts == 0 and #known == 0 then
			K.EmptyState(listScroll, { order = 1, icon = "💞", title = "아직 아는 사람이 없어요", body = "길에서 사람들에게 말을 걸어 보세요. 친해지면 번호도 받을 수 있어요." })
			return
		end
		section(string.format("연락처 %d", #contacts), contacts)
		section(string.format("아는 사람 %d", #known), known)
		if (s.wanted or 0) > 0 then
			order += 1
			K.Pill(listScroll, { name = "Wanted", text = "🚨 수배 " .. string.rep("★", s.wanted) .. string.rep("☆", 5 - s.wanted), color = K.Color.red or Color3.fromRGB(255, 80, 80), height = 22, order = order })
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Detail
	---------------------------------------------------------------------------------------------------
	local function chipsLine(parent: Instance, title: string, items: { string }?, empty: string, order: number)
		local holder = K.frame(parent, { Name = "Known_" .. order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
		K.list(holder, false, 4)
		K.text(holder, { Name = "Title", Size = UDim2.new(1, 0, 0, 16), Text = title, TextColor3 = K.Color.sub, Font = K.Font.bold, TextSize = K.Type.micro, LayoutOrder = 1 })
		local wrap = K.frame(holder, { Name = "Items", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
		local lay = K.make("UIGridLayout", { CellSize = UDim2.fromOffset(96, 22), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, wrap)
		local _ = lay
		if not items or #items == 0 then
			K.text(holder, { Name = "Empty", Size = UDim2.new(1, 0, 0, 16), Text = empty, TextColor3 = K.Color.faint, TextSize = K.Type.micro, LayoutOrder = 3 })
			return
		end
		for i, it in items do
			K.Pill(wrap, { name = "Item" .. i, text = it, color = K.Color.cyan, height = 22, order = i })
		end
	end

	local function renderDetail()
		local v = openId and views[openId]
		AppKit.clear(detailScroll)
		if not v then
			K.EmptyState(detailScroll, { order = 1, icon = "🤷", title = "정보가 없어요", body = "" })
			return
		end
		detailHeader.title.Text = nameOf(v)
		detailHeader.setSubtitle(tostring(v.stageIcon or "") .. " " .. tostring(v.stageLabel or "") .. (if v.label and v.label ~= "" then " · " .. v.label else ""), stageColor(v))

		local card = K.frame(detailScroll, { Name = "Card", Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
		K.corner(card, K.Radius.lg)
		local sc = stageColor(v)
		K.gradient(card, { sc, sc:Lerp(Color3.fromRGB(40, 36, 100), 0.6), Color3.fromRGB(24, 24, 48) }, 30)
		local av = K.avatar(card, 52, glyphOf(v), Color3.fromRGB(40, 40, 70))
		av.Position = UDim2.fromOffset(14, 14)
		K.text(card, { Name = "Name", Position = UDim2.fromOffset(78, 14), Size = UDim2.new(1, -90, 0, 24), Text = nameOf(v) .. (if v.age then string.format(" (%s)", tostring(v.age)) else ""), Font = K.Font.bold, TextSize = K.Type.title2, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(card, { Name = "Job", Position = UDim2.fromOffset(78, 40), Size = UDim2.new(1, -90, 0, 16), Text = tostring(v.job or ""), TextColor3 = Color3.fromRGB(236, 236, 250), TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
		local status = if v.number then "📱 번호 있음" else "📵 번호 없음"
		if v.where and v.where ~= "" then
			status ..= "  ·  📍 " .. tostring(v.where)
		end
		K.text(card, { Name = "Status", Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -28, 0, 16), Text = status .. "  ·  대화 " .. tostring(v.talks or 0) .. "번", TextColor3 = Color3.fromRGB(236, 236, 250), TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd })

		-- actions
		local acts = K.frame(detailScroll, { Name = "Actions", Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 2 })
		K.list(acts, true, 8, Enum.HorizontalAlignment.Center)
		if v.number then
			local call = K.Button(acts, { name = "Call", text = "📞 전화", style = "success", size = UDim2.new(1 / 3, -6, 0, 44), order = 1 })
			local text = K.Button(acts, { name = "Text", text = "💬 문자", style = "primary", size = UDim2.new(1 / 3, -6, 0, 44), order = 2 })
			local meet = K.Button(acts, { name = "Meet", text = "📅 약속", style = "gold", size = UDim2.new(1 / 3, -6, 0, 44), order = 3 })
			call.Activated:Connect(function()
				app.openChat(v.id, "call")
			end)
			text.Activated:Connect(function()
				app.openChat(v.id, "text")
			end)
			meet.Activated:Connect(function()
				app.openChat(v.id, "text", true)
			end)
		else
			K.text(acts, { Name = "Hint", Size = UDim2.new(1, 0, 1, 0), Text = "더 친해져서 번호를 받으면 전화 · 문자 · 약속을 할 수 있어요", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
		end

		K.SectionHeader(detailScroll, { title = "관계", order = 3 })
		local stats = K.Card(detailScroll, { Name = "Stats", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
		K.list(stats, false, 0)
		K.pad(stats, 0, 0, 4, 4)
		for i, s in STAT_ROWS do
			local val = math.clamp(tonumber(v[s.key]) or 0, 0, 100)
			local row = K.frame(stats, { Name = "Stat_" .. s.key, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = i })
			K.text(row, { Name = "Label", Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -80, 0, 16), Text = s.icon .. " " .. s.label, Font = K.Font.bold, TextSize = K.Type.caption })
			K.text(row, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.fromOffset(44, 16), Text = tostring(n0(val)), Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = s.color, TextXAlignment = Enum.TextXAlignment.Right })
			local bar = K.ProgressBar(row, { color = s.color, height = 6 })
			bar.frame.Position = UDim2.fromOffset(12, 26)
			bar.frame.Size = UDim2.new(1, -24, 0, 6)
			bar.set(val / 100, true)
		end

		K.SectionHeader(detailScroll, { title = "알아낸 취향", order = 5 })
		local tastes = K.Card(detailScroll, { Name = "Tastes", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 })
		K.list(tastes, false, 10)
		K.pad(tastes, 12, 12, 10, 12)
		local kn = type(v.known) == "table" and v.known or {}
		chipsLine(tastes, "🍽️ 좋아하는 음식", kn.foods, "대화하다 보면 알게 될 거예요 (\"뭐 좋아해?\")", 1)
		chipsLine(tastes, "🎁 좋아하는 선물", kn.gifts, "선물을 주면 반응으로 알 수 있어요", 2)
		chipsLine(tastes, "🎨 취미", kn.hobbies, "\"취미가 뭐야?\" 하고 물어보세요", 3)
		if kn.nofood then
			chipsLine(tastes, "🙅 싫어하는 음식", { kn.nofood }, "", 4)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Chat (문자 / 전화)
	---------------------------------------------------------------------------------------------------
	local function addMsg(me: boolean, text: string, sys: boolean?)
		if chat then
			table.insert(chat.msgs, { me = me, text = text, sys = sys })
			while #chat.msgs > 60 do
				table.remove(chat.msgs, 1)
			end
		end
	end

	local function scrollToEnd()
		task.defer(function()
			pcall(function()
				local lay = chatScroll:FindFirstChildOfClass("UIListLayout")
				local h = if lay then lay.AbsoluteContentSize.Y else 0
				chatScroll.CanvasPosition = Vector2.new(0, math.max(0, h - chatScroll.AbsoluteSize.Y))
			end)
		end)
	end

	local function renderBubbles()
		AppKit.clear(chatScroll)
		if not chat then
			return
		end
		local v = views[chat.id]
		local L = ctx.phone.layout()
		local maxW = math.floor(math.min(L.screenW * 0.72, 300))
		local order = 0
		local function row(name: string, h: number?): Frame
			order += 1
			return K.frame(chatScroll, { Name = name, Size = UDim2.new(1, 0, 0, h or 0), AutomaticSize = if h then Enum.AutomaticSize.None else Enum.AutomaticSize.Y, LayoutOrder = order })
		end
		local prevMe: boolean? = nil
		for _, m in chat.msgs do
			if m.sys then
				local r = row("SystemRow")
				local sw = math.min(L.screenW - 40, math.ceil(K.textWidth(m.text, K.Type.micro)) + 28)
				local pill = K.text(r, { Name = "System", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(sw, K.textHeight(m.text, K.Type.micro, sw - 20) + 10), BackgroundTransparency = 0.3, BackgroundColor3 = K.Color.card2, Text = m.text, TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
				K.corner(pill, 10)
				K.pad(pill, 10, 10, 5, 5)
				prevMe = nil
				continue
			end
			if not m.me and prevMe ~= false then
				local head = row("SenderRow", 34)
				K.avatar(head, 30, glyphOf(v), stageColor(v), { Position = UDim2.fromOffset(12, 2) })
				K.text(head, { Name = "Sender", Position = UDim2.fromOffset(50, 18), Size = UDim2.fromOffset(200, 15), Text = nameOf(v), TextColor3 = K.Color.sub, TextSize = K.Type.micro, Font = K.Font.bold })
			end
			prevMe = m.me
			local fs = K.Type.caption + 1
			local bw = math.clamp(math.ceil(K.textWidth(m.text, fs)) + 30, 44, maxW)
			local bh = K.textHeight(m.text, fs, bw - 26) + 16
			local r = row(if m.me then "OutRow" else "InRow")
			local line = K.frame(r, { Name = "Line", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
			K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = if m.me then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left }, line)
			K.pad(line, if m.me then 0 else 50, if m.me then 12 else 0, 0, 0)
			local bubble = K.text(line, { Name = if m.me then "Out" else "In", Size = UDim2.fromOffset(bw, bh), BackgroundTransparency = 0, BackgroundColor3 = if m.me then Color3.new(1, 1, 1) else K.Color.card2, Text = m.text, TextColor3 = if m.me then K.Color.onAccent else K.Color.text, TextSize = fs, Font = K.Font.medium, TextWrapped = true })
			if m.me then
				K.gradient(bubble, if chat.mode == "call" then K.Grad.success else K.Grad.primary, 15)
			end
			K.corner(bubble, 16)
			K.pad(bubble, 12, 12, 8, 8)
		end
		if chat.typing then
			local r = row("TypingRow", 38)
			local dots = K.text(r, { Name = "Typing", Position = UDim2.fromOffset(50, 4), Size = UDim2.fromOffset(54, 30), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2, Text = "• • •", TextColor3 = K.Color.sub, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center })
			K.corner(dots, 15)
		end
		row("End", 8)
		scrollToEnd()
	end

	local function setChatSub()
		if not chat then
			return
		end
		local v = views[chat.id]
		if chat.mode == "call" then
			if chat.ended then
				chatHeader.setSubtitle("통화 종료", K.Color.faint)
			else
				local s = math.max(0, math.floor(os.clock() - (chat.since or os.clock())))
				chatHeader.setSubtitle(string.format("📞 통화 중 %02d:%02d", s // 60, s % 60), K.Color.green or Color3.fromRGB(80, 220, 140))
			end
		else
			chatHeader.setSubtitle(if v then tostring(v.stageIcon or "") .. " " .. tostring(v.stageLabel or "") else "", if v then stageColor(v) else nil)
		end
	end

	local renderChips: () -> ()

	local function applyView(res: any)
		if type(res) == "table" and type(res.view) == "table" and res.view.id then
			views[res.view.id] = res.view
			snapAt = -1e9 -- the list refetches next time
		end
	end

	-- player turn: show it, wait for the reply (typing dots in texts, a short beat on calls)
	local function send(text: string?, intent: string?, meetKind: string?)
		if not chat or chat.busy or chat.ended then
			return
		end
		local id, mode = chat.id, chat.mode
		local v = views[id]
		local close = v ~= nil and (v.stage == "friend" or v.stage == "bestie" or v.stage == "lover" or v.stage == "close")
		local shown = text
		if meetKind then
			local inv = Social and Social.INVITES[meetKind]
			shown = if inv then inv.icon .. " " .. inv.label else meetKind
		elseif not shown and intent and M then
			shown = M.playerLine(intent, close, { you = ctx.player.DisplayName })
		end
		addMsg(true, shown or "…")
		chat.busy = true
		chat.typing = mode == "text"
		chat.meetMenu = false
		renderBubbles()
		renderChips()
		local mine = chat
		task.spawn(function()
			local res
			if meetKind then
				res = invoke("meet", { id = id, kind = meetKind })
			elseif mode == "call" then
				res = invoke("say", { id = id, text = shown, intent = intent, polite = not close })
			else
				res = invoke("text", { id = id, text = shown, intent = intent })
			end
			if chat ~= mine then
				return
			end
			applyView(res)
			local lines: { string } = {}
			if res.ok then
				if type(res.reply) == "string" then
					lines = { res.reply }
				elseif type(res.out) == "table" and type(res.out.lines) == "table" then
					lines = res.out.lines
				end
			end
			local delay = if mode == "text" then math.clamp(tonumber(res.delay) or 1.5, 0.6, 4) else 0.5
			task.wait(delay)
			if chat ~= mine then
				return
			end
			chat.typing = false
			if not res.ok then
				addMsg(false, if res.err == "slow" then "(잠깐… 천천히 말해 주세요)" elseif res.err == "nonumber" then "번호가 없어요" else "(전송 실패)", true)
			end
			for i, l in lines do
				if i > 1 then
					task.wait(if mode == "text" then 0.9 else 0.6)
					if chat ~= mine then
						return
					end
				end
				addMsg(false, l)
				renderBubbles()
			end
			local act = type(res.out) == "table" and res.out.act or nil
			if mode == "call" and (act == "end" or act == "leave" or act == "flee") then
				chat.ended = true
				addMsg(false, "📵 상대방이 전화를 끊었어요", true)
			end
			chat.busy = false
			setChatSub()
			renderBubbles()
			renderChips()
		end)
	end

	local function hangUp()
		if chat and chat.mode == "call" and not chat.ended then
			chat.ended = true
			local id = chat.id
			task.spawn(invoke, "close", { id = id })
			addMsg(false, "📵 통화를 종료했어요", true)
			setChatSub()
			renderBubbles()
			renderChips()
		end
	end

	renderChips = function()
		AppKit.clear(chipBar)
		if not chat then
			return
		end
		local function chip(name: string, label: string, style: string, fn: () -> (), order: number)
			local w = math.clamp(math.ceil(K.textSize(label, K.Type.caption, K.Font.bold).X) + 26, 56, 200)
			local b = K.Button(chipBar, { name = name, text = label, style = style, size = UDim2.fromOffset(w, 34), order = order, textSize = K.Type.caption })
			if chat.busy or chat.ended then
				K.setButtonEnabled(b, false)
			end
			b.Activated:Connect(function()
				if not b:GetAttribute("Disabled") then
					fn()
				end
			end)
		end
		if chat.ended then
			chip("Back", "‹ 돌아가기", "secondary", function()
				app.back()
			end, 1)
			if chat.mode == "call" then
				chip("Redial", "📞 다시 걸기", "success", function()
					app.openChat(chat.id, "call")
				end, 2)
			end
			return
		end
		local order = 0
		if chat.meetMenu then
			order += 1
			chip("MeetBack", "‹ 뒤로", "secondary", function()
				chat.meetMenu = false
				renderChips()
			end, order)
			for _, kind in MEET_KINDS do
				local inv = Social and Social.INVITES[kind]
				if inv then
					order += 1
					chip("Meet_" .. kind, inv.icon .. " " .. string.gsub(inv.label, "가자$", ""), "gold", function()
						send(nil, nil, kind)
					end, order)
				end
			end
			return
		end
		if chat.mode == "call" then
			order += 1
			chip("HangUp", "📵 끊기", "destructive", hangUp, order)
		end
		order += 1
		chip("Meet", "📅 약속", "gold", function()
			chat.meetMenu = true
			renderChips()
		end, order)
		for _, q in QUICK do
			order += 1
			chip("Q_" .. q.id, q.label, "secondary", function()
				send(nil, q.id)
			end, order)
		end
	end

	local function loadThread(id: string)
		local res = invoke("thread", { id = id })
		applyView(res)
		if chat and chat.id == id and chat.mode == "text" then
			chat.msgs = {}
			for _, m in (res.thread or {}) do
				table.insert(chat.msgs, { me = m.f == "me", text = tostring(m.m or "") })
			end
			if #chat.msgs == 0 then
				addMsg(false, "새 대화를 시작해 보세요", true)
			end
			renderBubbles()
		end
	end

	---------------------------------------------------------------------------------------------------
	-- Navigation
	---------------------------------------------------------------------------------------------------
	local page = "list"
	local function showPage(p: string)
		local from = if page == "list" then listView elseif page == "detail" then detailView else chatView
		local to = if p == "list" then listView elseif p == "detail" then detailView else chatView
		if from == to then
			to.Visible = true
			return
		end
		local depth = { list = 1, detail = 2, chat = 3 }
		if depth[p] > depth[page] then
			K.pushPage(to, from)
		else
			K.popPage(from, to)
		end
		page = p
	end

	function app.openDetail(id: string)
		openId = id
		renderDetail()
		showPage("detail")
	end

	function app.openChat(id: string, mode: string, meet: boolean?)
		if chat and chat.mode == "call" and not chat.ended then
			hangUp()
		end
		openId = id
		chat = { id = id, mode = mode, msgs = {}, busy = false, typing = false, since = os.clock(), meetMenu = meet == true }
		local v = views[id]
		chatHeader.title.Text = nameOf(v)
		inputBar.Visible = true
		input.Text = ""
		input.PlaceholderText = if mode == "call" then "통화로 할 말…" else "문자 보내기…"
		setChatSub()
		showPage("chat")
		renderChips()
		if mode == "text" then
			renderBubbles()
			task.spawn(loadThread, id)
			return
		end
		addMsg(false, "📞 " .. nameOf(v) .. "에게 거는 중…", true)
		chat.busy = true
		renderBubbles()
		renderChips()
		local mine = chat
		task.spawn(function()
			task.wait(1.4)
			local res = invoke("call", { id = id })
			if chat ~= mine then
				return
			end
			applyView(res)
			chat.busy = false
			if not res.ok or res.noAnswer then
				chat.ended = true
				addMsg(false, if res.ok then "받지 않아요… 나중에 다시 걸어 보세요" else "연결할 수 없어요", true)
			else
				chat.since = os.clock()
				addMsg(false, "📞 연결됐어요", true)
				for i, l in (res.out and res.out.lines or {}) do
					if i > 1 then
						task.wait(0.6)
					end
					addMsg(false, l)
				end
			end
			setChatSub()
			renderBubbles()
			renderChips()
		end)
	end

	function app.back(): boolean
		if page == "chat" then
			if chat and chat.mode == "call" then
				hangUp()
			end
			chat = nil
			renderDetail()
			showPage("detail")
			return true
		elseif page == "detail" then
			openId = nil
			snapAt = -1e9
			renderList()
			showPage("list")
			return true
		end
		return false
	end

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		listView = K.frame(body, { Name = "List", Size = UDim2.fromScale(1, 1) })
		ctx.phone.header(listView, "인맥")
		listScroll = AppKit.scroll(listView, L.headerH, { name = "People", gap = 8, topPad = 2 })

		detailView = K.frame(body, { Name = "Detail", Size = UDim2.fromScale(1, 1), Visible = false, BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg })
		detailHeader = ctx.phone.header(detailView, "", { subtitle = "", onBack = app.back })
		detailScroll = AppKit.scroll(detailView, L.headerH, { name = "Info", gap = 10, topPad = 2 })

		chatView = K.frame(body, { Name = "Chat", Size = UDim2.fromScale(1, 1), Visible = false, BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg })
		chatHeader = ctx.phone.header(chatView, "", { subtitle = "", onBack = app.back })
		local BAR = 96
		chatScroll = K.make("ScrollingFrame", {
			Name = "Bubbles",
			Position = UDim2.fromOffset(0, L.headerH),
			Size = UDim2.new(1, 0, 1, -(L.headerH + BAR)),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(14, 17, 28),
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = K.Color.sub,
		}, chatView)
		K.list(chatScroll, false, 4)
		K.pad(chatScroll, 0, 0, 6, 6)
		local bottom = K.frame(chatView, { Name = "Composer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, BAR), BackgroundTransparency = 0, BackgroundColor3 = K.Color.bg })
		chipBar = K.make("ScrollingFrame", { Name = "Chips", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0 }, bottom)
		K.list(chipBar, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		K.pad(chipBar, 10, 10, 0, 0)
		inputBar = K.frame(bottom, { Name = "InputBar", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 46) })
		local field = K.frame(inputBar, { Name = "Field", Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -86, 0, 38), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card })
		K.corner(field, UDim.new(0.5, 0))
		input = K.make("TextBox", {
			Name = "Input",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = "",
			PlaceholderText = "문자 보내기…",
			PlaceholderColor3 = K.Color.faint,
			TextColor3 = K.Color.text,
			TextSize = K.Type.caption + 1,
			Font = K.Font.medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, field)
		local sendB = K.Button(inputBar, { name = "Send", text = "보내기", style = "primary", size = UDim2.fromOffset(64, 38), position = UDim2.new(1, -72, 0, 4), textSize = K.Type.caption })
		local function submit()
			local t = string.gsub(input.Text or "", "^%s+", "")
			t = string.gsub(t, "%s+$", "")
			if t == "" or not chat or chat.busy or chat.ended then
				return
			end
			input.Text = ""
			send(string.sub(t, 1, 140), nil)
		end
		sendB.Activated:Connect(submit)
		input.FocusLost:Connect(function(enter: boolean)
			if enter then
				submit()
			end
		end)

		-- NPC texts arrive while the app is open
		task.spawn(function()
			local f = ReplicatedStorage:WaitForChild((M and M.Folder) or "GwangalliMind", 60)
			local ev = f and f:WaitForChild((M and M.Remote.Event) or "MindEvent", 30)
			if not ev then
				return
			end
			(ev :: RemoteEvent).OnClientEvent:Connect(function(msg: any)
				if type(msg) ~= "table" then
					return
				end
				if msg.kind == "text" and type(msg.id) == "string" then
					snapAt = -1e9
					if visible and chat and chat.id == msg.id and chat.mode == "text" and not chat.busy then
						addMsg(false, tostring(msg.msg or ""))
						renderBubbles()
					elseif visible and page == "list" then
						renderList()
					end
				elseif msg.kind == "view" and type(msg.id) == "string" and type(msg.view) == "table" then
					views[msg.id] = msg.view
				end
			end)
		end)

		-- the call timer
		task.spawn(function()
			while true do
				task.wait(1)
				if visible and chat and chat.mode == "call" and not chat.ended and not chat.busy then
					setChatSub()
				end
			end
		end)

		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			for _, s in { listScroll, detailScroll } do
				s.Position = UDim2.fromOffset(0, l.headerH)
				s.Size = UDim2.new(1, 0, 1, -l.headerH)
			end
			chatScroll.Position = UDim2.fromOffset(0, l.headerH)
			chatScroll.Size = UDim2.new(1, 0, 1, -(l.headerH + BAR))
			if visible and chat then
				renderBubbles()
			end
		end)
	end

	-- args {id?, mode? = "text" | "call"}: open straight into someone (from a notification / the street)
	function app.show(args: any)
		visible = true
		if type(args) == "table" and type(args.id) == "string" then
			refreshSnap(true)
			if args.mode == "call" or args.mode == "text" then
				openId = args.id
				renderDetail()
				page = "detail"
				listView.Visible, detailView.Visible = false, true
				app.openChat(args.id, args.mode)
			else
				listView.Visible = false
				openId = args.id
				renderDetail()
				detailView.Visible = true
				page = "detail"
			end
			return
		end
		if page == "list" then
			task.spawn(function()
				refreshSnap(true)
				if visible and page == "list" then
					renderList()
				end
			end)
			renderList()
		elseif page == "detail" then
			renderDetail()
		end
	end

	function app.hide()
		visible = false
		if chat and chat.mode == "call" and not chat.ended then
			hangUp()
		end
	end

	-- test hook (only with workspace.GwangalliStreetLifeDebug): LocalPlayer.GwangalliPeopleAPI
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		local api = Instance.new("BindableFunction")
		api.Name = "GwangalliPeopleAPI"
		local queue: { () -> () } = {}
		local lastDebug = ""
		api.OnInvoke = function(method: string, a: any, b: any, c: any): any
			if method == "state" then
				local lines = {}
				for _, m in (chat and chat.msgs or {}) do
					table.insert(lines, (if m.sys then "# " elseif m.me then "> " else "< ") .. m.text)
				end
				return lastDebug .. string.format("\npage=%s open=%s mode=%s busy=%s ended=%s\n%s", page, tostring(openId), tostring(chat and chat.mode), tostring(chat and chat.busy), tostring(chat and chat.ended), table.concat(lines, "\n"))
			end
			-- remotes must be invoked from the client's own thread: queue it
			table.insert(queue, function()
				if method == "send" then
					send(a, b, c)
				elseif method == "chat" then
					app.openChat(a, b or "text", c)
				elseif method == "detail" then
					refreshSnap(true)
					app.openDetail(a)
				elseif method == "back" then
					app.back()
				elseif method == "befriend" then
					local r = invoke("debug", { id = a, aff = b })
					lastDebug = string.format("befriend %s ok=%s tier=%s number=%s", tostring(a), tostring(r.ok), tostring(r.tier), tostring(r.view and r.view.number))
					snapAt = -1e9
				end
			end)
			return true
		end
		api.Parent = ctx.player
		task.spawn(function()
			while api.Parent do
				task.wait(0.25)
				while #queue > 0 do
					task.spawn(table.remove(queue, 1))
				end
			end
		end)
	end

	return app
end
