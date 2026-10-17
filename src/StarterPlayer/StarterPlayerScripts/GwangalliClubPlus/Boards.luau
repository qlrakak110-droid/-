-- GwangalliClubPlus.Boards: the side LED wall as the "CLUB OCEAN 랭킹전" board (client).
-- Canvas = a local part 0.25 stud in front of MainRoom/ServiceStation/SideLEDFrame (the long screen on
-- the bar-side wall; ClubRanking's own board hangs on the opposite wall), SurfaceGui in PlayerGui.
--   header   CLUB OCEAN 랭킹전 · ● LIVE · night / week labels
--   4 cards  오늘의 큰손 TOP 5 · 후원 랭킹 TOP 5 · 최고가 주문 · 이번 주 랭킹 (folder attribute Boards)
--            rows slide to their new place when ranks change, ▲n / NEW chips, a new #1 gets a gold
--            flash + "NEW 1위" stamp; bars show each row against #1
--   ticker   the night's events (Stage.ticker) crawling along the bottom; during an LED takeover the
--            ticker turns into a live banner ("💸 하늘님 30만원 후원!")

local Boards = {}

local Core: any
local S: any
local L: any
local Led: any

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 194, 71)
local CYAN = Color3.fromRGB(61, 214, 245)
local MAGENTA = Color3.fromRGB(255, 79, 163)
local VIOLET = Color3.fromRGB(139, 108, 255)
local NAVY = Color3.fromRGB(10, 12, 26)

local PPS = 18
local ROWS = 5
local CARDS = {
	{ key = "spend", title = "오늘의 큰손 TOP 5", icon = "👑", color = GOLD },
	{ key = "donate", title = "후원 랭킹 TOP 5", icon = "💸", color = MAGENTA },
	{ key = "best", title = "최고가 주문", icon = "💎", color = CYAN },
	{ key = "weekly", title = "이번 주 랭킹", icon = "📅", color = VIOLET },
}

local board: any = nil
local lastRows: { [string]: { [number]: number } } = {} -- card -> uid -> rank (previous render)
local tickerX = 0
local tickerText = ""
local bannerUntil = 0

