-- GwangalliClinic/Bridge: every integration with the owner's existing systems (found at runtime, all
-- pcall-guarded). The clinic is built ON the game's Health system: fees, cures and effects of a treatment
-- always go through Health's own ops; this module never re-implements them.
--
--   Health module   ServerScriptService.<GwangalliGameplay Folder>.Health (same Lua VM; required only after
--                   ServerStorage.GwangalliHealthAPI exists = Health.init finished): status / fatigue /
--                   isIll / rest / findBed / onLoaded
--   Health API      ServerStorage.GwangalliHealthAPI (BindableFunction): treat / vitamin / checkup (fee =
--                   G.HEALTH price + d.health.debt, bank first then cash, the seated nurse choreography,
--                   cure / fatigue / 행복, HealthEvent "cured"/"vitamin"/"checkup"), setRisk, cure, status
--                   (always called with the Player instance: an unknown id falls back to the first player)
--   Profiles        same folder: Profiles.get (d.health.debt / illness.online / restore), markDirty,
--                   persistent
--   gameplay ctx    VenueLife.ctx / Play.ctx (the shared context table): ledger (account-specific debit with
--                   the Money / Bank attributes + ProfileChanged + toast), notify, addStats, onShift,
--                   isRiding, allowTeleport, jobsResetPosition, env
--   Gameplay API    ServerStorage.GwangalliGameplayAPI: balance / spend / addStats (fallbacks)
--   Passes          ServerStorage.GwangalliPassesAPI ("has", player, "qol")
--   legacy          the HospitalPrompt prompts are switched off (kept off) once our server is up

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridge = {}

local S: any
local C: any
local K: any

local folder: Instance? = nil
local HealthMod: any = nil
local Profiles: any = nil
local G: any = nil
local ctx: any = nil
local inflight: { [Player]: boolean } = {}
local passCache: { [Player]: { v: boolean, t: number } } = {}

local function log(...)
	if C and C.Debug then
		print("[GwangalliClinic]", ...)
	end
end
Bridge.log = log

local function bindable(name: string): BindableFunction?
	local f = ServerStorage:FindFirstChild(name)
	if f and f:IsA("BindableFunction") then
		return f
	end
	return nil
end

-- Invokes a BindableFunction in its own thread. Returns ("noapi" | "ok" | "error" | "timeout", a, b).
local function invoke(name: string, timeout: number?, ...: any): (string, any, any)
	local api = bindable(name)
	if not api then
		return "noapi", nil, nil
	end
	local args = table.pack(...)
	local box = { done = false, ok = false, a = nil :: any, b = nil :: any }
	task.spawn(function()
		local ok, a, b = pcall(function()
			return (api :: BindableFunction):Invoke(table.unpack(args, 1, args.n))
		end)
		box.ok, box.a, box.b = ok, a, b
		box.done = true
		if not ok then
			warn("[GwangalliClinic]", name, tostring(args[1]), "failed:", a)
		end
	end)
	local t0 = os.clock()
	while not box.done do
		if timeout and os.clock() - t0 > timeout then
			return "timeout", nil, nil
		end
		task.wait(0.03)
	end
	if not box.ok then
		return "error", nil, nil
	end
	return "ok", box.a, box.b
end
Bridge.invoke = invoke

local function findGameplayFolder(): Instance?
	for _, c in ServerScriptService:GetChildren() do
		if c.Name == "GwangalliGameplay" and c:IsA("Folder") then
			return c
		end
	end
	return nil
end

local function requireChild(name: string): any
	local f = folder
	if not f then
		return nil
	end
	local m = f:FindFirstChild(name)
	if not (m and m:IsA("ModuleScript")) then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliClinic] require", name, "failed:", res)
	return nil
end

