--!nocheck
-- GwangalliGameplay/Customers (server, feature module; owner: npc_mind · NPC session): the NPC customers
-- of the shops — only their BEHAVIOUR. Personas, lines and store geometry: ReplicatedStorage.
-- GwangalliCustomerShared.
--
--   arrive (door) -> queue (move up as the line moves) -> at the counter: order (a speech bubble with the
--   order, the persona icon and a patience bar) -> wait near the pick-up counter (nags at the persona's
--   nagAt shares of patience; a drunk wanders) -> called: walk to the pick-up spot and take it -> react
--   (thanks / ok / complain / angry with a line + emote; a remake request = back to waiting) -> leave.
--   Patience runs out -> angry line, leave. The store closes (the last worker clocks out) -> everybody
--   leaves. 단골 (regular) customers are real townspeople (GwangalliCitizens): a happy visit is a small
--   호감도 gain with the worker(s) on shift (the Relationships system), an angry one a small loss.
--
-- BOUNDARY with the 알바 session (kept separable on purpose):
--   * this module never decides pay, XP, menus, judging or shifts. It talks to the job side ONLY through
--     ServerScriptService.GwangalliGameplay.WorkOrders:
--       WorkOrders.registerProvider(storeId, { name, onCall(order), onResult(result), onCancelled(order, reason) })
--       WorkOrders.placeOrder(storeId, customerId, nil, { name, patience, group })  -> order? (nil = closed)
--       WorkOrders.receive(orderId) -> result { reaction, remake, accuracy, satisfaction, waited }
--       WorkOrders.cancel(orderId, "left") / WorkOrders.view(order, now) (the order text for the bubble)
--   * a store is OPEN for customers while a player is on that job's shift (player attribute GwWorkShift
--     = the site's job id) and the job module handles it (ctx.work.handles(job)); with no job module /
--     no WorkOrders this module does nothing (the city keeps working).
--   * events for anyone (the 알바 session's UI, quests): BindableEvent ServerStorage.GwangalliCustomerEvents
--       ("arrive", siteId, info) ("order", siteId, info, orderId) ("react", siteId, info, reaction, result)
--       ("tip", siteId, info) — a regular's thank-you gesture; paying it is the job side's call
--       ("leave", siteId, info, why)          info = { id, persona, label, name?, citizenId? }
--   * API: BindableFunction ServerStorage.GwangalliCustomersAPI
--       ("sites") -> { siteId... } · ("count", siteId) -> n · ("registerSite", siteId, spec) (a new store
--       from the 알바 session, same shape as CS.SITES) · ("setOpen", siteId, true | false | nil) (force /
--       release; nil = follow the shifts)
--   Rigs: GwangalliNPCLooks rigs in workspace.GwangalliNPCs with the NPC.luau attribute contract (NpcId /
--   NpcLeg polyline / NpcYaw / NpcAct / NpcEmote, NpcKind "shop"): GwangalliNPCClient walks / animates them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Customers = {}

local ctx: any
local CS: any
local Orders: any = nil
local Looks: any = nil
local Citizens: any = nil

local rng = Random.new()
local sites: { [string]: any } = {}
local custs: { [string]: any } = {}
local serial = 0
local events: BindableEvent
local npcFolder: Instance

local function now(): number
	return os.clock()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

local function fire(kind: string, ...: any)
	if events then
		events:Fire(kind, ...)
	end
end

local function isNight(): boolean
	if ctx and ctx.env then
		local ok, e = pcall(ctx.env)
		if ok and type(e) == "table" then
			if e.night ~= nil then
				return e.night == true
			end
			local c = tonumber(e.clock)
			if c then
				return c >= 20 or c < 6
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- Geometry
-------------------------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ground(p: Vector3): Vector3
	local ex = { npcFolder }
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ex, pl.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ex
	local ok, hit = pcall(function()
		return workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -9, 0), rayParams)
	end)
	if ok and hit then
		return Vector3.new(p.X, hit.Position.Y, p.Z)
	end
	return p
end

