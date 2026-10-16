-- GwangalliPasses/MarketTab (client): the "블랙마켓" tab (pass #3 편의 패스).
-- A dark "secure app" screen: live connection status (server marketState every 2 s while shown) and three
-- doors into the 총기상's own shop (기본 총기 · 조직 물건 · 탄약). The server opens the existing WeaponShopUI
-- (same stock, same prices, same street checks); the phone closes itself when it opens.
-- Locked: the same screen dimmed, every door opens the purchase prompt.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MarketTab = {}

local ctx: any
local P: any, K: any, Lines: any, Hub: any
local scroll: ScrollingFrame? = nil
local statusLabel: TextLabel? = nil
local statusDot: Frame? = nil
local doors: { TextButton } = {}
local visible = false
local loopId = 0

local NEON = Color3.fromRGB(57, 255, 136)
local DARK = Color3.fromRGB(8, 10, 12)
local RED = Color3.fromRGB(255, 90, 90)

local function owned(): boolean
	return P.has(Players.LocalPlayer, "Convenience")
end

local function setStatus(open: boolean, text: string)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.TextColor3 = if open then NEON else RED
	end
	if statusDot then
		statusDot.BackgroundColor3 = if open then NEON else RED
	end
	for _, d in doors do
		d:SetAttribute("GwOpen", open)
		local stroke = d:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if open then NEON else Color3.fromRGB(80, 90, 86)
		end
	end
end

local function shake(g: GuiObject)
	if K.reduced() then
		return
	end
	local p = g.Position
	for i = 1, 4 do
		local off = if i % 2 == 0 then -6 else 6
		TweenService:Create(g, TweenInfo.new(0.04), { Position = p + UDim2.fromOffset(off, 0) }):Play()
		task.wait(0.04)
	end
	g.Position = p
end

local function door(parent: Instance, tab: string, glyph: string, title: string, sub: string, order: number)
	local b = Instance.new("TextButton")
	b.Name = "Door_" .. tab
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = UDim2.new(1, 0, 0, 68)
	b.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
	b.LayoutOrder = order
	b.Parent = parent
	K.corner(b, 12)
	K.stroke(b, NEON, 1, 0.55)
	K.pressable(b)
	K.text(b, { Text = glyph, TextSize = 26, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(44, 68), TextXAlignment = Enum.TextXAlignment.Center })
	K.text(b, { Text = title, Font = K.Font.bold, TextSize = K.Type.body, TextColor3 = Color3.fromRGB(220, 255, 230), Position = UDim2.fromOffset(60, 14), Size = UDim2.new(1, -96, 0, 20) })
	local subL = K.text(b, { Text = sub, Font = K.Font.mono, TextSize = K.Type.micro, TextColor3 = Color3.fromRGB(120, 170, 140), Position = UDim2.fromOffset(60, 36), Size = UDim2.new(1, -96, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	local _ = subL
	K.text(b, { Text = if owned() then "›" else "🔒", TextSize = 20, TextColor3 = NEON, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(24, 24), TextXAlignment = Enum.TextXAlignment.Center })
	b.Activated:Connect(function()
		if not owned() then
			ctx.Store.buy("Convenience")
			return
		end
		task.spawn(function()
			setStatus(true, "⌛ 보안 연결 중…")
			local res = ctx.Net.request("market", { tab = tab })
			if res.ok then
				ctx.Hub.close()
			else
				setStatus(false, tostring(res.text or res.message or Lines.t("market_inactive")))
				shake(b)
			end
		end)
	end)
	table.insert(doors, b)
	return b
end

local function render()
	local s = scroll
	if not s then
		return
	end
	for _, ch in s:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	doors = {}
	local has = owned()
	local order = 1
	if not has then
		Hub.lockCard(s, "Convenience", order)
		order += 1
	end
	local term = K.frame(s, { Name = "Terminal", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0, BackgroundColor3 = DARK, LayoutOrder = order })
	K.corner(term, 14)
	K.stroke(term, NEON, 1, 0.75)
	K.list(term, false, 8)
	K.pad(term, 12, 12, 12, 12)
	local head = K.frame(term, { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 })
	K.text(head, { Text = "▌" .. Lines.t("market_title") .. "  //  BUSAN-NET", Font = K.Font.mono, TextSize = K.Type.bodySm, TextColor3 = NEON, Size = UDim2.new(1, 0, 0, 18) })
	local dot = K.frame(head, { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(0, 24), BackgroundTransparency = 0, BackgroundColor3 = NEON })
	K.corner(dot, UDim.new(0.5, 0))
	statusDot = dot
	statusLabel = K.text(head, { Text = if has then "⌛ 보안 연결 중…" else Lines.t("locked_tab", P.Config.PASSES.Convenience.Title), Font = K.Font.mono, TextSize = K.Type.micro, TextColor3 = NEON, Position = UDim2.fromOffset(14, 20), Size = UDim2.new(1, -14, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	door(term, "basic", "🔫", Lines.t("market_basic"), Lines.t("market_basic_sub"), 2)
	door(term, "upper", "🕶️", Lines.t("market_upper"), Lines.t("market_upper_sub"), 3)
	door(term, "ammo", "📦", Lines.t("market_ammo"), Lines.t("market_ammo_sub"), 4)
	K.text(term, { Text = Lines.t("market_footer"), Font = K.Font.mono, TextSize = K.Type.micro, TextColor3 = Color3.fromRGB(110, 140, 120), TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9 })
	if not has then
		for _, d in doors do
			d.BackgroundTransparency = 0.35
		end
	end
end

local function poll(id: number)
	while visible and loopId == id do
		if owned() then
			local st = ctx.Net.request("marketState")
			if not visible or loopId ~= id then
				return
			end
			if st.ok then
				setStatus(st.open == true, tostring(st.text or ""))
			end
		end
		task.wait(2)
	end
end

function MarketTab.build(c: any, container: Frame)
	ctx = c
	P, K, Lines, Hub = c.P, c.K, c.P.Lines, c.Hub
	scroll = Hub.scroll(container)
	render()
end

function MarketTab.show(_state: any)
	render()
	visible = true
	loopId += 1
	task.spawn(poll, loopId)
end

function MarketTab.hide()
	visible = false
	loopId += 1
end

return MarketTab
