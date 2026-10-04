-- GwangalliGameplay/VenueLife (owner: venues_detail): the shared server layer of the venue interiors
-- (노래방 / PC방 / 헬스장 / 볼링장 라운지), required and started by Venues.init.
--   * remotes VenueRequest (RemoteFunction) + VenueEvent (RemoteEvent) and the request router
--     (submodules register handlers: VenueLife.handle(op, fn))
--   * venue acts: player attribute GwVenueAct (every client animates it) + props welded to the hands
--   * food orders (PC방 seat / counter, 볼링장 분식): money through ctx.spend, a prop at the seat or the
--     pickup spot, the PC clerk walks the order over, eating applies stats (daily caps in d.daily)
--   * VenueSpot prompts: counters, 볼링화 대여 (shoe shells welded to the feet), 펀치 기계,
--     (gym spots are handled by Venues.luau through VenueLife.spot(id, fn))
--   * VenueBoard leaderboards (karaoke / pc / bowling / punch): the server writes Row1..Row5
--   * one 1 s tick for every venue system (VenueLife.onTick(fn))
-- Data: ReplicatedStorage.GwangalliVenuesShared. Money / stats are server-authoritative.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VenueLife = {}

local ctx: any
local G: any
local Util: any
local Profiles: any
local V: any
local reqRemote: RemoteFunction
local evRemote: RemoteEvent

local handlers: { [string]: (Player, any) -> any } = {}
local spotHandlers: { [string]: (Player, BasePart, ProximityPrompt) -> () } = {}
local spotSetups: { [string]: (BasePart) -> () } = {}
local tickers: { () -> () } = {}
local leaveHooks: { (Player) -> () } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end
VenueLife.now = now

function VenueLife.handle(op: string, fn: (Player, any) -> any)
	handlers[op] = fn
end
-- opts: { setup = fn(part) (makes its own prompt; the default prompt is skipped), action, object, hold }
local spotText: { [string]: { any } } = {}
function VenueLife.spot(id: string, fn: (Player, BasePart, ProximityPrompt) -> (), opts: any?)
	spotHandlers[id] = fn
	local o = opts or {}
	if o.setup then
		spotSetups[id] = o.setup
	end
	if o.action then
		spotText[id] = { o.action, o.object or "", o.hold or 0.3 }
	end
end
function VenueLife.onTick(fn: () -> ())
	table.insert(tickers, fn)
end
function VenueLife.onLeave(fn: (Player) -> ())
	table.insert(leaveHooks, fn)
end

function VenueLife.fire(player: Player, payload: any)
	if player.Parent == Players then
		evRemote:FireClient(player, payload)
	end
end

