-- GwangalliKaraokePlus/Hud (client): the on-screen controls around the booth.
--   * action bar inside a room: [📖 노래책] [📟 리모컨] [🎤 마이크] [🪇 탬버린] [👏 박수] [🎉 효과 ▸ 환호 · 폭죽 ·
--     꽃가루 · 춤]; while I sing: [📟 리모컨] [■ 취소] [🎤 넘기기]; free room: [🪙 방 잡기] [📖 노래책]
--   * room info chip (남은 곡 · 예약 · 퇴실 경고), room-entry banner, 🔒 locked banner
--   * payment sheet (동전 · 지폐 넣기), result card, mic hand-over card, knock card
--   * shortcuts inside a room: B / ButtonY 노래책, N / ButtonL1 리모컨, T / ButtonR1 탬버린
--   * HideGwangalliHUD on our ScreenGui while I sing or a sheet is open

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")

local Hud = {}

local K: any
local S: any
local Kit: any
local Rooms: any
local player = Players.LocalPlayer

local bar: Frame
local barBtns: { [string]: TextButton } = {}
local tray: Frame
local info: TextLabel
local banner: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local resultCard: Frame
local offerCard: Frame
local knockCard: Frame
local pay: any
local payRows: Frame
local payBalance: TextLabel
local payRoom: any = nil
local lastFx: { [string]: number } = {}
local bannerUntil = 0
local bound = false
local mode = ""

-------------------------------------------------------------------------------------------------
-- actions
-------------------------------------------------------------------------------------------------
function Hud.cheer(kind: string)
	local v = Rooms.current()
	if not v or not Rooms.allowedMe(v) then
		Kit.toast("방 안에서 함께할 수 있어요", nil, "info")
		return
	end
	local cd = S.Config.EffectCooldown[kind] or 1
	local t = os.clock()
	if t - (lastFx[kind] or -math.huge) < cd then
		return
	end
	lastFx[kind] = t
	local payload: { [string]: any } = { room = v.no, kind = kind }
	if kind == "tamb" and v.state == "play" and v.clock then
		payload.beats = { math.floor(Rooms.songTime(v, S.now()) * 1000 + 0.5) / 1000 }
	end
	K.Band.fx(kind)
	K.Fx.burst(kind)
	if kind ~= "tamb" and kind ~= "clap" then
		K.Fx.emote(kind)
	end
	K.Net.call("cheer", payload, nil, true)
end

function Hud.micToggle()
	local v = Rooms.current()
	if not v then
		return
	end
	if Rooms.micSlot(v) > 0 then
		K.Net.call("mic", { room = v.no, action = "put" })
	else
		K.Net.call("mic", { room = v.no, action = "grab" }, function(res)
			if res.ok then
				local body = if K.Mic.live then "에코 마이크 연결! 가사 색을 따라 불러요" else "음성 채팅이 꺼져 있어 ♪ 박자 버튼으로 채점해요 (음성 채팅을 켜면 에코 마이크)"
				Kit.toast(string.format("🎤 무선 마이크 %d", res.slot or 1), body, "success")
			end
		end)
	end
end

function Hud.stopSong()
	local v = Rooms.current()
	if not v then
		return
	end
	K.Net.call("stop", { room = v.no })
end

-------------------------------------------------------------------------------------------------
-- payment sheet
-------------------------------------------------------------------------------------------------
local function rid(): string
	return string.sub(HttpService:GenerateGUID(false), 1, 18)
end

