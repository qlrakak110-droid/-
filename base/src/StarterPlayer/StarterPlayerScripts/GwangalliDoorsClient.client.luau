-- GwangalliDoorsClient (LocalScript, StarterPlayerScripts)
-- Local sliding animation for the automatic doors. The server script GwangalliDoors owns the
-- state and the collision; this script only moves the leaves on this client, so the motion is
-- smooth at 60 fps and costs no network traffic. Contract (set by the server):
--   door (tag AutoDoor)  Open (boolean), OpenChangedAt (server time of the last change),
--                        optional OpenRadius / CloseDelay / TweenTime (same defaults as the server)
--   leaf (BasePart)      OpenOffset (Vector3, world), ClosedCFrame (CFrame), Collides (boolean)
-- Prediction: when the local character comes within OpenRadius + PREDICT_EXTRA studs, the door
-- starts opening at once and its leaves stop colliding locally. The player no longer waits for a
-- round trip (150-400 ms on mobile data) before the door moves. The door closes only when the
-- server says so and the local character has been out of range for CloseDelay seconds.
-- The server re-enables collision after its own close delay; this script restores the local
-- collision when the local close slide ends, so the two agree.
-- StreamingEnabled-safe: doors and leaves register on stream-in and drop on stream-out.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local cfg = { Radius = 10, CloseDelay = 1.5, TweenTime = 0.6 }
local configModule = ReplicatedStorage:WaitForChild("GwangalliConfig", 30)
if configModule and configModule:IsA("ModuleScript") then
	local ok, Config = pcall(require, configModule)
	if ok and type(Config) == "table" and type(Config.Doors) == "table" then
		cfg = Config.Doors
	end
end

local PREDICT_EXTRA = 4 -- studs beyond the server radius at which the local open starts
local PROXIMITY_INTERVAL = 0.1 -- seconds between local proximity checks

local player = Players.LocalPlayer

type Leaf = { part: BasePart, closed: CFrame, open: CFrame, collides: boolean }
type Door = {
	inst: Instance,
	leaves: { Leaf },
	center: Vector3,
	radius: number,
	closeDelay: number,
	tweenTime: number,
	serverOpen: boolean,
	localSeen: number, -- os.clock() when the local character was last in range
	target: number, -- 0 closed, 1 open
	alpha: number, -- current slide position 0..1
	conns: { RBXScriptConnection },
}

local doors: { [Instance]: Door } = {}
local moving: { [Door]: boolean } = {}

local function numberAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v == v and v > 0 then
		return v
	end
	return default
end

-- smoothstep: symmetric, so reversing mid-slide never jumps
local function ease(a: number): number
	return a * a * (3 - 2 * a)
end

local function place(door: Door)
	local e = ease(door.alpha)
	for _, leaf in door.leaves do
		if leaf.part.Parent then
			leaf.part.CFrame = leaf.closed:Lerp(leaf.open, e)
		end
	end
end

-- Local collision: off while the door is open or moving toward open; back to the authored value
-- once it is fully closed and the server agrees it is closed.
local function applyCollision(door: Door)
	local passable = door.target == 1 or door.alpha > 0 or door.serverOpen
	for _, leaf in door.leaves do
		if leaf.collides and leaf.part.Parent then
			local want = not passable
			if leaf.part.CanCollide ~= want then
				leaf.part.CanCollide = want
			end
		end
	end
end

local function recenter(door: Door)
	if #door.leaves == 0 then
		return
	end
	local sum = Vector3.zero
	for _, leaf in door.leaves do
		sum += leaf.closed.Position
	end
	door.center = sum / #door.leaves
end

local function wantOpen(door: Door): boolean
	return door.serverOpen or os.clock() - door.localSeen < door.closeDelay
end

local function retarget(door: Door)
	local target = if wantOpen(door) then 1 else 0
	if target ~= door.target then
		door.target = target
		applyCollision(door)
	end
	if door.alpha ~= door.target then
		moving[door] = true
	end
end

local function addLeaf(door: Door, part: BasePart)
	for _, leaf in door.leaves do
		if leaf.part == part then
			return
		end
	end
	local offset = part:GetAttribute("OpenOffset")
	if typeof(offset) ~= "Vector3" then
		return
	end
	local closed = part:GetAttribute("ClosedCFrame")
	if typeof(closed) ~= "CFrame" then
		closed = part.CFrame -- the server never moves the leaves, so this is the closed pose
	end
	local collides = part:GetAttribute("Collides")
	if type(collides) ~= "boolean" then
		collides = part.CanCollide
	end
	local leaf: Leaf = { part = part, closed = closed :: CFrame, open = (closed :: CFrame) + offset, collides = collides :: boolean }
	table.insert(door.leaves, leaf)
	recenter(door)
	if door.alpha > 0 then -- a closed leaf already sits at its closed pose (the server never moves it)
		part.CFrame = leaf.closed:Lerp(leaf.open, ease(door.alpha))
	end
	applyCollision(door)
