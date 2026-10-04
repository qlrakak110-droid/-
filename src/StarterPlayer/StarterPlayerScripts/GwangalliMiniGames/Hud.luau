--!strict
-- GwangalliMiniGames/Hud: the minigames while you walk the promenade (client only, GwangalliUI kit).
--   * STATION CARD (bottom centre) when you are within MS.T.nearStation of a table / machine:
--       free:    [게임 참가] [상대 찾기] [친구에게 신청] [NPC와 연습]  (NPC only where a host waits)
--       waiting: "OOO님이 ₩10,000로 상대를 기다려요" [⚔️ 도전하기 ₩10,000]   (your own seat: [친구에게
--                신청] [일어나기])
--       playing: "OOO VS OOO · 상금 ₩20,000 · 2 : 1" [👀 관전]
--     plus a small 📊 (my record). Buttons are >= 48 px for thumbs.
--   * STAKE PICKER: 친선전 / ₩1,000 / ₩5,000 / ₩10,000 / ₩50,000 (NPC: the host's allowed stakes);
--     a stake you cannot afford (Money / Bank attributes, the server checks again) is disabled.
--   * FRIEND PICKER: players in the server, Roblox friends first, with distance.
--   * CHALLENGE POPUP: "OOO님이 오목 대결을 신청했습니다." 참가비, place, distance, [수락] [거절]
--     with a countdown ring; accepted from far away -> a waypoint marker over the table.
--   * RECORD CARD: rank, rating, per-game W / L / 승률, today's NPC allowance, server top 5.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Hud = {}

local K: any = nil
local MS: any = nil
local Net: any = nil
local gui: ScreenGui = nil :: any
local player = Players.LocalPlayer

local card: Frame = nil :: any
local cardTitle: TextLabel = nil :: any
local cardSub: TextLabel = nil :: any
local cardButtons: Frame = nil :: any
local nearStation: Model? = nil
local cardKey = ""
local inMatch = false
local scale: UIScale = nil :: any
local inviteCards: { [number]: Frame } = {}
local waypoint: BillboardGui? = nil
local friendCache: { [number]: boolean } = {}
local sheet: any = nil

function Hud.init(k: any, ms: any, net: any, screen: ScreenGui)
	K, MS, Net, gui = k, ms, net, screen
	card = K.Panel(gui, { Name = "StationCard", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(380, 168), Visible = false, Radius = K.Radius.xl })
	scale = Instance.new("UIScale")
	scale.Parent = card
	cardTitle = K.text(card, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -70, 0, 22), Font = K.Font.bold, TextSize = K.Type.title2, TextTruncate = Enum.TextTruncate.AtEnd })
	cardSub = K.text(card, { Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -32, 0, 18), TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
	K.Button(card, { text = "📊", style = "icon", size = UDim2.fromOffset(40, 40), position = UDim2.new(1, -50, 0, 8), onClick = Hud.openRecord })
	cardButtons = K.frame(card, { Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 1, -72) })
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.CellSize = UDim2.new(0.5, -4, 0, 46)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cardButtons
	RunService.Heartbeat:Connect(Hud.step)
	Net.on(MS.Kinds.invite, Hud.invite)
	Net.on(MS.Kinds.inviteClosed, function(p: any)
		local c = inviteCards[p and p.id]
		if c then
			inviteCards[p.id] = nil
			c:Destroy()
			if p.reason == "taken" then
				K.toast({ kind = "info", title = "마감됐어요", body = "다른 사람이 먼저 수락했어요" })
			end
		end
	end)
	Net.on(MS.Kinds.waypoint, Hud.waypoint)
end

function Hud.setInMatch(on: boolean)
	inMatch = on
	if on then
		card.Visible = false
		cardKey = ""
	end
end

local function money(): (number, number)
	local c = player:GetAttribute("Money")
	local b = player:GetAttribute("Bank")
	return if type(c) == "number" then c else 0, if type(b) == "number" then b else 0
end

local function rootPos(): Vector3?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else nil
end

local function stationPos(m: Model): Vector3
	local f = m:FindFirstChild("Focus")
	if f and f:IsA("BasePart") then
		return f.Position
	end
	return m:GetPivot().Position
end

