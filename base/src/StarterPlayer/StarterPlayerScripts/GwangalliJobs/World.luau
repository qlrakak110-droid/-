--!nocheck
-- GwangalliJobs/World: the 알바 IN THE WORLD (client side, local instances only).
--   * camera framing of the station while a round sheet is up (J.frameCamera / J.releaseCamera)
--   * 계산: the customer's basket appears ON THE COUNTER as product props; tap a prop (world tap,
--     camera ray against the props only) or its tile to scan it: scanner beep, the prop slides to
--     the bagging side, the POS monitor's SurfaceGui ("PosScreen", tag GwPosScreen) lists the lines
--     and the total, the customer display shows the total; cash -> a bill on the counter, change
--     coins; then the receipt prints out of the printer
--   * 재고 정리: the active restock slots glow (one Highlight) and get a local ProximityPrompt
--     "진열하기"; placed items appear on the slot's shelf boards
--   * 유통기한: 4 products glow on the showcase with date tags; tap the expired one
--   * 택배 접수: a box with a weight label on the counter; 카페: a cup on the machine that fills layer
--     by layer (shot / milk / ice / syrup ...)
--   * speech bubbles: the boss (JobGame {op = "say"}), customers / recipients (model attributes
--     ShopSay + ShopSaySeq), all through J.bubble (shared pool)
--   * the door chime (station "door_in" attribute ChimeSeq) and the 택배 ring / 퀵 marker
-- Cost: tweens + attribute signals; no per-frame loop (the latte ring is a tween too).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local World = {}

local J: any
local K: any
local JS: any

local folder: Folder? = nil
local cur: any = nil -- the current round payload
local pickables: { [BasePart]: (any) -> () } = {}
local tapConn: RBXScriptConnection? = nil
local roundProps: { Instance } = {}
local sale: any = nil
local restock: any = nil
local expiry: any = nil
local cup: any = nil
local ring: Model? = nil
local marker: Part? = nil
local recipientHL: Highlight? = nil

local CAT_COLOR = {
	food = Color3.fromRGB(242, 240, 232),
	snack = Color3.fromRGB(250, 196, 60),
	drink = Color3.fromRGB(90, 170, 240),
	life = Color3.fromRGB(200, 130, 220),
}
local ING_COLOR = {
	shot = Color3.fromRGB(70, 40, 22),
	milk = Color3.fromRGB(245, 240, 228),
	ice = Color3.fromRGB(200, 230, 245),
	syrup = Color3.fromRGB(220, 150, 60),
	water = Color3.fromRGB(150, 200, 230),
	foam = Color3.fromRGB(250, 248, 240),
	cream = Color3.fromRGB(252, 246, 230),
	tea = Color3.fromRGB(170, 100, 50),
}

local function localFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "GwangalliJobLocal"
	f.Parent = workspace
	folder = f
	return f
end

local function part(props: any): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	if not props.Parent then
		p.Parent = localFolder()
	end
	return p
end

local function label3d(adornee: BasePart, text: string, size: Vector2?, offsetY: number?, color: Color3?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromScale((size and size.X) or 1.6, (size and size.Y) or 0.8)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 0.9, 0)
	bb.MaxDistance = 30
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
	t.BackgroundTransparency = if color then 0.05 else 1
	t.TextColor3 = if color then Color3.fromRGB(20, 20, 24) else Color3.fromRGB(255, 255, 255)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = text
	t.Parent = bb
	if color then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.25, 0)
		c.Parent = t
	end
	bb.Adornee = adornee
	bb.Parent = adornee
	return bb
end

local function tweenCF(p: BasePart, cf: CFrame, t: number?)
	pcall(function()
		TweenService:Create(p, TweenInfo.new(t or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf }):Play()
	end)
end

local function track(inst: Instance)
	table.insert(roundProps, inst)
	return inst
end

local function clearProps(delay: number?)
	local list = roundProps
	roundProps = {}
	local function kill()
		for _, inst in list do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end
	if delay and delay > 0 then
		task.delay(delay, kill)
	else
		kill()
	end
end

local function stationCF(id: string): CFrame?
	local st = cur and cur.stations
	local cf = st and st[id]
	if typeof(cf) == "CFrame" then
		return cf
	end
	return nil
