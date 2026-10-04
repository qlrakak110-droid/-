-- GwangalliGameplay/Jobs: data-driven jobs (G.JOBS) with shifts made of short tasks (docs/JOBS.md).
--   * apply (NPC dialog / phone 알바 앱 / message offer) -> d.job; quit anytime
--   * a shift = "출근" (reach the job's Destination) + the job's tasks:
--       goto    server distance check (deliveries: `pickup` attaches the delivery bag)
--       hold    ProximityPrompt on an invisible anchor next to the Destination
--       choice  answered on the phone, checked here
--       game    a MINI-GAME ROUND (JobGames + GwangalliJobsShared): with `point` the round opens
--               when the anchor's prompt is held, without one it opens at once; the client plays
--               it in GwangalliJobs and answers through the JobGame remote; the server keeps the
--               answer key, checks timing windows and pays
--               base x score x combo x speed bonus x Health.payMultiplier
--       deliver drop-off of the current delivery order: a "배달 완료" prompt appears at the
--               destination; distance-scaled pay + tip when fast
--     Pay per task accumulates and is paid into the BANK when the shift ends (complete: + shift
--     bonus; ended early / left the game: what was earned so far).
--   * XP -> promotion levels with higher wages (G.addJobXp)
--   * WorkState remote carries the current task to the phone / HUD; JobGame carries the rounds.
--   * Optional health module (Health.luau next to this file): Health.payMultiplier(player) -> 0..1
--     (, reason) lowers every pay-out; Health.onWork(player, seconds, jobId) is told about work.
-- Work points are created at runtime relative to the job's Destination part, snapped to the build's
-- GwJobStation anchors when they exist. World layer (feedback stage, docs/JOBS.md "월드 알바"):
--   JobWorld    NPC customers at the store / cafe counter, the boss's lines, carried props
--   JobShop     purchases for EVERY player (drinks fridge / shelf / cafe counter -> purchase sheet)
--   JobDelivery 광안 딜리버리: dispatch table, 퀵 (handover to a waiting NPC), 택배 (탑차 + rings +
--               red-light fines)
-- Contract attributes (docs/careers_contract.md): GwJob (career id) + GwJobBase (base Destination).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jobs = {}

local G: any
local JS: any
local JobGames: any
local Util: any
local Profiles: any
local ctx: any

type Sess = {
	jobId: string,
	tasks: { any },
	index: number, -- 0 = clock-in
	task: any?,
	taskId: string,
	taskStart: number,
	earned: number,
	shiftStart: number,
	teleported: boolean,
	lastPos: Vector3?,
	combo: number,
	maxCombo: number,
	rounds: number,
	perfect: number,
	delivery: any?, -- the chosen order { dish, icon, pickup, drop, dist, pay, tip, timeLimit }
	bag: BasePart?,
	dropPart: BasePart?,
	roundStarted: boolean,
	rng: Random,
	carry: BasePart?, -- JobWorld: restock box / quick parcel in the hands
	recipient: any?, -- JobDelivery: the 퀵 recipient NPC
	route: { any }?, -- JobDelivery: 택배 drops
	routeIndex: number?,
	truck: Model?,
	noTruck: boolean?,
	pendingFine: number?,
	redLights: number?,
	roundExtra: any?,
}
local shifts: { [Player]: Sess } = {}
local counter = 0
local rng = Random.new()

-- work point anchors: points[jobId][pointId] = BasePart
local points: { [string]: { [string]: BasePart } } = {}
local pointsFolder: Folder? = nil

local jobGameRemote: RemoteEvent? = nil

-- world layer (optional modules next to this file)
local World: any = nil
local Shop: any = nil
local Delivery: any = nil
local function sub(name: string): any
	local m = script.Parent and script.Parent:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliGameplay] " .. name .. " failed: " .. tostring(res))
	end
	return nil
end
local function world(fn: string, ...: any): any
	if World and type(World[fn]) == "function" then
		local ok, res = pcall(World[fn], ...)
		if ok then
			return res
		end
		warn("[GwangalliGameplay] JobWorld." .. fn .. ": " .. tostring(res))
	end
	return nil
end
local function delivery(fn: string, ...: any): any
	if Delivery and type(Delivery[fn]) == "function" then
		local ok, res = pcall(Delivery[fn], ...)
		if ok then
			return res
		end
		warn("[GwangalliGameplay] JobDelivery." .. fn .. ": " .. tostring(res))
	end
	return nil
end

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

-------------------------------------------------------------------------------------------------
-- Optional health module (fatigue debuff owner)
-------------------------------------------------------------------------------------------------
local healthModule: any = nil
local healthChecked = 0
local function health(): any
	if healthModule then
		return healthModule
	end
	local now = os.clock()
	if now - healthChecked < 5 then
		return nil
	end
	healthChecked = now
	local m = script.Parent and script.Parent:FindFirstChild("Health")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			healthModule = res
			return res
		end
	end
	return nil
end

-- 0..1 pay multiplier and an optional Korean reason ("피로해서 집중이 안 돼요")
local function payMultiplier(player: Player): (number, string?)
	local H = health()
	if not H or type(H.payMultiplier) ~= "function" then
		return 1, nil
	end
	local ok, m, reason = pcall(H.payMultiplier, player)
	if ok and type(m) == "number" and m == m then
		return math.clamp(m, 0, 1), if type(reason) == "string" and reason ~= "" then reason else nil
	end
	return 1, nil
end

local function healthReason(player: Player, mult: number): string?
	if mult >= 0.999 then
		return nil
	end
	local H = health()
	local reason: string? = nil
	if H and type(H.payReason) == "function" then
		local ok, r = pcall(H.payReason, player)
		if ok and type(r) == "string" and r ~= "" then
			reason = r
		end
	end
	if not reason and H and type(H.status) == "function" then
		-- the health module's status view: { tierLabel = "피로"|"과로"|"탈진", illness = { name, icon }? }
		local ok, st = pcall(H.status, player)
		if ok and type(st) == "table" then
			if type(st.illness) == "table" and st.illness.name then
				reason = string.format("%s %s 때문에 일이 힘들어요", tostring(st.illness.icon or "🤒"), tostring(st.illness.name))
			elseif type(st.tierLabel) == "string" and st.tierLabel ~= "" then
				local byTier = {
					["피로"] = "피로해서 집중이 안 돼요",
					["과로"] = "과로로 몸이 무거워요",
					["탈진"] = "탈진 직전이라 손이 느려요",
				}
				reason = byTier[st.tierLabel] or (st.tierLabel .. " 상태라 집중이 안 돼요")
			end
		end
	end
	return JS.describeMult(mult, reason)
