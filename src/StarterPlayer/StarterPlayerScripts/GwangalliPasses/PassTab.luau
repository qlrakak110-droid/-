-- GwangalliPasses/PassTab (client): the "패스" tab, the 패스 상점: one premium card per available pass
-- (gradient band, glyph, title, perks, price / 보유 중) with a shortcut into the pass's own tab.

local Players = game:GetService("Players")

local PassTab = {}

local ctx: any
local P: any, K: any, Lines: any, Hub: any
local scroll: ScrollingFrame? = nil

local TAB_OF = { PremiumGarage = "garage", Convenience = "market", Flex = "flex" }

local function card(parent: Instance, key: string, order: number)
	local d = P.Config.PASSES[key]
	local owned = P.has(Players.LocalPlayer, key)
	local c = K.Card(parent, { Name = "Pass_" .. key, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ClipsDescendants = true })
	K.list(c, false, 0)
	-- hero band: gradient + glyph + title
	local hero = K.frame(c, { Name = "Hero", Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 0 })
	K.gradient(hero, { d.C1, d.C2 }, 0)
	K.corner(hero, 16)
	-- square bottom edge under the rounded top (ClipsDescendants does not follow UICorner)
	local fill = K.frame(hero, { Name = "Fill", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 0 })
	K.gradient(fill, { d.C1, d.C2 }, 0)
	K.frame(hero, { Name = "Shine", Size = UDim2.new(1, 0, 0.5, 0), BackgroundTransparency = 0.85, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.text(hero, { Text = d.Glyph, TextSize = 34, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(48, 74), TextXAlignment = Enum.TextXAlignment.Center })
	K.text(hero, { Text = d.Title, Font = K.Font.heavy, TextSize = K.Type.title2, TextColor3 = Color3.fromRGB(20, 12, 4), Position = UDim2.fromOffset(66, 12), Size = UDim2.new(1, -150, 0, 24) })
	K.text(hero, { Text = d.Desc, TextSize = K.Type.micro, Font = K.Font.bold, TextColor3 = Color3.fromRGB(40, 24, 10), TextWrapped = true, Position = UDim2.fromOffset(66, 38), Size = UDim2.new(1, -76, 0, 32), TextYAlignment = Enum.TextYAlignment.Top })
	local content = K.frame(c, { Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	K.list(content, false, 6)
	K.pad(content, 12, 12, 10, 12)
	if owned then
		local pill = Hub.chip(hero, "✓ " .. Lines.t("owned"), Color3.fromRGB(20, 12, 4), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12), BackgroundTransparency = 0.6, BackgroundColor3 = Color3.new(1, 1, 1) })
		local _p = pill
	end
	for i, perk in d.Perks do
		K.text(content, { Text = perk, TextSize = K.Type.caption, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i })
	end
	local row = K.frame(content, { Name = "Actions", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 20 })
	Hub.buyButton(row, key, { size = UDim2.new(0.6, -4, 1, 0) })
	K.Button(row, { name = "Go", text = if owned then "열기 ›" else "둘러보기 ›", style = "secondary", size = UDim2.new(0.4, -4, 1, 0), position = UDim2.new(0.6, 4, 0, 0), onClick = function()
		ctx.Hub.open(ctx.Hub.mode(), TAB_OF[key])
	end })
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
	local any = false
	for i, key in P.ORDER do
		if P.available(key) then
			any = true
			card(s, key, i)
		end
	end
	if not any then
		K.text(s, { Text = Lines.t("not_ready"), TextColor3 = K.Color.sub, Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	end
	K.text(s, { Text = "한 번 사면 영구 적용 · 로벅스(R$)로 결제", TextSize = K.Type.micro, TextColor3 = K.Color.faint, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 99 })
end

function PassTab.build(c: any, container: Frame)
	ctx = c
	P, K, Lines, Hub = c.P, c.K, c.P.Lines, c.Hub
	scroll = Hub.scroll(container)
	render()
end

function PassTab.show(_state: any)
	render()
end

return PassTab
