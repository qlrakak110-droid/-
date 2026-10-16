-- GwangalliPasses/PhoneHook (client): the "👑 VIP" icon on the phone.
-- The phone's app registry is closed (GwangalliPhone/Phone.luau APP_META) and its 10-app grid is full on
-- landscape phones, so the icon joins the DOCK as a 5th cell: a copy of the bank dock icon (same size,
-- shadow, gloss, badge) with our gradient + glyph; the dock's UIGridLayout is switched to 5 columns and the
-- cell width is re-derived whenever the phone re-lays itself out. Tapping it opens Hub in "phone" mode.
-- The optional patch patches/GwangalliPasses_Phone.patch makes it a native app (the phone sets the
-- ReplicatedStorage.GwangalliPassesShared attribute PhoneNative); then nothing is injected here.
--   PhoneHook.screen() -> Frame?   PhoneHook.phoneGui() -> ScreenGui?   PhoneHook.appOpen() -> boolean
--   PhoneHook.closePhone()   (a 0.25 s HideGwangalliHUD pulse: the phone closes itself on it)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhoneHook = {}

local ctx: any
local P: any, K: any
local phoneGui: ScreenGui? = nil
local screenFrame: Frame? = nil
local appsFrame: Frame? = nil
local cell: GuiButton? = nil
local badge: Frame? = nil
local lastOurWidth = -1
local pulseGui: ScreenGui? = nil

local GOLD = Color3.fromRGB(255, 194, 71)
local MAGENTA = Color3.fromRGB(255, 79, 163)

function PhoneHook.screen(): Frame?
	return screenFrame
end

function PhoneHook.phoneGui(): ScreenGui?
	return phoneGui
end

