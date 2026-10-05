-- GwangalliGameplay (server): the 광안리 GTA LIFE GAME core (docs/LIFE_GAME_DESIGN.md).
--   profiles (cash + bank ledger, stats, job / careers, home, messages / offers, inventory,
--   outfit / hair; DataStore "GwangalliProfile_v1" key "u_<UserId>", v1 saves migrated), jobs and
--   shifts, housing + daily rent, NPCs and their dialogs, phone messages / offers / calls, taxis,
--   gym / salon / shops / elevators. Modules live in the Folder ServerScriptService.GwangalliGameplay
--   (Util, Profiles, Jobs, Life, NPC, Taxi, Venues); shared data and the remote / attribute contract
--   are documented in ReplicatedStorage.GwangalliGameplayShared.
--
-- Remotes: ReplicatedStorage.GwangalliRemotes { GetProfile (RemoteFunction), ProfileChanged,
-- PhoneAction, Notify, TaxiState, Dialog, WorkState (RemoteEvents) }, created here at start.
--
-- Money: every cash / bank change goes through ctx.ledger (G.ledger: one transactions list, Korean
-- labels). Wages are paid into the bank; purchases take cash first, then the bank (check card).
-- Stat effects: 체력 -> RunSpeedBonus (HUD sprint), 외모지수 -> Appearance (club entry), 행복 ->
-- Happiness, job -> Job attribute.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function loadShared(): any
	local m = ReplicatedStorage:WaitForChild("GwangalliGameplayShared", 30)
	if not m then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliGameplay] GwangalliGameplayShared failed to load: " .. tostring(res))
	return nil
end

local G = loadShared()
if not G then
	warn("[GwangalliGameplay] ReplicatedStorage.GwangalliGameplayShared missing; gameplay disabled")
	return
end

-- The modules folder shares this script's name, so find it by class.
local folder: Instance? = nil
for _, c in script.Parent:GetChildren() do
	if c:IsA("Folder") and c.Name == "GwangalliGameplay" then
		folder = c
		break
	end
end
if not folder then
	warn("[GwangalliGameplay] module folder ServerScriptService.GwangalliGameplay missing; gameplay disabled")
	return
end

local function mod(name: string): any
	local m = (folder :: Instance):FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		error("[GwangalliGameplay] module missing: " .. name)
	end
	local ok, res = pcall(require, m)
	if not ok then
		error("[GwangalliGameplay] module " .. name .. " failed: " .. tostring(res))
	end
	return res
end

local Util = mod("Util")
local Profiles = mod("Profiles")
local Taxi = mod("Taxi")
local Venues = mod("Venues")
local Jobs = mod("Jobs")
local Life = mod("Life")
local NPC = mod("NPC")

-- Clock / night / drone show helpers (optional).
local Clock: any = nil
do
	local m = ReplicatedStorage:WaitForChild("GwangalliShared", 10)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			Clock = res
		end
	end
end

do
	local problems = G.validate()
	for _, p in problems do
		warn("[GwangalliGameplay] data: " .. p)
	end
end

-------------------------------------------------------------------------------------------------
-- Remotes
-------------------------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild(G.RemotesFolder)
if remotesFolder and not remotesFolder:IsA("Folder") then
	remotesFolder:Destroy()
	remotesFolder = nil
end
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = G.RemotesFolder
end

local function remote(name: string, className: string): any
	local r = (remotesFolder :: Instance):FindFirstChild(name)
	if r and r.ClassName ~= className then
		r:Destroy()
		r = nil
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = remotesFolder
	end
	return r
end

local remotes = {
	GetProfile = remote(G.Remote.GetProfile, "RemoteFunction") :: RemoteFunction,
	ProfileChanged = remote(G.Remote.ProfileChanged, "RemoteEvent") :: RemoteEvent,
	PhoneAction = remote(G.Remote.PhoneAction, "RemoteEvent") :: RemoteEvent,
	Notify = remote(G.Remote.Notify, "RemoteEvent") :: RemoteEvent,
	TaxiState = remote(G.Remote.TaxiState, "RemoteEvent") :: RemoteEvent,
	Dialog = remote(G.Remote.Dialog, "RemoteEvent") :: RemoteEvent,
	WorkState = remote(G.Remote.WorkState, "RemoteEvent") :: RemoteEvent,
}
-- parent the folder last so clients that find it also find every remote
local rf: Instance = remotesFolder :: Instance
rf.Parent = ReplicatedStorage

