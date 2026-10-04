-- ElevClient: the moving parts of every elevator on this client.
--   * the car follows the server's motion segment (SegY0/SegY1/SegT0/SegV0 + VMax/Accel, Util.evalSeg on
--     the shared server clock), so every device sees the same smooth trapezoid ride;
--   * the local avatar rides along: while it stands in a moving car it is kept on the car floor;
--   * car + hall door leaves slide from Door / DoorT0; the hall lanterns and position displays show the
--     floor and direction; lit call buttons follow Calls / HallUp / HallDown;
--   * the floor panel sheet ("elev.panel" from the car's COP prompt) sends car calls, door open / close
--     and the alarm.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Util = Shared.Util
local UI = require(script.Parent:WaitForChild("UI"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local ElevClient = {}

local player = Players.LocalPlayer

type PartRel = { part: BasePart, rel: CFrame }
type Leaf = { slide: number, parts: { PartRel } }
type Elev = {
	model: Model,
	car: Model,
	labels: { string },
	short: { string },
	ys: { number },
	carCF0: CFrame,
	carY0: number,
	right: Vector3,
	base: CFrame,
	body: { PartRel }, -- car parts except door leaves, relative to the car pivot
	carLeaves: { Leaf },
	hall: { [number]: { Leaf } }, -- per stop, parts as world CFrames (rel = closed CFrame)
	displays: { { gui: SurfaceGui, stop: number?, where: string } },
	hallButtons: { { part: BasePart, stop: number, dir: string } },
	carButtons: { [number]: BasePart },
	y: number,
	doorP: number,
	hallStop: number?,
	lastDisp: number,
	lastLabel: string,
	moving: boolean,
	hum: Sound?,
	conns: { RBXScriptConnection },
}

local cache: { [Model]: Elev } = setmetatable({}, { __mode = "k" }) :: any
local live: { [Elev]: boolean } = {}
local rideOffset: number? = nil
local panelFor: Elev? = nil
local panelSheet: any = nil

local LIT = Color3.fromRGB(255, 170, 60)
local UNLIT = Color3.fromRGB(230, 230, 232)

local function shortLabel(label: string): string
	return string.match(label, "^(%d+)F$") or label
end

local function numberList(s: any): { [number]: boolean }
	local out = {}
	for _, v in Util.split(if type(s) == "string" then s else "", ",") do
		local n = tonumber(v)
		if n then
			out[n] = true
		end
	end
	return out
end

local function capture(m: Model): Elev?
	local car = m:FindFirstChild("Car")
	if not car or not car:IsA("Model") then
		return nil
	end
	local labels = Util.split(m:GetAttribute("Stops") :: string?, "|")
	local ys = {}
	for _, s in Util.split(m:GetAttribute("StopY") :: string?, "|") do
		table.insert(ys, tonumber(s) or 0)
	end
	if #labels == 0 or #labels ~= #ys then
		return nil
	end
	local base = m:GetAttribute("BaseCF")
	local right = if typeof(base) == "CFrame" then base.RightVector else car:GetPivot().RightVector
	local pivot = car:GetPivot()
	local carCF0 = m:GetAttribute("CarCF0")
	local carY0 = tonumber(m:GetAttribute("CarY0"))
	if typeof(carCF0) ~= "CFrame" or not carY0 then
		-- the server has not registered it yet: the car stands at its home stop
		local home = tonumber(m:GetAttribute("Home")) or 1
		carCF0 = pivot
		carY0 = ys[home] or ys[1]
	end
	local e: Elev = {
		model = m,
		car = car,
		labels = labels,
		short = {},
		ys = ys,
		carCF0 = carCF0 :: CFrame,
		carY0 = carY0 :: number,
		right = right,
		base = if typeof(base) == "CFrame" then base else car:GetPivot(),
		body = {},
		carLeaves = {},
		hall = {},
		displays = {},
		hallButtons = {},
		carButtons = {},
		y = 0,
		doorP = 0,
		hallStop = nil,
		lastDisp = 0,
		lastLabel = "",
		moving = false,
		hum = nil,
		conns = {},
	}
	for i, l in labels do
		e.short[i] = shortLabel(l)
	end
	-- car parts relative to the pivot the car has right now
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			local leafM = d.Parent
			if leafM and string.sub(leafM.Name, 1, 7) == "CarLeaf" then
				continue
			end
			table.insert(e.body, { part = d, rel = pivot:ToObjectSpace(d.CFrame) })
			local stop = tonumber(d:GetAttribute("Stop"))
			if stop and d:GetAttribute("Where") == "car" then
				e.carButtons[stop] = d
			end
		end
	end
	for _, leafM in car:GetChildren() do
		if leafM:IsA("Model") and string.sub(leafM.Name, 1, 7) == "CarLeaf" then
			local lf: Leaf = { slide = tonumber(leafM:GetAttribute("SlideX")) or 0, parts = {} }
			for _, d in leafM:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(lf.parts, { part = d, rel = pivot:ToObjectSpace(d.CFrame) })
				end
			end
			table.insert(e.carLeaves, lf)
		end
	end
	for _, s in m:GetChildren() do
		local i = tonumber(string.match(s.Name, "^Stop_(%d+)$"))
		if i then
			local list = {}
			for _, leafM in s:GetChildren() do
				if leafM:IsA("Model") and string.sub(leafM.Name, 1, 8) == "HallLeaf" then
					local lf: Leaf = { slide = tonumber(leafM:GetAttribute("SlideX")) or 0, parts = {} }
					for _, d in leafM:GetDescendants() do
						if d:IsA("BasePart") then
							table.insert(lf.parts, { part = d, rel = d.CFrame })
						end
					end
					table.insert(list, lf)
				end
			end
			e.hall[i] = list
			for _, d in s:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Where") == "hall" and d:GetAttribute("Dir") then
					table.insert(e.hallButtons, { part = d, stop = i, dir = d:GetAttribute("Dir") :: string })
				end
			end
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Name == "Display" and d.Parent and d.Parent:IsA("BasePart") then
			local p = d.Parent :: BasePart
			table.insert(e.displays, { gui = d, stop = tonumber(p:GetAttribute("Stop")), where = (p:GetAttribute("Where") :: string?) or "hall" })
		end
	end
	return e
end

local function segOf(m: Model): any
	return {
		y0 = tonumber(m:GetAttribute("SegY0")) or 0,
		y1 = tonumber(m:GetAttribute("SegY1")) or 0,
		t0 = tonumber(m:GetAttribute("SegT0")) or 0,
		v0 = tonumber(m:GetAttribute("SegV0")) or 0,
		vmax = tonumber(m:GetAttribute("VMax")) or Config.ELEV_SPEED,
		a = tonumber(m:GetAttribute("Accel")) or Config.ELEV_ACCEL,
	}
end

-- current car floor height + vertical speed
local function motion(e: Elev, now: number): (number, number)
	local m = e.model
	if m:GetAttribute("Moving") == true then
		local y, v = Util.evalSeg(segOf(m), now)
		return y, v
	end
	return tonumber(m:GetAttribute("SegY1")) or e.ys[tonumber(m:GetAttribute("Pos")) or 1] or e.carY0, 0
end

local function doorProgress(e: Elev, now: number): number
	local m = e.model
	local phase = m:GetAttribute("Door")
	local t0 = tonumber(m:GetAttribute("DoorT0")) or 0
	local k = math.clamp((now - t0) / Config.ELEV_DOOR_TIME, 0, 1)
	k = k * k * (3 - 2 * k)
	if phase == "opening" then
		return k
	elseif phase == "open" then
		return 1
	elseif phase == "closing" then
		return 1 - k
	end
	return 0
end

local function pivotAt(e: Elev, y: number): CFrame
	return e.carCF0 + Vector3.new(0, y - e.carY0, 0)
end

local function placeBody(e: Elev, pivot: CFrame)
	for _, r in e.body do
		r.part.CFrame = pivot * r.rel
	end
end

local function placeCarLeaves(e: Elev, pivot: CFrame, p: number)
	for _, lf in e.carLeaves do
		local off = e.right * (lf.slide * p)
		for _, r in lf.parts do
			r.part.CFrame = (pivot * r.rel) + off
		end
	end
end

local function placeHall(e: Elev, stop: number, p: number)
	local list = e.hall[stop]
	if not list then
		return
	end
	for _, lf in list do
		local off = e.right * (lf.slide * p)
		for _, r in lf.parts do
			r.part.CFrame = r.rel + off
		end
	end
end

local function stopNear(e: Elev, y: number): number
	local best, bd = 1, math.huge
	for i, sy in e.ys do
		local d = math.abs(sy - y)
		if d < bd then
			best, bd = i, d
		end
	end
	return best
end

local function updateDisplays(e: Elev, y: number)
	local m = e.model
	local moving = m:GetAttribute("Moving") == true
	local dir = m:GetAttribute("Dir")
	local label = e.short[stopNear(e, y)] or ""
	local arrow = if moving then (if dir == "up" then "▲" elseif dir == "down" then "▼" else "") else ""
	local key = label .. arrow
	local pos = tonumber(m:GetAttribute("Pos")) or 0
	local door = m:GetAttribute("Door")
	local open = door == "opening" or door == "open"
	for _, d in e.displays do
		local bg = d.gui:FindFirstChildOfClass("Frame")
		if bg then
			local f = bg:FindFirstChild("Floor") :: TextLabel?
			local a = bg:FindFirstChild("Arrow") :: TextLabel?
			if f then
				f.Text = label
			end
			if a then
				-- hall lantern: the arriving car's direction blinks at its stop
				if not moving and open and d.where == "hall" and d.stop == pos and dir ~= "" then
					a.Text = if dir == "up" then "▲" else "▼"
				else
					a.Text = arrow
				end
			end
		end
	end
	e.lastLabel = key
	-- call buttons
	local calls = numberList(m:GetAttribute("Calls"))
	for stop, b in e.carButtons do
		b.Color = if calls[stop] then LIT else UNLIT
	end
	local up, down = numberList(m:GetAttribute("HallUp")), numberList(m:GetAttribute("HallDown"))
	for _, hb in e.hallButtons do
		local lit = if hb.dir == "up" then up[hb.stop] else down[hb.stop]
		hb.part.Color = if lit then LIT else UNLIT
	end
end

-- is this world position inside the car? (car frame: the shaft frame at the car floor height y)
local function inCar(e: Elev, y: number, pos: Vector3): boolean
	local f = CFrame.new(e.base.X, y, e.base.Z) * e.base.Rotation
	local l = f:PointToObjectSpace(pos)
	local hw = Config.ELEV_CAR_W / 2 + 0.2
	return math.abs(l.X) <= hw and l.Z >= 0.2 and l.Z <= 0.6 + Config.ELEV_CAR_D + 0.2 and l.Y >= -1.5 and l.Y <= Config.ELEV_CAR_H
end

local function step()
	local now = workspace:GetServerTimeNow()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local riding = false
	for e in live do
		local m = e.model
		if not m.Parent then
			continue
		end
		local y, v = motion(e, now)
		local p = doorProgress(e, now)
		local moved = math.abs(y - e.y) > 1e-4
		local pivot = pivotAt(e, y)
		local near = (pivot.Position - camPos).Magnitude < 160
		if moved or (p ~= e.doorP) then
			if near or not e.moving then
				placeBody(e, pivot)
				placeCarLeaves(e, pivot, p)
			end
		end
		local pos = tonumber(m:GetAttribute("Pos")) or 1
		local stopHere = if m:GetAttribute("Moving") == true then nil else pos
		if e.hallStop and e.hallStop ~= stopHere then
			placeHall(e, e.hallStop, 0)
			e.hallStop = nil
		end
		if stopHere and (p ~= e.doorP or e.hallStop ~= stopHere) then
			placeHall(e, stopHere, p)
			e.hallStop = if p > 0 then stopHere else nil
		end
		e.doorP = p
		-- ride along: keep the avatar on the car floor while it moves
		if root and near then
			local inside = inCar(e, y, root.Position)
			if inside then
				riding = true
				local isMoving = m:GetAttribute("Moving") == true
				if not isMoving then
					local off = root.Position.Y - y
					if off > 1 and off < 6 then
						rideOffset = off
					end
				elseif moved then
					local want = y + (rideOffset or 3)
					local dy = want - root.Position.Y
					if math.abs(dy) > 0.25 then
						root.CFrame = root.CFrame + Vector3.new(0, dy, 0)
						local lv = root.AssemblyLinearVelocity
						root.AssemblyLinearVelocity = Vector3.new(lv.X, v, lv.Z)
					end
				end
			end
		end
		e.y = y
		-- motor hum while moving (only the car you are near)
		local mv = m:GetAttribute("Moving") == true
		if mv ~= e.moving then
			e.moving = mv
			if mv and near then
				local light = e.car:FindFirstChild("CarLight")
				e.hum = Sfx.loop("elevator_hum", light, { volume = 0.25, maxDist = 26 })
			elseif e.hum then
				e.hum:Destroy()
				e.hum = nil
			end
		end
		if near and os.clock() - e.lastDisp > 0.2 then
			e.lastDisp = os.clock()
			updateDisplays(e, y)
		end
	end
	if not riding then
		rideOffset = nil
	end
end

local function onArrive(e: Elev)
	local m = e.model
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local pos = tonumber(m:GetAttribute("Pos")) or 1
	local stopM = m:FindFirstChild("Stop_" .. pos)
	local disp = stopM and stopM:FindFirstChild("HallDisplay")
	if disp and (disp :: BasePart).Position and ((disp :: BasePart).Position - cam.CFrame.Position).Magnitude < 60 then
		Sfx.at("elevator_ding", disp, { volume = 0.6, maxDist = 40 })
	end
	local light = e.car:FindFirstChild("CarLight")
	if light and ((light :: BasePart).Position - cam.CFrame.Position).Magnitude < 30 then
		Sfx.at("elevator_ding", light, { volume = 0.5, maxDist = 24 })
	end
	if panelFor == e and panelSheet and panelSheet.isOpen() then
		ElevClient.refreshPanel()
	end
end

local function register(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local e = cache[m]
	if not e then
		e = capture(m)
		if not e then
			-- attributes not there yet (still building): try again shortly
			task.delay(1, function()
				if m.Parent and not cache[m] then
					register(m)
				end
			end)
			return
		end
		cache[m] = e
	end
	local ee = e :: Elev
	-- the server may publish the car origin after we captured: re-read it
	local cf0 = m:GetAttribute("CarCF0")
	if typeof(cf0) == "CFrame" then
		ee.carCF0 = cf0
		ee.carY0 = tonumber(m:GetAttribute("CarY0")) or ee.carY0
	end
	for _, c in ee.conns do
		c:Disconnect()
	end
	ee.conns = {
		m:GetAttributeChangedSignal("Arrive"):Connect(function()
			onArrive(ee)
		end),
		m:GetAttributeChangedSignal("CarCF0"):Connect(function()
			local c0 = m:GetAttribute("CarCF0")
			if typeof(c0) == "CFrame" then
				ee.carCF0 = c0
				ee.carY0 = tonumber(m:GetAttribute("CarY0")) or ee.carY0
			end
		end),
		m:GetAttributeChangedSignal("Calls"):Connect(function()
			if panelFor == ee and panelSheet and panelSheet.isOpen() then
				ElevClient.refreshPanel()
			end
		end),
	}
	ee.y = -1e9 -- force a placement on the next frame
	live[ee] = true
end

local function unregister(m: Instance)
	local e = cache[m :: Model]
	if not e then
		return
	end
	live[e] = nil
	for _, c in e.conns do
		c:Disconnect()
	end
	e.conns = {}
	-- leave every leaf closed
	local pivot = pivotAt(e, e.y)
	placeCarLeaves(e, pivot, 0)
	for i in e.hall do
		placeHall(e, i, 0)
	end
	if e.hum then
		e.hum:Destroy()
		e.hum = nil
	end
end

-------------------------------------------------------------------------------------------------
-- floor panel (the COP prompt opens it; also usable from the 월패드 later)
-------------------------------------------------------------------------------------------------
function ElevClient.refreshPanel()
	local e = panelFor
	local s = panelSheet
	if not e or not s or not s.isOpen() then
		return
	end
	s.clear()
	local m = e.model
	local calls = numberList(m:GetAttribute("Calls"))
	local pos = tonumber(m:GetAttribute("Pos")) or 1
	-- top floor first, like a real panel read top-down
	local n = #e.labels
	for k = n, 1, -1 do
		local i = k
		local lit = calls[i] == true
		local b = UI.button(s.body, e.short[i], function()
			Sfx.ui("tap")
			Net.call("elev.car", { elevator = m, stop = i })
		end, { style = if lit then "gold" elseif i == pos then "primary" else "ghost", textSize = 20, order = n - k + 1 })
		b.Name = "Floor_" .. i
	end
	s.setSub(string.format("현재 %s층 · 원하는 층을 누르세요", e.short[pos] or "?"))
end

local function openPanel(m: Model)
	local e = cache[m]
	if not e then
		return
	end
	panelFor = e
	local name = (m:GetAttribute("Name") :: string?) or "엘리베이터"
	local s = UI.sheet({
		title = "🛗 " .. name,
		sub = "원하는 층을 누르세요",
		h = 380,
		w = 360,
		grid = UDim2.new(0, 72, 0, 54),
		footer = true,
		kind = "elev",
		onClose = function()
			panelFor = nil
			panelSheet = nil
		end,
	})
	panelSheet = s
	UI.button(s.footer, "◀▶ 열림", function()
		Net.call("elev.door", { elevator = m, action = "open" })
	end, { style = "ghost", size = UDim2.new(0.31, 0, 0, 46) })
	UI.button(s.footer, "▶◀ 닫힘", function()
		Net.call("elev.door", { elevator = m, action = "close" })
	end, { style = "ghost", size = UDim2.new(0.31, 0, 0, 46) })
	UI.button(s.footer, "🔔 비상", function()
		Net.call("elev.door", { elevator = m, action = "alarm" })
	end, { style = "danger", size = UDim2.new(0.31, 0, 0, 46) })
	ElevClient.refreshPanel()
end

function ElevClient.start()
	CollectionService:GetInstanceAddedSignal("GwB_Elevator"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("GwB_Elevator"):Connect(unregister)
	for _, m in CollectionService:GetTagged("GwB_Elevator") do
		task.spawn(register, m)
	end
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[GwangalliBuildings] elevator client: " .. tostring(err))
		end
	end)
	Net.on("elev.panel", function(d)
		if typeof(d.elevator) == "Instance" then
			openPanel(d.elevator :: Model)
		end
	end)
	-- close the panel when the player walks out of the car
	task.spawn(function()
		while true do
			task.wait(0.5)
			local e = panelFor
			if e and panelSheet and panelSheet.isOpen() then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and not inCar(e, e.y, root.Position) then
					panelSheet.close()
				end
			end
		end
	end)
end

-- tests
function ElevClient.debug(m: Model): any
	local e = cache[m]
	return e and { y = e.y, doorP = e.doorP, hallStop = e.hallStop }
end

return ElevClient
