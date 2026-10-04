-- GwangalliFeatures/TaxiRide: everything after the call (owner: taxi_call; docs/features_contract.md §4).
--   * every taxi in Workspace.GwangalliTaxis is re-sampled each frame from its published path
--     (TaxiPath / TaxiT0, workspace:GetServerTimeNow) so it glides along the lanes on phones; spawn
--     fade-in, hazard lights (TaxiHazard), "빵빵!" honk bubble (TaxiHonk), the driver waves (TaxiWave)
--   * my taxi: a compact card in the "bottomCenter" slot — driver / car / plate / live ETA while it
--     comes, "탑승" when it is at the kerb, the meter (기본 4,800원 + 100원 steps) with ⏩ 빨리 가기
--     (after 5 s) and 🎥 camera while riding; tap = details (call the driver, cancel with the fee rule)
--   * arrival: 결제 sheet (💳 카드 = 통장 / 💵 현금, auto card after the timeout), then the 영수증 card
--     with ★ rating
--   * ride camera: follows the taxi (orbit, min zoom 16) or a cinematic chase; restored afterwards
--   * visibility guard (bug "택시 타도 차가 안 보이는 경우"): my taxi is looked up by name as well as
--     by the folder events, the client acks the model to the server ("seen") before it is seated, and
--     a 2 Hz watchdog while boarded re-applies the ride camera, clears stray LocalTransparencyModifier
--     (an interrupted fade-in) and shows "택시 오는 중…" on the card until the model is present
-- Flows: "taxiRide" (details of the current taxi), "taxiReceipt" (last receipt).
-- Server: TaxiState (RemoteEvent) + TaxiCall (RemoteFunction: board / skip / pay / rate / cancel / state).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local M = {}
M.flows = { "taxiRide", "taxiReceipt" }

local F: any
local K: any
local Layout: any
local player: Player

local GOLD1 = Color3.fromRGB(255, 206, 84)
local GOLD2 = Color3.fromRGB(240, 140, 30)
local BOARD_DIST = 22

-------------------------------------------------------------------------------------------------
-- Path sampling (same maths as the server's TaxiDispatch.sample)
-------------------------------------------------------------------------------------------------
local UP = Vector3.new(0, 1, 0)

local function unitFlat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	local m = f.Magnitude
	if m < 1e-4 then
		return nil
	end
	return f / m
end

local function cframe(pos: Vector3, dir: Vector3): CFrame
	local look = unitFlat(dir) or Vector3.new(0, 0, -1)
	return CFrame.fromMatrix(pos, look:Cross(UP), UP, -look)
end

local function posAt(pts: { Vector3 }, times: { number }, t: number): (Vector3, number)
	local n = #pts
	if n == 0 then
		return Vector3.zero, 1
	end
	if t <= times[1] or n == 1 then
		return pts[1], 1
	end
	if t >= times[n] then
		return pts[n], n - 1
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local span = times[hi] - times[lo]
	local u = if span > 1e-6 then (t - times[lo]) / span else 1
	return pts[lo]:Lerp(pts[hi], u), lo
end

local function sample(pts: { Vector3 }, times: { number }, t: number): (Vector3, Vector3)
	local p, i = posAt(pts, times, t)
	local a = posAt(pts, times, t - 0.3)
	local b = posAt(pts, times, t + 0.3)
	local dir = unitFlat(b - a)
	if not dir or Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude < 0.4 then
		local n = #pts
		local j = math.clamp(i, 1, math.max(1, n - 1))
		dir = nil
		for k = j, 1, -1 do
			if k + 1 <= n then
				dir = unitFlat(pts[k + 1] - pts[k])
				if dir and Vector3.new(pts[k + 1].X - pts[k].X, 0, pts[k + 1].Z - pts[k].Z).Magnitude > 0.4 then
					break
				end
			end
		end
		if not dir then
			for k = j, n - 1 do
				dir = unitFlat(pts[k + 1] - pts[k])
				if dir then
					break
				end
			end
		end
	end
	return p, dir or Vector3.new(0, 0, -1)
end

local function distanceAt(pts: { Vector3 }, times: { number }, t: number): number
	local p, i = posAt(pts, times, t)
	local d = 0
	for k = 2, i do
		d += Vector3.new(pts[k].X - pts[k - 1].X, 0, pts[k].Z - pts[k - 1].Z).Magnitude
	end
	return d + Vector3.new(p.X - pts[i].X, 0, p.Z - pts[i].Z).Magnitude
end

local function decode(s: string): ({ Vector3 }, { number })
	local pts, times = {}, {}
	for x, y, z, t in string.gmatch(s, "([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)") do
		local nx, ny, nz, nt = tonumber(x), tonumber(y), tonumber(z), tonumber(t)
		if nx and ny and nz and nt then
			table.insert(pts, Vector3.new(nx, ny, nz))
			table.insert(times, nt)
		end
	end
	return pts, times
end

local function polyLength(pts: { Vector3 }): number
	local len = 0
	for i = 2, #pts do
		len += Vector3.new(pts[i].X - pts[i - 1].X, 0, pts[i].Z - pts[i - 1].Z).Magnitude
	end
	return len
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

-------------------------------------------------------------------------------------------------
-- Cars (every taxi in the world)
-------------------------------------------------------------------------------------------------
type Car = {
	model: Model,
	root: BasePart?,
	pts: { Vector3 },
	times: { number },
	t0: number,
	total: number,
	length: number,
	serial: number,
	lamps: { BasePart },
	hazard: boolean,
	conns: { RBXScriptConnection },
	faded: boolean,
	parts: { BasePart }, -- every BasePart (visibility watchdog)
	fading: boolean, -- spawn fade-in running (LocalTransparencyModifier is ours for 0.7 s)
	mine: boolean,
}
local cars: { [Model]: Car } = {}
local ROOT_LIFT = 0.5
-- forward declarations (defined with the state code below)
local onMyCarPresent: (Car) -> () = function() end

local function loadPath(car: Car)
	local s = car.model:GetAttribute("TaxiPath")
	local t0 = car.model:GetAttribute("TaxiT0")
	if type(s) ~= "string" or type(t0) ~= "number" then
		car.pts, car.times, car.total = {}, {}, 0
		return
	end
	local serial = car.model:GetAttribute("TaxiSerial")
	if serial ~= car.serial or #car.pts == 0 then
		car.pts, car.times = decode(s)
		car.total = if #car.times > 0 then car.times[#car.times] else 0
		car.length = polyLength(car.pts)
		car.serial = serial
	end
	car.t0 = t0
end

local function honkBubble(car: Car)
	local root = car.root
	if not root or not root.Parent then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "TaxiHonk"
	bb.Size = UDim2.fromOffset(96, 40)
	bb.StudsOffset = Vector3.new(0, 7.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	local l = K.text(bb, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.1, BackgroundColor3 = Color3.fromRGB(20, 22, 36), Text = "빵빵! 🚕", Font = K.Font.heavy, TextSize = 18, TextColor3 = GOLD1, TextXAlignment = Enum.TextXAlignment.Center })
	K.corner(l, UDim.new(0.5, 0))
	K.stroke(l, GOLD1, 1.5, 0.2)
	local sc = K.make("UIScale", { Scale = 0.4 }, l)
	bb.Parent = root
	K.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.5, function()
		K.tween(sc, 0.2, { Scale = 0.2 })
		task.wait(0.22)
		bb:Destroy()
	end)
