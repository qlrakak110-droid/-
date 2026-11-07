--!strict
-- SeoulSkylineClient — 한강 잠실 야경 맵의 클라이언트 연출 (서버 의존 없음, RemoteEvent 없음)
--   * Traffic  : TrafficLanes 차선을 따라 흐르는 차량 불빛(클라이언트 전용 Neon 파트 ≤ 400)
--   * Beacons  : SeoulBeacon 항공장애등 1 Hz 맥동
--   * Boats    : SeoulBoat 유람선 운항(U턴 루프)
--   * CameraFx : 접속 인트로 시네마틱 + 포토 스팟 사진 모드
--   * ElevatorFx : 엘리베이터 탑승 시 화면 페이드(서버가 순간 이동 처리)
-- 맵이 Studio 에서 구워졌든 실행 중 생성되든 동작: Workspace.SeoulSkyline 이 나타날 때까지 기다리고,
-- 맵이 지워지거나 다시 생성되면(Build() 재실행) 모든 시스템을 정리한 뒤 새 루트로 다시 시작합니다.
-- 루트 속성 Traffic / Beacons / Boats / TrafficDensity / IntroCinematic 로 켜고 끕니다(변경 시 재시작).

local Util = require(script:WaitForChild("Util"))
local Traffic = require(script:WaitForChild("Traffic"))
local Beacons = require(script:WaitForChild("Beacons"))
local Boats = require(script:WaitForChild("Boats"))
local CameraFx = require(script:WaitForChild("CameraFx"))
local ElevatorFx = require(script:WaitForChild("ElevatorFx"))

type System = { start: (Model) -> () -> () }
local SYSTEMS: { { name: string, mod: System } } = {
	{ name = "Traffic", mod = Traffic :: any },
	{ name = "Beacons", mod = Beacons :: any },
	{ name = "Boats", mod = Boats :: any },
}
local RESTART_ATTRS = { Traffic = true, Beacons = true, Boats = true }

local current: Model? = nil
local stops: { () -> () } = {}
local rootConns: { RBXScriptConnection } = {}
local restartQueued = false

local function stopSystems()
	for _, stop in stops do
		local ok, err = pcall(stop)
		if not ok then
			warn("[SeoulSkylineClient] stop failed: " .. tostring(err))
		end
	end
	table.clear(stops)
end

local function startSystems(root: Model)
	for _, sys in SYSTEMS do
		local ok, res = pcall(sys.mod.start, root)
		if ok and type(res) == "function" then
			table.insert(stops, res)
		elseif not ok then
			warn(string.format("[SeoulSkylineClient] %s start failed: %s", sys.name, tostring(res)))
		end
	end
end

local scan: () -> ()

local function detach()
	Util.disconnectAll(rootConns)
	stopSystems()
	current = nil
	CameraFx.setRoot(nil)
end

local function attach(root: Model)
	if current == root then
		return
	end
	detach()
	current = root
	startSystems(root)
	CameraFx.setRoot(root)
	table.insert(rootConns, root.AncestryChanged:Connect(function()
		if current == root and not root:IsDescendantOf(workspace) then
			detach()
			task.defer(scan)
		end
	end))
	table.insert(rootConns, root.AttributeChanged:Connect(function(name)
		if RESTART_ATTRS[name] and not restartQueued then
			restartQueued = true
			task.defer(function()
				restartQueued = false
				if current == root then
					stopSystems()
					startSystems(root)
				end
			end)
		end
	end))
end

scan = function()
	local r = workspace:FindFirstChild(Util.ROOT_NAME)
	if r and r:IsA("Model") then
		attach(r)
	end
end

local cameraCleanup = CameraFx.init()
local elevatorCleanup = ElevatorFx.init()
local conns: { RBXScriptConnection } = {}
table.insert(conns, workspace.ChildAdded:Connect(function(c)
	if c.Name == Util.ROOT_NAME and c:IsA("Model") then
		attach(c)
	end
end))
script.Destroying:Connect(function()
	Util.disconnectAll(conns)
	detach()
	cameraCleanup()
	elevatorCleanup()
end)
scan()