-- Yields until the Health system is up (or `timeout`). Returns ok, reason.
function Bridge.waitReady(timeout: number): (boolean, string?)
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		folder = folder or findGameplayFolder()
		if folder and bindable("GwangalliHealthAPI") then
			break
		end
		task.wait(0.5)
	end
	if not folder then
		return false, "GwangalliGameplay folder not found"
	end
	if not bindable("GwangalliHealthAPI") then
		return false, "ServerStorage.GwangalliHealthAPI not found (Health system off?)"
	end
	HealthMod = requireChild("Health")
	Profiles = requireChild("Profiles")
	if not HealthMod or type(HealthMod.status) ~= "function" then
		return false, "Health module not usable"
	end
	if not Profiles or type(Profiles.get) ~= "function" then
		return false, "Profiles module not usable"
	end
	do
		local m = ReplicatedStorage:FindFirstChild("GwangalliGameplayShared")
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				G = res
			end
		end
	end
	-- the shared gameplay context (optional: richer money / notify paths)
	task.spawn(function()
		local t1 = os.clock()
		while os.clock() - t1 < 40 and not ctx do
			for _, name in { "VenueLife", "Play", "MiniGames" } do
				local mod = requireChild(name)
				if mod and type(mod.ctx) == "table" and mod.ctx.health ~= nil then
					ctx = mod.ctx
					log("gameplay ctx from", name)
					break
				end
			end
			if not ctx then
				task.wait(1)
			end
		end
	end)
	return true, nil
end

function Bridge.G(): any
	return G
end

function Bridge.ctx(): any
	return ctx
end

-------------------------------------------------------------------------------------------------
-- profile / health data (read)
-------------------------------------------------------------------------------------------------
function Bridge.profile(player: Player): any?
	if not Profiles then
		return nil
	end
	local ok, d = pcall(Profiles.get, player)
	if ok and type(d) == "table" then
		return d
	end
	return nil
end

function Bridge.healthData(player: Player): any?
	local d = Bridge.profile(player)
	if d and type(d.health) == "table" then
		return d.health
	end
	return nil
end

function Bridge.markDirty(player: Player)
	if Profiles and Profiles.markDirty then
		pcall(Profiles.markDirty, player)
	end
end

function Bridge.persistent(player: Player): boolean
	if Profiles and type(Profiles.persistent) == "function" then
		local ok, v = pcall(Profiles.persistent, player)
		if ok then
			return v ~= false
		end
	end
	return true
end

function Bridge.status(player: Player): any?
	if not HealthMod then
		return nil
	end
	local ok, st = pcall(HealthMod.status, player)
	if ok and type(st) == "table" then
		return st
	end
	return nil
end

function Bridge.fatigue(player: Player): number
	if HealthMod then
		local ok, f = pcall(HealthMod.fatigue, player)
		if ok and type(f) == "number" then
			return f
		end
	end
	return tonumber(player:GetAttribute("Fatigue")) or 0
end

function Bridge.illness(player: Player): string?
	local h = Bridge.healthData(player)
	if h and type(h.illness) == "table" and type(h.illness.kind) == "string" then
		return h.illness.kind
	end
	local a = player:GetAttribute("Illness")
	if type(a) == "string" and a ~= "" then
		return a
	end
	return nil
end

function Bridge.illOnline(player: Player): number
	local h = Bridge.healthData(player)
	if h and type(h.illness) == "table" then
		return tonumber(h.illness.online) or 0
	end
	return 0
end

function Bridge.risk(player: Player): number
	local h = Bridge.healthData(player)
	return if h then math.clamp(tonumber(h.risk) or 0, 0, 100) else 0
end

function Bridge.debt(player: Player): number
	local h = Bridge.healthData(player)
	return if h then math.max(0, math.floor(tonumber(h.debt) or 0)) else 0
end

-- d.health.debt is the one source of truth for unpaid hospital bills (Health's next treat / ambulance
-- fee adds it to its own fee and clears it).
function Bridge.setDebt(player: Player, amount: number)
	local h = Bridge.healthData(player)
	if not h then
		return
	end
	h.debt = math.max(0, math.floor(tonumber(amount) or 0))
	Bridge.markDirty(player)
end