end

local function onWork(player: Player, seconds: number, jobId: string)
	local H = health()
	if H and type(H.onWork) == "function" then
		pcall(H.onWork, player, math.max(0, seconds), jobId)
	end
end
Jobs.payMultiplier = payMultiplier
Jobs.healthReason = healthReason
Jobs.onWork = onWork
Jobs.health = health

-------------------------------------------------------------------------------------------------
-- Work state -> client
-------------------------------------------------------------------------------------------------
local function taskPosition(jobId: string, t: any): (Vector3?, string?)
	local job = G.JOBS[jobId]
	if typeof(t.position) == "Vector3" then
		return t.position, t.dest or job.place
	end
	if t.point then
		local p = points[jobId] and points[jobId][t.point]
		if p and p.Parent then
			return p.Position, job.place
		end
		local dp = ctx.dest(job.place)
		return dp and dp.Position or nil, job.place
	end
	local name = t.dest or job.place
	local dp = ctx.dest(name)
	return dp and dp.Position or nil, name
end

local function earnedToday(d: any): number
	if d.earnedDay and d.earnedDay.day == d.lifeDay then
		return d.earnedDay.amount
	end
	return 0
end

local function sendGame(player: Player, payload: { [string]: any })
	if jobGameRemote and player.Parent == Players then
		jobGameRemote:FireClient(player, payload)
	end
end

function Jobs.push(player: Player)
	if player.Parent ~= Players then
		return
	end
	local d = Profiles.get(player)
	if not d then
		return
	end
	if not d.job then
		ctx.remotes.WorkState:FireClient(player, { jobId = nil, onShift = false })
		return
	end
	local jobId = d.job.id
	local job = G.JOBS[jobId]
	local lv = G.jobLevel(jobId, d.careerXp[jobId] or 0)
	local s = shifts[player]
	local mult = 1
	if s then
		mult = payMultiplier(player)
	end
	local payload: { [string]: any } = {
		jobId = jobId,
		jobTitle = job.title,
		place = job.place,
		icon = job.icon,
		onShift = s ~= nil,
		level = lv,
		levelTitle = job.levels[lv].title,
		wage = G.jobWage(jobId, lv),
		taskPay = G.taskPay(jobId, lv),
		earnedShift = s and s.earned or 0,
		earnedToday = earnedToday(d),
		progress = { done = s and math.max(0, s.index - 1) or 0, total = s and #s.tasks or 0 },
		combo = s and s.combo or 0,
		payMult = mult,
		payReason = if s then healthReason(player, mult) else nil,
		career = G.jobCareer(jobId),
		base = G.jobBase(jobId),
		redLights = s and s.redLights or nil,
	}
	if s and s.task then
		local t = s.task
		local pos, target = taskPosition(jobId, t)
		local out: { [string]: any } = {
			id = s.taskId,
			kind = t.kind,
			prompt = t.prompt,
			target = target,
			position = pos,
			timeLimit = t.timeLimit,
			action = t.action,
			game = t.game,
			world = t.world,
			mode = t.mode,
		}
		if t.kind == "choice" then
			out.choices = table.clone(t.choices)
		end
		payload.task = out
	end
	ctx.remotes.WorkState:FireClient(player, payload)
end

function Jobs.onShift(player: Player): boolean
	return shifts[player] ~= nil
end

-------------------------------------------------------------------------------------------------
-- Work points
-------------------------------------------------------------------------------------------------
local function floorAt(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local ok, hit = pcall(function()
		return workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), params)
	end)
	if ok and hit then
		return hit.Position
	end
	return pos
end

local function anchorsFolder(): Folder
	if not pointsFolder or not pointsFolder.Parent then
		local f = workspace:FindFirstChild("GwangalliWorkPoints")
		if not f or not f:IsA("Folder") then
			f = Instance.new("Folder")
			f.Name = "GwangalliWorkPoints"
			f.Parent = workspace
		end
		pointsFolder = f :: Folder
	end
	return pointsFolder :: Folder
end

local startRound: (Player, Sess, boolean?) -> ()

local function onPointTriggered(player: Player, jobId: string, pointId: string, part: BasePart)
	local s = shifts[player]
	local d = Profiles.get(player)
	if not d then
		return
	end
	if not s or s.jobId ~= jobId then
		if Util.cooldown(player, "jobHint", 3) then
			local job = G.JOBS[jobId]
			if d.job and d.job.id == jobId then
				ctx.notify(player, "job", job.title, "알바 앱에서 '근무 시작'을 먼저 눌러 주세요")
			else
				ctx.notify(player, "job", job.title, string.format("%s에서 일하려면 먼저 지원하세요 (NPC와 대화 또는 폰 알바 앱)", job.place))
			end
		end
		return
	end
	local t = s.task
	if not t or (t.kind ~= "hold" and t.kind ~= "game" and t.kind ~= "pickup" and t.kind ~= "load") or t.point ~= pointId then
		if Util.cooldown(player, "jobWrongPoint", 2) and t then
			ctx.notify(player, "job", "여기가 아니에요", t.prompt)
		end
		return
	end
	local pos = Util.rootPosition(player)
	if not pos or (pos - part.Position).Magnitude > G.WORK_POINT_RADIUS + 4 then
		return
	end
	if t.kind == "game" then
		if t.world == "customer" and not s.roundStarted and World and not World.customerReady(player, s) then
			if Util.cooldown(player, "jobNoCustomer", 2.5) then
				ctx.notify(player, "job", "손님을 기다리는 중…", "곧 손님이 카운터로 와요. 잠깐만요!")
			end
			return
		end
		-- the round opens (or is re-sent when the player closed the UI)
		startRound(player, s, true)
		return
	end
	if t.kind == "pickup" or t.kind == "load" then
		if os.clock() - s.taskStart < G.TASK_MIN_SECONDS then
			return
		end
		local ok = if t.kind == "pickup" then delivery("pickup", player, s, t) else delivery("load", player, s, t)
		if ok then
			Jobs.advance(player, s)
		end
		return
	end
	Jobs.completeTask(player, true)
end

local placePoints: { [string]: BasePart } = {} -- "<place>|<point>" -> anchor shared by jobs of one place

