-- GwangalliSignals (server)
-- Assigns a direction phase (attribute SignalPhase = 0 | 1) to every TrafficSignal / PedSignal
-- housing so all clients cycle the two directions of an intersection the same way even though
-- StreamingEnabled gives each client a different subset of housings.
--
-- Rule per Group: the reference axis is the facing axis of the vehicle housing with the smallest
-- (X, Z) position (deterministic). Housings whose facing axis is within 45 degrees of it
-- (either direction) get phase 0, the perpendicular ones phase 1. Pedestrian heads face the
-- people crossing, so their axis runs parallel to the traffic that is allowed to move while they
-- walk: they share that traffic's phase (walk while it is green).
--
-- A housing that already has attribute Phase (0/1, set by a builder) keeps it.
--
-- Network / mobile: this is the ONLY thing the server does for traffic lights. SignalPhase is
-- written once per housing (only when it differs), so it travels with the housing when it streams
-- in and costs nothing afterwards. The cycle itself is a pure function of
-- workspace:GetServerTimeNow() and the Group name (GwangalliShared.vehicleState / pedState, offset
-- = hash of the group), and every lamp colour change happens on the clients
-- (GwangalliWorld/Traffic). Any future server-side traffic AI can query the same functions.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliShared", 30)
if not sharedModule then
	warn("[GwangalliSignals] GwangalliShared missing")
	return
end
local Shared = require(sharedModule)
local PHASE_ATTR = Shared.Attr.SignalPhase

local TAGS = { "TrafficSignal", "PedSignal" }
local COS45 = math.cos(math.rad(45))

local function flatAxis(part: BasePart): Vector3?
	local look = part.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

local function groupOf(inst: Instance): string
	local g = inst:GetAttribute("Group")
	if type(g) == "string" and g ~= "" then
		return g
	end
	return "default"
end

local function isBefore(a: BasePart, b: BasePart): boolean
	local pa, pb = a.Position, b.Position
	if math.abs(pa.X - pb.X) > 1e-3 then
		return pa.X < pb.X
	end
	return pa.Z < pb.Z
end

local function assign(part: BasePart, refAxis: Vector3)
	local phase = 0
	local override = part:GetAttribute("Phase")
	if override == 0 or override == 1 then
		phase = override
	else
		local axis = flatAxis(part)
		if axis and math.abs(axis:Dot(refAxis)) < COS45 then
			phase = 1
		end
	end
	if part:GetAttribute(PHASE_ATTR) ~= phase then
		part:SetAttribute(PHASE_ATTR, phase)
	end
end

local function assignGroup(vehicles: { BasePart }, peds: { BasePart })
	local pool = if #vehicles > 0 then vehicles else peds
	local ref: BasePart? = nil
	for _, part in pool do
		if flatAxis(part) and (ref == nil or isBefore(part, ref)) then
			ref = part
		end
	end
	if not ref then
		return
	end
	local refAxis = flatAxis(ref) :: Vector3
	for _, part in vehicles do
		assign(part, refAxis)
	end
	for _, part in peds do
		assign(part, refAxis)
	end
end

-- Debounced recompute of the dirty groups (hundreds of housings arrive in the same frame at
-- start-up). One pass buckets every housing by group, so the cost is O(housings) per flush
-- instead of O(groups x housings).
local dirty: { [string]: boolean } = {}
local flushQueued = false

local function flush()
	flushQueued = false
	local groups = dirty
	dirty = {}
	local buckets: { [string]: { vehicles: { BasePart }, peds: { BasePart } } } = {}
	for _, tag in TAGS do
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
				local group = groupOf(inst)
				if groups[group] then
					local b = buckets[group]
					if not b then
						b = { vehicles = {}, peds = {} }
						buckets[group] = b
					end
					table.insert(if tag == "TrafficSignal" then b.vehicles else b.peds, inst)
				end
			end
		end
	end
	for group, b in buckets do
		local ok, err = pcall(assignGroup, b.vehicles, b.peds)
		if not ok then
			warn("[GwangalliSignals] group " .. group .. ": " .. tostring(err))
		end
	end
end

local function schedule(group: string)
	dirty[group] = true
	if not flushQueued then
		flushQueued = true
		task.defer(flush)
	end
end

for _, tag in TAGS do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		schedule(groupOf(inst))
	end)
	for _, inst in CollectionService:GetTagged(tag) do
		schedule(groupOf(inst))
	end
end
