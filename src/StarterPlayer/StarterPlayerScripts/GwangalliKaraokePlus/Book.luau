-- GwangalliKaraokePlus/Book (client): the 노래책 (song book).
-- Tabs 인기차트 · 신곡 · 장르 · 애창곡 · 최근 · 수첩, search by 제목 / 가수 / 초성 / 번호 (예: ㄱㅇㄷㄱ, 38262),
-- rows "38262 | 민락동 치킨송 / 바삭즈 · 댄스 · 1:08 · ★★☆ · 혼성 | [예약] [♥]", a detail panel with lyric
-- preview, 내 최고 점수, [우선예약] [듀엣 예약]. Opened from the lobby catalog stand it is read-only.

local Players = game:GetService("Players")

local Book = {}

local K: any
local S: any
local Kit: any
local Rooms: any
local player = Players.LocalPlayer

local sheet: any
local search: TextBox
local tabsRow: Frame
local genreRow: Frame
local list: Frame
local tab = "chart"
local genre = "발라드"
local readOnly = false
local expanded: string? = nil
local tabBtns: { [string]: TextButton } = {}

local TABS = {
	{ id = "chart", label = "🔥 인기차트" },
	{ id = "new", label = "✨ 신곡" },
	{ id = "genre", label = "🎼 장르" },
	{ id = "fav", label = "♥ 애창곡" },
	{ id = "recent", label = "🕘 최근" },
	{ id = "stats", label = "📒 수첩" },
}

local function room(): any?
	local v = Rooms.current()
	if v and Rooms.allowedMe(v) then
		return v
	end
	return nil
end

function Book.setFav(id: string, on: boolean)
	K.Net.call("fav", { song = id, on = on }, function(res)
		if res.ok and type(res.fav) == "table" and K.me then
			K.me.fav = res.fav
			if sheet and sheet.isOpen then
				Book.render()
			end
		end
	end)
	if K.me and K.me.fav then
		local i = table.find(K.me.fav, id)
		if on and not i then
			table.insert(K.me.fav, 1, id)
		elseif not on and i then
			table.remove(K.me.fav, i)
		end
	end
	Kit.toast(if on then "♥ 애창곡에 담았어요" else "애창곡에서 뺐어요", nil, "info")
end

local function reserve(song: any, first: boolean, duet: boolean)
	local v = room()
	if not v then
		Kit.toast("방 안에서 예약할 수 있어요", "문 옆 패널에서 방을 먼저 잡아 주세요", "info")
		return
	end
	K.Net.call("reserve", { room = v.no, song = song.id, first = first, duet = duet }, function(res)
		if res.ok then
			Kit.sound("ping")
			local pos = res.pos or 1
			local body
			if not v.unlimited and (res.credits or 0) <= 0 then
				body = "남은 곡이 없어요 · 동전을 넣으면 바로 시작해요 🪙"
			elseif not res.playing and pos == 1 then
				body = "곧 시작해요! 마이크를 잡아 주세요 🎤"
			else
				body = string.format("%d번째로 예약했어요", pos)
			end
			Kit.toast(string.format("%s %d %s", if first then "⏫ 우선예약" else "✅ 예약", song.no, song.title), body, "success")
		end
	end)
end

local function durOf(song: any): string
	local c = S.Chart.get(song, S.Songs)
	return if c then S.mmss(c.duration) else ""
end

local function starsOf(song: any): string
	local c = S.Chart.get(song, S.Songs)
	local n = if c then c.stars else 1
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

local function isFav(id: string): boolean
	return K.me ~= nil and K.me.fav ~= nil and table.find(K.me.fav, id) ~= nil
end

