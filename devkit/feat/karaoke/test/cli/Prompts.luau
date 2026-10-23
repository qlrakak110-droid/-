-- GwangalliKaraokePlus/Prompts (client): local ProximityPrompts on our own invisible anchors in
-- Workspace.GwKaraokePlusLocal.Prompts (never on map parts; the interior team may hide the props, the
-- anchors keep their poses). Every action they trigger is validated by the server.
--   corridor panel   방 잡기 (빈 방) / 노크하기 (다른 손님 방)
--   반주기            동전 넣기 · 남은 곡 N곡
--   리모컨 · 노래책    리모컨 / 노래책 보기
--   무선 마이크 1 · 2  마이크 잡기 / 내려놓기
--   탬버린            탬버린 흔들기
--   lobby            노래책 보기 (읽기 전용) · 랭킹 보기 (오늘의 노래왕) · 지폐 교환 (동전교환기)
-- E / ButtonX / tap, HoldDuration 0, OnePerButton so only the nearest of the close table prompts shows.

local Players = game:GetService("Players")

local Prompts = {}

local K: any
local S: any
local Kit: any
local Rooms: any
local player = Players.LocalPlayer

local folder: Folder
local sets: { [number]: any } = {}
local lobbyDone: { [Instance]: boolean } = {}
local rankSheet: any = nil

local function anchorAt(name: string, pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.3, 0.3, 0.3)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos)
	p.Parent = folder
	return p
end

local function prompt(parent: Instance, action: string, object: string, dist: number, fn: () -> ()): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "GwKP_Prompt"
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = 0
	pr.MaxActivationDistance = dist
	pr.RequiresLineOfSight = false
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pr.KeyboardKeyCode = S.Config.PromptKey
	pr.GamepadKeyCode = S.Config.PromptGamepad
	pr.ClickablePrompt = true
	pr.Triggered:Connect(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[GwangalliKaraokePlus] prompt:", err)
		end
	end)
	pr.Parent = parent
	return pr
end

local function clear(no: number)
	local set = sets[no]
	if set then
		for _, a in set.anchors do
			a:Destroy()
		end
	end
	sets[no] = nil
end

local function build(v: any)
	clear(v.no)
	if not (v.model and v.panel and v.zone) then
		return
	end
	local set: any = { anchors = {}, p = {} }
	sets[v.no] = set
	local parts = v.parts or {}
	local function add(key: string, pos: Vector3, action: string, object: string, dist: number, fn: () -> ())
		local a = anchorAt(string.format("R%s_%s", v.name, key), pos)
		table.insert(set.anchors, a)
		set.p[key] = prompt(a, action, object, dist, fn)
	end
	local out = v.outDir or Vector3.new(-1, 0, 0)
	add("panel", v.panel.Position + out * 0.7, "방 잡기", "", 8, function()
		if v.renter == 0 then
			K.Hud.openPay(v)
		elseif not Rooms.allowedMe(v) then
			K.Net.call("knock", { room = v.no }, function(res)
				if res.ok and not res.allowed then
					Kit.toast("🚪 똑똑!", string.format("ROOM %s 방장에게 노크했어요", v.name), "info")
				elseif res.ok and res.allowed then
					Kit.toast("들어가도 돼요!", "이미 초대된 방이에요", "success")
				end
			end)
		else
			K.Hud.openPay(v)
		end
	end)
	if parts.machine then
		add("coin", parts.machine.Position + Vector3.new(0, parts.machine.Size.Y * 0.5 + 0.4, 0), "동전 넣기", "", 7, function()
			K.Hud.openPay(v)
		end)
	end
	if parts.remote then
		add("remote", parts.remote.Position + Vector3.new(0, 0.5, 0), "리모컨", "예약 · 에코 · 키", 6, function()
			K.Remote.open()
		end)
	end
	if parts.book then
		add("book", parts.book.Position + Vector3.new(0, 0.6, 0), "노래책 보기", string.format("총 %d곡", S.Songs.COUNT), 6, function()
			K.Book.open()
		end)
	end
	for i = 1, 2 do
		local m = parts.mics and parts.mics[i]
		if m then
			add("mic" .. i, m.Position + Vector3.new(0, 0.5, 0), "마이크 잡기", "무선 마이크 " .. i, 6, function()
				if Rooms.micSlot(v) == i then
					K.Net.call("mic", { room = v.no, action = "put" })
				else
					K.Net.call("mic", { room = v.no, action = "grab", slot = i })
				end
			end)
		end
	end
	if parts.tamb then
		add("tamb", parts.tamb.Position + Vector3.new(0, 0.5, 0), "탬버린 흔들기", "🪇 박자에 맞춰 흔들어요", 6, function()
			K.Hud.cheer("tamb")
		end)
	end
end

