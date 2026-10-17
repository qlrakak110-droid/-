-- GwangalliCarDealer/TestHud (client): 시승 on the dealer side.
--   TestHud.request(entry, colorId?) -> result     asks the server (kit cars: the garage's own 60 s test drive with
--       its HUD and route; showroom models with a 3D template: our dealer test drive)
--   * dealer test drive: top chip "🏁 시승 중 · 이름 · 52초" with 시승 끝내기, the next route point (beacon ring in
--     Workspace.GwangalliCarDealerLocal + distance), all client-side
--   * both: when the test ends, the 시승 리포트 card (최고 속도 · 주행 거리 · 시간 · personal best) with
--     🛒 계약 상담 / 다른 차 보기 / 닫기, and the dealer's follow-up line
--   * after a garage test that WE started ends on time, the garage panel it would reopen is closed again (our
--     report takes its place); the garage panel is untouched otherwise

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local TestHud = {}

local player = Players.LocalPlayer
local ctx: any
local Ui: any
local C: any
local U: any
local Col: any

local gui: ScreenGui
local chip: Frame? = nil
local chipText: TextLabel? = nil
local chipSub: TextLabel? = nil
local report: Frame? = nil
local beacon: Model? = nil
local pending: { entry: string, at: number, name: string }? = nil
local ours: { mode: string, entry: string, name: string, untilT: number, route: { Vector3 }, idx: number, car: Model? }? = nil
local hbConn: RBXScriptConnection? = nil
local garageOurs: { entry: string, at: number }? = nil -- a garage-mode test we started

local function ensureGui()
	if not gui then
		gui = Ui.screen("GwangalliCarDealerTest", C.UI.order.hud)
		Ui.show(gui, true, false)
	end
end

local function localFolder(): Folder
	local name = ctx.S.NAMES.Local
	local f = workspace:FindFirstChild(name)
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f :: Folder
end

local function clearBeacon()
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
end

