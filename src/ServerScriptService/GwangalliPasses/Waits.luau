-- GwangalliPasses/Waits (server): pass #3 편의 패스, the "50 % shorter waits" half.
--   * jail: Law calls Law.children.Jail.begin(player, s, episode, info) through the module table; the wrapper
--     halves episode.seconds (min Config.QOL.JAIL_MIN) for owners. Bail (LawShared.bailFor: left / total) and the
--     rejoin remainder follow on their own. A sentence already running keeps its length (Jail keeps it private).
--   * KO (nobody dies in 광안리: 0 HP = 기절 until 119 / transport):
--       - KO.koHelp (the "병원으로 이송" button) is wrapped: an owner may press it after SELF_HELP_AFTER x 0.5
--         (the client's own copy of A.KO.SELF_HELP_AFTER is halved by QoLClient so the button shows up on time)
--       - a watcher sends an owner to hospital (the same koHelp transport, same 119 fee as the fallback) at
--         EMS_WAIT x 0.5 when no ambulance was dispatched, or at EMS_TOTAL x 0.5 while still "waiting";
--         never during first aid / transport / staging (a 119 player at the scene keeps the patient), never
--         in "arrest" mode
--   * a real Roblox death / reset: the character comes back after Players.RespawnTime x 0.5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Waits = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any
local A: any = nil
local KO: any = nil
local origKoHelp: any = nil
local ko: { [Player]: { t0: number, ems: boolean, forced: boolean, charConn: any? } } = {}

Waits.jailReady = false
Waits.koReady = false

local function owns(player: Player): boolean
	return ctx.Ownership.owns(player, "Convenience")
end

---------------------------------------------------------------------------------------------------
-- jail
---------------------------------------------------------------------------------------------------
local function hookJail(): boolean
	local api = Util.waitChild(ServerStorage, "GwangalliGameplayAPI", "BindableFunction", 150)
	if not api then
		return false
	end
	local Jail, why = Util.requirePath("GwangalliGameplay", { "Law", "Jail" }, 60)
	if not Jail then
		Util.warnOnce("jail", why)
		return false
	end
	local orig = Util.wrap(Jail, "begin", function(o)
		return function(player: any, s: any, episode: any, info: any)
			if Util.isPlayer(player) and type(episode) == "table" and type(episode.seconds) == "number" and owns(player) then
				local before = episode.seconds
				local after = math.max(Config.QOL.JAIL_MIN, math.ceil(before * Config.QOL.JAIL_MULT))
				if after < before then
					local e = table.clone(episode)
					e.seconds = after
					episode = e
					ctx.Net.send(player, { kind = "qol", what = "jail", before = before, after = after, text = Lines.t("jail_cut", Lines.dur(before), Lines.dur(after)) })
				end
			end
			return o(player, s, episode, info)
		end
	end)
	return orig ~= nil or Jail.begin ~= nil
end

---------------------------------------------------------------------------------------------------
-- KO
---------------------------------------------------------------------------------------------------
local function koConst(name: string, default: number): number
	local v = A and A.KO and A.KO[name]
	return if type(v) == "number" then v else default
end

-- calls the original koHelp with SELF_HELP_AFTER lifted for exactly this synchronous call
local function forceHelp(player: Player): boolean
	if not origKoHelp or not A or not A.KO then
		return false
	end
	local old = A.KO.SELF_HELP_AFTER
	A.KO.SELF_HELP_AFTER = 0
	local ok, res = pcall(origKoHelp, player)
	A.KO.SELF_HELP_AFTER = old
	return ok and res == true
end

local function koState(player: Player): string?
	local ch = player.Character
	if not ch or ch:GetAttribute("GwKO") ~= true then
		return nil
	end
	local st = ch:GetAttribute("ArmsKO")
	return if type(st) == "string" then st else "down"
end

local function setKOEnd(player: Player, rec: any)
	if not owns(player) then
		player:SetAttribute(P.Attr.KOEnd, nil)
		return
	end
	local mult = Config.QOL.KO_MULT
	local wait = if rec.ems then koConst("EMS_TOTAL", 150) * mult else koConst("EMS_WAIT", 95) * mult
	local remaining = math.max(0, wait - (os.clock() - rec.t0))
	player:SetAttribute(P.Attr.KOEnd, P.serverNow() + remaining)
	player:SetAttribute("GwPassQoLKOEms", rec.ems == true)
end

local function watchCharacter(player: Player, ch: Model)
	local function update()
		if ch:GetAttribute("GwKO") == true then
			if not ko[player] then
				local rec = { t0 = os.clock(), ems = false, forced = false }
				ko[player] = rec
				setKOEnd(player, rec)
			end
		else
			ko[player] = nil
			player:SetAttribute(P.Attr.KOEnd, nil)
		end
	end
	ch:GetAttributeChangedSignal("GwKO"):Connect(update)
	update()
end

local function tick()
	local mult = Config.QOL.KO_MULT
	for player, rec in ko do
		if player.Parent ~= Players then
			ko[player] = nil
			continue
		end
		if rec.forced or not owns(player) then
			continue
		end
		local st = koState(player)
		if not st then
			continue
		end
		local el = os.clock() - rec.t0
		local wait = koConst("EMS_WAIT", 95) * mult
		local total = koConst("EMS_TOTAL", 150) * mult
		local okState = st == "waiting" or st == "down"
		local due = (not rec.ems and el >= wait) or (el >= total and st == "waiting")
		if okState and due then
			rec.forced = true
			if forceHelp(player) then
				ctx.Net.send(player, { kind = "toast", icon = "⚡", title = Lines.t("ko_forced"), tone = "info" })
			else
				rec.forced = false
				rec.t0 += 3 -- arrest mode / busy: look again in a moment
			end
		end
	end
end

local function hookKO(): boolean
	local api = Util.waitChild(ServerStorage, "GwangalliArmsAPI", "BindableFunction", 150)
	if not api then
		return false
	end
	A = Util.requireShared(ReplicatedStorage, "GwangalliArmsShared", 30)
	local K, why = Util.requirePath("GwangalliGameplay", { "Arms", "KOSystem" }, 60)
	if not K or not A then
		Util.warnOnce("ko", why or "GwangalliArmsShared missing")
		return false
	end
	KO = K
	origKoHelp = Util.wrap(KO, "koHelp", function(o)
		return function(victim: any): boolean
			if Util.isPlayer(victim) and owns(victim) then
				local rec = ko[victim]
				local need = koConst("SELF_HELP_AFTER", 20) * Config.QOL.KO_MULT
				if rec and os.clock() - rec.t0 >= need then
					local old = A.KO.SELF_HELP_AFTER
					A.KO.SELF_HELP_AFTER = 0
					local ok, res = pcall(o, victim)
					A.KO.SELF_HELP_AFTER = old
					return ok and res == true
				end
			end
			return o(victim)
		end
	end)
	if not origKoHelp then
		return false
	end
	-- ambulance dispatched for an owner: the shorter "no crew" timer no longer applies
	local bus = ServerStorage:FindFirstChild("GwangalliCrimeBus")
	if bus and bus:IsA("BindableEvent") then
		bus.Event:Connect(function(name: any, payload: any)
			if name == "EmsDispatched" and type(payload) == "table" then
				local p = payload.player
				if typeof(p) == "Instance" and p:IsA("Player") and ko[p] then
					ko[p].ems = true
					setKOEnd(p, ko[p])
				end
			end
		end)
	end
	local function join(player: Player)
		if player.Character then
			watchCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(ch: Model)
			watchCharacter(player, ch)
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				Util.warnOnce("ko tick", err)
			end
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------
-- Roblox respawn
---------------------------------------------------------------------------------------------------
local function hookRespawn()
	local function onChar(player: Player, ch: Model)
		local hum = ch:WaitForChild("Humanoid", 10)
		if not hum or not hum:IsA("Humanoid") then
			return
		end
		hum.Died:Connect(function()
			if not owns(player) or not Players.CharacterAutoLoads then
				return
			end
			local delay = math.max(0.5, Players.RespawnTime * Config.QOL.RESPAWN_MULT)
			task.delay(delay, function()
				if player.Parent == Players and player.Character == ch then
					pcall(player.LoadCharacter, player)
				end
			end)
		end)
	end
	local function join(player: Player)
		if player.Character then
			task.spawn(onChar, player, player.Character)
		end
		player.CharacterAdded:Connect(function(ch: Model)
			onChar(player, ch)
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
end

function Waits.start(c: any)
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	hookRespawn()
	Players.PlayerRemoving:Connect(function(p: Player)
		ko[p] = nil
	end)
	task.spawn(function()
		local ok, res = pcall(hookJail)
		Waits.jailReady = ok and res == true
		if not Waits.jailReady then
			Util.warnOnce("jail", "Law/Jail hook unavailable: 유치장 단축 off (" .. tostring(res) .. ")")
		end
		c.refreshReady()
	end)
	task.spawn(function()
		local ok, res = pcall(hookKO)
		Waits.koReady = ok and res == true
		if not Waits.koReady then
			Util.warnOnce("ko", "Arms/KOSystem hook unavailable: 기절 단축 off (" .. tostring(res) .. ")")
		end
		c.refreshReady()
	end)
	-- buying while in a cell: tell them it applies from the next arrest
	c.Ownership.onChanged(function(player: Player, key: string, owned: boolean)
		if key == "Convenience" and owned then
			local j = player:GetAttribute("LawJail")
			if type(j) == "number" and j > P.serverNow() then
				c.Net.send(player, { kind = "toast", icon = "⚡", title = Lines.t("jail_next"), tone = "info" })
			end
			local rec = ko[player]
			if rec then
				setKOEnd(player, rec)
			end
		end
	end)
end

return Waits
