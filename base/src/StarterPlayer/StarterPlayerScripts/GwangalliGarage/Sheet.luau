-- GwangalliGarage/Sheet: the 광안 오토 sheet (GwangalliUI kit only). Three tabs:
--   구매   kind chips, the car card (spec line, 신차 / 중고 with prices), 8 colour swatches (the showroom car is
--          recoloured locally as a preview), 할부 toggle with the quote, the total, "시승 60초" + "구매하기";
--          a receipt card (plate, paid, 할부) after a purchase
--   내 차  owned / rented cars: condition, 부르기, 정비 (cost), 팔기 (60 %, tap twice), 견인 for a dead car
--   렌트   큐비 하루 렌트 (GS.RENTAL)
-- While 구매 is open from a showroom car, the camera frames that car from the aisle (Scriptable camera,
-- TweenService) and the car turns on its turntable (a NumberValue tweened 0 -> 2π, applied with
-- workspace:BulkMoveTo); everything is restored when the sheet closes. The sheet sits on the right
-- (landscape / tablet / PC) or the bottom 58 % (portrait), so the car stays visible and the centre of
-- the screen is clear. Touch targets >= 56 px, motion 180-240 ms (TweenService; transform / transparency).
--
--   Sheet.open({ tab = "buy" | "mine" | "rent", kind = "compact" ... })   Sheet.close()   Sheet.isOpen()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Sheet = {}

local player = Players.LocalPlayer
local K: any, Layout: any, GS: any, Net: any = nil, nil, nil, nil
local ctxRef: any = nil

local E: any = {}
local S: any = {
	open = false,
	tab = "buy",
	kind = "compact",
	grade = "used",
	color = nil,
	loan = false,
	busy = false,
	sellArm = nil,
	status = nil,
}
Sheet.state = S
Sheet.elements = E

local BTN = 56
local TWEEN_IN = 0.22
local TWEEN_OUT = 0.18
local DRIVE_KO = { FWD = "전륜", RWD = "후륜", AWD = "사륜" }

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local function won(n: number): string
	return GS.formatWon(n)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	return K.text(parent, props)
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function toast(kind: string, title: string, body: string?)
	K.toast({ kind = kind, title = title, body = body })
end

local function controls(enabled: boolean)
	pcall(function()
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			local c = (require(pm) :: any):GetControls()
			if enabled then
				c:Enable()
			else
				c:Disable()
			end
		end
	end)
end

local function specOf(kind: string): any
	local VS = ctxRef and ctxRef.VS
	return VS and VS.spec(kind) or nil
end

---------------------------------------------------------------------------------------------------
-- Showroom car: turntable spin + colour preview + camera framing
---------------------------------------------------------------------------------------------------
local show: any = nil -- { kind, model, disc, centre, parts, rel, colours, angle (NumberValue), tween, conn }
local savedCam: any = nil

local function displayFor(kind: string): (Model?, BasePart?)
	local model, disc = nil, nil
	for _, m in CollectionService:GetTagged(GS.Tags.Display) do
		if m:IsA("Model") and m:GetAttribute("GarageKind") == kind and m:IsDescendantOf(workspace) then
			model = m
			break
		end
	end
	for _, d in CollectionService:GetTagged(GS.Tags.Turntable) do
		if d:IsA("BasePart") and d:GetAttribute("GarageKind") == kind and d:IsDescendantOf(workspace) then
			disc = d
			break
		end
	end
	return model, disc
end

local function restoreShow()
	local sh = show
	show = nil
	if not sh then
		return
	end
	if sh.tween then
		sh.tween:Cancel()
	end
	if sh.conn then
		sh.conn:Disconnect()
	end
	if sh.angle then
		sh.angle:Destroy()
	end
	local parts, cfs = {}, {}
	for i, p in sh.parts do
		if p.Parent then
			table.insert(parts, p)
			table.insert(cfs, sh.orig[i])
		end
	end
	pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	for p, c in sh.colours do
		if p.Parent then
			p.Color = c
		end
	end
end

local function startShow(kind: string)
	if show and show.kind == kind then
		return
	end
	restoreShow()
	local model, disc = displayFor(kind)
	if not model then
		return
	end
	local centre: Vector3
	local c = disc and disc:GetAttribute("Centre")
	if typeof(c) == "Vector3" then
		centre = c
	elseif disc then
		centre = disc.Position
	else
		centre = model:GetPivot().Position
	end
	local parts, orig, rel = {}, {}, {}
	local base = CFrame.new(centre)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(orig, d.CFrame)
			table.insert(rel, base:ToObjectSpace(d.CFrame))
		end
	end
	if disc then
		table.insert(parts, disc)
		table.insert(orig, disc.CFrame)
		table.insert(rel, base:ToObjectSpace(disc.CFrame))
	end
	local colours = {}
	local paint = GS.paintParts(model)
	for _, p in paint do
		colours[p] = p.Color
	end
	local angle = Instance.new("NumberValue")
	angle.Value = 0
	local sh = { kind = kind, model = model, disc = disc, centre = centre, parts = parts, orig = orig, rel = rel, colours = colours, paint = paint, angle = angle }
	show = sh
	local cfs = table.create(#parts)
	sh.conn = angle:GetPropertyChangedSignal("Value"):Connect(function()
		if show ~= sh then
			return
		end
		local a = angle.Value
		local rot = base * CFrame.Angles(0, a, 0)
		for i, r in rel do
			cfs[i] = rot * r
		end
		pcall(function()
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameNotChanged)
		end)
	end)
	if not K.reduced() then
		sh.tween = TweenService:Create(angle, TweenInfo.new(16, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Value = math.pi * 2 })
		sh.tween:Play()
	end
