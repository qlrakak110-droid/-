-- GwangalliCarDealer/TestDrive (server): 시승 bookkeeping for both test-drive paths.
--   * "garage" — kit cars (and showroom models without a 3D template) use the garage's own 60 s test drive
--     (its spawn lane, HUD, route, timeout and return). We only WATCH the car it returns: top speed and
--     distance for the 시승 리포트, then the report goes to the client when the car is gone.
--   * "dealer" — a showroom model whose template exists is test-driven as itself: spawned through the
--     vehicles API (id "dealer_test", so the garage never tracks or damages it), C.TEST.seconds long, ended on
--     time / 시승 끝내기 / out of the car for C.TEST.leftLimit s / car gone / respawn / leaving; the driver is put
--     back at GarageReturn (only when far and not on a work shift).
--   TestDrive.watch(player, model, entry, name, mode, seconds)   TestDrive.start(player, entry, colorId) -> res
--   TestDrive.stop(player, why)   TestDrive.active(player) -> mode?   TestDrive.cooldownLeft(player) -> s

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TestDrive = {}

local S: any
local C: any
local Bridge: any
local Store: any
local fire: (Player, { [string]: any }) -> () = function() end

type Watch = {
	mode: string,
	model: Model,
	entry: string,
	name: string,
	startedAt: number,
	untilT: number,
	top: number,
	studs: number,
	leftAt: number?,
	conns: { RBXScriptConnection },
}

local watches: { [Player]: Watch } = {}
local lastEnd: { [Player]: number } = {}
local STUD_M = 0.3 -- 1 stud = 0.3 m (GwangalliVehiclesShared: km/h = studs/s x 1.08)

function TestDrive.init(shared: any, bridge: any, store: any, fireFn: (Player, { [string]: any }) -> ())
	S = shared
	C = shared.Config
	Bridge = bridge
	Store = store
	fire = fireFn
end

function TestDrive.active(player: Player): string?
	local w = watches[player]
	return if w then w.mode else nil
end

function TestDrive.cooldownLeft(player: Player): number
	local t = lastEnd[player]
	if not t then
		return 0
	end
	return math.max(0, C.TEST.cooldown - (os.clock() - t))
end

local function kmhOf(v: number): number
	local VS = S.VS(0)
	if VS and type(VS.kmh) == "function" then
		local ok, k = pcall(VS.kmh, v)
		if ok and type(k) == "number" then
			return k
		end
	end
	return v * 1.08
end

local function carRoot(model: Model): BasePart?
	local base = model:FindFirstChild("DriveBase")
	if base and base:IsA("BasePart") then
		return base
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function finish(player: Player, why: string)
	local w = watches[player]
	if not w then
		return
	end
	watches[player] = nil
	for _, c in w.conns do
		c:Disconnect()
	end
	if w.mode == "dealer" then
		lastEnd[player] = os.clock()
		local model = w.model
		if model.Parent then
			Bridge.vehicles("eject", model)
			task.wait(0.2)
			if Bridge.vehicles("current", player) == model then
				Bridge.vehicles("despawn", player, "test")
			elseif model.Parent then
				model:Destroy()
			end
		end
		if player.Parent == Players and why ~= "leave" then
			local ret = Bridge.marker("GarageReturn")
			local root = Bridge.root(player)
			if ret and root and player:GetAttribute("OnShift") ~= true and (root.Position - ret.Position).Magnitude > C.TEST.returnRadius then
				task.wait(0.15)
				local ch = player.Character
				if ch and ch.Parent then
					pcall(function()
						ch:PivotTo(Bridge.groundFrame(ret) + Vector3.new(0, 3, 0))
					end)
				end
			end
		end
	end
	if player.Parent ~= Players then
		return
	end
	local report = {
		entry = w.entry,
		name = w.name,
		topKmh = math.floor(w.top + 0.5),
		meters = math.floor(w.studs * STUD_M + 0.5),
		seconds = math.floor(os.clock() - w.startedAt + 0.5),
	}
	local record = Store.tested(player, w.entry, report.topKmh, report.meters)
	fire(player, { k = "test", stage = "end", mode = w.mode, why = why, report = report, record = record })
end

