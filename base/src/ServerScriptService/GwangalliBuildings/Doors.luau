-- Doors: every door of the building system, server-authoritative.
--   Door Models (tag GwB_Door, built by Builder.Core.door) carry the state as attributes:
--     Open (bool), OpenDir (+1 swing toward the back / -1 toward the front), OpenT (server time),
--     Locked, Ring (server time of the last doorbell).
--   Clients animate the leaves from those attributes (smooth on every device, no physics); the server
--   only switches the leaves' collision, so a door never blocks anyone because of network delay.
-- Kinds: swing / double / glass (hinged), slide / sliding_glass, auto (motion sensor), stall (lockable
-- from inside), fire (closes itself), unit (도어락: owner / guests / open house), room (hotel key card,
-- karaoke room), shutter, staff (직원 전용).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Kit = Shared.Kit

local Doors = {}

local Registry: any
local services: any

type Rec = { model: Model, prompt: ProximityPrompt?, closeAt: number?, stallUser: Player?, autoLast: number? }
local recs: { [Model]: Rec } = {}
local autos: { Rec } = {}

local function leaves(m: Model): { Model }
	local out = {}
	for _, c in m:GetChildren() do
		if c:IsA("Model") and string.sub(c.Name, 1, 4) == "Leaf" then
			table.insert(out, c)
		end
	end
	return out
end

local function setCollide(m: Model, on: boolean)
	for _, leaf in leaves(m) do
		for _, p in leaf:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = on
			end
		end
	end
end

local function frameOf(m: Model): CFrame
	local f = m:GetAttribute("Frame")
	if typeof(f) == "CFrame" then
		return f
	end
	return m:GetPivot()
end

-- may this player open the door? -> ok, reason, action ("ring" for unit doors)
local function canOpen(p: Player, m: Model): (boolean, string?, string?)
	local lock = m:GetAttribute("Lock")
	local restricted = m:GetAttribute("Restricted")
	if type(restricted) == "string" and restricted ~= "" then
		local H = services.Housing
		if H and not H.canEnter(p, restricted) then
			return false, "입주민 전용 층이에요 (펜트하우스 카드키 필요)", nil
		end
	end
	if lock == "staff" then
		return false, "직원 전용이에요", nil
	elseif lock == "unit" then
		local unitId = m:GetAttribute("UnitId")
		local H = services.Housing
		if H and not H.canEnter(p, unitId) then
			return false, "잠겨 있어요. 초인종을 눌렀어요", "ring"
		end
	elseif lock == "room" then
		local key = m:GetAttribute("RoomKey")
		local unitId = m:GetAttribute("UnitId")
		local S = services.ShopFlows
		if S and not S.canEnterRoom(p, key or unitId) then
			return false, if key then "예약한 방이 아니에요 (카운터에서 결제)" else "객실 카드키가 필요해요 (프런트에서 체크인)", nil
		end
	elseif lock == "stall" then
		local r = recs[m]
		if m:GetAttribute("Locked") == true and r and r.stallUser ~= p then
			return false, "사용 중이에요", nil
		end
	end
	return true, nil, nil
end

local function promptText(m: Model): (string, string)
	local open = m:GetAttribute("Open") == true
	local kind = m:GetAttribute("DoorKind")
	local lock = m:GetAttribute("Lock")
	local label = m:GetAttribute("Label")
	local obj = if type(label) == "string" then label else ""
	if lock == "unit" then
		return (if open then "닫기" else "도어락 열기"), obj
	elseif lock == "room" then
		return (if open then "닫기" else "카드키 / 열기"), obj
	elseif lock == "stall" then
		if m:GetAttribute("Locked") == true then
			return "잠금 해제", "화장실 칸 (사용 중)"
		end
		return (if open then "닫기" else "열기"), "화장실 칸"
	elseif kind == "shutter" then
		return (if open then "셔터 내리기" else "셔터 올리기"), obj
	elseif kind == "fire" then
		return (if open then "닫기" else "방화문 열기"), obj
	end
	return (if open then "닫기" else "열기"), obj