-- another phone app is on screen (ours is not one of the phone's apps)
function PhoneHook.appOpen(): boolean
	local a = appsFrame
	if not a then
		return false
	end
	for _, c in a:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			return true
		end
	end
	return false
end

function PhoneHook.closePhone()
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	if not pulseGui or not pulseGui.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "GwangalliPassesPhoneClose"
		g.ResetOnSpawn = false
		g.Enabled = false
		g:SetAttribute("HideGwangalliHUD", true)
		g.Parent = pg
		pulseGui = g
	end
	local g = pulseGui :: ScreenGui
	g.Enabled = true
	task.delay(0.25, function()
		g.Enabled = false
	end)
end

local function nativeMode(): boolean
	local shared = ReplicatedStorage:FindFirstChild("GwangalliPassesShared")
	return shared ~= nil and shared:GetAttribute("PhoneNative") == true
end

local function fitDock(layout: UIGridLayout)
	-- the phone sets CellSize = floor((innerW - 8) / 4) on every layout pass; we turn that into fifths
	local cs = layout.CellSize
	local w = cs.X.Offset
	if w == lastOurWidth then
		return
	end
	local ours = math.floor(w * 4 / 5)
	lastOurWidth = ours
	layout.FillDirectionMaxCells = 5
	layout.CellSize = UDim2.fromOffset(ours, cs.Y.Offset)
end

local function makeIcon(dock: Frame)
	local bank = dock:FindFirstChild("App_bank")
	local c: GuiButton
	if bank and bank:IsA("GuiButton") then
		c = bank:Clone()
		for _, d in c:GetDescendants() do
			if d:IsA("LocalScript") or d:IsA("Script") then
				d:Destroy()
			end
		end
	else
		local b = Instance.new("TextButton")
		b.Text = ""
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		local icon = K.frame(b, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
		K.corner(icon, UDim.new(0.27, 0))
		c = b
		local _ = icon
	end
	c.Name = "App_vip"
	c.LayoutOrder = 99
	local icon = c:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		local g = icon:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(GOLD, MAGENTA)
		else
			K.gradient(icon, { GOLD, MAGENTA }, 120)
		end
		-- keep only the tile's own look (corner, rim, gradient, gloss); the bank glyph and badge go
		for _, d in icon:GetChildren() do
			if not (d:IsA("UICorner") or d:IsA("UIStroke") or d:IsA("UIGradient") or d.Name == "Gloss") then
				d:Destroy()
			end
		end
		local glyph = K.text(icon, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "👑", TextSize = 24, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		local function size()
			-- the phone sizes its emoji glyphs at half the tile (applyHomeLayout)
			glyph.TextSize = math.max(12, math.floor(icon.Size.X.Offset * 0.5))
		end
		size()
		icon:GetPropertyChangedSignal("Size"):Connect(size)
		-- mirror the bank icon's size / position on every phone layout pass
		if bank then
			local bIcon = bank:FindFirstChild("Icon")
			local bShadow = bank:FindFirstChild("IconShadow")
			local myShadow = c:FindFirstChild("IconShadow")
			if bIcon and bIcon:IsA("GuiObject") then
				local function mirror()
					icon.Size = bIcon.Size
					icon.Position = bIcon.Position
					if bShadow and myShadow and bShadow:IsA("GuiObject") and myShadow:IsA("GuiObject") then
						myShadow.Size = bShadow.Size
						myShadow.Position = bShadow.Position
					end
				end
				mirror()
				bIcon:GetPropertyChangedSignal("Size"):Connect(mirror)
				bIcon:GetPropertyChangedSignal("Position"):Connect(mirror)
			end
		end
		badge = K.frame(icon, { Name = "GwDot", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 0, BackgroundColor3 = MAGENTA, Visible = false, ZIndex = 5 })
		K.corner(badge :: Frame, UDim.new(0.5, 0))
	end
	local label = c:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = "VIP"
	end
	-- the copied badge belongs to the bank: hide it
	for _, d in c:GetDescendants() do
		if d:IsA("GuiObject") and d ~= badge and string.find(string.lower(d.Name), "badge", 1, true) then
			d.Visible = false
		end
	end
	pcall(K.pressable, c, { veil = false, scale = 0.9 })
	c.Activated:Connect(function()
		ctx.Hub.open("phone")
		if badge then
			badge.Visible = false
		end
	end)
	c.Parent = dock
	cell = c
end

local function hook(g: ScreenGui)
	phoneGui = g
	task.spawn(function()
		local device = g:WaitForChild("Device", 30)
		local screen = device and device:WaitForChild("Screen", 30)
		if not screen or not screen:IsA("Frame") then
			return
		end
		screenFrame = screen
		appsFrame = screen:WaitForChild("Apps", 30) :: Frame?
		if nativeMode() or not P.anyAvailable() then
			return
		end
		local home = screen:WaitForChild("Home", 30)
		local dock = home and home:WaitForChild("Dock", 30)
		if not dock or not dock:IsA("Frame") or dock:FindFirstChild("App_vip") then
			return
		end
		local layout = dock:FindFirstChildOfClass("UIGridLayout")
		dock:WaitForChild("App_bank", 10)
		if nativeMode() or dock:FindFirstChild("App_vip") then
			return -- the patched phone has its own VIP dock app
		end
		makeIcon(dock)
		if layout then
			lastOurWidth = -1
			fitDock(layout)
			layout:GetPropertyChangedSignal("CellSize"):Connect(function()
				fitDock(layout)
			end)
			layout:GetPropertyChangedSignal("FillDirectionMaxCells"):Connect(function()
				if layout.FillDirectionMaxCells ~= 5 then
					layout.FillDirectionMaxCells = 5
				end
			end)
		end
	end)
end

function PhoneHook.showDot(on: boolean)
	if badge then
		badge.Visible = on
	end
end

function PhoneHook.start(c: any)
	ctx = c
	P, K = c.P, c.K
	-- the patched phone's native VIP app fires this (patches/GwangalliPasses_Phone.patch)
	local lp = Players.LocalPlayer
	local ev = lp:FindFirstChild("GwangalliPassesOpen")
	if not (ev and ev:IsA("BindableEvent")) then
		ev = Instance.new("BindableEvent")
		ev.Name = "GwangalliPassesOpen"
		ev.Parent = lp
	end
	(ev :: BindableEvent).Event:Connect(function(tab: any)
		ctx.Hub.open("phone", if type(tab) == "string" then tab else nil)
	end)
	local pg = lp:WaitForChild("PlayerGui")
	local function consider(g: Instance)
		if g.Name == "GwangalliPhone" and g:IsA("ScreenGui") and g ~= phoneGui then
			hook(g)
		end
	end
	for _, g in pg:GetChildren() do
		consider(g)
	end
	pg.ChildAdded:Connect(consider)
	-- a pass bought while away: a dot on the icon until the app is opened
	c.Store.changed(function(_key: string, owned: boolean)
		if owned then
			PhoneHook.showDot(true)
		end
	end)
end

return PhoneHook
