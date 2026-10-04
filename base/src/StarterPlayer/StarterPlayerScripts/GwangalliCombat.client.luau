if game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliStreetCombatShared") then return end
-- GwangalliCombat (LocalScript, StarterPlayerScripts; owner: combat client): the player's side of 전투 · 범죄 · 경찰.
-- The server decides everything (ServerScriptService.GwangalliGameplay.Crime); this script asks and renders:
--   * Moves  — punching (F / ButtonX / a click on the world / the 주먹 button): a jab -> cross -> hook combo on the
--              avatar (GwangalliAnim controller), the target in front (pedestrians, key NPCs, police, other players
--              with BumpEnabled), FireServer("punch"); other players' punches (GwCombatMove) and every character's
--              combat pose (GwCombatPose: hands up / cuffed / kneeling / KO).
--   * Hud    — the 주먹 button, the ❤ HP + ★ wanted card, the police stop order, the arrest result, the KO text.
--   * Fx     — red edge vignette, low-HP breathing, siren edges while chased, damage numbers, shakes, sounds.
--   * Street — the client crowd's reactions: flee, film, call 112, cower, victims, violent people fighting back.
-- Modules live in the sibling Folder "GwangalliCombat" (same name as this script: found by class).
-- Remotes: ReplicatedStorage.GwangalliCombat.CombatAction (client -> server, FireServer(kind, payload)) and
-- CombatEvent (server -> client, payload.kind = hit | miss | hurt | crime | alarm | stop | stopEnd | arrest | ko |
-- wake | say | search | escaped); contract in ReplicatedStorage.GwangalliCombatShared.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliCombat" and child:IsA("Folder") then
					return child
				end
			end
		end
		task.wait(0.1)
	end
	return nil
end

local folder = findFolder()
if not folder then
	warn("[GwangalliCombat] module folder missing next to the LocalScript")
	return
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local function optional(name: string, timeout: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliCombat] " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

local Combat = optional("GwangalliCombatShared", 30)
local K = optional("GwangalliUI", 30)
if not Combat or not K then
	warn("[GwangalliCombat] GwangalliCombatShared / GwangalliUI missing: combat disabled")
	return
