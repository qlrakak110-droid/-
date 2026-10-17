-- GwangalliShopCrew client / Dialog: the conversation sheet (the place's premium kit GwangalliUI.DialogBox when it
-- exists, a lite card of the same layout otherwise). Every node comes from the server; a choice sends only its id.
--   * placed in GwangalliLayout's "dialog" slot and lifted above ShopLife's seated HUD (LifeHud) when it shows
--   * PC: number keys 1-9 pick a choice, Esc closes   gamepad: the first choice is selected, B closes   touch: tap
--   * the ScreenGui carries HideGwangalliHUD = true while a dialog shows (the always-on HUD steps aside)
--   * pushed dialogs (the waiter at your table) have a timer ring and close by themselves
--   Dialog.init(ctx)   ctx = { player, gui (PlayerGui), K?, Layout?, Net }   Dialog.show(data)   Dialog.hide()

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Dialog = {}

local ctx: any = nil
local screen: ScreenGui? = nil
local box: any = nil
local lite = false
local cur: any = nil -- the data shown
local busy = false
local autoSerial = 0

local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }

-------------------------------------------------------------------------------------------------
-- lite card (no GwangalliUI)
-------------------------------------------------------------------------------------------------
local function liteBox(gui: ScreenGui): any
	local api: any = { visible = false }
	local panel = Instance.new("Frame")
	panel.Name = "CrewDialog"
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 40)
	panel.BackgroundTransparency = 0.06
	panel.Size = UDim2.fromOffset(460, 200)
	panel.Visible = false
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent = panel
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 255, 255)
	st.Transparency = 0.86
	st.Parent = panel
	local portrait = Instance.new("TextLabel")
	portrait.Name = "Portrait"
	portrait.Size = UDim2.fromOffset(48, 48)
	portrait.Position = UDim2.fromOffset(14, 12)
	portrait.BackgroundColor3 = Color3.fromRGB(61, 214, 245)
	portrait.TextSize = 26
	portrait.Font = Enum.Font.GothamBold
	portrait.TextColor3 = Color3.new(1, 1, 1)
	portrait.Parent = panel
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = portrait
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(72, 12)
	name.Size = UDim2.new(1, -120, 0, 24)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Parent = panel
	local role = Instance.new("TextLabel")
	role.BackgroundTransparency = 1
	role.Position = UDim2.fromOffset(72, 36)
	role.Size = UDim2.new(1, -120, 0, 18)
	role.Font = Enum.Font.Gotham
	role.TextSize = 13
	role.TextXAlignment = Enum.TextXAlignment.Left
	role.TextColor3 = Color3.fromRGB(180, 188, 210)
	role.Parent = panel
	local closeB = Instance.new("TextButton")
	closeB.Size = UDim2.fromOffset(44, 44)
	closeB.Position = UDim2.new(1, -52, 0, 8)
	closeB.BackgroundTransparency = 1
	closeB.Text = "✕"
	closeB.TextSize = 20
	closeB.Font = Enum.Font.GothamBold
	closeB.TextColor3 = Color3.fromRGB(200, 206, 222)
	closeB.Parent = panel
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 66)
	body.Size = UDim2.new(1, -32, 0, 60)
	body.Font = Enum.Font.GothamMedium
	body.TextSize = 16
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextColor3 = Color3.fromRGB(236, 240, 250)
	body.Parent = panel
	local grid = Instance.new("Frame")
	grid.Name = "Choices"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(14, 130)
	grid.Size = UDim2.new(1, -28, 0, 60)
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -6, 0, 44)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local buttons: { TextButton } = {}
	local rect = { x = 8, y = 8, w = 460, h = 400 }
	local function arrange(n: number)
		local cols = if rect.w >= 420 then 2 else 1
		layout.CellSize = UDim2.new(1 / cols, -6, 0, 44)
		local rows = math.ceil(n / cols)
		local textH = math.max(40, math.min(140, body.TextBounds.Y + 6))
		body.Size = UDim2.new(1, -32, 0, textH)
		grid.Position = UDim2.fromOffset(14, 70 + textH)
		local h = 70 + textH + rows * 52 + 8
		grid.Size = UDim2.new(1, -28, 0, rows * 52)
		panel.Size = UDim2.fromOffset(rect.w, h)
		panel.Position = UDim2.fromOffset(rect.x, rect.y + rect.h - h)
	end
	function api.place(r: any, _bottom: boolean?)
		rect = r
		arrange(#buttons)
	end
	function api.show(data: any)
		api.visible = true
		panel.Visible = true
		portrait.Text = tostring(data.icon or "🙂")
		local col = data.portraitColor
		if type(col) == "table" then
			portrait.BackgroundColor3 = Color3.fromRGB(col[1] or 61, col[2] or 214, col[3] or 245)
		end
		name.Text = tostring(data.name or "")
		role.Text = tostring(data.role or "")
		body.Text = tostring(data.text or "")
		for _, b in buttons do
			b:Destroy()
		end
		table.clear(buttons)
		for i, ch in data.choices or {} do
			local b = Instance.new("TextButton")
			b.Name = "Choice"
			b.LayoutOrder = i
			b.AutoButtonColor = true
			b.BackgroundColor3 = if ch.style == "primary" then Color3.fromRGB(61, 160, 245) elseif ch.style == "ghost" then Color3.fromRGB(40, 46, 70) else Color3.fromRGB(52, 60, 92)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 15
			b.TextColor3 = Color3.new(1, 1, 1)
			b.TextWrapped = true
			b.Text = tostring(ch.label)
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 12)
			bc.Parent = b
			b.Activated:Connect(function()
				if api.onChoice then
					task.spawn(api.onChoice, ch.id, ch)
				end
			end)
			b.Parent = grid
			table.insert(buttons, b)
		end
		task.defer(arrange, #buttons)
	end
	function api.hide()
		api.visible = false
		panel.Visible = false
		if api.onHidden then
			task.spawn(api.onHidden)
		end
	end
	function api.setTimer(_t: any) end
	closeB.Activated:Connect(function()
		if api.onClose then
			task.spawn(api.onClose)
		end
		api.hide()
	end)
	api.panel = panel
	api.buttons = buttons
	return api
end

-------------------------------------------------------------------------------------------------
-- layout: the Layout "dialog" slot, above ShopLife's seated HUD
-------------------------------------------------------------------------------------------------
local function lifeHudTop(): number?
	local pg = ctx.gui
	local bui = pg:FindFirstChild("GwangalliBuildingsUI")
	local hud = bui and bui:FindFirstChild("LifeHud", true)
	if hud and hud:IsA("GuiObject") and hud.Visible and (bui :: ScreenGui).Enabled then
		return hud.AbsolutePosition.Y
	end
	return nil
end

local function place()
	if not box or not screen then
		return
	end
	local size = screen.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 10 or H < 10 then
		return
	end
	local r: any = nil
	if ctx.Layout and type(ctx.Layout.rect) == "function" then
		local ok, rr = pcall(ctx.Layout.rect, "dialog")
		if ok and type(rr) == "table" and rr.w and rr.w > 100 then
			r = { x = rr.x, y = rr.y, w = rr.w, h = rr.h }
		end
	end
	if not r then
		local w = math.min(620, W - 24)
		r = { x = (W - w) / 2, y = 8, w = w, h = H - 24 }
	end
	-- above the seated HUD (screen space of the same inset: both ScreenGuis use the safe-area insets)
	local top = lifeHudTop()
	if top then
		local offset = screen.AbsolutePosition.Y
		local limit = top - offset - 10
		if r.y + r.h > limit then
			r.h = math.max(160, limit - r.y)
		end
	end
	if type(box.place) == "function" then
		pcall(box.place, r, true)
	elseif type(box.layout) == "function" then
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		pcall(box.layout, if not touch then "pc" elseif math.min(W, H) >= 600 then "tablet" else "phone", W, H, nil)
	end
end

-------------------------------------------------------------------------------------------------
-- input
-------------------------------------------------------------------------------------------------
local function choiceButtons(): { GuiButton }
	local out = {}
	if not screen then
		return out
	end
	for _, d in screen:GetDescendants() do
		if d:IsA("GuiButton") and d.Name == "Choice" and d.Visible then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = a.AbsolutePosition, b.AbsolutePosition
		if math.abs(pa.Y - pb.Y) > 4 then
			return pa.Y < pb.Y
		end
		return pa.X < pb.X
	end)
	return out