end

local function near(cf: CFrame?, r: number): boolean
	local pos = J.rootPos()
	return cf ~= nil and pos ~= nil and (pos - cf.Position).Magnitude <= r
end

-------------------------------------------------------------------------------------------------
-- World taps (camera ray against our props only)
-------------------------------------------------------------------------------------------------
local function onTap(input: InputObject, processed: boolean)
	if processed or next(pickables) == nil then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local ok, ray = pcall(function()
		return cam:ScreenPointToRay(input.Position.X, input.Position.Y)
	end)
	if not ok or not ray then
		return
	end
	local list = {}
	for p in pickables do
		if p.Parent then
			table.insert(list, p)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if hit and hit.Instance then
		local fn = pickables[hit.Instance :: BasePart]
		if fn then
			pcall(fn, hit.Instance)
		end
	end
end

local function pickable(p: BasePart, fn: (any) -> ())
	p.CanQuery = true
	pickables[p] = fn
	if not tapConn then
		tapConn = UserInputService.InputBegan:Connect(onTap)
	end
end

local function clearPickables()
	pickables = {}
	if tapConn then
		tapConn:Disconnect()
		tapConn = nil
	end
end

-------------------------------------------------------------------------------------------------
-- Camera framing per round
-------------------------------------------------------------------------------------------------
local function frameStation(standId: string, focusId: string, back: number, up: number)
	local stand = stationCF(standId)
	local focus = stationCF(focusId) or stand
	if not stand or not focus or not near(stand, 26) then
		return
	end
	local look = stand.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	flat = flat.Unit
	local eye = stand.Position - flat * back + Vector3.new(0, up, 0)
	-- look a little below the work spot so it sits in the upper part of the screen (the sheet covers
	-- the bottom 30 / 38 %)
	local target = focus.Position + flat * 1.5 - Vector3.new(0, 1.6, 0)
	J.frameCamera(eye, target, 0.6)
end

function World.round(p: any)
	cur = p
	if p.world == "customer" then
		if stationCF("counter") then
			frameStation("counter", "counter_items", 4.4, 5.4)
		elseif stationCF("bar") then
			frameStation("bar", "bar_cup", 4, 4.6)
		end
	elseif p.world == "expiry" then
		frameStation("chiller", "chiller_items", 3.6, 3.4)
	elseif p.world == "cup" then
		frameStation("bar", "bar_cup", 4, 4.6)
	end
end

function World.roundClosed()
	J.releaseCamera()
end

-------------------------------------------------------------------------------------------------
-- POS screen (SurfaceGui built by the store: PosScreen.Bg.{Head, Lines, Total})
-------------------------------------------------------------------------------------------------
local function posGui(jobId: string?): (any, any)
	local pos = J.rootPos()
	for _, mon in CollectionService:GetTagged("GwPosScreen") do
		if mon:IsA("BasePart") and (not jobId or mon:GetAttribute("Job") == jobId) and (not pos or (mon.Position - pos).Magnitude < 60) then
			local sg = mon:FindFirstChild("PosScreen")
			local bg = sg and sg:FindFirstChild("Bg")
			return bg, mon
		end
	end
	return nil, nil
end

local function customerDisplay(jobId: string?): TextLabel?
	local pos = J.rootPos()
	for _, d in CollectionService:GetTagged("GwPosCustomer") do
		if d:IsA("BasePart") and (not jobId or d:GetAttribute("Job") == jobId) and (not pos or (d.Position - pos).Magnitude < 60) then
			local l = d:FindFirstChildWhichIsA("TextLabel", true)
			return l
		end
	end
	return nil
end

local function posWrite(head: string?, lines: string?, total: string?)
	local bg = posGui(cur and cur.jobId)
	if not bg then
		return
	end
	local h, l, t = bg:FindFirstChild("Head"), bg:FindFirstChild("Lines"), bg:FindFirstChild("Total")
	if head and h then
		h.Text = head
	end
	if lines and l then
		l.Text = lines
	end
	if total and t then
		t.Text = total
	end
end