local function placeBeacon(pos: Vector3, label: string)
	clearBeacon()
	local m = Instance.new("Model")
	m.Name = "DealerRouteBeacon"
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 14, 14)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Col.accent
	ring.Transparency = 0.55
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = m
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Size = Vector3.new(0.6, 18, 0.6)
	pillar.CFrame = CFrame.new(pos + Vector3.new(0, 9, 0))
	pillar.Material = Enum.Material.Neon
	pillar.Color = Col.accent
	pillar.Transparency = 0.4
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Parent = m
	m.Parent = localFolder()
	local bb = Ui.make("BillboardGui", { Name = "GwDealerBeaconTag", Adornee = pillar, Size = UDim2.fromOffset(120, 34), StudsOffsetWorldSpace = Vector3.new(0, 11, 0), AlwaysOnTop = true, LightInfluence = 0, ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
	local box = Ui.frame(bb, { BackgroundTransparency = 0.1, BackgroundColor3 = Col.accentD })
	Ui.corner(box, 10)
	Ui.label(box, { Text = label, Font = Ui.F.bold, TextSize = 14, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	m.Destroying:Connect(function()
		bb:Destroy()
	end)
	beacon = m
end

local function hideChip()
	if chip then
		chip:Destroy()
		chip = nil
		chipText = nil
		chipSub = nil
	end
end

local function stopDealerHud()
	if hbConn then
		hbConn:Disconnect()
		hbConn = nil
	end
	hideChip()
	clearBeacon()
end

local function endTest()
	task.spawn(function()
		ctx.Net.call("endtest", nil)
	end)
end

local function showChip(name: string)
	ensureGui()
	hideChip()
	local m = Ui.metrics()
	local w = math.min(380, m.w - 24)
	local f = Ui.glass(gui, { Name = "TestChip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, m.inset + 8), Size = UDim2.fromOffset(w, 58), BackgroundColor3 = Col.bg2 })
	Ui.stroke(f, Col.accent, 1, 0.3)
	chipText = Ui.label(f, { Text = "🏁 시승 중 · " .. name, Font = Ui.F.bold, TextSize = 14, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -140, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	chipSub = Ui.label(f, { Text = "", Font = Ui.F.med, TextSize = 12, TextColor3 = Col.sub, Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -140, 0, 18) })
	local b = Ui.button(f, { text = "시승 끝내기", style = "secondary", size = UDim2.fromOffset(112, 40), anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -9, 0.5, 0), textSize = 13 })
	b.onClick(endTest)
	chip = f
end

local function startDealerHud(p: any)
	local route = {}
	if type(p.route) == "table" then
		for _, v in p.route do
			if typeof(v) == "Vector3" then
				table.insert(route, v)
			end
		end
	end
	ours = { mode = "dealer", entry = p.entry, name = p.name or "시승차", untilT = os.clock() + (tonumber(p.seconds) or 75), route = route, idx = 1, car = if typeof(p.car) == "Instance" then p.car else nil }
	showChip(ours.name)
	if #route > 0 then
		placeBeacon(route[1], string.format("📍 1/%d", #route))
	end
	if hbConn then
		hbConn:Disconnect()
	end
	hbConn = RunService.Heartbeat:Connect(function()
		local o = ours
		if not o or o.mode ~= "dealer" then
			return
		end
		local left = math.max(0, o.untilT - os.clock())
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local sub = string.format("남은 시간 %s", U.secs(left))
		if r and #o.route > 0 then
			local target = o.route[o.idx]
			local d = (Vector3.new(target.X, 0, target.Z) - Vector3.new((r :: BasePart).Position.X, 0, (r :: BasePart).Position.Z)).Magnitude
			if d < 20 then
				o.idx = (o.idx % #o.route) + 1
				placeBeacon(o.route[o.idx], string.format("📍 %d/%d", o.idx, #o.route))
				Ui.sfx("tap")
			end
			sub ..= string.format(" · 다음 지점 %dm (%d/%d)", math.floor(d * 0.3 + 0.5), o.idx, #o.route)
		end
		if chipSub then
			chipSub.Text = sub
		end
	end)
end

-- The garage panel reopens itself 1.2 s after a garage test ends on time; close it when the test was ours.
local function suppressGarageSheet()
	local ps = player:FindFirstChild("PlayerScripts")
	local gg = ps and ps:FindFirstChild("GwangalliGarage")
	local sm = gg and gg:FindFirstChild("Sheet")
	if not (sm and sm:IsA("ModuleScript")) then
		return
	end
	local ok, Sheet = pcall(require, sm)
	if not ok or type(Sheet) ~= "table" or type(Sheet.isOpen) ~= "function" or type(Sheet.close) ~= "function" then
		return
	end
	local t0 = os.clock()
	while os.clock() - t0 < 4 do
		task.wait(0.1)
		local okO, isOpen = pcall(Sheet.isOpen)
		if okO and isOpen then
			pcall(Sheet.close)
			return
		end
	end
end

local function closeReport()
	if report then
		report:Destroy()
		report = nil
	end
	ContextActionService:UnbindAction("GwCarDealerReport")
end

local function showReport(r: any, record: boolean?)
	ensureGui()
	closeReport()
	local e = ctx.Net.state.byId[r.entry]
	local name = r.name or (e and e.name) or "시승차"
	local m = Ui.metrics()
	local W = math.min(440, m.w - 24)
	local f = Ui.glass(gui, { Name = "TestReport", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, m.inset / 2), Size = UDim2.fromOffset(W, 300), BackgroundColor3 = Col.bg2, ZIndex = 5 })
	Ui.stroke(f, Col.accent, 2, 0.3)
	Ui.label(f, { Text = "🏁 시승 리포트", Font = Ui.F.black, TextSize = 20, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 26), ZIndex = 6 })
	Ui.label(f, { Text = name, Font = Ui.F.bold, TextSize = 14, TextColor3 = Col.sub, Position = UDim2.fromOffset(20, 42), Size = UDim2.new(1, -40, 0, 18), ZIndex = 6 })
	local stats = Ui.frame(f, { Position = UDim2.fromOffset(20, 70), Size = UDim2.new(1, -40, 0, 74), ZIndex = 6 })
	Ui.list(stats, "x", 10, Enum.HorizontalAlignment.Center)
	local function stat(order: number, big: string, small: string)
		local s = Ui.frame(stats, { Size = UDim2.new(1 / 3, -7, 1, 0), BackgroundTransparency = 0, BackgroundColor3 = Col.card, LayoutOrder = order, ZIndex = 6 })
		Ui.corner(s, 12)
		Ui.label(s, { Text = big, Font = Ui.F.black, TextSize = 20, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		Ui.label(s, { Text = small, Font = Ui.F.med, TextSize = 11, TextColor3 = Col.sub, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
	end
	stat(1, tostring(r.topKmh or 0) .. "km/h", "최고 속도")
	stat(2, U.meters(r.meters or 0), "주행 거리")
	stat(3, U.secs(r.seconds or 0), "시승 시간")
	local npc = ctx.CatalogUI.ctxNpc()
	local voice = (npc and npc.voice) or "consult"
	local follow = ctx.S.Lines.get(voice, "after_test", { car = (e and e.short) or name, kmh = r.topKmh or 0 })
	Ui.label(f, { Text = (if record then "🏆 개인 최고 기록 갱신! · " else "") .. "💬 " .. follow, Font = Ui.F.med, TextSize = 13, TextColor3 = if record then Col.gold else Col.ink, Position = UDim2.fromOffset(20, 154), Size = UDim2.new(1, -40, 0, 54), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6 })
	local row = Ui.frame(f, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -40, 0, 48), ZIndex = 6 })
	Ui.list(row, "x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local bw = math.floor((W - 40 - 16) / 3)
	local buy = Ui.button(row, { text = "계약 상담", icon = "🛒", style = "primary", size = UDim2.fromOffset(bw, 46), order = 1, textSize = 13, z = 7 })
	local other = Ui.button(row, { text = "다른 차 보기", style = "secondary", size = UDim2.fromOffset(bw, 46), order = 2, textSize = 13, z = 7 })
	local x = Ui.button(row, { text = "닫기", style = "ghost", size = UDim2.fromOffset(bw, 46), order = 3, textSize = 13, z = 7 })
	buy.onClick(function()
		closeReport()
		ctx.CatalogUI.open({ entry = r.entry, npc = npc })
	end)
	other.onClick(function()
		closeReport()
		ctx.CatalogUI.open({ cat = "all", npc = npc })
	end)
	x.onClick(closeReport)
	report = f
	Ui.select(buy.inst)
	Ui.sfx("success")
	ContextActionService:BindActionAtPriority("GwCarDealerReport", function(_, st)
		if st == Enum.UserInputState.Begin then
			closeReport()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 2100, Enum.KeyCode.ButtonB)
	local mine = f
	task.delay(30, function()
		if report == mine then
			closeReport()
		end
	end)
	if npc then
		ctx.NpcFx.say(npc.id, follow, 5)
	end
end

function TestHud.request(e: any, colorId: string?): { [string]: any }
	pending = { entry = e.id, at = os.clock(), name = e.name }
	local GS = ctx.GS
	local res = ctx.Net.call("testdrive", { entry = e.id, color = colorId or (GS and GS.DEFAULT_COLOR) or "white" })
	if not res.ok then
		pending = nil
		return res
	end
	if res.mode == "garage" then
		ours = { mode = "garage", entry = e.id, name = e.name, untilT = os.clock() + (tonumber(res.seconds) or 60), route = {}, idx = 1, car = nil }
		garageOurs = { entry = e.id, at = os.clock() }
		Ui.toast({ kind = "info", icon = "🏁", title = e.name .. " 시승 시작!", body = string.format("%d초 동안 코스를 달려 보세요 · 기록은 시승 리포트로 알려 드려요", tonumber(res.seconds) or 60) })
	end
	return res
end

function TestHud.init(c: any)
	ctx = c
	Ui = c.Ui
	C = c.C
	U = c.S.Util
	Col = Ui.C
	-- our server: dealer test start / end (both modes end here with the report)
	ctx.Net.on("test", function(p: any)
		if p.stage == "start" and p.mode == "dealer" then
			pending = nil
			ctx.CatalogUI.close()
			ctx.Dialog.close()
			startDealerHud(p)
		elseif p.stage == "end" then
			local wasOurs = ours
			ours = nil
			pending = nil
			stopDealerHud()
			local r = p.report
			if type(r) == "table" and (r.seconds or 0) >= 5 and p.why ~= "leave" then
				task.delay(if p.mode == "garage" then 1.4 else 0.6, function()
					showReport(r, p.record == true)
				end)
			end
			local _ = wasOurs
			ctx.Net.refresh()
		end
	end)
	-- the garage's own events for garage-mode tests
	ctx.Net.onGarage("testdrive", function(p: any)
		if p.stage == "start" then
			if pending and os.clock() - pending.at < 8 then
				ctx.CatalogUI.close()
				ctx.Dialog.close()
			end
		elseif p.stage == "end" then
			local g = garageOurs
			garageOurs = nil
			if g and os.clock() - g.at < 600 and p.why == "time" then
				task.spawn(suppressGarageSheet)
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		if ours and ours.mode == "dealer" then
			stopDealerHud()
		end
	end)
end

return TestHud
