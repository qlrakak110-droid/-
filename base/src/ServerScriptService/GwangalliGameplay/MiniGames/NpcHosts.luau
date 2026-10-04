--!strict
-- MiniGames/NpcHosts: the NPCs who wait at the minigame spots (박씨 아저씨 at the omok table, 민준 at
-- the word-chain table, 하은 the tourist at the 가위바위보 sign ...). Server only, brain only.
--
-- Rigs are GwangalliNPCLooks block-R15 people (GwangalliAnim.buildR15 as a fallback) parented to
-- workspace.GwangalliNPCs with the NPC.luau attribute contract, so StarterPlayerScripts.
-- GwangalliNPCClient animates them like every key NPC (acts, emotes, head look-at, LOD):
--   NpcId "mg_<id>", NpcKind "street", NpcAct, NpcYaw, NpcLeg (zero-length leg = stand here / a
--   short leg = walk), NpcLook (UserId), NpcEmote "name#seq#serverTime", NpcGround.
-- Modes: "host" (seated on SeatB / standing on PadB, waiting for a player: act sit / idle), "play"
-- (same spot, thinking / reacting during a match), "aside" (two players took the table: the NPC
-- gets up and watches from the side, arms crossed, and comes back afterwards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcHosts = {}

local M: any = nil
local MS: any = nil
local Looks: any = nil
local Anim: any = nil

type Host = {
	npc: any,
	station: any,
	model: Model,
	root: BasePart,
	head: BasePart?,
	ground: number,
	mode: string,
	emoteSeq: number,
	lastInvite: number,
	feetHost: Vector3,
	yawHost: number,
	actHost: string,
}
local hosts: { [string]: Host } = {} -- station id -> host

local function optional(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			return res
		end
	end
	return nil
end

function NpcHosts.init(m: any)
	M = m
	MS = m.MS
	Looks = optional("GwangalliNPCLooks")
	Anim = optional("GwangalliAnim")
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- yaw (degrees) whose facing (CFrame.Angles(0, yaw, 0).LookVector) points along `dir`
local function yawOf(dir: Vector3): number
	return math.deg(math.atan2(-dir.X, -dir.Z))
end

local function npcFolder(): Instance
	local f = workspace:FindFirstChild(MS.NpcFolder)
	if not f then
		f = Instance.new("Folder")
		f.Name = MS.NpcFolder
		f.Parent = workspace
	end
	return f :: Instance
end

local function nameTag(model: Model, head: BasePart?, npc: any)
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MiniGameNameTag"
	bb.Size = UDim2.fromOffset(170, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
	bb.MaxDistance = 45
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = head
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.5
	name.Text = npc.name
	name.Parent = bb
	local role = Instance.new("TextLabel")
	role.BackgroundTransparency = 1
	role.Position = UDim2.fromScale(0, 0.56)
	role.Size = UDim2.new(1, 0, 0.42, 0)
	role.Font = Enum.Font.GothamMedium
	role.TextScaled = true
	role.TextColor3 = Color3.fromRGB(255, 214, 110)
	role.TextStrokeTransparency = 0.6
	role.Text = npc.role .. " · " .. MS.DIFFICULTY[npc.difficulty]
	role.Parent = bb
	bb.Parent = model
end

local function buildRig(npc: any): (Model?, BasePart?, BasePart?, number)
	if Looks then
		local ok, rig = pcall(function()
			local spec = Looks.random(npc.seed, npc.look)
			return Looks.build(spec, { name = "MG_" .. npc.id, anchored = true, shadow = false })
		end)
		if ok and type(rig) == "table" and rig.model then
			return rig.model, rig.root, rig.head or (rig.parts and rig.parts.Head), rig.ground or 3
		end
		warn("[MiniGames] npc " .. npc.id .. ": look build failed: " .. tostring(rig))
	end
	if Anim then
		local ok, m, parts = pcall(Anim.buildR15, { name = "MG_" .. npc.id, body = npc.look.body or "m" })
		if ok and m then
			m:PivotTo(CFrame.new(0, -Anim.R15.rootY, 0) * m:GetPivot())
			return m, parts.HumanoidRootPart, parts.Head, Anim.R15.rootY
		end
	end
	return nil, nil, nil, 3
end

local function setAttr(h: Host, k: string, v: any)
	if h.model:GetAttribute(k) ~= v then
		h.model:SetAttribute(k, v)
	end
end

local function legStr(a: Vector3, b: Vector3, t0: number, dur: number): string
	return string.format("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", a.X, a.Y, a.Z, b.X, b.Y, b.Z, t0, dur)
end

local function place(h: Host, feet: Vector3, yaw: number, act: string, walkFrom: Vector3?)
	setAttr(h, "NpcYaw", math.floor(yaw * 10 + 0.5) / 10)
	setAttr(h, "NpcAct", act)
	if walkFrom and (walkFrom - feet).Magnitude > 0.5 then
		local dur = (walkFrom - feet).Magnitude / 6
		setAttr(h, "NpcLeg", legStr(walkFrom, feet, serverNow() + 0.1, dur))
		task.delay(dur + 0.2, function()
			if h.model.Parent then
				h.model:PivotTo(CFrame.new(feet + Vector3.new(0, h.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0))
			end
		end)
	else
		setAttr(h, "NpcLeg", legStr(feet, feet, serverNow(), 0.01))
		-- the whole rig (root + every body part), like NPC.luau's first placement
		h.model:PivotTo(CFrame.new(feet + Vector3.new(0, h.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0))
	end
end

-- Seated hosts: the rigs' sit pose lowers the hips ~1.25 studs from standing; the stool top is ~1.6
-- above the paving, so the seated rig's feet hang a little above it.
local SIT_RAISE = 0.55

function NpcHosts.spawn(station: any): Host?
	local npc = station.npc
	if not npc then
		return nil
	end
	local model, root, head, ground = buildRig(npc)
	if not model or not root then
		warn("[MiniGames] npc " .. npc.id .. ": no rig builder (GwangalliNPCLooks / GwangalliAnim missing)")
		return nil
	end
	local m = station.model
	local feet: Vector3
	local yaw: number
	local act: string
	if station.info.kind == "table" then
		local seat = m:FindFirstChild("SeatB") :: BasePart
		local focus = m:FindFirstChild("Focus") :: BasePart
		local base = seat.Position - Vector3.new(0, 1.45, 0)
		feet = base + Vector3.new(0, SIT_RAISE, 0)
		local d = focus.Position - seat.Position
		yaw = yawOf(Vector3.new(d.X, 0, d.Z))
		act = "sit"
	else
		local spot = m:FindFirstChild("SpotB") :: BasePart
		feet = spot.Position
		yaw = yawOf(spot.CFrame.LookVector)
		act = if station.game == "rps" then "hips" else "idle"
	end
	model:SetAttribute("NpcId", "mg_" .. npc.id)
	model:SetAttribute("NpcPost", "home")
	model:SetAttribute("NpcKind", "street")
	model:SetAttribute("NpcGround", ground)
	model:SetAttribute("NpcLook", 0)
	model:SetAttribute("NpcTalk", 0)
	model:SetAttribute("NpcEmote", "")
	model:SetAttribute("MiniGameHost", station.id)
	local h: Host = {
		npc = npc,
		station = station,
		model = model,
		root = root,
		head = head,
		ground = ground,
		mode = "host",
		emoteSeq = 0,
		lastInvite = 0,
		feetHost = feet,
		yawHost = yaw,
		actHost = act,
	}
	place(h, feet, yaw, act, nil)
	nameTag(model, head, npc)
	model.Parent = npcFolder()
	hosts[station.id] = h
	station.host = h
	return h
end

function NpcHosts.get(stationId: string): Host?
	return hosts[stationId]
end

function NpcHosts.head(stationId: string): BasePart?
	local h = hosts[stationId]
	return h and h.head
end

function NpcHosts.emote(stationId: string, name: string)
	local h = hosts[stationId]
	if not h then
		return
	end
	h.emoteSeq += 1
	setAttr(h, "NpcEmote", string.format("%s#%d#%.1f", name, h.emoteSeq, serverNow()))
end

function NpcHosts.act(stationId: string, act: string?)
	local h = hosts[stationId]
	if h then
		setAttr(h, "NpcAct", act or h.actHost)
	end
end

function NpcHosts.look(stationId: string, userId: number)
	local h = hosts[stationId]
	if h then
		setAttr(h, "NpcLook", userId)
	end
end

-- Speech bubble over the NPC (and the line is remembered for the station prompt).
function NpcHosts.say(stationId: string, kind: string, text: string?)
	local h = hosts[stationId]
	if not h then
		return
	end
	local line = text or MS.line(h.npc, kind)
	if line and h.head then
		M.say(h.head, line, 3.5)
	end
end

function NpcHosts.setMode(stationId: string, mode: string)
	local h = hosts[stationId]
	if not h or h.mode == mode then
		return
	end
	local m = h.station.model
	if mode == "aside" then
		local aside = m:FindFirstChild("NpcAside") :: BasePart?
		if aside then
			local focus = m:FindFirstChild("Focus") :: BasePart
			local d = focus.Position - aside.Position
			place(h, aside.Position, yawOf(Vector3.new(d.X, 0, d.Z)), "arms_crossed", (h.root.Position - Vector3.new(0, h.ground, 0)))
		end
	else
		local from = if h.mode == "aside" then h.root.Position - Vector3.new(0, h.ground, 0) else nil
		place(h, h.feetHost, h.yawHost, if mode == "play" and h.actHost == "idle" then "idle" else h.actHost, from)
	end
	h.mode = mode
end

-- Every few seconds while the station is free: greet a player who walks by.
function NpcHosts.idleTick(stationId: string, nearest: Player?, dist: number)
	local h = hosts[stationId]
	if not h or h.mode ~= "host" then
		return
	end
	if nearest and dist < 12 then
		setAttr(h, "NpcLook", nearest.UserId)
		local now = os.clock()
		if now - h.lastInvite > 30 then
			h.lastInvite = now
			NpcHosts.say(stationId, "invite")
			NpcHosts.emote(stationId, if math.random() < 0.5 then "wave_small" else "beckon")
		end
	else
		setAttr(h, "NpcLook", 0)
	end
end

return NpcHosts
