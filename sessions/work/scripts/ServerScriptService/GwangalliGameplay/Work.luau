--!nocheck
-- GwangalliGameplay/Work: the 알바 WORK SIMULATION coordinator (feature module; docs/WORK_SIM.md).
--
--   구직 공고 (board) → 지원 (Jobs.apply, existing) → 근무 조건 (length, pay) → 출근 (walk / drive to the
--   store, existing movement) → 출근 체크 at the staff time clock: uniform on, store equipment lights up,
--   오픈 준비 phase → 피크 → 마감 (close tasks) → 정산 (server-computed, paid ONCE into the bank) → 퇴근.
--
--   * Store kinds (stations, items, actions) live in WorkCafe / WorkStore / WorkKitchen / WorkDelivery.
--     This module owns sessions, phases, customers / test customers (WorkOrders), events, credit, XP,
--     pay-out, saving and the client state.
--   * Server authority: the client only says "do action X at station Y"; the server checks the shift,
--     the distance, the held item and the station state (the same action list the client was shown).
--   * Money: ctx.ledger (existing). A shift id is paid once: profile.work.paid keeps the last 40 ids and
--     is written in the same profile mutation as the bank deposit; an unsettled shift (server crash) is
--     kept in profile.work.open and settled on the next load.
--   * Existing systems are only CALLED: Jobs.apply (지원), ctx.dest / ctx.setWaypoint, ctx.ledger,
--     Profiles; NPCs connect through WorkOrders.registerProvider (no NPC code here).
--   * v2: WorkCustomers (visible NPC customers: the order provider of every store kind with a `site`),
--     WorkStore (GS25 편의점), WorkDelivery (음식 · 퀵 배달). Store kinds may add:
--       K.site(store) -> customer path def · K.noTestCustomers · K.unitPerOrder (one pay unit per order)
--       K.globalStations(store, player, sess) -> stations usable anywhere (배달 앱)
--       K.playerTick(store, player, sess, dt) · K.extraView(store, player, sess) -> kind HUD data
--       K.onClockIn / K.releasePlayer (existing)
--     Stations may carry `owner = player` (only that worker sees / uses them).
--
-- API for other systems (server):
--   Work.trackLevel(player, track) -> level, xp, nextXp?, title, rank
--   Work.trackInfo(player) -> { [track] = { level, xp, nextXp, title, rank } }
--   Work.isWorking(player) -> jobId? (clocked in) · Work.clerks(jobId) -> { Player } (clocked-in workers)
--   Work.storeState(jobId) -> { open, clerks, place, phase }?
--   ServerStorage.GwangalliWorkEvents (BindableEvent, from WorkOrders) also fires
--     ("shiftStart", info) when a worker clocks in, ("shiftEnd", info) when they leave,
--     ("settle", info + { total, paid, early }) after the 정산; info = { player, userId, jobId, track,
--     place, level, shiftId }. The store folder workspace.GwangalliWork_<jobId> carries attributes
--     Open (bool) / Clerks (number) / Place (string).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Work = {}

local ctx: any
local G: any
local Util: any
local Profiles: any
local C: any
local WS: any
local Props: any
local Orders: any
local Customers: any = nil
local KINDS: { [string]: any } = {}
local workEvents: BindableEvent? = nil

local remote: RemoteEvent? = nil
local stores: { [string]: any } = {}
local sessions: { [Player]: any } = {}
local itemSerial = 0
local rng = Random.new()
local pushAt: { [Player]: number } = {}
local dirtyPlayers: { [Player]: boolean } = {}

local function rand(n: number): number
	return rng:NextInteger(1, math.max(1, n))
end

local function sub(name: string): any
	local m = script.Parent and script.Parent:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliWork] " .. name .. " failed: " .. tostring(res))
	end
	return nil
end

local function send(player: Player, payload: any)
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function saveOf(player: Player): any?
	local d = Profiles.get(player)
	if not d then
		return nil
	end
	if type(d.work) ~= "table" or d.work.v ~= 1 then
		d.work = WS.sanitizeSave(d.work)
	end
	return d.work
end

local function trackLevel(player: Player, track: string): (number, number, number?, string, string)
	local s = saveOf(player)
	local xp = s and s.xp[track] or 0
	local lv = WS.level(xp)
	local nextXp = WS.levelProgress(xp)
	return lv, xp, nextXp, WS.levelTitle(track, lv), WS.levelRank(lv)
end
Work.trackLevel = trackLevel

function Work.trackInfo(player: Player): { [string]: any }
	local out = {}
	for track in C.LEVELS.titles do
		local lv, xp, nextXp, title, rank = trackLevel(player, track)
		out[track] = { level = lv, xp = xp, nextXp = nextXp, title = title, rank = rank }
	end
	return out
end

local function fireEvent(kind: string, info: any)
	if not workEvents then
		local e = game:GetService("ServerStorage"):FindFirstChild("GwangalliWorkEvents")
		workEvents = if e and e:IsA("BindableEvent") then e else nil
	end
	if workEvents then
		pcall(function()
			(workEvents :: BindableEvent):Fire(kind, info)
		end)
	end
end

local function allLevels(player: Player): { [string]: number }
	local out = {}
	for track in C.LEVELS.titles do
		out[track] = trackLevel(player, track)
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Stores
-------------------------------------------------------------------------------------------------
local function storeFor(jobId: string): any?
	local st = stores[jobId]
	if st then
		return st
	end
	local job = C.JOBS[jobId]
	local K = job and KINDS[job.work]
	if not K then
		return nil
	end
	local dest = ctx.dest(job.place)
	if not dest then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "GwangalliWork_" .. jobId
	folder:SetAttribute("Place", job.place)
	folder:SetAttribute("Open", false)
	folder:SetAttribute("Clerks", 0)
	folder.Parent = workspace
	st = {
		id = jobId,
		jobId = jobId,
		job = job,
		K = K,
		dest = dest,
		cf = dest.CFrame,
		folder = folder,
		items = {},
		workers = {},
		open = false,
		level = 1,
		nextArrival = 0,
		testSerial = 0,
		extraStations = {},
		lastEvent = 0,
	}
	stores[jobId] = st
	local ok, err = pcall(K.build, st)
	if not ok then
		warn("[GwangalliWork] build " .. jobId .. " failed: " .. tostring(err))
	end
	return st
end
Work.storeFor = storeFor

local function markStore(store: any)
	for p in store.workers do
		dirtyPlayers[p] = true
	end
	for p, s in sessions do
		if s.storeId == store.id then
			dirtyPlayers[p] = true
		end
	end
end

local function leadOf(store: any): any?
	local lead = nil
	for _, s in store.workers do
		if s.startedAt and (not lead or s.startedAt < lead.startedAt) then
			lead = s
		end
	end
	return lead
end

local function phaseOf(store: any): (string, number, number, number)
	local lead = leadOf(store)
	if not lead then
		return "prep", 1, 0, 0
	end
	local t = os.clock() - lead.startedAt
	local id, idx, prog = WS.phaseAt(t, lead.length)
	return id, idx, prog, t
end

-------------------------------------------------------------------------------------------------
-- Callbacks the store kinds use (W.*)
-------------------------------------------------------------------------------------------------
local W = {}

function W.newItem(store: any, kind: string, fields: any?): any
	itemSerial += 1
	local item = fields or {}
	item.id = "i" .. itemSerial
	item.kind = kind
	store.items[item.id] = item
	return item
end

function W.destroyItem(store: any, item: any)
	store.items[item.id] = nil
	Props.destroy(item)
end