local function destPart(name: string): BasePart?
	if ctx and ctx.dest then
		local d = ctx.dest(name)
		if d then
			return d
		end
	end
	for _, inst in CollectionService:GetTagged("Destination") do
		if inst:IsA("BasePart") and (inst:GetAttribute("DisplayName") == name or inst.Name == name) then
			return inst
		end
	end
	return nil
end

-- the site's points in world space (feet positions on the floor)
local function resolveSite(id: string, spec: any): any?
	local s = { id = id, spec = spec, open = false, force = nil, customers = {}, nextAt = now() + 4, queue = {}, waits = {}, memo = {} }
	if spec.anchors then
		local node: Instance? = workspace:FindFirstChild("Gwangalli")
		for _, n in spec.anchors do
			node = node and node:FindFirstChild(n)
		end
		if node then
			local function a(name: string): Vector3?
				local p = node:FindFirstChild("Station_" .. name)
				return if p and p:IsA("BasePart") then ground(p.Position) else nil
			end
			s.door = a("door_out")
			s.lobby = a("door_in")
			s.queue = {}
			for k = 1, 3 do
				local q = a("queue" .. k)
				if q then
					table.insert(s.queue, q)
				end
			end
			s.order = s.queue[1] or a("front")
			s.browse = {}
			for k = 1, 4 do
				local b = a("browse" .. k)
				if b then
					table.insert(s.browse, b)
				end
			end
			s.waits = { s.order }
			s.pickup = s.order
			s.counter = true
		end
	end
	if not s.door then
		local d = destPart(spec.dest)
		if not d then
			return nil
		end
		local cf = d.CFrame
		local function w(v: { number }): Vector3
			return ground((cf * CFrame.new(v[1], v[2], v[3])).Position)
		end
		s.door = w(spec.door)
		s.lobby = w(spec.lobby)
		s.order = w(spec.order)
		local dir = cf:VectorToWorldSpace(Vector3.new(spec.queueDir[1], spec.queueDir[2], spec.queueDir[3]))
		s.queue = {}
		for k = 1, 4 do
			table.insert(s.queue, ground(s.order + dir * (spec.queueStep * (k - 1))))
		end
		s.waits = {}
		for _, v in spec.waits do
			table.insert(s.waits, w(v))
		end
		s.pickup = w(spec.pickup)
		s.browse = {}
	end
	if not (s.door and s.order) then
		return nil
	end
	return s
end