local function makePoint(jobId: string, pointId: string, destPart: BasePart, offset: { number })
	points[jobId] = points[jobId] or {}
	if points[jobId][pointId] and points[jobId][pointId].Parent then
		return
	end
	local folder = anchorsFolder()
	local job = G.JOBS[jobId]
	-- jobs that share a place (퀵 / 택배 at the office) share one anchor + prompt
	local placeKey = job.place .. "|" .. pointId
	local shared = placePoints[placeKey]
	if shared and shared.Parent then
		points[jobId][pointId] = shared
		return
	end
	local cf = destPart.CFrame
	local flatLook = Util.flatLook(cf)
	local right = flatLook:Cross(Vector3.yAxis)
	local ground = Util.groundOf(destPart)
	local guess = ground + right * offset[1] + flatLook * -offset[2]
	local feet = floorAt(guess, Util.charactersIgnore({ destPart, folder :: Instance }))
	-- the venue build placed an exact anchor for this point
	local anchor = World and World.station(jobId, pointId)
	if anchor then
		feet = anchor.Position - Vector3.new(0, 0.5, 0)
	end
	local part = Instance.new("Part")
	part.Name = jobId .. "_" .. pointId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(feet + Vector3.new(0, 2.5, 0))
	part:SetAttribute("WorkJob", jobId)
	part:SetAttribute("WorkPoint", pointId)
	local hold: number? = nil
	local action: string? = nil
	for _, jid in G.JOB_ORDER do
		local other = G.JOBS[jid]
		if other and other.place == job.place and not hold then
			for _, t in G.jobTaskList(jid) do
				if t.point == pointId and (t.kind == "hold" or t.kind == "game" or t.kind == "pickup" or t.kind == "load") then
					hold = t.hold or (if t.kind == "game" then 0.6 else 1)
					action = t.action
					break
				end
			end
		end
	end
	if hold then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GwangalliWorkPrompt"
		prompt.ActionText = action or "근무하기"
		prompt.ObjectText = job.title
		prompt.HoldDuration = hold
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Parent = part
		prompt.Triggered:Connect(function(player: Player)
			local jid = jobId
			local cur = shifts[player]
			if cur and G.JOBS[cur.jobId] and G.JOBS[cur.jobId].place == job.place then
				jid = cur.jobId
			end
			local ok, err = pcall(onPointTriggered, player, jid, pointId, part)
			if not ok then
				warn("[GwangalliGameplay] work point failed: " .. tostring(err))
			end
		end)
	end
	part.Parent = folder
	points[jobId][pointId] = part
	placePoints[placeKey] = part
end

-- A Destination part was registered (called by the server for every Destination).
function Jobs.onDest(name: string, part: BasePart)
	for _, jobId in G.JOB_ORDER do
		local job = G.JOBS[jobId]
		if job and not job.alias and job.place == name and job.points then
			for pointId, off in job.points do
				local ok, err = pcall(makePoint, jobId, pointId, part, off)
				if not ok then
					warn("[GwangalliGameplay] work point " .. jobId .. "/" .. pointId .. ": " .. tostring(err))
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Delivery props: the bag on the rider's back, the drop-off prompt
-------------------------------------------------------------------------------------------------
local function removeBag(s: Sess)
	if s.bag then
		if s.bag.Parent then
			s.bag:Destroy()
		end
		s.bag = nil
	end
end

