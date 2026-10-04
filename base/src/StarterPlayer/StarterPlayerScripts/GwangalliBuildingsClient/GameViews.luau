-- GameViews: the play screens of the 당구장 and the PC방.
--   billiards: top-down camera over the rented table, aim line from the white ball, angle / power
--              buttons, 샷 -> the server simulates (Shared.Billiards) and every nearby client replays
--              the recorded frames on the ball parts ("billiards" event).
--   pc:        a 30-second reaction mini game on the PC (점수 -> 즐거움), the remaining time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Billiards = Shared.Billiards
local Util = Shared.Util
local UI = require(script.Parent:WaitForChild("UI"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local GameViews = {}

local C = UI.C

-------------------------------------------------------------------------------------------------
-- billiards
-------------------------------------------------------------------------------------------------
local aim: any = nil -- { d, angle, power, line, sheet, camSaved }

local function centerOf(tm: Instance): CFrame?
	local c = tm:FindFirstChild("TableCenter")
	if c and c:IsA("BasePart") then
		return c.CFrame
	elseif c and c:IsA("Attachment") then
		return c.WorldCFrame
	end
	return nil
end

local function updateLine()
	if not aim then
		return
	end
	local tm = aim.d.table
	local cue = tm and tm:FindFirstChild("Ball1") :: BasePart?
	local center = tm and centerOf(tm)
	if not cue or not center then
		return
	end
	if not aim.line then
		local p = Instance.new("Part")
		p.Name = "GwB_AimLine"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 255, 255)
		p.Transparency = 0.35
		p.Parent = workspace
		aim.line = p
	end
	local len = 2 + aim.power * 5
	local dir = center:VectorToWorldSpace(Vector3.new(math.cos(aim.angle), 0, math.sin(aim.angle)))
	local from = cue.Position
	aim.line.Size = Vector3.new(0.06, 0.04, len)
	aim.line.CFrame = CFrame.lookAt(from + dir * (len / 2 + Billiards.R), from + dir * (len + Billiards.R))
end

local function closeAim()
	if not aim then
		return
	end
	if aim.line then
		aim.line:Destroy()
	end
	local cam = workspace.CurrentCamera
	if cam and aim.camSaved then
		cam.CameraType = aim.camSaved
	end
	aim = nil
end

local function aimSheet(d: any)
	closeAim()
	aim = { d = d, angle = 0, power = 0.5 }
	local tm = d.table
	local center = tm and centerOf(tm)
	local cam = workspace.CurrentCamera
	if cam and center then
		aim.camSaved = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt((center * CFrame.new(0, 13, 7)).Position, center.Position)
	end
	local s = UI.sheet({
		title = "🎱 " .. tostring(d.tableId or "") .. "번 테이블 · 4구",
		sub = "흰 공으로 빨간 공 두 개를 맞히면 1점 (노란 공은 파울)",
		h = 250,
		w = 460,
		footer = true,
		kind = "billiards",
		onClose = closeAim,
	})
	aim.sheet = s
	local row1 = UI.frame(s.body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46) })
	UI.list(row1, 6, true)
	local function turn(deg: number)
		if aim then
			aim.angle += math.rad(deg)
			updateLine()
		end
	end
	UI.button(row1, "⟲ 15°", function()
		turn(-15)
	end, { style = "ghost", size = UDim2.new(0.23, 0, 1, 0), textSize = 14 })
	UI.button(row1, "◀ 2°", function()
		turn(-2)
	end, { style = "ghost", size = UDim2.new(0.23, 0, 1, 0), textSize = 14 })
	UI.button(row1, "2° ▶", function()
		turn(2)
	end, { style = "ghost", size = UDim2.new(0.23, 0, 1, 0), textSize = 14 })
	UI.button(row1, "15° ⟳", function()
		turn(15)
	end, { style = "ghost", size = UDim2.new(0.23, 0, 1, 0), textSize = 14 })
	local row2 = UI.frame(s.body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46) })
	UI.list(row2, 6, true)
	local powerLabel: TextLabel
	local function setPower(v: number)
		if aim then
			aim.power = math.clamp(v, 0.05, 1)
			powerLabel.Text = string.format("힘 %d%%", math.floor(aim.power * 100 + 0.5))
			updateLine()
		end
	end
	UI.button(row2, "－", function()
		setPower(aim.power - 0.1)
	end, { style = "ghost", size = UDim2.new(0.2, 0, 1, 0) })
	powerLabel = UI.label(row2, "힘 50%", { size = 16, bold = true, align = "center", sizeU = UDim2.new(0.5, 0, 1, 0) })
	UI.button(row2, "＋", function()
		setPower(aim.power + 0.1)
	end, { style = "ghost", size = UDim2.new(0.2, 0, 1, 0) })
	UI.button(s.footer, "🎱 샷!", function()
		if not aim then
			return
		end
		local res = Net.call("shop.billiardsShot", { shopId = d.shopId, tableId = d.tableId, angle = aim.angle, power = aim.power })
		if res.ok then
			Sfx.at("billiard_hit", tm and tm:FindFirstChild("Ball1"), { volume = 0.6 })
			if aim.line then
				aim.line.Transparency = 1
			end
		end
	end, { style = "gold", size = UDim2.new(0.6, 0, 0, 48) })
	UI.label(s.footer, "남은 시간 " .. Util.clock(tonumber(d.remaining) or 0), { size = 13, color = C.sub, align = "center", sizeU = UDim2.new(0.36, 0, 1, 0) })
	updateLine()
