-- GwangalliPhone/Net: the phone's only link to the server, via the CONTRACT remotes in
-- ReplicatedStorage.GwangalliRemotes (created by the gameplay core):
--   GetProfile      RemoteFunction  () -> { money, stats, quests, messages, inventory, outfit, hair }
--   ProfileChanged  RemoteEvent     server -> client, partial profile (top-level keys replaced)
--   PhoneAction     RemoteEvent     client -> server (action: string, payload: table)
--   Notify          RemoteEvent     server -> client { kind, title, body }
--   TaxiState       RemoteEvent     server -> client { state, eta, fare, destination }
-- The server core may start late or not at all: the module keeps waiting in the background
-- (status "connecting" -> "ready"; "offline" after a while) and the apps show '연결 중…'.
--
-- Events (Net.on(name, fn) -> disconnect function):
--   "status"  (status)            "profile" (changedKeys: { [string]: true })
--   "notify"  (data)              "taxi"    (data)        "tx" (entry)
--   "work"    (state)             "dialog"  (data)
--
-- Life-game profile (v2): cash, bank, transactions, stats, job, careers, home, threads, contacts,
-- offers, waypoint, inventory. Compatibility fields derived here for older apps:
--   money = cash + bank, messages = { threads = threads }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.status = "connecting" -- "connecting" | "ready" | "offline"
Net.hasProfile = false
Net.profile = {
	money = 0,
	stats = {},
	quests = { active = {}, done = {} },
	messages = {},
	inventory = {},
	outfit = nil,
	hair = nil,
	owned = {},
	buffs = {},
} :: any
Net.taxi = { state = "idle" } :: any
Net.work = nil :: any -- last WorkState {jobId, onShift, task, earnedToday}
Net.serverTx = false -- the server sends profile.transactions (no local bookkeeping then)
Net.questsAt = os.clock() -- when profile.quests last arrived (its cooldowns are "seconds left" then)
Net.transactions = {} :: { any } -- newest first: { amount, title, time }

local remotes: { [string]: Instance } = {}
local listeners: { [string]: { (...any) -> () } } = {}

function Net.on(name: string, fn: (...any) -> ()): () -> ()
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
	return function()
		local idx = table.find(list, fn)
		if idx then
			table.remove(list, idx)
		end
	end
end