-------------------------------------------------------------------------------------------------
-- station card
-------------------------------------------------------------------------------------------------
local function clearButtons()
	for _, c in cardButtons:GetChildren() do
		if c:IsA("GuiButton") or c:IsA("Frame") then
			c:Destroy()
		end
	end
end

local function btn(text: string, icon: string?, style: string, order: number, fn: () -> ()): TextButton
	return K.Button(cardButtons, { text = text, icon = icon, style = style, order = order, textSize = K.Type.bodySm, onClick = fn })
end

local function nameOf(id: string): string
	local n = MS.NPCS[id]
	return if n then n.name else ""
end

local function render(m: Model)
	local gameId = m:GetAttribute("GameId") :: string
	local info = MS.GAMES[gameId]
	if not info then
		return
	end
	local state = m:GetAttribute("State")
	local npcId = m:GetAttribute("NpcId")
	local station = m:GetAttribute("StationId")
	local p1, p2 = m:GetAttribute("P1") or "", m:GetAttribute("P2") or ""
	local p1Id = m:GetAttribute("P1Id")
	local waitStake = m:GetAttribute("WaitStake") or -1
	local pot = m:GetAttribute("Pot") or 0
	local score = m:GetAttribute("Score") or ""
	local key = table.concat({ station, state, p1, p2, tostring(waitStake), tostring(pot), score }, "|")
	if key == cardKey then
		return
	end
	cardKey = key
	cardTitle.Text = info.icon .. " " .. info.name .. "  ·  " .. (m:GetAttribute("Label") or "")
	clearButtons()
	local host = if type(npcId) == "string" and npcId ~= "" then MS.NPCS[npcId] else nil
	if state == "idle" then
		cardSub.Text = if host then (host.name .. " (" .. MS.DIFFICULTY[host.difficulty] .. ")가 기다리고 있어요 · " .. info.desc) else info.desc
		btn("게임 참가", "🪑", "primary", 1, function()
			Hud.pickStake(station, "sit", nil)
		end)
		btn("상대 찾기", "📣", "tonal", 2, function()
			Hud.pickStake(station, "open", nil)
		end)
		btn("친구에게 신청", "💌", "secondary", 3, function()
			Hud.pickFriend(station)
		end)
		if host then
			btn("NPC와 연습", "🤖", "gold", 4, function()
				Hud.pickStake(station, "practice", host)
			end)
		end
	elseif state == "waiting" then
		local mine = p1Id == player.UserId
		if mine then
			cardSub.Text = "상대를 기다리는 중 · " .. MS.stakeLabel(waitStake) .. (if p2 ~= "" then " · " .. p2 .. "님이 오는 중" else "")
			btn("친구에게 신청", "💌", "secondary", 1, function()
				Hud.pickFriend(station, waitStake)
			end)
			btn("상대 찾기", "📣", "tonal", 2, function()
				Net.send("open", { station = station, stake = waitStake })
			end)
			btn("일어나기", "🚶", "danger", 3, function()
				Net.send("leave")
			end)
		else
			cardSub.Text = p1 .. "님이 " .. MS.stakeLabel(waitStake) .. (if waitStake > 0 then "로" else "으로") .. " 상대를 기다려요"
			if p2 ~= "" then
				cardSub.Text = p1 .. "님과 " .. p2 .. "님이 곧 대결해요"
			else
				local c, b = money()
				local b1 = btn("도전하기 " .. MS.stakeLabel(waitStake), "⚔️", "gold", 1, function()
					Net.send("join", { station = station })
				end)
				if not MS.canAfford(c, b, waitStake) then
					K.setButtonEnabled(b1, false)
					cardSub.Text ..= " · 게임머니 부족"
				end
			end
		end
	else
		cardSub.Text = string.format("%s VS %s · %s%s", p1, p2, if pot > 0 then "상금 " .. MS.won(pot) else "친선전", if score ~= "" then " · " .. score else "")
		btn("관전", "👀", "tonal", 1, function()
			Net.send("spectate", { station = station })
		end)
	end
	local n = 0
	for _, c in cardButtons:GetChildren() do
		if c:IsA("GuiButton") then
			n += 1
		end
	end
	card.Size = UDim2.fromOffset(380, 72 + math.max(1, math.ceil(n / 2)) * 54)
	local _ = nameOf