-------------------------------------------------------------------------------------------------
-- Context shared by the modules
-------------------------------------------------------------------------------------------------
type Session = { joinedAt: number, allowTeleportUntil: number }
local sessions: { [Player]: Session } = {}
local ctx: any = { G = G, Util = Util, Profiles = Profiles, Clock = Clock, remotes = remotes }

function ctx.session(player: Player): Session
	local s = sessions[player]
	if not s then
		s = { joinedAt = os.clock(), allowTeleportUntil = 0 }
		sessions[player] = s
	end
	return s
end

function ctx.allowTeleport(player: Player, seconds: number)
	local s = ctx.session(player)
	s.allowTeleportUntil = math.max(s.allowTeleportUntil, os.clock() + seconds)
end

function ctx.teleportAllowed(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and os.clock() < s.allowTeleportUntil
end

-- Environment (in-game clock, night, drone show), cached for 0.5 s.
local envCache: any = nil
local envT = -1
function ctx.env(): any
	local now = os.clock()
	if envCache and now - envT < 0.5 then
		return envCache
	end
	local clock, night, drone, predrone = 12, false, false, false
	local ok = false
	if Clock then
		ok = pcall(function()
			clock = Clock.clockNow()
			night = Clock.isNightClock(clock)
			drone = (Clock.droneShowState())
			local nxt = Clock.nextShowClock(clock)
			if nxt then
				predrone = ((nxt - clock) % 24) <= 2
			end
		end)
	end
	if not ok then
		clock = Lighting.ClockTime
		night = clock >= 18 or clock < 6
	end
	envCache = { clock = clock, night = night, droneshow = drone == true, predrone = predrone }
	envT = now
	return envCache
end

-- Destination registry (tag "Destination", attribute DisplayName).
local destByName: { [string]: BasePart } = {}
local destNameOf: { [Instance]: string } = {}
local function destName(inst: Instance): string
	local n = inst:GetAttribute(G.Attr.DisplayName)
	if type(n) == "string" and n ~= "" then
		return n
	end
	return inst.Name
end
local function destAdded(inst: Instance)
	if not inst:IsA("BasePart") or not inst:IsDescendantOf(workspace) then
		return
	end
	local n = destName(inst)
	destNameOf[inst] = n
	if not destByName[n] then
		destByName[n] = inst
		for _, m in { Venues, Jobs, NPC } do
			local ok, err = pcall(m.onDest, n, inst)
			if not ok then
				warn("[GwangalliGameplay] destination setup failed (" .. n .. "): " .. tostring(err))
			end
		end
	end
end
local function destRemoved(inst: Instance)
	local n = destNameOf[inst]
	destNameOf[inst] = nil
	if n and destByName[n] == inst then
		destByName[n] = nil
		for other, on in destNameOf do
			if on == n then
				destAdded(other)
				break
			end
		end
	end
end
function ctx.dest(name: string): BasePart?
	local p = destByName[name]
	if p and p.Parent then
		return p
	end
	return nil
end

-- Notifications / profile deltas.
function ctx.notify(player: Player, kind: string, title: string, body: string?, extra: { [string]: any }?)
	if player.Parent ~= Players then
		return
	end
	local payload: { [string]: any } = { kind = kind, title = title, body = body or "" }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	remotes.Notify:FireClient(player, payload)
end

local pendingKeys: { [Player]: { [string]: boolean } } = {}
local function flush(player: Player)
	local keys = pendingKeys[player]
	pendingKeys[player] = nil
	if not keys or player.Parent ~= Players then
		return
	end
	local view = Profiles.view(player, keys)
	if view and next(view) then
		remotes.ProfileChanged:FireClient(player, view)
	end
end
function ctx.changed(player: Player, ...: string)
	local keys = pendingKeys[player]
	local schedule = keys == nil
	if not keys then
		keys = {}
		pendingKeys[player] = keys
	end
	for i = 1, select("#", ...) do
		keys[select(i, ...)] = true
	end
	Profiles.markDirty(player)
	if schedule then
		task.defer(flush, player)
	end
end

function ctx.refreshAttributes(player: Player)
	local d = Profiles.get(player)
	if not d or player.Parent ~= Players then
		return
	end
	local st = d.stats
	player:SetAttribute(G.Attr.Appearance, math.floor(st.appearance))
	player:SetAttribute(G.Attr.Strength, math.floor(st.strength))
	player:SetAttribute(G.Attr.Stamina, math.floor(st.stamina))
	player:SetAttribute(G.Attr.Popularity, math.floor(st.popularity))
	player:SetAttribute(G.Attr.Happiness, math.floor(st.happiness))
	player:SetAttribute(G.Attr.Money, d.cash)
	player:SetAttribute(G.Attr.Bank, d.bank)
	player:SetAttribute(G.Attr.Job, d.job and d.job.id or "")
	local energy = d.buffs.energy
	local bonus = G.runSpeedBonus(st.stamina, energy ~= nil and (energy.untilT or 0) > os.time())
	player:SetAttribute(G.Attr.RunSpeedBonus, bonus)
	player:SetAttribute(G.Attr.ClubVIP, st.appearance >= G.CLUB.vipAppearance)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute(G.Attr.RunSpeedBonus, bonus)
	end
end

-- The one place cash / bank change. account = "cash" | "bank". Returns false when it would go
-- negative (nothing changes then).
function ctx.ledger(player: Player, account: string, delta: number, label: string?, silent: boolean?): boolean
	local d = Profiles.get(player)
	if not d then
		return false
	end
	local ok = G.ledger(d, account, delta, label, os.time())
	if not ok then
		return false
	end
	ctx.changed(player, account)
	player:SetAttribute(G.Attr.Money, d.cash)
	player:SetAttribute(G.Attr.Bank, d.bank)
	if not silent and delta ~= 0 then
		ctx.notify(player, "money", (if delta > 0 then "+" else "-") .. G.format.won(math.abs(delta)), label or "")
	end
	return true
end

-- Legacy wallet API (cash).
function ctx.addMoney(player: Player, delta: number, reason: string?, silent: boolean?): boolean
	if not G.isFiniteNumber(delta) then
		return false
	end
	return ctx.ledger(player, "cash", delta, reason, silent)
end

function ctx.canAfford(player: Player, amount: number): boolean
	local d = Profiles.get(player)
	return d ~= nil and G.canAfford(d, amount)
end

-- Pays from cash, or the bank (check card) when cash is short.
function ctx.spend(player: Player, amount: number, label: string?, silent: boolean?, prefer: string?): boolean
	local d = Profiles.get(player)
	if not d then
		return false
	end
	local ok, account = G.spend(d, amount, label, os.time(), prefer)
	if not ok then
		return false
	end
	ctx.changed(player, account or "cash")
	player:SetAttribute(G.Attr.Money, d.cash)
	player:SetAttribute(G.Attr.Bank, d.bank)
	if not silent and amount > 0 then
		ctx.notify(player, "money", "-" .. G.format.won(amount), (label or "") .. (if account == "bank" then " (체크카드)" else ""))
	end
	return true
end

function ctx.addStats(player: Player, delta: { [string]: number }?, reason: string?, silent: boolean?): { [string]: number }
	local d = Profiles.get(player)
	if not d or not delta then
		return {}
	end
	local newStats, applied = G.addStats(d.stats, delta)
	if not next(applied) then
		return applied
	end
	d.stats = newStats
	ctx.changed(player, "stats")
	ctx.refreshAttributes(player)
	if not silent then
		ctx.notify(player, "stat", reason or "능력치 변화", G.describeStats(applied))
	end
	return applied
end

-- Legacy quest hooks (Venues / Taxi still call them): the quest system was folded into jobs + offers.
function ctx.questEvent(_player: Player, _event: any) end
function ctx.questsResetPosition(player: Player)
	Jobs.resetPosition(player)
end
function ctx.jobsResetPosition(player: Player)
	Jobs.resetPosition(player)
end
function ctx.isRiding(player: Player): boolean
	return Taxi.isRiding(player)
end
function ctx.venueBusy(player: Player): boolean
	local ok, res = pcall(Venues.isBusy, player)
	return ok and res == true
end
function ctx.onShift(player: Player): boolean
	return Jobs.onShift(player)
end
function ctx.applyJob(player: Player, jobId: string, via: string?): boolean
	return Jobs.apply(player, jobId, via)
end
function ctx.startShift(player: Player)
	Jobs.startShift(player)
end
function ctx.endShift(player: Player)
	Jobs.endShift(player)
end
function ctx.quitJob(player: Player)
	Jobs.quit(player)
end
function ctx.callTaxi(player: Player, payload: any)
	Taxi.call(player, payload or {})
end
function ctx.openDialog(player: Player, npcId: string, remote: boolean)
	NPC.open(player, npcId, remote)
end
ctx.sendMessage = function(player: Player, cid: string, text: string, special: string?)
	Life.sendMessage(player, cid, text, special)
end
ctx.setWaypoint = function(player: Player, dest: any)
	Life.setWaypoint(player, dest)
end
ctx.rentHome = function(player: Player, id: any)
	return Life.rentHome(player, id)
end
ctx.buyHome = function(player: Player, id: any)
	return Life.buyHome(player, id)
end
ctx.bankTransfer = function(player: Player, direction: any, amount: any)
	return Life.bankTransfer(player, direction, amount)
end
ctx.hasClubPass = function(player: Player)
	return Life.hasClubPass(player)
end
ctx.clubInvited = function(player: Player)
	return Life.clubInvited(player)
end
ctx.clubAction = function(player: Player, choiceId: string)
	return Life.clubAction(player, choiceId)
end
ctx.meetPending = function(player: Player, npcId: string)
	return Life.meetPending(player, npcId)
end
ctx.friendChat = function(player: Player, contact: string, npcId: string, remote: boolean)
	return Life.friendChat(player, contact, npcId, remote)
end

-------------------------------------------------------------------------------------------------
-- Init modules
-------------------------------------------------------------------------------------------------
Profiles.init(ctx)
Venues.init(ctx)
Taxi.init(ctx)
Jobs.init(ctx)
Life.init(ctx)
NPC.init(ctx)

-- Optional feature modules (docs/features_contract.md §2). Append a module name to add one; a missing
-- or failing module is skipped. Hooks: init(ctx), onLoaded(player), onCharacter(player, character),
-- onLeave(player) (before the profile is saved and released).

-- Unified server wallet used by building purchases, furniture and the original life game.
do
 local ss = game:GetService("ServerStorage")
 local api = ss:FindFirstChild("GwangalliGameplayAPI")
 if not api then api = Instance.new("BindableFunction"); api.Name = "GwangalliGameplayAPI"; api.Parent = ss end
 api.OnInvoke = function(op, player, amount, label)
  local d = Profiles.get(player)
  if op == "balance" then return d and d.cash or 0, d and d.bank or 0 end
  if not d then return false end
  if op == "spend" then
   if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then return false end
   return ctx.spend(player, math.floor(amount), label or "건물 · 생활")
  elseif op == "earn" then
   if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then return false end
   return ctx.ledger(player, "bank", math.floor(amount), label or "생활 수익")
  elseif op == "addStats" then return ctx.addStats(player, amount, label or "생활") end
  return false
 end
end

local FEATURE_MODULES = { "MiniGames", "Bank", "Relationships", "Health", "Bump", "Mind", "Law", "Goals", "Fuel", "Garage", "Interact", "Work", "Customers", "Shops", "Progress", "Transit", "Details", "LivingEconomy", "LivingAnchors", "LivingAccess", "LivingElevator", "LivingFixtures", "LivingHomes", "HomeDecor", "LivingShops" } -- Relationships: 호감도 / 친구 (sets ctx.social; listens to Players itself). Living*: docs/living_city_contract.md §C (missing modules are skipped)
local features: { any } = {}
for _, name in FEATURE_MODULES do
	local m = (folder :: Instance):FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local okReq, res = pcall(require, m)
		if okReq and type(res) == "table" then
			local okInit, err = pcall(function()
				if type(res.init) == "function" then
					res.init(ctx)
				end
			end)
			if okInit then
				table.insert(features, res)
			else
				warn("[GwangalliGameplay] feature " .. name .. " init failed: " .. tostring(err))
			end
		else
			warn("[GwangalliGameplay] feature " .. name .. " failed to load: " .. tostring(res))
		end
	end
end
local function featureHook(hook: string, ...: any)
	for _, f in features do
		local fn = f[hook]
		if type(fn) == "function" then
			local ok, err = pcall(fn, ...)
			if not ok then
				warn("[GwangalliGameplay] feature hook " .. hook .. " failed: " .. tostring(err))
			end
		end
	end
end

Profiles.startAutosave()

CollectionService:GetInstanceAddedSignal(G.Tags.Destination):Connect(destAdded)
CollectionService:GetInstanceRemovedSignal(G.Tags.Destination):Connect(destRemoved)
for _, inst in CollectionService:GetTagged(G.Tags.Destination) do
	destAdded(inst)
end

-------------------------------------------------------------------------------------------------
-- Remote handlers
-------------------------------------------------------------------------------------------------
local ACTION_COOLDOWN: { [string]: number } = {
	applyJob = 1,
	quitJob = 1,
	startShift = 1,
	endShift = 1,
	workTask = 0.3,
	callTaxi = 1,
	taxiDestination = 0.5,
	cancelTaxi = 0.5,
	callContact = 1,
	readThread = 0.1,
	reply = 0.25,
	dialogChoice = 0.25,
	rentHome = 1,
	buyHome = 1,
	enterHome = 2,
	leaveHome = 2,
	sleep = 2,
	setWaypoint = 0.2,
	buy = 0.4,
	equip = 1,
	bankTransfer = 0.5,
}

local function idOf(p: any, key: string): any
	local v = p[key]
	if v == nil then
		v = p.id
	end
	return v
end

local handlers: { [string]: (Player, any) -> () } = {
	applyJob = function(player, p)
		Jobs.apply(player, idOf(p, "jobId"), "phone")
	end,
	quitJob = function(player)
		Jobs.quit(player)
	end,
	startShift = function(player)
		Jobs.startShift(player)
	end,
	endShift = function(player)
		Jobs.endShift(player)
	end,
	workTask = function(player, p)
		Jobs.workTask(player, p)
	end,
	callTaxi = function(player, p)
		Taxi.call(player, p)
	end,
	taxiDestination = function(player, p)
		Taxi.setDestination(player, p)
	end,
	cancelTaxi = function(player)
		Taxi.cancel(player)
	end,
	callContact = function(player, p)
		Life.callContact(player, p.contactId or p.contact)
	end,
	readThread = function(player, p)
		Life.readThread(player, p.contactId or p.contact)
	end,
	reply = function(player, p)
		local choice = p.choice
		if choice == nil then
			choice = p.index or p.choiceId
		end
		Life.reply(player, p.contactId or p.contact, choice)
	end,
	dialogChoice = function(player, p)
		NPC.choice(player, p)
	end,
	rentHome = function(player, p)
		Life.rentHome(player, idOf(p, "listingId"))
	end,
	buyHome = function(player, p)
		Life.buyHome(player, idOf(p, "listingId"))
	end,
	enterHome = function(player)
		Life.enterHome(player)
	end,
	leaveHome = function(player)
		Life.leaveHome(player)
	end,
	sleep = function(player)
		Life.sleep(player)
	end,
	setWaypoint = function(player, p)
		local dest = p.destination
		if dest == nil then
			dest = p.name
		end
		Life.setWaypoint(player, dest)
	end,
	buy = function(player, p)
		Venues.buy(player, p.itemId, "phone")
	end,
	equip = function(player, p)
		Venues.equip(player, p.itemId)
	end,
	bankTransfer = function(player, p)
		Life.bankTransfer(player, p.direction, p.amount)
	end,
}

remotes.PhoneAction.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
	if type(action) ~= "string" or not G.Actions[action] or not handlers[action] then
		return
	end
	if payload ~= nil and type(payload) ~= "table" then
		return
	end
	if not Util.bucket(player, 8, 16) then
		return
	end
	if not Util.cooldown(player, "act:" .. action, ACTION_COOLDOWN[action] or 0.3) then
		return
	end
	if not Profiles.get(player) then
		ctx.notify(player, "info", "잠시만요", "프로필을 불러오는 중이에요")
		return
	end
	local ok, err = pcall(handlers[action], player, payload or {})
	if not ok then
		warn(string.format("[GwangalliGameplay] %s from %s failed: %s", action, player.Name, tostring(err)))
	end
end)

