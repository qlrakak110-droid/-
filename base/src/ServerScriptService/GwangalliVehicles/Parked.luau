-- GwangalliVehicles/Parked: parked NPC cars on the map that a player may take (GTA feel).
-- Rule: only UNLOCKED cars can be entered — 30 % of the drivable parked cars (sedan, G80, Ray,
-- Tucson, Carnival, Porter), chosen by a stable hash of the car's position so every server agrees.
-- Moving traffic (any ancestor named "TrafficVehicles"), taxis, police cars, ambulances, buses,
-- scooters and cars with attribute NoDrive = true are never enterable. Unlocked cars get their
-- door prompts now (read-only analysis); the physics rig is built only when someone gets in.
-- Dev switch: workspace attribute GwangalliDriveUnlockAll = true unlocks every drivable parked car.

local Parked = {}

local VS: any = nil
local Analyze: any = nil
local Cars: any = nil

function Parked.init(shared: any, analyze: any, cars: any)
	VS, Analyze, Cars = shared, analyze, cars
end

local function skip(m: Instance): boolean
	local node = m.Parent
	while node and node ~= workspace do
		if node.Name == "TrafficVehicles" or node.Name == "GwangalliPlayerCars" or node:GetAttribute("VehicleKind") ~= nil then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Stable 0..1 hash of a position.
function Parked.hash(p: Vector3): number
	local P = 1000003
	local x = math.floor(p.X * 10 + 0.5) % P
	local z = math.floor(p.Z * 10 + 0.5) % P
	local h = (x * 7919 + z * 104729 + 17) % P
	h = (h * h + 12345) % P
	h = (h * 48271 + 11) % P
	return h / P
end

local function refPos(m: Model): Vector3?
	local under = m:FindFirstChild("Underbody")
	if under and under:IsA("BasePart") then
		return under.CFrame.Position
	end
	local p = m:FindFirstChildWhichIsA("BasePart", true)
	return p and p.CFrame.Position
end

function Parked.eligible(m: Model): boolean
	local kind = m:GetAttribute(VS.Attr.Kind)
	if type(kind) ~= "string" or not VS.Drivable[kind] then
		return false
	end
	if m:GetAttribute(VS.Attr.NoDrive) or m:GetAttribute(VS.Attr.Rigged) then
		return false
	end
	return not skip(m)
end

function Parked.unlocked(m: Model): boolean
	if workspace:GetAttribute("GwangalliDriveUnlockAll") == true then
		return true
	end
	local p = refPos(m)
	return p ~= nil and Parked.hash(p) < VS.Limits.UnlockedShare
end

-- Prepares one parked car: returns true when it became an enterable candidate.
function Parked.prepare(m: Model): boolean
	if Cars.candidates[m] or Cars.recs[m] then
		return false
	end
	if not Parked.eligible(m) or not Parked.unlocked(m) then
		return false
	end
	local info = Analyze.run(m)
	if not info then
		return false
	end
	Cars.candidates[m] = { model = m, info = info }
	m:SetAttribute(VS.Attr.Unlocked, true)
	m:SetAttribute(VS.Attr.Label, VS.spec(m:GetAttribute(VS.Attr.Kind)).label)
	Cars.addPrompts(m, info.frame, info.doorDriver, info.doorPassenger, VS.spec(m:GetAttribute(VS.Attr.Kind)).label)
	return true
end

-- Scans the map (yields between batches). Returns counts.
function Parked.scan(root: Instance?): { [string]: number }
	local stats = { seen = 0, eligible = 0, unlocked = 0 }
	local r = root or workspace:FindFirstChild("Gwangalli") or workspace
	local n = 0
	for _, d in r:GetDescendants() do
		n += 1
		if n % 3000 == 0 then
			task.wait()
		end
		if d:IsA("Model") and d:GetAttribute("VehicleKind") ~= nil then
			stats.seen += 1
			if Parked.eligible(d) then
				stats.eligible += 1
				if Parked.prepare(d) then
					stats.unlocked += 1
					if stats.unlocked % 8 == 0 then
						task.wait()
					end
				end
			end
		end
	end
	return stats
end

return Parked