function W.hold(player: Player, sess: any, item: any)
	table.insert(sess.held, item.id)
	item.loc = { type = "hand", player = player }
	Props.hold(item, player, #sess.held)
	local store = stores[sess.storeId]
	if store then
		Props.sound(item.model and item.model.PrimaryPart, "pickup", 0.35)
	end
end

-- take the first held item out of the hand (the caller places it somewhere)
function W.take(player: Player, sess: any): any?
	local store = stores[sess.storeId]
	local id = table.remove(sess.held, 1)
	local item = id and store and store.items[id]
	if item then
		item.loc = nil
	end
	-- the second hand item (tray) moves to the right hand
	if sess.held[1] and store then
		local other = store.items[sess.held[1]]
		if other then
			Props.hold(other, player, 1)
		end
	end
	return item
end

-- put the held supply / rag back (gone from the world)
function W.drop(player: Player, sess: any)
	local store = stores[sess.storeId]
	local item = W.take(player, sess)
	if item and store then
		W.destroyItem(store, item)
	end
end
W.dropDestroy = W.drop

function W.stationPart(store: any, station: string): BasePart?
	for _, s in store.stationList do
		if s.id == station then
			if not s.part then
				local p = Props.part(store.folder, "StationAnchor_" .. station, Vector3.new(0.2, 0.2, 0.2), CFrame.new(s.pos + Vector3.new(0, 0.5, 0)), Color3.new(1, 1, 1), { transparency = 1 })
				s.part = p
			end
			return s.part
		end
	end
	return nil
end

function W.addStation(store: any, s: any)
	table.insert(store.stationList, s)
	markStore(store)
end

function W.removeStation(store: any, id: string)
	for i, s in store.stationList do
		if s.id == id then
			if s.part then
				s.part:Destroy()
			end
			table.remove(store.stationList, i)
			break
		end
	end
	markStore(store)
end

function W.phaseOf(store: any): string
	return (phaseOf(store))
end

function W.dirty(store: any)
	markStore(store)
end

function W.toast(player: Player, text: string, kind: string?, extra: any?)
	local p = { op = "toast", text = text, kind = kind or "info" }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	send(player, p)
end

function W.storeToast(store: any, text: string, kind: string?)
	for p in store.workers do
		W.toast(p, text, kind)
	end
end

function W.announce(store: any, text: string)
	for p in store.workers do
		W.toast(p, text, "call")
	end
end

function W.orderSummary(o: any): string
	local names = {}
	for _, it in o.items do
		table.insert(names, if o.kind == "cafe" then WS.specText(it.spec) else (it.label or "?"))
	end
	return table.concat(names, ", ")
end

local function addXp(player: Player, sess: any, amount: number)
	local save = saveOf(player)
	if not save or amount <= 0 then
		return
	end
	local track = sess.track
	local before = WS.level(save.xp[track] or 0)
	save.xp[track] = (save.xp[track] or 0) + amount
	sess.xpGain += amount
	local after = WS.level(save.xp[track])
	if after > before then
		local unlocks = WS.unlocksAt(track, after)
		sess.levelUps = sess.levelUps or {}
		table.insert(sess.levelUps, { level = after, unlocks = unlocks })
		send(player, { op = "levelup", track = track, level = after, title = WS.levelTitle(track, after), unlocks = unlocks })
		sess.level = math.max(sess.level, after)
		local store = stores[sess.storeId]
		if store then
			store.level = math.max(store.level, after)
			if store.K.refreshLights then
				pcall(store.K.refreshLights, store)
			end
		end
	end
	Profiles.markDirty(player)
end
W.xp = addXp

-- a non-order work unit (restock, cleaning ...): small performance pay
function W.task(player: Player, sess: any, kind: string, perf: number)
	sess.tasks += 1
	sess.taskPerf += perf
	addXp(player, sess, C.XP.task)
	W.toast(player, string.format("+%s · %s", WS.won(perf), ({ restock = "재료 보충", clean = "머신 청소", trash = "쓰레기 비우기", mop = "바닥 청소", shelf = "진열", fridge = "냉장고 보충", face = "매대 정리" })[kind] or "작업"), "reward")
end

-- one paid work unit outside the order registry (배달 1건, 택배 접수, 진상 응대 ...)
-- unit = { perf, accuracy 0..1, exact, fast, group? }; label = toast text
function W.unit(player: Player, sess: any, unit: any, label: string?, xp: number?)
	local u = { perf = math.max(0, tonumber(unit.perf) or 0), accuracy = math.clamp(tonumber(unit.accuracy) or 1, 0, 1), exact = unit.exact == true, fast = unit.fast == true, group = unit.group == true, order = unit.order }
	table.insert(sess.units, u)
	if unit.satisfaction then
		sess.satTotal += unit.satisfaction
		sess.satCount += 1
	end
	addXp(player, sess, xp or (C.XP.order + (if u.exact then C.XP.perfectExtra else 0)))
	local est = u.perf * u.accuracy + (if u.exact then u.perf * C.PAY.accuracyBonus else 0) + (if u.fast then u.perf * C.PAY.serviceBonus else 0)
	W.toast(player, string.format("+%s 예상 · %s", WS.won(WS.round100(est)), label or (if u.exact then "완벽!" else string.format("정확도 %d%%", math.floor(u.accuracy * 100)))), "reward", { sound = "coin", satisfaction = unit.satisfaction })
	dirtyPlayers[player] = true
end

-- an extra 정산 line (aggregated per key): 손님 팁, 우천 할증, 단체 배달 보너스 ...
function W.extra(player: Player?, sess: any, key: string, label: string, amount: number, note: string?)
	if amount <= 0 then
		return
	end
	sess.extras = sess.extras or {}
	local e = sess.extras[key]
	if not e then
		e = { key = key, label = label, amount = 0, n = 0 }
		sess.extras[key] = e
	end
	e.amount += amount
	e.n += 1
	e.note = note or string.format("%d건", e.n)
	if player then
		dirtyPlayers[player] = true
	end
end

function W.tip(player: Player, sess: any, amount: number, who: string?)
	W.extra(player, sess, "tip", "손님 팁", amount)
	W.toast(player, string.format("💝 %s 팁 +%s", who or "손님", WS.won(amount)), "reward", { sound = "coin" })
end

-- a mistake that costs performance pay (never the base pay): shown in the 정산 as 실수 차감
function W.penalty(player: Player, sess: any, label: string, amount: number, text: string?)
	sess.penalties = sess.penalties or {}
	table.insert(sess.penalties, { label = label, amount = math.max(0, amount) })
	sess.mistakes = (sess.mistakes or 0) + 1
	W.toast(player, text or string.format("⚠️ %s · 성과급 -%s", label, WS.won(amount)), "bad", { sound = "error" })
	dirtyPlayers[player] = true
end

function W.levelOf(sess: any): number
	return sess.level or 1
end

function W.session(player: Player): any?
	return sessions[player]
end

function W.closeTask(store: any, player: Player, sess: any, id: string)
	if store.close[id] then
		return
	end
	store.close[id] = true
	addXp(player, sess, C.XP.closeTask)
	W.storeToast(store, "✅ 마감: " .. ((store.K.CLOSE_LABEL and store.K.CLOSE_LABEL[id]) or id), "good")
	markStore(store)
end

-- a step was done on the held item (sound / hint refresh)
function W.afterStep(player: Player, sess: any, _item: any)
	dirtyPlayers[player] = true
end

function W.requestEnd(player: Player)
	local sess = sessions[player]
	if not sess then
		return
	end
	local store = stores[sess.storeId]
	local early = true
	if store and sess.startedAt then
		local t = os.clock() - sess.startedAt
		local allDone = true
		for _, v in store.close or {} do
			if not v then
				allDone = false
			end
		end
		early = t < sess.length or not allDone
	end
	send(player, { op = "endPrompt", early = early, text = if early then "지금 퇴근하면 근무한 시간의 기본급과 이미 전달한 주문의 성과급만 받아요. 마감 수당은 없어요." else "마감까지 끝냈어요. 정산하고 퇴근할까요?" })
end

function W.markPlayer(player: Player)
	dirtyPlayers[player] = true
end

function W.ctx(): any
	return ctx
end

function W.customers(): any
	return Customers
end

function W.calledOrder(store: any, o: any)
	if o.source == "test" then
		-- the test customer comes to the pick-up counter after a moment
		task.delay(2 + rng:NextNumber() * 2, function()
			if o.state == "ready" then
				Orders.receive(o.id)
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- Orders hooks
-------------------------------------------------------------------------------------------------
local function storeOfOrder(o: any): any?
	return stores[o.store]
end

local function placeOrder(storeId: string, customerId: any, items: { any }?, info: any?): (any?, string?)
	local store = stores[storeId] or storeFor(storeId)
	if not store or not store.open then
		return nil, "store closed"
	end
	local specs = {}
	if type(items) == "table" and #items > 0 then
		for _, it in items do
			if store.K.validSpec and store.K.validSpec(it) then
				table.insert(specs, it)
			elseif store.K.kind == "cafe" and WS.validItem(it) then
				table.insert(specs, it)
			end
		end
		if #specs == 0 then
			return nil, "no valid items"
		end
	else
		specs = store.K.genOrder(store, rand, store.level, false)
	end
	local CK = C[string.upper(store.K.kind)] or C.CAFE
	local patience = (info and tonumber(info.patience)) or (CK.patience.base + CK.patience.perItem * #specs)
	local target = CK.targetSeconds.base + CK.targetSeconds.perItem * #specs
	local o, err = Orders.create(storeId, customerId, specs, { source = (info and info.source) or "npc", name = info and info.name, patience = patience, target = target, kind = store.K.kind, confirmed = info and info.confirmed, meta = info and info.meta, persona = info and info.persona, strict = info and info.strict, noRemake = (info and info.noRemake) or store.K.kind == "cvs", group = info and info.group })
	if o and store.K.onOrder then
		pcall(store.K.onOrder, store, o)
	end
	markStore(store)
	return o, err
end

local function onResolved(o: any, result: any)
	local store = storeOfOrder(o)
	if not store then
		return
	end
	if result.reaction == "left" then
		for p, s in store.workers do
			s.walkouts += 1
			W.toast(p, string.format("😞 #%d 손님이 기다리다 떠났어요", o.number), "warn")
		end
		if store.K.onCancelled then
			pcall(store.K.onCancelled, store, o)
		end
		markStore(store)
		return
	end
	if result.remake then
		local probs = {}
		for _, it in o.items do
			for _, iss in it.issues or {} do
				if iss.severity ~= "todo" then
					table.insert(probs, iss.text)
				end
			end
		end
		for p in store.workers do
			W.toast(p, string.format("😠 #%d 손님: 주문한 거랑 달라요! 다시 만들어 주세요 (%s)", o.number, table.concat(probs, ", ")), "bad")
		end
		for _, s in store.workers do
			s.remakes += 1
		end
	elseif store.K.unitPerOrder then
		-- one unit for the whole order (편의점 계산 1건): credited to the worker who rang it up
		local maker = o.worker
		local sess = maker and sessions[maker]
		if not sess or sess.storeId ~= store.id or not sess.startedAt then
			maker = next(store.workers)
			sess = maker and sessions[maker]
		end
		if sess and maker then
			local acc, exact = 0, true
			for _, it in o.items do
				acc += it.accuracy or 0
				if not it.exact then
					exact = false
				end
			end
			acc = if #o.items > 0 then acc / #o.items else 0
			local perf = if store.K.perfOf then store.K.perfOf(nil, o) else C.CVS.perfBase
			local face = ({ thanks = "😊", ok = "🙂", complain = "😕", angry = "😠" })[result.reaction] or ""
			W.unit(maker, sess, { perf = perf, accuracy = acc, exact = exact, fast = result.waited <= o.target, group = o.group, order = o.id, satisfaction = result.satisfaction }, string.format("#%d %s %s", o.number, if exact then "완벽!" else string.format("정확도 %d%%", math.floor(acc * 100)), face))
		end
	else
		-- credit each item to whoever made it (falls back to any worker)
		for _, it in o.items do
			local item = it.itemId and store.items[it.itemId]
			local maker = item and item.maker
			local sess = maker and sessions[maker]
			if not sess or sess.storeId ~= store.id or not sess.startedAt then
				maker = next(store.workers)
				sess = maker and sessions[maker]
			end
			if sess and maker then
				local perf = if store.K.perfOf then store.K.perfOf(it.spec, o) else WS.cafePerf(it.spec)
				local unit = { perf = perf, accuracy = it.accuracy or 0, exact = it.exact == true, fast = result.waited <= o.target, group = o.group, order = o.id }
				table.insert(sess.units, unit)
				sess.satTotal += result.satisfaction
				sess.satCount += 1
				local est = perf * unit.accuracy + (if unit.exact then perf * C.PAY.accuracyBonus else 0) + (if unit.fast then perf * C.PAY.serviceBonus else 0)
				addXp(maker, sess, C.XP.order + (if unit.exact then C.XP.perfectExtra else 0))
				local face = ({ thanks = "😊 감사해요!", ok = "🙂", complain = "😕 조금 아쉬워요", angry = "😠" })[result.reaction] or ""
				W.toast(maker, string.format("+%s 예상 · #%d %s %s", WS.won(WS.round100(est)), o.number, if unit.exact then "완벽!" else string.format("정확도 %d%%", math.floor(unit.accuracy * 100)), face), "reward", { sound = "coin", satisfaction = result.satisfaction })
			end
		end
	end
	if store.K.onResolved then
		pcall(store.K.onResolved, store, o, result)
	end
	markStore(store)
end

local function judge(o: any)
	local store = storeOfOrder(o)
	if store and store.K.judge then
		store.K.judge(store, o)
	end
end

-------------------------------------------------------------------------------------------------
-- Uniform (apron / vest with the store name, welded to the torso; everyone sees it)
-------------------------------------------------------------------------------------------------
local function removeUniform(sess: any)
	if sess.uniform then
		if sess.uniform.Parent then
			sess.uniform:Destroy()
		end
		sess.uniform = nil
	end
end

local function attachUniform(player: Player, sess: any)
	removeUniform(sess)
	local u = C.JOBS[sess.jobId] and C.JOBS[sess.jobId].uniform
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not u or not torso or not torso:IsA("BasePart") then
		return
	end
	local apron = Instance.new("Part")
	apron.Name = "WorkUniform"
	apron.Size = Vector3.new(math.max(1.5, torso.Size.X * 0.82), math.max(1.4, torso.Size.Y * 1.1), 0.08)
	apron.Color = Props.rgb(u.color)
	apron.Material = Enum.Material.Fabric
	apron.CanCollide = false
	apron.CanQuery = false
	apron.CanTouch = false
	apron.Massless = true
	apron.CastShadow = false
	apron.CFrame = torso.CFrame * CFrame.new(0, -0.2, -(torso.Size.Z / 2 + 0.05))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = apron
	weld.Parent = apron
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.MaxDistance = 50
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 0.3)
	t.Position = UDim2.fromScale(0, 0.1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = if u.color[1] + u.color[2] + u.color[3] > 600 then Color3.fromRGB(30, 30, 30) else Color3.new(1, 1, 1)
	t.Text = u.text
	t.Parent = gui
	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(0.6, 0.14)
	name.Position = UDim2.fromScale(0.2, 0.45)
	name.BackgroundColor3 = Color3.new(1, 1, 1)
	name.TextColor3 = Color3.fromRGB(30, 30, 30)
	name.TextScaled = true
	name.Font = Enum.Font.GothamBold
	name.Text = player.DisplayName
	name.Parent = gui
	gui.Parent = apron
	apron.Parent = char
	sess.uniform = apron
end

-------------------------------------------------------------------------------------------------
-- Job board (구직 공고)
-------------------------------------------------------------------------------------------------
local Garage: any = nil
local function goalPrice(goal: any): (number?, string?)
	if not goal then
		return nil, nil
	end
	if goal.kind == "car" then
		if not Garage then
			local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
			if m then
				local ok, res = pcall(require, m)
				if ok then
					Garage = res
				end
			end
		end
		if Garage and Garage.price then
			local ok, p = pcall(Garage.price, goal.id, goal.grade or "used")
			if ok and type(p) == "number" then
				local cat = Garage.CATALOG and Garage.CATALOG[goal.id]
				return p, string.format("%s %s", cat and cat.label or goal.id, if goal.grade == "new" then "신차" else "중고")
			end
		end
	elseif goal.kind == "home" then
		local l = G.LISTINGS and G.LISTINGS[goal.id]
		if l then
			local p = l[goal.field or "deposit"] or l.price or l.deposit
			return p, l.name .. (if goal.field == "deposit" then " 보증금" else "")
		end
	elseif goal.kind == "furniture" then
		local f = G.FURNITURE and G.FURNITURE[goal.id]
		if f then
			return f.price, f.name
		end
	end
	return nil, nil
end

local function moneyOf(player: Player): number
	local d = Profiles.get(player)
	return d and ((d.cash or 0) + (d.bank or 0)) or 0
end

local function goalView(player: Player, gained: number?): any?
	local save = saveOf(player)
	local goal = save and save.goal
	if not goal then
		return nil
	end
	local price, name = goalPrice(goal)
	if not price then
		return nil
	end
	local have = moneyOf(player)
	local avg = 0
	local n = 0
	for _, h in save.history do
		avg += h.net
		n += 1
	end
	avg = if n > 0 then avg / n else 0
	local left = math.max(0, price - have)
	return {
		name = name,
		price = price,
		have = have,
		progress = math.clamp(have / math.max(1, price), 0, 1),
		before = if gained then math.clamp((have - gained) / math.max(1, price), 0, 1) else nil,
		gained = gained,
		left = left,
		shifts = if avg > 0 and left > 0 then math.ceil(left / avg) else (if left <= 0 then 0 else nil),
		avg = math.floor(avg),
	}
end

local function boardView(player: Player): any
	local d = Profiles.get(player)
	local save = saveOf(player)
	local levels = allLevels(player)
	local postings = {}
	for _, jobId in C.JOB_ORDER do
		local job = C.JOBS[jobId]
		local lv = levels[job.track] or 1
		local rate = WS.baseRate(lv)
		local ok, why = WS.canApply(jobId, levels)
		local lengths = {}
		for _, l in C.SHIFT.lengths do
			table.insert(lengths, { id = l.id, label = l.label, seconds = l.seconds, base = WS.round100(rate * l.seconds / 60) })
		end
		local nextXp, prog = WS.levelProgress(save and save.xp[job.track] or 0)
		table.insert(postings, {
			jobId = jobId,
			title = job.title,
			place = job.place,
			icon = job.icon,
			duty = job.duty,
			perf = job.perf,
			rate = rate,
			lengths = lengths,
			canApply = ok,
			requires = why,
			applied = d and d.job and d.job.id == (job.gjob or jobId) or false,
			ready = KINDS[job.work] ~= nil,
			level = lv,
			levelTitle = WS.levelTitle(job.track, lv),
			rank = WS.levelRank(lv),
			xp = save and save.xp[job.track] or 0,
			xpNext = nextXp,
			xpProgress = prog,
			nextUnlocks = if lv < #C.LEVELS.xp then WS.unlocksAt(job.track, lv + 1) else {},
		})
	end
	local goals = {}
	for i, g in C.GOALS do
		local price, name = goalPrice(g)
		if price then
			table.insert(goals, { index = i, name = name or g.label, price = price, kind = g.kind, selected = save and save.goal and save.goal.kind == g.kind and save.goal.id == g.id and (save.goal.field or "") == (g.field or "") })
		end
	end
	return { op = "board", postings = postings, goal = goalView(player), goals = goals, length = save and save.length or C.SHIFT.defaultLength, hints = save and save.hints, onShift = sessions[player] ~= nil }
end

-------------------------------------------------------------------------------------------------
-- Shift lifecycle
-------------------------------------------------------------------------------------------------
local shiftSerial = 0

function Work.handles(jobId: any): boolean
	local job = type(jobId) == "string" and C.JOBS[jobId]
	return job ~= nil and KINDS[job.work] ~= nil
end

function Work.onShift(player: Player): boolean
	return sessions[player] ~= nil
end

function Work.startShift(player: Player, jobId: string?, lengthId: string?): boolean
	local d = Profiles.get(player)
	if not d then
		return false
	end
	if sessions[player] then
		W.toast(player, "이미 근무 중이에요", "info")
		return false
	end
	local id = jobId or (d.job and d.job.id)
	if not id or not Work.handles(id) then
		return false
	end
	do
		local ok, why = WS.canApply(id, allLevels(player))
		if not ok then
			local fb = C.JOBS[id].fallback
			if fb and Work.handles(fb) and WS.canApply(fb, allLevels(player)) then
				W.toast(player, string.format("%s · 아직은 %s부터 시작해요", why or "숙련도 부족", C.JOBS[fb].title), "info")
				id = fb
			else
				W.toast(player, why or "지원할 수 없어요", "warn")
				return false
			end
		end
	end
	local gid = C.JOBS[id].gjob or id
	if not d.job or d.job.id ~= gid then
		ctx.applyJob(player, gid, "board")
		if not d.job or d.job.id ~= gid then
			return false
		end
	end
	if ctx.onShift and ctx.onShift(player) then
		W.toast(player, "다른 근무 중이에요 · 먼저 퇴근하세요", "warn")
		return false
	end
	local store = storeFor(id)
	if not store then
		W.toast(player, "가게를 찾을 수 없어요", "warn")
		return false
	end
	local save = saveOf(player)
	local lenId = lengthId or (save and save.length) or C.SHIFT.defaultLength
	if save and (lenId == "short" or lenId == "normal" or lenId == "long") then
		save.length = lenId
	end
	local job = C.JOBS[id]
	local lv = trackLevel(player, job.track)
	shiftSerial += 1
	local sess = {
		id = string.format("W%d-%d-%d", player.UserId, os.time(), shiftSerial),
		jobId = id,
		storeId = id,
		track = job.track,
		state = "commute",
		length = WS.shiftLength(lenId),
		lengthId = lenId,
		startedAt = nil,
		commuteAt = os.clock(),
		level = lv,
		startLevel = lv,
		units = {},
		tasks = 0,
		taskPerf = 0,
		held = {},
		focus = nil,
		xpGain = 0,
		waste = 0,
		walkouts = 0,
		remakes = 0,
		satTotal = 0,
		satCount = 0,
		hints = (save and save.hints) or C.LEVELS.hintsByLevel[lv] or 1,
		lastAct = 0,
		near = {},
		moneyBefore = moneyOf(player),
		extras = {},
		penalties = {},
		mistakes = 0,
	}
	sessions[player] = sess
	pcall(ctx.setWaypoint, player, job.place)
	W.toast(player, string.format("%s %s 출근하세요 · 직원 출입구의 출퇴근 단말기에서 출근 체크", job.icon, job.place), "job")
	dirtyPlayers[player] = true
	return true
end

local function updateStoreAttrs(store: any)
	local n = 0
	for _ in store.workers do
		n += 1
	end
	pcall(function()
		store.folder:SetAttribute("Open", store.open == true)
		store.folder:SetAttribute("Clerks", n)
	end)
end

local function clockIn(player: Player, sess: any)
	local store = stores[sess.storeId]
	if not store then
		return
	end
	sess.state = "work"
	sess.startedAt = os.clock()
	store.workers[player] = sess
	store.level = math.max(store.level, sess.level)
	if not store.open then
		store.K.activate(store)
		store.nextArrival = os.clock() + 8
		store.lastEvent = os.clock()
		if Customers and store.K.site then
			local ok, err = pcall(Customers.open, store)
			if not ok then
				warn("[GwangalliWork] customers " .. store.id .. ": " .. tostring(err))
			end
		end
	end
	if store.K.onClockIn then
		pcall(store.K.onClockIn, store, player, sess)
	end
	attachUniform(player, sess)
	pcall(ctx.setWaypoint, player, nil)
	player:SetAttribute("GwWorkShift", sess.jobId)
	player:SetAttribute("GwWorkTrack", sess.track)
	updateStoreAttrs(store)
	fireEvent("shiftStart", { player = player, userId = player.UserId, jobId = sess.jobId, track = sess.track, place = C.JOBS[sess.jobId].place, level = sess.level, shiftId = sess.id })
	W.toast(player, string.format("✅ 출근 체크 · 유니폼 착용 · %s (%d분 근무) · 오픈 준비부터!", C.JOBS[sess.jobId].title, math.floor(sess.length / 60)), "good", { sound = "ready" })
	markStore(store)
end

-- release everything a leaving worker had (held items, claims, machine heads keep their cups)
local function releaseWorker(player: Player, sess: any)
	local store = stores[sess.storeId]
	removeUniform(sess)
	player:SetAttribute("GwWorkShift", nil)
	player:SetAttribute("GwWorkTrack", nil)
	if not store then
		return
	end
	for _, id in sess.held do
		local item = store.items[id]
		if item then
			if item.kind == "cup" and item.orderId then
				local o = Orders.get(item.orderId)
				local it = o and o.items[item.itemIndex]
				if it and it.cupId == item.id then
					it.cupId = nil
				end
			end
			if item.kind == "pitcher" then
				-- a pitcher always goes back to its stand
				local slot = item.slotIndex or 1
				store.slots.steam[slot] = item.id
				Props.put(item, store.folder, store.cf * CFrame.new(table.unpack(store.K.LAYOUT.stations.steam.slots[slot])))
			else
				W.destroyItem(store, item)
			end
		end
	end
	sess.held = {}
	store.workers[player] = nil
	if store.K.releasePlayer then
		pcall(store.K.releasePlayer, store, player, sess)
	end
	if next(store.workers) == nil and store.open then
		if Customers and store.K.site then
			pcall(Customers.close, store)
		end
		Orders.closeStore(store.id, "store closed")
		store.K.deactivate(store)
	end
	updateStoreAttrs(store)
	if sess.startedAt then
		fireEvent("shiftEnd", { player = player, userId = player.UserId, jobId = sess.jobId, track = sess.track, place = C.JOBS[sess.jobId].place, level = sess.level, shiftId = sess.id })
	end
	markStore(store)
end

local function extrasList(sess: any): { any }
	local out = {}
	for _, e in sess.extras or {} do
		table.insert(out, e)
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

-- the 정산 (and pay-out, once)
local function finish(player: Player, reason: string, opts: any?)
	local sess = sessions[player]
	if not sess or sess.settled then
		return
	end
	sess.settled = true
	local store = stores[sess.storeId]
	local early = true
	local closeDone = false
	local worked = 0
	if sess.startedAt then
		local t = os.clock() - sess.startedAt
		worked = math.min(t, sess.length + C.SHIFT.closeGrace)
		closeDone = true
		for _, v in (store and store.close) or {} do
			if not v then
				closeDone = false
			end
		end
		early = t < sess.length - 1 or (opts and opts.disconnect == true)
	end
	local summary = WS.settle({ level = sess.startLevel, workedSeconds = worked, early = early, closeDone = closeDone, units = sess.units, tasks = sess.tasks, taskPerf = sess.taskPerf, extras = extrasList(sess), penalties = sess.penalties })
	if sess.startedAt and not early and closeDone then
		addXp(player, sess, C.XP.shiftComplete)
	end
	releaseWorker(player, sess)
	sessions[player] = nil
	local d = Profiles.get(player)
	local save = saveOf(player)
	local paid = 0
	if d and save and not WS.isPaid(save, sess.id) then
		if summary.total > 0 then
			local job = C.JOBS[sess.jobId]
			if ctx.ledger(player, "bank", summary.total, string.format("급여 · %s %s", job.place, if early then "(중도 퇴근)" else "(근무 완료)"), true) then
				paid = summary.total
			end
		end
		table.insert(save.paid, sess.id)
		while #save.paid > 40 do
			table.remove(save.paid, 1)
		end
		table.insert(save.history, { t = os.time(), job = sess.jobId, net = paid })
		while #save.history > 10 do
			table.remove(save.history, 1)
		end
		save.open = nil
		Profiles.markDirty(player)
		if Profiles.saveSoon then
			pcall(Profiles.saveSoon, player, 2)
		end
	end
	if player.Parent ~= Players then
		fireEvent("settle", { player = player, userId = player.UserId, jobId = sess.jobId, track = sess.track, place = C.JOBS[sess.jobId].place, level = sess.level, shiftId = sess.id, total = summary.total, paid = paid, early = early })
		return
	end
	local exact, acc = 0, 0
	for _, u in sess.units do
		acc += u.accuracy
		if u.exact then
			exact += 1
		end
	end
	local nextXp, prog = WS.levelProgress(save and save.xp[sess.track] or 0)
	local lv = WS.level(save and save.xp[sess.track] or 0)
	send(player, {
		op = "settle",
		reason = reason,
		early = early,
		job = sess.jobId,
		title = C.JOBS[sess.jobId].title,
		icon = C.JOBS[sess.jobId].icon,
		place = C.JOBS[sess.jobId].place,
		lines = summary.lines,
		total = summary.total,
		paid = paid,
		worked = worked,
		orders = #sess.units,
		exact = exact,
		accuracy = if #sess.units > 0 then math.floor(acc / #sess.units * 100 + 0.5) else nil,
		satisfaction = if sess.satCount > 0 then math.floor(sess.satTotal / sess.satCount + 0.5) else nil,
		walkouts = sess.walkouts,
		remakes = sess.remakes,
		waste = sess.waste,
		tasks = sess.tasks,
		closeDone = closeDone,
		xpGain = sess.xpGain,
		level = lv,
		levelTitle = WS.levelTitle(sess.track, lv),
		xpNext = nextXp,
		xpProgress = prog,
		levelUps = sess.levelUps,
		nextUnlocks = if lv < #C.LEVELS.xp then WS.unlocksAt(sess.track, lv + 1) else {},
		goal = goalView(player, paid),
		mistakes = sess.mistakes,
		rank = WS.levelRank(lv),
	})
	fireEvent("settle", { player = player, userId = player.UserId, jobId = sess.jobId, track = sess.track, place = C.JOBS[sess.jobId].place, level = lv, shiftId = sess.id, total = summary.total, paid = paid, early = early })
end
Work.finish = finish

function Work.endShift(player: Player)
	if sessions[player] then
		finish(player, "퇴근", nil)
	end
end

-------------------------------------------------------------------------------------------------
-- Client state
-------------------------------------------------------------------------------------------------
local function nearStations(store: any, player: Player, sess: any): { any }
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return {}
	end
	local pos = root.Position
	local look = root.CFrame.LookVector
	local list = {}
	for _, s in store.stationList do
		if sess.state == "commute" and s.id ~= "timeclock" then
			continue
		end
		if s.owner and s.owner ~= player then
			continue
		end
		local d = s.pos - pos
		local flat = Vector3.new(d.X, 0, d.Z)
		local dist = flat.Magnitude
		local reach = if sess.state == "commute" then C.SHIFT.clockInRadius * 0.4 else (s.reach or C.SHIFT.reachDistance)
		if dist <= reach and math.abs(d.Y) < (s.reachY or 9) then
			local facing = if dist > 0.1 then look:Dot(flat.Unit) else 1
			table.insert(list, { s = s, score = dist - 1.4 * facing })
		end
	end
	table.sort(list, function(a, b)
		return a.score < b.score
	end)
	local out = {}
	for i = 1, math.min(2, #list) do
		table.insert(out, list[i].s)
	end
	if sess.state == "work" and store.K.globalStations then
		local ok, extra = pcall(store.K.globalStations, store, player, sess)
		if ok and type(extra) == "table" then
			for _, g in extra do
				g.global = true
				table.insert(out, g)
			end
		end
	end
	return out
end

local function stateView(player: Player, sess: any): any
	local store = stores[sess.storeId]
	local job = C.JOBS[sess.jobId]
	local now = os.clock()
	local out: any = { op = "state", job = sess.jobId, state = sess.state, title = job.title, icon = job.icon, place = job.place, track = sess.track }
	local save = saveOf(player)
	local xp = save and save.xp[sess.track] or 0
	local nextXp, prog = WS.levelProgress(xp)
	out.level = WS.level(xp)
	out.levelTitle = WS.levelTitle(sess.track, out.level)
	out.xp = xp
	out.xpNext = nextXp
	out.xpProgress = prog
	out.hints = sess.hints
	out.rank = WS.levelRank(out.level)
	out.kind = store and store.K.kind
	out.test = store and not store.K.noTestCustomers and not Orders.hasProvider(store.id) or false
	out.mistakes = sess.mistakes
	if sess.state == "commute" then
		local tc = nil
		for _, s in store.stationList do
			if s.id == "timeclock" then
				tc = s
			end
		end
		out.target = tc and tc.pos or (store and store.dest.Position)
		local near = nearStations(store, player, sess)
		out.near = {}
		if #near > 0 then
			table.insert(out.near, { id = "timeclock", label = "출퇴근 단말기", actions = { { id = "clockin", label = "출근 체크", dur = 0.6, enabled = true, icon = "🪪" } } })
		end
		out.hint = { text = string.format("%s 직원 출입구로 출근 (출퇴근 단말기)", job.place), station = "timeclock", pos = out.target, label = "출퇴근 단말기" }
		return out
	end
	local phase, idx, phaseProg, t = phaseOf(store)
	local def = C.SHIFT.phases[idx]
	out.phase = phase
	out.phaseLabel = def and def.label or phase
	out.phaseIdx = idx
	out.phaseProgress = phaseProg
	out.elapsed = math.floor(now - sess.startedAt)
	out.length = sess.length
	out.timeLeft = math.max(0, math.floor(sess.length - (now - sess.startedAt)))
	out.lastOrders = t >= sess.length * C.SHIFT.lastOrderShare
	local est = WS.settle({ level = sess.startLevel, workedSeconds = math.min(now - sess.startedAt, sess.length + C.SHIFT.closeGrace), early = false, closeDone = false, units = sess.units, tasks = sess.tasks, taskPerf = sess.taskPerf, extras = extrasList(sess), penalties = sess.penalties })
	out.estimate = est.total
	out.units = #sess.units
	-- orders (open + the last result)
	local list = {}
	for _, o in Orders.open(store.id) do
		table.insert(list, Orders.view(o, now))
	end
	table.sort(list, function(a, b)
		local ra = if a.state == "ready" then 2 elseif a.confirmed then 0 else 1
		local rb = if b.state == "ready" then 2 elseif b.confirmed then 0 else 1
		if ra ~= rb then
			return ra < rb
		end
		return a.waited > b.waited
	end)
	out.orders = list
	if sess.focus and not Orders.get(sess.focus) then
		sess.focus = nil
	end
	if sess.focus then
		local o = Orders.get(sess.focus)
		if o and not WS.isOpen(o.state) then
			sess.focus = nil
		end
	end
	if not sess.focus then
		for _, v in list do
			if v.confirmed and v.state ~= "ready" then
				sess.focus = v.id
				break
			end
		end
	end
	out.focus = sess.focus
	out.held = {}
	for _, id in sess.held do
		local item = store.items[id]
		if item then
			table.insert(out.held, store.K.itemView(store, item))
		end
	end
	out.near = {}
	for _, s in sess.near do
		local ok, acts = pcall(store.K.actions, store, player, sess, s.id)
		table.insert(out.near, { id = s.id, label = s.label, actions = if ok then acts else {} })
	end
	if sess.hints > 0 then
		local ok, text, station = pcall(store.K.hint, store, sess)
		if ok and text then
			local pos, label = nil, nil
			for _, s in store.stationList do
				if s.id == station and (not s.owner or s.owner == player) then
					pos = s.pos
					label = s.label
				end
			end
			out.hint = { text = text, station = station, pos = pos, label = label }
		elseif not ok then
			warn("[GwangalliWork] hint: " .. tostring(text))
		end
	end
	out.stock = store.K.stockView(store)
	if store.K.extraView then
		local ok, ev = pcall(store.K.extraView, store, player, sess)
		if ok then
			out.extra = ev
		else
			warn("[GwangalliWork] extraView: " .. tostring(ev))
		end
	end
	out.close = if phase == "close" or out.lastOrders then store.K.closeTasks(store) else nil
	local allDone = true
	for _, c in store.K.closeTasks(store) do
		if not c.done then
			allDone = false
		end
	end
	out.canFinish = out.timeLeft <= 0 and allDone and #Orders.open(store.id) == 0
	out.overtime = out.timeLeft <= 0
	return out
end

local function push(player: Player)
	local sess = sessions[player]
	if not sess then
		return
	end
	local ok, view = pcall(stateView, player, sess)
	if ok then
		send(player, view)
	else
		warn("[GwangalliWork] state failed: " .. tostring(view))
	end
end
Work.push = push

-------------------------------------------------------------------------------------------------
-- Remote
-------------------------------------------------------------------------------------------------
local function handle(player: Player, p: any)
	if type(p) ~= "table" or type(p.op) ~= "string" then
		return
	end
	if not Util.bucket(player, 12, 20) then
		return
	end
	local op = p.op
	if op == "board" then
		send(player, boardView(player))
		return
	elseif op == "apply" then
		local id = Util.str(p.job, 40)
		local ok, why = WS.canApply(id or "", allLevels(player))
		if not ok then
			W.toast(player, why or "지원할 수 없어요", "warn")
		else
			ctx.applyJob(player, (C.JOBS[id] and C.JOBS[id].gjob) or id, "board")
		end
		send(player, boardView(player))
		return
	elseif op == "start" then
		local id = Util.str(p.job, 40)
		local len = Util.str(p.length, 10)
		Work.startShift(player, id, len)
		send(player, boardView(player))
		push(player)
		return
	elseif op == "goal" then
		local save = saveOf(player)
		local g = C.GOALS[tonumber(p.index) or 0]
		if save then
			save.goal = if g then { kind = g.kind, id = g.id, grade = g.grade, field = g.field } else nil
			Profiles.markDirty(player)
		end
		send(player, boardView(player))
		return
	elseif op == "hints" then
		local save = saveOf(player)
		local lv = tonumber(p.level)
		if save and (lv == 0 or lv == 1 or lv == 2) then
			save.hints = lv
			if sessions[player] then
				sessions[player].hints = lv
			end
			Profiles.markDirty(player)
		end
		dirtyPlayers[player] = true
		return
	end
	local sess = sessions[player]
	if not sess then
		return
	end
	if op == "end" then
		finish(player, if p.reason == "early" then "중도 퇴근" else "퇴근", nil)
		return
	elseif op == "cancel" then
		-- leaving the shift before clocking in
		if sess.state == "commute" then
			sessions[player] = nil
			pcall(ctx.setWaypoint, player, nil)
			W.toast(player, "출근을 취소했어요", "info")
			send(player, { op = "closed" })
		end
		return
	elseif op == "focus" then
		local o = Orders.get(p.order)
		if o and o.store == sess.storeId and WS.isOpen(o.state) then
			sess.focus = o.id
			dirtyPlayers[player] = true
		end
		return
	elseif op == "act" then
		local station = Util.str(p.station, 40)
		local action = Util.str(p.action, 80)
		if not station or not action then
			return
		end
		local store = stores[sess.storeId]
		if not store then
			return
		end
		local now = os.clock()
		if now - sess.lastAct < 0.12 then
			return
		end
		-- distance check (server truth); global stations (배달 앱) work anywhere
		local isGlobal = false
		if sess.state == "work" and store.K.globalStations then
			local ok, extra = pcall(store.K.globalStations, store, player, sess)
			if ok and type(extra) == "table" then
				for _, g in extra do
					if g.id == station then
						isGlobal = true
					end
				end
			end
		end
		local spos, sreach = nil, nil
		for _, s in store.stationList do
			if s.id == station and (not s.owner or s.owner == player) then
				spos = s.pos
				sreach = s.reach
			end
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not isGlobal then
			if not spos or not root then
				return
			end
			local d = spos - root.Position
			local reach = if sess.state == "commute" then C.SHIFT.clockInRadius * 0.4 + 2 else (sreach or C.SHIFT.reachDistance) + 2
			if Vector3.new(d.X, 0, d.Z).Magnitude > reach then
				W.toast(player, "조금 더 가까이 가요", "warn")
				return
			end
		end
		sess.lastAct = now
		if sess.state == "commute" then
			if station == "timeclock" and action == "clockin" then
				clockIn(player, sess)
			end
			push(player)
			return
		end
		local ok, res, msg = pcall(store.K.act, store, player, sess, station, action, p.arg)
		if not ok then
			warn("[GwangalliWork] act " .. station .. "/" .. action .. " failed: " .. tostring(res))
			W.toast(player, "앗, 처리하지 못했어요", "warn")
		elseif res == false then
			W.toast(player, msg or "지금은 할 수 없어요", "warn")
		end
		markStore(store)
		push(player)
		return
	end
end
Work.handle = handle

-------------------------------------------------------------------------------------------------
-- Tick: phases, customers, events, timers, near stations, pushes, crash-safe open shift record
-------------------------------------------------------------------------------------------------
local lastTick = os.clock()
local lastSaveRec = 0

local function storeTick(store: any, now: number)
	store.K.tick(store, now)
	Orders.tick(store.id, now)
	if not store.open then
		return
	end
	local lead = leadOf(store)
	if not lead then
		return
	end
	local phase, _, _, t = phaseOf(store)
	local CK = C[string.upper(store.K.kind)] or C.CAFE
	-- test customers while no NPC provider is connected
	if not store.K.noTestCustomers and not Orders.hasProvider(store.id) and CK.arrival and t < lead.length * C.SHIFT.lastOrderShare and now >= store.nextArrival then
		local open = Orders.open(store.id)
		local gap = CK.arrival[phase] or CK.arrival.rush
		store.nextArrival = now + rng:NextNumber(gap[1], gap[2])
		if #open < CK.maxOpenOrders then
			store.testSerial += 1
			local group = phase == "rush" and rng:NextNumber() < (CK.groupChance or 0)
			local specs = store.K.genOrder(store, rand, store.level, group)
			local o = placeOrder(store.id, "test-" .. store.testSerial, specs, { source = "test", name = (if group then "🧪 단체 손님 " else "🧪 테스트 손님 ") .. store.testSerial })
			if o then
				W.storeToast(store, string.format("🔔 손님이 POS 앞에 왔어요%s", if group then string.format(" · 단체 주문 %d잔!", #o.items) else ""), "order")
			end
		end
	end
	-- 주문 변경 (once per order, while still being made)
	if phase == "rush" and store.K.changeSpec and now - store.lastEvent > 12 then
		store.lastEvent = now
		for _, o in Orders.open(store.id) do
			if o.confirmed and not o.changed and o.state ~= "ready" and rng:NextNumber() < (CK.changeChance or 0) * 3 then
				for i, it in o.items do
					if not it.itemId then
						local new, text = store.K.changeSpec(it.spec, rand, store.level)
						if new and Orders.change(o, i, new, text) then
							-- a cup already stickered for it now needs fixing or a remake
							W.storeToast(store, string.format("✏️ #%d 손님: \"%s\"", o.number, text), "change")
							for _, item in store.items do
								if item.orderId == o.id and item.itemIndex == i then
									item.spec = new
								end
							end
							break
						end
					end
				end
				break
			end
		end
	end
	-- overtime: the shift ended; close tasks / last orders get a grace period, then auto 정산
	for p, s in store.workers do
		if s.startedAt and now - s.startedAt > s.length + C.SHIFT.closeGrace then
			task.defer(finish, p, "근무 시간 종료 (자동 정산)", nil)
		end
	end
end

local function tick()
	local now = os.clock()
	local dt = math.min(0.5, now - lastTick)
	lastTick = now
	for _, store in stores do
		local ok, err = pcall(storeTick, store, now)
		if not ok then
			warn("[GwangalliWork] store " .. store.id .. ": " .. tostring(err))
		end
	end
	if Customers then
		local ok, err = pcall(Customers.tick, now)
		if not ok then
			warn("[GwangalliWork] customers: " .. tostring(err))
		end
	end
	for player, sess in sessions do
		if player.Parent ~= Players then
			continue
		end
		local store = stores[sess.storeId]
		if not store then
			continue
		end
		local near = nearStations(store, player, sess)
		local key = ""
		for _, s in near do
			key ..= s.id .. ","
		end
		if key ~= sess.nearKey then
			sess.nearKey = key
			sess.near = near
			dirtyPlayers[player] = true
		end
		if sess.state == "work" and store.K.playerTick then
			local ok, err = pcall(store.K.playerTick, store, player, sess, dt)
			if not ok then
				warn("[GwangalliWork] playerTick: " .. tostring(err))
			end
		end
		if sess.state == "work" and store.K.checkSpill then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local v = root.AssemblyLinearVelocity
				pcall(store.K.checkSpill, store, player, sess, Vector3.new(v.X, 0, v.Z).Magnitude, dt)
			end
		end
		local last = pushAt[player] or 0
		if (dirtyPlayers[player] and now - last > 0.15) or now - last > 0.6 then
			dirtyPlayers[player] = nil
			pushAt[player] = now
			push(player)
		end
	end
	-- crash-safe record of the running shifts (settled on the next load if the server dies)
	if now - lastSaveRec > 10 then
		lastSaveRec = now
		for player, sess in sessions do
			local save = saveOf(player)
			if save and sess.startedAt and not sess.settled then
				local est = WS.settle({ level = sess.startLevel, workedSeconds = 0, units = sess.units, tasks = sess.tasks, taskPerf = sess.taskPerf, extras = extrasList(sess), penalties = sess.penalties })
				save.open = { id = sess.id, job = sess.jobId, level = sess.startLevel, worked = math.min(now - sess.startedAt, sess.length + C.SHIFT.closeGrace), perf = est.total, count = #sess.units, t = os.time() }
				Profiles.markDirty(player)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- API for other systems
-------------------------------------------------------------------------------------------------
function Work.isWorking(player: Player): string?
	local s = sessions[player]
	return if s and s.state == "work" then s.jobId else nil
end

function Work.clerks(jobId: string): { Player }
	local out = {}
	local st = stores[jobId]
	if st then
		for p, s in st.workers do
			if s.state == "work" and p.Parent == Players then
				table.insert(out, p)
			end
		end
	end
	return out
end

function Work.storeState(jobId: string): any?
	local st = stores[jobId]
	if not st then
		return nil
	end
	return { open = st.open == true, clerks = #Work.clerks(jobId), place = st.job.place, phase = (phaseOf(st)) }
end

-- debug hook for headless tests: ServerStorage.GwangalliWorkDebug:Invoke(cmd, player, ...), only while
-- workspace attribute GwangalliStreetLifeDebug == true
local function setupDebug()
	local SS = game:GetService("ServerStorage")
	if SS:FindFirstChild("GwangalliWorkDebug") then
		return
	end
	local bf = Instance.new("BindableFunction")
	bf.Name = "GwangalliWorkDebug"
	bf.OnInvoke = function(cmd: string, player: Player?, a: any, b: any, c: any): any
		if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
			return "debug off"
		end
		if cmd == "start" and player then
			local ok = Work.startShift(player, a, b)
			return ok
		elseif cmd == "clockin" and player then
			local sess = sessions[player]
			if sess and sess.state == "commute" then
				clockIn(player, sess)
				return true
			end
			return false
		elseif cmd == "act" and player then
			-- bypasses the distance check (the test teleports anyway)
			local sess = sessions[player]
			local store = sess and stores[sess.storeId]
			if not store then
				return "no session"
			end
			local ok, res, msg = pcall(store.K.act, store, player, sess, a, b, c)
			markStore(store)
			return tostring(ok) .. " " .. tostring(res) .. " " .. tostring(msg)
		elseif cmd == "acts" and player then
			local sess = sessions[player]
			local store = sess and stores[sess.storeId]
			if not store then
				return "no session"
			end
			local ok, list = pcall(store.K.actions, store, player, sess, a)
			if not ok then
				return "ERR " .. tostring(list)
			end
			local out = {}
			for _, x in list do
				table.insert(out, string.format("%s|%s|%s", x.id, tostring(x.enabled), x.label))
			end
			return table.concat(out, "\n")
		elseif cmd == "teleport" and player then
			-- to a station of the current store (tests)
			local sess = sessions[player]
			local store = sess and stores[sess.storeId]
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if store and root then
				for _, st in store.stationList do
					if st.id == a then
						player.Character:PivotTo(CFrame.new(st.pos + Vector3.new(0.5, 3, 0.5)))
						return true
					end
				end
			end
			return false
		elseif cmd == "state" and player then
			local sess = sessions[player]
			if not sess then
				return nil
			end
			local ok, v = pcall(stateView, player, sess)
			return if ok then v else tostring(v)
		elseif cmd == "end" and player then
			finish(player, "퇴근", nil)
			return true
		elseif cmd == "xp" and player then
			local save = saveOf(player)
			if save then
				save.xp[a] = tonumber(b) or 0
			end
			return true
		elseif cmd == "pos" and player then
			local sess = sessions[player]
			local store = sess and stores[sess.storeId]
			for _, st in (store and store.stationList) or {} do
				if st.id == a then
					return st.pos
				end
			end
			return nil
		elseif cmd == "customers" then
			return Customers and Customers.debug and Customers.debug(a)
		end
		return "unknown"
	end
	bf.Parent = SS
end

-------------------------------------------------------------------------------------------------
-- Feature module hooks
-------------------------------------------------------------------------------------------------
function Work.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	local cfgMod = ReplicatedStorage:WaitForChild("GwangalliWorkConfig", 20)
	local wsMod = ReplicatedStorage:WaitForChild("GwangalliWorkShared", 20)
	C = require(cfgMod)
	WS = require(wsMod)
	WS.setConfig(C)
	Props = sub("WorkProps")
	Orders = sub("WorkOrders")
	Props.init(C, WS)
	Orders.init(C, WS, {
		onChanged = function(storeId: string)
			local st = stores[storeId]
			if st then
				markStore(st)
				if st.K.refreshLights then
					pcall(st.K.refreshLights, st)
				end
			end
		end,
		onResolved = onResolved,
		judge = judge,
		placeOrder = placeOrder,
	})
	Customers = sub("WorkCustomers")
	if Customers then
		local ok, err = pcall(Customers.init, C, WS, Orders, W)
		if not ok then
			warn("[GwangalliWork] WorkCustomers init: " .. tostring(err))
			Customers = nil
		end
	end
	for _, name in { "WorkCafe", "WorkStore", "WorkKitchen", "WorkDelivery" } do
		local K = sub(name)
		if K then
			local ok, err = pcall(K.init, C, WS, Props, Orders, W)
			if ok then
				KINDS[K.kind] = K
			else
				warn("[GwangalliWork] " .. name .. " init: " .. tostring(err))
			end
		end
	end
	setupDebug()
	local folder = ctx.remotes.WorkState and ctx.remotes.WorkState.Parent
	if folder then
		local r = folder:FindFirstChild("Work")
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = "Work"
			r.Parent = folder
		end
		remote = r :: RemoteEvent
		remote.OnServerEvent:Connect(function(player: Player, p: any)
			local ok, err = pcall(handle, player, p)
			if not ok then
				warn("[GwangalliWork] " .. player.Name .. ": " .. tostring(err))
			end
		end)
	end
	ctx.work = Work
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliWork] tick: " .. tostring(err))
			end
		end
	end)
	print("[GwangalliWork] ready: " .. table.concat((function()
		local t = {}
		for k in KINDS do
			table.insert(t, k)
		end
		table.sort(t)
		return t
	end)(), ", "))
end

-- profile loaded: settle a shift the server could not settle (crash), exactly once
function Work.onLoaded(player: Player)
	local save = saveOf(player)
	if not save or not save.open then
		return
	end
	local o = save.open
	if WS.isPaid(save, o.id) then
		save.open = nil
		return
	end
	local summary = WS.settle({ level = o.level, workedSeconds = o.worked, early = true, units = {}, taskPerf = o.perf })
	if summary.total > 0 then
		ctx.ledger(player, "bank", summary.total, "급여 · 미정산 근무 정산 (접속 끊김)", false)
	end
	table.insert(save.paid, o.id)
	table.insert(save.history, { t = os.time(), job = o.job, net = summary.total })
	save.open = nil
	Profiles.markDirty(player)
end

function Work.onCharacter(player: Player, _char: Model?)
	local sess = sessions[player]
	if not sess then
		return
	end
	-- the old character took the held items and the uniform with it
	local store = stores[sess.storeId]
	if store then
		for _, id in sess.held do
			local item = store.items[id]
			if item then
				if item.kind == "pitcher" then
					item.model = nil
					local slot = item.slotIndex or 1
					store.slots.steam[slot] = item.id
					item.milk = "empty"
					Props.create(item, store.folder, store.cf * CFrame.new(table.unpack(store.K.LAYOUT.stations.steam.slots[slot])))
				else
					store.items[id] = nil
				end
			end
		end
	end
	sess.held = {}
	if sess.state == "work" then
		task.delay(1, function()
			if sessions[player] == sess then
				attachUniform(player, sess)
			end
		end)
	end
	dirtyPlayers[player] = true
end

function Work.onLeave(player: Player)
	if sessions[player] then
		finish(player, "접속 종료", { disconnect = true })
	end
	sessions[player] = nil
	pushAt[player] = nil
	dirtyPlayers[player] = nil
end

-- tests / tools
Work.sessions = sessions
Work.stores = stores
Work.W = W
Work.boardView = boardView
Work.orders = function()
	return Orders
end

return Work
