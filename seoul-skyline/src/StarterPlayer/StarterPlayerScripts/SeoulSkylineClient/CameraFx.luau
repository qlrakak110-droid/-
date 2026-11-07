--!strict
-- SeoulSkylineClient / CameraFx — 접속 인트로 시네마틱 + 포토 스팟(사진 모드)
--
--   인트로: 루트 속성 IntroCinematic ~= false 일 때, 세션에서 처음 캐릭터가 생기면 7초 시네마틱.
--     수면 가까이 낮게 떠서 타워를 올려다보는 구도 → 강과 공원 위로 뒤로 물러나며 상승 → 히어로 구도(루트 속성
--     HeroCamPos/HeroCamLook/HeroFov)에서 끝남. 레터박스 + 제목, 아무 입력이나 누르면 즉시 건너뜀.
--     다른 스크립트가 도중에 카메라를 가져가면(CFrame 이 외부에서 바뀜) 조용히 양보합니다.
--   사진 모드: ProximityPromptService.PromptTriggered 에서 ActionText "사진 구도" 인 프롬프트 → 히어로 구도로 트윈,
--     Lighting 의 DepthOfFieldEffect 를 은은하게 켬(없으면 임시 생성), 안내 문구 표시.
--     아무 키/클릭/터치 또는 캐릭터 이동 시 카메라·피사계 심도·프롬프트를 원래대로 복구.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Lighting = game:GetService("Lighting")
local Util = require(script.Parent.Util)

local CameraFx = {}

local PHOTO_ACTION = "사진 구도"
local PHOTO_HINT = "사진 모드 · 아무 키나 눌러 나가기"
local INTRO_SECONDS = 7
local INTRO_STEP = "SeoulSkylineIntro"
local PLAYED_ATTR = "SeoulIntroPlayed"

local player = Players.LocalPlayer
local root: Model? = nil
local introState = "idle" -- idle | running | done
local stopIntro: ((boolean) -> ())? = nil
local photo: { [string]: any }? = nil

local function heroOf(src: Instance?): (Vector3?, Vector3?, number)
	for _, inst in { src, root } do
		if inst then
			local p, l, f = inst:GetAttribute("HeroCamPos"), inst:GetAttribute("HeroCamLook"), inst:GetAttribute("HeroFov")
			if typeof(p) == "Vector3" and typeof(l) == "Vector3" then
				return p, l, if typeof(f) == "number" then f else 62
			end
		end
	end
	return nil, nil, 62
end

local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function restoreCamera(saved: { [string]: any })
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local t = saved.type
	cam.CameraType = if t == nil or t == Enum.CameraType.Scriptable then Enum.CameraType.Custom else t
	cam.FieldOfView = saved.fov or 70
	cam.CameraSubject = humanoid() or saved.subject
end