local function attachBag(player: Player, s: Sess)
	removeBag(s)
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local bag = Instance.new("Part")
	bag.Name = "DeliveryBag"
	bag.Size = Vector3.new(1.7, 1.9, 1.1)
	bag.Color = Color3.fromRGB(42, 193, 188)
	bag.Material = Enum.Material.SmoothPlastic
	bag.CanCollide = false
	bag.CanQuery = false
	bag.CanTouch = false
	bag.Massless = true
	bag.CastShadow = false
	bag.CFrame = torso.CFrame * CFrame.new(0, 0.15, 1.0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = bag
	weld.Parent = bag
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 60
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🛵 배달"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = bag
	bag.Parent = char
	s.bag = bag
end

local function removeDrop(s: Sess)
	if s.dropPart then
		if s.dropPart.Parent then
			s.dropPart:Destroy()
		end
		s.dropPart = nil
	end
end

local completeDelivery: (Player, Sess, BasePart) -> ()

local function makeDrop(player: Player, s: Sess, t: any)
	removeDrop(s)
	local dest = t.dest and ctx.dest(t.dest)
	if not dest then
		return
	end
	local folder = anchorsFolder()
	local part = Instance.new("Part")
	part.Name = "Drop_" .. player.UserId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(Util.groundOf(dest) + Vector3.new(0, 2.5, 0))
	part:SetAttribute("DropFor", player.UserId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GwangalliDropPrompt"
	prompt.ActionText = "배달 완료"
	prompt.ObjectText = string.format("%s %s", tostring(t.icon or "🛵"), tostring(t.dish or "배달"))
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = part
	prompt.Triggered:Connect(function(who: Player)
		if who ~= player then
			return
		end
		local cur = shifts[player]
		if not cur or cur.dropPart ~= part or not cur.task or cur.task.kind ~= "deliver" then
			return
		end
		local ok, err = pcall(completeDelivery, player, cur, part)
		if not ok then
			warn("[GwangalliGameplay] delivery failed: " .. tostring(err))
		end
	end)
	part.Parent = folder
	s.dropPart = part
end

local function sendDelivery(player: Player, s: Sess, phase: string)
	local o = s.delivery
	sendGame(player, {
		op = "delivery",
		phase = phase,
		order = o,
		timeLimit = if phase == "deliver" and s.task then s.task.timeLimit else nil,
	})
end

-------------------------------------------------------------------------------------------------
-- Shift lifecycle
-------------------------------------------------------------------------------------------------
local function setTask(player: Player, s: Sess, index: number)
	s.index = index
	counter += 1
	s.taskId = "t" .. tostring(counter)
	s.taskStart = os.clock()
	s.teleported = false
	s.roundStarted = false
	JobGames.cancel(player)
	removeDrop(s)
	if index == 0 then
		local job = G.JOBS[s.jobId]
		s.task = { kind = "goto", dest = job.place, prompt = job.place .. "(으)로 출근하기", radius = G.CLOCK_IN_RADIUS, clockIn = true }
	else
		s.task = s.tasks[index]
	end
	local t = s.task
	if t.kind == "goto" and t.pickup and not s.delivery then
		-- no order chosen (should not happen): plain return to the shop
		t.dest = t.dest or G.JOBS[s.jobId].place
		t.prompt = string.format("%s(으)로 돌아가기", t.dest)
	elseif t.kind == "deliver" then
		if s.delivery then
			makeDrop(player, s, t)
			sendDelivery(player, s, "deliver")
		else
			t.dest = t.dest or G.JOBS[s.jobId].place
			t.prompt = string.format("%s(으)로 돌아가기", t.dest)
		end
	end
	if t.kind == "handover" or t.kind == "ring" then
		delivery("setTask", player, s, t)
	end
	if t.kind == "game" and t.world == "customer" then
		world("taskStarted", player, s, t)
	end
	Jobs.push(player)
	if t.kind == "game" and not t.point then
		startRound(player, s, false)
	end
end

local function payOut(player: Player, d: any, s: Sess, bonus: number, reason: string)
	local total = s.earned + bonus
	if total > 0 then
		local job = G.JOBS[s.jobId]
		ctx.ledger(player, "bank", total, string.format("급여 · %s%s", job.place, if bonus > 0 then " (근무 완료)" else ""), true)
		if not d.earnedDay or d.earnedDay.day ~= d.lifeDay then
			d.earnedDay = { day = d.lifeDay, amount = 0 }
		end
		d.earnedDay.amount += total
		if player.Parent == Players then
			ctx.notify(player, "money", string.format("급여 입금 +%s", G.format.won(total)), string.format("%s · 통장으로 입금됐어요%s", reason, if bonus > 0 then string.format(" (보너스 %s 포함)", G.format.won(bonus)) else ""), { sound = "cash" })
		end
	end
end

local function finish(player: Player, completed: boolean, reason: string)
	local s = shifts[player]
	if not s then
		return
	end
	shifts[player] = nil
	JobGames.cancel(player)
	removeBag(s)
	removeDrop(s)
	world("shiftEnded", player, s, completed)
	delivery("endShift", player, s)
	player:SetAttribute(G.Attr.OnShift, false)
	local d = Profiles.get(player)
	if not d then
		return
	end
	local bonus = 0
	if completed then
		local lv = G.jobLevel(s.jobId, d.careerXp[s.jobId] or 0)
		bonus = G.shiftBonus(s.jobId, lv)
		local mult = payMultiplier(player)
		bonus = G.round100(bonus * mult)
		-- red-light fines that no drop could absorb come out of the bonus
		if (s.pendingFine or 0) > 0 then
			local take = math.min(bonus, s.pendingFine)
			bonus -= take
			s.pendingFine -= take
		end
		d.shifts = (d.shifts or 0) + 1
		Jobs.addXp(player, d, s.jobId, G.SHIFT_XP)
		ctx.addStats(player, { happiness = 2 }, nil, true)
	end
	payOut(player, d, s, bonus, reason)
	local job = G.JOBS[s.jobId]
	local seconds = os.clock() - s.shiftStart
	sendGame(player, {
		op = "summary",
		jobId = s.jobId,
		jobTitle = job.title,
		jobIcon = job.icon,
		place = job.place,
		rounds = s.rounds,
		perfect = s.perfect,
		tasks = math.max(0, s.index - (if completed then 0 else 1)),
		total = #s.tasks,
		earned = s.earned,
		bonus = bonus,
		paid = s.earned + bonus,
		maxCombo = s.maxCombo,
		seconds = seconds,
		hourly = if seconds > 30 then G.round100((s.earned + bonus) / seconds * 3600) else nil,
		reason = reason,
		completed = completed,
		earnedToday = earnedToday(d),
		redLights = s.redLights,
		boss = (JS.BOSS[if s.jobId == "delivery_quick" or s.jobId == "delivery_parcel" then "delivery" else s.jobId] or {}).name,
	})
	ctx.changed(player, "job")
	Jobs.push(player)
end

function Jobs.addXp(player: Player, d: any, jobId: string, amount: number)
	local xp, lv, promoted = G.addJobXp(jobId, d.careerXp[jobId] or 0, amount)
	d.careerXp[jobId] = xp
	d.careers[jobId] = lv
	ctx.changed(player, "job")
	if promoted and player.Parent == Players then
		local job = G.JOBS[jobId]
		local l = job.levels[lv]
		ctx.notify(player, "job", "승진! 🎉 " .. l.title, string.format("%s · 시급 %s", job.title, G.format.won(l.wage)), { sound = "complete" })
		ctx.addStats(player, { happiness = 8, popularity = 2 }, nil, true)
		if job.contact then
			ctx.sendMessage(player, job.contact, string.format("축하해요! 오늘부터 %s예요. 시급도 %s으로 올려 줄게요 👏", l.title, G.format.won(l.wage)))
		end
	end
end

local function advance(player: Player, s: Sess)
	if s.index >= #s.tasks then
		finish(player, true, "근무 완료 수고했어요!")
		return
	end
	setTask(player, s, s.index + 1)
end
Jobs.advance = advance

-- goto / hold / choice / tap tasks (game rounds and deliveries have their own paths below)
function Jobs.completeTask(player: Player, correct: boolean)
	local s = shifts[player]
	local d = Profiles.get(player)
	if not s or not d or not s.task then
		return
	end
	local t = s.task
	if os.clock() - s.taskStart < G.TASK_MIN_SECONDS then
		return
	end
	if t.clockIn then
		ctx.notify(player, "job", "출근 완료 ✅", "첫 업무: " .. ((s.tasks[1] and s.tasks[1].prompt) or ""))
		world("clockIn", player, s)
		setTask(player, s, 1)
		return
	end
	if t.returnTruck then
		delivery("despawnTruck", player, s)
	end
	local jobId = s.jobId
	local lv = G.jobLevel(jobId, d.careerXp[jobId] or 0)
	local elapsed = os.clock() - s.taskStart
	if correct then
		local pay = G.taskPay(jobId, lv)
		local tip = 0
		if t.timeLimit then
			if s.teleported then
				pay = math.floor(pay / 2 / 100) * 100
			elseif elapsed <= t.timeLimit then
				tip = G.round100(pay * 0.5)
			end
		end
		local mult = payMultiplier(player)
		local total = G.round100((pay + tip) * mult)
		s.earned += total
		s.combo += 1
		s.maxCombo = math.max(s.maxCombo, s.combo)
		Jobs.addXp(player, d, jobId, G.TASK_XP)
		local why = healthReason(player, mult)
		if t.pickup then
			attachBag(player, s)
			sendDelivery(player, s, "picked")
			ctx.notify(player, "job", string.format("픽업 완료 🛵 +%s", G.format.won(total)), string.format("%s 배달 가방을 챙겼어요 · 이제 %s까지!", tostring(s.delivery and s.delivery.dish or ""), tostring(s.delivery and s.delivery.drop or "")))
		else
			ctx.notify(player, "job", string.format("+%s%s", G.format.won(total), if tip > 0 then " (빠른 배달 팁!)" else ""), t.prompt .. " 완료" .. (if why then " · " .. why else ""))
		end
	else
		s.combo = 0
		ctx.notify(player, "job", "앗, 틀렸어요 😅", "이번 업무는 급여가 없어요. 다음엔 잘할 수 있어요!")
	end
	ctx.addStats(player, { stamina = -G.TASK_STAMINA, happiness = -0.5 }, nil, true)
	onWork(player, math.min(elapsed, 120), jobId)
	advance(player, s)
end

-------------------------------------------------------------------------------------------------
-- Mini-game rounds
-------------------------------------------------------------------------------------------------
local function deliveryInfo(s: Sess, d: any): any
	local job = G.JOBS[s.jobId]
	local lv = G.jobLevel(s.jobId, d.careerXp[s.jobId] or 0)
	local pickups = {}
	for _, name in job.pickups or { job.place } do
		local p = ctx.dest(name)
		if p then
			table.insert(pickups, { name = name, pos = p.Position })
		end
	end
	if #pickups == 0 then
		local p = ctx.dest(job.place)
		table.insert(pickups, { name = job.place, pos = p and p.Position or Vector3.zero })
	end
	local drops = {}
	for _, name in G.DELIVERY_DESTS do
		local p = ctx.dest(name)
		if p then
			table.insert(drops, { name = name, pos = p.Position })
		end
	end
	if #drops == 0 then
		-- the map has none of the listed Destinations: use whatever pickups exist (the generator
		-- skips same-name pairs), else the shop itself
		for _, pu in pickups do
			table.insert(drops, pu)
		end
		if #drops < 2 then
			table.insert(drops, { name = job.place .. " 앞", pos = pickups[1].pos })
		end
	end
	return { pickups = pickups, drops = drops, basePay = G.taskPay(s.jobId, lv) }
end

local function todayInfo(): any
	local ok, t = pcall(function()
		return os.date("!*t", os.time() + 9 * 3600)
	end)
	if ok and type(t) == "table" then
		return { month = t.month, day = t.day }
	end
	return { month = 10, day = 2 }
end

startRound = function(player: Player, s: Sess, fromPrompt: boolean?)
	local t = s.task
	local d = Profiles.get(player)
	if not t or t.kind ~= "game" or not d then
		return
	end
	local existing = JobGames.current(player)
	if existing and existing.taskId == s.taskId then
		-- the UI was closed: re-send with the time left
		if fromPrompt and Util.cooldown(player, "jobRoundResend", 1) then
			local p = JobGames.payload(existing)
			p.op = "round"
			p.resend = true
			Jobs.decorateRound(player, s, p)
			sendGame(player, p)
		end
		return
	end
	local info: any = { today = todayInfo() }
	if t.game == "order" then
		info = deliveryInfo(s, d)
	end
	-- the world layer: the counter customer, prop rows, the restock box (also adds generator input)
	s.roundExtra = if t.world then world("roundInfo", player, s, t, info) else nil
	local round, err = JobGames.start(player, s.taskId, t.game, info, t.timeLimit)
	if not round then
		warn("[GwangalliGameplay] job round failed (" .. tostring(t.game) .. "): " .. tostring(err))
		-- never block the shift: skip the round
		advance(player, s)
		return
	end
	s.roundStarted = true
	local p = JobGames.payload(round)
	p.op = "round"
	Jobs.decorateRound(player, s, p)
	sendGame(player, p)
end

function Jobs.decorateRound(player: Player, s: Sess, p: { [string]: any })
	local job = G.JOBS[s.jobId]
	local mult = payMultiplier(player)
	p.jobId = s.jobId
	p.jobTitle = job.title
	p.jobIcon = job.icon
	p.place = job.place
	p.prompt = s.task and s.task.prompt or ""
	p.round = s.index
	p.total = #s.tasks
	p.combo = s.combo
	p.earned = s.earned
	p.payMult = mult
	p.payReason = healthReason(player, mult)
	local extra = s.roundExtra
	if type(extra) == "table" then
		p.world = extra.world
		p.stations = extra.stations
		p.customer = extra.customer
	end
	local boss = JS.BOSS and JS.BOSS[s.jobId]
	p.boss = boss and boss.name or nil
	p.npc = G.JOBS[s.jobId] and G.JOBS[s.jobId].npc or nil
end

-- Applies a chosen delivery order to the pickup / deliver tasks that follow the "order" round.
local function applyOrder(s: Sess, order: any)
	s.delivery = order
	local pu = s.tasks[s.index + 1]
	local dl = s.tasks[s.index + 2]
	if pu and pu.kind == "goto" and pu.pickup then
		pu.dest = order.pickup
		pu.prompt = string.format("%s에서 %s 픽업하기", order.pickup, order.dish)
		pu.radius = pu.radius or JS.DELIVERY.radius
	end
	if dl and dl.kind == "deliver" then
		dl.dest = order.drop
		dl.dish = order.dish
		dl.icon = order.icon
		dl.prompt = string.format("%s까지 %s 배달하기", order.drop, order.dish)
		dl.timeLimit = order.timeLimit
		dl.pay = order.pay
		dl.tip = order.tip
		dl.radius = dl.radius or JS.DELIVERY.radius
	end
end

-- The client answered the active round (or the server timed it out: forced = true).
local function resolveRound(player: Player, s: Sess, answer: any, forced: boolean?, taskId: any?)
	local d = Profiles.get(player)
	local t = s.task
	if not d or not t or t.kind ~= "game" then
		return
	end
	local res = JobGames.answer(player, taskId, answer, forced)
	if not res then
		return
	end
	local jobId = s.jobId
	local lv = G.jobLevel(jobId, d.careerXp[jobId] or 0)
	local base = G.taskPay(jobId, lv)
	local result: { [string]: any } = {
		op = "result",
		taskId = s.taskId,
		game = t.game,
		score = res.score,
		elapsed = res.elapsed,
		timedOut = res.timedOut,
		base = base,
		last = s.index >= #s.tasks,
	}
	if t.game == "order" then
		local order = res.round.secret.orders[tonumber(answer) or 0]
		if not order then
			order = res.round.secret.orders[1]
		end
		if order then
			applyOrder(s, order)
			result.ok = true
			result.pay = 0
			result.order = order
			result.message = string.format("%s 주문 접수! %s에서 픽업해요", order.dish, order.pickup)
			sendGame(player, result)
			sendDelivery(player, s, "pickup")
			ctx.notify(player, "job", "주문 접수 🛵 " .. order.dish, string.format("%s → %s · %s%s", order.pickup, order.drop, G.format.won(order.pay), if order.tip > 0 then string.format(" (+팁 %s)", G.format.won(order.tip)) else ""))
			advance(player, s)
		else
			-- no order could be built (no destinations): skip the delivery cycle
			result.ok = false
			result.pay = 0
			result.message = "배달 가능한 주문이 없어요"
			sendGame(player, result)
			-- the pickup / deliver tasks that follow turn into "돌아가기" errands (setTask)
			advance(player, s)
		end
		return
	end
	local score = res.score
	local ok = score >= JS.PASS_SCORE and not res.timedOut and not res.tooFast
	local timeLimit = res.round.timeLimit
	local pay = 0
	local comboMult = 1
	local speedBonus = false
	local mult, why = 1, nil
	if ok then
		s.combo += 1
		s.maxCombo = math.max(s.maxCombo, s.combo)
		comboMult = JS.comboMult(s.combo)
		speedBonus = score >= 0.999 and res.elapsed <= timeLimit * JS.SPEED_FRACTION
		mult = payMultiplier(player)
		why = healthReason(player, mult)
		local v = base * JS.scoreMult(score) * comboMult * (if speedBonus then 1 + JS.SPEED_BONUS else 1) * mult
		if t.game == "latte" then
			v *= 0.5 -- bonus mini-game: half a task's pay
		end
		if s.teleported then
			v *= 0.5
		end
		pay = G.round100(v)
		s.earned += pay
		s.perfect += if score >= 0.999 then 1 else 0
		Jobs.addXp(player, d, jobId, G.TASK_XP)
	else
		s.combo = 0
		Jobs.addXp(player, d, jobId, math.floor(G.TASK_XP / 2))
	end
	s.rounds += 1
	result.ok = ok
	result.pay = pay
	result.combo = s.combo
	result.comboMult = comboMult
	result.speedBonus = speedBonus
	result.payMult = mult
	result.payReason = why
	result.earned = s.earned
	if res.timedOut then
		result.message = "시간 초과 ⏰ 이번 라운드는 급여가 없어요"
	elseif res.tooFast then
		result.message = "너무 빨라요… 다시 천천히!"
	elseif not ok then
		result.message = "앗, 틀렸어요 😅 콤보가 끊겼어요"
	elseif score >= 0.999 then
		result.message = if speedBonus then "완벽해요! ⚡ 스피드 보너스" else "완벽해요! ✨"
	else
		result.message = "거의 다 맞았어요 👍"
	end
	sendGame(player, result)
	if t.world then
		world("roundResolved", player, s, t, ok, score, res.round.view)
	end
	s.roundExtra = nil
	ctx.addStats(player, { stamina = -G.TASK_STAMINA, happiness = if ok then 0.5 else -0.5 }, nil, true)
	onWork(player, math.min(res.elapsed + 2, 120), jobId)
	advance(player, s)
end

-- JobGame remote (client -> server)
local function onGameEvent(player: Player, p: any)
	if type(p) ~= "table" or type(p.op) ~= "string" then
		return
	end
	if not Util.bucket(player, 5, 10) then
		return
	end
	local s = shifts[player]
	if p.op == "quit" then
		if Util.cooldown(player, "act:endShift", 1) then
			Jobs.endShift(player)
		end
		return
	elseif p.op == "buy" then
		if Shop then
			Shop.buy(player, p.item, p.anchor)
		end
		return
	elseif p.op == "dispatchPick" then
		if Util.cooldown(player, "dispatchPick", 1.5) then
			delivery("pick", player, p.mode)
		end
		return
	end
	if not s or not s.task then
		return
	end
	if p.op == "answer" then
		if not Util.cooldown(player, "jobAnswer", 0.3) then
			return
		end
		resolveRound(player, s, p.answer, false, p.taskId)
	elseif p.op == "ready" then
		-- the UI is up; nothing to do (the timer started when the round was sent)
		return
	end
end

-------------------------------------------------------------------------------------------------
-- Deliveries
-------------------------------------------------------------------------------------------------
completeDelivery = function(player: Player, s: Sess, part: BasePart)
	local d = Profiles.get(player)
	local t = s.task
	if not d or not t or t.kind ~= "deliver" then
		return
	end
	local pos = Util.rootPosition(player)
	if not pos or (pos - part.Position).Magnitude > (t.radius or JS.DELIVERY.radius) + 6 then
		return
	end
	local jobId = s.jobId
	local elapsed = os.clock() - s.taskStart
	local pay = tonumber(t.pay) or G.taskPay(jobId, G.jobLevel(jobId, d.careerXp[jobId] or 0))
	local tip = 0
	local fast = t.timeLimit ~= nil and elapsed <= t.timeLimit
	if s.teleported then
		pay = math.floor(pay / 2 / 100) * 100
	elseif fast then
		tip = tonumber(t.tip) or 0
	end
	local mult = payMultiplier(player)
	local why = healthReason(player, mult)
	local total = G.round100((pay + tip) * mult)
	s.earned += total
	s.combo += 1
	s.maxCombo = math.max(s.maxCombo, s.combo)
	s.rounds += 1
	s.perfect += if fast then 1 else 0
	Jobs.addXp(player, d, jobId, G.TASK_XP)
	removeBag(s)
	removeDrop(s)
	local order = s.delivery
	s.delivery = nil
	sendGame(player, {
		op = "result",
		taskId = s.taskId,
		game = "deliver",
		ok = true,
		score = if fast then 1 else 0.7,
		pay = total,
		base = pay,
		tip = tip,
		speedBonus = fast,
		combo = s.combo,
		comboMult = 1,
		payMult = mult,
		payReason = why,
		earned = s.earned,
		elapsed = elapsed,
		order = order,
		message = if fast then "배달 완료! 🛵 빠른 배달 팁까지" else "배달 완료! 🛵",
		last = s.index >= #s.tasks,
	})
	sendDelivery(player, s, "done")
	ctx.notify(player, "job", string.format("배달 완료 +%s%s", G.format.won(total), if tip > 0 then " (빠른 배달 팁!)" else ""), string.format("%s · %s%s", tostring(order and order.dish or "배달"), tostring(order and order.drop or ""), if why then " · " .. why else ""))
	ctx.addStats(player, { stamina = -G.TASK_STAMINA, happiness = 0.5 }, nil, true)
	onWork(player, math.min(elapsed, 180), jobId)
	advance(player, s)
end

-------------------------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------------------------
-- GwJob / GwJobBase (docs/careers_contract.md): the Careers module respawns job holders at the base
local function setCareerAttrs(player: Player, jobId: string?)
	if jobId and G.JOBS[jobId] then
		player:SetAttribute("GwJob", G.jobCareer(jobId))
		player:SetAttribute("GwJobBase", G.jobBase(jobId))
	else
		player:SetAttribute("GwJob", nil)
		player:SetAttribute("GwJobBase", nil)
	end
end
Jobs.setCareerAttrs = setCareerAttrs

function Jobs.apply(player: Player, jobId: any, via: string?): boolean
	local id = Util.str(jobId, 40)
	id = id and G.resolveJob(id)
	local job = id and G.JOBS[id]
	local d = Profiles.get(player)
	if not job or not d or not id then
		return false
	end
	if d.job and d.job.id == id then
		ctx.notify(player, "job", job.title, "이미 여기서 일하고 있어요. 알바 앱에서 근무를 시작하세요")
		return false
	end
	if shifts[player] then
		finish(player, false, "근무 중단")
	end
	local prev = d.job and G.JOBS[d.job.id]
	d.job = { id = id }
	if not d.careerXp[id] then
		d.careerXp[id] = 0
	end
	d.careers[id] = G.jobLevel(id, d.careerXp[id])
	player:SetAttribute(G.Attr.Job, id)
	setCareerAttrs(player, id)
	ctx.changed(player, "job")
	local lv = d.careers[id]
	ctx.notify(player, "job", "합격! " .. job.icon .. " " .. job.title, string.format("%s · %s · 시급 %s%s", job.place, job.levels[lv].title, G.format.won(job.levels[lv].wage), if prev then string.format(" (%s 그만둠)", prev.title) else ""), { sound = "complete" })
	ctx.setWaypoint(player, job.place)
	ctx.addStats(player, { happiness = 3 }, nil, true)
	Jobs.push(player)
	return true
end

function Jobs.quit(player: Player)
	local d = Profiles.get(player)
	if not d or not d.job then
		return
	end
	if shifts[player] then
		finish(player, false, "근무 중단")
	end
	local job = G.JOBS[d.job.id]
	d.job = nil
	player:SetAttribute(G.Attr.Job, "")
	setCareerAttrs(player, nil)
	ctx.changed(player, "job")
	ctx.notify(player, "job", "퇴사했어요", (job and job.title or "") .. " · 경력은 그대로 남아 있어요")
	Jobs.push(player)
end

function Jobs.startShift(player: Player)
	local d = Profiles.get(player)
	if not d then
		return
	end
	if ctx.work and d.job and ctx.work.handles(d.job.id) then
		ctx.work.startShift(player, d.job.id)
		return
	end
	if not d.job then
		ctx.notify(player, "job", "직업이 없어요", "알바 앱이나 가게 NPC에게 먼저 지원하세요")
		return
	end
	if shifts[player] then
		Jobs.push(player)
		return
	end
	if (d.stats.stamina or 0) < G.MIN_SHIFT_STAMINA then
		ctx.notify(player, "warn", "너무 피곤해요 😴", "집에서 자거나 뭘 좀 먹고 체력을 회복하세요")
		return
	end
	local H = health()
	if H and type(H.canWork) == "function" then
		local ok, can, why = pcall(H.canWork, player)
		if ok and can == false then
			ctx.notify(player, "warn", "지금은 일할 수 없어요", if type(why) == "string" then why else "병원에서 치료를 받아야 해요")
			return
		end
	end
	local jobId = d.job.id
	local s: Sess = {
		jobId = jobId,
		tasks = G.buildShift(jobId, rand),
		index = 0,
		task = nil,
		taskId = "",
		taskStart = os.clock(),
		earned = 0,
		shiftStart = os.clock(),
		teleported = false,
		lastPos = Util.rootPosition(player),
		combo = 0,
		maxCombo = 0,
		rounds = 0,
		perfect = 0,
		delivery = nil,
		bag = nil,
		dropPart = nil,
		roundStarted = false,
		rng = Random.new(),
	}
	shifts[player] = s
	player:SetAttribute(G.Attr.OnShift, true)
	ctx.changed(player, "job")
	ctx.notify(player, "job", "근무 시작 · " .. G.JOBS[jobId].title, string.format("업무 %d개 · 끝까지 하면 보너스!", #s.tasks))
	setTask(player, s, 0)
end

function Jobs.endShift(player: Player)
	if ctx.work and ctx.work.onShift(player) then ctx.work.endShift(player); return end
	if shifts[player] then
		finish(player, false, "근무 조기 종료")
	end
end

function Jobs.workTask(player: Player, p: any)
	local s = shifts[player]
	if not s or not s.task then
		return
	end
	if type(p.taskId) == "string" and p.taskId ~= s.taskId then
		return -- stale
	end
	local t = s.task
	if t.kind == "choice" then
		local choice = p.choice
		if type(choice) == "string" then
			for i, label in t.choices do
				if label == choice then
					choice = i
					break
				end
			end
		end
		local idx = Util.int(choice, 1, #t.choices)
		if not idx then
			return
		end
		Jobs.completeTask(player, idx == t.answer)
	elseif t.kind == "tap" then
		Jobs.completeTask(player, p.ok ~= false)
	end
	-- goto / hold / deliver complete on the server only; game rounds answer through JobGame
end

-------------------------------------------------------------------------------------------------
-- Tick: goto checks, teleport detection, timeouts
-------------------------------------------------------------------------------------------------
local TELEPORT_JUMP = 160

local function tick()
	world("tick")
	local now = os.clock()
	for player, s in shifts do
		if player.Parent ~= Players then
			continue
		end
		local pos = Util.rootPosition(player)
		if not pos then
			continue
		end
		if s.lastPos and (pos - s.lastPos).Magnitude > TELEPORT_JUMP and not ctx.teleportAllowed(player) and not ctx.isRiding(player) then
			s.teleported = true
		end
		s.lastPos = pos
		if os.clock() - s.shiftStart > G.MAX_SHIFT_SECONDS then
			finish(player, false, "근무 시간 초과")
			continue
		end
		local t = s.task
		if Delivery and (s.jobId == "delivery_quick" or s.jobId == "delivery_parcel") and shifts[player] == s then
			delivery("tick", player, s, pos, now)
			if shifts[player] ~= s then
				continue
			end
			t = s.task
		end
		if t and t.kind == "goto" then
			local target, _ = taskPosition(s.jobId, t)
			if target then
				local radius = t.radius or G.WORK_POINT_RADIUS
				local flat = Vector3.new(pos.X - target.X, 0, pos.Z - target.Z).Magnitude
				if flat <= radius and math.abs(pos.Y - target.Y) < 40 then
					Jobs.completeTask(player, true)
				end
			elseif os.clock() - s.taskStart > 3 then
				-- the Destination does not exist in this map: skip the task instead of blocking the shift
				warn("[GwangalliGameplay] job target missing: " .. tostring(t.dest or t.point))
				s.taskStart = -math.huge
				Jobs.completeTask(player, true)
			end
		elseif t and t.kind == "deliver" then
			if not s.dropPart then
				-- the drop-off Destination does not exist in this map: skip after a moment
				if os.clock() - s.taskStart > 3 then
					warn("[GwangalliGameplay] delivery target missing: " .. tostring(t.dest))
					removeBag(s)
					s.delivery = nil
					sendDelivery(player, s, "done")
					advance(player, s)
				end
			end
		elseif t and t.kind == "game" then
			local left = JobGames.timeLeft(player)
			if left ~= nil and left < -2 then
				-- the client never answered (UI closed / left the shop): the round is lost
				resolveRound(player, s, nil, true, nil)
			elseif not s.roundStarted and t.point and os.clock() - s.taskStart > 240 then
				-- idle for 4 minutes without reaching the work point: the shift moves on
				s.combo = 0
				ctx.notify(player, "job", "라운드를 건너뛰었어요", t.prompt)
				advance(player, s)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Player lifecycle
-------------------------------------------------------------------------------------------------
function Jobs.onLoaded(player: Player)
	local d = Profiles.get(player)
	-- saved alias jobs (the old 배달 라이더 "rider") move to their new id, career XP included
	if d and d.job and d.job.id then
		local old = d.job.id
		local id = G.resolveJob(old)
		if id and id ~= old then
			d.job.id = id
			if d.careerXp and d.careerXp[old] and not d.careerXp[id] then
				d.careerXp[id] = d.careerXp[old]
				d.careers[id] = G.jobLevel(id, d.careerXp[id])
			end
			if Profiles.markDirty then
				pcall(Profiles.markDirty, player)
			end
		elseif not id then
			d.job = nil
		end
	end
	setCareerAttrs(player, d and d.job and d.job.id or nil)
	player:SetAttribute(G.Attr.Job, d and d.job and d.job.id or "")
	player:SetAttribute(G.Attr.OnShift, false)
	Jobs.push(player)
end

function Jobs.onCharacter(player: Player)
	local s = shifts[player]
	if s then
		s.lastPos = nil
		if s.bag then
			-- the old character took the bag with it: put it on the new one
			s.bag = nil
			task.delay(1, function()
				local cur = shifts[player]
				if cur == s and s.delivery and s.task and s.task.kind == "deliver" then
					pcall(attachBag, player, s)
				end
			end)
		end
	end
end

-- Leaving: pay what was earned (called before the profile is saved and released).
function Jobs.onLeave(player: Player)
	if shifts[player] then
		finish(player, false, "접속 종료")
	end
	shifts[player] = nil
	JobGames.cancel(player)
end

function Jobs.resetPosition(player: Player)
	local s = shifts[player]
	if s then
		s.lastPos = nil
	end
end

function Jobs.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles

	-- shared mini-game data (+ the server round module next to this file)
	do
		local m = ReplicatedStorage:FindFirstChild("GwangalliJobsShared") or ReplicatedStorage:WaitForChild("GwangalliJobsShared", 10)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				JS = res
			else
				warn("[GwangalliGameplay] GwangalliJobsShared failed: " .. tostring(res))
			end
		end
		local jm = script.Parent and script.Parent:FindFirstChild("JobGames")
		if jm and jm:IsA("ModuleScript") then
			local ok, res = pcall(require, jm)
			if ok and type(res) == "table" then
				JobGames = res
			else
				warn("[GwangalliGameplay] JobGames failed: " .. tostring(res))
			end
		end
	end
	if not JS then
		-- minimal stand-in so shifts still run (game rounds are skipped)
		JS = { NET_SLACK = 1.5, PASS_SCORE = 0.5, SPEED_FRACTION = 0.5, SPEED_BONUS = 0.25, DELIVERY = { radius = 30 }, GAMES = {}, gen = {}, check = {}, comboMult = function()
			return 1
		end, scoreMult = function(s)
			return s
		end, describeMult = function()
			return nil
		end }
	end
	if not JobGames then
		JobGames = { init = function() end, start = function()
			return nil, "JobGames missing"
		end, current = function()
			return nil
		end, answer = function()
			return nil
		end, cancel = function() end, timeLeft = function()
			return nil
		end, payload = function()
			return {}
		end, active = {} }
	end
	JobGames.init({ JS = JS, rng = rng })
	World = sub("JobWorld")
	Shop = sub("JobShop")
	Delivery = sub("JobDelivery")
	if JS.validate then
		for _, p in JS.validate() do
			warn("[GwangalliGameplay] jobs data: " .. p)
		end
	end

	-- JobGame remote in the shared remotes folder
	local folder = ctx.remotes.WorkState and ctx.remotes.WorkState.Parent
	if folder then
		local r = folder:FindFirstChild(JS.Remote or "JobGame")
		if r and not r:IsA("RemoteEvent") then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = JS.Remote or "JobGame"
			r.Parent = folder
		end
		jobGameRemote = r :: RemoteEvent
		ctx.remotes.JobGame = jobGameRemote
		if World then
			pcall(World.init, ctx, Jobs, JS, jobGameRemote)
		end
		if Shop then
			pcall(Shop.init, ctx, JS, jobGameRemote, health)
		end
		if Delivery then
			pcall(Delivery.init, ctx, Jobs, World, JS, jobGameRemote)
		end
		jobGameRemote.OnServerEvent:Connect(function(player: Player, p: any)
			local ok, err = pcall(onGameEvent, player, p)
			if not ok then
				warn("[GwangalliGameplay] JobGame from " .. player.Name .. " failed: " .. tostring(err))
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliGameplay] jobs tick failed: " .. tostring(err))
			end
		end
	end)
end

-- exported for the simulator / tests
Jobs.shifts = shifts

return Jobs