end

function Hud.step()
	if inMatch then
		return
	end
	local pos = rootPos()
	local best: Model? = nil
	local bestD = MS.T.nearStation
	if pos then
		for _, m in CollectionService:GetTagged(MS.Tags.Station) do
			if m:IsA("Model") then
				local d = (stationPos(m) - pos).Magnitude
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
	end
	if best ~= nearStation then
		nearStation = best
		cardKey = ""
		if best then
			card.Visible = true
			K.pop(card, 0.94)
		else
			card.Visible = false
		end
	end
	if best then
		local cam = Workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			scale.Scale = if vp.X < 700 then math.clamp(vp.X / 520, 0.78, 1) else 1
		end
		render(best)
	end
	-- waypoint distance
	if waypoint and waypoint.Parent and pos then
		local adornee = waypoint.Adornee
		local l = waypoint:FindFirstChild("Dist") :: TextLabel?
		if adornee and adornee:IsA("BasePart") and l then
			l.Text = math.floor((adornee.Position - pos).Magnitude * 0.28 + 0.5) .. "m"
		end
	end
end

-------------------------------------------------------------------------------------------------
-- stake picker
-------------------------------------------------------------------------------------------------
local function closeSheet()
	if sheet then
		pcall(sheet.close)
		sheet = nil
	end
end

-- action "sit" | "open" | "practice" | "challenge"
function Hud.pickStake(station: string, action: string, host: any?, target: Player?)
	closeSheet()
	local stakes = if host then MS.NPC_STAKES[host.difficulty] else MS.STAKES
	local title = if action == "practice" then (host.name .. "와 연습") elseif action == "challenge" and target then (target.DisplayName .. "님에게 신청") else "참가비 선택"
	sheet = K.BottomSheet(gui, { title = title, subtitle = "게임 안의 원(게임머니)만 걸 수 있어요 · 실제 돈/Robux와 무관", height = 300 })
	local content = sheet.content
	local grid = K.frame(content, { Size = UDim2.new(1, 0, 0, 120) })
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -6, 0, 52)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local c, b = money()
	for i, s in stakes do
		local ok = MS.canAfford(c, b, s)
		local bt = K.Button(grid, {
			text = MS.stakeLabel(s),
			style = if s == 0 then "secondary" elseif s >= 10000 then "gold" else "tonal",
			order = i,
			textSize = K.Type.body,
			onClick = function()
				closeSheet()
				if action == "challenge" and target then
					Net.send("challenge", { station = station, target = target.UserId, stake = s })
				else
					Net.send(action, { station = station, stake = s })
				end
			end,
		})
		if not ok then
			K.setButtonEnabled(bt, false)
		end
	end
	local note = if host then string.format("NPC 상대는 하루 순수익 %s까지만 받을 수 있어요. 이겨서 받는 돈은 연습 보너스예요.", MS.won(MS.NPC_DAILY_PROFIT_CAP)) else "이기면 상대 참가비까지 모두 받아요. 경기 전에 나가면 참가비는 돌려받고, 경기 중에 나가면 기권패예요."
	K.text(content, { Position = UDim2.fromOffset(0, 128), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Text = note .. "\n보유: 현금 " .. MS.won(c) .. " · 통장 " .. MS.won(b) })
	sheet.open()
end

-------------------------------------------------------------------------------------------------
-- friend picker
-------------------------------------------------------------------------------------------------
local function isFriend(p: Player): boolean
	local v = friendCache[p.UserId]
	if v == nil then
		friendCache[p.UserId] = false
		task.spawn(function()
			local ok, res = pcall(function()
				return player:IsFriendsWith(p.UserId)
			end)
			friendCache[p.UserId] = ok and res == true
		end)
		return false
	end
	return v
end