end

local function refresh(r: Rec)
	if r.prompt then
		local a, o = promptText(r.model)
		r.prompt.ActionText = a
		r.prompt.ObjectText = o
	end
end

function Doors.setOpen(m: Model, open: boolean, opener: Player?)
	local r = recs[m]
	if not r then
		return
	end
	if (m:GetAttribute("Open") == true) == open then
		return
	end
	if open then
		local dir = 1
		local swing = m:GetAttribute("Swing")
		if swing == "front" then
			dir = -1
		elseif swing == "back" then
			dir = 1
		elseif opener then
			local pos = Registry.pos(opener)
			if pos then
				local f = frameOf(m)
				-- opener in front (LookVector side) -> the door swings away, to the back
				dir = if (pos - f.Position):Dot(f.LookVector) > 0 then 1 else -1
			end
		end
		m:SetAttribute("OpenDir", dir)
		m:SetAttribute("Open", true)
		m:SetAttribute("OpenT", Registry.now())
		setCollide(m, false)
		local ac = tonumber(m:GetAttribute("AutoClose"))
		if not ac and m:GetAttribute("DoorKind") ~= "auto" and m:GetAttribute("DoorKind") ~= "sliding_glass" and m:GetAttribute("DoorKind") ~= "shutter" then
			ac = Config.DOOR_AUTO_CLOSE + 6
		end
		r.closeAt = if ac then os.clock() + ac else nil
	else
		m:SetAttribute("Open", false)
		m:SetAttribute("OpenT", Registry.now())
		r.closeAt = nil
		task.delay(0.35, function()
			if m:GetAttribute("Open") ~= true then
				setCollide(m, true)
			end
		end)
	end
	refresh(r)
end

-- a character standing in the doorway keeps self-closing doors open
local function doorwayBusy(m: Model): boolean
	local f = frameOf(m)
	local w = tonumber(m:GetAttribute("Width")) or 4
	for _, p in Players:GetPlayers() do
		local pos = Registry.pos(p)
		if pos then
			local l = f:PointToObjectSpace(pos)
			if math.abs(l.X) < w / 2 + 0.6 and math.abs(l.Z) < 2.2 and l.Y > -1 and l.Y < 8 then
				return true
			end
		end
	end
	return false
end

local function onTriggered(m: Model, p: Player)
	local r = recs[m]
	if not r or not m:IsDescendantOf(workspace) then
		return
	end
	local anchor = m:FindFirstChild("PromptAt")
	if not anchor or not Registry.near(p, anchor, Config.DOOR_PROMPT_DIST + 4) then
		return
	end
	local open = m:GetAttribute("Open") == true
	local lock = m:GetAttribute("Lock")
	if lock == "stall" then
		-- inside the stall: lock / unlock; outside: open / close when free
		local f = frameOf(m)
		local pos = Registry.pos(p)
		local inside = pos and (pos - f.Position):Dot(f.LookVector) < 0
		if m:GetAttribute("Locked") == true then
			if r.stallUser == p or not (r.stallUser and r.stallUser.Parent) then
				m:SetAttribute("Locked", false)
				r.stallUser = nil
				Doors.setOpen(m, true, p)
			else
				Registry.toast(p, "사용 중이에요", "warn")
			end
		elseif inside and not open then
			m:SetAttribute("Locked", true)
			r.stallUser = p
			Registry.toast(p, "🔒 잠갔어요", "info")
		else
			Doors.setOpen(m, not open, p)
		end
		local ind = m:FindFirstChild("LockInd", true)
		if ind and ind:IsA("BasePart") then
			ind.Color = if m:GetAttribute("Locked") == true then Color3.fromRGB(220, 40, 40) else Color3.fromRGB(40, 200, 80)
		end
		refresh(r)
		return
	end
	if open then
		Doors.setOpen(m, false, p)
		return
	end
	local ok, msg, action = canOpen(p, m)
	if not ok then
		if action == "ring" then
			m:SetAttribute("Ring", Registry.now())
			local H = services.Housing
			if H and H.ring then
				H.ring(p, m:GetAttribute("UnitId"))
			end
		end
		if msg then
			Registry.toast(p, msg, "warn")
		end
		m:SetAttribute("Denied", Registry.now())
		return
	end
	if lock == "unit" or lock == "room" then
		m:SetAttribute("Unlock", Registry.now())
	end
	Doors.setOpen(m, true, p)
