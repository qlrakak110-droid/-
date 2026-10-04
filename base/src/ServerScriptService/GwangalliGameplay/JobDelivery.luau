--!nocheck
-- GwangalliGameplay/JobDelivery: 광안 딜리버리 (docs/DESIGN_JOBS.md 배달, docs/JOBS.md). Required and
-- driven by Jobs.luau (its 0.5 s tick calls JobDelivery.tick). Office anchors come from
-- build/venues/delivery.luau (GwJobStation, Job = "delivery": dispatch / shelf / dock / pad / exit).
--   * DISPATCH TABLE (prompt on the "dispatch" anchor): JobGame {op = "dispatch"} -> the client shows
--     퀵 / 택배 cards -> {op = "dispatchPick", mode} -> Jobs.apply(delivery_quick | delivery_parcel) +
--     Jobs.startShift (the office is the clock-in place, so the shift starts at the table)
--   * 퀵 (delivery_quick): task "pickup" (office shelf prompt) assigns a downtown order
--     ("<건물> <호수> - 배달요망" in the phone navigation), a parcel box goes into the hands; task
--     "handover": a recipient NPC waits at the building entrance with a "택배 전달" prompt (only the
--     courier can use it) -> paid (distance + tip within the time limit) -> back to the office
--   * 택배 (delivery_parcel): task "load" (dock prompt) spawns the 탑차 through
--     ServerStorage.GwangalliEvents.SpawnJobVehicle(player, "parcel_truck", padCFrame) (pcall; without
--     the garage module the route still works on foot / any car) and plans 4 drops all over the map;
--     tasks "ring": a translucent ring (drawn by the client) in front of the building, snapped to the
--     nearest road lane; the drop completes automatically when the truck (or the courier) is inside;
--     final "goto pad" returns the truck. RED LIGHTS: while driving, crossing the stop line of a
--     signalised approach whose phase is red (TrafficSignal housings: Group + SignalPhase, timing from
--     GwangalliShared.vehicleState) with a grace second and a heading check (right turns are legal)
--     costs JS.DELIVERY_MODES.parcel.redLightFine, taken from the next drop's pay.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JobDelivery = {}

local ctx: any
local G: any
local JS: any
local Jobs: any
local World: any
local Util: any
local remote: RemoteEvent? = nil

local Shared: any = nil -- GwangalliShared (signal timing)
local Nav: any = nil
local navTried = false
local Looks: any = nil

local OFFICE = "광안 딜리버리"

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function send(player: Player, payload: any)
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function officePos(): Vector3?
	local p = ctx.dest(OFFICE)
	if p then
		return p.Position
	end
	local st = World.station("delivery", "dispatch")
	return st and st.Position or nil
end

local function nav(): any
	if navTried then
		return Nav
	end
	navTried = true
	local m = ReplicatedStorage:FindFirstChild("GwangalliNav")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and type(res.decode) == "function" then
			local ok2, dec = pcall(res.decode)
			if ok2 and type(dec) == "table" and dec.lanePos then
				Nav = dec
			end
		end
	end
	return Nav
end

-- nearest road-lane point to `pos` within `radius` (flat distance), else nil
local function nearestLane(pos: Vector3, radius: number): Vector3?
	local N = nav()
	if not N then
		return nil
	end
	local best, bd = nil, radius * radius
	for _, p in N.lanePos do
		local dx, dz = p.X - pos.X, p.Z - pos.Z
		local d2 = dx * dx + dz * dz
		if d2 < bd then
			best, bd = p, d2
		end
	end
	return best
end