local function label(parent: Instance, text: string, size: number, pos: UDim2, anchor: Vector2, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(0.6, 0, 0, size + 6)
	t.Position = pos
	t.AnchorPoint = anchor
	t.Font = Enum.Font.GothamMedium
	t.TextSize = size
	t.TextColor3 = Color3.fromRGB(240, 236, 228)
	t.TextXAlignment = align
	t.TextTransparency = 1
	t.Text = text
	t.Parent = parent
	return t
end

------------------------------------------------------------------------------------------------------
-- 인트로
------------------------------------------------------------------------------------------------------
local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local function smoother(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function playIntro()
	if introState ~= "idle" then
		return
	end
	local r = root
	local cam = workspace.CurrentCamera
	if not r or not cam or r:GetAttribute("IntroCinematic") == false or player:GetAttribute(PLAYED_ATTR) then
		return
	end
	local H, K, F = heroOf(nil)
	if not H or not K then
		return
	end
	introState = "running"
	player:SetAttribute(PLAYED_ATTR, true)

	-- 경로(히어로 구도 기준 상대 좌표): 강 위 낮은 곳에서 타워를 올려다봄 → 뒤로 물러나며 상승 → 히어로
	local flat = Vector3.new(K.X - H.X, 0, K.Z - H.Z)
	local dist = flat.Magnitude
	local fwd = flat.Unit
	local right = fwd:Cross(Vector3.yAxis)
	local P0 = H + fwd * (dist * 0.5) - right * (dist * 0.2)
	P0 = Vector3.new(P0.X, math.max(H.Y * 0.18, 45), P0.Z)
	local C1 = P0:Lerp(H, 0.35) + Vector3.new(0, 20, 0)
	local C2 = H + fwd * (dist * 0.12) + right * (dist * 0.02) - Vector3.new(0, 30, 0)
	local L0 = K - right * (dist * 0.16) + Vector3.new(0, dist * 0.1, 0)
	local FOV0 = math.max(F - 22, 30)

	local saved = { type = cam.CameraType, fov = cam.FieldOfView, subject = cam.CameraSubject }
	local conns: { RBXScriptConnection } = {}
	local gui = Util.screenGui("SeoulIntro", 50)
	local bars: { Frame } = {}
	local texts: { TextLabel } = {}
	if gui then
		for i, y in { 0, 1 } do
			local f = Instance.new("Frame")
			f.BackgroundColor3 = Color3.new(0, 0, 0)
			f.BorderSizePixel = 0
			f.AnchorPoint = Vector2.new(0, y)
			f.Position = UDim2.fromScale(0, y)
			f.Size = UDim2.fromScale(1, 0)
			f.Parent = gui
			bars[i] = f
			TweenService:Create(f, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 0.1) }):Play()
		end
		texts[1] = label(gui, "잠실 · 한강", 26, UDim2.new(0, 36, 0.9, 8), Vector2.new(0, 0), Enum.TextXAlignment.Left)
		texts[2] = label(gui, "SEOUL  ·  BLUE HOUR", 13, UDim2.new(0, 38, 0.9, 42), Vector2.new(0, 0), Enum.TextXAlignment.Left)
		texts[3] = label(gui, "아무 키나 눌러 건너뛰기", 13, UDim2.new(1, -36, 0.9, 20), Vector2.new(1, 0), Enum.TextXAlignment.Right)
		for i, t in texts do
			TweenService:Create(t, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.6 + i * 0.25), { TextTransparency = if i == 3 then 0.35 else 0.05 }):Play()
		end
	end

	local t0 = os.clock()
	local lastSet: CFrame? = nil
	local finished = false

	local function finish(restore: boolean)
		if finished then
			return
		end
		finished = true
		introState = "done"
		stopIntro = nil
		pcall(function()
			RunService:UnbindFromRenderStep(INTRO_STEP)
		end)
		Util.disconnectAll(conns)
		if restore then
			restoreCamera(saved)
		end
		if gui then
			for _, f in bars do
				TweenService:Create(f, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0) }):Play()
			end
			for _, t in texts do
				TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			end
			task.delay(0.6, function()
				gui:Destroy()
			end)
		end
	end
	stopIntro = finish

	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(INTRO_STEP, Enum.RenderPriority.Camera.Value + 1, function()
		local c = workspace.CurrentCamera
		if not c then
			return
		end
		-- 다른 스크립트가 카메라를 가져갔으면 양보
		if lastSet and (c.CFrame.Position - lastSet.Position).Magnitude > 0.05 then
			finish(false)
			return
		end
		local k = math.clamp((os.clock() - t0) / INTRO_SECONDS, 0, 1)
		local e = smoother(k)
		local pos = bezier(P0, C1, C2, H, e)
		local lookAt = L0:Lerp(K, smoother(math.min(1, k * 1.12)))
		local cf = CFrame.lookAt(pos, lookAt)
		c.CameraType = Enum.CameraType.Scriptable
		c.CFrame = cf
		c.FieldOfView = FOV0 + (F - FOV0) * e
		lastSet = cf
		if k >= 1 then
			finish(true)
		end
	end)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input)
		if Util.isUserInput(input) then
			finish(true)
		end
	end))
	table.insert(conns, player.CharacterRemoving:Connect(function()
		finish(true)
	end))
end

local function tryIntro()
	if introState ~= "idle" or not root or not player.Character then
		return
	end
	task.delay(0.5, playIntro)
end

------------------------------------------------------------------------------------------------------
-- 사진 모드
------------------------------------------------------------------------------------------------------
local exitPhoto: () -> ()