local function sideFrame(): (CFrame?, Vector3?)
	local f = Core.mainPart("SideLEDFrame")
	local cf: CFrame, size: Vector3
	if f then
		cf, size = f.CFrame, f.Size
	else
		local fb = S.Config.Fallback.SideLED
		cf = CFrame.lookAt(fb.pos, fb.pos + Vector3.new(-0.015, 0, -0.9999)) * CFrame.Angles(0, math.pi / 2, 0)
		size = fb.size
	end
	-- the thinnest axis is the screen normal; it faces the main room's centre
	local axes = {
		{ v = cf.RightVector, s = size.X },
		{ v = cf.UpVector, s = size.Y },
		{ v = cf.LookVector, s = size.Z },
	}
	table.sort(axes, function(a, b)
		return a.s < b.s
	end)
	local n = axes[1].v
	local room = Core.roomBox().Position
	if (room - cf.Position):Dot(n) < 0 then
		n = -n
	end
	n = Vector3.new(n.X, 0, n.Z)
	if n.Magnitude < 0.5 then
		return nil, nil
	end
	n = n.Unit
	-- width = the longer of the two other axes, height = the vertical extent
	local w, h = 0, 0
	for i = 2, 3 do
		local a = axes[i]
		if math.abs(a.v.Y) > 0.7 then
			h = a.s
		else
			w = math.max(w, a.s)
		end
	end
	if h == 0 then
		h = axes[2].s
		w = axes[3].s
	end
	local at = cf.Position + n * (axes[1].s * 0.5 + 0.25)
	return CFrame.lookAt(at, at + n), Vector3.new(w, h, 0.05)
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
local function buildCard(parent: Instance, i: number, def: any): any
	local x = 0.012 + (i - 1) * 0.247
	local card = Core.frame(parent, {
		Name = def.key,
		Position = UDim2.fromScale(x, 0.15),
		Size = UDim2.fromScale(0.235, 0.7),
		BackgroundColor3 = Color3.fromRGB(16, 18, 36),
		BackgroundTransparency = 0.08,
		ClipsDescendants = true,
		corner = 10,
		strokeColor = def.color,
		strokeT = 0.35,
	})
	local head = Core.frame(card, { Size = UDim2.fromScale(1, 0.17), BackgroundColor3 = def.color, BackgroundTransparency = 0.15, ZIndex = 2, gradient = Core.seq(def.color, def.color:Lerp(NAVY, 0.55)) })
	Core.text(head, { Position = UDim2.fromScale(0.04, 0.12), Size = UDim2.fromScale(0.92, 0.76), Text = def.icon .. " " .. def.title, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left, stroke = Color3.fromRGB(10, 6, 20) })
	local empty = Core.text(card, { Position = UDim2.fromScale(0.08, 0.45), Size = UDim2.fromScale(0.84, 0.14), Text = L.Board.empty, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(150, 160, 190), ZIndex = 2 })
	local rows = {}
	for r = 1, ROWS do
		local row = Core.frame(card, {
			Name = "Row" .. r,
			Position = UDim2.fromScale(0.03, 0.2 + (r - 1) * 0.158),
			Size = UDim2.fromScale(0.94, 0.145),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.93,
			Visible = false,
			ZIndex = 2,
			corner = 6,
		})
		local bar = Core.frame(row, { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = def.color, BackgroundTransparency = 0.78, ZIndex = 2, corner = 6 })
		local badge = Core.frame(row, { Position = UDim2.fromScale(0.015, 0.1), Size = UDim2.fromScale(0.13, 0.8), BackgroundColor3 = if r == 1 then GOLD else Color3.fromRGB(70, 78, 110), ZIndex = 3, corner = 5 })
		local badgeText = Core.text(badge, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = if r == 1 then "👑" else tostring(r), ZIndex = 4, TextColor3 = if r == 1 then Color3.fromRGB(40, 25, 0) else WHITE })
		local name = Core.text(row, { Position = UDim2.fromScale(0.17, 0.08), Size = UDim2.fromScale(0.5, 0.84), Text = "", Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		local value = Core.text(row, { Position = UDim2.fromScale(0.62, 0.12), Size = UDim2.fromScale(0.36, 0.76), Text = "", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if r == 1 then GOLD else WHITE, ZIndex = 3 })
		local chip = Core.frame(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.99, 0.5), Size = UDim2.fromScale(0.2, 0.62), BackgroundColor3 = Color3.fromRGB(61, 220, 132), Visible = false, ZIndex = 5, corner = 5 })
		local chipText = Core.text(chip, { Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), Text = "", TextColor3 = Color3.fromRGB(8, 30, 14), ZIndex = 6 })
		table.insert(rows, { f = row, bar = bar, badge = badge, badgeText = badgeText, name = name, value = value, chip = chip, chipText = chipText, slotY = 0.2 + (r - 1) * 0.158 })
	end
	local stamp = Core.text(card, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.24), Text = L.Rank.newKing, TextColor3 = GOLD, Rotation = -8, TextTransparency = 1, ZIndex = 9, stroke = Color3.fromRGB(60, 30, 0) })
	local flash = Core.frame(card, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD, BackgroundTransparency = 1, ZIndex = 8 })
	return { card = card, rows = rows, empty = empty, stamp = stamp, flash = flash, def = def, king = 0 }
end

