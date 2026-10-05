-- GwangalliGameplay/Law/Crimes (server; owner: law): the crime careers.
--
-- PETTY CRIMES (anyone, LS.SMALL; faster money than 알바 but real risk — the money is cash, a part is
-- seized on the next arrest, failures are witnessed at once):
--   편의점 슬쩍하기  prompt inside every convenience store / mart Destination (hold); success = a few
--                   thousand 원; the clerk may notice (instant report) or the CCTV catches it later.
--   작은 상점 털기   (crime Lv.3) the same stores + food trucks / bakeries: a long hold, a bigger payout,
--                   always reported (2 stars).
--   소매치기        the street-life client offers it behind a pedestrian (GwangalliMindAPI "nearest");
--                   the archetype decides the odds and the purse (취객 easy, 부자 rich, 경찰 = caught).
--   자전거 훔치기    locked private bikes at the bike racks (hold 5 s, a fence pays at once).
--   차량 절도        driving away in a parked NPC car that is not yours (the GwangalliVehicles parked cars)
--                   marks it stolen (LawStolen = your UserId: player cops see it in 차량 조회) and is
--                   reported a bit later; 폐차장 (광안 공영주차장) buys a stolen car when nobody chases you.
--   불법 배달        a shady man in the back lane (more pay at night) hands over a package: deliver it in
--                   time; any officer who sees you up close may stop you (검문: 2 stars + 압수).
-- BIG CRIMES (LS.BIG, 조직 범죄): need LS.MAFIA_PASS_ID (0 = none in this build) or crime level
--   LS.ORG_LEVEL; long preparation steps (정찰, 장비, 도주 차량, 정보원 ...), a loud job and the escape to
--   the 아지트. Same payout and the same risk for everybody (the pass only opens the door).
-- Ops (Law.Action): crime {act = "pickpocket" {id, arch, pos} | "bigList" | "bigStart" {id} | "bigQuit" |
--   "bigState" | "contraband" | "chop"}; the store / bike / big-crime props use ProximityPrompts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")

local Crimes = {}

local Law: any
local ctx: any
local LS: any
local G: any
local Looks: any = nil
local Transit: any = nil

local rng = Random.new()
local folder: Folder
local cool: { [Player]: { [string]: number } } = {}
local carry: { [Player]: any } = {} -- contraband / crates in hand
local stolen: { [Model]: any } = {} -- car -> { by, home (CFrame), t }
local bigLive: { [Player]: any } = {} -- the running organised job
local passCache: { [number]: boolean } = {}

local function now(): number
	return os.clock()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function randPay(r: { number }): number
	return math.floor((r[1] + rng:NextNumber() * (r[2] - r[1])) / 100 + 0.5) * 100
end

local function level(player: Player): number
	return (LS.crimeLevel(Law.data(player).crimeXp))
end

local function coolLeft(player: Player, key: string): number
	local c = cool[player]
	return if c and c[key] then math.max(0, c[key] - now()) else 0
end

local function setCool(player: Player, key: string, seconds: number)
	cool[player] = cool[player] or {}
	cool[player][key] = now() + seconds
end

local function blocked(player: Player): string?
	local s = Law.sess(player)
	if not s then
		return "잠시 후 다시"
	end
	if s.jail or s.cuffed then
		return "구금 중이에요"
	end
	if player:GetAttribute(LS.Attr.Cop) == true then
		return "근무 중인 경찰관은 범죄를 저지를 수 없어요"
	end
	return nil
end

-- officers / cops who would notice right now (shrinks the odds)
local function watched(pos: Vector3, radius: number): number
	local n = 0
	local P = Law.children.Police
	if P then
		for _, o in P.officers() do
			if not o.gone and flat(o.pos, pos) < radius and P.losClear(o.pos + Vector3.new(0, 4.6, 0), pos + Vector3.new(0, 2, 0)) then
				n += 1
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if p:GetAttribute(LS.Attr.Cop) == true then
			local cp = Law.posOf(p)
			if cp and flat(cp, pos) < radius then
				n += 1
			end
		end
	end
	return n
end

local function toast(player: Player, text: string, tone: string?)
	Law.push(player, { kind = "toast", text = text, tone = tone })
end

