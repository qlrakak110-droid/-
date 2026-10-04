-- GwangalliGarage/Hud: small in-world helpers that never cover the centre of the screen.
--   * zone chip: when the player's own car stands in the 정비소 service bay / under the wash gantry
--     (GarageEvent "zone"), one big action button appears ABOVE the driving HUD's bottom cluster:
--     "🔧 정비 받기 · 32,000원" / "🫧 세차하기 · 5,000원" (56 px tall, slides up in 0.2 s)
--   * 시승 HUD (GarageEvent "testdrive"): a top chip with the countdown and the next route point
--     ("다음 지점 230m ▶"), a 56 px "시승 끝내기" button, and a glowing ring + beam at the next point of the
--     loop (one local part pair, moved from point to point)
--   * hit flash: a short red edge flash + toast when the car takes damage ("hit")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Hud = {}

local player = Players.LocalPlayer
local K: any, Layout: any, GS: any, Net: any = nil, nil, nil, nil
local E: any = {}
local S: any = { zone = nil, test = nil }

local BTN = 56

local function place()
	if not E.gui then
		return
	end
	local mt = Layout.metrics()
	local W, H = mt.W, mt.H
	-- the zone chip sits above the driving HUD's bottom cluster (speedometer / condition chip / pad)
	local y: number
	if mt.class == "phoneP" then
		y = H - 290
	elseif mt.class == "pc" then
		y = H - 150
	else
		y = H - 112
	end
	E.chip.Position = UDim2.fromOffset(math.floor(W / 2), y)
	-- 시승 chip: top centre under the toast row
	E.test.Position = UDim2.fromOffset(math.floor(W / 2), if mt.class == "phoneP" then 64 else 8)
end

function Hud.build(ctx: any)
	K, Layout, GS, Net = ctx.K, ctx.Layout, ctx.GS, ctx.Net
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliGarageHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 14
	E.gui = gui
	-- zone chip
	local chip = K.Button(gui, { name = "ZoneAction", text = "", style = "gold", size = UDim2.fromOffset(250, BTN), anchor = Vector2.new(0.5, 1), zIndex = 5, radius = K.Radius.pill, onClick = function()
		Hud.zoneAction()
	end })
	chip.Visible = false
	E.chip = chip
	E.chipScale = Instance.new("UIScale")
	E.chipScale.Parent = chip
	-- test drive chip
	local test = K.Panel(gui, { Name = "TestDrive", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(300, 68), Radius = K.Radius.pill, Visible = false })
	E.test = test
	E.testText = K.text(test, { Name = "Text", Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -148, 0, 20), ZIndex = 3 })
	E.testSub = K.text(test, { Name = "Sub", Text = "", TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(18, 30), Size = UDim2.new(1, -148, 0, 18), ZIndex = 3 })
	E.testBar = K.ProgressBar(test, { height = 4, color = K.Color.gold })
	E.testBar.frame.AnchorPoint = Vector2.new(0, 1)
	E.testBar.frame.Position = UDim2.new(0, 18, 1, -8)
	E.testBar.frame.Size = UDim2.new(1, -150, 0, 4)
	E.testBar.frame.ZIndex = 3
	E.testEnd = K.Button(test, { name = "EndTest", text = "시승 끝내기", style = "secondary", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -6, 0.5, 0), size = UDim2.fromOffset(120, BTN), zIndex = 4, radius = K.Radius.pill, onClick = function()
		task.spawn(Net.request, "endtest")
	end })
	gui.Parent = pg
	Layout.onChanged(place)
	Net.on("zone", Hud.onZone)
	Net.on("testdrive", Hud.onTest)
	Net.on("hit", Hud.onHit)
	Net.on("repair", function(p)
		if p.stage == "done" then
			Hud.onZone({ zone = nil })
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Zone chip
---------------------------------------------------------------------------------------------------
function Hud.onZone(p: any)
	local zone = p.zone
	S.zone = zone
	S.zoneQuote = p.quote
	local chip = E.chip
	if zone == "service" then
		local cost = (p.quote and p.quote.repair) or 0
		chip.Text = if cost > 0 then string.format("🔧  정비 받기 · %s", GS.formatWon(cost)) else "🔧  상태 100% · 정비 필요 없음"
	elseif zone == "wash" then
		chip.Text = string.format("🫧  세차하기 · %s", GS.formatWon(GS.WASH.fee))
	end
	if zone == "service" or zone == "wash" then
		place()
		local w = math.ceil(K.textSize(chip.Text, K.Type.bodySm, K.Font.bold).X) + 48
		chip.Size = UDim2.fromOffset(math.max(220, w), BTN)
		if not chip.Visible then
			chip.Visible = true
			E.chipScale.Scale = 0.85
			K.tween(E.chipScale, 0.22, { Scale = 1 })
			K.feedback("notify")
		end
		K.pulse(chip, true, 0.0, 0.25)
	else
		K.pulse(chip, false)
		chip.Visible = false
	end
end

function Hud.zoneAction()
	local zone = S.zone
	if zone ~= "service" and zone ~= "wash" then
		return
	end
	K.setButtonLoading(E.chip, true, "…")
	local res = Net.request(if zone == "service" then "repair" else "wash", {})
	K.setButtonLoading(E.chip, false)
	if res.ok then
		K.feedback("success")
		K.pulse(E.chip, false)
		E.chip.Visible = false
		K.toast({ kind = "success", icon = if zone == "service" then "🔧" else "🫧", title = if zone == "service" then "정비 시작!" else "세차 시작!", body = if zone == "service" then "리프트가 차를 올려요 · 잠시만 기다려 주세요" else "브러시가 지나가요 · 잠시만 기다려 주세요" })
	else
		K.feedback("error")
		K.toast({ kind = "warn", title = "할 수 없어요", body = tostring(res.message or "") })
	end
end

---------------------------------------------------------------------------------------------------
-- 시승 HUD
---------------------------------------------------------------------------------------------------
local ring: Part? = nil
local beam: Part? = nil
local renderConn: RBXScriptConnection? = nil

local function marker(pos: Vector3)
	if not ring then
		local r = Instance.new("Part")
		r.Name = "GarageRouteRing"
		r.Shape = Enum.PartType.Cylinder
		r.Size = Vector3.new(0.4, 16, 16)
		r.Material = Enum.Material.Neon
		r.Color = Color3.fromRGB(255, 180, 60)
		r.Transparency = 0.35
		r.Anchored = true
		r.CanCollide = false
		r.CanQuery = false
		r.CanTouch = false
		r.CastShadow = false
		r.Parent = workspace
		ring = r
		local b = Instance.new("Part")
		b.Name = "GarageRouteBeam"
		b.Size = Vector3.new(1.2, 60, 1.2)
		b.Material = Enum.Material.Neon
		b.Color = Color3.fromRGB(255, 200, 90)
		b.Transparency = 0.55
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Parent = workspace
		beam = b
	end
	(ring :: Part).CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2);
	(beam :: Part).CFrame = CFrame.new(pos + Vector3.new(0, 30, 0))