local function build(): any?
	local cf, size = sideFrame()
	if not cf or not size then
		return nil
	end
	local part = Core.part("PlusSideLED", size, cf)
	part.Transparency = 1
	local gui = Core.surface("GwClubPlusBoards", part, Enum.NormalId.Front, PPS, { Brightness = 2.2, MaxDistance = 200 })
	local root = Core.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.02, gradient = Core.seq(Color3.fromRGB(8, 10, 28), Color3.fromRGB(26, 12, 48), Color3.fromRGB(8, 10, 28)) })
	local glow = Core.frame(root, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 })
	-- header
	local header = Core.frame(root, { Size = UDim2.fromScale(1, 0.135), BackgroundTransparency = 1, ZIndex = 2 })
	Core.text(header, { Position = UDim2.fromScale(0.012, 0.1), Size = UDim2.fromScale(0.42, 0.8), Text = "🏆 " .. L.Board.title, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, stroke = Color3.fromRGB(60, 20, 90) })
	local live = Core.frame(header, { Position = UDim2.fromScale(0.44, 0.2), Size = UDim2.fromScale(0.07, 0.6), BackgroundColor3 = Color3.fromRGB(255, 50, 80), ZIndex = 3, corner = UDim.new(0.5, 0) })
	Core.text(live, { Size = UDim2.fromScale(0.86, 0.76), Position = UDim2.fromScale(0.07, 0.12), Text = "● " .. L.Board.live, ZIndex = 4 })
	local dates = Core.text(header, { Position = UDim2.fromScale(0.55, 0.2), Size = UDim2.fromScale(0.435, 0.6), Text = "", Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(190, 200, 230), ZIndex = 3 })
	local cards = {}
	for i, def in CARDS do
		table.insert(cards, buildCard(root, i, def))
	end
	-- ticker band
	local band = Core.frame(root, { Position = UDim2.fromScale(0, 0.875), Size = UDim2.fromScale(1, 0.125), BackgroundColor3 = WHITE, BackgroundTransparency = 0.05, ClipsDescendants = true, ZIndex = 2, gradient = Core.seq(Color3.fromRGB(30, 10, 60), Color3.fromRGB(70, 20, 110), Color3.fromRGB(30, 10, 60)) })
	local ticker = Core.text(band, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0, 3000, 0.72, 0), TextScaled = false, TextSize = 22, Text = "", Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local banner = Core.frame(band, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 5, gradient = Core.seq(MAGENTA, VIOLET, CYAN) })
	local bannerText = Core.text(banner, { Size = UDim2.fromScale(0.96, 0.76), Position = UDim2.fromScale(0.02, 0.12), Text = "", TextTransparency = 1, ZIndex = 6, stroke = Color3.fromRGB(30, 10, 40) })
	return { part = part, gui = gui, root = root, glow = glow, live = live, dates = dates, cards = cards, band = band, ticker = ticker, banner = banner, bannerText = bannerText }
end

local function ensure(): any?
	if board and board.part.Parent and board.gui.Parent then
		return board
	end
	if board then
		pcall(function()
			board.part:Destroy()
			board.gui:Destroy()
		end)
		board = nil
	end
	board = build()
	if board then
		Boards.render(Core.state.Boards)
		Boards.renderTicker(Core.state.Stage)
	end
	return board
end

-------------------------------------------------------------------------------------------------
-- render
-------------------------------------------------------------------------------------------------
local function valueText(key: string, e: any): string
	return S.wonShort(tonumber(e.v) or 0)
end

local function renderCard(c: any, list: any)
	local key = c.def.key
	local prev = lastRows[key] or {}
	local now: { [number]: number } = {}
	list = if type(list) == "table" then list else {}
	c.empty.Visible = #list == 0
	local top = (list[1] and tonumber(list[1].v)) or 1
	local newKing = false
	for r = 1, ROWS do
		local row = c.rows[r]
		local e = list[r]
		if type(e) == "table" and type(e.u) == "number" then
			row.f.Visible = true
			local nm = tostring(e.n or "손님")
			if key == "best" and type(e.x) == "string" and e.x ~= "" then
				nm = nm .. " · " .. e.x
			end
			row.name.Text = nm
			row.value.Text = valueText(key, e)
			Core.tween(row.bar, 0.6, { Size = UDim2.fromScale(math.clamp((tonumber(e.v) or 0) / math.max(1, top), 0.06, 1), 1) })
			local uid = e.u
			-- (최고가 주문 rows are single orders: one player can hold two rows)
			local was = if key == "best" then nil else prev[uid]
			now[uid] = r
			row.chip.Visible = false
			if key ~= "best" and next(prev) ~= nil then
				if was == nil then
					row.chip.Visible = true
					row.chipText.Text = L.Rank.new
					row.chip.BackgroundColor3 = CYAN
				elseif was > r then
					row.chip.Visible = true
					row.chipText.Text = string.format(L.Rank.up, was - r)
					row.chip.BackgroundColor3 = Color3.fromRGB(61, 220, 132)
				end
				if was ~= r then
					-- slide in from the old slot (or from the right for a new entry)
					local fromY = if was then c.rows[math.min(was, ROWS)].slotY else row.slotY
					row.f.Position = UDim2.fromScale(if was then 0.03 else 1.05, fromY)
					Core.tween(row.f, 0.7, { Position = UDim2.fromScale(0.03, row.slotY) }, Enum.EasingStyle.Back)
				end
				if row.chip.Visible then
					local chip = row.chip
					task.delay(6, function()
						chip.Visible = false
					end)
				end
			end
			if r == 1 and c.king ~= uid then
				newKing = c.king ~= 0
				c.king = uid
			end
		else
			row.f.Visible = false
		end
	end
	if #list == 0 then
		c.king = 0
	end
	lastRows[key] = now
	if newKing then
		c.flash.BackgroundTransparency = 0.25
		Core.tween(c.flash, 0.9, { BackgroundTransparency = 1 })
		c.stamp.TextTransparency = 0
		c.stamp.Size = UDim2.fromScale(1.3, 0.34)
		Core.tween(c.stamp, 0.35, { Size = UDim2.fromScale(0.8, 0.24) }, Enum.EasingStyle.Back)
		task.delay(3.5, function()
			Core.tween(c.stamp, 0.5, { TextTransparency = 1 })
		end)
	end