local function row(song: any, order: number, rank: number?)
	local open = expanded == song.id
	local f = Kit.new("Frame", { Name = song.id, BackgroundColor3 = if open then Kit.C.card2 else Kit.C.card, BackgroundTransparency = 0.05, Size = UDim2.new(1, 0, 0, if open then 186 else 64), LayoutOrder = order, ZIndex = 22 }, list)
	Kit.corner(f, 14)
	local hit = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, -150, 0, 64), ZIndex = 23, Selectable = true }, f)
	hit.Activated:Connect(function()
		expanded = if expanded == song.id then nil else song.id
		Kit.sound("tap")
		Book.render()
	end)
	Kit.text(f, { Text = (if rank then string.format("%d위", rank) else "") , Font = Kit.F.black, TextSize = 12, TextColor3 = Kit.C.magenta, Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(60, 16), ZIndex = 23 })
	Kit.text(f, { Text = tostring(song.no), Font = Kit.F.black, TextSize = 17, TextColor3 = Kit.C.gold, Position = UDim2.fromOffset(12, if rank then 24 else 20), Size = UDim2.fromOffset(64, 24), ZIndex = 23 })
	Kit.text(f, { Text = song.title, Font = Kit.F.bold, TextSize = 16, Position = UDim2.fromOffset(80, 10), Size = UDim2.new(1, -236, 0, 24), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd })
	local subTxt = string.format("%s · %s · %s · %s · %s", song.artist, song.style, durOf(song), starsOf(song), S.Songs.partLabel(song))
	Kit.text(f, { Text = subTxt, Font = Kit.F.medium, TextSize = 12, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(80, 34), Size = UDim2.new(1, -236, 0, 20), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd })
	local favB = Kit.btn(f, { text = if isFav(song.id) then "♥" else "♡", style = "ghost", size = UDim2.fromOffset(44, 44), pos = UDim2.new(1, -10, 0, 10), anchor = Vector2.new(1, 0), textSize = 18, radius = 22, z = 23, onClick = function()
		Book.setFav(song.id, not isFav(song.id))
	end })
	favB.TextColor3 = Kit.C.magenta
	if not readOnly then
		Kit.btn(f, { text = "예약", style = "primary", size = UDim2.fromOffset(80, 44), pos = UDim2.new(1, -60, 0, 10), anchor = Vector2.new(1, 0), textSize = 15, z = 23, onClick = function()
			reserve(song, false, false)
		end })
	end
	if open then
		local preview = {}
		for i = 1, math.min(2, #song.lines) do
			table.insert(preview, song.lines[i].t)
		end
		local best = K.me and K.me.best and K.me.best[song.id]
		Kit.text(f, { Text = "♪ " .. table.concat(preview, " / "), Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.text, TextWrapped = true, Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -32, 0, 38), ZIndex = 23, TextYAlignment = Enum.TextYAlignment.Top })
		local info = { string.format("BPM %d", song.bpm), "KEY " .. song.key, song.credit }
		if song.origin then
			table.insert(info, song.origin)
		end
		if best then
			table.insert(info, string.format("내 최고 %d점", best))
		end
		Kit.text(f, { Text = table.concat(info, " · "), Font = Kit.F.medium, TextSize = 12, TextColor3 = Kit.C.faint, TextWrapped = true, Position = UDim2.fromOffset(16, 104), Size = UDim2.new(1, -32, 0, 30), ZIndex = 23, TextYAlignment = Enum.TextYAlignment.Top })
		if not readOnly then
			Kit.btn(f, { text = "⏫ 우선예약", style = "gold", size = UDim2.new(0.5, -22, 0, 40), pos = UDim2.new(0, 16, 1, -48), textSize = 14, z = 23, onClick = function()
				reserve(song, true, false)
			end })
			Kit.btn(f, { text = "👫 듀엣 예약", style = "magenta", size = UDim2.new(0.5, -22, 0, 40), pos = UDim2.new(0.5, 6, 1, -48), textSize = 14, z = 23, onClick = function()
				reserve(song, false, true)
			end })
		end
	end
end

local function note(text: string, order: number)
	Kit.text(list, { Text = text, Font = Kit.F.medium, TextSize = 14, TextColor3 = Kit.C.sub, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, ZIndex = 22, TextXAlignment = Enum.TextXAlignment.Center })
end

local function chartIds(): { string }
	local f = K.stateFolder :: Instance
	local ids = S.decode(f:GetAttribute("Chart"))
	if type(ids) ~= "table" or #ids == 0 then
		ids = S.Songs.SEED_CHART
	end
	return ids