local function emit(name: string, ...: any)
	local list = listeners[name]
	if not list then
		return
	end
	for _, fn in table.clone(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[GwangalliPhone] " .. name .. " handler: " .. tostring(err))
		end
	end
end

local function setStatus(s: string)
	if Net.status ~= s then
		Net.status = s
		emit("status", s)
	end
end

-- Transactions ----------------------------------------------------------------------------------------
local lastReason: { title: string, at: number }? = nil

local function addTx(amount: number, title: string?)
	if amount == 0 or amount ~= amount then
		return
	end
	local reason = title
	if not reason and lastReason and os.clock() - lastReason.at < 4 then
		reason = lastReason.title
	end
	local entry = {
		amount = amount,
		title = reason or (if amount > 0 then "입금" else "결제"),
		time = workspace:GetServerTimeNow(),
	}
	table.insert(Net.transactions, 1, entry)
	while #Net.transactions > 40 do
		table.remove(Net.transactions)
	end
	emit("tx", entry)
end

-- Profile -------------------------------------------------------------------------------------------------
local PROFILE_KEYS = { "money", "stats", "quests", "messages", "inventory", "outfit", "hair", "owned", "buffs" }

local function num(v: any): number
	local n = tonumber(v)
	return if n and n == n and n ~= math.huge and n ~= -math.huge then n else 0
end

-- server transactions [{t, amount, label, balance}] (oldest or newest first) -> newest first
local function convertTx(list: any): { any }
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, e in list do
		if type(e) == "table" then
			table.insert(out, {
				amount = num(e.amount),
				title = if type(e.label) == "string" then e.label elseif type(e.title) == "string" then e.title else (if num(e.amount) >= 0 then "입금" else "출금"),
				time = num(e.t or e.time),
				balance = tonumber(e.balance),
				account = if e.account == "cash" or e.account == "bank" then e.account else nil,
			})
		end
	end
	table.sort(out, function(a, b)
		return a.time > b.time
	end)
	return out
end

-- v2 keys -> derived compatibility keys (mutates `changed`)
local function derive(changed: { [string]: boolean })
	local p = Net.profile
	if changed.cash or changed.bank then
		p.cash = num(p.cash)
		p.bank = num(p.bank)
		p.money = p.cash -- legacy meaning: cash on hand
		changed.money = true
	end
	if changed.threads then
		p.messages = { threads = if type(p.threads) == "table" then p.threads else {} }
		changed.messages = true
	end
	if changed.transactions then
		Net.serverTx = true
		Net.transactions = convertTx(p.transactions)
		changed.tx = true
		if Net.transactions[1] then
			emit("tx", Net.transactions[1])
		end
	end
end

local function sanitize(key: string, v: any): any
	if key == "quests" then
		Net.questsAt = os.clock()
	end
	if key == "money" then
		local n = tonumber(v)
		return if n and n == n then n else 0
	elseif key == "stats" or key == "inventory" or key == "messages" or key == "owned" or key == "buffs" then
		return if type(v) == "table" then v else {}
	elseif key == "quests" then
		local q = if type(v) == "table" then v else {}
		if type(q.active) ~= "table" then
			q.active = {}
		end
		if type(q.done) ~= "table" then
			q.done = {}
		end
		return q
	end
	return v
end

local function applyFull(p: any)
	if type(p) ~= "table" then
		return
	end
	local changed: { [string]: boolean } = {}
	local oldMoney = Net.profile.money
	for k, v in p do
		if type(k) == "string" then
			Net.profile[k] = sanitize(k, v)
			changed[k] = true
		end
	end
	for _, k in PROFILE_KEYS do
		if p[k] == nil and (k == "stats" or k == "quests" or k == "messages" or k == "inventory" or k == "owned" or k == "buffs") then
			Net.profile[k] = sanitize(k, nil)
		end
		changed[k] = true
	end
	derive(changed)
	local first = not Net.hasProfile
	Net.hasProfile = true
	setStatus("ready")
	if not first and not Net.serverTx then
		addTx((Net.profile.money or 0) - (oldMoney or 0), nil)
	end
	emit("profile", changed)
end

local function applyPartial(p: any)
	if type(p) ~= "table" then
		return
	end
	if not Net.hasProfile then
		-- a partial update before GetProfile returned: keep it, the full profile will follow
		local c = {}
		for k, v in p do
			if type(k) == "string" then
				Net.profile[k] = sanitize(k, v)
				c[k] = true
			end
		end
		derive(c)
		emit("profile", c)
		return
	end
	local changed: { [string]: boolean } = {}
	local oldMoney = Net.profile.money or 0
	for k, v in p do
		if type(k) == "string" then
			Net.profile[k] = sanitize(k, v)
			changed[k] = true
		end
	end
	derive(changed)
	if changed.money and not Net.serverTx then
		addTx((Net.profile.money or 0) - oldMoney, nil)
	end
	emit("profile", changed)
end

-- GetProfile with one invocation in flight at a time (an InvokeServer before the server sets its
-- callback just waits, so it is never repeated while pending).
local inFlight = false
local function fetchProfile()
	local rf = remotes.GetProfile
	if inFlight or not (rf and rf:IsA("RemoteFunction")) then
		return
	end
	inFlight = true
	task.spawn(function()
		local tries = 0
		while not Net.hasProfile and rf.Parent do
			tries += 1
			local ok, res = pcall(function()
				return (rf :: RemoteFunction):InvokeServer()
			end)
			if ok and type(res) == "table" then
				applyFull(res)
				break
			end
			if not ok then
				warn("[GwangalliPhone] GetProfile failed: " .. tostring(res))
			end
			task.wait(math.min(15, 2 * tries))
		end
		inFlight = false
	end)
end

-- Remote binding --------------------------------------------------------------------------------------------
local bound: { [Instance]: boolean } = {}

local function bindRemote(r: Instance)
	if bound[r] then
		return
	end
	local name = r.Name
	if name == "GetProfile" and r:IsA("RemoteFunction") then
		bound[r] = true
		remotes.GetProfile = r
		fetchProfile()
	elseif name == "ProfileChanged" and r:IsA("RemoteEvent") then
		bound[r] = true
		remotes.ProfileChanged = r
		r.OnClientEvent:Connect(function(partial: any)
			applyPartial(partial)
		end)
	elseif name == "PhoneAction" and r:IsA("RemoteEvent") then
		bound[r] = true
		remotes.PhoneAction = r
	elseif name == "Notify" and r:IsA("RemoteEvent") then
		bound[r] = true
		remotes.Notify = r
		r.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" then
				return
			end
			local kind = if type(data.kind) == "string" then data.kind else "info"
			local title = if type(data.title) == "string" then data.title else ""
			local body = if type(data.body) == "string" then data.body else ""
			if kind == "money" or kind == "quest" or kind == "taxi" or kind == "pay" then
				lastReason = { title = (if title ~= "" then title else body), at = os.clock() }
			end
			emit("notify", { kind = kind, title = title, body = body, contact = data.contact, quest = data.quest or data.questId, raw = data })
		end)
	elseif name == "TaxiState" and r:IsA("RemoteEvent") then
		bound[r] = true
		remotes.TaxiState = r
		r.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" or type(data.state) ~= "string" then
				return
			end
			Net.taxi = {
				state = data.state,
				eta = tonumber(data.eta),
				fare = tonumber(data.fare),
				destination = if type(data.destination) == "string" then data.destination else nil,
				at = os.clock(),
				raw = data,
			}
			emit("taxi", Net.taxi)
		end)
	elseif name == "WorkState" and r:IsA("RemoteEvent") then
		bound[r] = true
		remotes.WorkState = r
		r.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" then
				return
			end
			Net.work = data
			emit("work", data)
		end)
	elseif name == "Dialog" and r:IsA("RemoteEvent") then
		bound[r] = true
		remotes.Dialog = r
		r.OnClientEvent:Connect(function(data: any)
			if type(data) == "table" then
				emit("dialog", data)
			end
		end)
	end
	if remotes.PhoneAction and Net.status ~= "ready" and Net.hasProfile then
		setStatus("ready")
	end
