--!strict
-- SeoulSkylineClient / ElevatorFx — 엘리베이터 탑승 연출
--   서버(SeoulSkylineBoot)가 태그 "SeoulElevator" 버튼의 ProximityPrompt 로 캐릭터를 순간 이동시키는 동안,
--   클라이언트는 화면을 부드럽게 어둡게 했다가(문 닫힘) 이동이 끝나면 다시 밝힙니다(문 열림).
--   이동 완료 = HumanoidRootPart 가 크게 움직임(> 20 stud) 또는 1.4 초 경과.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local ElevatorFx = {}

local TAG = "SeoulElevator"
local player = Players.LocalPlayer
local busy = false

local function makeGui(): (ScreenGui, Frame, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SeoulElevatorFade"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(6, 8, 12)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(420, 40)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(236, 238, 244)
	label.TextTransparency = 1
	label.Parent = frame
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, frame, label
end

local function ride(prompt: ProximityPrompt)
	if busy then
		return
	end
	busy = true
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = hrp and hrp.Position
	local gui, frame, label = makeGui()
	label.Text = prompt.ActionText ~= "" and (prompt.ActionText .. " …") or "이동 중 …"
	local tin = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, tin, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(label, tin, { TextTransparency = 0.1 }):Play()
	local t0 = os.clock()
	while os.clock() - t0 < 1.4 do
		RunService.RenderStepped:Wait()
		if start and hrp and hrp.Parent and (hrp.Position - start).Magnitude > 20 and os.clock() - t0 > 0.45 then
			break
		end
	end
	task.wait(0.15)
	local tout = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(label, tout, { TextTransparency = 1 }):Play()
	local fade = TweenService:Create(frame, tout, { BackgroundTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	gui:Destroy()
	busy = false
end

-- init: 세션 단위 연결. 반환 = 정리 함수
function ElevatorFx.init(): () -> ()
	local conn = ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local button = prompt.Parent
		if button and CollectionService:HasTag(button, TAG) then
			task.spawn(ride, prompt)
		end
	end)
	return function()
		conn:Disconnect()
		local g = player:FindFirstChild("PlayerGui")
		local f = g and g:FindFirstChild("SeoulElevatorFade")
		if f then
			f:Destroy()
		end
		busy = false
	end
end

return ElevatorFx