remotes.GetProfile.OnServerInvoke = function(player: Player)
	if not Util.bucket(player, 2, 6) then
		return nil
	end
	local d = Profiles.wait(player, 10)
	if not d then
		return nil
	end
	local ok, view = pcall(Profiles.view, player)
	return if ok then view else nil
end

-------------------------------------------------------------------------------------------------
-- Players
-------------------------------------------------------------------------------------------------
local function onCharacter(player: Player, character: Model)
	ctx.allowTeleport(player, 5)
	Taxi.forceEnd(player, "respawn")
	Venues.onCharacter(player)
	Jobs.onCharacter(player)
	NPC.onCharacter(player)
	Life.onCharacter(player)
	featureHook("onCharacter", player, character)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and player.Character == character then
			ctx.refreshAttributes(player)
		end
	end)
end

local function onLoaded(player: Player, _d: any, info: any)
	ctx.refreshAttributes(player)
	Life.onLoaded(player)
	Jobs.onLoaded(player)
	featureHook("onLoaded", player)
	ctx.changed(player, table.unpack(Profiles.VIEW_KEYS))
	Venues.applyLook(player)
	if info.message then
		ctx.notify(player, "info", "저장 안내", info.message)
	end
end

local function onPlayerAdded(player: Player)
	ctx.session(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	task.spawn(function()
		local ok, err = pcall(Profiles.load, player, function(p, d, info)
			local ok2, err2 = pcall(onLoaded, p, d, info)
			if not ok2 then
				warn("[GwangalliGameplay] profile setup failed for " .. p.Name .. ": " .. tostring(err2))
			end
		end)
		if not ok then
			warn("[GwangalliGameplay] profile load crashed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	pcall(Taxi.forceEnd, player, "left")
	pcall(Venues.onLeave, player)
	pcall(Jobs.onLeave, player) -- pays the wages earned so far before the profile is saved
	pcall(NPC.onLeave, player)
	pcall(Life.onLeave, player)
	featureHook("onLeave", player)
	pendingKeys[player] = nil
	task.spawn(function()
		local ok, err = pcall(Profiles.release, player)
		if not ok then
			warn("[GwangalliGameplay] release failed for " .. player.Name .. ": " .. tostring(err))
		end
		sessions[player] = nil
		Util.forget(player)
	end)
end)

-- Buff expiry (energy -> RunSpeedBonus back to normal).
task.spawn(function()
	while true do
		task.wait(2)
		local now = os.time()
		for _, player in Players:GetPlayers() do
			local d = Profiles.get(player)
			if d then
				local changed = false
				for id, b in d.buffs do
					if (b.sets or 0) <= 0 and (b.untilT or 0) <= now then
						d.buffs[id] = nil
						changed = true
					end
				end
				if changed then
					ctx.changed(player, "buffs")
					ctx.refreshAttributes(player)
				end
			end
		end
	end
end)
