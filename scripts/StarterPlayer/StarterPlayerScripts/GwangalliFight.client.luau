-- GwangalliFight (LocalScript, StarterPlayerScripts; owner: npc): the NPC side of 길거리 싸움 on this
-- client (contract: ReplicatedStorage.GwangalliFightShared; server: GwangalliGameplay/Fight).
-- NO UI and no attack input of its own: the player's combat system (its buttons, animations and
-- hitboxes) reports a hit that LANDED on an NPC through LocalPlayer.GwangalliNPCHitAPI; the
-- existing 어깨빵 and the talk card's 때리기 reach the same server code directly.
--   * the server's answer plays here on the street pedestrian (client-side rigs): the fall (stagger /
--     knockdown) or the KO (down for good, then taken away), the line, and what they do next (fight
--     back = a brawl with real swings, flee, a phone report, an officer's arrest, cower) + the short
--     memory (GwangalliStreetAPI "remember": the person stays wary / scared of you a while).
--   * "down": citizens in hospital are not spawned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local FS = require(ReplicatedStorage:WaitForChild("GwangalliFightShared"))
local Bump: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliBumpShared")
	if m then
		local ok, res = pcall(require, m)
		Bump = if ok then res else nil
	end
end

local action: RemoteEvent? = nil
local streetApi: BindableFunction? = nil

local function street(method: string, ...: any): any
	local api = streetApi
	if not api or not api.Parent then
		local a = player:FindFirstChild("GwangalliStreetAPI")
		if a and a:IsA("BindableFunction") then
			streetApi = a
			api = a
		else
			return nil
		end
	end
	local ok, res = pcall(function(...)
		return (api :: BindableFunction):Invoke(method, ...)
	end, ...)
	return if ok then res else nil
end

local function character(): (Model?, Humanoid?, BasePart?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if hum and root and root:IsA("BasePart") and hum.Health > 0 then
		return ch, hum, root
	end
	return nil, nil, nil
end

local CollectionService = game:GetService("CollectionService")
local function keyModel(id: string): Model?
	local f = workspace:FindFirstChild("GwangalliNPCs")
	for _, m in (if f then f:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id then
			return m
		end
	end
	-- shop staff (GwangalliGameplay/ShopStaff, tagged GwShopStaff)
	for _, m in CollectionService:GetTagged("GwShopStaff") do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

-- a street pedestrian's rig root (client-side rigs in Workspace.GwangalliStreetLife, StreetId = id)
local function pedRoot(id: string): BasePart?
	local f = workspace:FindFirstChild("GwangalliStreetLife")
	if not f then
		return nil
	end
	for _, m in f:GetChildren() do
		if m:GetAttribute("StreetId") == id then
			local r = m:FindFirstChild("HumanoidRootPart")
			return if r and r:IsA("BasePart") then r else nil
		end
	end
	return nil
end

-- a "near" entry's position (root if it came through, else its numbers)
local function entryPos(e: any): Vector3?
	if typeof(e.root) == "Instance" and e.root:IsA("BasePart") then
		return e.root.Position
	end
	local x, y, z = tonumber(e.x), tonumber(e.y), tonumber(e.z)
	if x and y and z then
		return Vector3.new(x, y, z)
	end
	return nil
end

local function bubble(adornee: Instance?, text: string?, dur: number?)
	if not adornee or not text or text == "" then
		return
	end
	local ev = player:FindFirstChild((Bump and Bump.BUBBLE_EVENT) or "GwangalliBubble")
	if ev and ev:IsA("BindableEvent") then
		ev:Fire(adornee, text, "plain", dur or 3, 3.2)
	end
end

-------------------------------------------------------------------------------------------------
-- hits IN (no UI here: the combat system owns buttons, hitboxes, HUD)
-------------------------------------------------------------------------------------------------
-- LocalPlayer.GwangalliNPCHitAPI (BindableFunction), for the player's combat system on this client:
--   Invoke("hit", { model = <an NPC Model the hitbox touched> | kind = "ped"|"npc", id = ..., attack =
--     "punch" | "kick" | "shove" | "strong", power = 0..2 (1 = a normal punch) }) -> true when sent.
--     Call it ONLY for a hit that landed (the hitbox touched the NPC). The server checks the reach
--     again and decides damage / reaction; nothing happens for a miss.
--   Invoke("resolve", model) -> { kind, id } for a Model the hitbox touched (a street pedestrian rig in
--     Workspace.GwangalliStreetLife carries StreetId; any server NPC rig an NpcId: key NPCs, police /
--     특임대 / 119, Law actors, customers, shop staff; not the jail's inmates, not the 알바 / minigame
--     rigs: FightShared.foreign).
local lastHit = 0

local function resolve(model: Instance?): (string?, string?, Vector3?, number?)
	local m = model
	-- (a hitbox may touch an accessory / tool inside the rig: up to the Model that carries the id)
	while m and not (m:IsA("Model") and (m:GetAttribute("StreetId") ~= nil or m:GetAttribute("NpcId") ~= nil)) do
		m = m.Parent
	end
	if not m then
		return nil, nil, nil, nil
	end
	local sid = m:GetAttribute("StreetId")
	local r = m:FindFirstChild("HumanoidRootPart")
	local pos = if r and r:IsA("BasePart") then r.Position else nil
	if type(sid) == "string" then
		return "ped", sid, pos, tonumber(m:GetAttribute("StreetSn"))
	end
	local nid = m:GetAttribute("NpcId")
	-- (not the jail's inmates, not the 알바 / minigame rigs or stations: FS.foreign)
	if type(nid) == "string" and nid ~= "" and m:GetAttribute("NpcKind") ~= "inmate" and not FS.foreign(nid, m) then
		return "npc", nid, pos, nil
	end
	return nil, nil, nil, nil
end

local function pedPos(id: string): (Vector3?, string?, number?)
	local near = street("near", 40)
	for _, e in (if type(near) == "table" then near else {}) do
		if type(e) == "table" and e.id == id then
			return entryPos(e), e.typeId, tonumber(e.sn)
		end
	end
	return nil, nil, nil
end

local function sendHit(spec: any): boolean
	if not action or type(spec) ~= "table" then
		return false
	end
	if os.clock() - lastHit < 0.12 then
		return false -- (one swing = one hit, even if two hitbox parts touched)
	end
	local kind, id, pos, sn = spec.kind, spec.id, nil, nil
	if typeof(spec.model) == "Instance" then
		kind, id, pos, sn = resolve(spec.model)
	end
	if type(kind) ~= "string" or type(id) ~= "string" then
		return false
	end
	local ptype = nil
	if kind == "ped" then
		local p2, t2, s2 = pedPos(id)
		pos = pos or p2
		ptype = t2
		sn = sn or s2
	else
		local m = keyModel(id)
		local r = m and m:FindFirstChild("HumanoidRootPart")
		pos = pos or (r and r:IsA("BasePart") and r.Position or nil)
	end
	if not pos then
		return false
	end
	lastHit = os.clock()
	action:FireServer("punch", { kind = kind, id = id, pos = { pos.X, pos.Y, pos.Z }, ptype = ptype, attack = spec.attack, power = spec.power, sn = sn })
	return true
end

local hitApi = Instance.new("BindableFunction")
hitApi.Name = "GwangalliNPCHitAPI"
hitApi.OnInvoke = function(op: string, arg: any)
	if op == "hit" then
		return sendHit(arg)
	elseif op == "resolve" then
		local k, id = resolve(arg)
		return if k then { kind = k, id = id } else nil
	end
	return nil
end
hitApi.Parent = player

-------------------------------------------------------------------------------------------------
-- server answers: the NPC's reaction (no UI: the fall / the line / what they do next)
-------------------------------------------------------------------------------------------------
local function onEvent(p: any)
	if type(p) ~= "table" then
		return
	end
	if p.kind == "hit" and type(p.id) == "string" then
		-- 정의감 높은 사람들이 본다, the victim's friends take their side (GwangalliStreetLife/Characters)
		street("witness", p.id, p.attack, p.outcome)
		local dx, dz = tonumber(p.dx) or 0, tonumber(p.dz) or -1
		if p.target == "ped" then
			if p.outcome == "ko" then
				street("ko", p.id, dx, dz, p.ko or FS.KO_DOWN)
			elseif p.outcome ~= "none" and p.attack ~= "car" then
				-- (a car hit already fell here when the car touched them: Crowd's contact pass)
				street("knock", p.id, dx, dz, p.outcome, if p.crit then "퍽!!" else "퍽!")
			end
			if type(p.line) == "string" then
				task.delay(0.35, function()
					street("say", p.id, p.line, nil, 3)
				end)
			end
			if p.react == "fight" then
				-- the server's window (one brawl, not two different lengths) and how hurt they are
				local hpFrac = (tonumber(p.hp) or 1) / math.max(1, tonumber(p.max) or 1)
				street("brawl", p.id, tonumber(p.brawl) or FS.BRAWL_S[1], hpFrac)
			elseif p.react == "flee" or p.react == "report" or p.react == "arrest" or p.react == "cower" or p.react == "warn" then
				street("react", p.id, p.react)
			end
			street("remember", p.id, if p.react == "fight" or p.react == "warn" then "anger" else "fear", if p.outcome == "ko" then 3 else 1)
		else
			local m = keyModel(p.id)
			bubble(m and m:FindFirstChild("Head"), p.line, 3)
		end
	elseif p.kind == "remember" and type(p.id) == "string" then
		street("remember", p.id, p.mood, 1)
		if p.crime == true then
			-- a hit the caller played itself (the talk card's 때리기): the same people react as to a punch
			street("witness", p.id, nil, p.outcome)
		end
	elseif p.kind == "hurt" and type(p.outcome) == "string" then
		-- a server rig's swing landed (a key NPC fighting back): the fall here (the 어깨빵 motion); a
		-- street brawler's own swing already played it on this client (no outcome then)
		local ch, hum = character()
		local knocked = (Bump and Bump.Attr and Bump.Attr.Knocked) or "GwangalliKnocked"
		if Bump and ch and hum and not hum.Sit and not ch:GetAttribute(knocked) and type(Bump.knockCharacter) == "function" then
			local okK, did = pcall(Bump.knockCharacter, ch, tonumber(p.dx) or 0, tonumber(p.dz) or 0, if p.outcome == "knockdown" then "knockdown" else "stagger", {})
			if okK and did and type(Bump.shakeCamera) == "function" then
				pcall(Bump.shakeCamera, if p.outcome == "knockdown" then 0.35 else 0.14, 0.4)
			end
		end
	elseif p.kind == "brawlEnd" and type(p.id) == "string" then
		street("brawl", p.id, 0) -- (the server did not take that fight: it is called off)
	elseif p.kind == "say" and type(p.id) == "string" then
		local m = keyModel(p.id)
		bubble(m and m:FindFirstChild("Head"), p.line, 3)
	elseif p.kind == "incident" and type(p.what) == "string" then
		-- 생활콘텐츠 -> NPC: the street mind casts the people and plays it
		local mapi = player:FindFirstChild("GwangalliMindAPI")
		if mapi and mapi:IsA("BindableFunction") then
			local at = if type(p.pos) == "table" then Vector3.new(p.pos[1], p.pos[2], p.pos[3]) else nil
			local okI, res = pcall(function()
				return (mapi :: BindableFunction):Invoke("incident", p.what, { pos = at, id = p.id })
			end)
			-- (the outcome back to the server: was anybody cast - player attribute GwangalliIncidentLast)
			if action then
				action:FireServer("incidentDone", { kind = p.what, ok = okI and res == true })
			end
		end
	elseif p.kind == "crime" and type(p.crime) == "string" then
		-- a crime this module noted (a hit, a car hit, a KO): the street crowd around reacts by
		-- personality (GwangalliStreetLife Mind.onCrime; a witness who calls 112 reports it)
		local mapi = player:FindFirstChild("GwangalliMindAPI")
		if mapi and mapi:IsA("BindableFunction") then
			pcall(function()
				(mapi :: BindableFunction):Invoke("crime", { crime = p.crime, pos = p.pos, victim = p.victim, car = p.car == true })
			end)
		end
	elseif p.kind == "gunfire" and type(p.pos) == "table" then
		street("gunfire", p.pos[1], p.pos[2], p.pos[3])
	elseif p.kind == "commotion" and type(p.pos) == "table" then
		-- a scuffle among server rigs (Law/City): the street crowd around notices
		street("commotion", p.pos[1], p.pos[2], p.pos[3])
	elseif p.kind == "ems" and type(p.id) == "string" then
		-- 119 (GwangalliGameplay/Law/Rescue): the casualty waits for the ambulance / is carried off
		if p.phase == "dispatched" then
			street("emshold", p.id, tonumber(p.hold) or 150)
		elseif p.phase == "pickup" then
			street("emspickup", p.id)
		end
	elseif p.kind == "down" then
		street("hospital", p.ids)
	end
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(FS.Folder, 60)
	if not folder then
		return
	end
	local a = folder:WaitForChild(FS.Remote.Action, 20)
	local e = folder:WaitForChild(FS.Remote.Event, 20)
	if a and a:IsA("RemoteEvent") then
		action = a
	end
	if e and e:IsA("RemoteEvent") then
		e.OnClientEvent:Connect(function(p)
			local ok, err = pcall(onEvent, p)
			if not ok then
				warn("[GwangalliFight] " .. tostring(err))
			end
		end)
	end
end)

-------------------------------------------------------------------------------------------------
-- test harness only (workspace GwangalliStreetLifeDebug): LocalPlayer.GwangalliFightAPI
--   "tp" {x,y,z} | "goto" id? / "*anon" | "gopunch" id (stand next to them, then one landed hit
--   through the same path a combat system uses)
-------------------------------------------------------------------------------------------------
local debugQueue: { () -> () } = {}
local api = Instance.new("BindableFunction")
api.Name = "GwangalliFightAPI"
api.OnInvoke = function(op: string, arg: any)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
		return nil
	end
	local _, _, root = character()
	if op == "tp" and type(arg) == "table" and root then
		local cf = CFrame.new(arg[1], arg[2], arg[3])
		table.insert(debugQueue, function()
			player.Character:PivotTo(cf)
			root.AssemblyLinearVelocity = Vector3.zero
		end)
		return true
	elseif op == "goto" and root then
		local near = street("near", 160)
		local best, bd, bestPos = nil, math.huge, nil
		for _, e in (if type(near) == "table" then near else {}) do
			local at = type(e) == "table" and entryPos(e)
			local want = arg == nil or e.id == arg or (arg == "*anon" and string.match(tostring(e.id), "^x%d+$") ~= nil)
			if at and not e.down and want then
				local d = (at - root.Position).Magnitude
				if d < bd then
					best, bd, bestPos = e, d, at
				end
			end
		end
		if not best or not bestPos then
			return nil
		end
		local p = bestPos :: Vector3
		local at = p + Vector3.new(2.6, 0, 0)
		table.insert(debugQueue, function()
			player.Character:PivotTo(CFrame.lookAt(at, Vector3.new(p.X, at.Y, p.Z)))
			root.AssemblyLinearVelocity = Vector3.zero
		end)
		return best.id
	elseif op == "gopunch" and type(arg) == "string" then
		local p = pedPos(arg)
		if not p then
			return nil
		end
		table.insert(debugQueue, function()
			local _, _, r = character()
			if not r then
				return
			end
			local stand = (p :: Vector3) + Vector3.new(2.4, 0, 0)
			player.Character:PivotTo(CFrame.lookAt(stand, Vector3.new(p.X, stand.Y, p.Z)))
			r.AssemblyLinearVelocity = Vector3.zero
			RunService.Heartbeat:Wait()
			RunService.Heartbeat:Wait()
			lastHit = 0
			-- through the receiver itself (what a combat system calls)
			hitApi:Invoke("hit", { kind = "ped", id = arg, attack = "punch", power = 1 })
		end)
		return true
	elseif op == "gopunchModel" and type(arg) == "table" and type(arg.id) == "string" then
		-- the rig model the way a hitbox reports it (tests resolve too): a street pedestrian or a server rig;
		-- arg = { id, attack?, power?, stay? } (stay = punch from where the player is)
		local m: Model? = nil
		local f = workspace:FindFirstChild("GwangalliStreetLife")
		for _, x in (if f then f:GetChildren() else {}) do
			if x:IsA("Model") and x:GetAttribute("StreetId") == arg.id then
				m = x
				break
			end
		end
		m = m or keyModel(arg.id)
		local mr = m and m:FindFirstChild("HumanoidRootPart")
		if not m or not mr or not mr:IsA("BasePart") then
			return nil
		end
		local model = m :: Model
		local mroot = mr :: BasePart
		table.insert(debugQueue, function()
			local _, _, r = character()
			if not r then
				return
			end
			if not arg.stay then
				local p = mroot.Position
				local stand = p + Vector3.new(2.4, 0, 0)
				player.Character:PivotTo(CFrame.lookAt(stand, Vector3.new(p.X, stand.Y, p.Z)))
				r.AssemblyLinearVelocity = Vector3.zero
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
			end
			lastHit = 0
			local part = model:FindFirstChild("Head") or mroot
			hitApi:Invoke("hit", { model = part, attack = arg.attack or "punch", power = arg.power or 1 })
		end)
		return true
	end
	return nil
end
api.Parent = player
task.spawn(function()
	while true do
		task.wait(0.2)
		while #debugQueue > 0 do
			task.spawn(table.remove(debugQueue, 1))
		end
	end
end)