function TestDrive.stop(player: Player, why: string)
	task.spawn(finish, player, why)
end

-- Starts measuring a test car (both modes). The watcher ends a garage test when its car is gone.
function TestDrive.watch(player: Player, model: Model, entry: string, name: string, mode: string, seconds: number)
	if watches[player] then
		finish(player, "replaced")
	end
	local w: Watch = {
		mode = mode,
		model = model,
		entry = entry,
		name = name,
		startedAt = os.clock(),
		untilT = os.clock() + seconds,
		top = 0,
		studs = 0,
		leftAt = nil,
		conns = {},
	}
	watches[player] = w
	if mode == "dealer" then
		table.insert(w.conns, player.CharacterAdded:Connect(function()
			TestDrive.stop(player, "respawn")
		end))
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			table.insert(w.conns, h.Died:Connect(function()
				TestDrive.stop(player, "dead")
			end))
		end
	end
end

-- Dealer-mode start (showroom model with a template). -> result table
function TestDrive.start(player: Player, e: any, colorId: string): { [string]: any }
	local GS = S.GS(0)
	if not GS then
		return Bridge.fail("offline", "정비소 전산이 아직 준비되지 않았어요")
	end
	if watches[player] then
		return Bridge.fail("busy", "이미 시승 중이에요")
	end
	local cd = TestDrive.cooldownLeft(player)
	if cd > 0 then
		return Bridge.fail("cooldown", string.format("%d초 뒤에 다시 시승할 수 있어요", math.ceil(cd)))
	end
	Bridge.request(player, "dismiss", {}) -- the called car (if any) goes home first; "none" is fine
	local spawnPart = Bridge.marker("GarageSpawn")
	local secs = C.TEST.seconds
	local ok, msg, model = Bridge.vehicles("spawnOwned", player, {
		id = "dealer_test",
		kind = e.kind,
		model = e.model,
		color = GS.color3(colorId),
		colorId = colorId,
		plate = "시승 " .. string.format("%04d", math.random(1000, 9999)),
		cond = 100,
		dirt = 0,
		label = e.name .. " 시승차",
		testDrive = os.time() + secs + 3, -- we end it first (report "time"), the spawn system is the backstop
	}, {
		near = if spawnPart then spawnPart.Position else nil,
		cframe = if spawnPart then Bridge.groundFrame(spawnPart) else nil,
		radius = 200,
		force = true,
		seat = true,
	})
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return Bridge.fail("spawn", if type(msg) == "string" and msg ~= "" then msg else "시승차를 준비하지 못했어요")
	end
	TestDrive.watch(player, model, e.id, e.name, "dealer", secs)
	fire(player, { k = "test", stage = "start", mode = "dealer", entry = e.id, name = e.name, seconds = secs, route = Bridge.route(), car = model })
	return { ok = true, code = "ok", message = "시승 시작", mode = "dealer", seconds = secs }
end

-- 4 Hz watcher
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then
		return
	end
	local step = acc
	acc = 0
	local now = os.clock()
	for player, w in watches do
		local model = w.model
		if not model.Parent then
			TestDrive.stop(player, "gone")
		elseif now >= w.untilT + (if w.mode == "garage" then 20 else 0) then
			-- garage tests end on the garage's own clock (the car vanishes); 20 s grace before we give up
			if w.mode == "dealer" then
				TestDrive.stop(player, "time")
			else
				TestDrive.stop(player, "gone")
			end
		else
			local driver = model:GetAttribute("DriveDriver")
			if driver == player.UserId then
				w.leftAt = nil
				local root = carRoot(model)
				if root then
					local v = root.AssemblyLinearVelocity
					local speed = Vector3.new(v.X, 0, v.Z).Magnitude
					if speed < 150 then -- ignore teleports / physics spikes
						w.top = math.max(w.top, kmhOf(speed))
						w.studs += speed * step
					end
				end
			elseif w.mode == "dealer" and now - w.startedAt > C.TEST.grace then
				w.leftAt = w.leftAt or now
				if now - (w.leftAt :: number) > C.TEST.leftLimit then
					TestDrive.stop(player, "left")
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if watches[player] then
		finish(player, "leave")
	end
	lastEnd[player] = nil
end)

return TestDrive