end

function Boards.render(b: any)
	local bd = board
	if not bd or type(b) ~= "table" then
		return
	end
	bd.dates.Text = string.format("%s 밤 · 이번 주 %s", tostring(b.nl or ""), tostring(b.wl or ""))
	for _, c in bd.cards do
		renderCard(c, b[c.def.key])
	end
end

function Boards.renderTicker(st: any)
	local list = if type(st) == "table" and type(st.ticker) == "table" then st.ticker else {}
	local parts = {}
	for i = #list, 1, -1 do
		local e = list[i]
		if type(e) == "table" and type(e.t) == "string" then
			table.insert(parts, e.t)
		end
		if #parts >= 8 then
			break
		end
	end
	local text = if #parts > 0 then table.concat(parts, "     ✦     ") else L.Board.tickerIdle
	if text ~= tickerText then
		tickerText = text
		if board then
			board.ticker.Text = text
		end
	end
end

-- a live banner across the ticker while an LED takeover runs
local function onActivate(it: any, late: number)
	local bd = board
	if not bd or late > 2 then
		return
	end
	local d = it.data or {}
	local text: string? = nil
	if it.kind == "donate" then
		text = string.format("💸 %s님 %s 후원!%s", tostring(d.n or "손님"), S.wonShort(tonumber(d.w) or 0), if type(d.m) == "string" and d.m ~= "" then "  “" .. d.m .. "”" else "")
	elseif it.kind == "order" then
		text = string.format("%s %s 테이블 %s님 · %s · %s", tostring(d.icon or "✨"), tostring(d.table or "?"), tostring(d.n or "손님"), tostring(d.label or ""), S.wonShort(tonumber(d.price) or 0))
	elseif it.kind == "booking" then
		text = string.format(L.LED.booking, tostring(d.table or "?"))
	elseif it.kind == "djon" then
		text = string.format("🎧 " .. L.LED.onAir, tostring(d.n or ""))
	end
	if not text then
		return
	end
	bd.bannerText.Text = text
	bd.banner.BackgroundTransparency = 0.05
	bd.bannerText.TextTransparency = 0
	bannerUntil = os.clock() + math.min(it.dur or 6, 10)
	local glowCol = S.tier(it.tier or 1).color
	bd.glow.BackgroundColor3 = glowCol
	bd.glow.BackgroundTransparency = 0.7
	Core.tween(bd.glow, 1.4, { BackgroundTransparency = 1 })
end

function Boards.init(core: any, led: any)
	Core = core
	S = core.S
	L = core.L
	Led = led
	Core.on("Boards", function(b: any)
		if board then
			Boards.render(b)
		end
	end)
	Core.on("Stage", function(st: any)
		Boards.renderTicker(st)
	end)
	Led.onActivate(function(it: any, late: number)
		pcall(onActivate, it, late)
	end)
	local liveT = 0
	Core.job("boards", 30, function(dt: number)
		local here = Core.inside
		if not here then
			if board then
				board.gui.Enabled = false
			end
			return true
		end
		local bd = ensure()
		if not bd then
			return true
		end
		bd.gui.Enabled = true
		-- ticker crawl (px per second on the 18 PPS canvas)
		local w = bd.band.AbsoluteSize.X
		if w > 0 then
			local textW = bd.ticker.TextBounds.X
			tickerX -= dt * 90
			if tickerX < -textW - 40 then
				tickerX = w
			end
			bd.ticker.Position = UDim2.new(0, tickerX, 0.5, 0)
		end
		if bannerUntil > 0 and os.clock() > bannerUntil then
			bannerUntil = 0
			Core.tween(bd.banner, 0.4, { BackgroundTransparency = 1 })
			Core.tween(bd.bannerText, 0.4, { TextTransparency = 1 })
		end
		liveT += dt
		bd.live.BackgroundTransparency = 0.1 + 0.35 * (0.5 + 0.5 * math.sin(liveT * 4))
		return true
	end)
end

return Boards
