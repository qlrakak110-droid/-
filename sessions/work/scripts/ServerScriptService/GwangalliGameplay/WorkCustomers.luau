--!nocheck
-- GwangalliGameplay/WorkCustomers: the VISIBLE NPC CUSTOMERS of the 알바 work simulation. Registered as
-- the order provider (WorkOrders.registerProvider) of every store whose kind gives a `site`
-- (WorkCafe → 스타벅스 광안리점, WorkStore → GS25 광안리점); while it is connected the store spawns no
-- "🧪 테스트 손님". Driven by Work.luau: Customers.open(store) at the first clock-in, Customers.close(store)
-- when the last worker leaves, Customers.tick(now) from Work's 0.1 s loop (state machine at 4 Hz, bubbles
-- at 1 Hz).
--
--   door_out → door_in → (browse a shelf / the menu board) → queue slot 3..1 → at slot 1: order
--   (cafe: the worker takes it at the POS, then the customer waits near the pick-up counter until the
--   call · cvs: the items go on the counter and WorkStore runs the sale) → result → reaction → leave.
--
--   * RIGS: GwangalliNPCLooks block rigs, pooled per store (≤ C.CUSTOMERS.maxPerStore = 4 visible), parked
--     in ServerStorage when idle; they live in workspace.GwangalliNPCs with the NPC.luau attribute
--     contract (NpcId / NpcLeg polyline on the server clock / NpcYaw / NpcAct / NpcEmote, NpcKind "shop")
--     so GwangalliNPCClient walks and animates them, exactly like JobWorld's shop customers.
--   * BUBBLE: a BillboardGui on the rig's Head (in the Workspace, so the emulator renders it): a name tag
--     with the personality icon, the speech line and a patience bar (green → red) while waiting.
--   * PERSONALITIES (C.CUSTOMERS.personas, lines in GwangalliWorkLines): 평범한 손님 · 급한 손님 (short
--     patience, nags) · 취객 (slow, slurred, wanders, may change the order / cause trouble) · 진상 손님
--     (strict: a remake below 90 %, argues, refund demands in the store) · 학생 (2-3 together, group
--     orders) · 단골 (patient, polite, tips on a good result). A line never repeats twice in a row.
--
-- Store-kind hooks (all optional): K.site(store) -> { door_out, door_in, browse = { { pos, path? } },
--   queue = { feet x3 }, face (Vector3 the queue looks along), pickupWait? = { feet }, pickup? = feet,
--   orderAtCounter }, K.customerPurpose(store, cust, rand) -> purpose?, K.customerBrowse(store, cust,
--   rand) (fills cust.items), K.customerOrder(store, cust, rand) -> specs?, info?, K.orderLine(store, o,
--   cust) -> text, K.customerEvent(store, cust, kind) ("wander" / "arrive" / "leave").
-- API for the store kinds: Customers.say / sayText / emote / get / byOrder / release / hold / spawn /
--   count / setAct.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local Customers = {}

local C: any
local WS: any
local Orders: any
local W: any
local Lines: any
local Looks: any = nil

local rng = Random.new()
local sites: { [string]: any } = {}
local custSerial = 0
local lastStateTick = 0
local lastBubbleTick = 0

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

local function yawOf(v: Vector3): number
	return math.deg(math.atan2(-v.X, -v.Z))
end

function Customers.init(cfg: any, ws: any, orders: any, work: any)
	C = cfg
	WS = ws
	Orders = orders
	W = work
	local lm = ReplicatedStorage:FindFirstChild("GwangalliWorkLines")
	if lm and lm:IsA("ModuleScript") then
		local ok, res = pcall(require, lm)
		if ok and type(res) == "table" then
			Lines = res
		end
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and type(res.build) == "function" then
			Looks = res
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Folders / rigs
-------------------------------------------------------------------------------------------------
local function npcFolder(): Folder
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	return f :: Folder
end

local function parkFolder(): Folder
	local f = ServerStorage:FindFirstChild("GwangalliWorkCustomerPool")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliWorkCustomerPool"
		f.Parent = ServerStorage
	end
	return f :: Folder
end

local AGE_HINT = { student = "teen", drunk = "middle", regular = "adult", hurry = "young", karen = "middle" }

-- the bubble on the head: tag (persona + name), speech, patience bar
local function buildBubble(head: BasePart): any
	local old = head:FindFirstChild("WorkCustomerBubble")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "WorkCustomerBubble"
	bb.Size = UDim2.fromOffset(220, 78)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 55
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = bb
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.Size = UDim2.new(1, 0, 0, 18)
	tag.Position = UDim2.new(0, 0, 1, -18)
	tag.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	tag.BackgroundTransparency = 0.25
	tag.TextColor3 = Color3.fromRGB(235, 240, 248)
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 12
	tag.Text = ""
	tag.Parent = root
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 6)
	tc.Parent = tag
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, -8, 0, 4)
	bar.Position = UDim2.new(0, 4, 1, -3)
	bar.BackgroundColor3 = Color3.fromRGB(50, 54, 64)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = tag
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local say = Instance.new("TextLabel")
	say.Name = "Say"
	say.Size = UDim2.new(1, 0, 1, -22)
	say.Position = UDim2.fromOffset(0, 0)
	say.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	say.BackgroundTransparency = 0.05
	say.TextColor3 = Color3.fromRGB(25, 25, 30)
	say.Font = Enum.Font.GothamMedium
	say.TextSize = 14
	say.TextWrapped = true
	say.Text = ""
	say.Visible = false
	say.Parent = root
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 10)
	sc.Parent = say
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = say
	bb.Parent = head
	return { gui = bb, tag = tag, say = say, bar = bar, fill = fill }