-------------------------------------------------------------------------------------------------
-- 계산
-------------------------------------------------------------------------------------------------
local function productProp(it: any, cf: CFrame): Part
	local def = JS.PRODUCT_BY_ID and JS.PRODUCT_BY_ID[it.id]
	local col = CAT_COLOR[def and def.cat or "food"] or CAT_COLOR.food
	local size = if def and def.cat == "drink" then Vector3.new(0.55, 1.05, 0.55) elseif def and def.cat == "food" then Vector3.new(0.9, 0.55, 0.7) else Vector3.new(0.8, 0.8, 0.45)
	local p = part({ Name = "JobProduct", Size = size, CFrame = cf * CFrame.new(0, size.Y / 2, 0), Color = col })
	label3d(p, tostring(it.icon or "📦"), Vector2.new(1.1, 1.1), size.Y / 2 + 0.55)
	return track(p) :: Part
end

function World.saleStart(p: any, onScan: (number) -> ())
	local cf = stationCF("counter_items")
	if not cf then
		return
	end
	local items = (p.view and p.view.items) or {}
	local n = #items
	local span = 3.0
	local hl = Instance.new("Highlight")
	hl.Name = "SaleGlow"
	hl.FillTransparency = 0.82
	hl.OutlineColor = Color3.fromRGB(255, 214, 90)
	hl.FillColor = Color3.fromRGB(255, 214, 90)
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	local model = Instance.new("Model")
	model.Name = "SaleBasket"
	model.Parent = localFolder()
	track(model)
	sale = { props = {}, model = model, onScan = onScan, count = 0 }
	local perRow = math.max(1, math.ceil(n / 2))
	for i, it in items do
		local row = if i <= perRow then 0 else 1
		local k = if row == 0 then i else i - perRow
		local cols = if row == 0 then perRow else n - perRow
		local x = if cols <= 1 then 0 else -span / 2 + (k - 1) * span / (cols - 1)
		local z = if row == 0 then -0.25 else 0.45 -- toward the customer (the station faces the door)
		local pcf = cf * CFrame.new(x, -0.5, z) * CFrame.Angles(0, math.rad((i * 37) % 30 - 15), 0)
		local prop = productProp(it, pcf)
		prop.Parent = model
		sale.props[i] = prop
		pickable(prop, function()
			onScan(i)
		end)
	end
	hl.Adornee = model
	hl.Parent = model
	posWrite("POS 1 · 스캔 중", "상품을 찍어 주세요", "합계 0원")
	local cd = customerDisplay(cur and cur.jobId)
	if cd then
		cd.Text = "합계 0원"
	end
end

function World.saleScanned(i: number, it: any)
	if not sale then
		return
	end
	local prop = sale.props[i]
	local dst = stationCF("counter_scanned")
	if prop then
		pickables[prop] = nil
		sale.count += 1
		if dst then
			local k = sale.count
			tweenCF(prop, dst * CFrame.new(((k - 1) % 3 - 1) * 0.8, -0.5 + prop.Size.Y / 2, math.floor((k - 1) / 3) * 0.7 - 0.2), 0.3)
		end
		local tag = prop:FindFirstChild("Tag")
		if tag then
			tag:Destroy()
		end
	end
	-- the scanner flashes red for a beat
	for _, s in CollectionService:GetTagged("GwPosScanner") do
		if s:IsA("BasePart") and (s.Position - (prop and prop.Position or s.Position)).Magnitude < 12 then
			local flash = part({ Name = "ScanFlash", Size = Vector3.new(0.5, 0.05, 1.4), CFrame = s.CFrame * CFrame.new(0, -0.45, -0.6), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, Transparency = 0.2 })
			task.delay(0.15, function()
				flash:Destroy()
			end)
		end
	end
	local _ = it
end