end

local function clearMarker()
	if ring then
		ring:Destroy()
		ring = nil
	end
	if beam then
		beam:Destroy()
		beam = nil
	end
end

function Hud.onTest(p: any)
	if p.stage == "start" then
		local route = {}
		for _, v in p.route or {} do
			if typeof(v) == "Vector3" then
				table.insert(route, v)
			end
		end
		S.test = { untilT = os.clock() + (tonumber(p.seconds) or 60), seconds = tonumber(p.seconds) or 60, route = route, idx = 1, kind = p.carKind }
		E.test.Visible = true
		place()
		K.pop(E.test, 0.9)
		local c = GS.CATALOG[p.carKind or ""]
		K.toast({ kind = "info", icon = "🏁", title = "시승 시작! " .. (if c then c.label else ""), body = "빛나는 기둥을 따라 동네 한 바퀴 · 60초" })
		if renderConn then
			renderConn:Disconnect()
		end
		renderConn = RunService.RenderStepped:Connect(Hud.stepTest)
	elseif p.stage == "end" then
		S.test = nil
		E.test.Visible = false
		clearMarker()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end
end

function Hud.stepTest()
	local t = S.test
	if not t then
		return
	end
	local left = math.max(0, t.untilT - os.clock())
	E.testText.Text = string.format("🏁 시승 중 · %d초", math.ceil(left))
	E.testBar.set(left / t.seconds, true)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = hrp and (hrp :: BasePart).Position
	local target = t.route[t.idx]
	if target and pos then
		local d = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z).Magnitude
		if d < 34 then
			t.idx += 1
			if t.idx > #t.route then
				t.idx = 1
			end
			K.feedback("tap")
			target = t.route[t.idx]
		end
		if target then
			marker(target)
			E.testSub.Text = string.format("다음 지점 %dm ▶ (%d/%d)", math.floor(d * 0.3 + 0.5), t.idx, #t.route)
		end
	elseif #t.route == 0 then
		E.testSub.Text = "마음껏 달려 보세요"
	end
end

---------------------------------------------------------------------------------------------------
-- Hit feedback
---------------------------------------------------------------------------------------------------
local lastHit = 0
function Hud.onHit(p: any)
	if os.clock() - lastHit < 2 then
		return
	end
	lastHit = os.clock()
	K.haptic("error")
	K.toast({ kind = "warn", icon = "💥", title = string.format("쾅! 차 상태 -%d%%", p.dmg or 0), body = string.format("현재 %d%% · 정비소에서 고칠 수 있어요", p.cond or 0) })
end

return Hud