end

local function newRig(persona: string): any?
	if not Looks then
		return nil
	end
	custSerial += 1
	local seed = custSerial * 6151 + rng:NextInteger(1, 100000)
	local okS, spec = pcall(Looks.random, seed, { age = AGE_HINT[persona] })
	if not okS then
		return nil
	end
	local okB, rig = pcall(Looks.build, spec, { name = "WorkCustomer", anchored = true, humanoid = false })
	if not okB or type(rig) ~= "table" or not rig.model then
		return nil
	end
	local model: Model = rig.model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("NpcKind", "shop")
	model:SetAttribute("WorkCustomer", true)
	model:SetAttribute("NpcGround", rig.ground or 3)
	model:SetAttribute("NpcAct", "idle")
	model:SetAttribute("NpcYaw", 0)
	model:SetAttribute("NpcLook", 0)
	model:SetAttribute("NpcTalk", 0)
	model:SetAttribute("NpcLeg", "")
	model:SetAttribute("NpcEmote", "")
	local head = rig.head or model:FindFirstChild("Head")
	return { model = model, root = rig.root, head = head, ground = rig.ground or 3, ui = head and buildBubble(head) or nil }
end

-------------------------------------------------------------------------------------------------
-- Motion / speech
-------------------------------------------------------------------------------------------------
local function setAct(c: any, act: string)
	if c.model:GetAttribute("NpcAct") ~= act then
		c.model:SetAttribute("NpcAct", act)
	end
end

local emoteSeq = 0
local function emote(c: any, name: string)
	emoteSeq += 1
	c.model:SetAttribute("NpcEmote", string.format("%s#%d#%.1f", name, emoteSeq, workspace:GetServerTimeNow()))
end