function World.saleTotal(n: number, total: number, items: { any }, scanned: { [number]: boolean })
	local lines = {}
	for i, it in items do
		if scanned[i] then
			table.insert(lines, string.format("%s %s  %s", it.icon or "", it.name or "", JS.won(it.price or 0)))
		end
	end
	-- the screen shows the last 4 lines
	local from = math.max(1, #lines - 3)
	local show = {}
	for i = from, #lines do
		table.insert(show, lines[i])
	end
	posWrite(string.format("POS 1 · 스캔 %d/%d", n, #items), if #show > 0 then table.concat(show, "\n") else "상품을 찍어 주세요", "합계 " .. JS.won(total))
	local cd = customerDisplay(cur and cur.jobId)
	if cd then
		cd.Text = "합계 " .. JS.won(total)
	end
end

function World.salePay(method: string, paid: number?)
	local cf = stationCF("counter_items")
	if method == "cash" then
		posWrite("POS 1 · 현금 " .. JS.won(paid or 0), nil, nil)
		if cf then
			local bill = part({ Name = "CashBill", Size = Vector3.new(1.3, 0.04, 0.65), CFrame = cf * CFrame.new(0.2, -0.47, 0.9), Color = Color3.fromRGB(150, 190, 120) })
			track(bill)
			tweenCF(bill, cf * CFrame.new(0.2, -0.47, 0.2) * CFrame.Angles(0, 0.3, 0), 0.4)
		end
	else
		posWrite("POS 1 · 카드 결제", nil, nil)
	end
end

function World.saleChange(_i: number)
	local cf = stationCF("counter_items")
	if not cf then
		return
	end
	for k = 1, 3 do
		local coin = part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.35, 0.35), CFrame = cf * CFrame.new(-0.4 + k * 0.25, -0.4, -0.3) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(220, 190, 110), Material = Enum.Material.Metal })
		track(coin)
		tweenCF(coin, cf * CFrame.new(-0.4 + k * 0.25, -0.47, 0.8) * CFrame.Angles(0, 0, math.rad(90)), 0.35)
	end
end

function World.saleStop()
	if not sale then
		return
	end
	sale = nil
	clearPickables()
	-- the receipt prints out of the printer
	for _, pr in CollectionService:GetTagged("GwPosPrinter") do
		local pos = J.rootPos()
		if pr:IsA("BasePart") and pos and (pr.Position - pos).Magnitude < 20 then
			local slip = part({ Name = "Receipt", Size = Vector3.new(0.45, 0.02, 0.1), CFrame = pr.CFrame * CFrame.new(0, pr.Size.Y / 2, 0), Color = Color3.fromRGB(250, 250, 248) })
			track(slip)
			J.sfx("printer")
			pcall(function()
				TweenService:Create(slip, TweenInfo.new(0.6), { Size = Vector3.new(0.45, 0.02, 1.1), CFrame = pr.CFrame * CFrame.new(0, pr.Size.Y / 2 + 0.02, -0.5) }):Play()
			end)
			break
		end
	end
	task.delay(1.2, function()
		posWrite("POS 1 · 결제 대기", "어서오세요 😊", "합계 0원")
		local cd = customerDisplay(cur and cur.jobId)
		if cd then
			cd.Text = "합계 0원"
		end
	end)
	clearProps(1.3)
end

-------------------------------------------------------------------------------------------------
-- 택배 접수 / 컵
-------------------------------------------------------------------------------------------------
function World.parcelStart(p: any)
	local cf = stationCF("counter_items")
	if not cf then
		return
	end
	local box = part({ Name = "ParcelBox", Size = Vector3.new(1.6, 1.1, 1.2), CFrame = cf * CFrame.new(0, 0.05, 0.1), Color = Color3.fromRGB(196, 160, 110), Material = Enum.Material.Cardboard })
	track(box)
	label3d(box, string.format("⚖️ %s", tostring(p.view and p.view.weight or "?")), Vector2.new(2.2, 0.7), 1.0, Color3.fromRGB(255, 255, 255))
	posWrite("택배 접수 · " .. tostring(p.view and p.view.dest or ""), "무게 " .. tostring(p.view and p.view.weight or "?"), nil)
end

function World.parcelStop()
	clearProps(1.0)
	task.delay(1.0, function()
		posWrite("POS 1 · 결제 대기", "어서오세요 😊", "합계 0원")
	end)
end

