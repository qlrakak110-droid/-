-- GwangalliPasses/HudButton (client): the "👑 VIP" 패스 상점 shortcut on the HUD, right under the place's
-- "🚗 내 차" button (PlayerGui.GWIntegratedCarShortcut.MyCar; Config.HUD.FALLBACK_POS when it is missing),
-- plus the chat command /패스 (/vip). Hidden while driving, while the phone or the app is open, while knocked
-- out, and whenever another full-screen UI asks the HUD to hide (HideGwangalliHUD).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local HudButton = {}

local ctx: any
local P: any, K: any, Config: any
local gui: ScreenGui? = nil
local button: TextButton? = nil
local others: { [ScreenGui]: boolean } = {}

local GOLD = Color3.fromRGB(255, 194, 71)
local MAGENTA = Color3.fromRGB(255, 79, 163)

local function hiddenByOthers(): boolean
	for g in others do
		if g.Parent and g.Enabled and g:GetAttribute("HideGwangalliHUD") == true then
			return true
		end
	end
	return false
end

local function shouldShow(): boolean
	if not P.anyAvailable() or ctx.Hub.isOpen() then
		return false
	end
	local ch = Players.LocalPlayer.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		return false
	end
	if ch and ch:GetAttribute("GwKO") == true then
		return false
	end
	local phone = ctx.PhoneHook.phoneGui()
	if phone and phone.Enabled then
		return false
	end
	return not hiddenByOthers()
end

local function place()
	local b = button
	if not b then
		return
	end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local sc = pg and pg:FindFirstChild("GWIntegratedCarShortcut")
	local my = sc and sc:FindFirstChild("MyCar")
	if my and my:IsA("GuiObject") and my.Visible then
		b.AnchorPoint = my.AnchorPoint
		b.Position = my.Position + UDim2.fromOffset(0, my.Size.Y.Offset + 6)
		b.Size = UDim2.fromOffset(my.Size.X.Offset, Config.HUD.SIZE.Y)
	else
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = Config.HUD.FALLBACK_POS
		b.Size = UDim2.fromOffset(Config.HUD.SIZE.X, Config.HUD.SIZE.Y)
	end
end

local function open()
	ctx.Hub.open("panel", "pass")
end

function HudButton.start(c: any)
	ctx = c
	P, K, Config = c.P, c.K, c.P.Config
	if not Config.HUD.ENABLED then
		return
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliPassesHud"
	g.ResetOnSpawn = false
	g.DisplayOrder = 5
	g.Parent = pg
	gui = g
	local b = Instance.new("TextButton")
	b.Name = "VipShortcut"
	b.Text = "👑 VIP"
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(40, 20, 4)
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Parent = g
	K.corner(b, 12)
	K.gradient(b, { GOLD, MAGENTA }, 20)
	K.stroke(b, Color3.new(1, 1, 1), 1, 0.6)
	pcall(K.pressable, b)
	b.Activated:Connect(open)
	button = b
	place()
	-- other HUD guis that may ask us to hide
	local function consider(x: Instance)
		if x:IsA("ScreenGui") and x ~= g then
			others[x] = true
		end
	end
	for _, x in pg:GetChildren() do
		consider(x)
	end
	pg.ChildAdded:Connect(consider)
	pg.ChildRemoved:Connect(function(x: Instance)
		others[x :: any] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.3 then
			return
		end
		acc = 0
		b.Visible = shouldShow()
		place()
	end)
	-- /패스 · /vip
	pcall(function()
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "GwangalliPassesCommand"
		cmd.PrimaryAlias = "/패스"
		cmd.SecondaryAlias = "/vip"
		cmd.Triggered:Connect(function()
			open()
		end)
		cmd.Parent = TextChatService
	end)
end

return HudButton
