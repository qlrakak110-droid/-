-- GwangalliVehicles/Cars: runtime of every rigged car (server authoritative).
--   * registry of rigged cars (called player cars + parked NPC cars someone got into)
--   * ProximityPrompts at the doors ("운전하기" F / "타기" G), enter / exit, seat bookkeeping
--   * network ownership to the driver; wake (unanchor) / settle / sleep (anchor) cycle
--   * driver state (lamps, brake lights, horn), flip-back, sea (eject + sink), sanity checks,
--     streaming hints for fast drivers, despawn / restore rules, cleanup on leave
--   * seating: Seat:Sit (the engine's SeatWeld + Occupant) first; when the engine refuses or lacks it
--     (a humanoid mid-state change, test engines) the same effect is produced by hand: a "SeatWeld"
--     Weld seat -> HumanoidRootPart, Humanoid.Sit, and the occupant bookkeeping (rec.manual) so the
--     driver / passenger events fire either way. Cars.occupants() counts both kinds.
--   * owned cars (rec.ownerOnly, from Spawn.callOwned / spawnJob): only rec.owner may take the driver's
--     seat; rec.label (model + plate) names the door prompts; rec.idleLimit overrides the idle despawn

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Cars = {}

local VS: any = nil
local Rig: any = nil
local Analyze: any = nil
local remote: RemoteEvent = nil :: any

local recs: { [Model]: any } = {}
local driving: { [Player]: any } = {}
local riding: { [Player]: any } = {} -- passengers
local called: { [Player]: any } = {}
local jobCars: { [Player]: any } = {} -- SpawnJobVehicle (one per player, besides the called car)
local candidates: { [Model]: any } = {} -- parked, unlocked, not rigged yet
local buckets: { [Player]: { t: number, n: number } } = {}

Cars.recs = recs
Cars.driving = driving
Cars.called = called
Cars.jobCars = jobCars
Cars.candidates = candidates

local charParams = RaycastParams.new()
charParams.FilterType = Enum.RaycastFilterType.Exclude
charParams.RespectCanCollide = true

local function now(): number
	return os.clock()
end

local function toast(player: Player, title: string, body: string?, kind: string?)
	if player.Parent == Players then
		remote:FireClient(player, { op = "toast", title = title, body = body, kind = kind or "info" })
	end
end
Cars.toast = toast

local function characters(): { Instance }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 and hrp and hrp:IsA("BasePart") then
		return hum, hrp
	end
	return nil, nil
end

-- Rate limit for client events (token bucket).
function Cars.allow(player: Player, cost: number?): boolean
	local b = buckets[player]
	local t = now()
	local rate = VS.Limits.EventRate
	if not b then
		b = { t = t, n = rate }
		buckets[player] = b
	end
	b.n = math.min(rate * 1.5, b.n + (t - b.t) * rate)
	b.t = t
	local c = cost or 1
	if b.n < c then
		return false
	end
	b.n -= c
	return true
end

function Cars.awakeCount(): number
	local n = 0
	for _, rec in recs do
		if not rec.sleeping then
			n += 1
		end
	end
	return n
end

function Cars.init(shared: any, rig: any, analyze: any, ev: RemoteEvent)
	VS, Rig, Analyze, remote = shared, rig, analyze, ev
end

---------------------------------------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------------------------------------
local function promptPart(model: Model): BasePart?
	local base = model:FindFirstChild(VS.Parts.Body)
	if base and base:IsA("BasePart") then
		return base
	end
	local under = model:FindFirstChild("Underbody")
	if under and under:IsA("BasePart") then
		return under
	end
	-- a root-level part (LOD sub-models are replaced when the car is rigged)
	local best: BasePart? = nil
	local bestV = -1
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") then
			local v = c.Size.X * c.Size.Y * c.Size.Z
			if v > bestV then
				best, bestV = c, v
			end
		end
	end
	return best
end

local function clearPrompts(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and string.sub(d.Name, 1, #VS.Parts.Prompt) == VS.Parts.Prompt then
			d:Destroy()
		end
	end
end

-- origin: a CFrame on the car (the car frame for a parked car, DriveBase for a rigged one);
-- doorDriver / doorPassenger: door points in that space.
function Cars.addPrompts(model: Model, origin: CFrame, doorDriver: Vector3, doorPassenger: Vector3, label: string)
	clearPrompts(model)
	local part = promptPart(model)
	if not part then
		return
	end
	local function one(role: string, pos: Vector3)
		local att = Instance.new("Attachment")
		att.Name = VS.Parts.Prompt .. (if role == "driver" then "Driver" else "Passenger")
		att.CFrame = part.CFrame:ToObjectSpace(origin * CFrame.new(pos))
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "DrivePrompt"
		pp.ActionText = if role == "driver" then "운전하기" else "타기"
		pp.ObjectText = label
		pp.KeyboardKeyCode = if role == "driver" then Enum.KeyCode.F else Enum.KeyCode.G
		pp.GamepadKeyCode = if role == "driver" then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
		pp.HoldDuration = 0
		pp.MaxActivationDistance = 8
		pp.RequiresLineOfSight = false
		pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		pp:SetAttribute("GwangalliDrive", role)
		pp.Parent = att
		att.Parent = part
	end
	one("driver", doorDriver)
	one("passenger", doorPassenger)
end

local function playerOfHumanoid(h: Humanoid?): Player?
	if not h then
		return nil
	end
	return Players:GetPlayerFromCharacter(h.Parent)
end

-- The player on a seat: the engine's Occupant, else our manual seating record.
local function occupantOf(rec: any, seat: Seat): Player?
	local p = playerOfHumanoid(seat.Occupant)
	if p then
		return p
	end
	local manual = rec.manual and rec.manual[seat]
	if manual and manual.Parent == Players then
		return manual
	end
	return nil
end

local function setPromptsEnabled(rec: any)
	local driverFree = rec.seat and occupantOf(rec, rec.seat) == nil
	local passengerFree = false
	for _, s in rec.passengers do
		if occupantOf(rec, s) == nil then
			passengerFree = true
		end
	end
	for _, d in rec.model:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("GwangalliDrive") then
			local role = d:GetAttribute("GwangalliDrive")
			d.Enabled = not rec.sunk and (if role == "driver" then driverFree else passengerFree)
		end
	end
end
Cars.setPromptsEnabled = setPromptsEnabled

---------------------------------------------------------------------------------------------------
-- Lamps / horn / light state
---------------------------------------------------------------------------------------------------
local TAIL_DIM = Color3.fromRGB(150, 16, 20)
local TAIL_BRAKE = Color3.fromRGB(255, 34, 34)
local HEAD_ON = Color3.fromRGB(255, 250, 236)

local function applyState(rec: any, bits: number)
	local B = VS.Bits
	local brake = bit32.btest(bits, B.BRAKE) or bit32.btest(bits, B.HANDBRAKE)
	local lights = bit32.btest(bits, B.LIGHTS)
	local key = (if brake then 1 else 0) + (if lights then 2 else 0)
	if key ~= rec.lampKey then
		rec.lampKey = key
		for _, l in rec.lamps.head do
			if lights then
				l.part.Material = Enum.Material.Neon
				l.part.Color = HEAD_ON
			else
				l.part.Material = l.material
				l.part.Color = l.color
			end
		end
		for _, l in rec.lamps.tail do
			if brake then
				l.part.Material = Enum.Material.Neon
				l.part.Color = TAIL_BRAKE
			elseif lights then
				l.part.Material = Enum.Material.Neon
				l.part.Color = TAIL_DIM
			else
				l.part.Material = l.material
				l.part.Color = l.color
			end
		end
		if rec.light then
			rec.light.Enabled = lights
		end
	end
	local horn = bit32.btest(bits, B.HORN)
	if rec.horn and rec.horn.Playing ~= horn then
		rec.horn.Playing = horn
	end
	if rec.model:GetAttribute(VS.Attr.State) ~= bits then
		rec.model:SetAttribute(VS.Attr.State, bits)
	end
	rec.state = bits
end
Cars.applyState = applyState

---------------------------------------------------------------------------------------------------
-- Wake / sleep
---------------------------------------------------------------------------------------------------
local function zeroMovers(rec: any)
	rec.vf.Force = Vector3.zero
	rec.tq.Torque = Vector3.zero
end

function Cars.wake(rec: any)
	if not rec.sleeping then
		return
	end
	rec.sleeping = false
	rec.settled = 0
	rec.wokeAt = now()
	rec.base.Anchored = false
	rec.model:SetAttribute(VS.Attr.Sleeping, false)
	if rec.engine then
		rec.engine.Playing = true
	end
end

function Cars.sleep(rec: any)
	zeroMovers(rec)
	pcall(function()
		rec.base.AssemblyLinearVelocity = Vector3.zero
		rec.base.AssemblyAngularVelocity = Vector3.zero
	end)
	rec.base.Anchored = true
	rec.sleeping = true
	rec.model:SetAttribute(VS.Attr.Sleeping, true)
	if rec.engine then
		rec.engine.Playing = false
	end
end

local function controllerOf(rec: any): any
	if not rec.controller then
		rec.controller = VS.Controller.new(rec.rig, rec.spec)
	end
	return rec.controller
end

---------------------------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------------------------
local onSeat: (rec: any, seat: Seat) -> () = nil :: any

function Cars.register(rec: any, extra: { [string]: any }?)
	for k, v in extra or {} do
		rec[k] = v
	end
	rec.sleeping = true
	rec.state = 0
	rec.lampKey = -1
	rec.lastUsed = now()
	rec.occupants = {}
	rec.manual = {}
	recs[rec.model] = rec
	candidates[rec.model] = nil
	local conns = {}
	for _, seat in rec.seats do
		table.insert(conns, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onSeat(rec, seat)
		end))
	end
	table.insert(conns, rec.model.AncestryChanged:Connect(function()
		if not rec.model:IsDescendantOf(workspace) and rec.model.Parent == nil then
			Cars.forget(rec)
		end
	end))
	rec.conns = conns
	Cars.addPrompts(rec.model, rec.base.CFrame, rec.doors.driver, rec.doors.passenger, rec.label or rec.spec.label)
	setPromptsEnabled(rec)
	applyState(rec, 0)
	return rec
end

function Cars.forget(rec: any)
	if recs[rec.model] ~= rec then
		return
	end
	recs[rec.model] = nil
	for _, c in rec.conns or {} do
		c:Disconnect()
	end
	for p, r in driving do
		if r == rec then
			driving[p] = nil
		end
	end
	for p, r in riding do
		if r == rec then
			riding[p] = nil
		end
	end
	for p, r in called do
		if r == rec then
			called[p] = nil
		end
	end
	for p, r in jobCars do
		if r == rec then
			jobCars[p] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Seats
---------------------------------------------------------------------------------------------------
local function setDriver(rec: any, player: Player?)
	local old = rec.driver
	if old == player then
		return
	end
	rec.driver = player
	if old then
		driving[old] = nil
		if old.Parent == Players then
			remote:FireClient(old, { op = "exit", car = rec.model })
		end
	end
	if player then
		driving[player] = rec
		rec.model:SetAttribute(VS.Attr.Driver, player.UserId)
		Cars.wake(rec)
		local ok, err = pcall(function()
			rec.base:SetNetworkOwner(player)
		end)
		if not ok then
			warn("[GwangalliVehicles] SetNetworkOwner: " .. tostring(err))
		end
		rec.strikes = 0
		remote:FireClient(player, { op = "enter", car = rec.model, role = "driver", seat = rec.seat })
	else
		rec.model:SetAttribute(VS.Attr.Driver, 0)
		applyState(rec, 0)
		zeroMovers(rec)
		if not rec.sleeping then
			pcall(function()
				rec.base:SetNetworkOwner(nil)
			end)
		end
		rec.settled = 0
		rec.lastUsed = now()
	end
end

onSeat = function(rec: any, seat: Seat)
	local occ = seat.Occupant
	local player = playerOfHumanoid(occ)
	if player and rec.manual[seat] == player then
		rec.manual[seat] = nil -- the engine caught up with a manual seating
	end
	if occ == nil and rec.manual[seat] then
		player = rec.manual[seat] -- still seated by hand
	end
	local prev = rec.occupants[seat]
	rec.occupants[seat] = player
	if occ == nil and not rec.manual[seat] then
		seat.Disabled = true
	end
	if seat == rec.seat then
		setDriver(rec, player)
	else
		if prev and prev ~= player then
			riding[prev] = nil
			if prev.Parent == Players then
				remote:FireClient(prev, { op = "exit", car = rec.model })
			end
		end
		if player then
			riding[player] = rec
			remote:FireClient(player, { op = "enter", car = rec.model, role = "passenger", seat = seat })
		end
	end
	rec.lastUsed = now()
	setPromptsEnabled(rec)
end

-- Occupants of a car (players), engine-seated or manually seated.
function Cars.occupants(rec: any): { Player }
	local out = {}
	for _, seat in rec.seats do
		local p = occupantOf(rec, seat)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- Manual seating (Seat:Sit refused / unavailable): weld like the engine's SeatWeld and run the
-- same occupant bookkeeping. The weld is named "SeatWeld" so every exit path finds it.
local function manualSit(rec: any, seat: Seat, player: Player, hum: Humanoid, hrp: BasePart): boolean
	local char = player.Character
	if not char then
		return false
	end
	local old = seat:FindFirstChild("SeatWeld")
	if old then
		old:Destroy()
	end
	local lift = seat.Size.Y / 2 + hrp.Size.Y / 2 + 0.45
	local target = seat.CFrame * CFrame.new(0, lift, 0)
	local ok = pcall(function()
		char:PivotTo(target * hrp.CFrame:ToObjectSpace(char:GetPivot()))
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)
	if not ok then
		return false
	end
	local weld = Instance.new("Weld")
	weld.Name = "SeatWeld"
	weld.Part0 = seat
	weld.Part1 = hrp
	weld.C0 = CFrame.new(0, lift, 0)
	weld.C1 = CFrame.new()
	weld.Parent = seat
	pcall(function()
		hum.Sit = true
	end)
	rec.manual[seat] = player
	onSeat(rec, seat)
	return true
end

-- Clears a manual seating record (exit / leave); the engine's Occupant path needs nothing here.
local function clearManual(rec: any, player: Player)
	local changed = false
	for seat, p in rec.manual do
		if p == player then
			rec.manual[seat] = nil
			local w = seat:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
			changed = true
			onSeat(rec, seat)
		end
	end
	return changed
end

---------------------------------------------------------------------------------------------------
-- Enter / exit
---------------------------------------------------------------------------------------------------
local function rigCandidate(model: Model): (any?, string?)
	local cand = candidates[model]
	local rec, why = Rig.rig(model)
	if not rec then
		return nil, why
	end
	return Cars.register(rec, { parked = cand ~= nil, origin = rec.base.CFrame }), nil
end

function Cars.enter(player: Player, model: Model, role: string): (boolean, string?)
	local hum, hrp = humanoidOf(player)
	if not hum or not hrp then
		return false, "캐릭터가 없어요"
	end
	if hum.SeatPart then
		return false, "이미 앉아 있어요"
	end
	if not model:IsDescendantOf(workspace) then
		return false, "차를 찾을 수 없어요"
	end
	local rec = recs[model]
	if not rec then
		if not candidates[model] and not model:GetAttribute(VS.Attr.Unlocked) then
			return false, "문이 잠겨 있어요"
		end
		local r, why = rigCandidate(model)
		if not r then
			warn("[GwangalliVehicles] rig failed for " .. model:GetFullName() .. ": " .. tostring(why))
			return false, "이 차는 탈 수 없어요"
		end
		rec = r
	end
	if rec.sunk then
		return false, "물에 빠진 차예요"
	end
	-- distance (the prompt already limits it; this guards remote-driven entries)
	if (rec.base.Position - hrp.Position).Magnitude > math.max(20, rec.rig.L) then
		return false, "차에서 너무 멀어요"
	end
	local seat: Seat? = nil
	if role == "driver" then
		if rec.seat.Occupant then
			return false, "운전석에 누가 있어요"
		end
		-- owned / job cars: only the owner drives (friends may ride along)
		if rec.ownerOnly and rec.owner and rec.owner ~= player then
			return false, "차 주인만 운전할 수 있어요 · 조수석은 '타기'"
		end
		if rec.sleeping and Cars.awakeCount() >= VS.Limits.MaxActive then
			return false, "지금은 달리는 차가 너무 많아요. 잠시 후 다시 해 보세요"
		end
		seat = rec.seat
	else
		for _, s in rec.passengers do
			if s.Occupant == nil then
				seat = s
				break
			end
		end
		if not seat then
			return false, "빈자리가 없어요"
		end
	end
	local s = seat :: Seat
	s.Disabled = false
	local ok, err = pcall(function()
		s:Sit(hum)
	end)
	if not ok then
		-- the engine refused (or has no Seat:Sit): seat by hand, same outcome for everyone
		if not manualSit(rec, s, player, hum, hrp) then
			s.Disabled = true
			warn("[GwangalliVehicles] Sit failed: " .. tostring(err))
			return false, "자리에 앉지 못했어요"
		end
	end
	task.delay(1.5, function()
		if s.Occupant == nil and not rec.manual[s] then
			s.Disabled = true
		end
	end)
	return true, nil
end

-- A free standing spot next to the car (driver side first).
local function exitSpot(rec: any, preferRight: boolean): CFrame
	local cf = rec.base.CFrame
	local rig = rec.rig
	local halfW, halfL = rig.W / 2, rig.L / 2
	local flat = CFrame.lookAt(cf.Position, cf.Position + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z))
	local side = if preferRight then 1 else -1
	local cands = {
		Vector3.new(side * (halfW + 2.2), 0, -1),
		Vector3.new(-side * (halfW + 2.2), 0, -1),
		Vector3.new(0, 0, halfL + 3),
		Vector3.new(0, 0, -halfL - 3),
		Vector3.new(side * (halfW + 3.5), 0, 3),
	}
	local exclude = characters()
	table.insert(exclude, rec.model)
	charParams.FilterDescendantsInstances = exclude
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	overlap.RespectCanCollide = true
	for _, off in cands do
		local p = flat:PointToWorldSpace(off)
		local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), charParams)
		if hit and hit.Material ~= Enum.Material.Water then
			local stand = hit.Position + Vector3.new(0, 3.1, 0)
			local parts = workspace:GetPartBoundsInBox(CFrame.new(stand + Vector3.new(0, 0.4, 0)), Vector3.new(2, 4.4, 2), overlap)
			if #parts == 0 then
				return CFrame.lookAt(stand, stand + flat.LookVector)
			end
		end
	end
	-- roof as the last resort
	local top = cf.Position + Vector3.new(0, rig.H + 3, 0)
	return CFrame.lookAt(top, top + flat.LookVector)
