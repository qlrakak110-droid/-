-- GwangalliShopCrew/Augment: the place's OWN staff get a real conversation — ShopStaff counter rigs (편의점 점원,
-- 바리스타, 약사, 사장님 ...), the static GwShopClerk figures (주방 이모, 원장님, 약사님 ...) and venue staff
-- (PC방 · 노래방 · 볼링장 카운터 알바). Their models stay theirs: we add a 대화하기 prompt (our dialog replaces
-- ShopStaff's canned "말 걸기" line, whose prompt is switched off while ours is there and restored on cleanup)
-- and a CrewAugId attribute + GwCrewAug tag so clients can show bubbles over them.
-- Skipped: rigs of this add-on, GwangalliShopService waiters, 점장 모드 알바 (GwStaff), dealership staff
-- (GwDealerNpc = true), models with attribute CrewAugment = false.
--   Augment.init(Shared, Bridge, Net, mods)   mods = { Talk, Sites }   Augment.start()   Augment.cleanup()
--   Augment.target(id) -> Talk target?        Augment.count() -> n

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Augment = {}

local Shared: any = nil
local Config: any = nil
local Bridge: any = nil
local Net: any = nil
local Util: any = nil
local Talk: any = nil
local Personas: any = nil

local recs: { [Model]: any } = {}
local byId: { [string]: any } = {}
local serial = 0
local siteByModel: { [Model]: any } = {}
local AUG_TAG = "GwCrewAug"

function Augment.init(S: any, B: any, N: any, mods: any)
	Shared, Config, Bridge, Net, Util = S, S.Config, B, N, S.Util
	Talk = mods.Talk
	Personas = S.Personas
end

local function rootOf(m: Model): BasePart?
	local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	if r and r:IsA("BasePart") then
		return r
	end
	return m:FindFirstChildWhichIsA("BasePart")
end

local function skip(m: Instance): boolean
	if not m:IsA("Model") then
		return true
	end
	if CollectionService:HasTag(m, Shared.TAG) or m:GetAttribute(Shared.ATTR.Shop) ~= nil then
		return true -- ours
	end
	if m:GetAttribute("GwDealerNpc") == true or m:GetAttribute("CrewAugment") == false then
		return true
	end
	if m:GetAttribute("GwWaiter") ~= nil or m:GetAttribute("GwStaff") ~= nil then
		return true
	end
	if Players:GetPlayerFromCharacter(m) then
		return true
	end
	return false
end

-- what kind of counter this is
local VENUE_WORDS = {
	{ "PC", "pc" },
	{ "피씨", "pc" },
	{ "노래", "karaoke" },
	{ "코인", "karaoke" },
	{ "볼링", "game" },
	{ "당구", "game" },
	{ "게임", "game" },
	{ "오락", "game" },
	{ "아케이드", "game" },
	{ "호텔", "hotel" },
	{ "HOTEL", "hotel" },
	{ "Hotel", "hotel" },
	{ "대여", "rental" },
	{ "서프", "rental" },
	{ "은행", "office" },
	{ "병원", "office" },
	{ "의원", "office" },
	{ "헬스", "game" },
	{ "GYM", "game" },
}

local function venueKind(m: Model): string
	local a: Instance? = m
	local depth = 0
	while a and a ~= workspace and depth < 8 do
		local n = a.Name
		for _, w in VENUE_WORDS do
			if string.find(n, w[1], 1, true) then
				return w[2]
			end
		end
		a = a.Parent
		depth += 1
	end
	return "game"
end

local CLERK_KIND = { cook = "food", stylist = "salon", pharmacist = "pharmacy" }
local SHOPID_KIND = { clothing = "fashion", surf = "rental", pharmacy = "pharmacy", salon = "salon", gukbap = "food", chicken = "food", snack = "food" }
local MENU_OF = { cvs = "cvs", mart = "mart", cafe = "cafe", bakery = "bakery", pharmacy = "pharmacy", beauty = "beauty", pub = "pub", food = "food", game = "game", hotel = "hotel", rental = "rental" }

-- the ShopLife shop a position is inside (its record), or nil
local function shopAt(pos: Vector3): any?
	for _, rec in Bridge.shops() do
		if type(rec) == "table" and typeof(rec.frame) == "CFrame" and rec.sx and rec.sz then
			local fy = tonumber(rec.floorY) or rec.frame.Y
			local l = rec.frame:PointToObjectSpace(Vector3.new(pos.X, fy, pos.Z))
			if math.abs(l.X) <= rec.sx / 2 + 1.5 and math.abs(l.Z) <= rec.sz / 2 + 1.5 and pos.Y > fy - 3 and pos.Y < fy + 12 then
				return rec
			end
		end
	end
	return nil
end

local function venueSpot(pos: Vector3): any?
	local best, bd = nil, 26
	for _, p in CollectionService:GetTagged("VenueSpot") do
		if p:IsA("BasePart") then
			local d = (p.Position - pos).Magnitude
			if d < bd then
				local label = p:GetAttribute("Label")
				best, bd = { part = p, label = if type(label) == "string" and label ~= "" then label else "카운터" }, d
			end
		end
	end
	return best
end

local function hostShops(): boolean
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliRemotes")
	return remotes ~= nil and remotes:FindFirstChild("ShopRequest") ~= nil
end

local function add(m: Model, source: string)
	if recs[m] or skip(m) then
		return
	end
	local root = rootOf(m)
	if not root then
		return
	end
	serial += 1
	local id = "aug_" .. Util.hash6(m:GetFullName() .. "#" .. serial)
	local label = m:GetAttribute("ShopStaff") or m:GetAttribute("NpcName") or m:GetAttribute("DisplayName")
	local kind: string? = nil
	local venue: string? = nil
	if source == "venue" then
		venue = venueKind(m)
		kind = venue
		label = label or (if venue == "pc" then "PC방 알바" elseif venue == "karaoke" then "노래방 알바" elseif venue == "hotel" then "프런트 직원" else "직원")
	elseif source == "clerk" then
		local role = tostring(m:GetAttribute("Role") or "")
		kind = CLERK_KIND[role] or SHOPID_KIND[tostring(m:GetAttribute("ShopId") or "")] or "food"
		label = label or m.Name
	else
		local site = siteByModel[m]
		kind = site and site.kind or "shop"
		label = label or (site and site.label) or "점원"
	end
	label = tostring(label)
	local rec = shopAt(root.Position)
	if rec and rec.source == "gwshop" and hostShops() then
		rec = nil -- the map's own shop server runs it
	end
	local persona = Personas.forStaff(kind, label, id)
	local A: any = {
		id = id,
		model = m,
		root = root,
		persona = persona,
		kind = kind,
		label = label,
		source = source,
		venue = venue,
		menuKind = if rec then nil else (MENU_OF[kind or ""] or (if venue == "pc" then "pc" elseif venue == "karaoke" then "karaoke" else nil)),
		shopKey = rec and rec.key,
		shopName = if rec then tostring(rec.name) else tostring(m.Parent and m.Parent.Name or ""),
		shopType = rec and rec.type,
		flow = rec and rec.def and rec.def.flow,
		menuKey = rec and rec.menuKey,
		role = if source == "clerk" and m:GetAttribute("Role") == "cook" then "cook" else "cashier",
	}
	if venue then
		A.spot = venueSpot(root.Position)
	end
	-- prompts: ours on, theirs (canned 말 걸기) off while ours exists
	local theirs = root:FindFirstChild("StaffTalk")
	if theirs and theirs:IsA("ProximityPrompt") and Config.AUGMENT_REPLACE_TALK then
		A.theirs = theirs
		A.theirsEnabled = theirs.Enabled
		theirs.Enabled = false
	end
	local pr = Instance.new("ProximityPrompt")
	pr.Name = Shared.PROMPT
	pr.ActionText = "대화하기"
	pr.ObjectText = label
	pcall(function()
		pr.KeyboardKeyCode = (Enum.KeyCode :: any)[Config.TALK_KEY]
	end)
	pcall(function()
		pr.GamepadKeyCode = (Enum.KeyCode :: any)[Config.TALK_PAD]
	end)
	pr.HoldDuration = 0
	pr.MaxActivationDistance = Config.TALK_DIST
	pr.RequiresLineOfSight = false
	pcall(function()
		pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	end)
	pr.UIOffset = Vector2.new(0, 40)
	pr.Triggered:Connect(function(player)
		local T = Augment.target(id)
		if T then
			Talk.open(player, T)
		end
	end)
	pr.Parent = root
	A.prompt = pr
	m:SetAttribute("CrewAugId", id)
	CollectionService:AddTag(m, AUG_TAG)
	recs[m] = A
	byId[id] = A
	A.conn = m.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			Augment.drop(m)
		end
	end)