function World.cupStart(p: any)
	local cf = stationCF("bar_cup") or stationCF("counter_items")
	if not cf then
		cup = nil
		return
	end
	local body = part({ Name = "Cup", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.75, 0.75), CFrame = cf * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(235, 240, 245), Transparency = 0.45, Material = Enum.Material.Glass })
	track(body)
	cup = { cf = cf, level = 0, body = body }
	local _ = p
end

function World.cupLayer(id: string, right: boolean)
	if not cup then
		return
	end
	local h = 0.18
	if cup.level + h > 0.95 then
		h = math.max(0.02, 0.95 - cup.level)
	end
	local y = -0.5 + cup.level + h / 2
	local layer = part({ Name = "Layer", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 0.66, 0.66), CFrame = cup.cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = ING_COLOR[id] or Color3.fromRGB(200, 160, 120), Transparency = if id == "ice" then 0.3 else 0 })
	track(layer)
	cup.level += h
	if not right then
		J.sfx("wrong")
	end
end

function World.cupStop()
	cup = nil
	clearProps(1.2)
end

-------------------------------------------------------------------------------------------------
-- 유통기한
-------------------------------------------------------------------------------------------------
function World.expiryStart(p: any, onPick: (number) -> ())
	local cf = stationCF("chiller_items")
	if not cf then
		return
	end
	local items = (p.view and p.view.items) or {}
	local model = Instance.new("Model")
	model.Name = "ExpiryItems"
	model.Parent = localFolder()
	track(model)
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 220, 90)
	hl.OutlineColor = Color3.fromRGB(255, 230, 120)
	hl.FillTransparency = 0.7
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model
	pcall(function()
		TweenService:Create(hl, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = 0.35 }):Play()
	end)
	expiry = { props = {}, model = model }
	local span = 6
	for i, it in items do
		local x = -span / 2 + (i - 1) * span / math.max(1, #items - 1)
		local pcf = cf * CFrame.new(x, -0.5, -0.25)
		local prop = productProp(it, pcf)
		prop.Parent = model
		label3d(prop, string.format("%s ~%s", tostring(it.icon or ""), tostring(it.date or "")), Vector2.new(2.0, 0.7), prop.Size.Y / 2 + 1.35, Color3.fromRGB(255, 255, 255))
		expiry.props[i] = prop
		pickable(prop, function()
			onPick(i)
		end)
	end
end

function World.expiryPicked(i: number)
	if not expiry then
		return
	end
	local prop = expiry.props[i]
	if prop then
		tweenCF(prop, prop.CFrame * CFrame.new(0, 0.6, 1.4), 0.35)
	end
end

function World.expiryStop()
	expiry = nil
	clearPickables()
	clearProps(0.8)
end

-------------------------------------------------------------------------------------------------
-- 재고 정리
-------------------------------------------------------------------------------------------------
function World.restockStart(p: any, onSlot: (string) -> ())
	World.restockStop()
	local bins = (p.view and p.view.bins) or {}
	restock = { slots = {}, onSlot = onSlot, placed = {}, model = nil }
	local model = Instance.new("Model")
	model.Name = "RestockGlow"
	model.Parent = localFolder()
	restock.model = model
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 196, 0)
	hl.OutlineColor = Color3.fromRGB(255, 220, 90)
	hl.FillTransparency = 0.75
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = model
	hl.Parent = model
	pcall(function()
		TweenService:Create(hl, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = 0.45 }):Play()
	end)
	for _, b in bins do
		local cf = stationCF("slot_" .. tostring(b.cat))
		if cf then
			-- the glowing frame over the empty boards (3 rows x 2.8 wide)
			local glow = part({ Name = "SlotGlow_" .. b.cat, Size = Vector3.new(3.0, 4.4, 0.25), CFrame = cf * CFrame.new(0, 1.7, 0.1), Color = Color3.fromRGB(255, 196, 0), Transparency = 0.85, Parent = model })
			local anchor = part({ Name = "SlotAnchor_" .. b.cat, Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 1.0, -1.6), Transparency = 1 })
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "GwangalliRestockPrompt"
			prompt.ActionText = "진열하기"
			prompt.ObjectText = string.format("📦 %s 칸", tostring(b.name or b.cat))
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			prompt.Parent = anchor
			prompt.Triggered:Connect(function()
				if restock and restock.onSlot then
					-- frame the slot while picking (the sheet opens at the bottom)
					local eye = cf.Position + cf.LookVector * 5.5 + Vector3.new(0, 3.6, 0)
					J.frameCamera(eye, cf.Position + Vector3.new(0, 0.6, 0), 0.45)
					pcall(restock.onSlot, b.cat)
				end
			end)
			restock.slots[b.cat] = { cf = cf, glow = glow, anchor = anchor, n = 0 }
		end
	end