end

local function unregister(inst: Instance)
	local door = doors[inst]
	if not door then
		return
	end
	doors[inst] = nil
	moving[door] = nil
	for _, c in door.conns do
		c:Disconnect()
	end
	-- still in the world (tag removed, not streamed out): leave it closed and solid
	if inst:IsDescendantOf(workspace) then
		for _, leaf in door.leaves do
			if leaf.part.Parent then
				leaf.part.CFrame = leaf.closed
				leaf.part.CanCollide = leaf.collides
			end
		end
	end
end

local function register(inst: Instance)
	if doors[inst] or not inst:IsDescendantOf(workspace) then
		return
	end
	local tweenTime = numberAttr(inst, "TweenTime", cfg.TweenTime)
	local serverOpen = inst:GetAttribute("Open") == true
	-- streamed in mid-slide: resume from where the other clients are
	local alpha = if serverOpen then 1 else 0
	local changedAt = inst:GetAttribute("OpenChangedAt")
	if type(changedAt) == "number" then
		local progress = math.clamp((workspace:GetServerTimeNow() - changedAt) / tweenTime, 0, 1)
		alpha = if serverOpen then progress else 1 - progress
	end
	local door: Door = {
		inst = inst,
		leaves = {},
		center = Vector3.zero,
		radius = numberAttr(inst, "OpenRadius", cfg.Radius),
		closeDelay = numberAttr(inst, "CloseDelay", cfg.CloseDelay),
		tweenTime = tweenTime,
		serverOpen = serverOpen,
		localSeen = -math.huge,
		target = alpha, -- set properly by retarget below
		alpha = alpha,
		conns = {},
	}
	doors[inst] = door
	if inst:IsA("BasePart") then
		addLeaf(door, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			addLeaf(door, d)
		end
	end
	table.insert(door.conns, inst.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			addLeaf(door, d)
		end
	end))
	table.insert(door.conns, inst.DescendantRemoving:Connect(function(d)
		for i = #door.leaves, 1, -1 do
			if door.leaves[i].part == d then
				table.remove(door.leaves, i)
			end
		end
	end))
	table.insert(door.conns, inst:GetAttributeChangedSignal("Open"):Connect(function()
		door.serverOpen = inst:GetAttribute("Open") == true
		retarget(door)
		applyCollision(door)
	end))
	door.target = -1 -- force retarget to apply collision once
	retarget(door)
end

local function safeRegister(inst: Instance)
	local ok, err = pcall(register, inst)
	if not ok then
		warn("[GwangalliDoorsClient] " .. tostring(err))
	end
end

CollectionService:GetInstanceAddedSignal("AutoDoor"):Connect(safeRegister)
CollectionService:GetInstanceRemovedSignal("AutoDoor"):Connect(unregister)
for _, inst in CollectionService:GetTagged("AutoDoor") do
	safeRegister(inst)
end

-- Local proximity (10 Hz) --------------------------------------------------------------------
local function proximity()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local pos = if root and root:IsA("BasePart") then root.Position else nil
	local now = os.clock()
	for _, door in doors do
		if pos and #door.leaves > 0 then
			local r = door.radius + PREDICT_EXTRA
			local d = pos - door.center
			local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
			if d2 <= r * r then
				door.localSeen = now
			elseif d2 > (r + 40) * (r + 40) and door.target == 0 and door.alpha == 0 and not door.serverOpen then
				continue -- far, closed and at rest: nothing can change until the server opens it
			end
		end
		retarget(door)
		-- the server may have written CanCollide = true (its close timer) while this client
		-- already predicts the next opening
		if door.target == 1 then
			applyCollision(door)
		end
	end
end

-- Animation (only doors that are sliding) ------------------------------------------------------
local sinceProximity = 0
RunService.Heartbeat:Connect(function(dt: number)
	sinceProximity += dt
	if sinceProximity >= PROXIMITY_INTERVAL then
		sinceProximity = 0
		local ok, err = pcall(proximity)
		if not ok then
			warn("[GwangalliDoorsClient] " .. tostring(err))
		end
	end
	for door in moving do
		local step = dt / door.tweenTime
		if door.alpha < door.target then
			door.alpha = math.min(door.target, door.alpha + step)
		else
			door.alpha = math.max(door.target, door.alpha - step)
		end
		local ok, err = pcall(place, door)
		if not ok then
			warn("[GwangalliDoorsClient] " .. tostring(err))
		end
		if door.alpha == door.target then
			moving[door] = nil
			applyCollision(door)
		end
	end
end)
