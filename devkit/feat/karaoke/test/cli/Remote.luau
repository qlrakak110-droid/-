-- GwangalliKaraokePlus/Remote (client): the 리모컨.
--   * 5-digit LED + number pad (1-9, 0, ⌫, C) with the song title preview, [예약] [우선예약]
--   * transport: [▶ 시작] [■ 취소] [⏮ 처음부터] [⏸ 일시정지]
--   * 에코 − ■■■□□ + · 키 ♭ 0 ♯ · 템포 − 0 + · 멜로디 켜기/끄기 · 점수 켜기/끄기 (the whole room hears it)
--   * my settings: 반주 / 멜로디 볼륨, 가사 크기, 박자 모드, 효과, 싱크 (voice listeners)
--   * 예약 목록 with [⏫] [✕] (own entries or the renter)
--   * 방 설정 (renter): 🔒 잠금 · 👥 친구만 · 🌐 누구나, 초대하기 / 내보내기, 퇴실하기
--   * 마이크 넘기기 list (Remote.openPass)

local Players = game:GetService("Players")

local Remote = {}

local K: any
local S: any
local Kit: any
local Rooms: any
local player = Players.LocalPlayer

local sheet: any
local passSheet: any
local digits = ""
local led: TextLabel
local ledSub: TextLabel
local echoLbl: TextLabel
local keyLbl: TextLabel
local tempoLbl: TextLabel
local guideBtn: TextButton
local scoreBtn: TextButton
local pauseBtn: TextButton
local queueBox: Frame
local roomBox: Frame
local privBtns: { [string]: TextButton } = {}
local peopleBox: Frame
local sizeBtns: { [string]: TextButton } = {}
local modeBtn: TextButton
local fxBtn: TextButton
local sliders: { [string]: any } = {}

local function room(): any?
	local v = Rooms.current()
	if v and Rooms.allowedMe(v) then
		return v
	end
	return nil
end

local function section(title: string, order: number): Frame
	local f = Kit.new("Frame", { BackgroundColor3 = Kit.C.card, BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = 22 }, sheet.body)
	Kit.corner(f, 16)
	Kit.pad(f, 12, 10)
	Kit.list(f, "v", 8)
	Kit.text(f, { Text = title, Font = Kit.F.black, TextSize = 15, TextColor3 = Kit.C.cyan, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0, ZIndex = 23 })
	return f
end