function Hud.pickFriend(station: string, fixedStake: number?)
	closeSheet()
	sheet = K.BottomSheet(gui, { title = "대결 신청", subtitle = "친구 · 근처 사람에게 신청해요", height = 380 })
	local scroll = K.make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, sheet.content)
	K.list(scroll, false, 6)
	local pos = rootPos()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			local d = if r and pos then ((r :: BasePart).Position - pos).Magnitude else 1e9
			table.insert(list, { p = p, d = d, f = isFriend(p) })
		end
	end
	table.sort(list, function(a, c)
		if a.f ~= c.f then
			return a.f
		end
		return a.d < c.d
	end)
	if #list == 0 then
		K.EmptyState(scroll, { icon = "🏖️", title = "지금은 다른 사람이 없어요", body = "NPC와 연습하거나 '게임 참가'로 앉아서 기다려 보세요" })
	end
	for i, e in list do
		local p: Player = e.p
		K.ListRow(scroll, {
			icon = if e.f then "💛" else "🙂",
			title = p.DisplayName,
			subtitle = (p:GetAttribute("MiniRankIcon") or "🥉") .. " " .. (p:GetAttribute("MiniRank") or "브론즈") .. " · " .. (if e.d < 1e8 then math.floor(e.d * 0.28) .. "m" else "멀리 있음") .. (if e.f then " · 친구" else ""),
			chevron = true,
			order = i,
			onClick = function()
				closeSheet()
				if fixedStake then
					Net.send("challenge", { station = station, target = p.UserId, stake = fixedStake })
				else
					Hud.pickStake(station, "challenge", nil, p)
				end
			end,
		})
	end
	sheet.open()
end

-------------------------------------------------------------------------------------------------
-- incoming challenges
-------------------------------------------------------------------------------------------------
function Hud.invite(p: any)
	if type(p) ~= "table" or inviteCards[p.id] then
		return
	end
	local stack = gui:FindFirstChild("InviteStack") :: Frame?
	if not stack then
		local f = K.frame(gui, { Name = "InviteStack", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(360, 400), ZIndex = 50 })
		K.list(f, false, 8, Enum.HorizontalAlignment.Center)
		stack = f
	end
	local c = K.Panel(stack, { Size = UDim2.fromOffset(350, 150), ZIndex = 51, BackgroundTransparency = 0.04, Radius = K.Radius.xl })
	inviteCards[p.id] = c
	local who = p.from .. "님이 " .. p.gameName .. " 대결을 " .. (if p.open then "찾고 있어요!" else "신청했습니다.")
	K.text(c, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -80, 0, 40), TextWrapped = true, Font = K.Font.bold, TextSize = K.Type.body, Text = p.icon .. " " .. who, ZIndex = 52 })
	K.text(c, { Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 18), TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.caption, Text = "참가비 " .. MS.stakeLabel(p.stake) .. "  ·  " .. p.rankIcon .. " " .. p.rank, ZIndex = 52 })
	K.text(c, { Position = UDim2.fromOffset(16, 72), Size = UDim2.new(1, -32, 0, 16), TextColor3 = K.Color.sub, TextSize = K.Type.micro, Text = p.where .. (if p.dist and p.dist >= 0 then " · " .. math.floor(p.dist * 0.28) .. "m" else ""), ZIndex = 52 })
	local ring = K.text(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(44, 44), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 16, TextColor3 = K.Color.cyan, ZIndex = 52 })
	K.corner(ring, UDim.new(0.5, 0))
	K.stroke(ring, K.Color.cyan, 2, 0.2)
	local c2, b2 = money()
	local accept = K.Button(c, { text = "수락", icon = "⚔️", style = "success", size = UDim2.new(0.5, -20, 0, 44), position = UDim2.new(0, 14, 1, -54), zIndex = 52, onClick = function()
		Net.send("respond", { id = p.id, accept = true })
		inviteCards[p.id] = nil
		c:Destroy()
	end })
	if not MS.canAfford(c2, b2, p.stake) then
		K.setButtonEnabled(accept, false)
		accept.Text = "게임머니 부족"
	end
	K.Button(c, { text = "거절", style = "secondary", size = UDim2.new(0.5, -20, 0, 44), position = UDim2.new(0.5, 6, 1, -54), zIndex = 52, onClick = function()
		Net.send("respond", { id = p.id, accept = false })
		inviteCards[p.id] = nil
		c:Destroy()
	end })
	K.pop(c, 0.9)
	K.feedback("notify")
	local untilT = os.clock() + (p.ttl or MS.T.inviteTTL)
	task.spawn(function()
		while c.Parent do
			local left = untilT - os.clock()
			if left <= 0 then
				inviteCards[p.id] = nil
				c:Destroy()
				break
			end
			ring.Text = tostring(math.ceil(left))
			task.wait(0.25)
		end
	end)
