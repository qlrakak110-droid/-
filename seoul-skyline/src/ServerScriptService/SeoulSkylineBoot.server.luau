-- SeoulSkylineBoot — 서버 시작 시 맵 준비
--   * Workspace 에 SeoulSkyline 이 이미 있으면(커맨드 바로 구워 저장한 경우) 조명만 다시 적용합니다.
--   * 없으면 즉시 임시 스폰을 만든 뒤 전체 맵을 생성합니다(수 초).
--   * Config.Lighting.DayNightCycle = true 이면 시간이 흐르고 창문/가로등이 자동 점등/소등됩니다.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local SeoulSkyline = require(ServerStorage:WaitForChild("SeoulSkyline"))
local Config = SeoulSkyline.Config

local existing = workspace:FindFirstChild(Config.ROOT_NAME)
if existing then
	SeoulSkyline.ApplyLighting()
	SeoulSkyline.SetNight(SeoulSkyline.IsNightClock(Lighting.ClockTime))
else
	-- 맵이 생성되는 동안 접속한 플레이어가 물에 빠지지 않도록 전망대 위치에 임시 스폰/발판
	local V = Config.Viewpoint
	local tempPad = Instance.new("Part")
	tempPad.Name = "SeoulSkyline_TempPad"
	tempPad.Anchored = true
	tempPad.Size = Vector3.new(40, 2, 40)
	tempPad.Position = Vector3.new(V.DeckCenter.X, V.DeckHeight - 1, V.DeckCenter.Z)
	tempPad.Transparency = 1
	tempPad.Parent = workspace
	local tempSpawn = Instance.new("SpawnLocation")
	tempSpawn.Name = "SeoulSkyline_TempSpawn"
	tempSpawn.Anchored = true
	tempSpawn.Size = Vector3.new(8, 1, 8)
	tempSpawn.Position = tempPad.Position + Vector3.new(0, 1.5, 0)
	tempSpawn.Transparency = 1
	tempSpawn.CanCollide = false
	tempSpawn.Parent = workspace

	SeoulSkyline.Build()

	tempSpawn:Destroy()
	tempPad:Destroy()
	-- 생성 전에 스폰된 캐릭터는 정식 스폰으로 옮김
	local root = workspace:FindFirstChild(Config.ROOT_NAME)
	local spawn = root and root:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			if char and char.PrimaryPart then
				char:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
			end
		end
	end
end

if Config.Lighting.DayNightCycle then
	local secondsPerHour = Config.Lighting.MinutesPerDay * 60 / 24
	task.spawn(function()
		while true do
			local dt = task.wait(0.25)
			Lighting.ClockTime = (Lighting.ClockTime + dt / secondsPerHour) % 24
			SeoulSkyline.SetNight(SeoulSkyline.IsNightClock(Lighting.ClockTime))
		end
	end)
end
