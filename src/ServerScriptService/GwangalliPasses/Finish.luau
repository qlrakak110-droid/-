-- GwangalliPasses/Finish (server): pass #4 과시 패스, KO 피니시 이펙트.
-- KO events come off ServerStorage.GwangalliCrimeBus (Arms):
--   KnockedOut     a PLAYER went down: payload.by = attacker UserId when kind == "player"
--   NpcKnockedOut  an NPC / pedestrian: payload.player = the attacker
--   OfficerDown    a police NPC:       payload.player = the attacker (may be nil)
-- If the attacker owns Flex and picked an effect, every player within RANGE of the spot gets
-- Event { kind = "kofx", fx, pos, by, victim, self } (the attacker: self = true -> banner + 승리 포즈).
-- Rate limits: one effect per attacker per PER_ATTACKER_GAP s, SERVER_PER_SEC per second overall.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Finish = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any, KoFx: any
local lastBy: { [Player]: number } = {}
local lastPreview: { [Player]: number } = {}
local window = { t = 0, n = 0 }

Finish.ready = false

local function owns(player: Player): boolean
	return ctx.Ownership.owns(player, "Flex")
end

local function current(player: Player): string?
	if not owns(player) then
		return nil
	end
	local id = ctx.Data.get(player).ko
	return if type(id) == "string" and KoFx.get(id) then id else nil
end

local function serverGate(): boolean
	local t = os.clock()
	if t - window.t >= 1 then
		window.t = t
		window.n = 0
	end
	if window.n >= Config.KOFX.SERVER_PER_SEC then
		return false
	end
	window.n += 1
	return true
end

local function fire(attacker: Player, pos: Vector3, victim: string, victimChar: Instance?)
	local fx = current(attacker)
	if not fx then
		return
	end
	local t = os.clock()
	if t - (lastBy[attacker] or -1e9) < Config.KOFX.PER_ATTACKER_GAP then
		return
	end
	if not serverGate() then
		return
	end
	lastBy[attacker] = t
	ctx.Net.sendNear(pos, Config.KOFX.RANGE, { kind = "kofx", fx = fx, pos = pos, by = attacker.UserId, victim = victim, char = victimChar, neon = attacker:GetAttribute(P.Attr.Neon) }, function(p: Player)
		return { self = p == attacker }
	end)
end

local function posOf(payload: any, fallback: Player?): Vector3?
	if typeof(payload.pos) == "Vector3" then
		return payload.pos
	end
	if fallback then
		local r = Util.root(fallback)
		return r and r.Position or nil
	end
	return nil
end

local function onBus(name: any, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if name == "KnockedOut" then
		if payload.kind ~= "player" then
			return
		end
		local by = tonumber(payload.by)
		local attacker = by and Players:GetPlayerByUserId(by)
		local victim = payload.player
		if not attacker or attacker == victim then
			return
		end
		local vp = if typeof(victim) == "Instance" and victim:IsA("Player") then victim else nil
		local pos = posOf(payload, vp)
		if pos then
			fire(attacker, pos, "player", vp and vp.Character)
		end
	elseif name == "NpcKnockedOut" or name == "OfficerDown" then
		local attacker = payload.player
		if typeof(attacker) ~= "Instance" or not attacker:IsA("Player") then
			return
		end
		local pos = posOf(payload, nil)
		if pos then
			fire(attacker, pos, if name == "OfficerDown" then "officer" else "npc", nil)
		end
	end
end

function Finish.setFx(player: Player, fx: any): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked", message = Lines.t("locked_tab", Config.PASSES.Flex.Title) }
	end
	local id: string? = nil
	if type(fx) == "string" and fx ~= "" then
		if not KoFx.get(fx) then
			return { ok = false, code = "bad" }
		end
		id = fx
	end
	ctx.Data.update(player, function(prof)
		prof.ko = id or "off"
	end)
	player:SetAttribute(P.Attr.KoFx, id)
	return { ok = true, message = Lines.t("kofx_saved"), fx = id }
end

-- a preview for the requester only, a few studs in front of them
function Finish.preview(player: Player, fx: any): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked" }
	end
	if not KoFx.get(fx) then
		return { ok = false, code = "bad" }
	end
	local t = os.clock()
	if t - (lastPreview[player] or -1e9) < Config.KOFX.PREVIEW_GAP then
		return { ok = false, code = "cooldown", message = Lines.t("busy") }
	end
	lastPreview[player] = t
	local r = Util.root(player)
	if not r then
		return { ok = false, code = "dead" }
	end
	local look = Util.flat(r.CFrame.LookVector)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	ctx.Net.send(player, { kind = "kofx", fx = fx, pos = r.Position + look * 9, by = player.UserId, victim = "preview", self = true, preview = true, neon = player:GetAttribute(P.Attr.Neon) })
	return { ok = true }
end

function Finish.start(c: any): boolean
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	KoFx = P.mod("KoFx")
	c.Data.loaded:Connect(function(player: Player)
		player:SetAttribute(P.Attr.KoFx, current(player))
	end)
	c.Ownership.onChanged(function(player: Player, key: string, owned: boolean)
		if key ~= "Flex" then
			return
		end
		if owned and ctx.Data.get(player).ko == nil then
			ctx.Data.update(player, function(prof)
				prof.ko = Config.KOFX.DEFAULT
			end)
		end
		player:SetAttribute(P.Attr.KoFx, current(player))
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		lastBy[p] = nil
		lastPreview[p] = nil
	end)
	local bus = Util.waitChild(ServerStorage, "GwangalliCrimeBus", "BindableEvent", 150)
	if not bus then
		Util.warnOnce("kofx", "ServerStorage.GwangalliCrimeBus not found: KO 피니시 이펙트 off (미리보기는 가능)")
		return false
	end
	(bus :: BindableEvent).Event:Connect(function(name: any, payload: any)
		local ok, err = pcall(onBus, name, payload)
		if not ok then
			Util.warnOnce("kofx bus", err)
		end
	end)
	Finish.ready = true
	return true
end

return Finish