end

function Augment.drop(m: Model)
	local A = recs[m]
	if not A then
		return
	end
	recs[m] = nil
	byId[A.id] = nil
	if A.conn then
		A.conn:Disconnect()
	end
	Talk.closeFor(A.id)
	pcall(function()
		if A.prompt then
			A.prompt:Destroy()
		end
		if A.theirs and A.theirs.Parent then
			A.theirs.Enabled = A.theirsEnabled ~= false
		end
		if m.Parent then
			m:SetAttribute("CrewAugId", nil)
			CollectionService:RemoveTag(m, AUG_TAG)
		end
	end)
end

function Augment.target(id: string): any?
	local A = byId[id]
	if not A or not A.model.Parent or not A.root.Parent then
		return nil
	end
	return {
		id = A.id,
		kind = "staff",
		root = A.root,
		persona = A.persona,
		role = A.role,
		shopKey = A.shopKey,
		shopName = A.shopName,
		shopType = A.shopType,
		flow = A.flow,
		menuKey = A.menuKey,
		aug = A,
	}
end

local function refreshSites()
	table.clear(siteByModel)
	for _, s in Bridge.staffSites() do
		if s.model then
			siteByModel[s.model] = s
		end
	end
end

local function sweep()
	refreshSites()
	for _, m in CollectionService:GetTagged(Shared.STAFF_TAG) do
		if m:IsA("Model") and m:GetAttribute("ShopStaff") ~= nil then
			add(m, if CollectionService:HasTag(m, "GwShopClerk") then "clerk" else "shopstaff")
		end
	end
	for _, m in CollectionService:GetTagged("GwShopClerk") do
		if m:IsA("Model") then
			add(m, "clerk")
		end
	end
	for _, m in CollectionService:GetTagged("VenueStaff") do
		if m:IsA("Model") then
			add(m, "venue")
		end
	end
	-- a player working at that counter: our prompt steps aside (their job prompts stay alone)
	local workers = {}
	for _, p in Players:GetPlayers() do
		if Bridge.working(p) then
			local pos = Bridge.posOf(p)
			if pos then
				table.insert(workers, pos)
			end
		end
	end
	for _, A in recs do
		local busy = false
		for _, w in workers do
			if (w - A.root.Position).Magnitude < 12 then
				busy = true
				break
			end
		end
		if A.prompt then
			A.prompt.Enabled = not busy
		end
	end
end

function Augment.start()
	if not Config.AUGMENT_STAFF then
		return
	end
	for _, tag in { Shared.STAFF_TAG, "GwShopClerk", "VenueStaff" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(m)
			task.delay(0.5, function()
				if m.Parent and m:IsA("Model") then
					refreshSites()
					local src = if tag == "VenueStaff" then "venue" elseif tag == "GwShopClerk" or CollectionService:HasTag(m, "GwShopClerk") then "clerk" else "shopstaff"
					if src ~= "shopstaff" or m:GetAttribute("ShopStaff") ~= nil then
						add(m :: Model, src)
					end
				end
			end)
		end)
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(sweep)
			if not ok then
				Bridge.warnOnce("augment", "augment sweep: " .. tostring(err))
			end
			task.wait(3)
		end
	end)
end

function Augment.cleanup()
	local list = {}
	for m in recs do
		table.insert(list, m)
	end
	for _, m in list do
		Augment.drop(m)
	end
end

function Augment.count(): number
	local n = 0
	for _ in recs do
		n += 1
	end
	return n
end

return Augment
