-- GwangalliClubPlus.Signs: small world signs around the show (client; every GUI lives in PlayerGui
-- with an Adornee, never under a map part).
--   table LED signs   one per occupied table (GwangalliClubShow Tables attribute): table number in the
--                     tier colour, the current orderer, the set; pops on every new order; chips for
--                     "✨ 합석 중" (Booking), "🎧 DJ" (the guest DJ's table), "💸 후원 도착" (a 후원 to it)
--   presenter board   floating board over the lead bottle-staff during the club's own parade
--                     ("✨ 골드 스파클링 주스 · G2 · 하늘님 · ₩600,000")
--   bartender flair   a main-bar bartender flips a glowing juice bottle when an order comes in
--   crown nameplates  👑 오늘의 큰손 / 💸 후원왕 over tonight's #1s (ClubRanking draws its own 큰손 crown
--                     when it runs: then we only add 후원왕, stacked above it)

local Players = game:GetService("Players")

local Signs = {}

local Core: any
local S: any
local Fx: any
local L: any

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 194, 71)
local GLASS = Color3.fromRGB(15, 18, 31)

local signs: { [string]: any } = {}
local bookingTable: string? = nil
local bookingUntil = 0
local djTable: string? = nil
local pings: { [string]: { text: string, untilT: number } } = {}

local function menuItem(id: any): any?
	local SS = Core.ShowShared
	if SS and type(SS.item) == "function" then
		local ok, it = pcall(SS.item, id)
		if ok and type(it) == "table" then
			return it
		end
	end
	return nil
end
local function itemText(id: any): (string, string, number)
	local it = menuItem(id)
	if not it then
		return "✨", "음료 세트", 0
	end
	local SS = Core.ShowShared
	local aa = Core.allAges()
	local icon, label = "✨", tostring(it.labelAA or it.label or "음료 세트")
	if type(SS.icon) == "function" then
		local ok, v = pcall(SS.icon, it, aa)
		if ok and type(v) == "string" then
			icon = v
		end
	end
	if type(SS.label) == "function" then
		local ok, v = pcall(SS.label, it, aa)
		if ok and type(v) == "string" then
			label = v
		end
	end
	return icon, label, tonumber(it.price) or 0
end