end

local function pick(i: number)
	if not cur then
		return
	end
	local ch = cur.choices and cur.choices[i]
	if ch and box.onChoice then
		task.spawn(box.onChoice, ch.id, ch)
	end
end

local function bindInput(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority("GwShopCrewDialogKeys", function(_, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				if box.onClose then
					task.spawn(box.onClose)
				end
				return Enum.ContextActionResult.Sink
			end
			for i, k in KEYS do
				if input.KeyCode == k then
					pick(i)
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB, table.unpack(KEYS))
	else
		ContextActionService:UnbindAction("GwShopCrewDialogKeys")
	end
end

local function selectFirst()
	if not UserInputService.GamepadEnabled then
		return
	end
	task.delay(0.35, function()
		local bs = choiceButtons()
		if bs[1] then
			pcall(function()
				GuiService.SelectedObject = bs[1]
			end)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- show / hide
-------------------------------------------------------------------------------------------------
function Dialog.hide()
	if not box then
		return
	end
	cur = nil
	autoSerial += 1
	if box.visible ~= false then
		box.hide()
	end
	bindInput(false)
	if screen then
		screen:SetAttribute("HideGwangalliHUD", false)
	end
	pcall(function()
		if GuiService.SelectedObject and screen and GuiService.SelectedObject:IsDescendantOf(screen) then
			GuiService.SelectedObject = nil
		end
	end)
end

function Dialog.show(data: any)
	if not box or type(data) ~= "table" then
		return
	end
	cur = data
	place()
	box.show({
		npcId = data.crewId,
		name = data.name,
		role = data.role,
		portraitColor = data.color,
		icon = data.icon,
		text = data.text,
		choices = data.choices,
		timer = data.timer,
	})
	if screen then
		screen:SetAttribute("HideGwangalliHUD", true)
	end
	bindInput(true)
	selectFirst()
	autoSerial += 1
	local mine = autoSerial
	local secs = if type(data.timer) == "table" and tonumber(data.timer.total) then tonumber(data.timer.total) :: number else nil
	if secs then
		task.delay(secs, function()
			if autoSerial == mine and cur == data then
				ctx.Net.request("close", { token = data.token })
				Dialog.hide()
			end
		end)
	end
end

local function onChoice(id: string)
	if busy or not cur then
		return
	end
	busy = true
	local data = cur
	if ctx.K and type(ctx.K.feedback) == "function" then
		pcall(ctx.K.feedback, "tap")
	end
	local res = ctx.Net.request("choose", { crew = data.crewId, token = data.token, choice = id })
	busy = false
	if cur ~= data then
		return
	end
	if type(res.toast) == "string" and res.toast ~= "" then
		ctx.toast(res.toast, "info")
	end
	if type(res.dialog) == "table" then
		Dialog.show(res.dialog)
	elseif res.close or res.ok == false then
		Dialog.hide()
	end
end

function Dialog.init(c: any)
	ctx = c
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliShopCrewUI"
	g.ResetOnSpawn = false
	g.DisplayOrder = 32
	g.IgnoreGuiInset = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = c.gui
	screen = g
	if c.K and type(c.K.DialogBox) == "function" then
		local ok, d = pcall(c.K.DialogBox, g)
		if ok and type(d) == "table" and type(d.show) == "function" then
			box = d
		end
	end
	if not box then
		box = liteBox(g)
		lite = true
	end
	box.onChoice = onChoice
	box.onClose = function()
		local data = cur
		if data then
			ctx.Net.request("close", { token = data.token })
		end
		Dialog.hide()
	end
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	if c.Layout and type(c.Layout.onChanged) == "function" then
		pcall(c.Layout.onChanged, place)
	end
	-- the seated HUD appearing / going away moves the sheet
	task.spawn(function()
		local last = nil
		while g.Parent do
			local top = lifeHudTop()
			if top ~= last then
				last = top
				if cur then
					place()
				end
			end
			task.wait(0.5)
		end
	end)
	c.Net.on("dialog", function(d)
		Dialog.show(d)
	end)
	c.Net.on("dialog.close", function(d)
		if cur and (d.token == nil or d.token == cur.token) then
			Dialog.hide()
		end
	end)
	-- the character died / respawned: no dialog left hanging
	c.player.CharacterAdded:Connect(function()
		Dialog.hide()
	end)
end

function Dialog.isLite(): boolean
	return lite
end

function Dialog.screen(): ScreenGui?
	return screen
end

return Dialog