end

local function renderStats()
	local me = K.me or {}
	local st = me.stats or {}
	local bestSong, bestScore = nil, -1
	for id, sc in me.best or {} do
		if sc > bestScore and S.Songs.byId[id] then
			bestSong, bestScore = S.Songs.byId[id], sc
		end
	end
	local favs = {}
	for i = 1, math.min(3, #(me.fav or {})) do
		local s = S.Songs.byId[me.fav[i]]
		if s then
			table.insert(favs, s.title)
		end
	end
	local rows = {
		{ "🎤 총 부른 곡", string.format("%d곡", st.songs or 0) },
		{ "💯 100점", string.format("%d번", st.hundred or 0) },
		{ "🏆 최고 점수", if bestSong then string.format("%d점 · %s", bestScore, bestSong.title) else "-" },
		{ "👫 듀엣", string.format("%d번", st.duets or 0) },
		{ "🪇 탬버린", string.format("%d번", st.tamb or 0) },
		{ "♥ 애창곡 TOP 3", if #favs > 0 then table.concat(favs, " · ") else "노래책에서 ♡ 를 눌러 담아요" },
	}
	for i, r in rows do
		local f = Kit.new("Frame", { BackgroundColor3 = Kit.C.card, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, ZIndex = 22 }, list)
		Kit.corner(f, 14)
		Kit.text(f, { Text = r[1], Font = Kit.F.bold, TextSize = 15, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.42, 0, 1, 0), ZIndex = 23 })
		Kit.text(f, { Text = r[2], Font = Kit.F.bold, TextSize = 15, TextColor3 = Kit.C.gold, Position = UDim2.new(0.42, 0, 0, 0), Size = UDim2.new(0.58, -16, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd })
	end
end

function Book.render()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for id, b in tabBtns do
		Kit.restyle(b, if id == tab and search.Text == "" then "primary" else "ghost")
	end
	genreRow.Visible = tab == "genre" and search.Text == ""
	local v = room()
	if readOnly then
		sheet.sub.Text = "방을 잡으면 바로 예약할 수 있어요 · 1곡 500원 · 4곡 1,000원"
	elseif v then
		sheet.sub.Text = string.format("ROOM %s · 남은 곡 %s · 예약 %d/%d", v.name, if v.unlimited then "∞" else tostring(v.credits), #(v.queue or {}), S.Config.QueueMax)
	else
		sheet.sub.Text = "방 안에서 예약할 수 있어요"
	end
	local q = search.Text
	local songs: { any } = {}
	local ranks = false
	if q ~= "" then
		songs = S.Search.find(S.Songs, q, 60)
		if #songs == 0 then
			note(string.format("'%s' 검색 결과가 없어요 · 초성(ㄱㅇㄷㄱ)이나 번호로도 찾아보세요", q), 1)
			return
		end
	elseif tab == "chart" then
		for _, id in chartIds() do
			local s = S.Songs.byId[id]
			if s then
				table.insert(songs, s)
			end
		end
		ranks = true
	elseif tab == "new" then
		for i = #S.Songs.LIST, 1, -1 do
			local s = S.Songs.LIST[i]
			if s.tagSet.new or s.tagSet.event then
				table.insert(songs, s)
			end
		end
	elseif tab == "genre" then
		for _, s in S.Songs.LIST do
			if (genre == "듀엣" and s.tagSet.duet) or s.genre == genre then
				table.insert(songs, s)
			end
		end
	elseif tab == "fav" then
		for _, id in (K.me and K.me.fav) or {} do
			local s = S.Songs.byId[id]
			if s then
				table.insert(songs, s)
			end
		end
		if #songs == 0 then
			note("아직 애창곡이 없어요 · 노래 옆 ♡ 를 눌러 담아 보세요", 1)
			return
		end
	elseif tab == "recent" then
		local seen = {}
		for _, e in (K.me and K.me.recent) or {} do
			local s = S.Songs.byId[e.s]
			if s and not seen[s.id] then
				seen[s.id] = true
				table.insert(songs, s)
			end
		end
		if #songs == 0 then
			note("최근 부른 곡이 없어요 · 첫 곡을 불러 볼까요? 🎤", 1)
			return
		end
	elseif tab == "stats" then
		renderStats()
		return
	end
	for i, s in songs do
		row(s, i, if ranks then i else nil)
	end
end

function Book.open(opts: { [string]: any }?)
	readOnly = opts ~= nil and opts.readOnly == true
	sheet.title.Text = string.format("📖 노래책 · 총 %d곡", S.Songs.COUNT)
	Book.render()
	sheet.open()
end

function Book.toggle()
	if sheet.isOpen then
		sheet.close()
	else
		Book.open()
	end
end

function Book.init(k: any)
	K = k
	S, Kit, Rooms = k.S, k.Kit, k.Rooms
	sheet = Kit.sheet("GwKP_Book", { title = "📖 노래책", w = 600, h = 680, accent = Kit.C.cyan })
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, ZIndex = 22 }, sheet.body)
	Kit.list(top, "v", 8)
	local sbox = Kit.new("Frame", { BackgroundColor3 = Kit.C.card, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 1, ZIndex = 22 }, top)
	Kit.corner(sbox, 14)
	Kit.stroke(sbox, Kit.C.cyan, 1, 0.6)
	Kit.text(sbox, { Text = "🔍", TextSize = 18, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(28, 46), ZIndex = 23 })
	search = Kit.new("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Font = Kit.F.bold,
		TextSize = 16,
		TextColor3 = Kit.C.text,
		PlaceholderText = "제목 · 가수 · 초성 · 번호 검색 (예: ㄱㅇㄷㄱ)",
		PlaceholderColor3 = Kit.C.faint,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
	}, sbox)
	Kit.btn(sbox, { text = "✕", style = "ghost", size = UDim2.fromOffset(40, 36), pos = UDim2.new(1, -6, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 14, z = 23, onClick = function()
		search.Text = ""
	end })
	local pending = false
	search:GetPropertyChangedSignal("Text").Changed:Connect(function() end)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		if #search.Text > 24 then
			search.Text = string.sub(search.Text, 1, 24)
			return
		end
		if pending then
			return
		end
		pending = true
		task.delay(0.15, function()
			pending = false
			if sheet.isOpen then
				Book.render()
			end
		end)
	end)
	tabsRow = Kit.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0, LayoutOrder = 2, ZIndex = 22, BorderSizePixel = 0 }, top)
	Kit.list(tabsRow, "h", 6)
	for i, t in TABS do
		tabBtns[t.id] = Kit.chip(tabsRow, { text = t.label, style = "ghost", order = i, z = 23, onClick = function()
			tab = t.id
			expanded = nil
			search.Text = ""
			Book.render()
		end })
	end
	genreRow = Kit.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0, LayoutOrder = 3, ZIndex = 22, Visible = false, BorderSizePixel = 0 }, top)
	Kit.list(genreRow, "h", 6)
	local genres = {}
	for _, g in S.GENRES do
		table.insert(genres, { id = g.id, label = g.emoji .. " " .. g.id })
	end
	table.insert(genres, { id = "듀엣", label = "👫 듀엣" })
	local genreBtns = {}
	for i, g in genres do
		genreBtns[g.id] = Kit.chip(genreRow, { text = g.label, style = if g.id == genre then "magenta" else "ghost", order = i, z = 23, onClick = function()
			genre = g.id
			for id, b in genreBtns do
				Kit.restyle(b, if id == genre then "magenta" else "ghost")
			end
			Book.render()
		end })
	end
	list = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 22 }, sheet.body)
	Kit.list(list, "v", 8)
	sheet.focus = tabBtns.chart
	Rooms.changed(function(v, attr)
		if sheet.isOpen and v == Rooms.current() and (attr == "Queue" or attr == "Credits") then
			local r = room()
			if r then
				sheet.sub.Text = string.format("ROOM %s · 남은 곡 %s · 예약 %d/%d", r.name, if r.unlimited then "∞" else tostring(r.credits), #(r.queue or {}), S.Config.QueueMax)
			end
		end
	end)
end

return Book