end

local function register(m: Instance)
	if not m:IsA("Model") or recs[m] then
		return
	end
	local r: Rec = { model = m }
	recs[m] = r
	local kind = m:GetAttribute("DoorKind")
	if kind == "auto" then
		table.insert(autos, r)
	else
		local anchor = m:FindFirstChild("PromptAt")
		if anchor then
			local a, o = promptText(m)
			local pr = Kit.prompt(anchor, a, o, { dist = Config.DOOR_PROMPT_DIST, name = "DoorPrompt" })
			pr.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
			pr.Triggered:Connect(function(p)
				onTriggered(m, p)
			end)
			r.prompt = pr
		end
	end
	setCollide(m, m:GetAttribute("Open") ~= true)
end

-- API for other services ---------------------------------------------------------------------------
function Doors.forUnit(unitId: string): { Model }
	local out = {}
	for m in recs do
		if m:GetAttribute("UnitId") == unitId and m:GetAttribute("Entrance") == true then
			table.insert(out, m)
		end
	end
	return out
end

function Doors.refreshAll()
	for _, r in recs do
		refresh(r)
	end
end

function Doors.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	CollectionService:GetInstanceAddedSignal("GwB_Door"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("GwB_Door"):Connect(function(m)
		recs[m :: Model] = nil
	end)
	for _, m in CollectionService:GetTagged("GwB_Door") do
		register(m)
	end
	Registry.on("door.toggle", function(p: Player, payload: any)
		local m = payload.door
		if typeof(m) == "Instance" and recs[m :: Model] then
			onTriggered(m :: Model, p)
		end
		return { ok = true }
	end)
end

function Doors.start()
	local acc = 0
	while true do
		local dt = task.wait(0.25)
		acc += dt
		local now = os.clock()
		-- automatic doors (motion sensor)
		local positions = {}
		for _, p in Players:GetPlayers() do
			local pos = Registry.pos(p)
			if pos then
				table.insert(positions, pos)
			end
		end
		for i = #autos, 1, -1 do
			local r = autos[i]
			local m = r.model
			if not m.Parent then
				table.remove(autos, i)
			elseif m:IsDescendantOf(workspace) then
				local f = frameOf(m)
				local near = false
				for _, pos in positions do
					local l = f:PointToObjectSpace(pos)
					if math.abs(l.Z) < Config.DOOR_AUTO_RADIUS and math.abs(l.X) < (tonumber(m:GetAttribute("Width")) or 5) / 2 + 3 and l.Y > -2 and l.Y < 9 then
						near = true
						break
					end
				end
				if near then
					r.autoLast = now
					if m:GetAttribute("Open") ~= true then
						Doors.setOpen(m, true, nil)
					end
				elseif m:GetAttribute("Open") == true and now - (r.autoLast or 0) > 1.4 then
					Doors.setOpen(m, false, nil)
				end
			end
		end
		-- self-closing doors
		if acc >= 0.5 then
			acc = 0
			for m, r in recs do
				if r.closeAt and now >= r.closeAt and m:GetAttribute("Open") == true then
					if doorwayBusy(m) then
						r.closeAt = now + 1.5
					else
						Doors.setOpen(m, false, nil)
					end
				end
			end
		end
	end
end

return Doors
