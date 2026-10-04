-- GwangalliTravel (server)
-- Quick travel between Destination parts (tag "Destination", attribute DisplayName, optional
-- attribute Order for sorting). Creates ReplicatedStorage.GwangalliTravel (RemoteEvent):
--   client -> server : FireServer("travel", destinationId)
--   server -> client : FireClient(player, "result", ok: boolean, message: string)
-- The destination list is published on the RemoteEvent as attribute "Destinations" (JSON array of
-- { id, name, order, x, z, cat? }) because with StreamingEnabled a client only has nearby Destination
-- parts (x / z: rounded position for distances in the HUD travel sheet; cat: optional part attribute
-- "Category", e.g. "beach" / "해변", overriding the sheet's keyword categories).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local configModule = ReplicatedStorage:WaitForChild("GwangalliConfig", 30)
if not configModule then
	warn("[GwangalliTravel] GwangalliConfig missing")
	return
end
local Config = require(configModule)
local cfg = Config.Travel

local TAG = "Destination"
-- Seconds to wait for the destination to stream to the client before moving the character there.
-- With StreamingMinRadius 128 and MinimumRadiusPause a dense venue needs ~5-7k parts before the client
-- unpauses; on LTE phones 4 s was too short (the pause screen showed). The client HUD keeps its
-- "in flight" state for this long + 3 s (GwangalliHUD TRAVEL_WAIT).
local STREAM_TIMEOUT = tonumber(cfg.StreamTimeout) or 8

local remote = ReplicatedStorage:FindFirstChild("GwangalliTravel")
if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "GwangalliTravel"
	remote.Parent = ReplicatedStorage
end
local travelRemote = remote :: RemoteEvent

-- Destination registry ------------------------------------------------------------------------------
local byId: { [string]: BasePart } = {}
local attrConns: { [Instance]: RBXScriptConnection } = {}

local function displayNameOf(part: BasePart): string
	local n = part:GetAttribute("DisplayName")
	if type(n) == "string" and n ~= "" then
		return n
	end
	return part.Name
end

local function orderOf(part: BasePart): number
	local order = part:GetAttribute("Order")
	return if type(order) == "number" and order == order then order else 1000
end

local function rebuild()
	table.clear(byId)
	-- Deterministic order (Order, name, position) so duplicate names always get the same suffix.
	local parts: { BasePart } = {}
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(parts, inst)
		end
	end
	table.sort(parts, function(a, b)
		local oa, ob = orderOf(a), orderOf(b)
		if oa ~= ob then
			return oa < ob
		end
		local na, nb = displayNameOf(a), displayNameOf(b)
		if na ~= nb then
			return na < nb
		end
		local pa, pb = a.Position, b.Position
		if pa.X ~= pb.X then
			return pa.X < pb.X
		end
		return pa.Z < pb.Z
	end)
	local entries = {}
	for _, inst in parts do
		local base = displayNameOf(inst)
		local id = base
		local n = 2
		while byId[id] do
			id = string.format("%s (%d)", base, n)
			n += 1
		end
		byId[id] = inst
		-- x / z (rounded studs) let clients show distances although the part may not be streamed in;
		-- cat is an optional explicit travel-sheet category (part attribute "Category")
		local pos = inst.Position
		local entry = { id = id, name = id, order = orderOf(inst), x = math.floor(pos.X + 0.5), z = math.floor(pos.Z + 0.5) }
		local cat = inst:GetAttribute("Category")
		if type(cat) == "string" and cat ~= "" then
			entry.cat = cat
		end
		table.insert(entries, entry)
	end
	table.sort(entries, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.name < b.name
	end)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, entries)
	travelRemote:SetAttribute("Destinations", ok and json or "[]")
	travelRemote:SetAttribute("DestinationCount", #entries)
end

local rebuildQueued = false
local function queueRebuild()
	if rebuildQueued then
		return
	end
	rebuildQueued = true
	task.defer(function()
		rebuildQueued = false
		local ok, err = pcall(rebuild)
		if not ok then
			warn("[GwangalliTravel] rebuild failed: " .. tostring(err))
		end
	end)
end

local function onAdded(inst: Instance)
	if not attrConns[inst] then
		attrConns[inst] = inst:GetAttributeChangedSignal("DisplayName"):Connect(queueRebuild)
	end
	queueRebuild()
end

local function onRemoved(inst: Instance)
	local c = attrConns[inst]
	if c then
		c:Disconnect()
		attrConns[inst] = nil
	end
	queueRebuild()
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(onAdded)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(onRemoved)
for _, inst in CollectionService:GetTagged(TAG) do
	onAdded(inst)
end
queueRebuild()

-- Travel requests -----------------------------------------------------------------------------------
type State = { lastRequest: number, lastTravel: number, busy: boolean }
local states: { [Player]: State } = {}

local function reply(player: Player, ok: boolean, message: string)
	if player.Parent == Players then
		travelRemote:FireClient(player, "result", ok, message)
	end
end

-- Root CFrame standing on the destination part's bottom face (its ground point), keeping only
-- the yaw so the character stands upright. `standHeight` = root height above the feet.
local function flatLook(part: BasePart): Vector3
	local look = part.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function groundOf(part: BasePart): Vector3
	-- lowest point of the (possibly rotated) part: its centre minus the world-Y half extent
	local cf, s = part.CFrame, part.Size
	local halfY = 0.5 * (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
	return part.Position - Vector3.new(0, halfY, 0)
end

local function standAt(feet: Vector3, look: Vector3, standHeight: number): CFrame
	local pos = feet + Vector3.new(0, standHeight + 0.5, 0)
	return CFrame.lookAt(pos, pos + look)
end

local function targetCFrame(part: BasePart, standHeight: number): CFrame
	return standAt(groundOf(part), flatLook(part), standHeight)
end

-- Builders place Destination markers by hand; some sit below a café terrace deck, a kerb step,
-- a fence plinth or next to a shop window, and builders disagree on whether the marker's
-- LookVector faces the door or the street. Probe the marker and nearby spots (symmetric order,
-- nearest first) for a floor within 4 studs above / 12 below with ~5 studs of free headroom,
-- and stand there; fall back to the marker's bottom face.
local PROBE_OFFSETS = { { 0, 0 }, { 0, 3 }, { 0, -3 }, { 3, 0 }, { -3, 0 }, { 0, 6 }, { 0, -6 }, { 4, 4 }, { -4, 4 }, { 4, -4 }, { -4, -4 }, { 0, 9 }, { 0, -9 } }
local function safeTarget(part: BasePart, standHeight: number, ignore: { Instance }): CFrame
	local look = flatLook(part)
	local right = look:Cross(Vector3.yAxis)
	local ground = groundOf(part)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	rayParams.IgnoreWater = true
	pcall(function()
		(rayParams :: any).RespectCanCollide = true
	end)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	pcall(function()
		(overlap :: any).RespectCanCollide = true
	end)
	for _, o in PROBE_OFFSETS do
		local probe = ground + right * o[1] + look * o[2]
		local hit = workspace:Raycast(probe + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), rayParams)
		if hit then
			local feet = Vector3.new(probe.X, hit.Position.Y, probe.Z)
			local room = workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 2.9, 0)), Vector3.new(2.2, 4.8, 2.2), overlap)
			local blocked = false
			for _, p in room do
				if p.CanCollide and not p:IsA("Terrain") then
					blocked = true
					break
				end
			end
			if not blocked then
				return standAt(feet, look, standHeight)
			end
		end
	end
	return targetCFrame(part, standHeight)