local function placeAt(c: any, feet: Vector3, yaw: number)
	c.pos = feet
	c.yaw = yaw
	c.root.CFrame = CFrame.new(feet + Vector3.new(0, c.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	c.model:SetAttribute("NpcYaw", math.floor(yaw * 10 + 0.5) / 10)
end

-- walk a polyline of feet points; nextState after arrival (the client interpolates on the server clock)
local function walk(c: any, pts: { Vector3 }, nextState: string, endYaw: number?)
	local clean = { c.pos }
	for _, p in pts do
		if (p - clean[#clean]).Magnitude > 0.3 then
			table.insert(clean, p)
		end
	end
	if #clean < 2 then
		-- already there: arrive on the next step (so the arrival logic runs)
		c.state = "walk"
		c.arriveAt = os.clock()
		c.nextState = nextState
		if endYaw then
			c.yaw = endYaw
		end
		return
	end
	local speed = C.CUSTOMERS.walkSpeed * (c.pdef.walk or 1)
	local len = 0
	for i = 2, #clean do
		len += (clean[i] - clean[i - 1]).Magnitude
	end
	local buf = { "P", string.format("%.2f", workspace:GetServerTimeNow()), string.format("%.3f", speed) }
	for _, p in clean do
		table.insert(buf, string.format("%.1f,%.2f,%.1f", p.X, p.Y, p.Z))
	end
	setAct(c, "walk")
	c.model:SetAttribute("NpcLeg", table.concat(buf, ";"))
	c.state = "walk"
	c.nextState = nextState
	c.arriveAt = os.clock() + len / speed + 0.15
	local last = clean[#clean]
	local dir = last - clean[#clean - 1]
	c.pos = last
	c.yaw = endYaw or (if dir.Magnitude > 0.1 then yawOf(dir) else c.yaw)
end

local function arrive(c: any)
	c.model:SetAttribute("NpcLeg", "")
	placeAt(c, c.pos, c.yaw)
end

local function sayText(c: any, text: string?, dur: number?)
	if not c.ui then
		return
	end
	if not text or text == "" then
		c.ui.say.Visible = false
		c.ui.say.Text = ""
		c.sayUntil = nil
		return
	end
	c.ui.say.Text = text
	c.ui.say.Visible = true
	c.sayUntil = os.clock() + (dur or math.clamp(2.5 + #text / 14, 3, 7))
	c.model:SetAttribute("NpcTalk", 1)
	c.talkUntil = os.clock() + 1.6
end

local function say(c: any, situation: string, vars: any?, dur: number?): string?
	if not Lines then
		return nil
	end
	local text = Lines.pick(c.site.memo, c.persona, situation, rand, vars)
	if text then
		sayText(c, text, dur)
	end
	return text
end

local function tagText(c: any): string
	local pd = c.pdef
	local base = string.format("%s %s", pd.icon or "🙂", pd.label or "손님")
	if c.orderId then
		local o = Orders.get(c.orderId)
		if o and o.number then
			base ..= string.format(" · #%d", o.number)
		end
	end
	if c.leader then
		base = string.format("%s %s (일행)", pd.icon or "🙂", pd.label or "손님")
	end
	return base
end

-------------------------------------------------------------------------------------------------
-- Sites
-------------------------------------------------------------------------------------------------
local function pickPersona(store: any, wantGroup: boolean?): string
	if wantGroup then
		return "student"
	end
	local list = {}
	local total = 0
	local night = false
	pcall(function()
		local t = Lighting.ClockTime
		night = t >= 20 or t < 5
	end)
	for id, p in C.CUSTOMERS.personas do
		local w = p.weight or 1
		if id == "drunk" and night then
			w *= p.night or 1
		end
		if p.level and (store.level or 1) < p.level then
			w = 0
		end
		if w > 0 then
			table.insert(list, { id = id, w = w })
			total += w
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	local r = rng:NextNumber() * total
	for _, e in list do
		r -= e.w
		if r <= 0 then
			return e.id
		end
	end
	return "normal"
end

local function siteOf(storeId: string): any?
	return sites[storeId]
end

local function queueTaken(site: any): { [number]: any }
	local out = {}
	for _, c in site.customers do
		if c.slot then
			out[c.slot] = c
		end
	end
	return out
end

local function hook(site: any, name: string, ...: any): (boolean, any, any)
	local K = site.store.K
	local fn = K and K[name]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(fn, site.store, ...)
	if not ok then
		warn("[GwangalliWork] customers hook " .. name .. ": " .. tostring(a))
		return false, nil, nil
	end
	return true, a, b
end

local function despawn(site: any, c: any)
	local i = table.find(site.customers, c)
	if i then
		table.remove(site.customers, i)
	end
	c.gone = true
	sayText(c, nil)
	if c.ui then
		c.ui.bar.Visible = false
		c.ui.tag.Text = ""
	end
	c.model.Parent = parkFolder()
	c.model:SetAttribute("NpcLeg", "")
	table.insert(site.pool, { model = c.model, root = c.root, head = c.head, ground = c.ground, ui = c.ui })
end

local function exitPath(site: any, c: any): { Vector3 }
	local d = site.def
	local pts = {}
	if d.exitVia then
		for _, p in d.exitVia do
			table.insert(pts, p)
		end
	elseif d.queue[1] and (c.pos - d.door_in).Magnitude > 6 then
		-- pass in front of the counter line, then the door
		local mid = d.queue[#d.queue] or d.door_in
		table.insert(pts, mid)
	end
	table.insert(pts, d.door_in)
	table.insert(pts, d.door_out)
	return pts
end

local function leave(c: any, situation: string?, vars: any?)
	if c.leaving then
		return
	end
	c.leaving = true
	c.slot = nil
	c.holding = nil
	if situation then
		say(c, situation, vars)
	end
	if c.ui then
		c.ui.bar.Visible = false
	end
	hook(c.site, "customerEvent", c, "leave")
	walk(c, exitPath(c.site, c), "gone")
	-- followers go with the leader
	for _, f in c.followers or {} do
		if not f.leaving and not f.gone then
			f.leaving = true
			walk(f, exitPath(f.site, f), "gone")
		end
	end
end

local function advanceQueue(site: any)
	local slots = site.def.queue
	local taken = queueTaken(site)
	for i = 2, #slots do
		local c = taken[i]
		if c and not taken[i - 1] and not c.leaving and (c.state == "queue" or c.state == "walk") then
			c.slot = i - 1
			taken[i - 1], taken[i] = c, nil
			walk(c, { slots[i - 1] }, "queue", yawOf(site.def.face))
		end
	end
end

local function followerSpot(c: any, idx: number): Vector3
	local d = c.site.def
	local face = d.face or Vector3.new(0, 0, 1)
	local side = Vector3.new(-face.Z, 0, face.X)
	if side.Magnitude < 0.1 then
		side = Vector3.new(1, 0, 0)
	end
	side = side.Unit
	return c.pos + side * (1.9 * idx) - face.Unit * 0.6
end

local moveFollowersLater: (c: any) -> ()
local spawnFollowers: (site: any, c: any) -> ()

-- spawn a customer at the door (persona = nil: random by weight). opts = { purpose, group }
local function spawn(site: any, persona: string?, opts: any?): any?
	local maxN = C.CUSTOMERS.maxPerStore
	if #site.customers >= maxN then
		return nil
	end
	local o = opts or {}
	local pid = persona or pickPersona(site.store, o.group)
	local pdef = C.CUSTOMERS.personas[pid] or C.CUSTOMERS.personas.normal
	local rec = table.remove(site.pool)
	if rec and Looks and type(Looks.restyle) == "function" and rng:NextNumber() < 0.7 then
		custSerial += 1
		pcall(function()
			Looks.restyle({ model = rec.model }, Looks.random(custSerial * 104729 + rand(9999), { age = AGE_HINT[pid] }), "WorkCustomer")
		end)
	end
	if not rec then
		rec = newRig(pid)
		if not rec then
			return nil
		end
	end
	site.serial += 1
	local def = site.def
	local c: any = {
		id = string.format("wc_%s_%d", site.store.id, site.serial),
		site = site,
		model = rec.model,
		root = rec.root,
		head = rec.head,
		ground = rec.ground,
		ui = rec.ui,
		persona = pid,
		pdef = pdef,
		state = "walk",
		pos = def.door_out,
		yaw = yawOf(def.door_in - def.door_out),
		slot = nil,
		joinedAt = os.clock(),
		queueSince = nil,
		lastNag = os.clock(),
		purpose = o.purpose,
		forceWander = o.wander == true,
		followers = {},
	}
	if not c.ui and c.head then
		c.ui = buildBubble(c.head)
		rec.ui = c.ui
	end
	c.model:SetAttribute("NpcId", c.id)
	c.model:SetAttribute("WorkStore", site.store.id)
	c.model:SetAttribute("WorkPersona", pid)
	c.model:SetAttribute("NpcEmote", "")
	c.model.Name = "WorkCustomer_" .. c.id
	placeAt(c, def.door_out, c.yaw)
	c.model.Parent = npcFolder()
	if c.ui then
		c.ui.tag.Text = tagText(c)
		c.ui.bar.Visible = false
		sayText(c, nil)
	end
	table.insert(site.customers, c)
	if not c.purpose then
		local ok, pur = hook(site, "customerPurpose", c, rand)
		if ok then
			c.purpose = pur
		end
	end
	-- walk in: browse first (most), or straight to the queue
	local browse = def.browse or {}
	if #browse > 0 and c.purpose == nil and (c.forceWander or rng:NextNumber() < 0.85) then
		local b = browse[rand(#browse)]
		local pts = { def.door_in }
		for _, p in b.path or {} do
			table.insert(pts, p)
		end
		-- a drunk takes a detour
		if pdef.wander then
			table.insert(pts, def.door_in + (b.pos - def.door_in) * 0.5 + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)))
		end
		table.insert(pts, b.pos)
		c.browseAt = b
		walk(c, pts, "browse", if b.face then yawOf(b.face) else nil)
	else
		walk(c, { def.door_in }, "toqueue")
	end
	if rng:NextNumber() < 0.5 then
		say(c, "enter")
	end
	hook(site, "customerEvent", c, "arrive")
	return c
end

local function toQueue(c: any)
	local site = c.site
	local slots = site.def.queue
	local taken = queueTaken(site)
	local free = nil
	for i = 1, #slots do
		if not taken[i] then
			free = i
			break
		end
	end
	if not free then
		-- queue full: look around a little longer
		c.state = "browse"
		c.waitUntil = os.clock() + 4
		setAct(c, "look")
		return
	end
	c.slot = free
	c.queueSince = c.queueSince or os.clock()
	walk(c, { slots[free] }, "queue", yawOf(site.def.face))
	moveFollowersLater(c)
end

moveFollowersLater = function(c: any)
	-- followers line up beside the leader after the leader's leg (their own leg starts now, slower)
	for i, f in c.followers or {} do
		if not f.leaving and not f.gone then
			local spot = followerSpot({ pos = c.pos, site = c.site }, i)
			walk(f, { spot }, "follow", c.yaw)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Ordering
-------------------------------------------------------------------------------------------------
local function patienceFor(site: any, c: any, nItems: number): number
	local kind = site.store.K.kind
	local CK = C[string.upper(kind)] or C.CAFE
	local p = (CK.patience.base + CK.patience.perItem * nItems) * (c.pdef.patience or 1)
	return math.floor(p)
end

local function placeOrder(c: any)
	local site = c.site
	local store = site.store
	if c.orderId then
		return
	end
	local specs, extra = nil, nil
	local ok, a, b = hook(site, "customerOrder", c, rand)
	if ok then
		specs, extra = a, b
	end
	if not specs then
		local okG, res = pcall(store.K.genOrder, store, rand, store.level or 1, #(c.followers or {}) > 0, c)
		specs = if okG then res else nil
	end
	if type(specs) ~= "table" or #specs == 0 then
		say(c, "leave")
		leave(c, nil)
		return
	end
	local info = {
		source = "npc",
		name = string.format("%s %s", c.pdef.icon or "🙂", c.pdef.label or "손님"),
		patience = patienceFor(site, c, #specs),
		persona = c.persona,
		strict = c.pdef.strict == true,
		group = #(c.followers or {}) > 0 or #specs >= 3,
	}
	if type(extra) == "table" then
		for k, v in extra do
			info[k] = v
		end
	end
	local o, err = Orders.placeOrder(store.id, c.id, specs, info)
	if not o then
		warn("[GwangalliWork] customer order refused: " .. tostring(err))
		leave(c, "leave")
		return
	end
	c.orderId = o.id
	c.orderedAt = os.clock()
	c.state = "ordering"
	setAct(c, "talk")
	if c.ui then
		c.ui.tag.Text = tagText(c)
	end
	local line = nil
	local okL, text = hook(site, "orderLine", o, c)
	if okL and type(text) == "string" then
		line = text
	end
	if not line then
		line = say(c, if site.def.orderAtCounter and store.K.kind == "cafe" then "order" else "counter", { order = W.orderSummary(o) }, 6)
	else
		sayText(c, line, 6)
	end
	W.storeToast(store, string.format("🔔 %s %s%s", c.pdef.icon or "", c.pdef.label or "손님", if o.group then string.format(" · 단체 %d개", #o.items) else " 주문"), "order")
end

-------------------------------------------------------------------------------------------------
-- Provider callbacks (WorkOrders)
-------------------------------------------------------------------------------------------------
local function byOrder(site: any, orderId: string): any?
	for _, c in site.customers do
		if c.orderId == orderId then
			return c
		end
	end
	return nil
end

local function workerFor(store: any, o: any): (Player?, any?)
	local p = o and o.worker
	local sess = p and W.session(p)
	if not sess or sess.storeId ~= store.id then
		p = next(store.workers)
		sess = p and W.session(p)
	end
	return p, sess
end

local function onCall(site: any, o: any)
	local c = byOrder(site, o.id)
	if not c or c.leaving then
		return
	end
	if site.def.pickup and site.store.K.kind == "cafe" then
		say(c, "called")
		c.state = "walk"
		c.slot = nil
		local yaw = yawOf(site.def.face)
		walk(c, { site.def.pickup }, "pickup", yaw)
		moveFollowersLater(c)
	end
end

local function onResult(site: any, result: any)
	local c = byOrder(site, result.orderId)
	if not c then
		return
	end
	local o = Orders.get(result.orderId)
	if c.ui then
		c.ui.bar.Visible = false
	end
	if result.remake then
		say(c, "remake")
		emote(c, if c.persona == "karen" then "facepalm" else "shake")
		-- back to waiting for the remake
		c.state = "waitpickup"
		c.waitSince = os.clock()
		setAct(c, "phone")
		return
	end
	local r = result.reaction
	local sit = if r == "thanks" then "thanks" elseif r == "ok" then "ok" elseif r == "complain" then "complain" else "angry"
	if c.persona == "karen" and r == "thanks" and rng:NextNumber() < 0.5 then
		sit = "ok"
	end
	-- the store kind may decide the line (판매 거절 / 환불 거절 ...)
	local forced = o and o.meta and o.meta.line
	if type(forced) == "string" then
		sit = forced
		if forced == "refused" or forced == "refundNo" then
			r = "complain"
		end
	end
	-- 단골: a tip for a good result
	if c.persona == "regular" and r == "thanks" and c.pdef.tip then
		local p, sess = workerFor(site.store, o)
		if p and sess then
			local amt = math.floor(rng:NextInteger(c.pdef.tip[1], c.pdef.tip[2]) / 100) * 100
			W.tip(p, sess, amt, "단골 손님")
			sit = "tip"
		end
	end
	emote(c, if r == "thanks" then (if rng:NextNumber() < 0.5 then "bow" else "wave") elseif r == "ok" then "nod" elseif r == "complain" then "shrug" else "facepalm")
	c.result = result
	-- a short pause at the counter, then out
	c.state = "react"
	c.waitUntil = os.clock() + 1.6
	c.reactLine = sit
	say(c, sit)
end

local function onCancelled(site: any, o: any, reason: string?)
	local c = byOrder(site, o.id)
	if not c then
		return
	end
	if reason == "store closed" then
		leave(c, nil)
	else
		emote(c, "facepalm")
		leave(c, "leave")
	end
	advanceQueue(site)
end

-------------------------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------------------------
function Customers.open(store: any)
	local old = sites[store.id]
	if old then
		-- a quick re-open: the leftover customers of the old site go straight back to the pool
		if old.unregister then
			old.unregister()
		end
		for _, c in table.clone(old.customers) do
			pcall(despawn, old, c)
		end
		Customers._pools = Customers._pools or {}
		Customers._pools[store.id] = old.pool
		sites[store.id] = nil
	end
	local okD, def = pcall(store.K.site, store)
	if not okD or type(def) ~= "table" or not def.door_out or not def.queue or #def.queue == 0 then
		warn("[GwangalliWork] no customer site for " .. store.id .. ": " .. tostring(def))
		return
	end
	local pools = Customers._pools or {}
	local site = { store = store, def = def, customers = {}, pool = pools[store.id] or {}, nextSpawn = os.clock() + 4, serial = (Customers._serials and Customers._serials[store.id]) or 0, memo = {}, unregister = nil }
	site.unregister = Orders.registerProvider(store.id, {
		name = "work-customers",
		onCall = function(o)
			onCall(site, o)
		end,
		onResult = function(result)
			onResult(site, result)
		end,
		onCancelled = function(o, reason)
			onCancelled(site, o, reason)
		end,
	})
	sites[store.id] = site
	if store.K.refreshLights then
		pcall(store.K.refreshLights, store)
	end
end

function Customers.close(store: any)
	local site = sites[store.id]
	if not site then
		return
	end
	if site.unregister then
		site.unregister()
		site.unregister = nil
	end
	site.closed = true
	for _, c in table.clone(site.customers) do
		if not c.leaving then
			leave(c, nil)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------------------------
local function updateBubble(c: any, now: number)
	if not c.ui then
		return
	end
	if c.sayUntil and now >= c.sayUntil then
		sayText(c, nil)
	end
	if c.talkUntil and now >= c.talkUntil then
		c.talkUntil = nil
		c.model:SetAttribute("NpcTalk", 0)
	end
	c.ui.tag.Text = tagText(c)
	-- patience bar while waiting
	local frac = nil
	local o = c.orderId and Orders.get(c.orderId)
	if o and WS.isOpen(o.state) and o.state ~= "ready" then
		frac = 1 - (now - o.createdAt) / math.max(1, o.patience)
	elseif c.queueSince and not c.orderId and c.slot then
		frac = 1 - (now - c.queueSince) / math.max(1, patienceFor(c.site, c, 1))
	end
	if frac and not c.leaving then
		frac = math.clamp(frac, 0, 1)
		c.ui.bar.Visible = true
		c.ui.fill.Size = UDim2.fromScale(frac, 1)
		c.ui.fill.BackgroundColor3 = if frac > 0.5 then Color3.fromRGB(80, 220, 120) elseif frac > 0.25 then Color3.fromRGB(250, 190, 50) else Color3.fromRGB(240, 70, 60)
	else
		c.ui.bar.Visible = false
	end
end

local function nag(c: any, now: number, frac: number)
	local every = C.CUSTOMERS.nagEvery * (c.pdef.nag or 1)
	if now - c.lastNag < every then
		return
	end
	if c.persona == "hurry" or c.persona == "karen" or (frac < 0.4 and not c.naggedLow) then
		c.lastNag = now
		c.naggedLow = frac < 0.4 or c.naggedLow
		say(c, "nag")
		if c.persona == "hurry" and rng:NextNumber() < 0.4 then
			emote(c, "stop_hand")
		end
	elseif rng:NextNumber() < 0.15 then
		c.lastNag = now
		say(c, "wait")
	end
end

local function stepCustomer(site: any, c: any, now: number)
	local store = site.store
	if c.leader and not c.leaving and (c.leader.gone or c.leader.leaving) then
		leave(c, nil)
		return
	end
	if c.state == "walk" then
		if now >= c.arriveAt then
			arrive(c)
			local nxt = c.nextState
			c.nextState = nil
			if nxt == "gone" then
				despawn(site, c)
				return
			elseif nxt == "browse" then
				c.state = "browse"
				c.waitUntil = now + rng:NextNumber(3, 6) * (if c.persona == "drunk" then 1.6 else 1)
				setAct(c, "look")
				hook(site, "customerBrowse", c, rand)
				if rng:NextNumber() < 0.45 then
					say(c, "browse")
				end
			elseif nxt == "toqueue" then
				toQueue(c)
			elseif nxt == "queue" then
				c.state = "queue"
				setAct(c, if c.slot == 1 then "idle" else "phone")
			elseif nxt == "towait" then
				c.state = "waitpickup"
				c.waitSince = now
				setAct(c, "phone")
			elseif nxt == "pickup" then
				c.state = "pickup"
				setAct(c, "idle")
				local o = c.orderId and Orders.get(c.orderId)
				if o and o.state == "ready" then
					Orders.receive(o.id)
				elseif not o or not WS.isOpen(o.state) then
					leave(c, nil)
				else
					c.state = "waitpickup"
					c.waitSince = now
				end
			elseif nxt == "follow" then
				c.state = "follow"
				setAct(c, "phone")
			else
				c.state = nxt or "browse"
			end
		end
		return
	end
	if c.state == "browse" then
		if site.closed then
			leave(c, nil)
		elseif c.pdef.wander and not c.wandered and (c.forceWander or rng:NextNumber() < 0.35) then
			-- a drunk wanders off somewhere first
			c.wandered = true
			local b = site.def.browse and site.def.browse[rand(#site.def.browse)]
			local to = (b and b.pos or c.pos) + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			say(c, "wander")
			walk(c, { to }, "browse")
			hook(site, "customerEvent", c, "wander")
		elseif now >= (c.waitUntil or 0) then
			if c.holding then
				c.waitUntil = now + 2
			else
				toQueue(c)
			end
		end
		return
	end
	if c.state == "queue" then
		if site.closed then
			leave(c, nil)
			return
		end
		local pat = patienceFor(site, c, 1)
		local frac = 1 - (now - (c.queueSince or now)) / math.max(1, pat)
		if c.slot == 1 and not c.orderId and site.def.orderAtCounter then
			-- the counter must be free (the previous customer may still be reacting there)
			placeOrder(c)
			return
		end
		if frac <= 0 and not c.orderId then
			emote(c, "facepalm")
			leave(c, "leave")
			advanceQueue(site)
			return
		end
		nag(c, now, frac)
		return
	end
	if c.state == "ordering" then
		local o = c.orderId and Orders.get(c.orderId)
		if not o or not WS.isOpen(o.state) then
			if not c.leaving and c.state ~= "react" then
				leave(c, nil)
				advanceQueue(site)
			end
			return
		end
		local frac = 1 - (now - o.createdAt) / math.max(1, o.patience)
		-- cafe: once the POS took the order, wait near the pick-up counter (frees the line)
		if store.K.kind == "cafe" and o.confirmed then
			local spots = site.def.pickupWait or {}
			local used = {}
			for _, x in site.customers do
				if x ~= c and x.waitSpot then
					used[x.waitSpot] = true
				end
			end
			local idx = 1
			for i = 1, #spots do
				if not used[i] then
					idx = i
					break
				end
			end
			c.waitSpot = idx
			c.slot = nil
			local spot = spots[idx] or site.def.pickup or c.pos
			if o.state == "ready" then
				walk(c, { site.def.pickup or spot }, "pickup", yawOf(site.def.face))
			else
				walk(c, { spot }, "towait", yawOf(site.def.face))
			end
			moveFollowersLater(c)
			advanceQueue(site)
			-- a drunk changes the order now and then
			if c.persona == "drunk" and store.K.changeSpec and rng:NextNumber() < 0.35 then
				task.delay(rng:NextNumber(6, 12), function()
					if c.gone or c.leaving or not WS.isOpen(o.state) or o.state == "ready" or o.changed then
						return
					end
					for i, it in o.items do
						if not it.itemId then
							local okC, new, text = pcall(store.K.changeSpec, it.spec, rand, store.level or 1)
							if okC and new and Orders.change(o, i, new, text) then
								say(c, "change")
								W.storeToast(store, string.format("✏️ #%d %s: \"%s\"", o.number, c.pdef.label, text or "주문 바꿀게요"), "change")
								for _, item in store.items do
									if item.orderId == o.id and item.itemIndex == i then
										item.spec = new
									end
								end
								break
							end
						end
					end
				end)
			end
			return
		end
		nag(c, now, frac)
		return
	end
	if c.state == "waitpickup" then
		local o = c.orderId and Orders.get(c.orderId)
		if not o or not WS.isOpen(o.state) then
			if not c.leaving then
				leave(c, nil)
			end
			return
		end
		if o.state == "ready" and not c.leaving then
			walk(c, { site.def.pickup or c.pos }, "pickup", yawOf(site.def.face))
			return
		end
		local frac = 1 - (now - o.createdAt) / math.max(1, o.patience)
		nag(c, now, frac)
		if c.state == "waitpickup" and rng:NextNumber() < 0.01 then
			say(c, "waitPickup")
		end
		return
	end
	if c.state == "react" then
		if now >= (c.waitUntil or 0) then
			c.state = "done"
			leave(c, nil)
			advanceQueue(site)
		end
		return
	end
	if c.state == "trouble" then
		-- held by the store kind (취객 소동 / 환불 실랑이); released through Customers.release
		if now - (c.troubleSince or now) > 9 and rng:NextNumber() < 0.08 then
			say(c, if c.persona == "karen" then "argue" else "trouble")
		end
		return
	end
end

-- 학생 무리: 1-2 friends walk in behind the leader and wait beside them
spawnFollowers = function(site: any, c: any)
	local n = rng:NextInteger(c.pdef.group[1], c.pdef.group[2]) - 1
	for k = 1, n do
		if #site.customers >= C.CUSTOMERS.maxPerStore then
			break
		end
		local f = spawn(site, "student", { purpose = "follow" })
		if f then
			f.leader = c
			table.insert(c.followers, f)
			f.state = "walk"
			walk(f, { site.def.door_in, followerSpot({ pos = site.def.door_in + (c.browseAt and (c.browseAt.pos - site.def.door_in) * 0.6 or Vector3.zero), site = site }, k) }, "follow")
		end
	end
end

function Customers.tick(now: number)
	if now - lastStateTick < 0.25 then
		return
	end
	lastStateTick = now
	local bubbles = now - lastBubbleTick >= 1
	if bubbles then
		lastBubbleTick = now
	end
	for id, site in sites do
		local store = site.store
		for i = #site.customers, 1, -1 do
			local c = site.customers[i]
			if c then
				local ok, err = pcall(stepCustomer, site, c, now)
				if not ok then
					warn("[GwangalliWork] customer " .. tostring(c.id) .. ": " .. tostring(err))
					pcall(despawn, site, c)
				elseif bubbles and not c.gone then
					pcall(updateBubble, c, now)
				end
			end
		end
		-- spawning while the store is open (no new customers in the last-order window)
		if not site.closed and store.open and now >= site.nextSpawn then
			local phase = W.phaseOf(store)
			local gap = C.CUSTOMERS.spawnGap[phase] or C.CUSTOMERS.spawnGap.rush
			site.nextSpawn = now + rng:NextNumber(gap[1], gap[2])
			local open = Orders.open(store.id)
			local CK = C[string.upper(store.K.kind)] or C.CAFE
			local inQueue = 0
			for _, c in site.customers do
				if not c.leaving and not c.leader then
					inQueue += 1
				end
			end
			local lastCall = false
			local lead = nil
			for _, s in store.workers do
				if s.startedAt and (not lead or s.startedAt < lead.startedAt) then
					lead = s
				end
			end
			if lead and now - lead.startedAt >= lead.length * C.SHIFT.lastOrderShare then
				lastCall = true
			end
			if not lastCall and #open < (CK.maxOpenOrders or 3) and inQueue < 3 and #site.customers < C.CUSTOMERS.maxPerStore then
				local persona = pickPersona(store)
				local c = spawn(site, persona)
				if c and c.pdef.group then
					spawnFollowers(site, c)
				end
			end
		end
		if site.closed and #site.customers == 0 then
			sites[id] = nil
			-- keep the parked pool (and the id serial) for the next opening
			Customers._pools = Customers._pools or {}
			Customers._pools[id] = site.pool
			Customers._serials = Customers._serials or {}
			Customers._serials[id] = site.serial
		end
		local _ = id
	end
end

-------------------------------------------------------------------------------------------------
-- API for the store kinds
-------------------------------------------------------------------------------------------------
local function find(storeId: string, customerId: any): any?
	local site = sites[storeId]
	if not site then
		return nil
	end
	for _, c in site.customers do
		if c.id == customerId then
			return c
		end
	end
	return nil
end

function Customers.get(storeId: string, customerId: any): any?
	return find(storeId, customerId)
end

function Customers.byOrder(storeId: string, orderId: string): any?
	local site = sites[storeId]
	return site and byOrder(site, orderId) or nil
end

function Customers.say(storeId: string, customerId: any, situation: string, vars: any?, dur: number?): string?
	local c = find(storeId, customerId)
	return c and say(c, situation, vars, dur) or nil
end

function Customers.sayText(storeId: string, customerId: any, text: string, dur: number?)
	local c = find(storeId, customerId)
	if c then
		sayText(c, text, dur)
	end
end

function Customers.emote(storeId: string, customerId: any, name: string)
	local c = find(storeId, customerId)
	if c then
		emote(c, name)
	end
end

function Customers.setAct(storeId: string, customerId: any, act: string)
	local c = find(storeId, customerId)
	if c then
		setAct(c, act)
	end
end

-- keep a customer where they are (trouble / argument) until release
function Customers.hold(storeId: string, customerId: any, on: boolean)
	local c = find(storeId, customerId)
	if not c then
		return
	end
	if on then
		c.holding = true
		if c.state ~= "walk" then
			c.state = "trouble"
		else
			c.nextState = "trouble"
		end
		c.troubleSince = os.clock()
	else
		c.holding = nil
		if c.state == "trouble" then
			c.state = if c.orderId then "ordering" else "browse"
			c.waitUntil = os.clock() + 1
		end
	end
end

-- the customer leaves now (situation = the line on the way out)
function Customers.release(storeId: string, customerId: any, situation: string?, vars: any?)
	local c = find(storeId, customerId)
	if not c then
		return
	end
	leave(c, situation, vars)
	advanceQueue(c.site)
end

-- an event customer (진상 환불 · 택배 손님 · 학생 무리 ...) -> customer?
function Customers.spawn(store: any, persona: string?, opts: any?): any?
	local site = sites[store.id]
	if not site or site.closed then
		return nil
	end
	local c = spawn(site, persona, opts)
	if c and c.pdef.group and not (opts and opts.purpose == "follow") then
		spawnFollowers(site, c)
	end
	return c
end

function Customers.count(storeId: string): number
	local site = sites[storeId]
	return site and #site.customers or 0
end

function Customers.active(storeId: string): boolean
	local site = sites[storeId]
	return site ~= nil and not site.closed
end

-- the customer at the counter (queue slot 1, arrived) -> customer?
function Customers.atCounter(storeId: string): any?
	local site = sites[storeId]
	if not site then
		return nil
	end
	for _, c in site.customers do
		if c.slot == 1 and c.state ~= "walk" and not c.leaving then
			return c
		end
	end
	return nil
end

function Customers.debug(storeId: string): any
	local site = sites[storeId]
	if not site then
		return "no site"
	end
	local out = {}
	for _, c in site.customers do
		table.insert(out, string.format("%s %s %s slot=%s order=%s", c.id, c.persona, c.state, tostring(c.slot), tostring(c.orderId)))
	end
	return table.concat(out, "\n")
end

-- every site's customer list (tests)
Customers.sites = sites
local _ = Players

return Customers