end

local replaying: { [Instance]: boolean } = {}
local function replay(d: any)
	local tm = d.table
	local frames = d.frames
	if typeof(tm) ~= "Instance" or type(frames) ~= "table" or #frames == 0 or replaying[tm] then
		return
	end
	local center = centerOf(tm)
	if not center then
		return
	end
	local balls = {}
	for b = 1, 4 do
		balls[b] = tm:FindFirstChild("Ball" .. b)
	end
	replaying[tm] = true
	local t0 = os.clock()
	local last = frames[#frames][1]
	local i = 1
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		while i < #frames and frames[i + 1][1] <= t do
			i += 1
		end
		local f0, f1 = frames[i], frames[math.min(i + 1, #frames)]
		local k = if f1[1] > f0[1] then math.clamp((t - f0[1]) / (f1[1] - f0[1]), 0, 1) else 1
		for b = 1, 4 do
			local bp = balls[b]
			if bp then
				local x = f0[2 * b] + (f1[2 * b] - f0[2 * b]) * k
				local z = f0[2 * b + 1] + (f1[2 * b + 1] - f0[2 * b + 1]) * k
				bp.CFrame = center * CFrame.new(x, Billiards.R, z)
			end
		end
		if t >= last then
			conn:Disconnect()
			replaying[tm] = nil
			if aim and aim.d.table == tm then
				if (tonumber(d.score) or 0) > 0 then
					UI.banner("🎯 득점! 총 " .. tostring(d.total or 0) .. "점", 2)
					Sfx.ui("success")
				elseif d.foul then
					UI.toast("😅 노란 공을 맞혀서 파울!", "warn")
				else
					UI.toast("아깝다! 빨간 공 두 개를 모두 맞혀야 해요", "info")
				end
				if aim.line then
					aim.line.Transparency = 0.35
				end
				updateLine()
			end
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- PC (PC방 seat or a home PC)
-------------------------------------------------------------------------------------------------
local function pcSheet(d: any)
	local s = UI.sheet({
		title = if d.free then "🖥️ 내 컴퓨터" else ("🖥️ PC방 " .. tostring(d.seatNo or "") .. "번 자리"),
		sub = if d.remaining then "남은 시간 " .. Util.clock(tonumber(d.remaining) or 0) else "게임 한 판 할까요?",
		h = 420,
		w = 460,
		footer = true,
		kind = "pc",
	})
	local area = UI.frame(s.body, { Size = UDim2.new(1, 0, 0, 280), BackgroundColor3 = Color3.fromRGB(10, 14, 24) })
	UI.corner(area, 10)
	local info = UI.label(area, "🎯 광안 에임 챌린지\n30초 동안 나타나는 과녁을 최대한 많이 누르세요!", { size = 15, bold = true, align = "center", sizeU = UDim2.fromScale(1, 1) })
	local running = false
	local score = 0
	local function spawnTarget()
		if not running or not area.Parent then
			return
		end
		local b = Instance.new("TextButton")
		b.Text = "🎯"
		b.TextSize = 30
		b.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		b.Size = UDim2.new(0, 54, 0, 54)
		b.Position = UDim2.new(math.random() * 0.82, 0, math.random() * 0.78, 0)
		UI.corner(b, 27)
		b.Parent = area
		local hit = false
		b.Activated:Connect(function()
			if hit then
				return
			end
			hit = true
			score += 1
			Sfx.ui("tap")
			b:Destroy()
			spawnTarget()
		end)
		task.delay(1.4, function()
			if b.Parent and not hit then
				b:Destroy()
				spawnTarget()
			end
		end)
	end
	UI.button(s.footer, "▶ 게임 시작", function()
		if running then
			return
		end
		running = true
		score = 0
		info.Text = ""
		spawnTarget()
		task.delay(30, function()
			running = false
			for _, c in area:GetChildren() do
				if c:IsA("TextButton") then
					c:Destroy()
				end
			end
			if not area.Parent then
				return
			end
			info.Text = string.format("🏁 결과: %d 점!\n%s", score, if score >= 25 then "프로게이머 각!" elseif score >= 15 then "실력이 좋네요" else "한 판 더?")
			local pct = math.clamp(score * 4, 0, 100)
			Net.request("shop.pcGame", { score = pct })
			UI.toast(string.format("🎮 게임 한 판 끝! %d 점", score), "ok")
		end)
	end, { style = "primary", size = UDim2.new(0.6, 0, 0, 48) })
	UI.button(s.footer, "끄기", function()
		s.close()
	end, { style = "ghost", size = UDim2.new(0.36, 0, 0, 48) })
end

function GameViews.start(Screens: any)
	Screens.views.billiards = aimSheet
	Screens.views.pc = pcSheet
	Net.on("billiards", replay)
	Net.on("pc.close", function()
		UI.closeSheet("pc")
	end)
end

return GameViews