-------------------------------------------------------------------------------------------------
-- table signs
-------------------------------------------------------------------------------------------------
local function buildSign(id: string, info: any): any?
	local cfg = S.Config.Show
	local pos = info.top + Vector3.new(0, cfg.SignHeight, 0)
	local anchor = Core.part("PlusSign_" .. id, Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos))
	anchor.Transparency = 1
	local bb = Core.billboard("GwClubPlusSign_" .. id, anchor, UDim2.new(4.8, 0, 1.45, 0), Vector3.zero, { MaxDistance = cfg.SignDistance, LightInfluence = 0 })
	local plate = Core.frame(bb, { Name = "Plate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = GLASS, BackgroundTransparency = 0.12, corner = UDim.new(0.22, 0), strokeColor = WHITE, strokeT = 0.2 })
	local scale = Instance.new("UIScale")
	scale.Parent = plate
	local num = Core.frame(plate, { Name = "Num", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = WHITE, corner = UDim.new(0.22, 0) })
	local numText = Core.text(num, { Size = UDim2.fromScale(0.86, 0.7), Position = UDim2.fromScale(0.07, 0.15), Text = id, TextColor3 = Color3.fromRGB(12, 12, 22) })
	local name = Core.text(plate, { Position = UDim2.fromScale(0.34, 0.08), Size = UDim2.fromScale(0.63, 0.44), Text = "", Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left })
	local sub = Core.text(plate, { Position = UDim2.fromScale(0.34, 0.54), Size = UDim2.fromScale(0.63, 0.34), Text = "", Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(200, 214, 240), TextXAlignment = Enum.TextXAlignment.Left })
	local chip = Core.frame(bb, { Name = "Chip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, -0.06), Size = UDim2.fromScale(0.62, 0.5), BackgroundColor3 = GOLD, Visible = false, corner = UDim.new(0.5, 0) })
	local chipText = Core.text(chip, { Size = UDim2.fromScale(0.9, 0.72), Position = UDim2.fromScale(0.05, 0.14), Text = "", TextColor3 = Color3.fromRGB(20, 14, 6) })
	return { id = id, anchor = anchor, bb = bb, plate = plate, scale = scale, num = num, numText = numText, name = name, sub = sub, chip = chip, chipText = chipText, at = 0, stroke = plate:FindFirstChildOfClass("UIStroke") }
end

local function destroySign(id: string)
	local s = signs[id]
	if s then
		signs[id] = nil
		s.bb:Destroy()
		s.anchor:Destroy()
	end
end

local function chipFor(id: string): (string?, Color3?)
	local now = Core.now()
	local p = pings[id]
	if p and os.clock() < p.untilT then
		return p.text, Color3.fromRGB(255, 120, 200)
	end
	if bookingTable == id and now < bookingUntil then
		return L.Show.signBooking, Color3.fromRGB(110, 240, 225)
	end
	if djTable == id then
		return L.Show.signDj, Color3.fromRGB(255, 90, 170)
	end
	return nil, nil
end

local function refreshSign(s: any, e: any)
	local icon, label, price = itemText(e.item or e.set)
	local tier = S.orderTier(price)
	local T = S.tier(tier)
	s.num.BackgroundColor3 = T.color:Lerp(WHITE, 0.15)
	if s.stroke then
		s.stroke.Color = T.color
	end
	s.name.Text = string.format("%s님", tostring(e.name or "손님"))
	s.sub.Text = string.format("%s %s", icon, label)
	local text, col = chipFor(s.id)
	s.chip.Visible = text ~= nil
	if text then
		s.chipText.Text = text
		s.chip.BackgroundColor3 = col :: Color3
	end
	if type(e.at) == "number" and e.at ~= s.at then
		local fresh = s.at ~= 0 or Core.now() - e.at < 20
		s.at = e.at
		if fresh then
			-- the set landed (or a new order): pop + flash
			local delay = math.max(0, e.at - Core.now())
			task.delay(math.min(delay, 30), function()
				if s.bb.Parent then
					s.scale.Scale = 1.25
					Core.tween(s.scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
					if s.stroke then
						s.stroke.Transparency = 0
						s.stroke.Thickness = 4
						Core.tween(s.stroke, 1.2, { Transparency = 0.2, Thickness = 2 })
					end
					if tier >= 2 and Fx then
						Fx.burst(s.anchor.Position, T.color, 18)
					end
				end
			end)
		end
	end
end

local function syncSigns()
	if not S.Config.Show or not Core.q().signs then
		return
	end
	local tables = Core.state.Tables
	if type(tables) ~= "table" or not Core.inside then
		for id in signs do
			destroySign(id)
		end
		return
	end
	local now = Core.now()
	local seen: { [string]: boolean } = {}
	for id, e in tables do
		if type(id) == "string" and type(e) == "table" and type(e.owner) == "number" and (type(e.untilT) ~= "number" or e.untilT <= 0 or e.untilT > now) then
			local info = Core.tableInfo(id)
			if info and info.top then
				seen[id] = true
				local s = signs[id]
				if not s then
					s = buildSign(id, info)
					signs[id] = s
				end
				if s then
					refreshSign(s, e)
				end
			end
		end
	end
	for id in signs do
		if not seen[id] then
			destroySign(id)
		end
	end
end

-- a short chip on a table's sign (e.g. a 후원 sent to that table)
function Signs.ping(tableId: string?, text: string, seconds: number)
	if type(tableId) ~= "string" then
		return
	end
	pings[tableId] = { text = text, untilT = os.clock() + seconds }
	syncSigns()
	task.delay(seconds + 0.1, syncSigns)
end

-------------------------------------------------------------------------------------------------
-- presenter board over the lead bottle-staff
-------------------------------------------------------------------------------------------------
local presenter: any = nil
function Signs.presenter(rec: any, tier: number, price: number, icon: string, label: string)
	if presenter then
		presenter.dead = true
		if presenter.bb then
			presenter.bb:Destroy()
		end
		presenter = nil
	end
	if tier < 2 then
		return
	end
	local p: any = { dead = false }
	presenter = p
	local T = S.tier(tier)
	local endAt = (tonumber(rec.endAt) or (rec.at + 40))
	task.spawn(function()
		-- the club show spawns its staff a moment after rec.at: wait for the lead rig
		local head: BasePart? = nil
		local leadName = "ClubShowStaff1"
		while not p.dead and Core.now() < endAt do
			local rig = Core.showRig(leadName)
			local h = rig and rig:FindFirstChild("Head")
			if h and h:IsA("BasePart") then
				head = h
				break
			end
			task.wait(0.25)
		end
		if p.dead or not head then
			return
		end
		local bb = Core.billboard("GwClubPlusPresenter", head, UDim2.new(6.4, 0, 2.3, 0), Vector3.new(0, 2.9, 0), { MaxDistance = 80, LightInfluence = 0 })
		p.bb = bb
		local plate = Core.frame(bb, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.05, corner = UDim.new(0.16, 0), strokeColor = T.accent, strokeT = 0, gradient = Core.seq(T.color:Lerp(Color3.new(0, 0, 0), 0.55), T.color:Lerp(Color3.new(0, 0, 0), 0.2), T.color:Lerp(Color3.new(0, 0, 0), 0.55)) })
		Core.text(plate, { Position = UDim2.fromScale(0.05, 0.06), Size = UDim2.fromScale(0.9, 0.36), Text = string.format("%s %s", icon, label), stroke = Color3.fromRGB(20, 10, 30) })
		Core.text(plate, { Position = UDim2.fromScale(0.05, 0.43), Size = UDim2.fromScale(0.9, 0.25), Text = string.format(L.Show.presenterFor, tostring(rec.table or "?"), tostring(rec.name or "손님")), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(230, 236, 255) })
		Core.text(plate, { Position = UDim2.fromScale(0.05, 0.7), Size = UDim2.fromScale(0.9, 0.26), Text = "₩" .. S.commas(price), TextColor3 = GOLD, stroke = Color3.fromRGB(60, 30, 0) })
		local sc = Instance.new("UIScale")
		sc.Scale = 0.3
		sc.Parent = plate
		Core.tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		while not p.dead and Core.now() < endAt and head.Parent do
			task.wait(0.5)
		end
		if bb.Parent then
			Core.tween(sc, 0.3, { Scale = 0 })
			task.wait(0.32)
			bb:Destroy()
		end
		if presenter == p then
			presenter = nil
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- bartender flair
-------------------------------------------------------------------------------------------------
local flairBusy: { [Model]: boolean } = {}
local flairN = 0
local JUICE = { Color3.fromRGB(255, 120, 60), Color3.fromRGB(255, 70, 160), Color3.fromRGB(80, 230, 255), Color3.fromRGB(255, 210, 70) }

local function bottle(col: Color3): Model
	local m = Instance.new("Model")
	m.Name = "PlusFlairBottle"
	local body = Core.part("Body", Vector3.new(0.34, 0.95, 0.34), CFrame.new(), col, Enum.Material.Neon, m)
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(0.95, 0.34, 0.34) -- (cylinders run along X)
	local neck = Core.part("Neck", Vector3.new(0.4, 0.14, 0.14), CFrame.new(0.65, 0, 0), WHITE, Enum.Material.Glass, m)
	neck.Shape = Enum.PartType.Cylinder
	m.PrimaryPart = body
	m.Parent = Core.folder()
	return m
end

function Signs.flair(tableId: string?, tier: number)
	if not Core.inside or not Core.showRoom then
		return
	end
	local list = Core.npcs("bartender", "Main")
	if #list == 0 then
		return
	end
	local info = Core.tableInfo(tableId)
	local ref = if info and info.top then info.top else Core.roomBox().Position
	table.sort(list, function(a, b)
		return (a:GetPivot().Position - ref).Magnitude < (b:GetPivot().Position - ref).Magnitude
	end)
	local npc: Model? = nil
	for _, m in list do
		local head = m:FindFirstChild("Head")
		if not flairBusy[m] and head and head:IsA("BasePart") and head.LocalTransparencyModifier < 0.5 and head.Transparency < 0.5 then
			npc = m
			break
		end
	end
	if not npc then
		return
	end
	local r = Core.root()
	if r and (r.Position - npc:GetPivot().Position).Magnitude > 120 then
		return
	end
	flairBusy[npc] = true
	local head = npc:FindFirstChild("Head") :: BasePart
	local look = npc:GetPivot().LookVector
	local hand = head.Position + Vector3.new(0, -1.3, 0) + Vector3.new(look.X, 0, look.Z).Unit * 0.9
	local bottles = { bottle(JUICE[math.random(1, #JUICE)]) }
	if tier >= 4 then
		table.insert(bottles, bottle(GOLD))
	end
	local text = string.format(if tier >= 4 then L.Show.bartenderLegend else L.Show.bartender, tostring(tableId or ""))
	local bb = Core.billboard("GwClubPlusFlair", head, UDim2.new(0, 220, 0, 34), Vector3.new(0, 2.4, 0), { MaxDistance = 70, LightInfluence = 0 })
	local plate = Core.frame(bb, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GLASS, BackgroundTransparency = 0.15, corner = UDim.new(0.5, 0), strokeColor = if tier >= 4 then GOLD else Color3.fromRGB(61, 214, 245), strokeT = 0.1 })
	Core.text(plate, { Size = UDim2.fromScale(0.92, 0.7), Position = UDim2.fromScale(0.04, 0.15), Text = text, Font = Enum.Font.GothamBold })
	local t0 = os.clock()
	local throws = if tier >= 3 then 3 else 2
	local per = 0.75
	local caught = 0
	flairN += 1
	Core.job("flair" .. flairN, 30, function()
		local el = os.clock() - t0
		local done = el >= throws * per + 0.3
		for i, b in bottles do
			local off = (i - 1) * per * 0.5
			local u = ((el + off) % per) / per
			local k = math.floor((el + off) / per)
			local h = if k < throws then 3.4 * math.sin(math.pi * u) else 0
			local spin = (k + u) * math.pi * 2 * 1.5
			local side = if i == 2 then 0.7 else 0
			local rt = Vector3.new(-look.Z, 0, look.X)
			b:PivotTo(CFrame.new(hand + Vector3.new(0, h, 0) + rt * side) * CFrame.Angles(0, 0, math.pi / 2 + spin))
		end
		local nowCaught = math.min(throws, math.floor(el / per))
		if nowCaught > caught then
			caught = nowCaught
			if Fx and tier >= 2 then
				Fx.burst(hand + Vector3.new(0, 0.6, 0), if tier >= 4 then GOLD else JUICE[(caught % #JUICE) + 1], 10)
			end
		end
		if done then
			for _, b in bottles do
				b:Destroy()
			end
			task.delay(1.6, function()
				bb:Destroy()
				flairBusy[npc :: Model] = nil
			end)
			return false
		end
		return true
	end)
end

-------------------------------------------------------------------------------------------------
-- crowns over tonight's #1s
-------------------------------------------------------------------------------------------------
local crowns: { [string]: { bb: BillboardGui, uid: number, head: BasePart } } = {}

local function crownGui(kind: string, head: BasePart, offset: number): BillboardGui
	local spend = kind == "spend"
	local bb = Core.billboard("GwClubPlusCrown_" .. kind, head, UDim2.new(0, 170, 0, 40), Vector3.new(0, offset, 0), { MaxDistance = 90, LightInfluence = 0 })
	local plate = Core.frame(bb, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.05,
		corner = UDim.new(0.5, 0),
		strokeColor = if spend then GOLD else Color3.fromRGB(255, 120, 200),
		strokeT = 0,
		gradient = if spend then Core.seq(Color3.fromRGB(90, 60, 10), Color3.fromRGB(200, 150, 40), Color3.fromRGB(90, 60, 10)) else Core.seq(Color3.fromRGB(80, 20, 70), Color3.fromRGB(200, 60, 150), Color3.fromRGB(80, 20, 70)),
	})
	Core.text(plate, { Size = UDim2.fromScale(0.9, 0.72), Position = UDim2.fromScale(0.05, 0.14), Text = if spend then L.Show.crownSpend else L.Show.crownDonate, stroke = Color3.fromRGB(30, 15, 0) })
	local sc = Instance.new("UIScale")
	sc.Scale = 0.2
	sc.Parent = plate
	Core.tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	return bb
end

local function syncCrowns()
	local b = Core.state.Boards
	local kings = type(b) == "table" and type(b.kings) == "table" and b.kings or {}
	local ranking = type(b) == "table" and b.src == "ranking"
	local want: { [string]: number } = {}
	if Core.inside then
		if not ranking and type(kings.spend) == "number" and kings.spend > 0 then
			want.spend = kings.spend
		end
		if type(kings.donate) == "number" and kings.donate > 0 then
			want.donate = kings.donate
		end
	end
	for kind, c in crowns do
		local uid = want[kind]
		if not uid or uid ~= c.uid or not c.head.Parent or not c.bb.Parent then
			c.bb:Destroy()
			crowns[kind] = nil
		end
	end
	for kind, uid in want do
		if not crowns[kind] then
			local p = Players:GetPlayerByUserId(uid)
			local head = p and p.Character and p.Character:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				-- stacked above the 큰손 crown (ours or ClubRanking's) when the same player wears both
				local stacked = kind == "donate" and (kings.spend == uid or (ranking and type(kings.spend) == "number" and kings.spend == uid))
				local offset = if stacked then S.Config.Show.CrownStack else S.Config.Show.CrownOffset
				crowns[kind] = { bb = crownGui(kind, head, offset), uid = uid, head = head }
			end
		end
	end
end

function Signs.init(core: any, fx: any)
	Core = core
	S = core.S
	Fx = fx
	L = core.L
	Core.on("Tables", function()
		syncSigns()
	end)
	Core.on("Booking", function(bk: any)
		if type(bk) == "table" and type(bk.id) == "number" and bk.id > 0 and type(bk.table) == "string" then
			bookingTable = bk.table
			bookingUntil = tonumber(bk.endAt) or (Core.now() + 150)
		else
			bookingTable = nil
			bookingUntil = 0
		end
		syncSigns()
	end)
	Core.on("DJ", function(dj: any)
		djTable = nil
		if type(dj) == "table" and dj.on and type(dj.u) == "number" then
			local tables = Core.state.Tables
			if type(tables) == "table" then
				for id, e in tables do
					if type(e) == "table" and e.owner == dj.u then
						djTable = id
					end
				end
			end
		end
		syncSigns()
	end)
	Core.on("Boards", function()
		syncCrowns()
	end)
	local wasInside = false
	Core.job("signs", 1, function()
		if Core.inside ~= wasInside then
			wasInside = Core.inside
			syncSigns()
		end
		if Core.inside then
			syncSigns()
		end
		syncCrowns()
		return true
	end)
end

return Signs