end

local function bindFolder(folder: Instance)
	folder.ChildAdded:Connect(bindRemote)
	for _, c in folder:GetChildren() do
		bindRemote(c)
	end
	-- the server may create the remotes one by one
	for _, n in { "PhoneAction", "GetProfile", "ProfileChanged", "Notify", "TaxiState" } do
		if not folder:FindFirstChild(n) then
			local r = folder:WaitForChild(n, 10)
			if r then
				bindRemote(r)
			end
		end
	end
	if remotes.PhoneAction and not remotes.GetProfile then
		setStatus("ready") -- actions work; the profile stays at defaults
	end
end

function Net.start()
	task.spawn(function()
		local waited = 0
		local folder = ReplicatedStorage:FindFirstChild("GwangalliRemotes")
		while not folder do
			folder = ReplicatedStorage:WaitForChild("GwangalliRemotes", 10)
			waited += 10
			if not folder and waited >= 40 then
				setStatus("offline") -- keep trying; the apps say the server is not ready
			end
		end
		setStatus("connecting")
		bindFolder(folder)
	end)
end

function Net.ready(): boolean
	return remotes.PhoneAction ~= nil and remotes.PhoneAction.Parent ~= nil
end

-- Client-side throttle (the server rate-limits too): the same action at most every 0.4 s and no
-- more than 10 actions per 3 s.
local lastSent: { [string]: number } = {}
local window: { number } = {}

function Net.send(action: string, payload: { [string]: any }?): (boolean, string?)
	local r = remotes.PhoneAction
	if not (r and r:IsA("RemoteEvent") and r.Parent) then
		return false, if Net.status == "offline" then "게임 서버가 아직 준비되지 않았어요" else "연결 중…"
	end
	local now = os.clock()
	if lastSent[action] and now - lastSent[action] < 0.4 then
		return false, "잠시 후 다시 시도해 주세요"
	end
	while window[1] and now - window[1] > 3 do
		table.remove(window, 1)
	end
	if #window >= 10 then
		return false, "잠시 후 다시 시도해 주세요"
	end
	lastSent[action] = now
	table.insert(window, now)
	local ok, err = pcall((r :: RemoteEvent).FireServer, r :: RemoteEvent, action, payload or {})
	if not ok then
		warn("[GwangalliPhone] PhoneAction failed: " .. tostring(err))
		return false, "전송에 실패했어요"
	end
	return true, nil
end

-- Refetch on demand (e.g. the phone opens while the profile never arrived).
function Net.refresh()
	if not Net.hasProfile then
		fetchProfile()
	end
end

return Net