end

function World.restockPlace(cat: string, it: any)
	if not restock then
		return
	end
	local s = restock.slots[cat]
	if not s then
		return
	end
	s.n += 1
	local k = s.n
	local row = (k - 1) % 3
	local col = math.floor((k - 1) / 3)
	-- boards at +0.0 / +1.5 / +3.0 above the station (Rows / RowGap of the anchor); fill from the front
	local cf = s.cf * CFrame.new(-0.9 + col * 0.9 + (row % 2) * 0.3, row * 1.5 - 0.5, 0.3)
	local prop = productProp(it, cf)
	prop.Parent = localFolder()
	table.insert(restock.placed, prop)
	K.tween(s.glow, 0.2, { Transparency = 0.6 })
	task.delay(0.25, function()
		if s.glow.Parent then
			K.tween(s.glow, 0.3, { Transparency = 0.85 })
		end
	end)
	-- the box gets lighter: the camera goes back to the player
	J.releaseCamera()
end

function World.restockStop()
	if not restock then
		return
	end
	local r = restock
	restock = nil
	for _, s in r.slots do
		if s.anchor.Parent then
			s.anchor:Destroy()
		end
	end
	if r.model and r.model.Parent then
		r.model:Destroy()
	end
	-- the restocked items stay on the shelf for a while
	local placed = r.placed
	task.delay(25, function()
		for _, p in placed do
			if p.Parent then
				p:Destroy()
			end
		end
	end)
	J.releaseCamera()
end

-------------------------------------------------------------------------------------------------
-- Results / work state / clear
-------------------------------------------------------------------------------------------------
function World.result(p: any)
	if p.game ~= "deliver" then
		task.delay(0.3, function()
			J.releaseCamera()
		end)
	end
end

local function clearDelivery()
	if ring and ring.Parent then
		ring:Destroy()
	end
	ring = nil
	if marker and marker.Parent then
		marker:Destroy()
	end
	marker = nil
	if recipientHL and recipientHL.Parent then
		recipientHL:Destroy()
	end
	recipientHL = nil
end

function World.clear()
	cur = nil
	sale, expiry, cup = nil, nil, nil
	World.restockStop()
	clearPickables()
	clearProps()
	clearDelivery()
	J.releaseCamera()
end

function World.work(w: any)
	if type(w) == "table" and w.onShift ~= true then
		World.clear()
	end
end