end

local function wave(car: Car)
	local model = car.model
	local arm, hand
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if p:GetAttribute("WaveArm") then
				arm = p
			elseif p:GetAttribute("WaveHand") then
				hand = p
			end
		end
	end
	local armW = arm and arm:FindFirstChildOfClass("Weld")
	local handW = hand and hand:FindFirstChildOfClass("Weld")
	if not armW then
		return
	end
	local c0a = armW.C0
	local c0h = handW and handW.C0
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 2.4 and armW.Parent do
			local t = os.clock() - t0
			local lift = math.min(1, t / 0.35) * math.min(1, (2.4 - t) / 0.35)
			local theta = math.rad(lift * (145 + math.sin(t * 11) * 18))
			armW.C0 = c0a * CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, theta) * CFrame.new(0, -0.75, 0)
			if handW and c0h then
				handW.C0 = c0h * CFrame.new(0, 1.65, 0) * CFrame.Angles(0, 0, theta) * CFrame.new(0, -1.65, 0)
			end
			RunService.RenderStepped:Wait()
		end
		if armW.Parent then
			armW.C0 = c0a
		end
		if handW and c0h and handW.Parent then
			handW.C0 = c0h
		end
	end)
end

local function collectParts(car: Car)
	local parts = {}
	for _, p in car.model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	car.parts = parts
end

-- Clears any LocalTransparencyModifier left on the car (an interrupted fade, a stale hide); the
-- hazard lamps keep their Transparency (blinked by stepCars). Returns the number of parts fixed.
local function restoreVisibility(car: Car): number
	if car.fading then
		return 0
	end
	local fixed = 0
	for _, p in car.parts do
		if p.Parent and p.LocalTransparencyModifier ~= 0 then
			p.LocalTransparencyModifier = 0
			fixed += 1
		end
	end
	return fixed
end

local function fadeIn(car: Car)
	if car.fading then
		return
	end
	car.fading = true
	local parts = car.parts
	for _, p in parts do
		p.LocalTransparencyModifier = 1
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.7 and cars[car.model] == car do
			local v = 1 - (os.clock() - t0) / 0.7
			for _, p in parts do
				p.LocalTransparencyModifier = v
			end
			RunService.RenderStepped:Wait()
		end
		for _, p in parts do
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
		end
		car.fading = false
	end)
end

local function untrack(model: Model)
	local car = cars[model]
	if car then
		for _, c in car.conns do
			c:Disconnect()
		end
		cars[model] = nil
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local car: Car = { model = model, root = model:FindFirstChild("TaxiRoot") :: BasePart?, pts = {}, times = {}, t0 = 0, total = 0, length = 0, serial = -1, lamps = {}, hazard = false, conns = {}, faded = false, parts = {}, fading = false, mine = false }
	collectParts(car)
	for _, p in car.parts do
		if p:GetAttribute("HazardLamp") then
			table.insert(car.lamps, p)
		end
	end
	car.mine = model:GetAttribute("TaxiOwner") == player.UserId
	cars[model] = car
	-- parts that arrive later (a non-atomic engine, the Detail model streaming in after the body)
	table.insert(car.conns, model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			table.insert(car.parts, d)
			if d:GetAttribute("HazardLamp") then
				table.insert(car.lamps, d)
			end
			if d.Name == "TaxiRoot" then
				car.root = d
			end
		end
	end))
	loadPath(car)
	car.hazard = model:GetAttribute("TaxiHazard") == true
	table.insert(car.conns, model.AttributeChanged:Connect(function(name: string)
		if name == "TaxiPath" or name == "TaxiT0" or name == "TaxiSerial" then
			loadPath(car)
		elseif name == "TaxiHazard" then
			car.hazard = model:GetAttribute("TaxiHazard") == true
			if not car.hazard then
				for _, l in car.lamps do
					l.Transparency = 1
				end
			end
		elseif name == "TaxiHonk" then
			honkBubble(car)
		elseif name == "TaxiWave" then
			wave(car)
		end
	end))
	table.insert(car.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end))
	-- a taxi that just appeared fades in instead of popping
	if model:GetAttribute("TaxiSpawnFade") and car.total > 0 and serverNow() - car.t0 < 1.5 then
		fadeIn(car)
	end
	if car.mine then
		onMyCarPresent(car)
	end
end

local lastBlink = 0
local blinkOn = false
local function stepCars()
	local tNow = serverNow()
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local blinkFlip = false
	if os.clock() - lastBlink > 0.42 then
		lastBlink = os.clock()
		blinkOn = not blinkOn
		blinkFlip = true
	end
	for _, car in cars do
		local root = car.root
		if not root or not root.Parent then
			car.root = car.model:FindFirstChild("TaxiRoot") :: BasePart?
			root = car.root
		end
		if root and #car.pts > 1 then
			local t = tNow - car.t0
			if t <= car.total + 0.3 and (root.Position - camPos).Magnitude < 900 then
				local p, dir = sample(car.pts, car.times, math.min(t, car.total))
				root.CFrame = cframe(p + Vector3.new(0, ROOT_LIFT, 0), dir)
			end
		end
		if blinkFlip and car.hazard and root and (root.Position - camPos).Magnitude < 320 then
			for _, l in car.lamps do
				l.Transparency = if blinkOn then 0 else 1
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- My taxi: state
-------------------------------------------------------------------------------------------------
local taxiCallRemote: RemoteFunction? = nil
local job: any = nil -- last job view
local jobState = "idle"
local lastReceipt: any = nil
local seenFor: string? = nil -- ride id the server was told "seen" about
local carHidden = false -- my taxi is missing on this client while I am boarded / riding
local carMissingSince: number? = nil
local camPending = false -- the ride started before the car was here: follow it when it appears