end

local function previewColor(colorId: string)
	local sh = show
	if not sh then
		return
	end
	local c = GS.color3(colorId)
	for _, p in sh.paint do
		if p.Parent then
			K.tween(p, 0.24, { Color = c }, Enum.EasingStyle.Quad)
		end
	end
end

-- Frames the showroom car so it sits in the part of the screen the sheet leaves free.
local function frameCamera()
	local sh = show
	local cam = workspace.CurrentCamera
	if not sh or not cam then
		return
	end
	if not savedCam then
		savedCam = { type = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView }
	end
	local centre = sh.centre
	-- the showroom front: toward the return marker / the destination in front of the glass
	local front: Vector3? = nil
	for _, r in CollectionService:GetTagged(GS.Tags.Return) do
		if r:IsA("BasePart") then
			front = r.Position
			break
		end
	end
	local dir = if front then Vector3.new(front.X - centre.X, 0, front.Z - centre.Z) else Vector3.new(0, 0, -1)
	if dir.Magnitude < 1 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	local right = dir:Cross(Vector3.yAxis).Unit
	local eye = centre + dir * 17 + right * 7 + Vector3.new(0, 6.5, 0)
	local target = centre + Vector3.new(0, 1.8, 0)
	local cf = CFrame.lookAt(eye, target)
	local mt = Layout.metrics()
	if mt.class == "phoneP" then
		cf = cf * CFrame.new(0, -4.2, 3.5) -- car in the top half
	elseif mt.class == "phoneL" then
		cf = cf * CFrame.new(4.6, 0, 1.5) -- car on the left
	else
		cf = cf * CFrame.new(3.4, 0, 0)
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local tw = TweenService:Create(cam, TweenInfo.new(if K.reduced() then 0.2 else 0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = cf, FieldOfView = 60 })
	tw:Play()
end