end

function Cars.exit(player: Player, why: string?): boolean
	local hum, hrp = humanoidOf(player)
	local rec = driving[player] or riding[player]
	if not hum or not rec then
		return false
	end
	local seat = hum.SeatPart
	if not seat then
		for s2, p2 in rec.manual do
			if p2 == player then
				seat = s2
			end
		end
	end
	local preferRight = false
	if seat and seat.Parent == rec.model then
		local l = rec.base.CFrame:PointToObjectSpace(seat.Position)
		preferRight = l.X > 0
	end
	local target: CFrame
	if why == "water" then
		local p = rec.base.Position
		target = CFrame.new(p.X, VS.WATER_Y + 2.5, p.Z)
	else
		target = exitSpot(rec, preferRight)
	end
	if seat then
		local w = seat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
	end
	hum.Sit = false
	clearManual(rec, player)
	if player.Character and hrp then
		player.Character:PivotTo(target)
		pcall(function()
			hrp.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	-- the Occupant signal clears driver / passenger state; make sure even if it is late
	task.defer(function()
		if seat and seat.Occupant == hum then
			hum.Sit = false
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------
-- Driver actions
---------------------------------------------------------------------------------------------------
function Cars.setState(player: Player, bits: any)
	local rec = driving[player]
	if not rec or type(bits) ~= "number" or bits ~= bits then
		return
	end
	bits = math.clamp(math.floor(bits), 0, 255)
	applyState(rec, bits)
end

function Cars.flip(player: Player): boolean
	local rec = driving[player]
	if not rec then
		return false
	end
	local base = rec.base
	local cf = base.CFrame
	local speed = base.AssemblyLinearVelocity.Magnitude
	if speed > 18 then
		return false
	end
	local tilted = cf.UpVector.Y < 0.8
	if not tilted then
		return false
	end
	Cars.upright(rec)
	return true
end

function Cars.upright(rec: any)
	local cf = rec.base.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
	end
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	local p = cf.Position + Vector3.new(0, 2.5 + rec.rig.H * 0.3, 0)
	rec.model:PivotTo(CFrame.lookAt(p, p + look.Unit))
	pcall(function()
		rec.base.AssemblyLinearVelocity = Vector3.zero
		rec.base.AssemblyAngularVelocity = Vector3.zero
	end)
	rec.flippedAt = nil
end

---------------------------------------------------------------------------------------------------
-- Despawn / restore / sink
---------------------------------------------------------------------------------------------------
local function ejectAll(rec: any, why: string?)
	for _, p in Cars.occupants(rec) do
		Cars.exit(p, why)
	end
end

function Cars.despawn(rec: any, reason: string?)
	ejectAll(rec)
	local owner = rec.owner
	Cars.forget(rec)
	if owner and owner.Parent == Players and reason then
		toast(owner, "🚗 차를 돌려보냈어요", reason)
	end
	task.defer(function()
		rec.model:Destroy()
	end)
end

function Cars.restore(rec: any)
	ejectAll(rec)
	if not rec.sleeping then
		Cars.sleep(rec)
	end
	rec.sunk = false
	rec.model:SetAttribute(VS.Attr.Sunk, nil)
	if rec.origin then
		rec.model:PivotTo(rec.origin)
	end
	applyState(rec, 0)
	setPromptsEnabled(rec)
	rec.lastUsed = now()
end

function Cars.sink(rec: any)
	if rec.sunk then
		return
	end
	rec.sunk = true
	rec.model:SetAttribute(VS.Attr.Sunk, true)
	for _, p in Cars.occupants(rec) do
		toast(p, "🌊 차가 바다에 빠졌어요", "헤엄쳐서 나오세요")
		Cars.exit(p, "water")
	end
	zeroMovers(rec)
	setPromptsEnabled(rec)
	task.delay(2.5, function()
		if recs[rec.model] ~= rec then
			return
		end
		if rec.owner then
			Cars.despawn(rec, "바다에 빠진 차는 견인됐어요")
		else
			Cars.restore(rec)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Server step
---------------------------------------------------------------------------------------------------
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.IgnoreWater = false

local function inWater(rec: any): boolean
	local p = rec.base.Position
	if p.Y < VS.WATER_Y - 12 then
		return true
	end
	if p.Y > VS.WATER_Y + 3 then
		return false
	end
	local ex = characters()
	table.insert(ex, rec.model)
	waterParams.FilterDescendantsInstances = ex
	local hit = workspace:Raycast(p + Vector3.new(0, 8, 0), Vector3.new(0, -14, 0), waterParams)
	if hit and hit.Material == Enum.Material.Water and hit.Position.Y > p.Y - rec.rAvg + 0.8 then
		return true
	end
	return false
end

local settleParams = RaycastParams.new()
settleParams.FilterType = Enum.RaycastFilterType.Exclude
settleParams.RespectCanCollide = true
settleParams.IgnoreWater = true
-- park = true: the controller's static hold (stops within the frame budget, never engages the GTA
-- brake-to-reverse latch, holds on slopes) -- not brake = 1, which would reverse once slow.
local SETTLE_INPUT = { park = true, steer = 0 }

-- Heartbeat: driverless awake cars (server owned) brake to a stop and go to sleep.
function Cars.physicsStep(dt: number)
	local ex: { Instance }? = nil
	for _, rec in recs do
		if rec.sleeping or rec.driver or rec.sunk then
			continue
		end
		if not ex then
			ex = characters()
		end
		local list = table.clone(ex :: { Instance })
		table.insert(list, rec.model)
		settleParams.FilterDescendantsInstances = list
		local st = controllerOf(rec)
		VS.Controller.stepRoblox(st, dt, SETTLE_INPUT, rec.base, rec.vf, rec.tq, settleParams)
		local v = rec.base.AssemblyLinearVelocity.Magnitude
		local w = rec.base.AssemblyAngularVelocity.Magnitude
		if v < 0.5 and w < 0.4 then
			rec.settled = (rec.settled or 0) + dt
		else
			rec.settled = 0
		end
		local flipped = VS.isFlipped(rec.base.CFrame)
		if rec.settled > 0.8 then
			if flipped then
				Cars.upright(rec)
				rec.settled = 0
			elseif #Cars.occupants(rec) == 0 or st.grounded >= 3 then
				Cars.sleep(rec)
			end
		elseif rec.wokeAt and now() - rec.wokeAt > 20 and not rec.driver then
			-- stuck rocking somewhere: park it where it is
			if flipped then
				Cars.upright(rec)
			end
			rec.wokeAt = now()
			rec.settled = 0.8
		end
	end
end

-- 4 Hz: water, sanity, streaming hints, flip timers.
local streamAt: { [Player]: number } = {}
function Cars.slowStep()
	local t = now()
	for _, rec in recs do
		if rec.sleeping or rec.sunk then
			continue
		end
		if inWater(rec) then
			Cars.sink(rec)
			continue
		end
		local driver = rec.driver
		if driver then
			local base = rec.base
			local v = base.AssemblyLinearVelocity
			local limit = VS.studs(rec.spec.topKmh) * 1.6 + 25
			if v.Magnitude > limit or v.Y > 160 then
				rec.strikes = (rec.strikes or 0) + 1
				if rec.strikes >= 4 then
					rec.strikes = 0
					warn(string.format("[GwangalliVehicles] %s: car too fast (%.0f studs/s), taking it back", driver.Name, v.Magnitude))
					pcall(function()
						base:SetNetworkOwner(nil)
						base.AssemblyLinearVelocity = Vector3.zero
						base.AssemblyAngularVelocity = Vector3.zero
					end)
					task.delay(1, function()
						if rec.driver == driver then
							pcall(function()
								base:SetNetworkOwner(driver)
							end)
						end
					end)
				end
			else
				rec.strikes = math.max(0, (rec.strikes or 0) - 1)
			end
			if v.Magnitude > 35 and (streamAt[driver] or 0) < t then
				streamAt[driver] = t + 1
				local target = base.Position + v * 1.5
				task.spawn(function()
					pcall(function()
						driver:RequestStreamAroundAsync(target, 2)
					end)
				end)
			end
		end
	end
end

-- 0.2 Hz: idle despawn of called cars, restore moved parked cars.
function Cars.housekeeping()
	local t = now()
	local L = VS.Limits
	for _, rec in recs do
		local occupied = #Cars.occupants(rec) > 0
		if occupied then
			rec.lastUsed = t
			rec.farSince = nil
			continue
		end
		if rec.owner then
			local owner = rec.owner
			if owner.Parent ~= Players then
				Cars.despawn(rec)
				continue
			end
			if t - rec.lastUsed > (rec.idleLimit or L.IdleDespawn) then
				Cars.despawn(rec, "한동안 타지 않아서 차를 돌려보냈어요")
				continue
			end
			local _, hrp = humanoidOf(owner)
			if hrp and (hrp.Position - rec.base.Position).Magnitude > L.FarDespawn then
				rec.farSince = rec.farSince or t
				if t - rec.farSince > L.FarGrace then
					Cars.despawn(rec, "차에서 너무 멀어져서 돌려보냈어요")
				end
			else
				rec.farSince = nil
			end
		elseif rec.parked and rec.sleeping and rec.origin and t - rec.lastUsed > L.RestoreAfter then
			local moved = (rec.base.Position - rec.origin.Position).Magnitude
			if moved > 12 then
				local near = false
				for _, p in Players:GetPlayers() do
					local _, hrp = humanoidOf(p)
					if hrp and ((hrp.Position - rec.base.Position).Magnitude < 300 or (hrp.Position - rec.origin.Position).Magnitude < 300) then
						near = true
						break
					end
				end
				if not near then
					Cars.restore(rec)
				end
			end
		end
	end
end

function Cars.playerRemoving(player: Player)
	local rec = driving[player] or riding[player]
	if rec then
		clearManual(rec, player)
	end
	rec = driving[player]
	if rec then
		setDriver(rec, nil)
	end
	riding[player] = nil
	local mine = called[player]
	if mine then
		Cars.despawn(mine)
	end
	local job = jobCars[player]
	if job then
		Cars.despawn(job)
	end
	buckets[player] = nil
	streamAt[player] = nil
end

return Cars