end

local function aliveParts(character: Model?): (Humanoid?, BasePart?)
	if not character or not character.Parent then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function travel(player: Player, id: string)
	local state = states[player]
	if not state then
		state = { lastRequest = -math.huge, lastTravel = -math.huge, busy = false }
		states[player] = state
	end
	local now = os.clock()
	if state.busy or now - state.lastRequest < cfg.SpamInterval then
		return
	end
	state.lastRequest = now
	-- 전투·범죄·경찰 (GwangalliCombatShared attributes): no quick travel while wanted / arrested / chased / KO
	do
		local wanted = player:GetAttribute("Wanted")
		local ch = player.Character
		if (type(wanted) == "number" and wanted > 0) or player:GetAttribute("Arrested") == true or player:GetAttribute("PoliceChase") == true or (ch and ch:GetAttribute("GwKO") == true) then
			reply(player, false, "수배 중에는 빠른 이동을 할 수 없어요")
			return
		end
	end
	local remaining = cfg.Cooldown - (now - state.lastTravel)
	if remaining > 0 then
		reply(player, false, string.format("%d초 후에 다시 이동할 수 있어요", math.ceil(remaining)))
		return
	end
	local part = byId[id]
	if not part or not part:IsDescendantOf(workspace) then
		reply(player, false, "목적지를 찾을 수 없어요")
		return
	end
	local character = player.Character
	local humanoid, root = aliveParts(character)
	if not humanoid or not root or not character then
		reply(player, false, "캐릭터가 준비되지 않았어요")
		return
	end

	state.busy = true
	state.lastTravel = now
	local function standHeight(): number
		if humanoid and root and humanoid.RigType == Enum.HumanoidRigType.R15 then
			return humanoid.HipHeight + root.Size.Y / 2
		end
		return cfg.LiftStuds -- R6: HipHeight is 0, the root sits 3 studs above the feet
	end
	local target = targetCFrame(part, standHeight())
	-- Make sure the destination is streamed to this client before moving the character there.
	pcall(player.RequestStreamAroundAsync, player, target.Position, STREAM_TIMEOUT)
	state.busy = false

	if player.Parent ~= Players or player.Character ~= character then
		return
	end
	humanoid, root = aliveParts(character)
	if not humanoid or not root or not part:IsDescendantOf(workspace) then
		reply(player, false, "이동이 취소됐어요")
		return
	end
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	local ignore: { Instance } = { part }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local okSafe, safe = pcall(safeTarget, part, standHeight(), ignore)
	target = if okSafe then safe else targetCFrame(part, standHeight())
	-- Move the whole character so that its root (not its model pivot) lands on the target.
	character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	reply(player, true, displayNameOf(part))
end

travelRemote.OnServerEvent:Connect(function(player: Player, action: any, id: any)
	if action ~= "travel" or type(id) ~= "string" or #id == 0 or #id > 200 then
		return
	end
	local ok, err = pcall(travel, player, id)
	if not ok then
		local state = states[player]
		if state then
			state.busy = false
		end
		warn("[GwangalliTravel] " .. tostring(err))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