-------------------------------------------------------------------------------------------------
-- Rigs, motion, bubbles
-------------------------------------------------------------------------------------------------
local function writeLeg(c: any, pts: { Vector3 }, speed: number)
	local m = c.model
	if not m or not m.Parent then
		return
	end
	c.path = pts
	c.speed = speed
	c.t0 = now()
	local total = 0
	for i = 2, #pts do
		total += (pts[i] - pts[i - 1]).Magnitude
	end
	c.arriveAt = now() + (if speed > 0 then total / speed else 0)
	c.pos = pts[#pts]
	if #pts < 2 or speed <= 0 then
		local p = pts[#pts]
		m:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", p.X, p.Y, p.Z, p.X, p.Y, p.Z, serverNow()))
		return
	end
	local parts = { "P", string.format("%.2f", serverNow()), string.format("%.2f", speed) }
	for _, p in pts do
		table.insert(parts, string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z))
	end
	m:SetAttribute("NpcLeg", table.concat(parts, ";"))
	local last = pts[#pts] - pts[#pts - 1]
	if last.Magnitude > 0.1 then
		m:SetAttribute("NpcYaw", math.deg(math.atan2(-last.X, -last.Z)))
	end
end

local function walkTo(c: any, pts: { Vector3 }, speed: number?)
	local from = c.pos
	local list = { from }
	for _, p in pts do
		table.insert(list, p)
	end
	writeLeg(c, list, speed or c.walk)
end

local function face(c: any, p: Vector3)
	local d = p - c.pos
	if Vector3.new(d.X, 0, d.Z).Magnitude > 0.2 and c.model then
		c.model:SetAttribute("NpcYaw", math.deg(math.atan2(-d.X, -d.Z)))
	end
end

local function act(c: any, a: string)
	if c.model then
		c.model:SetAttribute("NpcAct", a)
	end
end

local function emote(c: any, name: string)
	if c.model then
		serial += 1
		c.model:SetAttribute("NpcEmote", name .. "#" .. serial .. "#" .. string.format("%.2f", serverNow()))
	end
end

local function bubble(c: any): any?
	if c.bb and c.bb.gui.Parent then
		return c.bb
	end
	local head = c.model and c.model:FindFirstChild("Head")
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomerBubble"
	gui.Size = UDim2.fromOffset(230, 64)
	gui.StudsOffset = Vector3.new(0, 2.3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Adornee = head
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.Size = UDim2.new(1, 0, 0, 16)
	tag.BackgroundTransparency = 1
	tag.TextColor3 = Color3.fromRGB(255, 230, 150)
	tag.TextStrokeTransparency = 0.5
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 13
	tag.Parent = gui
	local say = Instance.new("TextLabel")
	say.Name = "Say"
	say.Position = UDim2.fromOffset(0, 17)
	say.Size = UDim2.new(1, 0, 0, 36)
	say.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	say.BackgroundTransparency = 0.06
	say.TextColor3 = Color3.fromRGB(30, 30, 40)
	say.Font = Enum.Font.GothamMedium
	say.TextScaled = true
	say.TextWrapped = true
	say.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = say
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 3), UDim.new(0, 3)
	pad.Parent = say
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 17
	lim.Parent = say
	say.Parent = gui
	local barBg = Instance.new("Frame")
	barBg.Name = "Patience"
	barBg.Position = UDim2.new(0.2, 0, 0, 56)
	barBg.Size = UDim2.new(0.6, 0, 0, 5)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	barBg.Visible = false
	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
	bar.BorderSizePixel = 0
	bar.Parent = barBg
	barBg.Parent = gui
	gui.Parent = c.model
	c.bb = { gui = gui, tag = tag, say = say, barBg = barBg, bar = bar }
	tag.Text = c.icon .. " " .. (c.name or c.label)
	return c.bb
end

local function say(c: any, situation: string, vars: any?, seconds: number?)
	local b = bubble(c)
	if not b then
		return
	end
	local text = CS.pick(c.memo, c.persona, situation, rand, vars)
	if not text then
		return
	end
	b.say.Text = text
	b.say.Visible = true
	c.sayStamp = now()
	local stamp = c.sayStamp
	task.delay(seconds or 3.6, function()
		if c.sayStamp == stamp and b.say.Parent then
			b.say.Visible = false
		end
	end)
	return text
end

local function patienceBar(c: any, share: number?)
	local b = bubble(c)
	if not b then
		return
	end
	if not share then
		b.barBg.Visible = false
		return
	end
	b.barBg.Visible = true
	b.bar.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	b.bar.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(80, 220, 120), math.clamp(share, 0, 1))
end

local NAMED_POOL: { string } = {}

local function buildRig(c: any): boolean
	if not Looks then
		return false
	end
	local ok, rig = pcall(function()
		local spec
		if c.citizenId and Citizens then
			spec = Looks.forCitizen(Citizens.byId[c.citizenId], false)
		else
			local h = table.clone(CS.PERSONAS[c.persona].hint or {})
			h.body = if rng:NextNumber() < 0.5 then "f" else "m"
			h.age = if c.persona == "student" then "young" elseif rng:NextNumber() < 0.6 then "adult" else "young"
			spec = Looks.random(c.id, h)
		end
		return Looks.build(spec, { name = "Customer_" .. c.id, anchored = true, shadow = false })
	end)
	if not ok or type(rig) ~= "table" or not rig.model then
		return false
	end
	c.model = rig.model
	c.ground = rig.ground or 3
	local m = rig.model
	m:SetAttribute("NpcId", c.id)
	m:SetAttribute("NpcKind", "shop")
	m:SetAttribute("NpcGround", c.ground)
	m:SetAttribute("NpcAct", "idle")
	m:SetAttribute("NpcYaw", 0)
	if c.citizenId then
		m:SetAttribute("CitizenId", c.citizenId)
	end
	rig.root.CFrame = CFrame.new(c.pos + Vector3.new(0, c.ground, 0))
	writeLeg(c, { c.pos }, 0)
	m.Parent = npcFolder
	return true
end

-------------------------------------------------------------------------------------------------
-- Customers
-------------------------------------------------------------------------------------------------
local function info(c: any): any
	return { id = c.id, persona = c.persona, label = c.label, name = c.name, citizenId = c.citizenId }
end

local function workersAt(s: any): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("GwWorkShift") == s.spec.job then
			table.insert(out, p)
		end
	end
	return out
end

-- 단골 = a real townsperson: a small relationship effect with the worker(s)
local function relate(c: any, s: any, mood: number)
	if not c.citizenId or not ctx.social or type(ctx.social.award) ~= "function" then
		return
	end
	for _, p in workersAt(s) do
		local pp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if pp and (pp.Position - c.pos).Magnitude < 60 then
			pcall(ctx.social.award, p, c.citizenId, if mood > 0 then "talk" else "rude", if mood > 0 then 2 else -2)
			if mood > 0 and ctx.notify then
				pcall(ctx.notify, p, "social", "💗 " .. tostring(c.name), "단골 손님이 기분 좋게 돌아갔어요")
			end
		end
	end
end

local function removeCust(c: any)
	custs[c.id] = nil
	local s = c.site
	if s then
		local i = table.find(s.customers, c)
		if i then
			table.remove(s.customers, i)
		end
		local q = table.find(s.queue, c)
		if q then
			table.remove(s.queue, q)
		end
	end
	if c.model then
		c.model:Destroy()
		c.model = nil
	end
end

local function leave(c: any, why: string)
	if c.state == "leaving" then
		return
	end
	if c.order and why ~= "done" and Orders then
		pcall(Orders.cancel, c.order.id, "left")
	end
	c.state = "leaving"
	patienceBar(c, nil)
	local s = c.site
	local i = table.find(s.queueLine, c)
	if i then
		table.remove(s.queueLine, i)
	end
	walkTo(c, { s.lobby or s.door, s.door }, c.walk * 1.05)
	fire("leave", s.id, info(c), why)
end

local function newCustomer(s: any, persona: string, groupId: string?): any?
	serial += 1
	local p = CS.PERSONAS[persona]
	local c = {
		id = "cust_" .. s.id .. "_" .. serial,
		site = s,
		persona = persona,
		label = p.label,
		icon = p.icon,
		walk = p.walk * (0.9 + rng:NextNumber() * 0.2),
		memo = {},
		state = "enter",
		pos = s.door,
		group = groupId,
		created = now(),
	}
	if p.named and Citizens and #NAMED_POOL > 0 then
		local id = NAMED_POOL[rng:NextInteger(1, #NAMED_POOL)]
		local busy = false
		for _, other in custs do
			if other.citizenId == id then
				busy = true
			end
		end
		if not busy then
			c.citizenId = id
			c.name = Citizens.byId[id] and Citizens.byId[id].name or nil
		end
	end
	if not buildRig(c) then
		warn("[GwangalliCustomers] rig build failed for " .. c.id)
		return nil
	end
	custs[c.id] = c
	table.insert(s.customers, c)
	-- in through the door to the end of the line
	table.insert(s.queueLine, c)
	local slot = s.queue[math.min(#s.queueLine, #s.queue)] or s.order
	walkTo(c, { s.lobby or s.door, slot })
	say(c, "enter")
	fire("arrive", s.id, info(c))
	return c
end

local function spawnArrival(s: any)
	local night = isNight()
	local persona = CS.pickPersona(function()
		return rng:NextNumber()
	end, night)
	local p = CS.PERSONAS[persona]
	local n = 1
	if p.group then
		n = rng:NextInteger(p.group[1], p.group[2])
	end
	n = math.min(n, s.spec.max - #s.customers)
	local gid = if n > 1 then "g" .. serial else nil
	for k = 1, n do
		local c = newCustomer(s, persona, gid)
		if c and k > 1 then
			c.follower = true -- the group's first member orders for everyone
		end
	end
end

local function place(c: any)
	local s = c.site
	local p = CS.PERSONAS[c.persona]
	local groupSize = 1
	if c.group then
		groupSize = 0
		for _, o in s.customers do
			if o.group == c.group then
				groupSize += 1
			end
		end
	end
	local ok, order = pcall(Orders.placeOrder, s.spec.job, c.id, nil, {
		name = c.name or c.label,
		patience = if p.patience ~= 1 then math.floor(95 * p.patience) else nil, -- nil: the job's own default
		group = if groupSize > 1 then groupSize else nil,
		-- for the 알바 session (optional to use): who this customer is
		meta = { persona = c.persona, strict = p.strict == true, citizenId = c.citizenId, npc = "npc-session" },
	})
	if not ok or not order then
		say(c, "leave")
		leave(c, "closed")
		return
	end
	c.order = order
	c.orderedAt = now()
	c.nagIdx = 1
	local text = ""
	local okV, v = pcall(Orders.view, order, now())
	if okV and type(v) == "table" and type(v.items) == "table" then
		local parts = {}
		for _, it in v.items do
			table.insert(parts, tostring(it.text or it.label or "음료"))
		end
		text = table.concat(parts, ", ")
	end
	say(c, "order", { order = if text ~= "" then text else "늘 먹던 거" }, 5)
	emote(c, "point_proc")
	fire("order", s.id, info(c), order.id)
	-- off the counter: wait near the pick-up
	local i = table.find(s.queueLine, c)
	if i then
		table.remove(s.queueLine, i)
	end
	c.state = "waiting"
	local spot = s.waits[(#s.customers % math.max(1, #s.waits)) + 1] or s.pickup or s.order
	walkTo(c, { spot })
	act(c, "phone")
	for _, o in s.customers do
		if o.group == c.group and o ~= c and o.follower then
			o.order = order
			o.state = "waiting"
			local fi = table.find(s.queueLine, o)
			if fi then
				table.remove(s.queueLine, fi)
			end
			walkTo(o, { spot + Vector3.new(rng:NextNumber() * 2 - 1, 0, rng:NextNumber() * 2 - 1) })
		end
	end
end

local function react(c: any, result: any)
	local s = c.site
	local reaction = CS.reaction(c.persona, tostring(result and result.reaction or "ok"))
	local r = CS.REACT[reaction]
	patienceBar(c, nil)
	act(c, "cup")
	say(c, r.line, nil, 4)
	emote(c, r.emote)
	fire("react", s.id, info(c), reaction, result)
	if c.persona == "regular" and reaction == "thanks" then
		task.delay(1.6, function()
			if custs[c.id] then
				say(c, "tip", nil, 3.5)
				fire("tip", s.id, info(c))
			end
		end)
	end
	relate(c, s, r.mood)
	for _, o in s.customers do
		if o.group and o.group == c.group and o ~= c then
			o.order = nil
			task.delay(0.5 + rng:NextNumber(), function()
				if custs[o.id] then
					act(o, "cup")
					leave(o, "done")
				end
			end)
		end
	end
	task.delay(2.4, function()
		if custs[c.id] then
			c.order = nil
			leave(c, "done")
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Provider callbacks (WorkOrders)
-------------------------------------------------------------------------------------------------
local function custByOrder(order: any): any?
	if not order then
		return nil
	end
	local c = custs[order.customerId]
	if c and not c.follower then
		return c
	end
	return nil
end

local function makeProvider(s: any): any
	return {
		name = "npc-session",
		onCall = function(order)
			local c = custByOrder(order)
			if not c or c.state == "leaving" then
				return
			end
			c.state = "called"
			say(c, "called")
			walkTo(c, { s.pickup or s.order }, c.walk * 1.15)
		end,
		onResult = function(result)
			local c = custs[result and result.customerId]
			if not c then
				return
			end
			if result.remake then
				-- the job asked for a remake: complain, back to waiting
				say(c, "remake", nil, 4)
				emote(c, "shake")
				c.state = "waiting"
				c.received = false
				return
			end
			react(c, result)
		end,
		onCancelled = function(order, reason)
			local c = custByOrder(order)
			if not c or c.state == "leaving" then
				return
			end
			c.order = nil
			say(c, if reason == "closed" then "leave" else "angry", nil, 4)
			emote(c, "facepalm")
			relate(c, s, -1)
			fire("react", s.id, info(c), "left", { reason = reason })
			leave(c, "cancelled")
		end,
	}
end

-------------------------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------------------------
local function siteOpen(s: any): boolean
	if s.force ~= nil then
		return s.force
	end
	if not (ctx.work and type(ctx.work.handles) == "function" and ctx.work.handles(s.spec.job)) then
		return false
	end
	return #workersAt(s) > 0
end

local function stepCustomer(c: any)
	local s = c.site
	local t = now()
	local arrived = t >= (c.arriveAt or 0)
	if c.state == "leaving" then
		if arrived then
			removeCust(c)
		end
		return
	end
	if not s.open then
		say(c, "leave")
		leave(c, "closed")
		return
	end
	if c.state == "enter" or c.state == "queue" then
		c.state = "queue"
		local idx = table.find(s.queueLine, c)
		if not idx then
			return
		end
		local slot = s.queue[math.min(idx, #s.queue)] or s.order
		if arrived and (c.pos - slot).Magnitude > 0.6 then
			walkTo(c, { slot })
			return
		end
		if arrived and idx == 1 and not c.follower then
			if not c.atCounterAt then
				c.atCounterAt = t
				act(c, "idle")
				face(c, s.pickup or s.order)
			elseif t - c.atCounterAt > 1.6 then
				place(c)
			end
		elseif arrived and idx > 1 and t - (c.lastQueueLine or 0) > 14 and rng:NextNumber() < 0.3 then
			c.lastQueueLine = t
			say(c, "wait")
		end
		-- the queue itself has a limit too
		if t - c.created > 140 * CS.PERSONAS[c.persona].patience then
			say(c, "leave")
			leave(c, "queue")
		end
		return
	end
	if c.state == "waiting" and c.order and not c.follower then
		local okV, v = pcall(Orders.view, c.order, t)
		if okV and type(v) == "table" and v.patience then
			local share = math.clamp((v.left or 0) / math.max(1, v.patience), 0, 1)
			patienceBar(c, share)
			local nags = CS.PERSONAS[c.persona].nagAt
			local elapsed = 1 - share
			if c.nagIdx and nags[c.nagIdx] and elapsed >= nags[c.nagIdx] then
				c.nagIdx += 1
				say(c, "nag")
				emote(c, if elapsed > 0.6 then "facepalm" else "look")
			end
		end
		-- a drunk wanders off and comes back
		local p = CS.PERSONAS[c.persona]
		if p.wander and arrived and t - (c.lastWander or c.orderedAt or t) > 12 and rng:NextNumber() < p.wander * 0.25 then
			c.lastWander = t
			say(c, "wander")
			local back = c.pos
			walkTo(c, { (s.lobby or s.door):Lerp(back, 0.5), back }, c.walk * 0.8)
		end
		return
	end
	if c.state == "called" and arrived and c.order and not c.received then
		c.received = true
		face(c, s.pickup or s.order)
		local ok, result = pcall(Orders.receive, c.order.id)
		if not ok or not result then
			c.received = false -- not on the counter yet: keep waiting at the pick-up spot
			c.state = "waiting"
		end
		-- the reaction comes through provider.onResult
	end
end

local acc = 0
local function tick(dt: number)
	acc += dt
	if acc < 0.25 then
		return
	end
	acc = 0
	for id, s in sites do
		local open = siteOpen(s)
		if open ~= s.open then
			s.open = open
			if open then
				s.nextAt = now() + 3
			end
		end
		if s.open and now() >= s.nextAt and #s.customers < s.spec.max then
			local g = s.spec.gap
			s.nextAt = now() + (g[1] + rng:NextNumber() * (g[2] - g[1])) * (if #s.customers == 0 then 0.6 else 1)
			local ok, err = pcall(spawnArrival, s)
			if not ok then
				warn("[GwangalliCustomers] spawn: " .. tostring(err))
			end
		end
		for _, c in table.clone(s.customers) do
			local ok, err = pcall(stepCustomer, c)
			if not ok then
				warn("[GwangalliCustomers] " .. tostring(err))
				removeCust(c)
			end
		end
		local _ = id
	end
end

-------------------------------------------------------------------------------------------------
-- Sites / API / init
-------------------------------------------------------------------------------------------------
local function addSite(id: string, spec: any): boolean
	if sites[id] or not Orders then
		return false
	end
	local s = resolveSite(id, spec)
	if not s then
		return false
	end
	s.queueLine = {}
	sites[id] = s
	local okR, unreg = pcall(Orders.registerProvider, spec.job, makeProvider(s))
	s.unregister = if okR then unreg else nil
	return true
end
Customers.addSite = addSite

function Customers.count(siteId: string): number
	local s = sites[siteId]
	return s and #s.customers or 0
end

function Customers.init(context: any)
	ctx = context
	local function opt(name: string): any
		local m = ReplicatedStorage:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok then
				return res
			end
		end
		return nil
	end
	CS = opt("GwangalliCustomerShared")
	Looks = opt("GwangalliNPCLooks")
	Citizens = opt("GwangalliCitizens")
	assert(CS, "GwangalliCustomerShared missing")
	local om = script.Parent and script.Parent:FindFirstChild("WorkOrders")
	if om and om:IsA("ModuleScript") then
		local ok, res = pcall(require, om)
		Orders = if ok then res else nil
	end
	ctx.customers = Customers
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	npcFolder = f
	local e = ServerStorage:FindFirstChild("GwangalliCustomerEvents")
	if not e then
		e = Instance.new("BindableEvent")
		e.Name = "GwangalliCustomerEvents"
		e.Parent = ServerStorage
	end
	events = e :: BindableEvent
	local api = ServerStorage:FindFirstChild("GwangalliCustomersAPI")
	if not api then
		api = Instance.new("BindableFunction")
		api.Name = "GwangalliCustomersAPI"
		api.Parent = ServerStorage
	end
	;(api :: BindableFunction).OnInvoke = function(op: string, a: any, b: any): any
		if op == "sites" then
			local out = {}
			for id in sites do
				table.insert(out, id)
			end
			return out
		elseif op == "count" then
			return Customers.count(a)
		elseif op == "registerSite" and type(a) == "string" and type(b) == "table" then
			return addSite(a, b)
		elseif op == "state" and sites[a] then
			local st = sites[a]
			return string.format("open=%s force=%s next=%.1f n=%d max=%s door=%s order=%s", tostring(st.open), tostring(st.force), st.nextAt - now(), #st.customers, tostring(st.spec.max), tostring(st.door), tostring(st.order))
		elseif op == "spawnNow" and sites[a] then
			local ok, err = pcall(spawnArrival, sites[a])
			return tostring(ok) .. " " .. tostring(err) .. " n=" .. #sites[a].customers
		elseif op == "setOpen" and sites[a] then
			sites[a].force = b
			return true
		end
		return nil
	end
	-- regulars: townspeople who are not key NPCs / police / street archetypes
	if Citizens and Citizens.ORDER then
		for _, id in Citizens.ORDER do
			local c = Citizens.byId[id]
			if c and not c.key and (c.type == nil or c.type == "plain") and not c.minor then
				table.insert(NAMED_POOL, id)
			end
		end
	end
	-- sites once the map (Destinations) and the job module are up
	task.delay(6, function()
		if not Orders then
			return
		end
		local names = {}
		for id, spec in CS.SITES do
			local handled = ctx.work and type(ctx.work.handles) == "function" and ctx.work.handles(spec.job)
			if handled and addSite(id, spec) then
				table.insert(names, id)
			end
		end
		print("[GwangalliCustomers] ready: " .. (if #names > 0 then table.concat(names, ", ") else "no store yet (the 알바 session registers more)"))
	end)
	task.spawn(function()
		local last = now()
		while true do
			task.wait(0.25)
			local t = now()
			local ok, err = pcall(tick, t - last)
			last = t
			if not ok then
				warn("[GwangalliCustomers] tick: " .. tostring(err))
			end
		end
	end)
end

return Customers