function Hud.openPay(v: any)
	payRoom = v
	pay.title.Text = string.format("🪙 ROOM %s · 동전 · 지폐 넣기", v.name)
	pay.sub.Text = if v.renter == 0 then "결제하면 이 방을 잡아요 · 같이 온 친구도 함께 들어와요" else string.format("남은 곡 %s곡 · 같이 내기도 돼요", if v.unlimited then "∞" else tostring(v.credits))
	for _, c in payRows:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	payBalance.Text = "잔액 확인 중…"
	local C = S.Config
	local first: GuiObject? = nil
	for i, p in C.Packs do
		local label = string.format("%s  %s", p.label, if K.trial then "무료 체험" else S.won(p.price))
		local b = Kit.btn(payRows, {
			name = p.id,
			text = label .. (if p.badge then "   · " .. p.badge else ""),
			style = if p.badge == "이득" then "gold" elseif i == 1 then "primary" else "secondary",
			size = UDim2.new(1, 0, 0, 58),
			textSize = 19,
			order = i,
			onClick = function(btn)
				btn.Text = "결제 중…"
				K.Net.call("buy", { room = v.no, pack = p.id, rid = rid() }, function(res)
					btn.Text = label .. (if p.badge then "   · " .. p.badge else "")
					if res.ok then
						Kit.sound("coin")
						K.Band.fx("coin")
						pay.close()
					end
				end)
			end,
		})
		local sub = Kit.text(b, { Text = p.sub or "", Font = Kit.F.medium, TextSize = 12, TextColor3 = Kit.C.faint, Position = UDim2.new(1, -110, 0, 0), Size = UDim2.new(0, 100, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = b.ZIndex + 1 })
		sub.TextColor3 = if p.badge == "이득" then Color3.fromRGB(80, 50, 0) else Kit.C.sub
		first = first or b
	end
	pay.focus = first
	pay.open()
	task.spawn(function()
		local res = K.Net.request("balance", {})
		if res.ok and res.economy then
			payBalance.Text = string.format("현금 %s · 통장 %s", S.won(res.cash or 0), S.won(res.bank or 0))
		elseif K.trial then
			payBalance.Text = "무료 체험 중이에요 · 돈이 들지 않아요"
		else
			payBalance.Text = ""
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- cards
-------------------------------------------------------------------------------------------------
local function card(name: string, accent: Color3): (Frame, TextLabel, TextLabel, TextButton, TextButton)
	local f = Kit.new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(420, 150), BackgroundColor3 = Kit.C.glass, BackgroundTransparency = 0.04, Visible = false, ZIndex = 30 }, Kit.gui)
	Kit.corner(f, 18)
	Kit.stroke(f, accent, 2, 0.3)
	local t = Kit.text(f, { Text = "", Font = Kit.F.black, TextSize = 18, Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 0, 26), ZIndex = 31, TextTruncate = Enum.TextTruncate.AtEnd })
	local s = Kit.text(f, { Text = "", Font = Kit.F.medium, TextSize = 14, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -36, 0, 22), ZIndex = 31, TextTruncate = Enum.TextTruncate.AtEnd })
	local yes = Kit.btn(f, { text = "", style = "primary", size = UDim2.new(0.5, -24, 0, 48), pos = UDim2.new(0, 18, 1, -62), z = 31 })
	local no = Kit.btn(f, { text = "", style = "secondary", size = UDim2.new(0.5, -24, 0, 48), pos = UDim2.new(0.5, 6, 1, -62), z = 31 })
	return f, t, s, yes, no
end

local offer: any = nil
local knock: any = nil
local offerUI: any = {}
local knockUI: any = {}

local function showOffer(p: any)
	offer = p
	offerUI.t.Text = string.format("🎤 %s님이 마이크를 건넸어요", p.name)
	offerUI.s.Text = string.format("무선 마이크 %d · %d초 안에 받아 주세요", p.slot or 1, p.ttl or 10)
	offerCard.Visible = true
	Kit.sound("ping")
	Kit.select(offerUI.yes)
	local id = p.offer
	task.delay(p.ttl or 10, function()
		if offer and offer.offer == id then
			offer = nil
			offerCard.Visible = false
		end
	end)
end

local function answerOffer(accept: boolean)
	local p = offer
	offer = nil
	offerCard.Visible = false
	if p then
		K.Net.call("micAnswer", { offer = p.offer, accept = accept })
	end
end