local function hrow(parent: Instance, order: number, h: number?): Frame
	local r = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 48), LayoutOrder = order, ZIndex = 23 }, parent)
	Kit.list(r, "h", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	return r
end

local function set(field: string, value: any)
	local v = room()
	if not v then
		Kit.toast("방 안에서 쓸 수 있어요", nil, "info")
		return
	end
	K.Net.call("set", { room = v.no, [field] = value })
end

local function saveSetting(field: string, value: any)
	if K.me and K.me.settings then
		K.me.settings[field] = value
	end
	K.applySettings()
	K.Net.call("settings", { [field] = value }, nil, true)
end

-------------------------------------------------------------------------------------------------
-- number pad
-------------------------------------------------------------------------------------------------
local function refreshLed()
	local shown = digits .. string.rep("-", 5 - #digits)
	led.Text = shown
	if #digits == 5 then
		local s = S.Songs.byNo[tonumber(digits) :: number]
		ledSub.Text = if s then string.format("%s · %s", s.title, s.artist) else "없는 곡 번호예요"
		ledSub.TextColor3 = if s then Kit.C.text else Kit.C.red
	elseif #digits > 0 then
		local hits = S.Search.find(S.Songs, digits, 1)
		ledSub.Text = if hits[1] then string.format("%d %s …", hits[1].no, hits[1].title) else "곡 번호 5자리를 눌러 주세요"
		ledSub.TextColor3 = Kit.C.sub
	else
		ledSub.Text = "곡 번호 5자리를 눌러 주세요 (노래책 참고)"
		ledSub.TextColor3 = Kit.C.sub
	end
end

local function press(d: string)
	if d == "⌫" then
		digits = string.sub(digits, 1, -2)
	elseif d == "C" then
		digits = ""
	elseif #digits < 5 then
		digits ..= d
	end
	Kit.sound("tap")
	refreshLed()
end

local function reserveNo(first: boolean)
	local v = room()
	if not v then
		Kit.toast("방 안에서 예약할 수 있어요", nil, "info")
		return
	end
	if #digits ~= 5 then
		Kit.toast("곡 번호 5자리를 눌러 주세요", nil, "warn")
		return
	end
	local no = tonumber(digits)
	K.Net.call("reserveNo", { room = v.no, no = no, first = first }, function(res)
		if res.ok then
			local s = S.Songs.byId[res.song]
			Kit.sound("ping")
			Kit.toast(string.format("%s %d %s", if first then "⏫ 우선예약" else "✅ 예약", no, if s then s.title else ""), string.format("%d번째로 예약했어요", res.pos or 1), "success")
			digits = ""
			refreshLed()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- dynamic parts
-------------------------------------------------------------------------------------------------
local function renderQueue(v: any)
	for _, c in queueBox:GetChildren() do
		if c:IsA("GuiObject") and c.Name ~= "Title" then
			c:Destroy()
		end
	end
	local q = v.queue or {}
	if #q == 0 then
		Kit.text(queueBox, { Text = "예약된 곡이 없어요 · 노래책이나 번호로 예약해요", Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.sub, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, ZIndex = 23 })
		return
	end
	local me = player.UserId
	local renter = Rooms.isRenter(v)
	for i, e in q do
		local s = S.Songs.byId[e.s]
		if not s then
			continue
		end
		local r = Kit.new("Frame", { BackgroundColor3 = Kit.C.card2, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i, ZIndex = 23 }, queueBox)
		Kit.corner(r, 12)
		Kit.text(r, { Text = string.format("%d.  %d  %s%s", i, s.no, s.title, if e.d then " 👫" else ""), Font = Kit.F.bold, TextSize = 14, Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -120, 0, 24), ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
		Kit.text(r, { Text = e.n .. "님", Font = Kit.F.medium, TextSize = 11, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -120, 0, 18), ZIndex = 24 })
		if e.by == me or renter then
			if i > 1 then
				Kit.btn(r, { text = "⏫", style = "gold", size = UDim2.fromOffset(44, 36), pos = UDim2.new(1, -56, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 14, z = 24, onClick = function()
					K.Net.call("first", { room = v.no, qid = e.q })
				end })
			end
			Kit.btn(r, { text = "✕", style = "danger", size = UDim2.fromOffset(44, 36), pos = UDim2.new(1, -6, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 14, z = 24, onClick = function()
				K.Net.call("cancel", { room = v.no, qid = e.q })
			end })
		end
	end
end

local function refresh()
	local v = room()
	if not v then
		sheet.sub.Text = "방 안에서 쓸 수 있어요"
		return
	end
	sheet.sub.Text = string.format("ROOM %s · 남은 곡 %s · 예약 %d/%d%s", v.name, if v.unlimited then "∞" else tostring(v.credits), #(v.queue or {}), S.Config.QueueMax, if Rooms.isRenter(v) then " · 👑 방장" else "")
	local e = v.echo or 0
	echoLbl.Text = string.format("에코 %s  %s", string.rep("■", e) .. string.rep("□", S.Config.EchoMax - e), S.ECHO_LABELS[e] or "")
	if not v.voiceRig then
		echoLbl.Text ..= "  (멜로디)"
	end
	keyLbl.Text = if v.key == 0 then "키 원키" else string.format("키 %s%d", if v.key > 0 then "♯" else "♭", math.abs(v.key))
	tempoLbl.Text = if v.tempo == 0 then "템포 0" else string.format("템포 %+d", v.tempo)
	guideBtn.Text = if v.guide then "🎵 멜로디 켜짐" else "🎵 멜로디 꺼짐"
	Kit.restyle(guideBtn, if v.guide then "primary" else "secondary")
	scoreBtn.Text = if v.scoreOn then "💯 점수 켜짐" else "💯 점수 꺼짐"
	Kit.restyle(scoreBtn, if v.scoreOn then "primary" else "secondary")
	pauseBtn.Text = if v.paused then "▶ 다시 재생" else "⏸ 일시정지"
	roomBox.Visible = Rooms.isRenter(v)
	for id, b in privBtns do
		Kit.restyle(b, if v.privacy == id then "magenta" else "secondary")
	end
	renderQueue(v)
end

local function renderPeople()
	for _, c in peopleBox:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local v = room()
	if not v then
		return
	end
	Kit.text(peopleBox, { Text = "근처 손님 불러오는 중…", Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.sub, Size = UDim2.new(1, 0, 0, 22), ZIndex = 23 })
	K.Net.call("nearby", { room = v.no }, function(res)
		for _, c in peopleBox:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not res.ok then
			return
		end
		if #(res.players or {}) == 0 then
			Kit.text(peopleBox, { Text = "근처에 다른 손님이 없어요", Font = Kit.F.medium, TextSize = 13, TextColor3 = Kit.C.sub, Size = UDim2.new(1, 0, 0, 22), ZIndex = 23 })
			return
		end
		for i, p in res.players do
			local r = Kit.new("Frame", { BackgroundColor3 = Kit.C.card2, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, ZIndex = 23 }, peopleBox)
			Kit.corner(r, 12)
			Kit.text(r, { Text = string.format("%s%s", p.n, if p.i then " · 방 안" elseif p.a then " · 초대됨" else ""), Font = Kit.F.bold, TextSize = 14, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -200, 1, 0), ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
			if not p.a then
				Kit.btn(r, { text = "초대", style = "primary", size = UDim2.fromOffset(80, 34), pos = UDim2.new(1, -96, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 13, z = 24, onClick = function()
					K.Net.call("invite", { room = v.no, userId = p.u }, function(r2)
						if r2.ok then
							Kit.toast(string.format("%s님을 초대했어요", p.n), nil, "success")
							renderPeople()
						end
					end)
				end })
			end
			Kit.btn(r, { text = "내보내기", style = "danger", size = UDim2.fromOffset(80, 34), pos = UDim2.new(1, -8, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 13, z = 24, onClick = function()
				Kit.confirm("내보내기", string.format("%s님을 이 방에서 내보낼까요?", p.n), "내보내기", "취소", function(yes)
					if yes then
						K.Net.call("kick", { room = v.no, userId = p.u }, function()
							renderPeople()
						end)
					end
				end)
			end })
		end
	end)
end

function Remote.openPass()
	local v = room()
	if not v then
		return
	end
	for _, c in passSheet.body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local n = 0
	for _, uid in v.memberList or {} do
		if uid ~= player.UserId and v.allowed[uid] then
			local p = Players:GetPlayerByUserId(uid)
			if p then
				n += 1
				Kit.btn(passSheet.body, { text = "🎤 " .. p.DisplayName .. "님에게 건네기", style = "secondary", size = UDim2.new(1, 0, 0, 50), order = n, textSize = 15, onClick = function()
					K.Net.call("mic", { room = v.no, action = "pass", to = uid }, function(res)
						if res.ok then
							Kit.toast("🎤 마이크를 건네는 중…", p.DisplayName .. "님이 받으면 넘어가요", "info")
							passSheet.close()
						end
					end)
				end })
			end
		end
	end
	Kit.btn(passSheet.body, { text = "🎤 테이블에 내려놓기", style = "ghost", size = UDim2.new(1, 0, 0, 50), order = 99, textSize = 15, onClick = function()
		K.Net.call("mic", { room = v.no, action = "put" })
		passSheet.close()
	end })
	if n == 0 then
		Kit.text(passSheet.body, { Text = "방 안에 다른 손님이 없어요", Font = Kit.F.medium, TextSize = 14, TextColor3 = Kit.C.sub, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0, ZIndex = 22 })
	end
	passSheet.open()
end

function Remote.toggle()
	if sheet.isOpen then
		sheet.close()
	else
		Remote.open()
	end
end

function Remote.open()
	refresh()
	refreshLed()
	sheet.open()
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
function Remote.init(k: any)
	K = k
	S, Kit, Rooms = k.S, k.Kit, k.Rooms
	sheet = Kit.sheet("GwKP_Remote", { title = "📟 리모컨", w = 560, h = 700, accent = Kit.C.magenta })
	-- LED + pad
	local pad = section("🔢 번호 예약", 1)
	local ledBox = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 14, 10), Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 1, ZIndex = 23 }, pad)
	Kit.corner(ledBox, 12)
	Kit.stroke(ledBox, Kit.C.green, 1, 0.6)
	led = Kit.text(ledBox, { Text = "-----", Font = Kit.F.black, TextSize = 36, TextColor3 = Color3.fromRGB(120, 255, 140), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	ledSub = Kit.text(ledBox, { Text = "", Font = Kit.F.bold, TextSize = 13, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
	local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4 * 52), LayoutOrder = 2, ZIndex = 23 }, pad)
	Kit.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 46), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, d in { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "⌫" } do
		local b = Kit.btn(grid, { text = d, style = if d == "C" or d == "⌫" then "ghost" else "secondary", textSize = 20, order = i, z = 24, sound = false, onClick = function()
			press(d)
		end })
		if i == 1 then
			sheet.focus = b
		end
	end
	local r1 = hrow(pad, 3)
	Kit.btn(r1, { text = "✅ 예약", style = "primary", size = UDim2.new(0.5, -4, 0, 46), textSize = 16, order = 1, z = 24, onClick = function()
		reserveNo(false)
	end })
	Kit.btn(r1, { text = "⏫ 우선예약", style = "gold", size = UDim2.new(0.5, -4, 0, 46), textSize = 16, order = 2, z = 24, onClick = function()
		reserveNo(true)
	end })
	-- transport
	local tr = section("🎬 재생", 2)
	local r2 = hrow(tr, 1)
	local function trBtn(text: string, style: string, order: number, fn: () -> ()): TextButton
		return Kit.btn(r2, { text = text, style = style, size = UDim2.new(0.25, -6, 0, 46), textSize = 14, order = order, z = 24, onClick = fn })
	end
	trBtn("▶ 시작", "green", 1, function()
		local v = room()
		if v then
			K.Net.call("start", { room = v.no })
		end
	end)
	trBtn("■ 취소", "danger", 2, function()
		local v = room()
		if v then
			K.Net.call("stop", { room = v.no }, function(res)
				if res.ok and res.refunded then
					Kit.toast("곡 취소 · 1곡 돌려받았어요", nil, "success")
				end
			end)
		end
	end)
	trBtn("⏮ 처음부터", "secondary", 3, function()
		local v = room()
		if v then
			K.Net.call("restart", { room = v.no })
		end
	end)
	pauseBtn = trBtn("⏸ 일시정지", "secondary", 4, function()
		local v = room()
		if v then
			K.Net.call("pause", { room = v.no })
		end
	end)
	-- room sound
	local snd = section("🎚 반주기 (방 전체)", 3)
	local function stepper(order: number, minus: string, plus: string, fn: (number) -> ()): TextLabel
		local r = hrow(snd, order)
		Kit.btn(r, { text = minus, style = "secondary", size = UDim2.fromOffset(56, 44), textSize = 18, order = 1, z = 24, onClick = function()
			fn(-1)
		end })
		local l = Kit.text(r, { Text = "", Font = Kit.F.bold, TextSize = 15, Size = UDim2.new(1, -136, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, ZIndex = 24 })
		Kit.btn(r, { text = plus, style = "secondary", size = UDim2.fromOffset(56, 44), textSize = 18, order = 3, z = 24, onClick = function()
			fn(1)
		end })
		return l
	end
	echoLbl = stepper(1, "−", "+", function(d)
		local v = room()
		if v then
			set("echo", math.clamp((v.echo or 0) + d, 0, S.Config.EchoMax))
		end
	end)
	keyLbl = stepper(2, "♭", "♯", function(d)
		local v = room()
		if v then
			set("key", math.clamp((v.key or 0) + d, S.Config.KeyMin, S.Config.KeyMax))
		end
	end)
	tempoLbl = stepper(3, "−", "+", function(d)
		local v = room()
		if v then
			set("tempo", math.clamp((v.tempo or 0) + d, S.Config.TempoMin, S.Config.TempoMax))
		end
	end)
	local r3 = hrow(snd, 4)
	guideBtn = Kit.btn(r3, { text = "", style = "primary", size = UDim2.new(0.5, -4, 0, 44), textSize = 14, order = 1, z = 24, onClick = function()
		local v = room()
		if v then
			set("guide", not v.guide)
		end
	end })
	scoreBtn = Kit.btn(r3, { text = "", style = "primary", size = UDim2.new(0.5, -4, 0, 44), textSize = 14, order = 2, z = 24, onClick = function()
		local v = room()
		if v then
			set("score", not v.scoreOn)
		end
	end })
	-- my settings
	local mine = section("🙋 내 설정", 4)
	local function sliderRow(order: number, label: string, field: string, mn: number, mx: number)
		Kit.text(mine, { Text = label, Font = Kit.F.bold, TextSize = 13, TextColor3 = Kit.C.sub, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, ZIndex = 23 })
		sliders[field] = Kit.slider(mine, { min = mn, max = mx, value = 0.7, step = 0.05, order = order + 1, onChange = function(val, final)
			if K.me and K.me.settings then
				K.me.settings[field] = val
			end
			K.applySettings()
			if final then
				K.Net.call("settings", { [field] = val }, nil, true)
			end
		end })
	end
	sliderRow(1, "반주 볼륨", "bandVol", 0, 1)
	sliderRow(3, "멜로디 가이드 볼륨", "guideVol", 0, 1)
	sliderRow(5, "싱크 (마이크 목소리와 반주 맞추기 · 듣는 사람)", "sync", 0, 0.8)
	local r4 = hrow(mine, 7)
	Kit.text(r4, { Text = "가사 크기", Font = Kit.F.bold, TextSize = 13, TextColor3 = Kit.C.sub, Size = UDim2.fromOffset(80, 44), LayoutOrder = 0, ZIndex = 24 })
	for i, sz in { "S", "M", "L" } do
		sizeBtns[sz] = Kit.btn(r4, { text = ({ S = "작게", M = "보통", L = "크게" })[sz], style = "secondary", size = UDim2.fromOffset(72, 40), textSize = 13, order = i, z = 24, onClick = function()
			saveSetting("lyricSize", sz)
			for id, b in sizeBtns do
				Kit.restyle(b, if id == sz then "primary" else "secondary")
			end
		end })
	end
	local r5 = hrow(mine, 8)
	modeBtn = Kit.btn(r5, { text = "", style = "secondary", size = UDim2.new(0.5, -4, 0, 44), textSize = 13, order = 1, z = 24, onClick = function()
		local cur = K.me and K.me.settings and K.me.settings.mode or "auto"
		local nxt = if cur == "tap" then "auto" else "tap"
		saveSetting("mode", nxt)
		modeBtn.Text = if nxt == "tap" then "🥁 채점: 박자 모드" else "🎤 채점: 자동 (목소리 우선)"
	end })
	fxBtn = Kit.btn(r5, { text = "", style = "secondary", size = UDim2.new(0.5, -4, 0, 44), textSize = 13, order = 2, z = 24, onClick = function()
		local cur = not (K.me and K.me.settings and K.me.settings.fx == false)
		saveSetting("fx", not cur)
		fxBtn.Text = if not cur then "✨ 조명 · 효과 켜짐" else "✨ 조명 · 효과 꺼짐"
	end })
	-- queue
	queueBox = section("📋 예약 목록", 5)
	-- room settings (renter)
	roomBox = section("👑 방 설정", 6)
	local r6 = hrow(roomBox, 1)
	for i, id in S.PRIVACY_ORDER do
		privBtns[id] = Kit.btn(r6, { text = S.PRIVACY[id].label, style = "secondary", size = UDim2.new(1 / 3, -6, 0, 44), textSize = 13, order = i, z = 24, onClick = function()
			local v = room()
			if v then
				K.Net.call("privacy", { room = v.no, mode = id }, function(res)
					if res.ok then
						Kit.toast(S.PRIVACY[id].label, S.PRIVACY[id].sub, "info")
					end
				end)
			end
		end })
	end
	local r7 = hrow(roomBox, 2)
	Kit.btn(r7, { text = "👥 초대 · 내보내기", style = "primary", size = UDim2.new(0.5, -4, 0, 44), textSize = 14, order = 1, z = 24, onClick = renderPeople })
	Kit.btn(r7, { text = "🚪 퇴실하기", style = "danger", size = UDim2.new(0.5, -4, 0, 44), textSize = 14, order = 2, z = 24, onClick = function()
		local v = room()
		if not v then
			return
		end
		local body = if v.unlimited or v.credits <= 0 then "이용해 주셔서 감사합니다. 방을 비울까요?" else string.format("남은 %d곡은 사라져요 (환불 불가). 나갈까요?", v.credits)
		Kit.confirm("🚪 퇴실하기", body, "퇴실", "더 있을래요", function(yes)
			if yes then
				sheet.close()
				K.Net.call("leave", { room = v.no })
			end
		end)
	end })
	peopleBox = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 23 }, roomBox)
	Kit.list(peopleBox, "v", 6)
	-- mic pass sheet
	passSheet = Kit.sheet("GwKP_MicPass", { title = "🎤 마이크 넘기기", sub = "방 안 손님에게 건네요", w = 420, h = 440, accent = Kit.C.magenta })
	sheet.onOpen = function()
		local st = (K.me and K.me.settings) or {}
		for field, sl in sliders do
			sl.set(tonumber(st[field]) or (if field == "sync" then 0.2 else 0.7))
		end
		for id, b in sizeBtns do
			Kit.restyle(b, if id == (st.lyricSize or "M") then "primary" else "secondary")
		end
		modeBtn.Text = if st.mode == "tap" then "🥁 채점: 박자 모드" else "🎤 채점: 자동 (목소리 우선)"
		fxBtn.Text = if st.fx == false then "✨ 조명 · 효과 꺼짐" else "✨ 조명 · 효과 켜짐"
	end
	Rooms.changed(function(v, attr)
		if sheet.isOpen and v == Rooms.current() and attr ~= "Members" and attr ~= "Vibe" and attr ~= "Clock" then
			refresh()
		end
	end)
	refreshLed()
end

return Remote