-------------------------------------------------------------------------------------------------
-- Delivery: 택배 ring / 퀵 marker + recipient highlight
-------------------------------------------------------------------------------------------------
local function beam(pos: Vector3, color: Color3): Part
	return part({ Name = "DeliveryBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(60, 1.4, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.Neon, Transparency = 0.55 })
end

local function findRecipient(): Model?
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		return nil
	end
	for _, m in f:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("DeliveryFor") == J.player.UserId and m.Name == "Recipient_" .. J.player.UserId then
			return m
		end
	end
	return nil
end

function World.delivery(p: any)
	if p.phase == "done" then
		clearDelivery()
		return
	end
	if p.phase ~= "deliver" then
		return
	end
	clearDelivery()
	local o = p.order or {}
	if p.mode == "parcel" and typeof(p.ring) == "Vector3" then
		local r = tonumber(p.radius) or 13
		local m = Instance.new("Model")
		m.Name = "DeliveryRing"
		m.Parent = localFolder()
		part({ Name = "Disc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, r * 2, r * 2), CFrame = CFrame.new(p.ring + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 196, 0), Material = Enum.Material.Neon, Transparency = 0.72, Parent = m })
		part({ Name = "Edge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, r * 2 + 0.6, r * 2 + 0.6), CFrame = CFrame.new(p.ring + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 220, 120), Material = Enum.Material.ForceField, Transparency = 0.2, Parent = m })
		local b = beam(p.ring, Color3.fromRGB(255, 196, 0))
		b.Parent = m
		ring = m
	elseif typeof(o.pos) == "Vector3" then
		marker = beam(o.pos, Color3.fromRGB(42, 193, 188))
		-- the waiting recipient gets an outline once it streams in
		task.spawn(function()
			for _ = 1, 40 do
				local mdl = findRecipient()
				if mdl then
					local hl = Instance.new("Highlight")
					hl.FillTransparency = 1
					hl.OutlineColor = Color3.fromRGB(42, 230, 220)
					hl.DepthMode = Enum.HighlightDepthMode.Occluded
					hl.Adornee = mdl
					hl.Parent = localFolder()
					recipientHL = hl
					return
				end
				if not marker then
					return
				end
				task.wait(1.5)
			end
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- Speech bubbles
-------------------------------------------------------------------------------------------------
local function staffModel(jobId: string?): Model?
	local key = if jobId == "delivery_quick" or jobId == "delivery_parcel" then "delivery" else jobId
	for _, m in CollectionService:GetTagged("GwJobStaff") do
		if m:IsA("Model") and m:GetAttribute("Job") == key then
			return m
		end
	end
	return nil
end

function World.say(p: any)
	local model = staffModel(p.jobId) or J.npcModel(p.npc)
	local head = J.headOf(model)
	local text = tostring(p.text or "")
	local shown = false
	if head then
		local pos = J.rootPos()
		if not pos or (head.Position - pos).Magnitude < 70 then
			shown = J.bubble(head, text, tonumber(p.dur) or 4, "talk")
		end
	end
	if not shown and text ~= "" then
		J.toast({ kind = "job", title = tostring(p.name or "사장님"), body = text, icon = "💬" })
	end
end

local watched: { [Instance]: RBXScriptConnection } = {}
local function watchModel(m: Instance)
	if watched[m] or not m:IsA("Model") then
		return
	end
	if m:GetAttribute("NpcKind") ~= "shop" then
		return
	end
	watched[m] = m:GetAttributeChangedSignal("ShopSaySeq"):Connect(function()
		local text = m:GetAttribute("ShopSay")
		if type(text) ~= "string" or text == "" then
			return
		end
		local head = J.headOf(m)
		local pos = J.rootPos()
		if head and (not pos or (head.Position - pos).Magnitude < 48) then
			J.bubble(head, text, 3.5, "talk")
		end
	end)
end

local chimeConns: { [Instance]: RBXScriptConnection } = {}
local function watchStation(inst: Instance)
	if chimeConns[inst] or not inst:IsA("BasePart") or inst:GetAttribute("Station") ~= "door_in" then
		return
	end
	chimeConns[inst] = inst:GetAttributeChangedSignal("ChimeSeq"):Connect(function()
		local pos = J.rootPos()
		if pos and (pos - inst.Position).Magnitude < 55 then
			J.sfx("chime")
			task.delay(0.22, function()
				J.sfx("chime2")
			end)
		end
	end)
end

function World.init(ctx: any)
	J = ctx
	K = ctx.K
	JS = ctx.JS
	task.spawn(function()
		local f = workspace:WaitForChild("GwangalliNPCs", 120)
		if not f then
			return
		end
		for _, m in f:GetChildren() do
			watchModel(m)
		end
		f.ChildAdded:Connect(function(m)
			task.defer(watchModel, m)
		end)
		f.ChildRemoved:Connect(function(m)
			local c = watched[m]
			if c then
				c:Disconnect()
				watched[m] = nil
			end
		end)
	end)
	for _, inst in CollectionService:GetTagged("GwJobStation") do
		watchStation(inst)
	end
	CollectionService:GetInstanceAddedSignal("GwJobStation"):Connect(watchStation)
	CollectionService:GetInstanceRemovedSignal("GwJobStation"):Connect(function(inst)
		local c = chimeConns[inst]
		if c then
			c:Disconnect()
			chimeConns[inst] = nil
		end
	end)
	-- local job props never block the player's own prompts / movement
	local _ = Players
end

return World