local function groundUnder(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = Util.charactersIgnore({})
	params.IgnoreWater = true
	local ok, hit = pcall(function()
		return workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
	end)
	if ok and hit then
		return hit.Position
	end
	return pos
end

local function levelMult(jobId: string, d: any): number
	local job = G.JOBS[jobId]
	local lv = G.jobLevel(jobId, d.careerXp[jobId] or 0)
	local base = job.levels[1].wage
	return G.jobWage(jobId, lv) / math.max(1, base)
end

-- all Destinations as { name, part } (server sees every one)
local function destinations(): { any }
	local out = {}
	local seen = {}
	for _, p in CollectionService:GetTagged("Destination") do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			local name = p:GetAttribute("DisplayName")
			if type(name) == "string" and name ~= "" and not seen[name] and name ~= OFFICE then
				seen[name] = true
				table.insert(out, { name = name, part = p })
			end
		end
	end
	return out
end

local BAD_DEST = { "해수욕장", "바다", "해변", "대교", "상판", "수변공원", "요트" }
local function okDest(name: string): boolean
	for _, w in BAD_DEST do
		if string.find(name, w, 1, true) then
			return false
		end
	end
	return true
end

-- picks n drop-offs for a mode: { name, pos (ground at the building), ring? (lane point), dist }
local function planDrops(mode: string, n: number, rand: Random): { any }
	local m = JS.DELIVERY_MODES[mode]
	local origin = officePos()
	if not origin then
		return {}
	end
	local cands = {}
	for _, d in destinations() do
		if okDest(d.name) then
			local dist = flat(d.part.Position - origin).Magnitude
			if dist >= m.minDist and dist <= m.maxDist then
				table.insert(cands, { name = d.name, part = d.part, dist = dist })
			end
		end
	end
	if #cands < n then
		-- small maps (subset builds): relax the distance window
		for _, d in destinations() do
			local dist = flat(d.part.Position - origin).Magnitude
			if dist >= 40 then
				local dup = false
				for _, c in cands do
					if c.name == d.name then
						dup = true
					end
				end
				if not dup then
					table.insert(cands, { name = d.name, part = d.part, dist = dist })
				end
			end
		end
	end
	-- shuffle, then keep drops at least 120 studs apart
	for i = #cands, 2, -1 do
		local j = rand:NextInteger(1, i)
		cands[i], cands[j] = cands[j], cands[i]
	end
	local out = {}
	for _, c in cands do
		if #out >= n then
			break
		end
		local okSep = true
		for _, o in out do
			if flat(o.pos - c.part.Position).Magnitude < 120 then
				okSep = false
				break
			end
		end
		if okSep or #cands < n * 2 then
			local pos = groundUnder(c.part.Position)
			local ring = nil
			if mode == "parcel" then
				local lane = nearestLane(pos, 70)
				ring = if lane then groundUnder(lane) else pos
			end
			table.insert(out, { name = c.name, pos = pos, ring = ring, dist = c.dist })
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Recipient NPCs (퀵): one per active order, pooled
-------------------------------------------------------------------------------------------------
local recipientPool: { any } = {}

local function looks(): any
	if Looks then
		return Looks
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			Looks = res
		end
	end
	return Looks
end

local function npcFolder(): Folder
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	return f :: Folder
end

local recSerial = 0
local function removeRecipient(s: any)
	local r = s.recipient
	if not r then
		return
	end
	s.recipient = nil
	if r.prompt then
		r.prompt:Destroy()
	end
	r.model.Parent = nil
	table.insert(recipientPool, r)
end

local function spawnRecipient(player: Player, s: any, order: any)
	removeRecipient(s)
	local r = table.remove(recipientPool)
	if not r then
		local L = looks()
		if not L then
			return
		end
		recSerial += 1
		local okS, spec = pcall(L.random, 50000 + recSerial * 31 + math.random(1, 999), {})
		if not okS then
			return
		end
		local okB, rig = pcall(L.build, spec, { name = "Recipient", anchored = true })
		if not okB or not rig then
			return
		end
		rig.model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		rig.model:SetAttribute("NpcKind", "shop")
		rig.model:SetAttribute("NpcGround", rig.ground or 3)
		r = { model = rig.model, root = rig.root, ground = rig.ground or 3 }
	end
	recSerial += 1
	local model = r.model
	model:SetAttribute("NpcId", "recipient_" .. recSerial)
	model:SetAttribute("NpcAct", "phone")
	model:SetAttribute("NpcLeg", "")
	model:SetAttribute("NpcEmote", "")
	model:SetAttribute("NpcLook", player.UserId)
	model:SetAttribute("ShopSay", "")
	model:SetAttribute("DeliveryFor", player.UserId)
	model.Name = "Recipient_" .. player.UserId
	-- stand at the building entrance, facing the street (away from the building centre when we can)
	local feet = order.pos
	local face = Vector3.new(0, 0, -1)
	local origin = officePos()
	if origin then
		local d = flat(origin - feet)
		if d.Magnitude > 1 then
			face = d.Unit
		end
	end
	local yaw = math.deg(math.atan2(-face.X, -face.Z))
	r.root.CFrame = CFrame.new(feet + Vector3.new(0, r.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	model:SetAttribute("NpcYaw", yaw)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GwangalliHandoverPrompt"
	prompt.ActionText = "택배 전달"
	prompt.ObjectText = string.format("📦 %s 손님", tostring(order.room or order.name))
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = r.root
	r.prompt = prompt
	prompt.Triggered:Connect(function(who: Player)
		if who ~= player then
			return
		end
		local cur = Jobs.shifts[player]
		if cur ~= s or not s.task or s.task.kind ~= "handover" or s.recipient ~= r then
			return
		end
		local ok, err = pcall(JobDelivery.completeDrop, player, s, r.root.Position)
		if not ok then
			warn("[GwangalliGameplay] handover failed: " .. tostring(err))
		end
	end)
	model.Parent = npcFolder()
	s.recipient = r
	r.greeted = false
end

-------------------------------------------------------------------------------------------------
-- Truck (택배)
-------------------------------------------------------------------------------------------------
local function events(): Instance?
	return ServerStorage:FindFirstChild("GwangalliEvents")
end

local function spawnTruck(player: Player, s: any): boolean
	local ev = events()
	local fn = ev and ev:FindFirstChild("SpawnJobVehicle")
	if not fn or not fn:IsA("BindableFunction") then
		return false
	end
	local pad = World.station("delivery", "pad")
	local cf = pad and pad.CFrame * CFrame.new(0, -0.5, 0) or nil
	local ok, model = pcall(function()
		return fn:Invoke(player, "parcel_truck", cf)
	end)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		s.truck = model
		return true
	end
	if not ok then
		warn("[GwangalliGameplay] SpawnJobVehicle failed: " .. tostring(model))
	end
	return false
end

function JobDelivery.despawnTruck(player: Player, s: any)
	local ev = events()
	if ev then
		local de = ev:FindFirstChild("DespawnJobVehicle")
		if de and de:IsA("BindableFunction") then
			pcall(function()
				de:Invoke(player)
			end)
		elseif s.truck then
			local fn = ev:FindFirstChild("SpawnJobVehicle")
			if fn and fn:IsA("BindableFunction") then
				pcall(function()
					fn:Invoke(player, nil)
				end)
			end
		end
	end
	if s.truck and s.truck.Parent then
		pcall(function()
			s.truck:Destroy()
		end)
	end
	s.truck = nil
end

-- the courier's vehicle (any seat), or nil on foot
local function vehicleOf(player: Player): (Model?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat then
		local m = seat:FindFirstAncestorOfClass("Model")
		return m, seat
	end
	return nil, nil
end

-------------------------------------------------------------------------------------------------
-- Tasks (called from Jobs.luau)
-------------------------------------------------------------------------------------------------
-- a new task of this module became current
function JobDelivery.setTask(player: Player, s: any, t: any)
	if t.kind == "handover" then
		local o = s.delivery
		if not o then
			return
		end
		t.dest = o.name
		t.prompt = o.room
		t.position = o.pos
		t.timeLimit = o.timeLimit
		spawnRecipient(player, s, o)
		send(player, { op = "delivery", phase = "deliver", mode = "quick", order = o, timeLimit = o.timeLimit })
	elseif t.kind == "ring" then
		local o = s.route and s.route[s.routeIndex]
		if not o then
			return
		end
		s.delivery = o
		t.dest = o.name
		t.prompt = o.room
		t.position = o.ring or o.pos
		t.timeLimit = o.timeLimit
		send(player, { op = "delivery", phase = "deliver", mode = "parcel", order = o, ring = o.ring or o.pos, radius = t.radius or JS.DELIVERY_MODES.parcel.radius, timeLimit = o.timeLimit, drop = s.routeIndex, drops = #s.route, truck = s.truck ~= nil })
	end
end

local function makeOrder(mode: string, drop: any, d: any, jobId: string, rand: Random): any
	local pay, tip, limit = JS.dropPay(mode, drop.dist)
	local mult = levelMult(jobId, d)
	return {
		name = drop.name,
		room = JS.roomLabel(drop.name, function(n)
			return rand:NextInteger(1, math.max(1, n))
		end),
		pos = drop.pos,
		ring = drop.ring,
		dist = math.floor(drop.dist),
		pay = G.round100(pay * mult),
		tip = G.round100(tip * mult),
		timeLimit = limit,
		mode = mode,
		dish = if mode == "quick" then "퀵 서류봉투" else "택배 상자",
		icon = if mode == "quick" then "📦" else "🚚",
	}
end

-- 퀵: the shelf prompt was held -> an order + the parcel in the hands
function JobDelivery.pickup(player: Player, s: any, t: any): boolean
	local d = ctx.Profiles.get(player)
	if not d then
		return false
	end
	local drops = planDrops("quick", 1, s.rng)
	local drop = drops[1]
	if not drop then
		ctx.notify(player, "job", "배달할 곳이 없어요", "이 지도에는 배달지가 없어요 · 퇴근해 주세요")
		return false
	end
	local o = makeOrder("quick", drop, d, s.jobId, s.rng)
	s.delivery = o
	World.attachCarry(player, s, "parcel", "퀵")
	send(player, { op = "delivery", phase = "picked", mode = "quick", order = o })
	ctx.notify(player, "job", "📦 " .. o.room, string.format("%s까지 %dm · %s%s", o.name, math.floor(o.dist * 0.3), G.format.won(o.pay), if o.tip > 0 then string.format(" (+빠르면 팁 %s)", G.format.won(o.tip)) else ""))
	return true
end

-- 택배: the dock prompt was held -> the truck + the route
function JobDelivery.load(player: Player, s: any, t: any): boolean
	local d = ctx.Profiles.get(player)
	if not d then
		return false
	end
	local n = 0
	for _, tt in s.tasks do
		if tt.kind == "ring" then
			n += 1
		end
	end
	local drops = planDrops("parcel", n, s.rng)
	if #drops == 0 then
		ctx.notify(player, "job", "배달할 곳이 없어요", "이 지도에는 배달지가 없어요 · 퇴근해 주세요")
		return false
	end
	s.route = {}
	for _, dr in drops do
		table.insert(s.route, makeOrder("parcel", dr, d, s.jobId, s.rng))
	end
	s.routeIndex = 1
	-- fewer drops than ring tasks (small maps): drop the extra rings
	local kept = {}
	local rings = 0
	for i, tt in s.tasks do
		if tt.kind == "ring" then
			rings += 1
			if rings > #s.route then
				continue
			end
		end
		table.insert(kept, tt)
		local _ = i
	end
	s.tasks = kept
	local got = spawnTruck(player, s)
	s.noTruck = not got
	send(player, { op = "delivery", phase = "loaded", mode = "parcel", drops = #s.route, truck = got, route = s.route })
	if got then
		ctx.notify(player, "job", "🚚 탑차 준비 완료", string.format("택배 %d건 상차! 차고의 탑차를 타고 출발 · 신호 위반은 -%s", #s.route, G.format.won(JS.DELIVERY_MODES.parcel.redLightFine)))
	else
		ctx.notify(player, "job", "🚚 상차 완료", string.format("택배 %d건 · 지금은 탑차가 없어 아무 차나 도보로 배달해도 돼요", #s.route))
	end
	return true
end

-- pays one drop (퀵 handover or 택배 ring)
function JobDelivery.completeDrop(player: Player, s: any, at: Vector3?)
	local d = ctx.Profiles.get(player)
	local t = s.task
	local o = s.delivery
	if not d or not t or not o then
		return
	end
	local pos = at or Util.rootPosition(player)
	if not pos then
		return
	end
	local elapsed = os.clock() - s.taskStart
	local fast = o.timeLimit ~= nil and elapsed <= o.timeLimit
	local pay = o.pay
	local tip = if fast then o.tip else 0
	if s.teleported then
		pay = G.round100(pay / 2)
		tip = 0
	end
	local mult = Jobs.payMultiplier(player)
	local why = Jobs.healthReason(player, mult)
	local gross = G.round100((pay + tip) * mult)
	local fine = math.min(gross, s.pendingFine or 0)
	s.pendingFine = (s.pendingFine or 0) - fine
	local total = gross - fine
	s.earned += total
	s.combo += 1
	s.maxCombo = math.max(s.maxCombo, s.combo)
	s.rounds += 1
	s.perfect += if fast and fine == 0 then 1 else 0
	Jobs.addXp(player, d, s.jobId, G.TASK_XP)
	removeRecipient(s)
	World.removeCarry(s)
	if t.kind == "handover" and s.lastRecipientModel then
		s.lastRecipientModel = nil
	end
	send(player, {
		op = "result",
		taskId = s.taskId,
		game = "deliver",
		ok = true,
		score = if fast then 1 else 0.7,
		pay = total,
		base = pay,
		tip = tip,
		fine = fine,
		speedBonus = fast,
		combo = s.combo,
		comboMult = 1,
		payMult = mult,
		payReason = why,
		earned = s.earned,
		elapsed = elapsed,
		order = o,
		message = (if fast then "배달 완료! ⚡ 빠른 배달 팁까지" else "배달 완료! 📦") .. (if fine > 0 then string.format(" · 신호 위반 -%s", G.format.won(fine)) else ""),
		last = s.index >= #s.tasks,
	})
	send(player, { op = "delivery", phase = "done", mode = o.mode, order = o })
	ctx.notify(player, "job", string.format("배달 완료 +%s%s", G.format.won(total), if tip > 0 then " (팁!)" else ""), string.format("%s%s%s", o.room, if fine > 0 then string.format(" · 🚦 -%s", G.format.won(fine)) else "", if why then " · " .. why else ""))
	ctx.addStats(player, { stamina = -G.TASK_STAMINA, happiness = 0.5 }, nil, true)
	Jobs.onWork(player, math.min(elapsed, 180), s.jobId)
	if o.mode == "quick" and at then
		-- the recipient thanks you (bubble on the model before it is pooled)
		local _ = at
	end
	s.delivery = nil
	if s.route then
		s.routeIndex = (s.routeIndex or 1) + 1
	end
	if math.random() < 0.35 then
		World.bossLine(player, s.jobId, "good", nil)
	end
	Jobs.advance(player, s)
end

-------------------------------------------------------------------------------------------------
-- Dispatch table
-------------------------------------------------------------------------------------------------
function JobDelivery.openDispatch(player: Player)
	local d = ctx.Profiles.get(player)
	if not d then
		return
	end
	local cur = d.job and d.job.id
	local modes = {}
	for _, key in { "quick", "parcel" } do
		local m = JS.DELIVERY_MODES[key]
		local job = G.JOBS[m.job]
		local lv = G.jobLevel(m.job, d.careerXp[m.job] or 0)
		local lo = G.round100(select(1, JS.dropPay(key, m.minDist)) * G.jobWage(m.job, lv) / job.levels[1].wage)
		local hi = G.round100(select(1, JS.dropPay(key, m.maxDist)) * G.jobWage(m.job, lv) / job.levels[1].wage)
		table.insert(modes, {
			mode = key,
			job = m.job,
			title = m.title,
			icon = m.icon,
			desc = job.desc,
			level = job.levels[lv].title,
			drops = m.drops,
			payRange = string.format("%s ~ %s / 건", G.format.won(lo), G.format.won(hi)),
			current = cur == m.job,
			drive = key == "parcel",
		})
	end
	send(player, { op = "dispatch", modes = modes, onShift = Jobs.onShift(player) })
end

function JobDelivery.pick(player: Player, mode: any)
	local m = type(mode) == "string" and JS.DELIVERY_MODES[mode]
	if not m then
		return
	end
	local st = World.station("delivery", "dispatch")
	local pos = Util.rootPosition(player)
	if not st or not pos or (pos - st.Position).Magnitude > 18 then
		return
	end
	local d = ctx.Profiles.get(player)
	if not d then
		return
	end
	local s = Jobs.shifts[player]
	if s and s.jobId == m.job then
		Jobs.push(player)
		return
	end
	if s then
		Jobs.endShift(player)
	end
	if not d.job or d.job.id ~= m.job then
		Jobs.apply(player, m.job, "dispatch")
	end
	Jobs.startShift(player)
end

-------------------------------------------------------------------------------------------------
-- Red lights (택배)
-------------------------------------------------------------------------------------------------
type Sig = { part: BasePart, pos: Vector3, dir: Vector3, right: Vector3, group: string, stop: number }
local signals: { Sig } = {}
local grid: { [string]: { Sig } } = {}
local CELL = 128
local sigDirty = true

local function cellKey(x: number, z: number): string
	return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

local function rebuildSignals()
	sigDirty = false
	signals = {}
	grid = {}
	local byGroup: { [string]: { Sig } } = {}
	for _, inst in CollectionService:GetTagged("TrafficSignal") do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local look = inst.CFrame.LookVector
			local dir = Vector3.new(look.X, 0, look.Z)
			if dir.Magnitude > 0.1 then
				dir = dir.Unit
				local g = inst:GetAttribute("Group")
				local sg: Sig = { part = inst, pos = inst.Position, dir = dir, right = dir:Cross(Vector3.yAxis), group = if type(g) == "string" then g else "default", stop = 28 }
				table.insert(signals, sg)
				byGroup[sg.group] = byGroup[sg.group] or {}
				table.insert(byGroup[sg.group], sg)
			end
		end
	end
	-- stop line distance: the opposite approach's far-side housing stands about at our stop line
	for _, list in byGroup do
		for _, a in list do
			local best = nil
			for _, b in list do
				if b ~= a and a.dir:Dot(b.dir) < -0.7 then
					local along = math.abs((b.pos - a.pos):Dot(a.dir))
					local lateral = math.abs((b.pos - a.pos):Dot(a.right))
					if along > 10 and along < 90 and lateral < 60 and (not best or along < best) then
						best = along
					end
				end
			end
			if best then
				a.stop = math.clamp(best, 14, 70)
			end
		end
	end
	for _, sg in signals do
		local k = cellKey(sg.pos.X, sg.pos.Z)
		grid[k] = grid[k] or {}
		table.insert(grid[k], sg)
	end
end

local function shared(): any
	if Shared then
		return Shared
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			Shared = res
		end
	end
	return Shared
end

local function nearSignals(p: Vector3): { Sig }
	local out = {}
	local cx, cz = math.floor(p.X / CELL), math.floor(p.Z / CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local l = grid[(cx + dx) .. ":" .. (cz + dz)]
			if l then
				for _, sg in l do
					table.insert(out, sg)
				end
			end
		end
	end
	return out
end

-- red at server time `tNow`, at least `grace` seconds into the red
local traffic: any = nil
local function trafficCfg(): any
	if traffic == nil then
		traffic = false
		local m = ReplicatedStorage:FindFirstChild("GwangalliConfig")
		if m and m:IsA("ModuleScript") then
			local ok, cfg = pcall(require, m)
			if ok and type(cfg) == "table" and type(cfg.Traffic) == "table" then
				traffic = cfg.Traffic
			end
		end
	end
	return traffic or nil
end

local function isRed(sg: Sig, tNow: number, grace: number): boolean
	local S = shared()
	if not S or type(S.vehicleState) ~= "function" then
		return false
	end
	local phase = sg.part:GetAttribute("SignalPhase")
	if phase ~= 0 and phase ~= 1 then
		local ok, ph = pcall(S.fallbackSignalPhase, sg.part.CFrame)
		phase = if ok then ph else 0
	end
	local ok, state = pcall(S.vehicleState, sg.group, phase, tNow)
	if not ok or state ~= "red" then
		return false
	end
	-- red spans signalTime u in [Green + Amber, cycle): require `grace` seconds of it (fair to a car
	-- that entered on amber)
	local T = trafficCfg()
	local ok2, u = pcall(S.signalTime, sg.group, phase, tNow)
	if T and T.Green and T.Amber and ok2 and type(u) == "number" then
		return u - (T.Green + T.Amber) >= grace
	end
	return true
end

-- called every Jobs tick for 택배 couriers (pos = vehicle or root position)
local function redLightCheck(player: Player, s: any, pos: Vector3, now: number)
	if sigDirty then
		rebuildSignals()
	end
	local prev = s.rlPrev
	local prevT = s.rlPrevT
	s.rlPrev = pos
	s.rlPrevT = now
	local m = JS.DELIVERY_MODES.parcel
	-- confirm pending violations (the car went on into the junction, still heading straight)
	if s.rlPending then
		local pnd = s.rlPending
		local mv = flat(pos - pnd.at)
		local along = (pos - pnd.sig.pos):Dot(pnd.sig.dir)
		if mv.Magnitude > 2 and mv.Unit:Dot(pnd.sig.dir) < 0.6 then
			s.rlPending = nil -- turned (a right turn on red is legal)
		elseif along > -pnd.sig.stop * 0.45 then
			s.rlPending = nil
			s.rlCooldown = s.rlCooldown or {}
			if not s.rlCooldown[pnd.sig.group] or now - s.rlCooldown[pnd.sig.group] > m.redLightCooldown then
				s.rlCooldown[pnd.sig.group] = now
				s.pendingFine = (s.pendingFine or 0) + m.redLightFine
				s.redLights = (s.redLights or 0) + 1
				ctx.notify(player, "warn", "🚦 신호 위반!", string.format("배달비 -%s (다음 배달에서 차감)", G.format.won(m.redLightFine)), { sound = "error" })
				send(player, { op = "redlight", fine = m.redLightFine, total = s.redLights, group = pnd.sig.group })
				World.bossSay(player, s.jobId, "신호는 꼭 지키자! 배달비 깎였다 🚦", nil, 3)
			end
		elseif now - pnd.t > 4 then
			s.rlPending = nil
		end
	end
	if not prev or not prevT or now - prevT > 2 then
		return
	end
	local mv = flat(pos - prev)
	local speed = mv.Magnitude / math.max(0.05, now - prevT)
	if speed < m.redLightSpeed then
		return
	end
	local heading = mv.Unit
	local tServer = workspace:GetServerTimeNow()
	for _, sg in nearSignals(pos) do
		if heading:Dot(sg.dir) > 0.8 then
			local rel0 = prev - sg.pos
			local rel1 = pos - sg.pos
			local a0, a1 = rel0:Dot(sg.dir), rel1:Dot(sg.dir)
			local line = -sg.stop
			if a0 < line and a1 >= line and math.abs(rel1:Dot(sg.right)) < 24 then
				-- interpolate the crossing time (server clock)
				local f = (line - a0) / math.max(1e-3, a1 - a0)
				local tCross = tServer - (1 - f) * (now - prevT)
				if isRed(sg, tCross, m.redLightGrace) then
					s.rlPending = { sig = sg, at = pos, t = now }
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------------------------
function JobDelivery.tick(player: Player, s: any, pos: Vector3, now: number)
	local t = s.task
	if not t then
		return
	end
	local car = vehicleOf(player)
	local probe = pos
	if car then
		local okP, piv = pcall(function()
			return car:GetPivot().Position
		end)
		if okP then
			probe = piv
		end
	end
	if s.jobId == "delivery_parcel" and (car or s.noTruck) then
		local ok, err = pcall(redLightCheck, player, s, probe, now)
		if not ok then
			warn("[GwangalliGameplay] red light check: " .. tostring(err))
		end
	end
	if t.kind == "ring" and s.delivery then
		local o = s.delivery
		local target = o.ring or o.pos
		local r = (t.radius or JS.DELIVERY_MODES.parcel.radius)
		local inside = flat(probe - target).Magnitude <= r and math.abs(probe.Y - target.Y) < 16
		local allowed = car ~= nil or s.noTruck or not s.truck or (s.truck and not s.truck.Parent)
		if inside and allowed and now - s.taskStart > 1 then
			JobDelivery.completeDrop(player, s, probe)
		end
	elseif t.kind == "handover" and s.recipient then
		local r = s.recipient
		if not r.greeted and (pos - r.root.Position).Magnitude < 28 then
			r.greeted = true
			World.modelSay(r.model, "여기요~! 📦")
			r.model:SetAttribute("NpcAct", "idle")
		end
	end
end

function JobDelivery.endShift(player: Player, s: any)
	removeRecipient(s)
	if s.truck then
		JobDelivery.despawnTruck(player, s)
	end
	s.route = nil
end

JobDelivery.planDrops = planDrops
JobDelivery.rebuildSignals = rebuildSignals
JobDelivery.signals = function()
	if sigDirty then
		rebuildSignals()
	end
	return signals
end

function JobDelivery.init(context: any, jobsModule: any, worldModule: any, js: any, r: RemoteEvent?)
	ctx = context
	G = context.G
	Util = context.Util
	Jobs = jobsModule
	World = worldModule
	JS = js
	remote = r
	CollectionService:GetInstanceAddedSignal("TrafficSignal"):Connect(function()
		sigDirty = true
	end)
	-- the dispatch table prompt (the office anchor arrives with the map)
	local function hook(inst: Instance)
		if not inst:IsA("BasePart") or inst:GetAttribute("Job") ~= "delivery" or inst:GetAttribute("Station") ~= "dispatch" then
			return
		end
		if inst:FindFirstChild("GwangalliDispatchPrompt") then
			return
		end
		local p = Instance.new("ProximityPrompt")
		p.Name = "GwangalliDispatchPrompt"
		p.ActionText = "퀵 / 택배 고르기"
		p.ObjectText = "🛵 배차 테이블"
		p.HoldDuration = 0.3
		p.MaxActivationDistance = 10
		p.RequiresLineOfSight = false
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.Parent = inst
		p.Triggered:Connect(function(player: Player)
			if Util.cooldown(player, "dispatchOpen", 1) then
				pcall(JobDelivery.openDispatch, player)
			end
		end)
	end
	for _, inst in CollectionService:GetTagged("GwJobStation") do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal("GwJobStation"):Connect(hook)
end

return JobDelivery