local function call(op: string, payload: any?): { [string]: any }
	local r = taxiCallRemote
	if not r then
		local G = F.G
		local inst = F.remote((G and G.Remote and G.Remote.TaxiCall) or "TaxiCall", 5)
		if inst and inst:IsA("RemoteFunction") then
			r = inst
			taxiCallRemote = inst
		end
	end
	if not r then
		return { ok = false, message = "택시 회사와 연결할 수 없어요" }
	end
	local ok, res = pcall(r.InvokeServer, r, op, payload)
	if ok and type(res) == "table" then
		return res
	end
	return { ok = false, message = "연결이 불안정해요" }
end

-- My taxi: the tracked car owned by me, else the folder child named after me (a model that arrived
-- without a ChildAdded we handled, e.g. a fresh streamed-in copy) which is tracked on the spot.
local function myCar(): Car?
	for model, car in cars do
		if car.mine and model.Parent then
			return car
		end
	end
	local folder = workspace:FindFirstChild("GwangalliTaxis")
	local m = folder and folder:FindFirstChild("GwangalliTaxi_" .. player.UserId)
	if m and m:IsA("Model") then
		track(m)
		local car = cars[m]
		if car and not car.mine then
			car.mine = true
		end
		return car
	end
	return nil
end

-- True when my taxi and its root exist on this client (the thing the server wants to know).
local function carPresent(): boolean
	local car = myCar()
	if not car then
		return false
	end
	local root = car.root
	if not (root and root.Parent) then
		car.root = car.model:FindFirstChild("TaxiRoot") :: BasePart?
		root = car.root
	end
	return root ~= nil and root.Parent ~= nil and car.model:IsDescendantOf(workspace)
end

local function rootPos(): Vector3?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else nil
end

-------------------------------------------------------------------------------------------------
-- Card ("bottomCenter")
-------------------------------------------------------------------------------------------------
local card: TextButton
local cardIcon: Frame
local cardIconGlyph: TextLabel
local cardTitle: TextLabel
local cardSub: TextLabel
local cardRight: TextLabel
local cardRightCap: TextLabel
local cardBar: any
local boardBtn: TextButton
local skipBtn: TextButton
local skipRing: any
local camBtn: TextButton
local destBtn: TextButton
local cardVisible = false
local meterShown = -1
local noticeUntil = 0

local function layoutCard()
	if not card then
		return
	end
	local ok, r = pcall(Layout.rect, "bottomCenter")
	if not ok or type(r) ~= "table" then
		r = { x = 200, y = 300, w = 360, h = 60 }
	end
	local w = math.max(260, r.w)
	card.Size = UDim2.fromOffset(w, math.max(56, r.h))
	card.Position = UDim2.fromOffset(r.x + r.w / 2 - w / 2, r.y)
end

local function setCardVisible(on: boolean)
	if on == cardVisible then
		return
	end
	cardVisible = on
	if on then
		layoutCard()
		card.Visible = true
		local sc = K.scaleOf and K.scaleOf(card) or card:FindFirstChildOfClass("UIScale")
		if sc and K.springIn then
			K.springIn(card, 0.85)
		elseif K.pop then
			K.pop(card, 0.9)
		end
	else
		card.Visible = false
	end
end

local function rightButtons(which: string?)
	boardBtn.Visible = which == "board"
	destBtn.Visible = which == "dest"
	skipBtn.Visible = which == "ride"
	camBtn.Visible = which == "ride"
	cardRight.Visible = which == nil or which == "eta"
	cardRightCap.Visible = which == nil or which == "eta"
	local rw = if which == "ride" then 104 elseif which == "board" or which == "dest" then 88 elseif which == "eta" then 72 else 8
	cardTitle.Size = UDim2.new(1, -(56 + rw), 0, 20)
	cardSub.Size = UDim2.new(1, -(56 + rw), 0, 16)
end

local function buildCard()
	card = K.make("TextButton", { Name = "TaxiCard", AutoButtonColor = false, Text = "", BackgroundColor3 = K.Color.glass, BackgroundTransparency = 0.06, Visible = false, ZIndex = 20 }, F.gui)
	K.corner(card, K.Radius.lg)
	K.stroke(card, GOLD1, 1, 0.55)
	cardIcon = K.iconTile(card, 40, "🚕", GOLD1, true)
	cardIcon.AnchorPoint = Vector2.new(0, 0.5)
	cardIcon.Position = UDim2.new(0, 10, 0.5, 0)
	cardIconGlyph = cardIcon:FindFirstChild("Glyph") :: TextLabel
	cardTitle = K.text(card, { Name = "Title", Position = UDim2.new(0, 58, 0.5, -19), Size = UDim2.new(1, -140, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd })
	cardSub = K.text(card, { Name = "Sub", Position = UDim2.new(0, 58, 0.5, 2), Size = UDim2.new(1, -140, 0, 16), Text = "", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
	cardRight = K.text(card, { Name = "Eta", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0.5, -19), Size = UDim2.fromOffset(64, 22), Text = "", Font = K.Font.bold, TextSize = 19, TextColor3 = GOLD1, TextXAlignment = Enum.TextXAlignment.Right })
	K.mono(cardRight)
	cardRightCap = K.text(card, { Name = "EtaCap", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0.5, 4), Size = UDim2.fromOffset(64, 14), Text = "도착 예정", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Right })
	cardBar = K.ProgressBar(card, { height = 3, color = GOLD1 })
	cardBar.frame.AnchorPoint = Vector2.new(0.5, 1)
	cardBar.frame.Position = UDim2.new(0.5, 0, 1, -3)
	cardBar.frame.Size = UDim2.new(1, -28, 0, 3)
	boardBtn = K.Button(card, { name = "Board", style = "gold", text = "탑승", icon = "🚕", size = UDim2.fromOffset(80, 44), anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), zIndex = 22, textSize = K.Type.bodySm })
	destBtn = K.Button(card, { name = "Dest", style = "gold", text = "목적지", size = UDim2.fromOffset(80, 44), anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), zIndex = 22, textSize = K.Type.bodySm })
	skipBtn = K.Button(card, { name = "Skip", style = "glass", text = "⏩", size = UDim2.fromOffset(44, 44), anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), zIndex = 22, textSize = 17 })
	K.corner(skipBtn, UDim.new(0.5, 0))
	skipRing = K.Ring(skipBtn, { size = 44, thickness = 2, color = GOLD1 })
	skipRing.frame.ZIndex = 23
	skipRing.label.Text = ""
	camBtn = K.Button(card, { name = "Camera", style = "glass", text = "🎥", size = UDim2.fromOffset(44, 44), anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -58, 0.5, 0), zIndex = 22, textSize = 16 })
	K.corner(camBtn, UDim.new(0.5, 0))
	rightButtons(nil)
	boardBtn.Activated:Connect(function()
		if boardBtn:GetAttribute("Disabled") then
			return
		end
		K.setButtonLoading(boardBtn, true, "…")
		task.spawn(function()
			local r = call("board")
			K.setButtonLoading(boardBtn, false)
			if not r.ok then
				F.toast({ kind = "taxi", title = "탑승", body = r.message or "탑승할 수 없어요" })
			end
		end)
	end)
	destBtn.Activated:Connect(function()
		F.open("taxiDest", {})
	end)
	skipBtn.Activated:Connect(function()
		if skipBtn:GetAttribute("Disabled") then
			return
		end
		K.setButtonEnabled(skipBtn, false)
		task.spawn(function()
			local r = call("skip")
			if not r.ok then
				F.toast({ kind = "taxi", title = "빨리 가기", body = r.message or "지금은 안 돼요" })
				K.setButtonEnabled(skipBtn, true)
			end
		end)
	end)
	camBtn.Activated:Connect(function()
		M._toggleCamera()
	end)
	card.Activated:Connect(function()
		if jobState == "coming" or jobState == "arrived" then
			M.open("taxiRide", {})
		end
	end)
	K.pressable(card, { scale = 0.98, veil = false })