local function enterPhoto(prompt: ProximityPrompt)
	if photo then
		return
	end
	if stopIntro then
		stopIntro(true)
	end
	local H, K, F = heroOf(prompt.Parent)
	local cam = workspace.CurrentCamera
	if not H or not K or not cam then
		return
	end
	local st: { [string]: any } = {
		type = cam.CameraType,
		fov = cam.FieldOfView,
		subject = cam.CameraSubject,
		prompt = prompt,
		conns = {},
		t0 = os.clock(),
	}
	photo = st
	prompt.Enabled = false
	cam.CameraType = Enum.CameraType.Scriptable
	st.camTween = TweenService:Create(cam, TweenInfo.new(1.6, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), { CFrame = CFrame.lookAt(H, K), FieldOfView = F })
	st.camTween:Play()

	-- 은은한 피사계 심도: 가까운 전경만 살짝, 원경은 아주 약하게
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		st.dofSaved = { Enabled = dof.Enabled, FarIntensity = dof.FarIntensity, NearIntensity = dof.NearIntensity, FocusDistance = dof.FocusDistance, InFocusRadius = dof.InFocusRadius }
	else
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "SeoulPhotoDOF"
		st.dofCreated = true
	end
	local d = dof :: DepthOfFieldEffect
	d.FarIntensity = 0
	d.NearIntensity = 0
	d.FocusDistance = 200
	d.InFocusRadius = 50
	d.Enabled = true
	d.Parent = Lighting
	st.dof = d
	st.dofTween = TweenService:Create(d, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { FarIntensity = 0.06, NearIntensity = 0.3 })
	st.dofTween:Play()

	local gui = Util.screenGui("SeoulPhotoMode", 40)
	if gui then
		local pill = Instance.new("Frame")
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -28)
		pill.Size = UDim2.fromOffset(300, 34)
		pill.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
		pill.BackgroundTransparency = 1
		pill.BorderSizePixel = 0
		pill.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = pill
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamMedium
		t.TextSize = 14
		t.TextColor3 = Color3.fromRGB(240, 236, 228)
		t.TextTransparency = 1
		t.Text = PHOTO_HINT
		t.Parent = pill
		TweenService:Create(pill, TweenInfo.new(0.6), { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(t, TweenInfo.new(0.6), { TextTransparency = 0.05 }):Play()
		st.gui = gui
	end

	table.insert(st.conns, UserInputService.InputBegan:Connect(function(input)
		if os.clock() - st.t0 > 0.5 and Util.isUserInput(input) then
			exitPhoto()
		end
	end))
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hrpPos = if hrp then hrp.Position else nil
	table.insert(st.conns, RunService.Heartbeat:Connect(function()
		local hum = humanoid()
		if not hum or hum.Health <= 0 then
			exitPhoto()
		elseif os.clock() - st.t0 > 0.3 and hum.MoveDirection.Magnitude > 0.1 then
			exitPhoto() -- 이동 입력
		elseif hrp and hrpPos and (hrp.Position - hrpPos).Magnitude > 3 then
			exitPhoto() -- 밀리거나 점프로 자리를 벗어남
		end
	end))
	table.insert(st.conns, player.CharacterRemoving:Connect(function()
		exitPhoto()
	end))
end

exitPhoto = function()
	local st = photo
	if not st then
		return
	end
	photo = nil
	Util.disconnectAll(st.conns)
	if st.camTween then
		st.camTween:Cancel()
	end
	if st.dofTween then
		st.dofTween:Cancel()
	end
	restoreCamera(st)
	local d: DepthOfFieldEffect = st.dof
	if d then
		local fade = TweenService:Create(d, TweenInfo.new(0.35), { FarIntensity = 0, NearIntensity = 0 })
		fade.Completed:Once(function()
			if st.dofCreated then
				d:Destroy()
			elseif st.dofSaved then
				for k, v in st.dofSaved do
					(d :: any)[k] = v
				end
			end
		end)
		fade:Play()
	end
	if st.gui then
		local g = st.gui :: ScreenGui
		g:Destroy()
	end
	local prompt = st.prompt :: ProximityPrompt
	if prompt and prompt.Parent then
		prompt.Enabled = true
	end
end

------------------------------------------------------------------------------------------------------
-- 수명
------------------------------------------------------------------------------------------------------
-- init: 세션 단위 연결. 반환 = 정리 함수
function CameraFx.init(): () -> ()
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.ActionText == PHOTO_ACTION then
			enterPhoto(prompt)
		end
	end))
	table.insert(conns, player.CharacterAdded:Connect(tryIntro))
	return function()
		Util.disconnectAll(conns)
		if stopIntro then
			stopIntro(true)
		end
		exitPhoto()
	end
end

-- 다른 로컬 스크립트(예: UI 버튼)에서 사진 모드를 열고 닫을 수 있게 공개
function CameraFx.enterPhoto(prompt: ProximityPrompt)
	enterPhoto(prompt)
end
function CameraFx.exitPhoto()
	exitPhoto()
end
function CameraFx.isPhotoMode(): boolean
	return photo ~= nil
end

-- 맵 루트가 생기거나(재생성 포함) 사라질 때 init.client 가 호출
function CameraFx.setRoot(r: Model?)
	root = r
	if not r then
		exitPhoto()
		return
	end
	tryIntro()
end

return CameraFx