function VenueLife.prompt(parent: Instance, action: string, object: string, hold: number, dist: number, key: Enum.KeyCode?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = dist
	p.RequiresLineOfSight = false
	p.ClickablePrompt = true
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	if key then
		p.KeyboardKeyCode = key
	end
	p.Parent = parent
	return p
end

-- Stat effect with a per-real-day cap (d.daily.counts[key], the same store Venues.buy uses).
function VenueLife.capped(player: Player, key: string, limit: number, delta: { [string]: number }): ({ [string]: number }?, boolean)
	local d = Profiles.get(player)
	if not d then
		return nil, false
	end
	d.daily = d.daily or { day = 0, counts = {} }
	local today = G.dayKey(os.time())
	if d.daily.day ~= today then
		d.daily.day = today
		d.daily.counts = {}
	end
	d.daily.counts = d.daily.counts or {}
	local n = d.daily.counts[key] or 0
	if n >= limit then
		return nil, false
	end
	d.daily.counts[key] = n + 1
	Profiles.markDirty(player)
	return ctx.addStats(player, delta, nil, true), true
end

function VenueLife.pay(player: Player, amount: number, label: string): boolean
	if amount <= 0 then
		return true
	end
	if not ctx.canAfford(player, amount) then
		local d = Profiles.get(player)
		ctx.notify(player, "money", "잔액 부족", string.format("%s · %s (현금 %s · 통장 %s)", label, G.format.won(amount), G.format.won(d and d.cash or 0), G.format.won(d and d.bank or 0)))
		return false
	end
	return ctx.spend(player, amount, label, false) == true
end

local function inside(part: BasePart, pos: Vector3, pad: number?): boolean
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2 + Vector3.new(pad or 0, pad or 0, pad or 0)
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y + 3 and math.abs(lp.Z) <= h.Z
end
VenueLife.inside = inside

function VenueLife.near(player: Player, part: BasePart?, reach: number): boolean
	if not part then
		return false
	end
	local pos = Util.rootPosition(player)
	return pos ~= nil and (pos - part.Position).Magnitude <= reach
end

-------------------------------------------------------------------------------------------------
-- Acts + hand props
-------------------------------------------------------------------------------------------------
local actToken: { [Player]: number } = {}
local actProps: { [Player]: { Instance } } = {}

local function noPhys(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function part(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	noPhys(p)
	p.Parent = parent
	return p
end

local function weldTo(host: BasePart, p: BasePart, offset: CFrame)
	p.CFrame = host.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = host
	w.Part1 = p
	w.Parent = p
end

local function hand(character: Model, right: boolean): BasePart?
	local h = character:FindFirstChild(if right then "RightHand" else "LeftHand") or character:FindFirstChild(if right then "Right Arm" else "Left Arm")
	if h and h:IsA("BasePart") then
		return h
	end
	return nil
end

-- Builds a small prop (1-5 parts) welded to the character's hands. Returns the created instances.
local function handProp(character: Model, kind: string): { Instance }
	local out: { Instance } = {}
	local m = Instance.new("Model")
	m.Name = "GwangalliVenueProp"
	local rh, lh = hand(character, true), hand(character, false)
	local grip = CFrame.new(0, -0.35, -0.15)
	if kind == "tambourine" and rh then
		local ring = part(m, "Tambourine", Vector3.new(0.18, 1.1, 1.1), Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(rh, ring, grip * CFrame.new(0, -0.45, 0) * CFrame.Angles(0, math.rad(90), 0))
		for i = 0, 3 do
			local a = i * math.pi / 2 + 0.4
			local j = part(m, "Jingle", Vector3.new(0.22, 0.22, 0.08), Color3.fromRGB(210, 214, 220), Enum.Material.Metal, Enum.PartType.Cylinder)
			weldTo(rh, j, grip * CFrame.new(math.cos(a) * 0.46, -0.45 + math.sin(a) * 0.46, 0))
		end
	elseif (kind == "ramen" or kind == "tteok") and lh then
		local bowl = part(m, "Bowl", Vector3.new(0.6, 0.85, 0.85), if kind == "ramen" then Color3.fromRGB(240, 236, 226) else Color3.fromRGB(230, 70, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(lh, bowl, CFrame.new(0, -0.3, -0.45) * CFrame.Angles(0, 0, math.rad(90)))
		local food = part(m, "Food", Vector3.new(0.08, 0.7, 0.7), if kind == "ramen" then Color3.fromRGB(226, 170, 80) else Color3.fromRGB(200, 40, 24), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(lh, food, CFrame.new(0, -0.0, -0.45) * CFrame.Angles(0, 0, math.rad(90)))
		if rh then
			for _, dx in { -0.05, 0.05 } do
				local c = part(m, "Chopstick", Vector3.new(0.05, 0.05, 1.0), Color3.fromRGB(196, 160, 110), Enum.Material.Wood)
				weldTo(rh, c, CFrame.new(dx, -0.35, -0.45) * CFrame.Angles(math.rad(-20), 0, 0))
			end
		end
	elseif kind == "cup" and rh then
		local cup = part(m, "Cup", Vector3.new(0.8, 0.45, 0.45), Color3.fromRGB(220, 40, 50), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(rh, cup, grip * CFrame.Angles(0, 0, math.rad(90)))
		local straw = part(m, "Straw", Vector3.new(0.06, 0.6, 0.06), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic)
		weldTo(rh, straw, grip * CFrame.new(0.05, 0.6, 0))
	elseif kind == "water" and rh then
		local cup = part(m, "PaperCup", Vector3.new(0.5, 0.36, 0.36), Color3.fromRGB(246, 246, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(rh, cup, grip * CFrame.Angles(0, 0, math.rad(90)))
	elseif (kind == "hotdog" or kind == "skewer" or kind == "fries") and rh then
		if kind == "fries" then
			local box = part(m, "FriesBox", Vector3.new(0.5, 0.6, 0.3), Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic)
			weldTo(rh, box, grip)
			local f = part(m, "Fries", Vector3.new(0.42, 0.3, 0.24), Color3.fromRGB(250, 200, 70), Enum.Material.SmoothPlastic)
			weldTo(rh, f, grip * CFrame.new(0, 0.4, 0))
		else
			local stick = part(m, "Stick", Vector3.new(0.06, 0.06, 1.3), Color3.fromRGB(220, 196, 150), Enum.Material.Wood)
			weldTo(rh, stick, grip * CFrame.new(0, 0, -0.3))
			local body = part(m, "Body", if kind == "hotdog" then Vector3.new(0.34, 0.34, 0.8) else Vector3.new(0.3, 0.12, 0.7), if kind == "hotdog" then Color3.fromRGB(214, 150, 60) else Color3.fromRGB(226, 200, 150), Enum.Material.SmoothPlastic)
			weldTo(rh, body, grip * CFrame.new(0, 0, -0.75))
		end
	elseif kind == "mic" and rh then
		local body = part(m, "Mic", Vector3.new(0.9, 0.22, 0.22), Color3.fromRGB(30, 30, 34), Enum.Material.Metal, Enum.PartType.Cylinder)
		weldTo(rh, body, grip * CFrame.Angles(0, 0, math.rad(90)))
		local head = part(m, "MicHead", Vector3.new(0.38, 0.38, 0.38), Color3.fromRGB(170, 172, 180), Enum.Material.Metal, Enum.PartType.Ball)
		weldTo(rh, head, grip * CFrame.new(0, 0.55, 0))
	elseif kind == "dumbbells" then
		for _, h in { rh, lh } do
			if h then
				local bar = part(m, "DumbbellBar", Vector3.new(0.9, 0.16, 0.16), Color3.fromRGB(200, 204, 210), Enum.Material.Metal, Enum.PartType.Cylinder)
				weldTo(h, bar, CFrame.new(0, -0.35, 0))
				for _, dx in { -0.42, 0.42 } do
					local hd = part(m, "DumbbellHead", Vector3.new(0.26, 0.55, 0.55), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber, Enum.PartType.Cylinder)
					weldTo(h, hd, CFrame.new(dx, -0.35, 0))
				end
			end
		end
	end
	if #m:GetChildren() > 0 then
		m.Parent = character
		table.insert(out, m)
	else
		m:Destroy()
	end
	return out
end

function VenueLife.clearAct(player: Player)
	actToken[player] = (actToken[player] or 0) + 1
	for _, inst in actProps[player] or {} do
		if inst.Parent then
			inst:Destroy()
		end
	end
	actProps[player] = nil
	if player.Parent == Players then
		player:SetAttribute(V.Attr.Act, nil)
		player:SetAttribute(V.Attr.ActT, nil)
	end
end

-- Plays a venue act on the player for `seconds` (nil = until clearAct). prop: handProp kind.
function VenueLife.setAct(player: Player, act: string, seconds: number?, prop: string?): number
	VenueLife.clearAct(player)
	local token = actToken[player]
	player:SetAttribute(V.Attr.Act, act)
	player:SetAttribute(V.Attr.ActT, now())
	if prop then
		local character = Util.alive(player)
		if character then
			local ok, res = pcall(handProp, character, prop)
			if ok then
				actProps[player] = res
			end
		end
	end
	if seconds then
		task.delay(seconds, function()
			if actToken[player] == token then
				VenueLife.clearAct(player)
			end
		end)
	end
	return token
end

function VenueLife.actToken(player: Player): number
	return actToken[player] or 0
end

-------------------------------------------------------------------------------------------------
-- Leaderboards (VenueBoard parts; per server)
-------------------------------------------------------------------------------------------------
local boardParts: { [string]: { BasePart } } = {}
local boardRows: { [string]: { string } } = {}

local function paintBoard(p: BasePart, rows: { string })
	local gui = p:FindFirstChild("BoardGui", true)
	if not gui then
		return
	end
	for i = 1, 5 do
		local l = gui:FindFirstChild("Row" .. i, true)
		if l and l:IsA("TextLabel") then
			l.Text = rows[i] or ""
		end
	end
end

function VenueLife.setBoard(board: string, rows: { string })
	boardRows[board] = rows
	for _, p in boardParts[board] or {} do
		if p.Parent then
			pcall(paintBoard, p, rows)
		end
	end
end

function VenueLife.boardRows(board: string): { string }
	return boardRows[board] or {}
end

-- Sorted top list helper: entries { {name, score, userId} }, one entry per user (best kept).
function VenueLife.submit(list: { any }, entry: any, size: number): number
	for i, e in list do
		if e.userId == entry.userId then
			if entry.score <= e.score then
				-- not a personal best: rank of the existing entry
				return i
			end
			table.remove(list, i)
			break
		end
	end
	local pos = #list + 1
	for i, e in list do
		if entry.score > e.score then
			pos = i
			break
		end
	end
	table.insert(list, pos, entry)
	while #list > size do
		table.remove(list)
	end
	return if pos <= size then pos else 0
end

local function rowsOf(list: { any }, fmt: (any, number) -> string): { string }
	local rows = {}
	for i = 1, 5 do
		local e = list[i]
		rows[i] = if e then fmt(e, i) else string.format("%d.  -", i)
	end
	return rows
end
VenueLife.rowsOf = rowsOf

-------------------------------------------------------------------------------------------------
-- Food orders
-------------------------------------------------------------------------------------------------
type Order = { player: Player, item: string, prop: Model?, prompt: ProximityPrompt?, expires: number }
local orders: { [Player]: { Order } } = {}
local propFolder: Folder? = nil
local spots: { [string]: { BasePart } } = {}
local staff: { [string]: Model } = {}
local clerkBusy = false

local function folder(): Folder
	if propFolder and propFolder.Parent then
		return propFolder
	end
	local f = Instance.new("Folder")
	f.Name = "GwangalliVenueProps"
	f.Parent = workspace
	propFolder = f
	return f
end

local function anchoredPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Food prop standing on a surface: cf = the spot on the desk / counter (Y = surface top).
local function foodProp(item: string, cf: CFrame): Model
	local def = V.FOOD[item]
	local m = Instance.new("Model")
	m.Name = "Order_" .. item
	local base = cf
	local main: BasePart
	if def.prop == "ramen" or def.prop == "tteok" then
		main = anchoredPart(m, "Cup", Vector3.new(0.75, 0.85, 0.85), base * CFrame.new(0, 0.38, 0) * CFrame.Angles(0, 0, math.rad(90)), if def.prop == "ramen" then Color3.fromRGB(240, 236, 226) else Color3.fromRGB(230, 70, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		anchoredPart(m, "Band", Vector3.new(0.2, 0.88, 0.88), base * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		anchoredPart(m, "Lid", Vector3.new(0.05, 0.9, 0.9), base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(14), 0, 0), Color3.fromRGB(250, 220, 90), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		for _, dx in { -0.05, 0.05 } do
			anchoredPart(m, "Chopstick", Vector3.new(0.05, 0.05, 1.1), base * CFrame.new(0.55 + dx, 0.03, 0), Color3.fromRGB(196, 160, 110), Enum.Material.Wood)
		end
		local steam = Instance.new("ParticleEmitter")
		steam.Name = "Steam"
		steam.Rate = 3
		steam.Lifetime = NumberRange.new(1.2, 1.8)
		steam.Speed = NumberRange.new(0.6, 1)
		steam.SpreadAngle = Vector2.new(12, 12)
		steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.7) })
		steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		steam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		steam.LightInfluence = 1
		steam.Parent = main
	elseif def.prop == "cup" then
		main = anchoredPart(m, "Cup", Vector3.new(0.9, 0.5, 0.5), base * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 40, 50), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		anchoredPart(m, "Straw", Vector3.new(0.06, 0.6, 0.06), base * CFrame.new(0.05, 1.1, 0), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic)
	elseif def.prop == "fries" then
		main = anchoredPart(m, "FriesBox", Vector3.new(0.6, 0.7, 0.4), base * CFrame.new(0, 0.35, 0), Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic)
		anchoredPart(m, "Fries", Vector3.new(0.5, 0.35, 0.32), base * CFrame.new(0, 0.85, 0), Color3.fromRGB(250, 200, 70), Enum.Material.SmoothPlastic)
	else -- hotdog / skewer on a paper tray
		main = anchoredPart(m, "Tray", Vector3.new(1.2, 0.08, 0.7), base * CFrame.new(0, 0.04, 0), Color3.fromRGB(246, 240, 226), Enum.Material.SmoothPlastic)
		anchoredPart(m, "Food", if def.prop == "hotdog" then Vector3.new(0.9, 0.34, 0.34) else Vector3.new(0.8, 0.12, 0.34), base * CFrame.new(0, 0.25, 0), if def.prop == "hotdog" then Color3.fromRGB(214, 150, 60) else Color3.fromRGB(226, 200, 150), Enum.Material.SmoothPlastic)
	end
	m.PrimaryPart = main
	return m
end

local function removeOrder(o: Order)
	if o.prop and o.prop.Parent then
		o.prop:Destroy()
	end
	local list = orders[o.player]
	if list then
		local i = table.find(list, o)
		if i then
			table.remove(list, i)
		end
	end
end

local function eat(player: Player, o: Order)
	local def = V.FOOD[o.item]
	if not def or not o.prop or not o.prop.Parent then
		return
	end
	local character, _, root = Util.alive(player)
	if not character or not root then
		return
	end
	if (root.Position - o.prop:GetPivot().Position).Magnitude > 14 then
		ctx.notify(player, "info", def.name, "조금 더 가까이 가서 먹어요")
		return
	end
	if o.prompt then
		o.prompt.Enabled = false
	end
	-- the prop leaves the table: the act prop appears in the hands
	o.prop:Destroy()
	local list = orders[player]
	if list then
		local i = table.find(list, o)
		if i then
			table.remove(list, i)
		end
	end
	VenueLife.setAct(player, def.pose, def.eat, def.prop)
	task.delay(def.eat, function()
		if player.Parent ~= Players then
			return
		end
		local applied, ok = VenueLife.capped(player, "venue_" .. o.item, def.daily, def.effect)
		local desc = if applied then G.describeStats(applied) else ""
		ctx.notify(player, "stat", def.icon .. " " .. def.name .. " 냠냠", if ok and desc ~= "" then desc else (if ok then "맛있게 먹었어요" else "맛있게 먹었어요 (오늘 효과는 다 받았어요)"))
		VenueLife.fire(player, { kind = "ate", item = o.item, applied = applied })
	end)
end

local function placeOrder(o: Order, cf: CFrame)
	local def = V.FOOD[o.item]
	local m = foodProp(o.item, cf)
	m.Parent = folder()
	o.prop = m
	local host = m.PrimaryPart :: BasePart
	host.CanQuery = true
	local pr = VenueLife.prompt(host, if def.pose == "drink" then "마시기" else "먹기", def.icon .. " " .. def.name .. " · " .. o.player.DisplayName, 0.3, 9, Enum.KeyCode.E)
	pr.Name = "GwangalliFoodPrompt"
	o.prompt = pr
	pr.Triggered:Connect(function(who: Player)
		if who ~= o.player then
			ctx.notify(who, "info", def.name, o.player.DisplayName .. "님이 주문한 음식이에요 🙅")
			return
		end
		if not Util.cooldown(who, "venueEat", 1) then
			return
		end
		eat(who, o)
	end)
	VenueLife.fire(o.player, { kind = "orderReady", item = o.item })
	ctx.notify(o.player, "info", def.icon .. " " .. def.name .. " 나왔어요", "자리에서 '먹기'를 누르세요")
end

-- Walks a staff rig along world points (HumanoidRootPart height), playing walk on the clients
-- (attribute Moving = speed; GwangalliVenues animates it).
local function walkRig(rig: Model, points: { Vector3 }, speed: number)
	local root = rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	rig:SetAttribute("Moving", speed)
	for _, p in points do
		if not rig.Parent then
			return
		end
		local from = root.Position
		local to = Vector3.new(p.X, p.Y, p.Z)
		local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local dist = flat.Magnitude
		if dist > 0.2 then
			local cf = CFrame.lookAt(to, to + flat.Unit)
			root.CFrame = CFrame.lookAt(from, from + flat.Unit)
			local tw = TweenService:Create(root, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), { CFrame = cf })
			tw:Play()
			tw.Completed:Wait()
		end
	end
	rig:SetAttribute("Moving", 0)
end

local function clerkDeliver(o: Order, pc: Model, prep: number)
	local clerk = staff.pc_clerk
	local serve = pc:GetAttribute("ServePos")
	local aisle = pc:GetAttribute("AislePos")
	local cf = pc:GetAttribute("RamenCF")
	if typeof(cf) ~= "CFrame" then
		return false
	end
	if clerkBusy or not clerk or not clerk.Parent or typeof(serve) ~= "Vector3" or typeof(aisle) ~= "Vector3" then
		task.delay(prep, function()
			if o.player.Parent == Players then
				placeOrder(o, cf)
			end
		end)
		return true
	end
	local home = clerk:GetAttribute("HomeCF")
	if typeof(home) ~= "CFrame" then
		task.delay(prep, function()
			placeOrder(o, cf)
		end)
		return true
	end
	-- waypoints out of the staff zone (Way1..Way6, builder-authored), then the hall aisle and the seat
	local ways: { Vector3 } = {}
	for i = 1, 6 do
		local w = clerk:GetAttribute("Way" .. i)
		if typeof(w) == "Vector3" then
			table.insert(ways, w)
		end
	end
	clerkBusy = true
	task.spawn(function()
		local speed = 9
		local rootY = home.Position.Y
		local pts: { Vector3 } = {}
		for _, w in ways do
			table.insert(pts, Vector3.new(w.X, rootY, w.Z))
		end
		table.insert(pts, Vector3.new(aisle.X, rootY, aisle.Z))
		table.insert(pts, Vector3.new(serve.X, rootY, serve.Z))
		local dist = 0
		local prev = home.Position
		for _, p in pts do
			dist += (p - prev).Magnitude
			prev = p
		end
		local walkT = dist / speed
		task.wait(math.max(1, prep - walkT - 1.5)) -- cooking at the counter
		local okWalk = pcall(function()
			clerk:SetAttribute("Act", "tray")
			walkRig(clerk, pts, speed)
			-- hand-over at the seat
			clerk:SetAttribute("Act", "give")
			if o.player.Parent == Players then
				placeOrder(o, cf)
			end
			task.wait(1.2)
			clerk:SetAttribute("Act", "walk")
			local back = {}
			for i = #pts - 1, 1, -1 do
				table.insert(back, pts[i])
			end
			table.insert(back, home.Position)
			walkRig(clerk, back, speed)
			local root = clerk.PrimaryPart
			if root then
				root.CFrame = home
			end
		end)
		if not okWalk and o.player.Parent == Players and not o.prop then
			placeOrder(o, cf)
		end
		clerk:SetAttribute("Act", clerk:GetAttribute("HomeAct") or "typing")
		clerkBusy = false
	end)
	return true
end

local function nearestSpot(player: Player, id: string, reach: number): BasePart?
	local pos = Util.rootPosition(player)
	if not pos then
		return nil
	end
	local best, bd = nil, reach
	for _, p in spots[id] or {} do
		if p.Parent then
			local d = (p.Position - pos).Magnitude
			if d <= bd then
				best, bd = p, d
			end
		end
	end
	return best
end
VenueLife.nearestSpot = nearestSpot

-- Order food. PC방 items go to the player's PC seat (the clerk brings them) or the counter
-- pickup; 볼링장 items to the snack bar pickup.
function VenueLife.order(player: Player, item: any): any
	local id = Util.str(item, 24)
	local def = id and V.FOOD[id]
	if not def then
		return { ok = false, code = "item", message = "메뉴에 없어요" }
	end
	local list = orders[player]
	if list and #list >= 3 then
		return { ok = false, code = "limit", message = "먼저 주문한 음식부터 먹어요 🍽️" }
	end
	local pc: Model? = nil
	local spot: BasePart? = nil
	if def.menu == "pcbang" then
		pc = VenueLife.pcOf and VenueLife.pcOf(player) or nil
		if not pc then
			spot = nearestSpot(player, "pc_counter", 22)
		end
	else
		spot = nearestSpot(player, "bowl_snack", 22)
	end
	if not pc and not spot then
		return { ok = false, code = "where", message = if def.menu == "pcbang" then "PC 자리나 카운터에서 주문할 수 있어요" else "분식 코너에서 주문할 수 있어요" }
	end
	if not VenueLife.pay(player, def.price, def.name) then
		return { ok = false, code = "money", message = "잔액이 부족해요" }
	end
	local o: Order = { player = player, item = id :: string, prop = nil, prompt = nil, expires = os.clock() + def.prep + 180 }
	list = orders[player] or {}
	orders[player] = list
	table.insert(list, o)
	if pc then
		clerkDeliver(o, pc, def.prep)
	else
		local s = spot :: BasePart
		local pcf = s:GetAttribute("PickupCF")
		local cf = if typeof(pcf) == "CFrame" then pcf else s.CFrame * CFrame.new(0, s.Size.Y / 2, 0)
		local n = #list - 1
		cf = cf * CFrame.new(n * 1.3, 0, 0)
		task.delay(def.prep, function()
			if player.Parent == Players then
				placeOrder(o, cf)
			end
		end)
	end
	return { ok = true, item = id, prep = def.prep, message = string.format("%s 주문 완료 · %d초 뒤에 나와요", def.name, def.prep) }
end

-------------------------------------------------------------------------------------------------
-- 볼링화 대여 (shoe shells welded to the feet)
-------------------------------------------------------------------------------------------------
local shoes: { [Player]: { color: number, counter: BasePart } } = {}
local shoePick: { [BasePart]: number } = {}

local function removeShoes(player: Player)
	local c = player.Character
	if c then
		for _, x in c:GetChildren() do
			if x.Name == "GwangalliBowlingShoes" then
				x:Destroy()
			end
		end
	end
end

local function wearShoes(player: Player, idx: number)
	local character = Util.alive(player)
	if not character then
		return
	end
	removeShoes(player)
	local col = V.SHOES.colors[idx] or V.SHOES.colors[1]
	local m = Instance.new("Model")
	m.Name = "GwangalliBowlingShoes"
	for _, fname in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local foot = character:FindFirstChild(fname)
		if foot and foot:IsA("BasePart") then
			local r6 = fname == "Left Leg" or fname == "Right Leg"
			local s = foot.Size
			local shellSize = if r6 then Vector3.new(s.X * 1.08, 0.55, s.Z * 1.25) else Vector3.new(s.X * 1.12, s.Y * 1.12, s.Z * 1.16)
			local off = if r6 then CFrame.new(0, -s.Y / 2 + 0.27, -0.05) else CFrame.new(0, 0, -0.03)
			local shell = part(m, "Shoe", shellSize, Util.color(col.main), Enum.Material.Leather)
			weldTo(foot, shell, off)
			local sole = part(m, "Sole", Vector3.new(shellSize.X * 1.02, 0.12, shellSize.Z * 1.02), Util.color(col.sole), Enum.Material.Rubber)
			weldTo(foot, sole, off * CFrame.new(0, -shellSize.Y / 2 + 0.05, 0))
			local stripe = part(m, "Stripe", Vector3.new(shellSize.X * 1.03, shellSize.Y * 0.3, shellSize.Z * 0.35), Util.color(col.trim), Enum.Material.Leather)
			weldTo(foot, stripe, off * CFrame.new(0, 0.02, shellSize.Z * 0.12))
		end
	end
	m.Parent = character
end

-------------------------------------------------------------------------------------------------
-- 펀치 기계
-------------------------------------------------------------------------------------------------
local punchTop: { any } = {}

local function punch(player: Player, spotPart: BasePart)
	if not Util.cooldown(player, "venuePunch", 4) then
		return
	end
	if not VenueLife.pay(player, V.PUNCH.price, "펀치 기계") then
		return
	end
	local d = Profiles.get(player)
	local strength = d and d.stats and d.stats.strength or 10
	local roll = math.random()
	local timing = 0.4 + math.random() * 0.6
	local score = V.punchScore(strength, timing, roll)
	VenueLife.setAct(player, "punch", 1.6)
	task.delay(0.55, function()
		local screen = spotPart:FindFirstChild("ScoreGui", true) or (spotPart.Parent and spotPart.Parent:FindFirstChild("ScoreGui", true))
		if screen then
			local l = screen:FindFirstChild("Text", true)
			if l and l:IsA("TextLabel") then
				l.Text = string.format("PUNCH %d", score)
			end
		end
		local rank = VenueLife.submit(punchTop, { name = player.DisplayName, score = score, userId = player.UserId }, 5)
		VenueLife.setBoard("punch", rowsOf(punchTop, function(e, i)
			return string.format("%d. %s  %d", i, e.name, e.score)
		end))
		local best = punchTop[1] and punchTop[1].score or score
		VenueLife.fire(player, { kind = "punch", score = score, best = best, rank = rank })
		local msg = if score >= 900 then "기계가 흔들려요! 펀치왕 👑" elseif score >= 700 then "묵직한 한 방 💥" else "근력을 키우면 더 세져요 💪"
		ctx.notify(player, "info", string.format("🥊 펀치 %d점", score), msg .. (if rank == 1 then " · 오늘 최고 기록!" else ""))
	end)
end

-------------------------------------------------------------------------------------------------
-- Bowling top 5 (players' LastBowlingScore)
-------------------------------------------------------------------------------------------------
local bowlTop: { any } = {}
local function watchBowling(player: Player)
	player:GetAttributeChangedSignal(G.Attr.LastBowlingScore):Connect(function()
		local s = player:GetAttribute(G.Attr.LastBowlingScore)
		if type(s) == "number" and s >= 0 and s <= 300 then
			VenueLife.submit(bowlTop, { name = player.DisplayName, score = s, userId = player.UserId }, 5)
			VenueLife.setBoard("bowling", rowsOf(bowlTop, function(e, i)
				return string.format("%d. %s  %d점", i, e.name, e.score)
			end))
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Spots / staff / boards discovery
-------------------------------------------------------------------------------------------------
local spotPrompts: { [BasePart]: boolean } = {}

local SPOT_TEXT = {
	pc_counter = { "음식 주문", "광안 PC방 카운터", 0.2 },
	bowl_snack = { "분식 주문", "ROCK & BOWL 분식", 0.2 },
	bowl_shoes = { "볼링화 대여", "볼링화 · " .. "1,500원", 0.3 },
	bowl_punch = { "펀치! (500원)", "펀치왕 기계", 0.3 },
}

local function setupSpot(p: Instance)
	if not p:IsA("BasePart") or spotPrompts[p] then
		return
	end
	local id = p:GetAttribute("Spot")
	if type(id) ~= "string" then
		return
	end
	spotPrompts[p] = true
	local list = spots[id] or {}
	spots[id] = list
	table.insert(list, p)
	if spotSetups[id] then
		spotSetups[id](p)
		return
	end
	local t = SPOT_TEXT[id] or spotText[id]
	if not t and not spotHandlers[id] then
		return
	end
	local label = p:GetAttribute("Label")
	local pr = VenueLife.prompt(p, t and t[1] or "이용하기", if type(label) == "string" then label else (t and t[2] or ""), t and t[3] or 0.3, 9, Enum.KeyCode.E)
	pr.Name = "GwangalliSpotPrompt"
	if id == "bowl_shoes" then
		shoePick[p] = 1
		pr.ObjectText = string.format("볼링화 (%s) · %s", V.SHOES.colors[1].name, V.won(V.SHOES.price))
		local nx = VenueLife.prompt(p, "색상 바꾸기 ▶", "", 0, 9, Enum.KeyCode.R)
		nx.Name = "GwangalliShoeColor"
		nx.UIOffset = Vector2.new(0, 84)
		nx.Triggered:Connect(function(player: Player)
			if not Util.cooldown(player, "shoeColor", 0.2) then
				return
			end
			local i = (shoePick[p] or 1) % #V.SHOES.colors + 1
			shoePick[p] = i
			pr.ObjectText = string.format("볼링화 (%s) · %s", V.SHOES.colors[i].name, V.won(V.SHOES.price))
		end)
	end
	pr.Triggered:Connect(function(player: Player)
		if not Profiles.get(player) or not Util.cooldown(player, "venueSpot", 0.6) then
			return
		end
		if spotHandlers[id] then
			local ok, err = pcall(spotHandlers[id], player, p, pr)
			if not ok then
				warn("[VenueLife] spot " .. id .. ": " .. tostring(err))
			end
		elseif id == "pc_counter" or id == "bowl_snack" then
			VenueLife.fire(player, { kind = "menu", spot = p, menu = if id == "pc_counter" then "pcbang" else "bowling", items = V.MENUS[if id == "pc_counter" then "pcbang" else "bowling"] })
		elseif id == "bowl_shoes" then
			local cur = shoes[player]
			if cur and player.Character and player.Character:FindFirstChild("GwangalliBowlingShoes") then
				removeShoes(player)
				shoes[player] = nil
				ctx.notify(player, "info", "👟 볼링화 반납", "감사합니다. 즐거운 게임 되셨나요?")
				return
			end
			local idx = shoePick[p] or 1
			if not VenueLife.pay(player, V.SHOES.price, "볼링화 대여") then
				return
			end
			wearShoes(player, idx)
			shoes[player] = { color = idx, counter = p }
			ctx.notify(player, "info", "👟 볼링화 (" .. V.SHOES.colors[idx].name .. ") 착용", "레인에서 '볼링 치기'! 나갈 때는 카운터에 반납해요")
		elseif id == "bowl_punch" then
			punch(player, p)
		end
	end)
end

local function setupStaff(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local id = m:GetAttribute("Staff")
	if type(id) == "string" then
		staff[id] = m
		if m:GetAttribute("HomeAct") == nil then
			m:SetAttribute("HomeAct", m:GetAttribute("Act") or "idle")
		end
	end
end

local function setupBoard(p: Instance)
	if not p:IsA("BasePart") then
		return
	end
	local b = p:GetAttribute("Board")
	if type(b) ~= "string" then
		return
	end
	local list = boardParts[b] or {}
	boardParts[b] = list
	if not table.find(list, p) then
		table.insert(list, p)
	end
	if boardRows[b] then
		pcall(paintBoard, p, boardRows[b])
	end
end

local function watchTag(tag: string, fn: (Instance) -> ())
	local function safe(inst: Instance)
		if not inst:IsDescendantOf(workspace) then
			return
		end
		local ok, err = pcall(fn, inst)
		if not ok then
			warn("[VenueLife] " .. tag .. " setup failed: " .. tostring(err))
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(safe)
	for _, inst in CollectionService:GetTagged(tag) do
		safe(inst)
	end
end
VenueLife.watchTag = watchTag

-------------------------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------------------------
function VenueLife.leave(player: Player)
	for _, fn in leaveHooks do
		pcall(fn, player)
	end
	for _, o in table.clone(orders[player] or {}) do
		removeOrder(o)
	end
	orders[player] = nil
	shoes[player] = nil
	actToken[player] = nil
	actProps[player] = nil
end

function VenueLife.character(player: Player)
	-- a respawn drops the act props / shoes with the old character
	actProps[player] = nil
	shoes[player] = nil
	if player.Parent == Players then
		player:SetAttribute(V.Attr.Act, nil)
	end
end

local function loadShared(): any
	local m = ReplicatedStorage:FindFirstChild("GwangalliVenuesShared") or ReplicatedStorage:WaitForChild("GwangalliVenuesShared", 10)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			return res
		end
		warn("[VenueLife] GwangalliVenuesShared failed: " .. tostring(res))
	end
	return nil
end

function VenueLife.init(context: any): boolean
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	V = loadShared()
	if not V then
		warn("[VenueLife] GwangalliVenuesShared missing; venue interactions disabled")
		return false
	end
	VenueLife.V = V
	VenueLife.ctx = ctx
	local folderR = ReplicatedStorage:FindFirstChild(G.RemotesFolder)
	if not folderR then
		folderR = Instance.new("Folder")
		folderR.Name = G.RemotesFolder
		folderR.Parent = ReplicatedStorage
	end
	local function remote(name: string, class: string): any
		local r = folderR:FindFirstChild(name)
		if r and r.ClassName ~= class then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(class)
			r.Name = name
			r.Parent = folderR
		end
		return r
	end
	reqRemote = remote(V.Remote.Request, "RemoteFunction")
	evRemote = remote(V.Remote.Event, "RemoteEvent")

	VenueLife.handle("order", function(player, p)
		return VenueLife.order(player, type(p) == "table" and p.item or nil)
	end)
	VenueLife.handle("emote", function(player, p)
		local name = type(p) == "table" and p.name or nil
		if name == "tambourine" then
			if not Util.cooldown(player, "tambourine", 1.2) then
				return { ok = false, code = "cooldown" }
			end
			VenueLife.setAct(player, "tambourine", 2.6, "tambourine")
			return { ok = true }
		end
		return { ok = false, code = "emote" }
	end)
	VenueLife.handle("boards", function(_player, p)
		local b = type(p) == "table" and Util.str(p.board, 16) or nil
		return { ok = b ~= nil, rows = if b then VenueLife.boardRows(b) else {} }
	end)

	reqRemote.OnServerInvoke = function(player: Player, op: any, payload: any)
		if type(op) ~= "string" or #op > 24 then
			return { ok = false, code = "op" }
		end
		if not Util.bucket(player, 6, 12) then
			return { ok = false, code = "rate", message = "잠시 후에 다시 시도해 주세요" }
		end
		local fn = handlers[op]
		if not fn or not Profiles.get(player) then
			return { ok = false, code = "op" }
		end
		local ok, res = pcall(fn, player, payload)
		if not ok then
			warn("[VenueLife] " .. op .. " failed: " .. tostring(res))
			return { ok = false, code = "error", message = "잠시 후에 다시 시도해 주세요" }
		end
		return if type(res) == "table" then res else { ok = res == true }
	end

	-- boards start with placeholder rows
	VenueLife.setBoard("punch", rowsOf({}, function()
		return ""
	end))
	VenueLife.setBoard("bowling", rowsOf({}, function()
		return ""
	end))

	Players.PlayerAdded:Connect(watchBowling)
	for _, pl in Players:GetPlayers() do
		watchBowling(pl)
	end

	-- one tick for every venue system
	task.spawn(function()
		while true do
			task.wait(1)
			for _, fn in tickers do
				local ok, err = pcall(fn)
				if not ok then
					warn("[VenueLife] tick: " .. tostring(err))
				end
			end
			-- shoes go back when the player leaves the bowling centre; stale orders expire
			for player, s in shoes do
				local pos = Util.rootPosition(player)
				if pos and s.counter.Parent and (pos - s.counter.Position).Magnitude > V.SHOES.returnDistance then
					removeShoes(player)
					shoes[player] = nil
					ctx.notify(player, "info", "👟 볼링화 자동 반납", "볼링장을 나가서 볼링화를 반납했어요")
				end
			end
			local t = os.clock()
			for _, list in orders do
				for _, o in table.clone(list) do
					if t > o.expires then
						removeOrder(o)
					end
				end
			end
		end
	end)
	return true
end

-- called by Venues.init after the submodules registered their spot handlers
function VenueLife.start()
	watchTag(V.Tags.Staff, setupStaff)
	watchTag(V.Tags.Spot, setupSpot)
	watchTag(V.Tags.Board, setupBoard)
end

return VenueLife