local function releaseCamera()
	local cam = workspace.CurrentCamera
	local sv = savedCam
	savedCam = nil
	if not cam or not sv then
		return
	end
	local tw = TweenService:Create(cam, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = sv.cf, FieldOfView = sv.fov })
	tw:Play()
	task.delay(0.3, function()
		if not savedCam then
			cam.CameraType = Enum.CameraType.Custom
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				cam.CameraSubject = hum
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------
local function pageFrame(name: string): ScrollingFrame
	local f = Instance.new("ScrollingFrame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 3
	f.ScrollBarImageColor3 = K.Color.sub
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.CanvasSize = UDim2.new()
	f.ScrollingDirection = Enum.ScrollingDirection.Y
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 3
	f.Visible = false
	f.Parent = E.body
	K.list(f, false, 10)
	K.pad(f, 14, 14, 6, 18)
	return f
end

function Sheet.build(ctx: any)
	ctxRef = ctx
	K, Layout, GS, Net = ctx.K, ctx.Layout, ctx.GS, ctx.Net
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliGarageUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 32
	gui.Enabled = false
	gui:SetAttribute("HideGwangalliHUD", false)
	E.gui = gui

	local panel = K.Panel(gui, { Name = "Sheet", Radius = K.Radius.xl, ZIndex = 2 })
	panel.BackgroundTransparency = 0.04
	panel.ClipsDescendants = true
	E.panel = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	E.scale = scale
	-- header
	local brand = K.frame(panel, { Name = "BrandBar", Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	K.gradient(brand, { Color3.fromRGB(255, 120, 60), Color3.fromRGB(232, 86, 30) }, 0)
	E.title = text(panel, { Name = "Title", Text = "🔧 광안 오토", Font = K.Font.bold, TextSize = K.Type.title2, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -90, 0, 24), ZIndex = 3 })
	E.money = text(panel, { Name = "Money", Text = "", TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -90, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	K.mono(E.money)
	E.close = K.IconButton(panel, { name = "Close", icon = "✕", anchor = Vector2.new(1, 0), position = UDim2.new(1, -8, 0, 6), size = UDim2.fromOffset(BTN, BTN), zIndex = 5, onClick = function()
		Sheet.close()
	end })
	-- tabs
	local tabs = K.Segmented(panel, { height = BTN - 6, items = { { id = "buy", label = "🚗 구매" }, { id = "mine", label = "🔑 내 차" }, { id = "rent", label = "⏱ 렌트" } }, value = "buy", onChange = function(id)
		Sheet.setTab(id)
	end })
	tabs.frame.Position = UDim2.fromOffset(12, 64)
	tabs.frame.Size = UDim2.new(1, -24, 0, BTN)
	tabs.frame.ZIndex = 3
	E.tabs = tabs
	local body = K.frame(panel, { Name = "Body", Position = UDim2.fromOffset(0, 64 + BTN + 6), Size = UDim2.new(1, 0, 1, -(64 + BTN + 6)), ZIndex = 3, ClipsDescendants = true })
	E.body = body
	E.pages = { buy = pageFrame("Buy"), mine = pageFrame("Mine"), rent = pageFrame("Rent") }
	-- receipt overlay
	local rc = K.frame(panel, { Name = "Receipt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.02, BackgroundColor3 = K.Color.glass2, ZIndex = 20, Visible = false, Active = true })
	K.corner(rc, K.Radius.xl)
	E.receipt = rc
	gui.Parent = pg
	Sheet.buildBuy()
	Layout.onChanged(function()
		Sheet.layout()
	end)
	Net.carsChanged:Connect(function()
		if S.open then
			if S.tab == "mine" then
				Sheet.renderMine()
			elseif S.tab == "rent" then
				Sheet.renderRent()
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------------
function Sheet.rect(): { x: number, y: number, w: number, h: number }
	local mt = Layout.metrics()
	if mt.class == "phoneP" then
		local top = math.floor(mt.H * 0.42)
		return { x = 8, y = top, w = mt.W - 16, h = mt.H - top - 8 }
	end
	local r = Layout.rect("sheetRight")
	return { x = r.x, y = r.y, w = r.w, h = r.h }
end

function Sheet.layout()
	if not E.panel then
		return
	end
	local r = Sheet.rect()
	E.panel.AnchorPoint = Vector2.zero
	E.panel.Size = UDim2.fromOffset(r.w, r.h)
	if S.open then
		E.panel.Position = UDim2.fromOffset(r.x, r.y)
	end
	E.rect = r
end

---------------------------------------------------------------------------------------------------
-- 구매 page
---------------------------------------------------------------------------------------------------
local function chip(parent: Instance, label: string, selected: boolean, order: number, onClick: () -> ()): TextButton
	local w = math.ceil(K.textSize(label, K.Type.bodySm, K.Font.bold).X) + 30
	local b = K.Button(parent, { name = "Chip", text = label, style = if selected then "primary" else "secondary", size = UDim2.fromOffset(math.max(76, w), BTN - 4), order = order, zIndex = 5, radius = K.Radius.pill, onClick = onClick })
	return b
end

function Sheet.buildBuy()
	local page = E.pages.buy
	clear(page)
	-- kind chips (horizontal scroller)
	local row = Instance.new("ScrollingFrame")
	row.Name = "Kinds"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.ScrollBarThickness = 0
	row.ScrollingDirection = Enum.ScrollingDirection.X
	row.AutomaticCanvasSize = Enum.AutomaticSize.X
	row.CanvasSize = UDim2.new()
	row.Size = UDim2.new(1, 0, 0, BTN)
	row.LayoutOrder = 1
	row.ZIndex = 4
	row.Parent = page
	K.list(row, true, 8, nil, Enum.VerticalAlignment.Center)
	E.kindRow = row
	-- car card
	local card = K.Card(page, { Name = "CarCard", Size = UDim2.new(1, 0, 0, 108), LayoutOrder = 2, ZIndex = 4 })
	K.gradient(card, K.Grad.card, 90)
	E.carGlyph = K.iconTile(card, 52, "🚙", Color3.fromRGB(255, 120, 60), false)
	E.carGlyph.Position = UDim2.fromOffset(12, 12)
	E.carGlyph.ZIndex = 5
	E.carName = text(card, { Name = "Name", Text = "", Font = K.Font.heavy, TextSize = K.Type.title, Position = UDim2.fromOffset(76, 10), Size = UDim2.new(1, -88, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	E.carBlurb = text(card, { Name = "Blurb", Text = "", TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(76, 40), Size = UDim2.new(1, -88, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	E.carSpec = text(card, { Name = "Spec", Text = "", TextSize = K.Type.caption, Font = K.Font.bold, TextColor3 = K.Color.cyan, Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -24, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	E.carTag = K.Pill(card, { text = "", color = K.Color.gold, height = 22 })
	E.carTag.AnchorPoint = Vector2.new(1, 0)
	E.carTag.Position = UDim2.new(1, -10, 0, 74)
	E.carTag.ZIndex = 6
	-- grade
	local grade = K.Segmented(page, { height = BTN - 6, items = { { id = "used", label = "중고" }, { id = "new", label = "신차" } }, value = S.grade, order = 3, onChange = function(id)
		S.grade = id
		Sheet.refreshBuy()
	end })
	grade.frame.ZIndex = 4
	E.grade = grade
	-- colours
	E.colorLabel = text(page, { Name = "ColorLabel", Text = "색상", Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 4, ZIndex = 4 })
	local sw = K.frame(page, { Name = "Swatches", Size = UDim2.new(1, 0, 0, BTN * 2 + 6), LayoutOrder = 5, ZIndex = 4 })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(BTN, BTN)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = sw
	E.swatchFrame = sw
	E.swatches = {}
	for i, c in GS.COLORS do
		local b = Instance.new("TextButton")
		b.Name = "Swatch_" .. c.id
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.LayoutOrder = i
		b.ZIndex = 5
		b.Parent = sw
		local dot = K.frame(b, { Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 0, BackgroundColor3 = GS.color3(c.id), ZIndex = 6 })
		K.corner(dot, UDim.new(0.5, 0))
		K.gradient(dot, { Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 178) }, 90)
		local ring = K.stroke(dot, K.Color.cyan, 3, 1)
		K.pressable(b, { veil = false, scale = 0.92, sound = "toggle" })
		b.Activated:Connect(function()
			S.color = c.id
			Sheet.refreshSwatches()
			previewColor(c.id)
		end)
		E.swatches[c.id] = { button = b, ring = ring, dot = dot }
	end
	-- 할부 row (the whole 56 px row toggles)
	local loanRow = Instance.new("TextButton")
	loanRow.Name = "LoanRow"
	loanRow.Text = ""
	loanRow.AutoButtonColor = false
	loanRow.BackgroundColor3 = K.Color.card
	loanRow.BackgroundTransparency = 0
	loanRow.Size = UDim2.new(1, 0, 0, 64)
	loanRow.LayoutOrder = 6
	loanRow.ZIndex = 4
	loanRow.Parent = page
	K.corner(loanRow, K.Radius.md)
	K.stroke(loanRow, nil, 1, 0.92)
	text(loanRow, { Name = "Title", Text = "할부로 사기", Font = K.Font.bold, TextSize = K.Type.bodySm, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -90, 0, 18), ZIndex = 5 })
	E.loanText = text(loanRow, { Name = "Quote", Text = "", TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -90, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	local tg = K.Toggle(loanRow, { value = false, color = K.Color.gold, onChange = function(v)
		S.loan = v
		Sheet.refreshBuy()
	end })
	tg.button.AnchorPoint = Vector2.new(1, 0.5)
	tg.button.Position = UDim2.new(1, -8, 0.5, 0)
	tg.button.ZIndex = 6
	E.loanToggle = tg
	E.loanRow = loanRow
	loanRow.Activated:Connect(function()
		if loanRow:GetAttribute("Disabled") then
			return
		end
		K.feedback("toggle")
		tg.set(not tg.value)
	end)
	-- total
	local total = K.Card(page, { Name = "Total", Size = UDim2.new(1, 0, 0, 62), LayoutOrder = 7, ZIndex = 4 })
	text(total, { Name = "Label", Text = "지금 결제", TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.5, 0, 0, 16), ZIndex = 5 })
	E.total = text(total, { Name = "Amount", Text = "", Font = K.Font.heavy, TextSize = 22, Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, 28), ZIndex = 5 })
	K.mono(E.total)
	E.payNote = text(total, { Name = "Note", Text = "", TextSize = K.Type.micro, TextColor3 = K.Color.faint, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0.5, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 })
	-- actions
	local acts = K.frame(page, { Name = "Actions", Size = UDim2.new(1, 0, 0, BTN), LayoutOrder = 8, ZIndex = 4 })
	E.testBtn = K.Button(acts, { name = "TestDrive", text = "시승 60초", icon = "🏁", style = "secondary", size = UDim2.new(0.42, -4, 1, 0), zIndex = 5, onClick = function()
		Sheet.testDrive()
	end })
	E.buyBtn = K.Button(acts, { name = "Buy", text = "구매하기", style = "primary", anchor = Vector2.new(1, 0), position = UDim2.fromScale(1, 0), size = UDim2.new(0.58, -4, 1, 0), zIndex = 5, onClick = function()
		Sheet.buy()
	end })
	E.buyNote = text(page, { Name = "Note", Text = string.format("최대 %d대 · 되팔면 산 값의 %d%% · 통장에서 결제 (부족하면 현금)", GS.MAX_CARS, math.floor(GS.SELL_RATE * 100)), TextSize = K.Type.micro, TextColor3 = K.Color.faint, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 9, ZIndex = 4 })
end

function Sheet.refreshSwatches()
	for id, s in E.swatches or {} do
		local on = id == S.color
		s.ring.Transparency = if on then 0 else 1
		K.tween(s.dot, 0.18, { Size = if on then UDim2.fromOffset(42, 42) else UDim2.fromOffset(36, 36) })
	end
	local entry = GS.colorEntry(S.color)
	E.colorLabel.Text = "색상 · " .. entry.name
end

function Sheet.renderKinds()
	clear(E.kindRow)
	K.list(E.kindRow, true, 8, nil, Enum.VerticalAlignment.Center)
	for i, kind in GS.KIND_ORDER do
		local c = GS.CATALOG[kind]
		chip(E.kindRow, c.glyph .. " " .. c.label, kind == S.kind, i, function()
			if S.kind ~= kind then
				S.kind = kind
				S.color = nil
				Sheet.renderKinds()
				Sheet.refreshBuy()
				startShow(kind)
				frameCamera()
			end
		end)
	end
end

function Sheet.refreshBuy()
	local c = GS.CATALOG[S.kind]
	if not c or not E.carName then
		return
	end
	if not S.color then
		local m = displayFor(S.kind)
		local pid = m and m:GetAttribute("PaintId")
		S.color = if type(pid) == "string" then pid else GS.DEFAULT_COLOR
	end
	E.carGlyph:FindFirstChildWhichIsA("TextLabel", true).Text = c.glyph
	K.setText(E.carName, c.full or c.label)
	E.carBlurb.Text = c.blurb
	local sp = specOf(S.kind)
	E.carSpec.Text = if sp then string.format("최고 %d km/h · %d인승 · %s", sp.topKmh, c.seats or 5, DRIVE_KO[sp.drive] or "") else string.format("%d인승", c.seats or 5)
	E.carTag.Visible = c.tag ~= nil
	E.carTag.Text = c.tag or ""
	-- grade labels with prices
	for _, b in E.grade.frame:GetChildren() do
		if b:IsA("TextButton") then
			if b.Name == "Seg_used" then
				b.Text = "중고 " .. won(c.used)
			elseif b.Name == "Seg_new" then
				b.Text = "신차 " .. won(c.new)
			end
		end
	end
	local price = GS.price(S.kind, S.grade) or 0
	local canLoan = GS.canLoan(price)
	E.loanRow:SetAttribute("Disabled", if canLoan then nil else true)
	if not canLoan and S.loan then
		S.loan = false
		E.loanToggle.set(false, true)
	end
	E.loanRow.BackgroundTransparency = if canLoan then 0 else 0.5
	local q = GS.loanQuote(price)
	if canLoan then
		E.loanText.Text = string.format("계약금 %s · 하루 %s × %d일 (이자 %d%%)", won(q.down), won(q.daily), q.days, math.floor(GS.LOAN.rate * 100))
	else
		E.loanText.Text = string.format("%s 이상 차만 할부가 돼요", won(GS.LOAN.minPrice))
	end
	local pay = if S.loan then q.down else price
	K.setText(E.total, won(pay))
	local st = S.status
	if st then
		local afford = (st.bank or 0) >= pay or (st.cash or 0) >= pay
		E.payNote.Text = if afford then "통장 결제 가능" else "잔액 부족"
		E.payNote.TextColor3 = if afford then K.Color.green else K.Color.orange
	else
		E.payNote.Text = ""
	end
	E.buyBtn.Text = if S.loan then "할부로 계약" else "구매하기"
	Sheet.refreshSwatches()
end

---------------------------------------------------------------------------------------------------
-- 내 차 page
---------------------------------------------------------------------------------------------------
local function actionButton(parent: Instance, label: string, style: string, order: number, onClick: () -> ()): TextButton
	return K.Button(parent, { name = "Act", text = label, style = style, size = UDim2.new(1 / 3, -6, 1, 0), order = order, zIndex = 6, textSize = K.Type.caption + 1, onClick = onClick })
end

function Sheet.renderMine()
	local page = E.pages.mine
	clear(page)
	K.list(page, false, 10)
	local cars = Net.cars or {}
	if #cars == 0 then
		local card = K.Card(page, { Name = "Empty", Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 1, ZIndex = 4 })
		text(card, { Text = "🚗", TextSize = 32, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 38), ZIndex = 5 })
		text(card, { Text = "아직 내 차가 없어요", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 20), ZIndex = 5 })
		text(card, { Text = "쇼룸의 차 앞에서 '구매 / 시승'을 누르거나 렌트로 먼저 타 보세요", TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 78), Size = UDim2.new(1, -32, 0, 34), ZIndex = 5 })
		return
	end
	for i, car in cars do
		local card = K.Card(page, { Name = "Car_" .. car.id, Size = UDim2.new(1, 0, 0, 142), LayoutOrder = i, ZIndex = 4 })
		local tile = K.frame(card, { Name = "Paint", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 0, BackgroundColor3 = GS.color3(car.color), ZIndex = 5 })
		K.corner(tile, UDim.new(0, 14))
		K.gradient(tile, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160) }, 90)
		text(tile, { Text = car.glyph or "🚗", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 6 })
		local name = (car.label or "내 차") .. (if car.rental then "  🔑 렌트" else "") .. (if car.loan then "  · 할부" else "")
		text(card, { Name = "Name", Text = name, Font = K.Font.bold, TextSize = K.Type.body, Position = UDim2.fromOffset(70, 12), Size = UDim2.new(1, -82, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		local plate = text(card, { Name = "Plate", Text = car.plate or "", Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(70, 34), Size = UDim2.new(1, -82, 0, 16), ZIndex = 5 })
		K.mono(plate)
		local band = GS.BANDS[car.band] or GS.BANDS.good
		local col = Color3.fromRGB(band.color[1], band.color[2], band.color[3])
		local track = K.frame(card, { Name = "CondTrack", Position = UDim2.fromOffset(70, 56), Size = UDim2.new(1, -170, 0, 6), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, ZIndex = 5 })
		K.corner(track, UDim.new(0.5, 0))
		local fill = K.frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0, BackgroundColor3 = col, ZIndex = 6 })
		K.corner(fill, UDim.new(0.5, 0))
		K.tween(fill, 0.24, { Size = UDim2.fromScale(math.clamp((car.cond or 100) / 100, 0, 1), 1) })
		local extra = ""
		if car.rental and car.rentalLeft then
			extra = string.format(" · %d분 남음", math.ceil(car.rentalLeft / 60))
		elseif car.loan then
			extra = string.format(" · 할부 %s 남음", won(car.loan.remaining or 0))
		end
		text(card, { Name = "Cond", Text = string.format("%d%% %s%s", car.cond or 100, band.label, extra), Font = K.Font.bold, TextSize = K.Type.micro, TextColor3 = col, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 51), Size = UDim2.fromOffset(150, 14), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		local acts = K.frame(card, { Name = "Actions", Position = UDim2.new(0, 10, 1, -(BTN + 10)), Size = UDim2.new(1, -20, 0, BTN), ZIndex = 5 })
		K.list(acts, true, 8)
		-- 1) call / tow / at the garage
		if car.out then
			actionButton(acts, "🚗 타는 중", "tonal", 1, function()
				toast("info", "이미 나와 있는 차예요", "길에 세워 둔 내 차를 찾아 보세요")
			end)
		elseif car.band == "dead" and not car.towed then
			actionButton(acts, "🚛 견인 " .. GS.formatWon(GS.TOW.fee), "gold", 1, function()
				Sheet.op("tow", { id = car.id })
			end)
		elseif car.callable then
			actionButton(acts, "🚗 부르기", "primary", 1, function()
				Sheet.op("call", { id = car.id }, true)
			end)
		else
			actionButton(acts, "정비소에 있음", "secondary", 1, function()
				toast("info", "정비 후 탈 수 있어요", car.why)
			end)
		end
		-- 2) repair
		local cost = car.repair or 0
		actionButton(acts, if cost > 0 then "🔧 정비 " .. won(cost) else "🔧 상태 좋음", if cost > 0 then "gold" else "secondary", 2, function()
			if cost <= 0 then
				toast("info", "정비가 필요 없어요", "상태 100%")
				return
			end
			Sheet.op("repair", { id = car.id })
		end)
		-- 3) sell (tap twice)
		if car.rental then
			actionButton(acts, "렌트 차", "secondary", 3, function()
				toast("info", "렌트 차는 팔 수 없어요")
			end)
		else
			local b
			b = actionButton(acts, "💸 팔기 " .. won(car.sell or 0), "danger", 3, function()
				if S.sellArm == car.id then
					S.sellArm = nil
					Sheet.op("sell", { id = car.id })
				else
					S.sellArm = car.id
					b.Text = "한 번 더 누르면 판매"
					task.delay(3, function()
						if S.sellArm == car.id then
							S.sellArm = nil
							if b.Parent then
								b.Text = "💸 팔기 " .. won(car.sell or 0)
							end
						end
					end)
				end
			end)
		end
	end
	local rows = {}
	for _, c in page:GetChildren() do
		if c:IsA("GuiObject") then
			table.insert(rows, c)
		end
	end
	K.stagger(rows)
end

---------------------------------------------------------------------------------------------------
-- 렌트 page
---------------------------------------------------------------------------------------------------
function Sheet.renderRent()
	local page = E.pages.rent
	clear(page)
	K.list(page, false, 10)
	local R = GS.RENTAL
	local c = GS.CATALOG[R.kind]
	local active: any = nil
	for _, car in Net.cars or {} do
		if car.rental then
			active = car
		end
	end
	local card = K.Card(page, { Name = "RentCard", Size = UDim2.new(1, 0, 0, 176), LayoutOrder = 1, ZIndex = 4 })
	K.gradient(card, K.Grad.card, 90)
	local tile = K.iconTile(card, 52, c.glyph, K.Color.teal, false)
	tile.Position = UDim2.fromOffset(12, 12)
	tile.ZIndex = 5
	text(card, { Text = c.label .. " 하루 렌트", Font = K.Font.heavy, TextSize = K.Type.title2, Position = UDim2.fromOffset(76, 12), Size = UDim2.new(1, -88, 0, 24), ZIndex = 5 })
	text(card, { Text = string.format("%s · 게임 시간 하루 (%d분) · 보험 포함", won(R.fee), math.floor(R.seconds / 60)), TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(76, 40), Size = UDim2.new(1, -88, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	text(card, { Text = "차가 없어도 바로 운전! 반납은 시간이 끝나면 자동이에요. 내 차 대수에는 안 들어가요.", TextSize = K.Type.caption, TextColor3 = K.Color.text, TextWrapped = true, Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -28, 0, 34), ZIndex = 5 })
	local b = K.Button(card, { name = "Rent", text = if active then string.format("렌트 중 · %d분 남음", math.ceil((active.rentalLeft or 0) / 60)) else "렌트하고 바로 타기", icon = "🔑", style = if active then "secondary" else "success", anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -12), size = UDim2.new(1, -24, 0, BTN), zIndex = 6, onClick = function()
		if active then
			Sheet.op("call", { id = active.id }, true)
			return
		end
		Sheet.op("rent", nil, true)
	end })
	local _ = b
end

---------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------
function Sheet.op(op: string, payload: { [string]: any }?, closeOnOk: boolean?)
	if S.busy then
		return
	end
	S.busy = true
	local res = Net.request(op, payload)
	S.busy = false
	if res.ok then
		K.feedback(if op == "sell" then "money" else "success")
		if op == "call" or op == "rent" then
			local label = res.label or "내 차"
			toast("success", "🚗 " .. tostring(label) .. " 도착!", if res.meters then string.format("%dm 떨어진 도로에 세워 뒀어요", res.meters) else "정비소 앞에 세워 뒀어요")
		elseif op == "repair" then
			toast("info", "🔧 정비를 시작했어요", if res.onLift then "리프트에서 정비 중이에요 · 잠시만요" else "차를 리프트로 올려요 · 잠시만요")
		end
		if closeOnOk then
			Sheet.close()
		end
	else
		K.feedback("error")
		toast("warn", "할 수 없어요", tostring(res.message or ""))
	end
	Sheet.refreshStatus()
end

function Sheet.refreshStatus()
	task.spawn(function()
		local st = Net.status()
		if st.ok then
			S.status = st
			if E.money then
				E.money.Text = string.format("통장 %s · 현금 %s · 내 차 %d/%d", won(st.bank or 0), won(st.cash or 0), st.owned or 0, st.max or GS.MAX_CARS)
			end
			if S.open and S.tab == "buy" then
				Sheet.refreshBuy()
			end
		end
	end)
end

function Sheet.buy()
	if S.busy then
		return
	end
	S.busy = true
	K.setButtonLoading(E.buyBtn, true, "결제 중…")
	local res = Net.request("buy", { kind = S.kind, grade = S.grade, color = S.color, loan = S.loan })
	K.setButtonLoading(E.buyBtn, false)
	S.busy = false
	if res.ok then
		K.feedback("money")
		Sheet.showReceipt(res)
	else
		K.feedback("error")
		toast("warn", "구매하지 못했어요", tostring(res.message or ""))
	end
	Sheet.refreshStatus()
end

function Sheet.testDrive()
	if S.busy then
		return
	end
	S.busy = true
	K.setButtonLoading(E.testBtn, true, "준비 중…")
	local res = Net.request("testdrive", { kind = S.kind, color = S.color })
	K.setButtonLoading(E.testBtn, false)
	S.busy = false
	if res.ok then
		K.feedback("success")
		Sheet.close(true)
	else
		K.feedback("error")
		toast("warn", "시승할 수 없어요", tostring(res.message or ""))
	end
end

-- Receipt card (animated) after a purchase: plate, what was paid, 할부, "지금 타기".
function Sheet.showReceipt(res: { [string]: any })
	local rc = E.receipt
	clear(rc)
	local r = res.receipt or {}
	local car = res.car or {}
	rc.Visible = true
	rc.BackgroundTransparency = 1
	K.tween(rc, TWEEN_IN, { BackgroundTransparency = 0.02 })
	local holder = K.frame(rc, { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -28, 0, 330), ZIndex = 21 })
	local sc = Instance.new("UIScale")
	sc.Scale = 0.9
	sc.Parent = holder
	K.tween(sc, TWEEN_IN, { Scale = 1 })
	text(holder, { Text = "🎉", TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 48), ZIndex = 22 })
	text(holder, { Text = "구매 완료! 내 차가 생겼어요", Font = K.Font.heavy, TextSize = K.Type.title2, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 24), ZIndex = 22 })
	text(holder, { Text = tostring(r.label or car.label or ""), TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 22 })
	-- Korean plate badge
	local plate = K.frame(holder, { Name = "Plate", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(220, 50), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(246, 246, 244), ZIndex = 22 })
	K.corner(plate, UDim.new(0, 8))
	K.stroke(plate, Color3.fromRGB(20, 20, 20), 2, 0)
	local holo = K.frame(plate, { Name = "Holo", Position = UDim2.fromOffset(6, 8), Size = UDim2.fromOffset(10, 34), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 100, 160), ZIndex = 23 })
	K.corner(holo, UDim.new(0, 3))
	local pt = text(plate, { Text = tostring(r.plate or car.plate or ""), Font = K.Font.heavy, TextSize = 24, TextColor3 = Color3.fromRGB(16, 16, 16), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 23 })
	local _ = pt
	local lines = {}
	table.insert(lines, string.format("결제 %s (%s)", won(r.paid or 0), if r.account == "cash" then "현금" else "통장"))
	if type(r.loan) == "table" then
		table.insert(lines, string.format("할부 하루 %s × %d일 · 총 %s", won(r.loan.daily or 0), r.loan.days or 0, won(r.loan.total or 0)))
	end
	table.insert(lines, string.format("상태 %d%% · 되팔면 %s", car.cond or 100, won(car.sell or 0)))
	for i, l in lines do
		text(holder, { Text = l, TextSize = K.Type.bodySm, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 164 + (i - 1) * 22), Size = UDim2.new(1, 0, 0, 20), ZIndex = 22 })
	end
	local id = car.id
	K.Button(holder, { name = "Drive", text = "지금 타기", icon = "🚗", style = "primary", anchor = Vector2.new(0, 1), position = UDim2.new(0, 0, 1, 0), size = UDim2.new(0.6, -4, 0, BTN), zIndex = 23, onClick = function()
		rc.Visible = false
		if id then
			Sheet.op("call", { id = id }, true)
		end
	end })
	K.Button(holder, { name = "Ok", text = "확인", style = "secondary", anchor = Vector2.new(1, 1), position = UDim2.new(1, 0, 1, 0), size = UDim2.new(0.4, -4, 0, BTN), zIndex = 23, onClick = function()
		K.tween(rc, TWEEN_OUT, { BackgroundTransparency = 1 })
		rc.Visible = false
	end })
	K.sheen(plate, { duration = 1.1, delay = 0.25, strength = 0.6 })
end

---------------------------------------------------------------------------------------------------
-- Open / close / tabs
---------------------------------------------------------------------------------------------------
function Sheet.setTab(id: string)
	if not E.pages[id] then
		id = "buy"
	end
	S.tab = id
	if E.tabs.value ~= id then
		E.tabs.set(id, true)
	end
	for k, f in E.pages do
		local on = k == id
		if on and not f.Visible then
			f.Visible = true
			f.Position = UDim2.fromOffset(18, 0)
			K.tween(f, 0.2, { Position = UDim2.fromOffset(0, 0) })
		elseif not on then
			f.Visible = false
		end
	end
	if id == "buy" then
		Sheet.renderKinds()
		Sheet.refreshBuy()
		startShow(S.kind)
		frameCamera()
	else
		restoreShow()
		releaseCamera()
		if id == "mine" then
			Sheet.renderMine()
		else
			Sheet.renderRent()
		end
	end
end

function Sheet.open(opts: { [string]: any }?)
	local o = opts or {}
	if type(o.kind) == "string" and GS.CATALOG[o.kind] then
		if S.kind ~= o.kind then
			S.color = nil
		end
		S.kind = o.kind
	end
	local wasOpen = S.open
	S.open = true
	E.receipt.Visible = false
	Sheet.layout()
	E.gui.Enabled = true
	E.gui:SetAttribute("HideGwangalliHUD", true)
	local r = E.rect
	if not wasOpen then
		local mt = Layout.metrics()
		local from = if mt.class == "phoneP" then UDim2.fromOffset(r.x, r.y + 60) else UDim2.fromOffset(r.x + 60, r.y)
		E.panel.Position = from
		E.scale.Scale = 0.97
		K.tween(E.panel, TWEEN_IN, { Position = UDim2.fromOffset(r.x, r.y) })
		K.tween(E.scale, TWEEN_IN, { Scale = 1 })
		K.feedback("open")
		if Layout.metrics().touch then
			controls(false)
		end
	end
	Sheet.setTab(o.tab or "buy")
	Sheet.refreshStatus()
end

function Sheet.close(keepCamera: boolean?)
	if not S.open then
		return
	end
	S.open = false
	restoreShow()
	if not keepCamera then
		releaseCamera()
	else
		local cam = workspace.CurrentCamera
		savedCam = nil
		if cam then
			cam.CameraType = Enum.CameraType.Custom
		end
	end
	controls(true)
	local r = E.rect
	local mt = Layout.metrics()
	local to = if mt.class == "phoneP" then UDim2.fromOffset(r.x, r.y + 60) else UDim2.fromOffset(r.x + 60, r.y)
	K.tween(E.panel, TWEEN_OUT, { Position = to })
	K.tween(E.scale, TWEEN_OUT, { Scale = 0.97 })
	K.feedback("close")
	task.delay(TWEEN_OUT, function()
		if not S.open then
			E.gui.Enabled = false
			E.gui:SetAttribute("HideGwangalliHUD", false)
		end
	end)
end

function Sheet.isOpen(): boolean
	return S.open
end

-- the sheet never outlives the character (respawn / teleport while open)
player.CharacterAdded:Connect(function()
	if S.open then
		Sheet.close()
	end
end)
local _ = RunService

return Sheet