-------------------------------------------------------------------------------------------------
-- Props
-------------------------------------------------------------------------------------------------
local function anchorPart(name: string, cf: CFrame, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(2, 2, 2)
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Parent = folder
	return p
end

local function prompt(parent: Instance, action: string, object: string, hold: number, key: Enum.KeyCode?): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = hold
	pr.MaxActivationDistance = 8
	pr.RequiresLineOfSight = false
	pr.KeyboardKeyCode = key or Enum.KeyCode.G
	pr.Style = Enum.ProximityPromptStyle.Default
	pr:SetAttribute("LawCrime", true) -- the client may hide these for cops on duty
	pr.Parent = parent
	return pr
end

local function npcRig(id: string, cf: CFrame, hint: any, act: string): any?
	if not Looks then
		return nil
	end
	local ok, rig = pcall(function()
		return Looks.build(Looks.random(id, hint), { name = "Law_" .. id, anchored = true, shadow = false })
	end)
	if not ok or type(rig) ~= "table" or not rig.model then
		return nil
	end
	local g = rig.ground or 3
	local p = cf.Position
	local _, yaw = cf:ToOrientation()
	rig.model:SetAttribute("NpcId", id)
	rig.model:SetAttribute("NpcKind", "law")
	rig.model:SetAttribute("NpcGround", g)
	rig.model:SetAttribute("NpcAct", act)
	rig.model:SetAttribute("NpcYaw", math.deg(yaw))
	rig.model:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", p.X, p.Y, p.Z, p.X, p.Y, p.Z, workspace:GetServerTimeNow()))
	rig.root.CFrame = cf + Vector3.new(0, g, 0)
	rig.model.Parent = workspace:FindFirstChild("GwangalliNPCs") or workspace
	return { model = rig.model, root = rig.root, id = id }
end

local function say(npc: any, text: string)
	local P = Law.children.Police
	if P and npc then
		P.say(npc, text, 3.5)
	end
end

-------------------------------------------------------------------------------------------------
-- Spots from the map's Destinations
-------------------------------------------------------------------------------------------------
local SHOP_WORDS = { "GS25", "편의점", "CU ", "세븐", "홈플러스", "마트" }
local SMALL_WORDS = { "푸드트럭", "빵", "밀락더마켓", "기념품" }

local function destName(inst: Instance): string
	local n = inst:GetAttribute("DisplayName")
	return if type(n) == "string" and n ~= "" then n else inst.Name
end

local function hasWord(name: string, words: { string }): boolean
	for _, w in words do
		if string.find(name, w, 1, true) then
			return true
		end
	end
	return false
end

local shops: { any } = {}

local function stealFrom(player: Player, shop: any)
	local why = blocked(player)
	if why then
		toast(player, why, "warn")
		return
	end
	local def = LS.SMALL.shoplift
	local left = coolLeft(player, "shoplift")
	if left > 0 then
		toast(player, "점원이 의심하고 있어요… " .. math.ceil(left) .. "초 뒤에", "warn")
		return
	end
	setCool(player, "shoplift", def.cool)
	local pos = shop.part.Position
	local chance = def.base + (if Law.isNight() then 0.06 else 0) - 0.35 * watched(pos, 35)
	Law.stat(player, "shoplift")
	if rng:NextNumber() < chance then
		local money = randPay(def.pay)
		Law.earnCrime(player, money, "🧃 " .. shop.name .. " (몰래)", def.xp)
		toast(player, "🧃 몰래 챙겼다… +" .. LS.won(money), "crime")
		-- the CCTV: a report some time later
		if rng:NextNumber() < 0.22 then
			Law.crime(player, "shoplift", { pos = pos, silent = true })
		end
		Law.push(player, { kind = "crimeDone", id = "shoplift", ok = true, money = money })
	else
		toast(player, "😱 점원: \"저기요! 계산 안 하셨죠?!\"", "warn")
		Law.crime(player, "shoplift", { pos = pos, seen = watched(pos, 35) > 0 })
		Law.report(player, "clerk", pos)
		Law.push(player, { kind = "crimeDone", id = "shoplift", ok = false })
	end
end

local function robShop(player: Player, shop: any)
	local why = blocked(player)
	if why then
		toast(player, why, "warn")
		return
	end
	local def = LS.SMALL.robbery
	if level(player) < def.level then
		toast(player, "범죄 등급 Lv." .. def.level .. "부터 할 수 있어요", "warn")
		return
	end
	local left = coolLeft(player, "robbery:" .. shop.name)
	if left > 0 then
		toast(player, "이 가게는 경계 중이에요 (" .. math.ceil(left) .. "초)", "warn")
		return
	end
	setCool(player, "robbery:" .. shop.name, def.cool)
	local pos = shop.part.Position
	Law.stat(player, "robbery")
	if watched(pos, 40) > 0 and rng:NextNumber() < 0.6 then
		toast(player, "🚨 경찰이 보고 있었어요!", "warn")
		Law.crime(player, "robbery", { pos = pos, seen = true })
		return
	end
	local money = randPay(def.pay)
	Law.earnCrime(player, money, "💰 " .. shop.name .. " (강도)", def.xp)
	toast(player, "💰 금고를 털었다! +" .. LS.won(money) .. " · 곧 신고가 들어가요", "crime")
	Law.crime(player, "robbery", { pos = pos })
	Law.push(player, { kind = "crimeDone", id = "robbery", ok = true, money = money })
end

local function buildShops()
	local tag = (G and G.Tags and G.Tags.Destination) or "Destination"
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then
			local name = destName(inst)
			local isShop = hasWord(name, SHOP_WORDS)
			local isSmall = isShop or hasWord(name, SMALL_WORDS)
			if isSmall then
				local cf = inst.CFrame * CFrame.new(0, 0, -3)
				local a = anchorPart("LawShop_" .. name, cf)
				local shop = { name = name, part = a }
				if isShop then
					local pr = prompt(a, "슬쩍하기 (절도)", name, LS.SMALL.shoplift.hold)
					pr.Triggered:Connect(function(p)
						stealFrom(p, shop)
					end)
				end
				local pr2 = prompt(a, "가게 털기 (강도)", name, LS.SMALL.robbery.hold, Enum.KeyCode.H)
				pr2.UIOffset = Vector2.new(0, 60)
				pr2.Triggered:Connect(function(p)
					robShop(p, shop)
				end)
				table.insert(shops, shop)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Bikes (locked private bikes at the racks)
-------------------------------------------------------------------------------------------------
local bikes: { any } = {}

local function placeBike(b: any)
	if b.model then
		b.model:Destroy()
		b.model = nil
	end
	if not Transit then
		return
	end
	local ok, built = pcall(Transit.buildBike, "bike", "full")
	if not ok or type(built) ~= "table" or not built.model then
		return
	end
	local m = built.model
	m.Name = "LawPrivateBike"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	m:PivotTo(b.cf)
	-- a chunky lock on the frame
	local lock = Instance.new("Part")
	lock.Name = "BikeLock"
	lock.Size = Vector3.new(0.5, 0.5, 0.25)
	lock.Color = Color3.fromRGB(230, 180, 40)
	lock.Material = Enum.Material.Metal
	lock.Anchored = true
	lock.CanCollide = false
	lock.CFrame = b.cf * CFrame.new(0, 1.2, 0)
	lock.Parent = m
	m.Parent = folder
	b.model = m
	local pr = prompt(lock, "자물쇠 따기 (자전거 절도)", "개인 자전거", LS.SMALL.bike_theft.hold)
	pr.Triggered:Connect(function(p)
		Crimes.stealBike(p, b)
	end)
end

function Crimes.stealBike(player: Player, b: any)
	local why = blocked(player)
	if why then
		toast(player, why, "warn")
		return
	end
	local def = LS.SMALL.bike_theft
	if level(player) < def.level then
		toast(player, "범죄 등급 Lv." .. def.level .. "부터 (지금은 소매치기·슬쩍하기로 경험을 쌓아요)", "warn")
		return
	end
	if not b.model then
		return
	end
	local pos = b.cf.Position
	Law.stat(player, "bike_theft")
	if rng:NextNumber() < def.base - 0.3 * watched(pos, 40) then
		local money = randPay(def.pay)
		b.model:Destroy()
		b.model = nil
		task.delay(300, function()
			placeBike(b)
		end)
		Law.earnCrime(player, money, "🚲 자전거 장물", def.xp)
		toast(player, "🚲 자물쇠를 땄다! 장물아비에게 넘김 +" .. LS.won(money), "crime")
		Law.crime(player, "bike_theft", { pos = pos, silent = true })
	else
		toast(player, "🔒 자물쇠가 안 풀려요… 누가 쳐다봐요!", "warn")
		Law.crime(player, "bike_theft", { pos = pos })
	end
end

local function buildBikes()
	if not Transit or not Transit.RACKS then
		return
	end
	for _, r in Transit.RACKS do
		local base = Transit.rackFrame(r)
		for k = 1, 2 do
			local cf = base * CFrame.new((k == 1 and -1 or 1) * (r.slots * 1.0 + 3), 0, 1.2) * CFrame.Angles(0, math.rad(90), 0)
			local b = { cf = cf, rack = r.name }
			table.insert(bikes, b)
			placeBike(b)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Car theft (parked NPC cars) + 폐차장
-------------------------------------------------------------------------------------------------
local function seatedCar(player: Player): Model?
	local ch = player.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	local seat = h and h.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local m: Instance? = seat
	while m and m ~= workspace do
		if m:IsA("Model") and m:GetAttribute("VehicleKind") ~= nil then
			return m :: Model
		end
		m = m.Parent
	end
	return nil
end

local function carTheftTick()
	for _, p in Players:GetPlayers() do
		local car = seatedCar(p)
		if car and not stolen[car] then
			local owned = car:GetAttribute("DriveOwnedCar") == true or car:GetAttribute("DriveJobKind") ~= nil
			local mine = car:GetAttribute("DriveOwner") == p.UserId
			if not owned and not mine and car:GetAttribute("DriveUnlocked") == true and p:GetAttribute(LS.Attr.Cop) ~= true then
				local okP, home = pcall(function()
					return car:GetPivot()
				end)
				stolen[car] = { by = p, home = if okP then home else nil, t = now() }
				car:SetAttribute("LawStolen", p.UserId)
				local def = LS.SMALL.car_theft
				Law.addCrimeXp(p, def.xp)
				Law.stat(p, "car_theft")
				toast(p, "🚗 남의 차를 몰고 있어요… 주인이 곧 신고할 거예요", "crime")
				Law.crime(p, "car_theft", { pos = Law.posOf(p), silent = true })
				-- the organised job step "steal a car"
				local job = bigLive[p]
				if job then
					Crimes.bigEvent(p, "steal_car", car)
				end
			end
		end
	end
	-- stolen cars left alone for long go back to their spot
	for car, st in stolen do
		if not car.Parent then
			stolen[car] = nil
		elseif now() - st.t > 420 and car:GetAttribute("DriveDriver") == 0 then
			stolen[car] = nil
			car:SetAttribute("LawStolen", nil)
			if st.home then
				pcall(function()
					local api = ServerStorage:FindFirstChild("GwangalliVehiclesAPI")
					if api then
						(api :: BindableFunction):Invoke("park", car)
					end
					car:PivotTo(st.home)
				end)
			end
		end
	end
end

local chopPos: Vector3? = nil

local function chop(player: Player): any
	local why = blocked(player)
	if why then
		return { ok = false, text = why }
	end
	local car = seatedCar(player)
	local st = car and stolen[car]
	if not car or not st or st.by ~= player then
		return { ok = false, text = "훔친 차를 타고 와야 해요" }
	end
	local pp = Law.posOf(player)
	if not chopPos or not pp or flat(pp, chopPos) > 40 then
		return { ok = false, text = "폐차장(광안 공영주차장)에서만 넘길 수 있어요" }
	end
	if player:GetAttribute(LS.Attr.Chase) == true then
		return { ok = false, text = "😬 경찰이 따라붙어 있어서 안 받아준대요" }
	end
	local def = LS.SMALL.chop
	local money = randPay(def.pay)
	pcall(function()
		local api = ServerStorage:FindFirstChild("GwangalliVehiclesAPI")
		if api then
			(api :: BindableFunction):Invoke("eject", car)
			;(api :: BindableFunction):Invoke("park", car)
		end
	end)
	stolen[car] = nil
	car:SetAttribute("LawStolen", nil)
	if st.home then
		pcall(function()
			car:PivotTo(st.home)
		end)
	end
	Law.earnCrime(player, money, "🔧 폐차장 (장물 차량)", def.xp)
	return { ok = true, money = money, text = "🔧 차를 넘겼어요 +" .. LS.won(money) }
end

-------------------------------------------------------------------------------------------------
-- 소매치기 (pedestrians live on the client; plausibility checked here)
-------------------------------------------------------------------------------------------------
local PICK = {
	drunk = { odds = 0.85, purse = { 4000, 16000 }, line = "어…? 내 지갑…? 히끅" },
	tourist = { odds = 0.72, purse = { 6000, 22000 }, line = "Excuse me?! 내 지갑!" },
	elder = { odds = 0.7, purse = { 2000, 9000 }, line = "아이고, 저놈 잡아라!" },
	rich = { odds = 0.5, purse = { 15000, 45000 }, line = "어머, 내 명품 지갑!" },
	student = { odds = 0.62, purse = { 1000, 6000 }, line = "야! 내 용돈!" },
	office = { odds = 0.58, purse = { 5000, 18000 }, line = "어? 지갑 어디 갔지?!" },
	thug = { odds = 0.32, purse = { 6000, 20000 }, line = "이 새끼가?! 너 죽었어!" },
	punk = { odds = 0.42, purse = { 2000, 9000 }, line = "야, 너 방금 뭐 했어?" },
	police = { odds = 0, purse = { 0, 0 }, line = "지금 경찰 지갑을 털어요?!" },
	homeless = { odds = 0.9, purse = { 300, 1500 }, line = "…그거 내 전 재산인데…" },
	fool = { odds = 0.8, purse = { 500, 3000 }, line = "히히 간지러워~ 어? 내 사탕 돈!" },
	clerk = { odds = 0.6, purse = { 3000, 9000 }, line = "아 진짜! 퇴근하는데!" },
	citizen = { odds = 0.62, purse = { 3000, 14000 }, line = "도둑이야!" },
}

local Citizens: any = nil
local MindShared: any = nil
local ANON_OK = { citizen = true, tourist = true, student = true, office = true, drunk = true, elder = true }

local function pickpocket(player: Player, p: any): any
	local why = blocked(player)
	if why then
		return { ok = false, text = why }
	end
	local def = LS.SMALL.pickpocket
	local left = coolLeft(player, "pickpocket")
	if left > 0 then
		return { ok = false, text = "너무 티 나요… " .. math.ceil(left) .. "초 뒤에" }
	end
	local id = type(p.id) == "string" and string.sub(p.id, 1, 40) or ""
	local pos = p.pos
	local pp = Law.posOf(player)
	if type(pos) ~= "table" or not pp then
		return { ok = false }
	end
	local vp = Vector3.new(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
	if flat(vp, pp) > 6 then
		return { ok = false, text = "너무 멀어요" }
	end
	setCool(player, "pickpocket", def.cool)
	-- the archetype: from the roster for a named citizen (never trusted from the client); an anonymous
	-- passer-by may only be one of the plain kinds
	local c = Citizens and Citizens.byId and Citizens.byId[id]
	local arch = "citizen"
	if c then
		local okA, a = pcall(function()
			return MindShared and MindShared.archOf(c) or nil
		end)
		arch = if okA and type(a) == "string" and PICK[a] then a elseif c.type == "police" then "police" else "citizen"
	elseif type(p.arch) == "string" and ANON_OK[p.arch] then
		arch = p.arch
	end
	local t = PICK[arch]
	Law.stat(player, "pickpocket")
	local chance = t.odds - 0.3 * watched(vp, 30) + (if Law.isNight() then 0.05 else 0)
	if arch == "police" then
		Law.crime(player, "pickpocket", { pos = vp, police = true })
		return { ok = true, success = false, line = t.line, arch = arch }
	end
	if rng:NextNumber() < chance then
		local money = randPay(t.purse)
		Law.earnCrime(player, money, "👛 소매치기", def.xp)
		-- noticed afterwards sometimes
		if rng:NextNumber() < 0.3 then
			Law.crime(player, "pickpocket", { pos = vp, silent = true, victim = id })
		end
		return { ok = true, success = true, money = money, arch = arch, text = "👛 +" .. LS.won(money) }
	end
	Law.crime(player, "pickpocket", { pos = vp, victim = id })
	Law.report(player, "victim", vp)
	-- the victim remembers (the Mind relationship gets angry / scared)
	if ctx.mind and type(ctx.mind.note) == "function" and c then
		pcall(ctx.mind.note, player, id, "bump", "fight")
	end
	return { ok = true, success = false, line = t.line, arch = arch }
end

-------------------------------------------------------------------------------------------------
-- 불법 배달 (contraband)
-------------------------------------------------------------------------------------------------
local fixer: any = nil
local destList: { { name: string, pos: Vector3 } } = {}

local function collectDests()
	local tag = (G and G.Tags and G.Tags.Destination) or "Destination"
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then
			table.insert(destList, { name = destName(inst), pos = inst.Position })
		end
	end
end

local function boxOn(player: Player, color: Color3): Part?
	local ch = player.Character
	local hand = ch and (ch:FindFirstChild("LeftHand") or ch:FindFirstChild("Left Arm"))
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end
	local b = Instance.new("Part")
	b.Name = "LawPackage"
	b.Size = Vector3.new(1.4, 1, 1.1)
	b.Color = color
	b.Material = Enum.Material.Cardboard
	b.CanCollide, b.CanQuery, b.CanTouch, b.Massless = false, false, false, true
	b.CFrame = hand.CFrame * CFrame.new(0, -0.6, -0.4)
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = b
	w.Parent = b
	b.Parent = ch
	return b
end

local function dropCarry(player: Player)
	local c = carry[player]
	carry[player] = nil
	if c and c.box then
		c.box:Destroy()
	end
end

local function contraband(player: Player): any
	local why = blocked(player)
	if why then
		return { ok = false, text = why }
	end
	local def = LS.SMALL.contraband
	if level(player) < def.level then
		return { ok = false, text = "\"넌 아직 못 믿겠다. 좀 더 굴러보고 와.\" (범죄 Lv." .. def.level .. ")" }
	end
	if carry[player] then
		return { ok = false, text = "이미 물건을 들고 있어요" }
	end
	local left = coolLeft(player, "contraband")
	if left > 0 then
		return { ok = false, text = "\"아직 물건 없어. " .. math.ceil(left) .. "초 뒤에 와.\"" }
	end
	local pp = Law.posOf(player)
	if not pp or not fixer or flat(pp, fixer.root.Position) > 12 then
		return { ok = false, text = "골목의 수상한 남자에게 가야 해요" }
	end
	local options = {}
	for _, d in destList do
		local dist = flat(d.pos, pp)
		if dist > 250 and dist < 900 then
			table.insert(options, d)
		end
	end
	if #options == 0 then
		return { ok = false }
	end
	setCool(player, "contraband", def.cool)
	local dst = options[rng:NextInteger(1, #options)]
	local dist = flat(dst.pos, pp)
	local limit = math.floor(70 + dist / 9)
	local night = Law.isNight()
	carry[player] = { kind = "contraband", dest = dst, deadline = now() + limit, pay = math.floor(randPay(def.pay) * (if night then 1.25 else 1) * (0.8 + dist / 1800)), box = boxOn(player, Color3.fromRGB(70, 60, 50)), checked = false }
	say(fixer, LS.pick({ "조용히 갖다 놔. 열어보면 죽는다.", "경찰 보이면 돌아가. 알지?", "늦으면 돈 없어." }))
	Law.push(player, { kind = "mission", id = "contraband", text = "📦 " .. dst.name .. "에 " .. limit .. "초 안에 배달", pos = { dst.pos.X, dst.pos.Y, dst.pos.Z }, deadline = limit })
	return { ok = true, dest = dst.name, limit = limit }
end

local function carryTick()
	for player, c in carry do
		local pp = Law.posOf(player)
		if not player.Parent or not pp then
			carry[player] = nil
		elseif c.kind == "contraband" then
			if now() > c.deadline then
				dropCarry(player)
				toast(player, "⌛ 시간 초과… 물건은 회수당했어요", "warn")
				Law.push(player, { kind = "mission", id = "contraband", done = true })
			elseif flat(pp, c.dest.pos) < 14 then
				local money = c.pay
				dropCarry(player)
				Law.earnCrime(player, money, "📦 불법 배달", LS.SMALL.contraband.xp)
				toast(player, "📦 배달 완료 +" .. LS.won(money), "crime")
				Law.push(player, { kind = "mission", id = "contraband", done = true })
				Law.stat(player, "contraband")
			elseif not c.checked and watched(pp, 22) > 0 then
				-- 검문: a close officer may want a look at the box
				c.checked = true
				if rng:NextNumber() < 0.45 then
					dropCarry(player)
					toast(player, "👮 \"그 상자 뭐예요?\" — 들켰다!", "warn")
					Law.crime(player, "contraband", { pos = pp, seen = true })
					Law.push(player, { kind = "mission", id = "contraband", done = true })
				else
					toast(player, "😮‍💨 경찰이 그냥 지나갔어요…", "crime")
				end
			end
		elseif c.kind == "crate" then
			local job = bigLive[player]
			if job and c.to and flat(pp, c.to) < 10 then
				dropCarry(player)
				Crimes.bigEvent(player, "crate")
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Organised crime (LS.BIG)
-------------------------------------------------------------------------------------------------
local hideout: any = nil
local hideoutPos: Vector3? = nil
local bankPos: Vector3? = nil
local portPos: Vector3? = nil

local function hasMafiaPass(player: Player): boolean
	if LS.MAFIA_PASS_ID == 0 then
		return false
	end
	local c = passCache[player.UserId]
	if c ~= nil then
		return c
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, LS.MAFIA_PASS_ID)
	end)
	passCache[player.UserId] = ok and owns == true
	return passCache[player.UserId]
end

local function bigOpen(player: Player, id: string): (boolean, string?)
	local b = LS.BIG[id]
	if not b then
		return false, "없는 임무"
	end
	local lvl = level(player)
	if not hasMafiaPass(player) and lvl < b.level then
		return false, "범죄 등급 Lv." .. b.level .. " 또는 조직 직업 필요 (지금 Lv." .. lvl .. ")"
	end
	local L = Law.data(player)
	local t = L.bigCool[id]
	if t and os.time() < t then
		return false, "재정비 중 (" .. LS.fmtTime(t - os.time()) .. ")"
	end
	if b.night and not Law.isNight() then
		return false, "밤에만 접선할 수 있어요"
	end
	return true, nil
end

function Crimes.bigView(player: Player): any?
	local job = bigLive[player]
	if not job then
		return nil
	end
	local b = LS.BIG[job.id]
	local step = b.steps[job.step]
	return { id = job.id, label = b.label, icon = b.icon, step = job.step, steps = #b.steps, stepLabel = step and step.label or "", n = job.n, need = step and step.n or nil, pos = job.markPos and { job.markPos.X, job.markPos.Y, job.markPos.Z } or nil, timer = job.timerEnd and math.max(0, job.timerEnd - now()) or nil }
end

local function bigPush(player: Player, text: string?)
	Law.push(player, { kind = "big", state = Crimes.bigView(player), text = text })
end

local function bigMark(job: any, pos: Vector3?)
	job.markPos = pos
end

local function ringAround(center: Vector3, r: number): Vector3
	local a = rng:NextNumber() * math.pi * 2
	return center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function bigFail(player: Player, why: string)
	local job = bigLive[player]
	if not job then
		return
	end
	bigLive[player] = nil
	dropCarry(player)
	if job.prop then
		job.prop:Destroy()
	end
	local L = Law.data(player)
	L.bigCool[job.id] = os.time() + math.floor(LS.BIG[job.id].cool * 0.5)
	L.orgTrust = math.max(0, L.orgTrust - 5)
	Law.dirty(player)
	Law.notify(player, "warn", "🕶️ 임무 실패", why)
	bigPush(player, "실패: " .. why)
end

local function bigNextStep(player: Player)
	local job = bigLive[player]
	if not job then
		return
	end
	local b = LS.BIG[job.id]
	job.step += 1
	job.n = 0
	job.timerEnd = nil
	local step = b.steps[job.step]
	if not step then
		-- done: payout
		bigLive[player] = nil
		local money = randPay(b.reward)
		Law.earnCrime(player, money, b.icon .. " " .. b.label, b.xp)
		local L = Law.data(player)
		L.bigCool[job.id] = os.time() + b.cool
		L.orgTrust = math.min(100, L.orgTrust + 10)
		Law.dirty(player)
		Law.stat(player, "big_" .. job.id)
		Law.notify(player, "money", "🕶️ " .. b.label .. " 성공", "+" .. LS.won(money) .. " · 조직 신뢰 +10")
		bigPush(player, "성공! +" .. LS.won(money))
		return
	end
	-- set up the step
	local pp = Law.posOf(player) or Vector3.zero
	if step.kind == "visit" then
		local center = if job.id == "smuggle" then (portPos or pp) else (bankPos or pp)
		job.points = {}
		for i = 1, step.n do
			job.points[i] = ringAround(center, if step.n == 1 then 6 else 20 + i * 8)
		end
		bigMark(job, job.points[1])
	elseif step.kind == "buy" then
		bigMark(job, hideoutPos)
	elseif step.kind == "steal_car" then
		bigMark(job, nil)
	elseif step.kind == "drill" then
		bigMark(job, bankPos)
	elseif step.kind == "escape" then
		bigMark(job, hideoutPos)
		job.timerEnd = now() + 300
	elseif step.kind == "talk" then
		-- the informant waits a short walk away
		local at = ringAround(hideoutPos or pp, 60)
		local P = Law.children.Police
		if P then
			local q = P.ringNode(at, 0, 30, nil)
			at = q or at
		end
		local npc = npcRig("informant_" .. player.UserId, CFrame.new(at), { style = "street", body = "m", age = "adult" }, "phone")
		job.prop = npc and npc.model or nil
		job.npc = npc
		bigMark(job, at)
	elseif step.kind == "steal_marked" then
		-- a marked target: a crate / the car near the far side of town
		local at = ringAround(pp, 260 + rng:NextNumber() * 200)
		local P = Law.children.Police
		if P then
			at = P.ringNode(at, 0, 40, nil) or at
		end
		local box = anchorPart("LawBigTarget", CFrame.new(at + Vector3.new(0, 1, 0)), Vector3.new(2.4, 2, 2.4))
		box.Transparency = 0
		box.Color = if job.id == "turf" then Color3.fromRGB(30, 30, 34) else Color3.fromRGB(200, 170, 60)
		box.Material = Enum.Material.Metal
		box.CanCollide = true
		local pr = prompt(box, if job.id == "turf" then "빼앗기" else "경보 해제 · 탈취", LS.BIG[job.id].label, 4.5)
		pr.Triggered:Connect(function(p)
			if p == player and bigLive[player] == job then
				box:Destroy()
				Law.crime(player, LS.BIG[job.id].crime, { pos = at })
				bigNextStep(player)
			end
		end)
		job.prop = box
		bigMark(job, at)
	elseif step.kind == "carry" then
		job.cratesFrom = portPos or pp
		job.cratesTo = (portPos or pp) + Vector3.new(18, 0, 6)
		bigMark(job, job.cratesFrom)
	end
	bigPush(player, step.label)
end

function Crimes.bigEvent(player: Player, ev: string, arg: any?)
	local job = bigLive[player]
	if not job then
		return
	end
	local b = LS.BIG[job.id]
	local step = b.steps[job.step]
	if not step then
		return
	end
	if ev == "steal_car" and step.kind == "steal_car" then
		bigNextStep(player)
	elseif ev == "crate" and step.kind == "carry" then
		job.n += 1
		if job.n >= step.n then
			Law.crime(player, b.crime, { pos = Law.posOf(player) })
			bigNextStep(player)
		else
			bigMark(job, job.cratesFrom)
			bigPush(player, "상자 " .. job.n .. "/" .. step.n)
		end
	end
	local _ = arg
end

local function bigTick()
	for player, job in bigLive do
		local pp = Law.posOf(player)
		local b = LS.BIG[job.id]
		local step = b.steps[job.step]
		local s = Law.sess(player)
		if not player.Parent then
			bigLive[player] = nil
		elseif s and (s.jail or s.cuffed) then
			bigFail(player, "체포됐어요")
		elseif pp and step then
			if step.kind == "visit" and job.points then
				local target = job.points[job.n + 1]
				if target and flat(pp, target) < 12 then
					job.n += 1
					if job.n >= step.n then
						bigNextStep(player)
					else
						bigMark(job, job.points[job.n + 1])
						bigPush(player, "정찰 " .. job.n .. "/" .. step.n)
					end
				end
			elseif step.kind == "talk" and job.npc and flat(pp, job.npc.root.Position) < 8 then
				say(job.npc, LS.pick({ "쉿. 목표는 저쪽이야. 경보는 4초면 꺼져.", "조심해. 요즘 순찰 빡세다.", "돈은 행동대장한테 받아. 난 모른다." }))
				if job.prop then
					local m = job.prop
					task.delay(4, function()
						m:Destroy()
					end)
					job.prop = nil
				end
				bigNextStep(player)
			elseif step.kind == "drill" and bankPos then
				local d = flat(pp, bankPos)
				if not job.timerEnd then
					if d < 10 then
						job.timerEnd = now() + step.seconds
						job.alarmAt = now() + 8
						bigPush(player, "🔩 드릴 작동! " .. step.seconds .. "초 동안 금고 근처에 있어요")
					end
				else
					if d > 16 then
						bigFail(player, "드릴 자리를 떠났어요")
					elseif job.alarmAt and now() >= job.alarmAt then
						job.alarmAt = nil
						Law.crime(player, b.crime, { pos = bankPos, seen = true })
						bigPush(player, "🚨 경보가 울렸어요! 조금만 버텨요")
					elseif now() >= job.timerEnd then
						bigNextStep(player)
					end
				end
			elseif step.kind == "escape" and hideoutPos then
				if job.timerEnd and now() > job.timerEnd then
					bigFail(player, "제시간에 아지트로 못 갔어요")
				elseif flat(pp, hideoutPos) < 16 then
					if player:GetAttribute(LS.Attr.Chase) == true then
						if now() - (job.warned or 0) > 6 then
							job.warned = now()
							toast(player, "🚓 경찰이 따라오고 있어요! 따돌리고 와요", "warn")
						end
					else
						bigNextStep(player)
					end
				end
			elseif step.kind == "carry" and not carry[player] and job.cratesFrom and flat(pp, job.cratesFrom) < 8 then
				carry[player] = { kind = "crate", to = job.cratesTo, box = boxOn(player, Color3.fromRGB(120, 90, 50)) }
				bigMark(job, job.cratesTo)
				bigPush(player, "상자를 트럭으로 (" .. (job.n + 1) .. "/" .. step.n .. ")")
			end
		end
	end
end

local function bigStart(player: Player, id: string): any
	local why = blocked(player)
	if why then
		return { ok = false, text = why }
	end
	if bigLive[player] then
		return { ok = false, text = "이미 진행 중인 임무가 있어요" }
	end
	local pp = Law.posOf(player)
	if not pp or not hideoutPos or flat(pp, hideoutPos) > 14 then
		return { ok = false, text = "아지트의 행동대장에게 가야 해요" }
	end
	local ok, err = bigOpen(player, id)
	if not ok then
		return { ok = false, text = err }
	end
	bigLive[player] = { id = id, step = 0, n = 0, started = now() }
	say(hideout, LS.pick({ "준비 단단히 해. 이번 건 크다.", "실수하면 너만 들어가는 거야.", "좋아. 하나씩 차근차근." }))
	bigNextStep(player)
	return { ok = true, state = Crimes.bigView(player) }
end

local function bigBuy(player: Player): any
	local job = bigLive[player]
	if not job then
		return { ok = false }
	end
	local step = LS.BIG[job.id].steps[job.step]
	if not step or step.kind ~= "buy" then
		return { ok = false }
	end
	local pp = Law.posOf(player)
	if not pp or not hideoutPos or flat(pp, hideoutPos) > 14 then
		return { ok = false, text = "아지트에서 장비를 살 수 있어요" }
	end
	if not (ctx.spend and ctx.spend(player, step.cost, "🕶️ 장비 구입")) then
		return { ok = false, text = "돈이 부족해요 (" .. LS.won(step.cost) .. ")" }
	end
	bigNextStep(player)
	return { ok = true }
end

local function bigList(player: Player): any
	local out = {}
	for _, id in LS.BIG_ORDER do
		local b = LS.BIG[id]
		local ok, err = bigOpen(player, id)
		local steps = {}
		for _, st in b.steps do
			table.insert(steps, st.label)
		end
		table.insert(out, { id = id, label = b.label, icon = b.icon, open = ok, why = err, reward = b.reward, steps = steps, level = b.level, night = b.night })
	end
	local lvl, cur, nxt = LS.crimeLevel(Law.data(player).crimeXp)
	return { ok = true, list = out, level = lvl, title = cur.title, xp = Law.data(player).crimeXp, nextXp = nxt and nxt.xp or nil, pass = hasMafiaPass(player), live = Crimes.bigView(player), trust = Law.data(player).orgTrust }
end

-------------------------------------------------------------------------------------------------
-- Places (the hideout, the fixer, the chop shop) once the map is in
-------------------------------------------------------------------------------------------------
local function findDest(words: { string }): Vector3?
	for _, d in destList do
		if hasWord(d.name, words) then
			return d.pos
		end
	end
	return nil
end

local function buildPlaces()
	collectDests()
	buildShops()
	buildBikes()
	-- 폐차장 at the public car park
	chopPos = findDest({ "공영주차장" })
	if chopPos then
		local a = anchorPart("LawChopShop", CFrame.new(chopPos + Vector3.new(0, 2, 0)), Vector3.new(4, 4, 4))
		local pr = prompt(a, "훔친 차 넘기기", "폐차장 (뒷거래)", LS.SMALL.chop.hold)
		pr.MaxActivationDistance = 30
		pr.Triggered:Connect(function(p)
			local r = chop(p)
			toast(p, r.text or (if r.ok then "완료" else "안 돼요"), if r.ok then "crime" else "warn")
		end)
	end
	-- the fixer in the back lane (불법 배달)
	local N = Law.nav()
	local lane = N and N.places and (N.places.backlane or N.places.side)
	local fixPos = if lane then Vector3.new(lane.x, lane.y, lane.z) else findDest({ "먹자골목", "빵천동" })
	if fixPos then
		fixer = npcRig("law_fixer", CFrame.new(fixPos + Vector3.new(3, 0, 2)), { style = "street", body = "m", age = "adult" }, "phone")
		if fixer then
			fixer.model:SetAttribute("LawName", "수상한 남자")
			local pr = prompt(fixer.root, "물건 받기 (불법 배달)", "수상한 남자", 0.6)
			pr.Triggered:Connect(function(p)
				local r = contraband(p)
				if not r.ok then
					toast(p, r.text or "지금은 안 된대요", "warn")
				end
			end)
		end
	end
	-- the 아지트 at the port (조직 범죄)
	portPos = findDest({ "민락항", "회타운", "활어직판장" })
	bankPos = findDest({ "BNK", "은행" })
	hideoutPos = if portPos then portPos + Vector3.new(-22, 0, 14) else nil
	if hideoutPos then
		local P = Law.children.Police
		local q = P and P.ringNode(hideoutPos, 0, 25, nil)
		hideoutPos = q or hideoutPos
		hideout = npcRig("law_boss", CFrame.new(hideoutPos) * CFrame.Angles(0, math.rad(180), 0), { style = "street", body = "m", age = "adult" }, "arms_crossed")
		if hideout then
			hideout.model:SetAttribute("LawName", "행동대장")
			local pr = prompt(hideout.root, "조직 임무", "행동대장", 0.4)
			pr.Triggered:Connect(function(p)
				local job = bigLive[p]
				if job then
					local step = LS.BIG[job.id].steps[job.step]
					if step and step.kind == "buy" then
						local r = bigBuy(p)
						if not r.ok then
							toast(p, r.text or "안 돼요", "warn")
						end
						return
					end
				end
				Law.push(p, { kind = "bigMenu", data = bigList(p) })
			end)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Ops / ticks
-------------------------------------------------------------------------------------------------
local OPS = {
	pickpocket = function(player, p)
		return pickpocket(player, p)
	end,
	contraband = function(player, _p)
		return contraband(player)
	end,
	chop = function(player, _p)
		return chop(player)
	end,
	bigList = function(player, _p)
		return bigList(player)
	end,
	bigStart = function(player, p)
		return bigStart(player, type(p.id) == "string" and p.id or "")
	end,
	bigBuy = function(player, _p)
		return bigBuy(player)
	end,
	bigQuit = function(player, _p)
		if bigLive[player] then
			bigFail(player, "임무를 포기했어요")
			return { ok = true }
		end
		return { ok = false }
	end,
	bigState = function(player, _p)
		return { ok = true, state = Crimes.bigView(player) }
	end,
	list = function(player, _p)
		local out = {}
		local lvl = level(player)
		for _, id in LS.SMALL_ORDER do
			local d = LS.SMALL[id]
			table.insert(out, { id = id, label = d.label, icon = d.icon, level = d.level, open = lvl >= d.level, pay = d.pay, risk = d.risk, cool = math.ceil(coolLeft(player, id)) })
		end
		return { ok = true, list = out, level = lvl }
	end,
}

local acc = 0
function Crimes.tick(dt: number)
	acc += dt
	carryTick()
	if acc < 1 then
		return
	end
	acc = 0
	pcall(carTheftTick)
	pcall(bigTick)
	for player, job in bigLive do
		if job.markPos and now() - (job.lastPush or 0) > 5 then
			job.lastPush = now()
			bigPush(player, nil)
		end
	end
end

function Crimes.onLeave(player: Player, _s: any)
	cool[player] = nil
	dropCarry(player)
	if bigLive[player] then
		bigLive[player] = nil
	end
	passCache[player.UserId] = nil
end

function Crimes.init(law: any, context: any)
	Law = law
	ctx = context
	LS = Law.shared()
	G = context.G
	for name, slot in { GwangalliNPCLooks = "Looks", GwangalliTransitShared = "Transit", GwangalliCitizens = "Citizens", GwangalliMindShared = "MindShared" } do
		local m = ReplicatedStorage:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok then
				if slot == "Looks" then
					Looks = res
				elseif slot == "Transit" then
					Transit = res
				elseif slot == "MindShared" then
					MindShared = res
				else
					Citizens = res
				end
			end
		end
	end
	local f = workspace:FindFirstChild("GwangalliLawProps")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliLawProps"
		f.Parent = workspace
	end
	folder = f :: Folder
	Law.ops.crime = function(player, _s, p)
		local fn = OPS[p and p.act]
		if not fn then
			return { ok = false, err = "bad" }
		end
		return fn(player, p)
	end
	task.delay(10, function()
		local ok, err = pcall(buildPlaces)
		if not ok then
			warn("[GwangalliLaw] crime spots failed: " .. tostring(err))
		end
	end)
end

return Crimes
