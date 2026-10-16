-- GwangalliPasses/QoLClient (client): the client half of pass #3's shorter waits.
--   * the KO screen (GwangalliArms/CombatUI) shows "병원으로 이송" after the client's own
--     A.KO.SELF_HELP_AFTER: for an owner it is halved on this client only (the server's koHelp wrap allows it)
--   * a chip under the KO screen counts down to the 편의 패스 hospital transfer (Player GwPassQoLKOEnd)
--   * the jail cut arrives as a toast (Event "qol")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QoLClient = {}

local P: any, K: any, Lines: any, Config: any
local A: any = nil
local origSelfHelp: number? = nil
local chipGui: ScreenGui? = nil
local chipLabel: TextLabel? = nil

local function owns(): boolean
	return P.has(Players.LocalPlayer, "Convenience")
end

local function applyKO()
	if not A or type(A.KO) ~= "table" then
		return
	end
	if origSelfHelp == nil then
		origSelfHelp = A.KO.SELF_HELP_AFTER
	end
	local base = origSelfHelp or 20
	A.KO.SELF_HELP_AFTER = if owns() then base * Config.QOL.KO_MULT else base
end

local function chip(): TextLabel
	if chipLabel and chipLabel.Parent then
		return chipLabel
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliPassesKO"
	g.ResetOnSpawn = false
	g.DisplayOrder = 60
	g.Enabled = false
	g.Parent = pg
	chipGui = g
	local l = K.text(g, { Name = "Chip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(330, 34), Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = Color3.fromRGB(57, 255, 136), TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.15, BackgroundColor3 = Color3.fromRGB(10, 16, 14) })
	K.corner(l, UDim.new(0.5, 0))
	K.stroke(l, Color3.fromRGB(57, 255, 136), 1, 0.5)
	chipLabel = l
	return l
end

local function tick()
	local lp = Players.LocalPlayer
	local ch = lp.Character
	local down = ch ~= nil and ch:GetAttribute("GwKO") == true
	local endsAt = lp:GetAttribute(P.Attr.KOEnd)
	if not down or type(endsAt) ~= "number" or not owns() then
		if chipGui then
			chipGui.Enabled = false
		end
		return
	end
	local state = ch and ch:GetAttribute("ArmsKO")
	if state == "transport" or state == "firstaid" then
		if chipGui then
			chipGui.Enabled = false
		end
		return
	end
	local l = chip()
	local left = math.max(0, math.ceil(endsAt - P.serverNow()))
	l.Text = if lp:GetAttribute("GwPassQoLKOEms") == true then Lines.t("ko_chip_ems", left) else Lines.t("ko_chip", left)
	if chipGui then
		chipGui.Enabled = true
	end
end

function QoLClient.start(ctx: any)
	P, K, Lines, Config = ctx.P, ctx.K, ctx.P.Lines, ctx.P.Config
	local m = ReplicatedStorage:WaitForChild("GwangalliArmsShared", 30)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			A = res
		end
	end
	applyKO()
	ctx.Store.changed(function(key: string)
		if key == "Convenience" then
			applyKO()
		end
	end)
	ctx.Net.on("qol", function(payload: any)
		if payload.what == "jail" then
			K.toast({ kind = "success", icon = "⚡", title = tostring(payload.text or ""), body = Lines.t("app_title") })
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			tick()
		end
	end)
end

return QoLClient