function Bridge.addDebt(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	Bridge.setDebt(player, Bridge.debt(player) + amount)
end

function Bridge.collapseAfter(): number
	local H = S.H()
	return tonumber(H and H.collapseAfter) or 600
end

-- keeps a registered patient from collapsing in the middle of a visit
function Bridge.clampOnline(player: Player, maxOnline: number)
	local h = Bridge.healthData(player)
	if h and type(h.illness) == "table" then
		local on = tonumber(h.illness.online) or 0
		if on > maxOnline then
			h.illness.online = math.max(0, maxOnline)
		end
	end
end

function Bridge.riskThreshold(): number
	local H = S.H()
	return tonumber(H and H.risk and H.risk.threshold) or 25
end

-------------------------------------------------------------------------------------------------
-- Health ops (fees + effects stay inside Health)
-------------------------------------------------------------------------------------------------
function Bridge.api(op: string, player: Player, a: any?, b: any?): any?
	local st, res = invoke("GwangalliHealthAPI", 10, op, player, a, b)
	if st ~= "ok" then
		return nil
	end
	return res
end

function Bridge.rest(player: Player, amount: number): number?
	if amount <= 0 then
		return nil
	end
	if HealthMod and type(HealthMod.rest) == "function" then
		local ok, f = pcall(HealthMod.rest, player, amount, "clinic")
		if ok then
			return f
		end
	end
	-- fallback: absolute set through the API
	local cur = Bridge.fatigue(player)
	local res = Bridge.api("setFatigue", player, math.max(0, cur - amount))
	return res and res.fatigue or nil
end

function Bridge.setRisk(player: Player, value: number)
	Bridge.api("setRisk", player, math.clamp(value, 0, 100))
end

function Bridge.onLoaded(player: Player)
	if HealthMod and type(HealthMod.onLoaded) == "function" then
		pcall(HealthMod.onLoaded, player)
	end
end

function Bridge.findBed(kind: string, near: Vector3?): BasePart?
	if HealthMod and type(HealthMod.findBed) == "function" then
		local ok, bed = pcall(HealthMod.findBed, kind, near)
		if ok and typeof(bed) == "Instance" then
			return bed
		end
	end
	return nil
end

-- Runs Health's own treatment op ("treat" | "vitamin" | "checkup"). Health charges its price + the debt
-- (bank first, then cash), seats the patient on the exam bed with the nurse choreography (treat /
-- vitamin) and applies the real effects. Returns ok, result, how ("card" | "cash" | "mixed" | nil).
function Bridge.healthOp(player: Player, op: string): (boolean, any, string?)
	if op ~= "treat" and op ~= "vitamin" and op ~= "checkup" then
		return false, { code = "bad", message = S.err("bad") }, nil
	end
	local cash0, bank0 = Bridge.balance(player)
	local res = Bridge.api(op, player)
	if type(res) ~= "table" then
		return false, { code = "health", message = S.err("health") }, nil
	end
	if res.ok ~= true then
		return false, res, nil
	end
	local how = nil
	local cash1, bank1 = Bridge.balance(player)
	if cash0 and cash1 and bank0 and bank1 then
		local dc, db = cash0 - cash1, bank0 - bank1
		if dc > 0 and db > 0 then
			how = "mixed"
		elseif db > 0 then
			how = "card"
		elseif dc > 0 then
			how = "cash"
		end
	end
	return true, res, how
end

-------------------------------------------------------------------------------------------------
-- money (server-authoritative; one money op in flight per player)
-------------------------------------------------------------------------------------------------
function Bridge.balance(player: Player): (number?, number?)
	local d = Bridge.profile(player)
	if d then
		return math.floor(tonumber(d.cash) or 0), math.floor(tonumber(d.bank) or 0)
	end
	local st, cash, bank = invoke("GwangalliGameplayAPI", 8, "balance", player)
	if st ~= "ok" then
		return nil, nil
	end
	return tonumber(cash) or 0, tonumber(bank) or 0
end

function Bridge.canAfford(player: Player, amount: number): boolean
	local cash, bank = Bridge.balance(player)
	if not cash or not bank then
		return false
	end
	return cash >= amount or bank >= amount
end

-- method = "card" (통장 체크카드) | "cash". Returns "ok" | "money" | "noapi" | "error" | "busy", account.
function Bridge.charge(player: Player, amount: number, label: string, method: string?): (string, string?)
	amount = math.floor(amount)
	if amount <= 0 then
		return "ok", nil
	end
	if inflight[player] then
		return "busy", nil
	end
	inflight[player] = true
	local result, account = "error", nil
	local okP, err = pcall(function()
		local acct = if method == "cash" then "cash" else "bank"
		if ctx and type(ctx.ledger) == "function" then
			local d = Bridge.profile(player)
			if not d then
				result = "error"
				return
			end
			if (tonumber(d[acct]) or 0) < amount then
				result = "money"
				return
			end
			local ok = ctx.ledger(player, acct, -amount, label .. (if acct == "bank" then " (체크카드)" else " (현금)"), false)
			result = if ok then "ok" else "money"
			account = acct
			return
		end
		-- fallback: the public wallet API (cash first, then the bank "(체크카드)")
		local cash0, bank0 = Bridge.balance(player)
		local st, res = invoke("GwangalliGameplayAPI", nil, "spend", player, amount, label)
		if st == "noapi" then
			result = "noapi"
		elseif st ~= "ok" then
			result = "error"
		elseif res ~= true then
			result = "money"
		else
			result = "ok"
			local cash1, bank1 = Bridge.balance(player)
			if cash0 and cash1 and (cash0 - cash1) > 0 then
				account = "cash"
			elseif bank0 and bank1 and (bank0 - bank1) > 0 then
				account = "bank"
			end
		end
	end)
	inflight[player] = nil
	if not okP then
		warn("[GwangalliClinic] charge failed:", err)
		return "error", nil
	end
	return result, account
end

function Bridge.addStats(player: Player, delta: { [string]: number }, label: string?)
	if ctx and type(ctx.addStats) == "function" then
		local ok = pcall(ctx.addStats, player, delta, label or C.Venue.Name, false)
		if ok then
			return
		end
	end
	invoke("GwangalliGameplayAPI", 8, "addStats", player, delta, label or C.Venue.Name)
end

function Bridge.notify(player: Player, kind: string, title: string, body: string?)
	if ctx and type(ctx.notify) == "function" then
		pcall(ctx.notify, player, kind, title, body or "", { sound = if kind == "success" then "complete" else "notify" })
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("GwangalliRemotes")
	local ev = remotes and remotes:FindFirstChild("Notify")
	if ev and ev:IsA("RemoteEvent") and player.Parent == Players then
		ev:FireClient(player, { kind = kind, title = title, body = body or "" })
	end
end

function Bridge.setWaypoint(player: Player, place: string)
	if ctx and type(ctx.setWaypoint) == "function" then
		pcall(ctx.setWaypoint, player, place)
	end
end

function Bridge.allowTeleport(player: Player, seconds: number)
	if ctx then
		if type(ctx.allowTeleport) == "function" then
			pcall(ctx.allowTeleport, player, seconds)
		end
		if type(ctx.jobsResetPosition) == "function" then
			pcall(ctx.jobsResetPosition, player)
		end
	end
end

function Bridge.onShift(player: Player): boolean
	if ctx and type(ctx.onShift) == "function" then
		local ok, v = pcall(ctx.onShift, player)
		if ok then
			return v == true
		end
	end
	return player:GetAttribute("OnShift") == true
end

function Bridge.isRiding(player: Player): boolean
	if ctx and type(ctx.isRiding) == "function" then
		local ok, v = pcall(ctx.isRiding, player)
		if ok then
			return v == true
		end
	end
	return player:GetAttribute("InTaxi") == true
end

function Bridge.hasPass(player: Player): boolean
	local c = passCache[player]
	if c and os.clock() - c.t < 30 then
		return c.v
	end
	local st, v = invoke("GwangalliPassesAPI", 3, "has", player, C.Pass.Key)
	local has = st == "ok" and v == true
	passCache[player] = { v = has, t = os.clock() }
	return has
end

-- "편의점 알바", "GS25 광안리점" for a job id (G.JOBS)
function Bridge.jobInfo(jobId: string?): (string?, string?)
	if type(jobId) ~= "string" or jobId == "" or not G or type(G.JOBS) ~= "table" then
		return nil, nil
	end
	local j = G.JOBS[jobId]
	if type(j) ~= "table" then
		return nil, nil
	end
	return j.title, j.place
end

-------------------------------------------------------------------------------------------------
-- health mirror (illness / risk / debt survive a rejoin; the profile loader drops d.health)
-------------------------------------------------------------------------------------------------
function Bridge.mirror(player: Player): any?
	local h = Bridge.healthData(player)
	if not h then
		return nil
	end
	local out: any = { risk = math.floor(tonumber(h.risk) or 0), debt = math.max(0, math.floor(tonumber(h.debt) or 0)), t = os.time() }
	if type(h.illness) == "table" and S.kind(h.illness.kind) then
		out.illness = { kind = h.illness.kind, since = tonumber(h.illness.since) or os.time(), online = math.floor(tonumber(h.illness.online) or 0) }
	end
	return out
end

-- Called once per join after the profile is ready. Returns what was restored (for the toast).
function Bridge.restoreMirror(player: Player, m: any): (string?, number)
	if type(m) ~= "table" then
		return nil, 0
	end
	local h = Bridge.healthData(player)
	if not h then
		return nil, 0
	end
	local restored = nil
	if type(m.illness) == "table" and S.kind(m.illness.kind) and type(h.illness) ~= "table" then
		local cap = math.max(0, Bridge.collapseAfter() - 240)
		h.illness = {
			kind = m.illness.kind,
			since = math.clamp(tonumber(m.illness.since) or os.time(), 0, 4e9),
			online = math.clamp(math.floor(tonumber(m.illness.online) or 0), 0, cap),
		}
		h.risk = 0
		restored = m.illness.kind
	elseif type(h.illness) ~= "table" then
		h.risk = math.max(tonumber(h.risk) or 0, math.clamp(tonumber(m.risk) or 0, 0, 100))
	end
	local debt = math.max(0, math.floor(tonumber(m.debt) or 0))
	local before = math.max(0, math.floor(tonumber(h.debt) or 0))
	if debt > before then
		h.debt = math.min(debt, 10_000_000)
	end
	Bridge.markDirty(player)
	if restored then
		Bridge.onLoaded(player) -- attributes (Illness), walk speed, status push
	end
	return restored, math.max(0, (tonumber(h.debt) or 0) - before)
end

-------------------------------------------------------------------------------------------------
-- legacy takeover: the two HospitalPrompt prompts (and the doctor rig's prompt) stay disabled
-------------------------------------------------------------------------------------------------
local watched: { [Instance]: boolean } = {}

local function keepOff(pr: ProximityPrompt)
	if watched[pr] then
		return
	end
	watched[pr] = true
	pr.Enabled = false
	pr:GetPropertyChangedSignal("Enabled"):Connect(function()
		if pr.Enabled then
			pr.Enabled = false
		end
	end)
	pr.Destroying:Connect(function()
		watched[pr] = nil
	end)
end

local function sweep(inst: Instance)
	if inst:IsA("ProximityPrompt") then
		keepOff(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			keepOff(d)
		end
	end
end

function Bridge.takeOverLegacy(venue: Instance?)
	if not C.TakeOverLegacy then
		return
	end
	local function watch(inst: Instance)
		sweep(inst)
		inst.DescendantAdded:Connect(function(d)
			if d:IsA("ProximityPrompt") then
				keepOff(d)
			end
		end)
	end
	for _, tag in { "HospitalPrompt", "HospitalStaff" } do
		for _, inst in CollectionService:GetTagged(tag) do
			if not venue or inst:IsDescendantOf(venue) then
				watch(inst)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if not venue or inst:IsDescendantOf(venue) then
				watch(inst)
			end
		end)
	end
	if venue then
		for _, d in venue:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == "HospitalPrompt" then
				keepOff(d)
			end
		end
	end
	log("legacy hospital prompts switched off")
end

function Bridge.init(k: any)
	K = k
	S = k.S
	C = S.Config
	Players.PlayerRemoving:Connect(function(p)
		inflight[p] = nil
		passCache[p] = nil
	end)
end

return Bridge