end

local function fmtClock(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

-- Per-frame-ish card refresh (10 Hz loop while visible).
local function refreshCard()
	if not card then
		return
	end
	local j = job
	local now = serverNow()
	if os.clock() < noticeUntil then
		return
	end
	if not j or jobState == "idle" or jobState == "done" or jobState == "paying" or jobState == "cancelled" then
		setCardVisible(false)
		return
	end
	setCardVisible(true)
	if jobState == "coming" then
		cardIconGlyph.Text = "🚕"
		cardTitle.Text = string.format("%s · ★%.1f", j.driverTitle or "기사님", tonumber(j.rating) or 5)
		cardSub.Text = string.format("%s %s · %s", j.color or "", j.car or "", j.plate or "")
		local eta = math.max(0, (j.arriveAt or now) - now)
		cardRight.Text = fmtClock(eta)
		cardRightCap.Text = if eta < 4 then "곧 도착" else "도착 예정"
		local span = math.max(1, (j.arriveAt or now) - (j.bookedAt or (j.arriveAt or now) - 15))
		cardBar.frame.Visible = true
		cardBar.set(1 - math.clamp(eta / span, 0, 1), true)
		rightButtons("eta")
	elseif jobState == "arrived" and not j.boarded then
		cardIconGlyph.Text = "🚖"
		cardTitle.Text = "택시가 도착했어요!"
		local car = myCar()
		local here = rootPos()
		local d = if car and car.root and here then (car.root.Position - here).Magnitude else nil
		cardSub.Text = string.format("%s %s %s · 비상등 켜진 차%s", j.color or "", j.car or "", j.plate or "", if d then " · " .. K.meters(d) else "")
		cardBar.frame.Visible = true
		local left = math.max(0, (j.waitUntil or now) - now)
		cardBar.set(math.clamp(left / 90, 0, 1), true)
		rightButtons("board")
		local near = d ~= nil and d <= BOARD_DIST + 4
		K.setButtonEnabled(boardBtn, near)
		boardBtn.Text = if near then "🚕  탑승" else "가까이"
	elseif jobState == "arrived" and j.boarded then
		cardIconGlyph.Text = "🧑‍✈️"
		cardTitle.Text = "기사님: 어디로 모실까요?"
		cardSub.Text = "목적지를 말씀해 주세요"
		cardBar.frame.Visible = false
		rightButtons("dest")
	elseif jobState == "riding" then
		cardIconGlyph.Text = "🧾"
		local car = myCar()
		local fare = tonumber(j.fare) or 4800
		local base = (j.lines and tonumber(j.lines.base)) or 4800
		local meter = base
		local remaining = 0
		local total = 0
		if car and #car.pts > 1 and car.length > 0 then
			local t = now - car.t0
			local dd = distanceAt(car.pts, car.times, math.clamp(t, 0, car.total))
			local p = math.clamp(dd / car.length, 0, 1)
			local extra = math.max(0, fare - base)
			meter = if p >= 0.999 then fare else math.min(fare, base + math.floor(extra * p / 100) * 100)
			remaining = math.max(0, car.length - dd)
			total = car.length
		end
		if meter ~= meterShown then
			if meterShown >= 0 and meter > meterShown then
				-- the meter clicks up in 100원 steps
				K.sound("tap")
				cardTitle.TextColor3 = GOLD1
				task.delay(0.25, function()
					cardTitle.TextColor3 = K.Color.text
				end)
			end
			meterShown = meter
		end
		cardTitle.Text = "미터 " .. K.won(meter)
		local secsLeft = math.max(0, (j.rideEnd or now) - now)
		if carHidden then
			cardSub.Text = "택시 오는 중… 잠시만요 🚕"
		else
			cardSub.Text = string.format("%s · %s · %s", j.destination or "목적지", K.meters(remaining), fmtClock(secsLeft))
		end
		cardBar.frame.Visible = true
		cardBar.set(if total > 0 then 1 - remaining / total else 0, true)
		rightButtons("ride")
		local skipAt = tonumber(j.skipAt) or now
		local wait = skipAt - now
		local canSkip = wait <= 0 and secsLeft > 4
		K.setButtonEnabled(skipBtn, canSkip)
		skipRing.set(if wait > 0 then 1 - math.clamp(wait / 5, 0, 1) else 1)
		skipRing.frame.Visible = wait > 0
	end
end

local function notice(icon: string, title: string, sub: string)
	if not card then
		return
	end
	noticeUntil = os.clock() + 4
	cardVisible = false
	setCardVisible(true)
	cardIconGlyph.Text = icon
	cardTitle.Text = title
	cardSub.Text = sub
	cardBar.frame.Visible = false
	rightButtons(nil)
	task.delay(4.05, function()
		if os.clock() >= noticeUntil then
			refreshCard()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Modal panels (details / payment / receipt)
-------------------------------------------------------------------------------------------------
local panelDim: Frame? = nil
local panel: Frame? = nil
local panelKey: string? = nil

local function closePanel()
	local d = panelDim
	panelDim, panel = nil, nil
	if panelKey then
		F.modal(false, panelKey)
		panelKey = nil
	end
	if d then
		K.tween(d, 0.16, { BackgroundTransparency = 1 })
		task.delay(0.17, function()
			d:Destroy()
		end)
	end
end

-- A centred dark-glass panel on a dim; returns the content frame (vertical list).
local function openPanel(key: string, modal: boolean, width: number?): Frame
	closePanel()
	local vp = F.gui.AbsoluteSize
	local dimF = K.frame(F.gui, { Name = "TaxiPanelDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Active = true, ZIndex = 90 })
	local w = math.min(width or 340, math.max(240, vp.X - 24))
	local maxH = math.max(200, vp.Y - 16)
	local p = K.Panel(dimF, { Name = "TaxiPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, 10), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.03, Radius = K.Radius.xl, ZIndex = 91 })
	K.make("UISizeConstraint", { MaxSize = Vector2.new(w, maxH) }, p)
	local compactY = vp.Y < 420
	K.pad(p, 16, 16, if compactY then 10 else 16, if compactY then 10 else 14)
	K.list(p, false, if compactY then 6 else 10, Enum.HorizontalAlignment.Center)
	K.tween(dimF, 0.2, { BackgroundTransparency = 0.45 })
	if K.springIn then
		K.springIn(p, 0.9)
	else
		K.pop(p, 0.9)
	end
	K.feedback("open")
	panelDim, panel = dimF, p
	if modal then
		panelKey = key
		F.modal(true, key)
	end
	return p
end

local function row(parent: Frame, order: number, label: string, value: string, color: Color3?, bold: boolean?): Frame
	local r = K.frame(parent, { Name = "Row" .. order, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order })
	K.text(r, { Name = "Label", Size = UDim2.new(0.5, 0, 1, 0), Text = label, TextColor3 = K.Color.sub, TextSize = K.Type.caption })
	local v = K.text(r, { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0), Text = value, TextColor3 = color or K.Color.text, Font = if bold then K.Font.bold else K.Font.medium, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
	K.mono(v, if bold then Enum.FontWeight.Bold else Enum.FontWeight.Medium)
	return r
end

local function hairline(parent: Frame, order: number)
	local h = K.frame(parent, { Name = "Line" .. order, Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.85, BackgroundColor3 = K.Color.line, LayoutOrder = order })
	return h
end

local function plateChip(parent: Instance, plate: string, order: number?): TextLabel
	local chip = K.text(parent, { Name = "Plate", Size = UDim2.fromOffset(K.textWidth and (K.textWidth(plate, 13) + 22) or 120, 24), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(250, 206, 40), Text = plate, TextColor3 = Color3.fromRGB(20, 20, 24), Font = K.Font.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = order or 0 })
	K.corner(chip, 5)
	K.stroke(chip, Color3.fromRGB(20, 20, 24), 1.5, 0.2)
	return chip
end

local function showDetails()
	local j = job
	if not j or (jobState ~= "coming" and jobState ~= "arrived") then
		return
	end
	local p = openPanel("taxiDetails", false, 340)
	local top = K.frame(p, { Name = "Top", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1 })
	local av = K.avatar(top, 52, "🧑‍✈️", Color3.fromRGB(150, 196, 236))
	av.Position = UDim2.fromOffset(0, 2)
	K.text(top, { Position = UDim2.fromOffset(62, 4), Size = UDim2.new(1, -62, 0, 22), Text = string.format("%s  ★%.1f", j.driverTitle or "기사님", tonumber(j.rating) or 5), Font = K.Font.bold, TextSize = K.Type.body, TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(top, { Position = UDim2.fromOffset(62, 28), Size = UDim2.new(1, -62, 0, 16), Text = string.format("경력 %d년 · 안심번호 %s", tonumber(j.years) or 5, j.phone or "050-0000-0000"), TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
	local carRow = K.frame(p, { Name = "Car", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 2 })
	K.list(carRow, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	K.text(carRow, { Size = UDim2.fromOffset(150, 24), AutomaticSize = Enum.AutomaticSize.X, Text = string.format("🚕 %s %s", j.color or "", j.car or "택시"), Font = K.Font.bold, TextSize = K.Type.bodySm, LayoutOrder = 1 })
	plateChip(carRow, j.plate or "", 2)
	hairline(p, 3)
	local now = serverNow()
	local etaText = if jobState == "coming" then ("약 " .. math.max(0, math.floor((j.arriveAt or now) - now)) .. "초 후 도착") else "도착해서 기다리는 중"
	row(p, 4, "상태", etaText, GOLD1, true)
	row(p, 5, "목적지", j.destination or "타서 말씀해 주세요")
	if j.fare then
		row(p, 6, "예상 요금", K.won(j.fare), nil, true)
	end
	local free = (j.freeCancelUntil or 0) - now
	row(p, 7, "취소 수수료", if free > 0 then string.format("%d초 동안 무료", math.ceil(free)) else K.won(j.cancelFee or 1000), if free > 0 then K.Color.green else K.Color.orange)
	local btns = K.frame(p, { Name = "Buttons", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 9 })
	local callB = K.Button(btns, { name = "CallDriver", style = "success", icon = "📞", text = "전화", size = UDim2.new(1 / 3, -4, 1, 0), position = UDim2.fromScale(0, 0) })
	local cancelB = K.Button(btns, { name = "Cancel", style = "danger", text = "호출 취소", size = UDim2.new(1 / 3, -4, 1, 0), position = UDim2.new(1 / 3, 2, 0, 0) })
	local closeB = K.Button(btns, { name = "Close", style = "secondary", text = "닫기", size = UDim2.new(1 / 3, -4, 1, 0), position = UDim2.new(2 / 3, 4, 0, 0) })
	callB.Activated:Connect(function()
		closePanel()
		local n = serverNow()
		local line
		if jobState == "coming" then
			local eta = math.max(0, math.floor((j.arriveAt or n) - n))
			line = if eta <= 5 then "네~ 거의 다 왔어요! 비상등 켜고 설게요." else string.format("네~ %s입니다. 지금 가고 있어요, %d초면 도착해요!", j.driverTitle or "기사", eta)
		else
			line = string.format("도착했어요~ %s %s, 비상등 켜고 있는 차예요. 천천히 오세요!", j.color or "", j.car or "")
		end
		F.toast({ kind = "taxi", title = "📞 " .. (j.driverTitle or "기사님"), body = line })
	end)
	cancelB.Activated:Connect(function()
		closePanel()
		local n = serverNow()
		local fee = if n > (j.freeCancelUntil or 0) then (j.cancelFee or 1000) else 0
		K.confirm(F.gui, {
			title = "택시 호출을 취소할까요?",
			body = if fee > 0 then string.format("배차된 지 시간이 지나서 취소 수수료 %s이 있어요.", K.won(fee)) else "지금 취소하면 수수료가 없어요.",
			icon = "🚕",
			iconColor = GOLD1,
			confirmText = "호출 취소",
			cancelText = "기다릴게요",
			destructive = true,
			zIndex = 95,
			onConfirm = function()
				task.spawn(function()
					local r = call("cancel")
					if not r.ok then
						F.toast({ kind = "taxi", title = "취소", body = r.message or "취소하지 못했어요" })
					end
				end)
			end,
		})
	end)
	closeB.Activated:Connect(closePanel)
end

local payTimer = 0
local function showPay(j: any, cash: number?, bank: number?)
	local p = openPanel("taxiPay", true, 340)
	local fare = tonumber(j.fare) or 0
	local head = K.frame(p, { Name = "Head", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1 })
	local av = K.avatar(head, 40, "🧑‍✈️", Color3.fromRGB(150, 196, 236))
	av.Position = UDim2.fromOffset(0, 2)
	K.text(head, { Position = UDim2.fromOffset(50, 2), Size = UDim2.new(1, -50, 0, 20), Text = "도착했습니다! 🚕", Font = K.Font.bold, TextSize = K.Type.body })
	K.text(head, { Position = UDim2.fromOffset(50, 23), Size = UDim2.new(1, -50, 0, 16), Text = (j.driverTitle or "기사님") .. ": 결제 도와드릴게요~", TextColor3 = K.Color.sub, TextSize = K.Type.caption, TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(p, { Name = "Dest", Size = UDim2.new(1, 0, 0, 16), Text = "📍 " .. (j.destination or "목적지"), TextColor3 = K.Color.faint, TextSize = K.Type.caption, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
	local big = K.text(p, { Name = "Fare", Size = UDim2.new(1, 0, 0, 36), Text = K.won(fare), Font = K.Font.bold, TextSize = 30, TextColor3 = GOLD1, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
	K.mono(big)
	if K.countUp then
		K.countUp(big, fare, { from = (j.lines and j.lines.base) or 4800, format = K.won, duration = 0.7 })
	end
	local lines = j.lines or {}
	local box = K.frame(p, { Name = "Lines", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 })
	K.list(box, false, 0)
	row(box, 1, "기본요금", K.won(lines.base or 4800))
	if (lines.distance or 0) > 0 then
		row(box, 2, "거리요금", K.won(lines.distance))
	end
	if (lines.night or 0) > 0 then
		row(box, 3, "심야 할증 (22~04시)", "+" .. K.won(lines.night), K.Color.orange)
	end
	if (lines.discount or 0) > 0 then
		row(box, 4, "단골 할인", "-" .. K.won(lines.discount), K.Color.green)
	end
	local cashN, bankN = tonumber(cash) or 0, tonumber(bank) or 0
	local btns = K.frame(p, { Name = "PayButtons", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 5 })
	local cardB = K.Button(btns, { name = "PayCard", style = "gold", text = "💳 카드", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.fromScale(0, 0) })
	local cashB = K.Button(btns, { name = "PayCash", style = "secondary", text = "💵 현금", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.new(0.5, 4, 0, 0) })
	for _, b in { cardB, cashB } do
		b.TextYAlignment = Enum.TextYAlignment.Top
		K.pad(b, 6, 6, 9, 4)
	end
	local cardBal = K.text(cardB, { Name = "Balance", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -8, 0, 14), Text = "통장 " .. K.won(bankN), TextColor3 = K.Color.onGold, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local cashBal = K.text(cashB, { Name = "Balance", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -8, 0, 14), Text = "현금 " .. K.won(cashN), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	if bankN < fare then
		K.setButtonEnabled(cardB, false)
		cardBal.Text = "잔액 부족 · " .. K.won(bankN)
	end
	if cashN < fare then
		K.setButtonEnabled(cashB, false)
		cashBal.Text = "잔액 부족 · " .. K.won(cashN)
	end
	local cap = K.text(p, { Name = "Auto", Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 6 })
	local busy = false
	local function pay(method: string, b: TextButton)
		if busy or b:GetAttribute("Disabled") then
			return
		end
		busy = true
		K.setButtonLoading(b, true, "결제 중…")
		task.spawn(function()
			local r = call("pay", { method = method })
			if not r.ok then
				busy = false
				K.setButtonLoading(b, false)
				F.toast({ kind = "taxi", title = "결제", body = r.message or "결제하지 못했어요" })
			else
				K.feedback("money")
			end
		end)
	end
	cardB.Activated:Connect(function()
		pay("card", cardB)
	end)
	cashB.Activated:Connect(function()
		pay("cash", cashB)
	end)
	payTimer += 1
	local mine = payTimer
	task.spawn(function()
		while payTimer == mine and panel == p do
			local left = math.max(0, math.floor((tonumber(j.payUntil) or serverNow()) - serverNow()))
			cap.Text = string.format("%d초 후 %s로 자동 결제돼요", left, if bankN >= fare then "카드" else "현금")
			task.wait(0.5)
		end
	end)
end

local function showReceipt(r: any)
	if type(r) ~= "table" then
		return
	end
	lastReceipt = r
	local p = openPanel("taxiReceipt", true, 330)
	local head = K.frame(p, { Name = "Head", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	K.text(head, { Size = UDim2.new(1, 0, 0, 22), Text = "🧾 영수증", Font = K.Font.bold, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Center })
	K.text(head, { Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 14), Text = string.format("%s · %s", r.company or "광안콜택시", r.id or ""), TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center })
	local box = K.frame(p, { Name = "Rows", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	K.list(box, false, 0)
	local o = 0
	local function add(label: string, value: string, color: Color3?, bold: boolean?)
		o += 1
		row(box, o, label, value, color, bold)
	end
	add("목적지", r.destination or "-")
	add("차량", string.format("%s · %s", r.plate or "", r.car or ""))
	add("기사", r.driverTitle or r.driver or "-")
	if r.meters then
		add("이동 거리", if r.meters >= 1000 then string.format("%.1fkm", r.meters / 1000) else string.format("%dm", r.meters))
	end
	if r.seconds then
		add("승차 시간", string.format("%d분 %02d초", r.seconds // 60, r.seconds % 60))
	end
	local lines = r.lines or {}
	o += 1
	hairline(box, o)
	add("기본요금", K.won(lines.base or 4800))
	if (lines.distance or 0) > 0 then
		add("거리요금", K.won(lines.distance))
	end
	if (lines.night or 0) > 0 then
		add("심야 할증", "+" .. K.won(lines.night), K.Color.orange)
	end
	if (lines.discount or 0) > 0 then
		add("단골 할인", "-" .. K.won(lines.discount), K.Color.green)
	end
	o += 1
	hairline(box, o)
	local how = if r.method == "card" then "카드 (통장)" elseif r.method == "cash" then "현금" elseif r.method == "split" then "현금 + 카드" else "미결제"
	add("결제", how)
	add("합계", K.won(r.paid or r.fare or 0), GOLD1, true)
	-- rating
	K.text(p, { Name = "RateQ", Size = UDim2.new(1, 0, 0, 18), Text = "기사님은 어떠셨나요?", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
	local stars = K.frame(p, { Name = "Stars", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4 })
	K.list(stars, true, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local rateCap = K.text(p, { Name = "RateCap", Size = UDim2.new(1, 0, 0, 14), Text = "", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 5 })
	local starBtns: { TextButton } = {}
	local rated = false
	for i = 1, 5 do
		local b = K.make("TextButton", { Name = "Star" .. i, Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "☆", TextColor3 = GOLD1, TextSize = 28, Font = K.Font.bold, AutoButtonColor = false, LayoutOrder = i }, stars)
		K.pressable(b, { veil = false, scale = 0.85, sound = "toggle" })
		starBtns[i] = b
		b.Activated:Connect(function()
			if rated then
				return
			end
			rated = true
			for k, s in starBtns do
				s.Text = if k <= i then "★" else "☆"
				if k <= i and K.pop then
					task.delay(k * 0.04, function()
						K.pop(s, 0.6)
					end)
				end
			end
			rateCap.Text = "전달 중…"
			task.spawn(function()
				local res = call("rate", { rideId = r.id, stars = i })
				rateCap.Text = if res.ok then (if i >= 4 then "감사합니다! 기사님께 전달할게요 🙏" else "소중한 의견 감사합니다") else (res.message or "")
			end)
		end)
	end
	local ok = K.Button(p, { name = "Done", style = "primary", text = "확인", size = UDim2.new(1, 0, 0, 44), order = 6 })
	ok.Activated:Connect(closePanel)
	task.delay(40, function()
		if panel == p then
			closePanel()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Ride camera
-------------------------------------------------------------------------------------------------
local camMode: string? = nil -- nil (off) | follow | cinema
local savedMinZoom: number? = nil
local camSmooth: CFrame? = nil
local ackSeen: (boolean) -> ()
local rideCameraStart: () -> ()

local function camRestore()
	if camMode == nil then
		return
	end
	camMode = nil
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
	if savedMinZoom then
		player.CameraMinZoomDistance = savedMinZoom
		savedMinZoom = nil
	end
end

local function camFollow(): boolean
	local car = myCar()
	local cam = workspace.CurrentCamera
	if not car or not car.root or not car.root.Parent or not cam then
		return false
	end
	camMode = "follow"
	if savedMinZoom == nil then
		savedMinZoom = player.CameraMinZoomDistance
	end
	player.CameraMinZoomDistance = math.max(savedMinZoom or 0.5, 16)
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = car.root
	local cf = car.root.CFrame
	cam.CFrame = CFrame.lookAt(cf.Position - cf.LookVector * 20 + Vector3.new(0, 8, 0) + cf.RightVector * 6, cf.Position)
	return true
end

function M._toggleCamera()
	if camMode == "follow" then
		camMode = "cinema"
		camSmooth = nil
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		F.toast({ kind = "taxi", title = "🎥 시네마 카메라", body = "한 번 더 누르면 자유 시점" })
	else
		camFollow()
	end
end

local function stepCamera(dt: number)
	if camMode ~= "cinema" then
		return
	end
	local car = myCar()
	local cam = workspace.CurrentCamera
	if not car or not car.root or not cam then
		return
	end
	local cf = car.root.CFrame
	local want = CFrame.lookAt(cf.Position - cf.LookVector * 17 + cf.RightVector * 7 + Vector3.new(0, 5.5, 0), cf.Position + cf.LookVector * 10 + Vector3.new(0, 2, 0))
	camSmooth = if camSmooth then camSmooth:Lerp(want, math.clamp(dt * 4, 0, 1)) else want
	cam.CFrame = camSmooth :: CFrame
end

-------------------------------------------------------------------------------------------------
-- Visibility guard: "seen" ack, ride camera retry, 2 Hz watchdog while boarded
-------------------------------------------------------------------------------------------------
-- (seenFor / carHidden / carMissingSince / camPending are declared with the job state above)

-- Tells the server that this client has the taxi model (once per ride, or again when asked).
function ackSeen(force: boolean)
	local j = job
	if not j or type(j.id) ~= "string" then
		return
	end
	if not force and seenFor == j.id then
		return
	end
	if not carPresent() then
		return -- the watchdog tries again when the model shows up
	end
	seenFor = j.id
	task.spawn(function()
		call("seen", { ride = j.id })
	end)
end

function rideCameraStart()
	if camMode == "cinema" then
		return
	end
	if camFollow() then
		camPending = false
	else
		camPending = true
	end
end

onMyCarPresent = function(car: Car)
	if jobState == "coming" or jobState == "arrived" or jobState == "riding" then
		ackSeen(false)
	end
	if camPending and jobState == "riding" then
		rideCameraStart()
	end
	if carHidden then
		carHidden = false
		carMissingSince = nil
		restoreVisibility(car)
	end
end

-- Runs every 0.5 s while my ride is active. Never costs more than a walk over the taxi's parts.
local function watchdog()
	local boarded = (job and job.boarded == true) or jobState == "riding" or player:GetAttribute("InTaxi") == true
	if not boarded then
		carHidden = false
		carMissingSince = nil
		return
	end
	local car = myCar()
	local present = car ~= nil and carPresent()
	if not present then
		carMissingSince = carMissingSince or os.clock()
		if not carHidden and os.clock() - carMissingSince > 1.5 then
			carHidden = true
			notice("🚕", "택시 오는 중…", "차가 보이면 바로 출발해요")
		end
		return
	end
	local c = car :: Car
	if carHidden then
		carHidden = false
		carMissingSince = nil
		K.feedback("success")
	end
	carMissingSince = nil
	local fixed = restoreVisibility(c)
	if fixed > 0 then
		warn(string.format("[TaxiRide] restored %d hidden taxi parts", fixed))
	end
	ackSeen(false)
	-- the ride camera must sit on the car root (a late model, a respawned camera, a stray reset)
	local cam = workspace.CurrentCamera
	if jobState == "riding" and cam then
		if camMode == "follow" then
			if cam.CameraSubject ~= c.root or cam.CameraType ~= Enum.CameraType.Custom then
				camFollow()
			end
		elseif camMode == nil then
			rideCameraStart()
		end
	end
end

-------------------------------------------------------------------------------------------------
-- TaxiState
-------------------------------------------------------------------------------------------------
local REASON = {
	player = "호출을 취소했어요",
	walkaway = "너무 멀어져서 택시가 떠났어요",
	timeout = "기사님이 기다리다 떠났어요",
	noroad = "근처에 도로가 없어요",
	money = "잔액이 부족해요",
	busy = "빈 택시가 없어요",
	respawn = "택시 이용이 끝났어요",
	died = "택시 이용이 끝났어요",
}

local destAsked: string? = nil

local function onState(data: any)
	if type(data) ~= "table" or type(data.state) ~= "string" then
		return
	end
	local prev = jobState
	jobState = data.state
	if type(data.job) == "table" then
		job = data.job
		if job.now then
			job.bookedAt = job.bookedAt or (job.freeCancelUntil and job.freeCancelUntil - 10)
		end
	end
	if data.askSeen then
		task.defer(ackSeen, true)
	end
	if data.state == "riding" then
		meterShown = -1
		if prev ~= "riding" then
			task.defer(rideCameraStart)
			if prev ~= "riding" and not data.skipped then
				F.toast({ kind = "taxi", title = (job and job.driverTitle or "기사님"), body = "출발하겠습니다~ 안전벨트 매 주세요! 🚕" })
			end
		end
	elseif data.state == "paying" then
		camRestore()
		if job then
			showPay(job, data.cash, data.bank)
		end
	elseif data.state == "done" then
		seenFor = nil
		camPending = false
		carHidden = false
		camRestore()
		if data.receipt then
			showReceipt(data.receipt)
		else
			closePanel()
		end
		destAsked = nil
	elseif data.state == "cancelled" then
		seenFor = nil
		camPending = false
		carHidden = false
		camRestore()
		if panelKey == "taxiPay" or panelKey == "taxiDetails" or (panel and panelKey == nil) then
			closePanel()
		end
		if data.reason and data.reason ~= "none" then
			local fee = tonumber(data.fee) or 0
			notice("🚕", REASON[data.reason] or "택시 이용이 끝났어요", if fee > 0 then ("수수료 " .. K.won(fee)) else "다시 부르려면 광안콜택시에 전화하세요")
		end
		job = nil
		destAsked = nil
	elseif data.state == "arrived" then
		if prev == "coming" then
			K.feedback("notify")
		end
		task.defer(ackSeen, false)
		if job and job.boarded and data.needDest and destAsked ~= job.id then
			-- seated without a destination: the driver asks right away
			destAsked = job.id
			task.delay(0.4, function()
				F.open("taxiDest", {})
			end)
		elseif job and job.boarded and data.reason == "money" then
			F.toast({ kind = "taxi", title = "잔액 부족", body = string.format("그곳까지 약 %s이 나와요. 가까운 곳으로 골라 주세요", K.won(data.fare or 0)) })
		end
	elseif data.state == "coming" and prev ~= "coming" and data.replanned == nil then
		K.feedback("success")
	end
	refreshCard()
end

-------------------------------------------------------------------------------------------------
-- Flows
-------------------------------------------------------------------------------------------------
function M.open(flowId: string, _args: any?)
	if flowId == "taxiReceipt" then
		if lastReceipt then
			showReceipt(lastReceipt)
		else
			F.toast({ kind = "taxi", title = "영수증", body = "최근 택시 영수증이 없어요" })
		end
		return
	end
	-- taxiRide
	if jobState == "coming" or jobState == "arrived" then
		showDetails()
	elseif jobState == "riding" then
		F.toast({ kind = "taxi", title = "운행 중", body = (job and job.destination or "목적지") .. "로 가는 중이에요" })
	else
		F.toast({ kind = "taxi", title = "광안콜택시", body = "호출한 택시가 없어요. 전화로 불러 보세요!" })
	end
end

function M.close()
	closePanel()
end

function M.isOpen(): boolean
	return panel ~= nil
end

function M.init(ctx: any)
	F = ctx
	K = ctx.K
	Layout = ctx.Layout
	player = ctx.player
	buildCard()
	Layout.onChanged(layoutCard)
	-- cars
	task.spawn(function()
		local folder = workspace:WaitForChild("GwangalliTaxis", 60)
		if not folder then
			return
		end
		for _, m in folder:GetChildren() do
			track(m)
		end
		folder.ChildAdded:Connect(function(m)
			task.defer(track, m)
		end)
		folder.ChildRemoved:Connect(function(m)
			if m:IsA("Model") then
				untrack(m)
			end
		end)
	end)
	RunService:BindToRenderStep("GwangalliTaxiCars", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
		local ok, err = pcall(stepCars)
		if not ok then
			warn("[TaxiRide] cars: " .. tostring(err))
		end
		pcall(stepCamera, dt)
	end)
	-- my taxi state
	task.spawn(function()
		local r = F.remote("TaxiState", 30)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(function(data)
				local ok, err = pcall(onState, data)
				if not ok then
					warn("[TaxiRide] state: " .. tostring(err))
				end
			end)
		end
		-- resync (UI reload / late join of the flow)
		local s = call("state")
		if s.ok and s.job then
			onState({ state = s.job.state == "leaving" and "done" or s.job.state, job = s.job })
		end
	end)
	F.on("taxiBooked", function(j: any)
		if type(j) == "table" and jobState ~= "coming" then
			job = j
			jobState = "coming"
			refreshCard()
		end
	end)
	-- 10 Hz card refresh while a taxi is active; the visibility watchdog every 5th tick (2 Hz)
	task.spawn(function()
		local tick = 0
		while true do
			tick += 1
			if jobState == "coming" or jobState == "arrived" or jobState == "riding" then
				local ok, err = pcall(refreshCard)
				if not ok then
					warn("[TaxiRide] card: " .. tostring(err))
				end
			end
			if tick % 5 == 0 and (jobState == "arrived" or jobState == "riding" or player:GetAttribute("InTaxi") == true) then
				local ok2, err2 = pcall(watchdog)
				if not ok2 then
					warn("[TaxiRide] watchdog: " .. tostring(err2))
				end
			end
			task.wait(0.1)
		end
	end)
	player.CharacterAdded:Connect(function()
		camRestore()
	end)
	local _ = Players
	local _s = SoundService
end

return M