end

function Hud.waypoint(p: any)
	if waypoint then
		waypoint:Destroy()
		waypoint = nil
	end
	if type(p) ~= "table" or p.clear then
		return
	end
	local m = Workspace:FindFirstChild(MS.FolderName)
	local st = m and m:FindFirstChild(p.station)
	local target: BasePart? = nil
	if st then
		local f = st:FindFirstChild("Focus")
		target = if f and f:IsA("BasePart") then f else nil
	end
	if not target then
		-- not streamed in yet: a temporary anchor part at the position
		local a = Instance.new("Part")
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.Transparency = 1
		a.Size = Vector3.one
		a.Position = p.pos
		a.Parent = Workspace.CurrentCamera
		target = a
		task.delay(p.ttl or 90, function()
			a:Destroy()
		end)
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MiniGameWaypoint"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(150, 64)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	bb.LightInfluence = 0
	bb.Adornee = target
	local l = K.text(bb, { Size = UDim2.new(1, 0, 0.6, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 22, Text = "🎯 대결 테이블", TextStrokeTransparency = 0.4 })
	local _ = l
	local d = K.text(bb, { Name = "Dist", Position = UDim2.fromScale(0, 0.6), Size = UDim2.new(1, 0, 0.4, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.bold, TextSize = 16, TextColor3 = K.Color.gold, TextStrokeTransparency = 0.4 })
	local _2 = d
	bb.Parent = gui
	waypoint = bb
	K.toast({ kind = "travel", title = "대결 테이블로 가요", body = (p.label or "") .. " · " .. math.floor(p.ttl or 90) .. "초 안에 도착해 주세요" })
	task.delay(p.ttl or 90, function()
		if waypoint == bb then
			bb:Destroy()
			waypoint = nil
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- record card
-------------------------------------------------------------------------------------------------
function Hud.openRecord()
	closeSheet()
	sheet = K.BottomSheet(gui, { title = "내 미니게임 전적", subtitle = "불러오는 중…", height = 460 })
	sheet.open()
	task.spawn(function()
		local rec = Net.query("record")
		local board = Net.query("board")
		if not sheet or not rec then
			return
		end
		sheet.setTitle("내 미니게임 전적", rec.rankIcon .. " " .. rec.rank .. " · " .. rec.rating .. "점 · " .. rec.w .. "승 " .. rec.l .. "패 (승률 " .. rec.rate .. "%)")
		local scroll = K.make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, sheet.content)
		K.list(scroll, false, 6)
		local order = 0
		for _, id in MS.GAME_ORDER do
			local g = rec.games[id]
			local info = MS.GAMES[id]
			order += 1
			K.ListRow(scroll, {
				icon = info.icon,
				title = info.name,
				subtitle = if g.w + g.l + g.d > 0 then string.format("전적 %d승 %d패%s · 승률 %d%%", g.w, g.l, if g.d > 0 then " " .. g.d .. "무" else "", g.rate) else "아직 기록이 없어요",
				trailing = if g.best >= 2 then ("최고 " .. g.best .. "연승") else "",
				order = order,
				height = 52,
			})
		end
		order += 1
		K.SectionHeader(scroll, { title = "광안리 명예의 전당 (이 서버)", order = order })
		for i, e in (board or {}) do
			order += 1
			K.ListRow(scroll, { icon = if i == 1 then "👑" else tostring(i), title = e.name, subtitle = e.rankIcon .. " " .. e.rank .. " · " .. e.w .. "승 " .. e.l .. "패", trailing = tostring(e.rating), order = order, height = 48 })
		end
		order += 1
		K.text(scroll, { Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextSize = K.Type.micro, TextColor3 = K.Color.sub, LayoutOrder = order, Text = "랭크: 브론즈 → 실버 1100 → 골드 1250 → 플래티넘 1400 → 다이아 1550 · 오늘 NPC 상금 남은 한도 " .. MS.won(rec.npcRoom) .. (if rec.persistent then "" else " · (이번 접속에만 저장)") })
	end)
end

return Hud