-- prompt texts / visibility from the room state
local function refresh(v: any)
	local set = sets[v.no]
	if not set then
		return
	end
	local cur = Rooms.current()
	local inside = cur == v
	local allowed = Rooms.allowedMe(v)
	local free = v.renter == 0
	local P = set.p
	local credits = if v.unlimited then "∞" else tostring(v.credits)
	if P.panel then
		if free then
			P.panel.Enabled = not inside
			P.panel.ActionText = "방 잡기"
			P.panel.ObjectText = string.format("ROOM %s · 1곡 %s", v.name, S.won(S.Config.Packs[1].price))
		elseif not allowed then
			P.panel.Enabled = not inside
			P.panel.ActionText = "노크하기"
			P.panel.ObjectText = string.format("ROOM %s · %s님 이용 중", v.name, v.renterName)
		else
			P.panel.Enabled = not inside
			P.panel.ActionText = "동전 넣기"
			P.panel.ObjectText = string.format("ROOM %s · 남은 곡 %s곡", v.name, credits)
		end
	end
	if P.coin then
		P.coin.Enabled = inside and (free or allowed)
		P.coin.ActionText = if free then "방 잡기" else "동전 넣기"
		P.coin.ObjectText = if free then "1곡 500원 · 4곡 1,000원" else string.format("남은 곡 %s곡", credits)
	end
	if P.remote then
		P.remote.Enabled = inside and allowed
	end
	if P.book then
		P.book.Enabled = inside
	end
	local mySlot = Rooms.micSlot(v)
	for i = 1, 2 do
		local pr = P["mic" .. i]
		if pr then
			local holder = v.mics and v.mics[i] or 0
			pr.Enabled = inside and allowed and (holder == 0 or holder == player.UserId) and (mySlot == 0 or mySlot == i)
			pr.ActionText = if holder == player.UserId then "마이크 내려놓기" else "마이크 잡기"
		end
	end
	if P.tamb then
		P.tamb.Enabled = inside and allowed and mySlot == 0
	end
end

-------------------------------------------------------------------------------------------------
-- lobby (catalog stand, ranking board, coin changer)
-------------------------------------------------------------------------------------------------
local function showRanking()
	if not rankSheet then
		rankSheet = Kit.sheet("GwKP_Rank", { title = "👑 오늘의 노래왕", sub = "이 서버 오늘의 최고 점수 TOP 5", w = 460, h = 480, accent = Kit.C.gold })
	end
	for _, c in rankSheet.body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local king = S.decode((K.stateFolder :: Instance):GetAttribute("King")) or {}
	if #king == 0 then
		Kit.text(rankSheet.body, { Text = "아직 기록이 없어요 · 첫 노래왕에 도전해 보세요! 🎤", Font = Kit.F.medium, TextSize = 14, TextColor3 = Kit.C.sub, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), ZIndex = 22 })
	end
	for i, e in king do
		local f = Kit.new("Frame", { BackgroundColor3 = if i == 1 then Color3.fromRGB(70, 56, 20) else Kit.C.card, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = i, ZIndex = 22 }, rankSheet.body)
		Kit.corner(f, 14)
		Kit.text(f, { Text = string.format("%s %s", ({ "🥇", "🥈", "🥉", "4", "5" })[i] or tostring(i), e.n), Font = Kit.F.black, TextSize = 16, Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -110, 0, 26), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd })
		Kit.text(f, { Text = "♪ " .. (e.t or ""), Font = Kit.F.medium, TextSize = 12, TextColor3 = Kit.C.sub, Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -110, 0, 20), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd })
		Kit.text(f, { Text = string.format("%d점", e.s or 0), Font = Kit.F.black, TextSize = 22, TextColor3 = Kit.C.gold, Position = UDim2.new(1, -100, 0, 0), Size = UDim2.new(0, 86, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 23 })
	end
	rankSheet.open()
end

local function lobbyFor(v: any)
	local m = v.model
	if not m then
		return
	end
	-- the venue model that holds the booths
	local venue = m.Parent
	while venue and venue ~= workspace do
		local hit = false
		for _, n in S.Config.VenueModelNames do
			if venue.Name == n then
				hit = true
			end
		end
		if hit then
			break
		end
		venue = venue.Parent
	end
	if not venue or venue == workspace or lobbyDone[venue] then
		return
	end
	local function find(name: string): BasePart?
		local p = venue:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			return p
		end
		if p and p:IsA("Model") then
			local pp = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true)
			return pp
		end
		return nil
	end
	local book = find("CatalogBook") or find("CatalogPost")
	local board = find("Board_karaoke")
	local face = board and (board.Parent and board.Parent:FindFirstChild("BoardFace", true)) or nil
	local boardPart = (if face and face:IsA("BasePart") then face else board) :: BasePart?
	local changer = find("CoinChanger")
	if not (book or boardPart or changer) then
		return
	end
	lobbyDone[venue] = true
	if book then
		prompt(anchorAt("Lobby_Book", book.Position + Vector3.new(0, 0.4, 0)), "노래책 보기", "노래 책 · 신곡 목록", 8, function()
			K.Book.open({ readOnly = Rooms.current() == nil })
		end)
	end
	if boardPart then
		prompt(anchorAt("Lobby_Rank", boardPart.Position), "랭킹 보기", "👑 오늘의 노래왕", 10, showRanking)
	end
	if changer then
		prompt(anchorAt("Lobby_Changer", changer.Position), "지폐 교환", "1,000원 → 500원 동전 2개", 7, function()
			Kit.sound("coin")
			Kit.toast("🪙 짤랑!", "방 안 반주기에서 지폐도 바로 결제돼요", "info")
		end)
	end
end

function Prompts.init(k: any)
	K = k
	S, Kit, Rooms = k.S, k.Kit, k.Rooms
	local localFolder = workspace:WaitForChild(S.NAMES.ClientFolder, 10)
	if not localFolder then
		localFolder = Instance.new("Folder")
		localFolder.Name = S.NAMES.ClientFolder
		localFolder.Parent = workspace
	end
	folder = Instance.new("Folder")
	folder.Name = "Prompts"
	folder.Parent = localFolder
	for _, v in Rooms.views do
		build(v)
		refresh(v)
		lobbyFor(v)
	end
	Rooms.changed(function(v, attr)
		if attr == "Model" then
			build(v)
			lobbyFor(v)
		end
		refresh(v)
	end)
	Rooms.entered(function(v, prev)
		if v then
			refresh(v)
		end
		if prev then
			refresh(prev)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, v in Rooms.views do
				refresh(v)
			end
		end
	end)
end

return Prompts