end
local Layout = K.Layout or optional("GwangalliLayout", 10)
local Anim = optional("GwangalliAnim", 15)
local CA = optional("GwangalliCombatAnim", 15)
if Anim and CA then
	pcall(CA.install, Anim) -- (GwangalliAnim's own hook normally did it already: idempotent)
end
local Bump = optional("GwangalliBumpShared", 10)
local Social = optional("GwangalliSocialShared", 5)

local playerGui = player:WaitForChild("PlayerGui", 30)
if not playerGui then
	warn("[GwangalliCombat] PlayerGui missing")
	return
end

-------------------------------------------------------------------------------------------------
-- shared context
-------------------------------------------------------------------------------------------------
local warned: { [string]: number } = {}
local ctx: any = {
	player = player,
	playerGui = playerGui,
	K = K,
	Layout = Layout,
	Combat = Combat,
	CA = CA,
	Anim = Anim,
	Bump = Bump,
	Social = Social,
	ready = false, -- the server's remotes exist
	action = nil :: RemoteEvent?,
	debug = workspace:GetAttribute("GwangalliCombatDebug") == true,
}

-- a warning at most every 10 s per key (per-frame code must never flood the output)
function ctx.warnOnce(key: string, msg: string)
	local now = os.clock()
	if warned[key] and now - warned[key] < 10 then
		return
	end
	warned[key] = now
	warn(msg)
end

function ctx.serverNow(): number
	return workspace:GetServerTimeNow()
end

function ctx.fire(kind: string, payload: any): boolean
	local a = ctx.action
	if not a or not a.Parent then
		return false
	end
	local ok, err = pcall(a.FireServer, a, kind, payload or {})
	if not ok then
		ctx.warnOnce("fire", "[GwangalliCombat] FireServer " .. kind .. ": " .. tostring(err))
	end
	return ok
end

function ctx.character(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	if not c or not c.Parent then
		return nil, nil, nil
	end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if not h or not r or not r:IsA("BasePart") then
		return c, nil, nil
	end
	return c, h, r :: BasePart
end

-- why the local player cannot fight right now (nil = can)
function ctx.blockReason(): string?
	local ch, hum, root = ctx.character()
	if not ch or not hum or not root or hum.Health <= 0 then
		return "dead"
	end
	if hum.Sit or hum.SeatPart then
		return "seated"
	end
	if player:GetAttribute(Combat.Attr.Arrested) == true then
		return "arrested"
	end
	if ch:GetAttribute(Combat.Attr.KO) == true then
		return "ko"
	end
	local pose = ch:GetAttribute(Combat.Attr.Pose)
	if type(pose) == "string" and pose ~= "" then
		return "pose"
	end
	-- working a shift, training at the gym or riding a taxi (the same rules as 어깨빵)
	if player:GetAttribute("OnShift") or player:GetAttribute("GymBusy") or player:GetAttribute("InTaxi") then
		return "busy"
	end
	if hum.PlatformStand or ch:GetAttribute(Combat.Attr.Knocked) == true or (Bump and type(Bump.isDown) == "function" and Bump.isDown()) then
		return "down"
	end
	return nil
end

-- the GwangalliStreetLife BindableFunction (pedestrians are client-side)
local streetApi: BindableFunction? = nil
function ctx.street(method: string, ...: any): any
	local api = streetApi
	if not api or not api.Parent then
		local f = player:FindFirstChild("GwangalliStreetAPI")
		if f and f:IsA("BindableFunction") then
			streetApi = f
			api = f
		else
			return nil
		end
	end
	local ok, res = pcall((api :: BindableFunction).Invoke, api, method, ...)
	return if ok then res else nil
end

local npcFolder: Instance? = nil
local npcCache: { [string]: Model } = {}
function ctx.npcModel(id: any): Model?
	if type(id) ~= "string" then
		return nil
	end
	local m = npcCache[id]
	if m and m.Parent and m:GetAttribute("NpcId") == id then
		return m
	end
	if not npcFolder or not npcFolder.Parent then
		npcFolder = workspace:FindFirstChild("GwangalliNPCs")
	end
	if not npcFolder then
		return nil
	end
	for _, c in npcFolder:GetChildren() do
		if c:IsA("Model") and c:GetAttribute("NpcId") == id then
			npcCache[id] = c
			return c
		end
	end
	return nil
end

function ctx.headOf(model: Instance?): BasePart?
	if not model then
		return nil
	end
	local h = model:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- the part a target's number / bubble hangs on
function ctx.targetPart(kind: any, id: any): BasePart?
	if kind == "street" then
		return ctx.Street and ctx.Street.partOf(id) or nil
	elseif kind == "npc" or kind == "police" then
		return ctx.headOf(ctx.npcModel(id))
	elseif kind == "player" then
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		return ctx.headOf(p and p.Character)
	end
	return nil
end

-- the shared pooled speech bubbles (GwangalliBumpShared; type colours from GwangalliSocialShared)
function ctx.bubble(adornee: any, text: any, typeId: any, dur: any, offsetY: any)
	if not Bump or type(Bump.bubbles) ~= "function" or typeof(adornee) ~= "Instance" then
		return
	end
	local ok, pool = pcall(Bump.bubbles, { font = K.Font.medium, types = Social and Social.TYPES })
	if ok and pool then
		pcall(pool.say, pool, adornee, text, typeId, dur, offsetY)
	end
end

-------------------------------------------------------------------------------------------------
-- modules
-------------------------------------------------------------------------------------------------
local function load(name: string): any
	local m = folder:FindFirstChild(name) or folder:WaitForChild(name, 10)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliCombat] module " .. name .. " missing")
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok or type(res) ~= "table" then
		warn("[GwangalliCombat] module " .. name .. " failed to load: " .. tostring(res))
		return nil
	end
	return res
end

ctx.Fx = load("Fx")
ctx.Street = load("Street")
ctx.Moves = load("Moves")
ctx.Hud = load("Hud")
for _, name in { "Fx", "Street", "Moves", "Hud" } do
	local mod = ctx[name]
	if mod and type(mod.init) == "function" then
		local ok, err = pcall(mod.init, ctx)
		if not ok then
			warn("[GwangalliCombat] " .. name .. ".init failed: " .. tostring(err))
			ctx[name] = nil
		end
	end
end

local function call(mod: any, fn: string, ...: any)
	if mod and type(mod[fn]) == "function" then
		local ok, err = pcall(mod[fn], ...)
		if not ok then
			ctx.warnOnce("ev-" .. fn, "[GwangalliCombat] " .. fn .. ": " .. tostring(err))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- server events
-------------------------------------------------------------------------------------------------
local function dispatch(p: any)
	if type(p) ~= "table" or type(p.kind) ~= "string" then
		return
	end
	local kind = p.kind
	if ctx.debug then
		print("[GwangalliCombat] event " .. kind)
	end
	if kind == "hit" then
		call(ctx.Moves, "onHit", p)
		if p.target == "street" then
			call(ctx.Street, "onHit", p)
		end
	elseif kind == "miss" then
		call(ctx.Moves, "onMiss", p)
	elseif kind == "hurt" then
		call(ctx.Moves, "onHurt", p)
		call(ctx.Hud, "onHurt", p)
		if ctx.Fx then
			local dmg = tonumber(p.dmg) or 0
			local strong = p.outcome == "knockdown" or p.outcome == "stagger"
			ctx.Fx.hurt(math.clamp(dmg / 16, 0.25, 1) + (if strong then 0.2 else 0))
			ctx.Fx.shake(if p.outcome == "knockdown" then 0.35 elseif strong then 0.22 else 0.14, if p.outcome == "knockdown" then 0.4 else 0.25)
			ctx.Fx.sound("hurt")
		end
	elseif kind == "crime" then
		call(ctx.Hud, "onCrime", p)
	elseif kind == "alarm" then
		call(ctx.Street, "onAlarm", p)
	elseif kind == "stop" then
		call(ctx.Hud, "onStop", p)
	elseif kind == "stopEnd" then
		call(ctx.Hud, "onStopEnd", p)
	elseif kind == "arrest" then
		call(ctx.Hud, "onArrest", p)
	elseif kind == "ko" then
		call(ctx.Hud, "onKO", p)
	elseif kind == "wake" then
		call(ctx.Hud, "onWake", p)
	elseif kind == "search" then
		call(ctx.Hud, "onSearch", p)
	elseif kind == "escaped" then
		call(ctx.Hud, "onEscaped", p)
	elseif kind == "say" then
		if type(p.id) == "string" and type(p.text) == "string" then
			local dur = tonumber(p.dur) or 3.5
			local handled = ctx.Street and ctx.Street.say(p.id, p.text, dur)
			if not handled then
				ctx.bubble(ctx.headOf(ctx.npcModel(p.id)), p.text, p.typeId, dur, 3.2)
			end
		end
	end
end

task.spawn(function()
	-- the server creates the folder at boot (parented last); wait for it without an infinite-yield warning
	local f: Instance? = nil
	local waited = 0
	while not f do
		f = ReplicatedStorage:WaitForChild(Combat.Folder, 30)
		if not f then
			waited += 30
			if waited == 60 then
				warn("[GwangalliCombat] ReplicatedStorage." .. Combat.Folder .. " missing: is the Crime server module running?")
			end
		end
	end
	local folderInst = f :: Instance
	local a = folderInst:WaitForChild(Combat.Remote.Action, 20)
	local e = folderInst:WaitForChild(Combat.Remote.Event, 20)
	if not a or not a:IsA("RemoteEvent") or not e or not e:IsA("RemoteEvent") then
		warn("[GwangalliCombat] combat remotes missing in ReplicatedStorage." .. Combat.Folder)
		return
	end
	ctx.action = a
	e.OnClientEvent:Connect(function(p)
		local ok, err = pcall(dispatch, p)
		if not ok then
			ctx.warnOnce("dispatch", "[GwangalliCombat] event failed: " .. tostring(err))
		end
	end)
	ctx.ready = true
	call(ctx.Hud, "refresh")
end)