local function showKnock(p: any)
	knock = p
	knockUI.t.Text = string.format("🚪 똑똑! %s님이 들어오고 싶어해요", p.name)
	knockUI.s.Text = string.format("ROOM %s · 들여보낼까요?", S.roomName(p.room))
	knockCard.Visible = true
	Kit.sound("ping")
	Kit.select(knockUI.yes)
	local from = p.from
	task.delay(15, function()
		if knock and knock.from == from then
			knock = nil
			knockCard.Visible = false
		end
	end)
end

local function answerKnock(accept: boolean)
	local p = knock
	knock = nil
	knockCard.Visible = false
	if p then
		K.Net.call("knockAnswer", { room = p.room, userId = p.from, accept = accept })
	end
end

local resultUI: any = {}
local function showResult(p: any)
	local m = p.mine
	if type(m) ~= "table" then
		return
	end
	local song = S.Songs.byId[p.song or ""]
	resultUI.score.Text = string.format("%d점", m.score or 0)
	resultUI.grade.Text = string.format("%s · %s", m.grade or "", if song then song.title else "")
	local lines = {}
	if m.rewards and m.rewards ~= "" then
		table.insert(lines, "🎁 " .. m.rewards)
	end
	if m.isBest then
		table.insert(lines, "🏅 내 최고 기록!")
	end
	if (m.rank or 0) > 0 then
		table.insert(lines, string.format("👑 오늘의 노래왕 %d위", m.rank))
	end
	if m.bonus then
		table.insert(lines, "🎉 서비스 1곡!")
	end
	resultUI.sub.Text = if #lines > 0 then table.concat(lines, "  ·  ") else "오늘 보상은 다 받았어요 · 그래도 즐겁게!"
	resultUI.song = p.song
	local fav = K.me and K.me.fav and table.find(K.me.fav, p.song) ~= nil
	resultUI.fav.Text = if fav then "♥ 애창곡" else "♡ 애창곡에 추가"
	resultCard.Visible = true
	resultCard.Position = UDim2.new(1, 20, 1, -110)
	Kit.tween(resultCard, 0.35, { Position = UDim2.new(1, -16, 1, -110) }, Enum.EasingStyle.Back)
	local serial = p.serial
	resultUI.serial = serial
	task.delay(11, function()
		if resultUI.serial == serial then
			resultCard.Visible = false
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- bar
-------------------------------------------------------------------------------------------------
local function setBar(m: string)
	if m == mode then
		return
	end
	mode = m
	local show: { [string]: boolean } = {}
	if m == "free" then
		show = { rent = true, book = true }
	elseif m == "member" then
		show = { book = true, remote = true, mic = true, tamb = true, clap = true, more = true }
	elseif m == "singer" then
		show = { remote = true, stop = true, mic = true, tamb = false }
	elseif m == "locked" then
		show = { knock = true }
	end
	local n = 0
	for name, b in barBtns do
		b.Visible = show[name] == true
		if b.Visible then
			n += 1
		end
	end
	bar.Visible = n > 0
	tray.Visible = false
end

local function barButton(name: string, text: string, order: number, style: string?, fn: () -> ()): TextButton
	local b = Kit.btn(bar, { name = name, text = text, style = style or "secondary", size = UDim2.fromOffset(70, 58), textSize = 13, order = order, radius = 14, onClick = fn })
	b.TextWrapped = true
	barBtns[name] = b
	return b
end

local function bindKeys(on: boolean)
	if on == bound then
		return
	end
	bound = on
	if on then
		ContextActionService:BindAction("GwKP_Book", function(_, st)
			if st == Enum.UserInputState.Begin then
				K.Book.toggle()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.B, Enum.KeyCode.ButtonY)
		ContextActionService:BindAction("GwKP_Remote", function(_, st)
			if st == Enum.UserInputState.Begin then
				K.Remote.toggle()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.N, Enum.KeyCode.ButtonL1)
		ContextActionService:BindAction("GwKP_Tamb", function(_, st)
			if st == Enum.UserInputState.Begin then
				local v = Rooms.current()
				if v and Rooms.micSlot(v) > 0 then
					Hud.cheer("clap")
				else
					Hud.cheer("tamb")
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.T, Enum.KeyCode.ButtonR1)
	else
		ContextActionService:UnbindAction("GwKP_Book")
		ContextActionService:UnbindAction("GwKP_Remote")
		ContextActionService:UnbindAction("GwKP_Tamb")
	end
end

function Hud.banner(title: string, sub: string?, secs: number?)
	bannerTitle.Text = title
	bannerSub.Text = sub or ""
	banner.Visible = true
	bannerUntil = os.clock() + (secs or 3.5)
end

local function onEnter(v: any?, prev: any?)
	if v then
		if v.renter == 0 then
			Hud.banner(string.format("🎤 ROOM %s · 빈 방", v.name), "반주기 동전 투입구나 🪙 방 잡기 버튼으로 시작해요", 4)
		elseif Rooms.allowedMe(v) then
			Hud.banner(string.format("🎤 ROOM %s · 남은 곡 %s곡 · 예약 %d곡", v.name, if v.unlimited then "∞" else tostring(v.credits), #(v.queue or {})), if Rooms.isRenter(v) then "내 방이에요 · 📟 리모컨에서 방 설정" else string.format("%s님의 방", v.renterName), 4)
		else
			Hud.banner("🔒 이 방은 다른 손님이 이용 중이에요", "문 옆 패널에서 노크해 보세요", 4)
		end
	elseif prev and Rooms.isRenter(prev) and prev.renter ~= 0 then
		Hud.banner(string.format("🚪 ROOM %s 밖으로 나왔어요", prev.name), string.format("방이 비면 %d초 뒤 퇴실되고 남은 곡은 사라져요", S.Config.EmptyGrace), 5)
	end
end

function Hud.update(_dt: number)
	local v = Rooms.current()
	local m = ""
	if v then
		if v.renter == 0 then
			m = "free"
		elseif Rooms.allowedMe(v) then
			m = if Rooms.isSinger(v) and v.state == "play" then "singer" else "member"
		else
			m = "locked"
		end
	end
	setBar(m)
	bindKeys(m == "member" or m == "singer")
	if v and m ~= "" and m ~= "locked" then
		local mic = Rooms.micSlot(v)
		barBtns.mic.Text = if mic > 0 then (if m == "singer" then "🎤\n넘기기" else "🎤\n내려놓기") else "🎤\n마이크"
		Kit.restyle(barBtns.mic, if mic > 0 then "magenta" else "secondary")
		barBtns.tamb.Text = if mic > 0 then "👏\n박수" else "🪇\n탬버린"
		local now = S.now()
		local parts = { string.format("ROOM %s", v.name) }
		if v.renter ~= 0 then
			table.insert(parts, if v.unlimited then "남은 곡 ∞" else string.format("남은 곡 %d", v.credits))
			table.insert(parts, string.format("예약 %d/%d", #(v.queue or {}), S.Config.QueueMax))
		end
		if v.idleT and v.idleT > 0 and v.idleT - now < 35 then
			table.insert(parts, string.format("⚠ %d초 뒤 퇴실", math.max(0, math.ceil(v.idleT - now))))
		end
		info.Text = table.concat(parts, "  ·  ")
		info.Visible = true
	else
		info.Visible = false
	end
	if banner.Visible and os.clock() > bannerUntil then
		banner.Visible = false
	end
	local hide = m == "singer" or Kit.anyOpen()
	if Kit.gui:GetAttribute("HideGwangalliHUD") ~= hide then
		Kit.gui:SetAttribute("HideGwangalliHUD", hide)
	end
end

function Hud.init(k: any)
	K = k
	S, Kit, Rooms = k.S, k.Kit, k.Rooms
	-- action bar
	bar = Kit.new("Frame", { Name = "ActionBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(0, 70), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Kit.C.glass, BackgroundTransparency = 0.12, Visible = false, ZIndex = 5 }, Kit.gui)
	Kit.corner(bar, 20)
	Kit.stroke(bar, Kit.C.cyan, 1, 0.7)
	Kit.pad(bar, 8, 6)
	Kit.list(bar, "h", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	barButton("rent", "🪙\n방 잡기", 1, "gold", function()
		local v = Rooms.current()
		if v then
			Hud.openPay(v)
		end
	end)
	barButton("knock", "🚪\n노크", 1, "primary", function()
		local v = Rooms.current() or Rooms.near()
		if v then
			K.Net.call("knock", { room = v.no }, function(res)
				if res.ok then
					Kit.toast("🚪 똑똑!", "방장에게 노크했어요", "info")
				end
			end)
		end
	end)
	barButton("book", "📖\n노래책", 2, "primary", function()
		K.Book.toggle()
	end)
	barButton("remote", "📟\n리모컨", 3, "secondary", function()
		K.Remote.toggle()
	end)
	barButton("stop", "■\n취소", 4, "danger", Hud.stopSong)
	barButton("mic", "🎤\n마이크", 5, "secondary", function()
		local v = Rooms.current()
		if v and Rooms.micSlot(v) > 0 and v.state == "play" and Rooms.isSinger(v) then
			K.Remote.openPass()
		else
			Hud.micToggle()
		end
	end)
	barButton("tamb", "🪇\n탬버린", 6, "secondary", function()
		local v = Rooms.current()
		Hud.cheer(if v and Rooms.micSlot(v) > 0 then "clap" else "tamb")
	end)
	barButton("clap", "👏\n박수", 7, "secondary", function()
		Hud.cheer("clap")
	end)
	barButton("more", "🎉\n효과", 8, "magenta", function()
		tray.Visible = not tray.Visible
	end)
	-- effect tray
	tray = Kit.new("Frame", { Name = "FxTray", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.fromOffset(0, 62), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Kit.C.glass, BackgroundTransparency = 0.08, Visible = false, ZIndex = 6 }, Kit.gui)
	Kit.corner(tray, 18)
	Kit.pad(tray, 8, 6)
	Kit.list(tray, "h", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i, id in { "cheer", "fire", "petal", "dance" } do
		local f = S.FX_BY_ID[id]
		Kit.btn(tray, { name = id, text = f.emoji .. "\n" .. f.label, size = UDim2.fromOffset(66, 50), textSize = 13, order = i, radius = 14, onClick = function()
			Hud.cheer(id)
		end })
	end
	info = Kit.text(Kit.gui, { Name = "RoomInfo", Text = "", Font = Kit.F.bold, TextSize = 13, TextColor3 = Kit.C.sub, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -86), Size = UDim2.fromOffset(520, 20), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 5 })
	info.TextStrokeTransparency = 0.6
	-- banner
	banner = Kit.new("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(520, 62), BackgroundColor3 = Kit.C.glass, BackgroundTransparency = 0.08, Visible = false, ZIndex = 25 }, Kit.gui)
	Kit.corner(banner, 18)
	Kit.stroke(banner, Kit.C.magenta, 1.5, 0.4)
	bannerTitle = Kit.text(banner, { Text = "", Font = Kit.F.black, TextSize = 17, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26, TextTruncate = Enum.TextTruncate.AtEnd })
	bannerSub = Kit.text(banner, { Text = "", Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -32, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26, TextTruncate = Enum.TextTruncate.AtEnd })
	-- payment sheet
	pay = Kit.sheet("GwKP_Pay", { title = "🪙 동전 · 지폐 넣기", w = 440, h = 470, accent = Kit.C.gold })
	payBalance = Kit.text(pay.body, { Text = "", Font = Kit.F.bold, TextSize = 14, TextColor3 = Kit.C.gold, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, ZIndex = 22 })
	payRows = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 22 }, pay.body)
	Kit.list(payRows, "v", 10)
	Kit.text(pay.body, { Text = "남은 곡은 퇴실하면 사라져요 (환불 불가) · 곡 시작 5초 안에 취소하면 1곡 돌려받아요 · 100점이면 서비스 1곡!", Font = Kit.F.medium, TextSize = 12, TextColor3 = Kit.C.faint, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, ZIndex = 22 })
	-- result card
	resultCard = Kit.new("Frame", { Name = "Result", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -110), Size = UDim2.fromOffset(330, 150), BackgroundColor3 = Kit.C.glass, BackgroundTransparency = 0.04, Visible = false, ZIndex = 28 }, Kit.gui)
	Kit.corner(resultCard, 18)
	Kit.stroke(resultCard, Kit.C.gold, 2, 0.3)
	resultUI.score = Kit.text(resultCard, { Text = "", Font = Kit.F.black, TextSize = 34, TextColor3 = Kit.C.gold, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(140, 42), ZIndex = 29 })
	resultUI.grade = Kit.text(resultCard, { Text = "", Font = Kit.F.bold, TextSize = 14, TextColor3 = Kit.C.text, Position = UDim2.fromOffset(150, 18), Size = UDim2.new(1, -166, 0, 26), ZIndex = 29, TextTruncate = Enum.TextTruncate.AtEnd })
	resultUI.sub = Kit.text(resultCard, { Text = "", Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.sub, TextWrapped = true, Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 36), ZIndex = 29, TextYAlignment = Enum.TextYAlignment.Top })
	resultUI.fav = Kit.btn(resultCard, { text = "♡ 애창곡에 추가", style = "secondary", size = UDim2.new(0.5, -20, 0, 40), pos = UDim2.new(0, 16, 1, -50), textSize = 13, z = 29, onClick = function()
		local id = resultUI.song
		if id then
			local on = not (K.me and K.me.fav and table.find(K.me.fav, id) ~= nil)
			K.Book.setFav(id, on)
			resultUI.fav.Text = if on then "♥ 애창곡" else "♡ 애창곡에 추가"
		end
	end })
	Kit.btn(resultCard, { text = "🎵 한 곡 더", style = "primary", size = UDim2.new(0.5, -20, 0, 40), pos = UDim2.new(0.5, 4, 1, -50), textSize = 13, z = 29, onClick = function()
		resultCard.Visible = false
		K.Book.open()
	end })
	-- mic offer / knock cards
	local f1, t1, s1, y1, n1 = card("MicOffer", Kit.C.magenta)
	offerCard, offerUI = f1, { t = t1, s = s1, yes = y1, no = n1 }
	y1.Text, n1.Text = "🎤 받기", "괜찮아요"
	y1.Activated:Connect(function()
		answerOffer(true)
	end)
	n1.Activated:Connect(function()
		answerOffer(false)
	end)
	local f2, t2, s2, y2, n2 = card("Knock", Kit.C.cyan)
	knockCard, knockUI = f2, { t = t2, s = s2, yes = y2, no = n2 }
	knockCard.Position = UDim2.new(0.5, 0, 0, 280)
	y2.Text, n2.Text = "들어오세요", "거절"
	y2.Activated:Connect(function()
		answerKnock(true)
	end)
	n2.Activated:Connect(function()
		answerKnock(false)
	end)
	Kit.onLayout(function()
		local W = Kit.size()
		local narrow = W < 700
		for _, b in barBtns do
			b.Size = if narrow then UDim2.fromOffset(60, 54) else UDim2.fromOffset(70, 58)
		end
	end)
	-- events
	K.Net.on("toast", function(p)
		Kit.toast(p.title or "", p.body, p.tone)
	end)
	K.Net.on("micOffer", showOffer)
	K.Net.on("knock", showKnock)
	K.Net.on("result", showResult)
	K.Net.on("stopped", function(p)
		Kit.toast(string.format("■ %s님이 곡을 취소했어요", p.by or ""), if p.refunded then "곡 취소 · 1곡 돌려받았어요" else nil, "info")
	end)
	K.Net.on("me", function(p)
		if type(p.me) == "table" then
			K.me = p.me
			K.applySettings()
		end
	end)
	Rooms.entered(onEnter)
end

return Hud
