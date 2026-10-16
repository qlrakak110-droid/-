-- GwangalliPasses/FlexTab (client): the "꾸미기" tab (pass #4 과시 패스).
--   나만의 번호판   live plate preview in the chosen style, text box (client pre-check with the shared rules;
--                   the server filters + claims), 🇰🇷 형식 helper, 🎲, 6 styles, 저장 / 기본으로
--   네온 닉네임     6 animated palettes (live preview with your own name) + 끄기
--   KO 피니시       6 effects: tap to use, ▶ 미리보기 (plays in front of you, only you see it) + 끄기
-- Locked: everything visible; every action opens the purchase prompt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FlexTab = {}

local ctx: any
local P: any, K: any, Lines: any, Hub: any, Plates: any, Neon: any, KoFx: any
local scroll: ScrollingFrame? = nil
local settings: { [string]: any } = {}
local grads: { { g: UIGradient, p: any } } = {}
local animConn: RBXScriptConnection? = nil
local GOLD = Color3.fromRGB(255, 194, 71)

local function owned(): boolean
	return P.has(Players.LocalPlayer, "Flex")
end

local function guard(fn: () -> ()): () -> ()
	return function()
		if not owned() then
			ctx.Store.buy("Flex")
			return
		end
		task.spawn(fn)
	end
end

local function toast(res: any, icon: string)
	K.toast({ kind = if res.ok then "success" else "warn", icon = icon, title = tostring(res.message or (if res.ok then "OK" else Lines.t("busy"))) })
end

local function animate()
	if animConn then
		return
	end
	animConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local alive = 0
		for i = #grads, 1, -1 do
			local e = grads[i]
			if not e.g:IsDescendantOf(game) then
				table.remove(grads, i)
				continue
			end
			alive += 1
			if not K.reduced() then
				e.g.Offset = Vector2.new(((t * e.p.speed) % 2) - 1, 0)
			end
		end
		if alive == 0 and animConn then
			animConn:Disconnect()
			animConn = nil
		end
	end)
end

local function neonLabel(parent: Instance, text: string, pal: any, props: any): TextLabel
	local l = K.text(parent, props)
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Color = Neon.sequence(pal)
	g.Parent = l
	local s = Instance.new("UIStroke")
	s.Color = pal.stroke
	s.Thickness = 1.5
	s.Transparency = 0.2
	s.Parent = l
	table.insert(grads, { g = g, p = pal })
	animate()
	return l
end

---------------------------------------------------------------------------------------------------
-- plate
---------------------------------------------------------------------------------------------------
local function platePreview(parent: Instance, order: number): any
	local holder = K.frame(parent, { Name = "PlateStage", Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(16, 18, 28), LayoutOrder = order })
	K.corner(holder, 12)
	local plate = K.frame(holder, { Name = "Plate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(240, 51), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
	K.corner(plate, 6)
	local stroke = K.stroke(plate, Color3.fromRGB(30, 30, 30), 2, 0)
	local band = K.frame(plate, { Name = "Band", Size = UDim2.new(0.16, 0, 1, 0), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Visible = false })
	K.corner(band, 6)
	local label = K.text(plate, { Name = "Text", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextScaled = true, Font = K.Font.bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	local api = {}
	function api.set(text: string, styleId: string)
		local st = Plates.style(styleId)
		plate.BackgroundColor3 = Plates.rgb(st.bg2 or st.bg)
		band.Visible = st.bg2 ~= nil
		band.BackgroundColor3 = Plates.rgb(st.bg)
		label.TextColor3 = Plates.rgb(st.fg)
		label.Font = Plates.font(st.font)
		label.Text = if text ~= "" then text else "12가 3456"
		label.TextTransparency = if text ~= "" then 0 else 0.55
		stroke.Color = if st.frame then Plates.rgb(st.frame) else Color3.fromRGB(30, 30, 30)
		stroke.Thickness = if st.frame then 3 else 2
	end
	return api
end

local function plateSection(s: Instance, order: number): number
	Hub.section(s, "🔢 " .. Lines.t("plate_title"), order)
	local card = K.Card(s, { Name = "PlateCard", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order + 1 })
	K.list(card, false, 8)
	K.pad(card, 12, 12, 12, 12)
	local style = settings.plateStyle or P.Config.PLATE.DEFAULT_STYLE
	local text = settings.plate or ""
	local pv = platePreview(card, 1)
	local box = Instance.new("TextBox")
	box.Name = "PlateInput"
	box.Size = UDim2.new(1, 0, 0, 44)
	box.BackgroundColor3 = K.Color.card2
	box.TextColor3 = K.Color.text
	box.PlaceholderText = Lines.t("plate_hint")
	box.PlaceholderColor3 = K.Color.faint
	box.Font = K.Font.bold
	box.TextSize = 16
	box.ClearTextOnFocus = false
	box.Text = text
	box.LayoutOrder = 2
	box.Parent = card
	K.corner(box, 10)
	K.pad(box, 12, 12, 0, 0)
	local hint = K.text(card, { Text = Lines.t("plate_rule", P.Config.PLATE.MIN, P.Config.PLATE.MAX), TextSize = K.Type.micro, TextColor3 = K.Color.sub, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3 })
	local function refresh()
		local clean = Plates.normalize(box.Text)
		pv.set(clean, style)
		if clean == "" then
			hint.Text = Lines.t("plate_rule", P.Config.PLATE.MIN, P.Config.PLATE.MAX)
			hint.TextColor3 = K.Color.sub
			return
		end
		local ok = Plates.validate(box.Text)
		hint.Text = if ok then "✓ 사용할 수 있는 형식이에요 (저장할 때 한 번 더 확인해요)" else Lines.t("plate_rule", P.Config.PLATE.MIN, P.Config.PLATE.MAX)
		hint.TextColor3 = if ok then Color3.fromRGB(90, 220, 140) else Color3.fromRGB(255, 120, 120)
	end
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if utf8.len(box.Text) and (utf8.len(box.Text) :: number) > P.Config.PLATE.MAX_TOTAL + 2 then
			box.Text = string.sub(box.Text, 1, utf8.offset(box.Text, P.Config.PLATE.MAX_TOTAL + 3) - 1)
		end
		refresh()
	end)
	-- helpers row
	local helpers = K.frame(card, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 4 })
	K.Button(helpers, { name = "Korean", text = "🇰🇷 번호판 형식", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), onClick = function()
		box.Text = Plates.korean(box.Text)
	end })
	K.Button(helpers, { name = "Dice", text = "🎲 랜덤", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.new(0.5, 4, 0, 0), onClick = function()
		box.Text = Plates.random()
	end })
	-- styles
	local styles = K.frame(card, { Name = "Styles", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -6, 0, 38)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = styles
	local rings = {}
	for i, st in Plates.STYLES do
		local b = Instance.new("TextButton")
		b.Name = "Style_" .. st.id
		b.Text = st.name
		b.Font = K.Font.bold
		b.TextSize = K.Type.micro
		b.TextColor3 = Plates.rgb(st.fg)
		b.BackgroundColor3 = Plates.rgb(st.bg2 or st.bg)
		b.AutoButtonColor = false
		b.LayoutOrder = i
		b.Parent = styles
		K.corner(b, 8)
		rings[st.id] = K.stroke(b, if st.id == style then GOLD else Color3.fromRGB(40, 40, 40), if st.id == style then 2.5 else 1, 0)
		b.Activated:Connect(function()
			style = st.id
			for id, r in rings do
				r.Color = if id == style then GOLD else Color3.fromRGB(40, 40, 40)
				r.Thickness = if id == style then 2.5 else 1
			end
			refresh()
		end)
	end
	local actions = K.frame(card, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 6 })
	local save = K.Button(actions, { name = "Save", text = if owned() then "저장" else "🔒 과시 패스로 열기", style = if owned() then "primary" else "gold", size = UDim2.new(0.62, -4, 1, 0) })
	save.Activated:Connect(guard(function()
		K.setButtonLoading(save, true)
		local res = ctx.Net.request("setPlate", { text = box.Text, style = style })
		K.setButtonLoading(save, false)
		toast(res, "🔢")
		if res.ok then
			settings.plate = res.plate
			settings.plateStyle = res.style or style
			if res.plate then
				box.Text = res.plate
			end
		end
	end))
	K.Button(actions, { name = "Reset", text = "기본으로", style = "secondary", size = UDim2.new(0.38, -4, 1, 0), position = UDim2.new(0.62, 4, 0, 0), onClick = guard(function()
		local res = ctx.Net.request("clearPlate")
		toast(res, "🔢")
		if res.ok then
			settings.plate = nil
			settings.plateStyle = P.Config.PLATE.DEFAULT_STYLE
			style = settings.plateStyle
			box.Text = ""
		end
	end) })
	refresh()
	return order + 2
end

---------------------------------------------------------------------------------------------------
-- neon nickname
---------------------------------------------------------------------------------------------------
local function neonSection(s: Instance, order: number): number
	Hub.section(s, "🌈 " .. Lines.t("neon_title"), order)
	local card = K.Card(s, { Name = "NeonCard", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order + 1 })
	K.pad(card, 10, 10, 10, 10)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -5, 0, 52)
	grid.CellPadding = UDim2.fromOffset(10, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = card
	local name = Players.LocalPlayer.DisplayName
	local rings = {}
	local function mark(id: string?)
		for pid, r in rings do
			r.Color = if pid == id then GOLD else Color3.new(1, 1, 1)
			r.Transparency = if pid == id then 0 else 0.85
			r.Thickness = if pid == id then 2 else 1
		end
	end
	local function pick(id: string)
		return guard(function()
			local res = ctx.Net.request("setNeon", { palette = id })
			toast(res, "🌈")
			if res.ok then
				settings.neon = res.neon
				mark(res.neon or "off")
			end
		end)
	end
	for i, pal in Neon.LIST do
		local b = Instance.new("TextButton")
		b.Name = "Neon_" .. pal.id
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
		b.LayoutOrder = i
		b.Parent = card
		K.corner(b, 10)
		rings[pal.id] = K.stroke(b, Color3.new(1, 1, 1), 1, 0.85)
		neonLabel(b, "✦ " .. name, pal, { Font = K.Font.heavy, TextSize = 16, Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(b, { Text = pal.name, TextSize = K.Type.micro, TextColor3 = K.Color.sub, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 32), TextXAlignment = Enum.TextXAlignment.Center })
		b.Activated:Connect(pick(pal.id))
	end
	local off = Instance.new("TextButton")
	off.Name = "Neon_off"
	off.Text = "🚫 " .. Lines.t("neon_off")
	off.Font = K.Font.bold
	off.TextSize = K.Type.caption
	off.TextColor3 = K.Color.sub
	off.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	off.LayoutOrder = 99
	off.Parent = card
	K.corner(off, 10)
	rings.off = K.stroke(off, Color3.new(1, 1, 1), 1, 0.85)
	off.Activated:Connect(pick(""))
	mark(if settings.neon then settings.neon else (if owned() then "off" else nil))
	return order + 2
end

---------------------------------------------------------------------------------------------------
-- KO finish effects
---------------------------------------------------------------------------------------------------
local function koSection(s: Instance, order: number): number
	Hub.section(s, "💥 " .. Lines.t("kofx_title"), order)
	local marks = {}
	local function mark(id: string?)
		for fid, m in marks do
			m.Text = if fid == id then "✓ 사용 중" else ""
		end
	end
	for i, fx in KoFx.LIST do
		local row = K.Card(s, { Name = "Fx_" .. fx.id, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = order + i })
		local hit = Instance.new("TextButton")
		hit.Name = "Pick"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.new(1, -96, 1, 0)
		hit.Parent = row
		K.text(row, { Text = fx.glyph, TextSize = 26, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 62), TextXAlignment = Enum.TextXAlignment.Center })
		K.text(row, { Text = fx.name, Font = K.Font.bold, TextSize = K.Type.bodySm, Position = UDim2.fromOffset(54, 10), Size = UDim2.new(1, -160, 0, 18) })
		K.text(row, { Text = fx.desc, TextSize = K.Type.micro, TextColor3 = K.Color.sub, TextWrapped = true, Position = UDim2.fromOffset(54, 28), Size = UDim2.new(1, -160, 0, 28), TextYAlignment = Enum.TextYAlignment.Top })
		marks[fx.id] = K.text(row, { Text = "", TextSize = K.Type.micro, Font = K.Font.bold, TextColor3 = GOLD, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -100, 0, 10), Size = UDim2.fromOffset(60, 14), TextXAlignment = Enum.TextXAlignment.Right })
		hit.Activated:Connect(guard(function()
			local res = ctx.Net.request("setKoFx", { fx = fx.id })
			toast(res, fx.glyph)
			if res.ok then
				settings.koFx = res.fx
				mark(res.fx)
			end
		end))
		K.Button(row, { name = "Preview", text = if owned() then Lines.t("kofx_preview") else "🔒", style = "secondary", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), size = UDim2.fromOffset(88, 40), onClick = guard(function()
			local res = ctx.Net.request("previewKo", { fx = fx.id })
			if res.ok then
				ctx.Hub.close()
				if ctx.PhoneHook then
					ctx.PhoneHook.closePhone()
				end
			elseif res.message then
				toast(res, fx.glyph)
			end
		end) })
	end
	local offRow = K.Button(s, { name = "FxOff", text = "🚫 피니시 이펙트 끄기", style = "secondary", size = UDim2.new(1, 0, 0, 40), order = order + #KoFx.LIST + 1, onClick = guard(function()
		local res = ctx.Net.request("setKoFx", { fx = "" })
		toast(res, "🚫")
		if res.ok then
			settings.koFx = nil
			mark(nil)
		end
	end) })
	local _ = offRow
	mark(settings.koFx)
	return order + #KoFx.LIST + 3
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
	local order = 1
	if not owned() then
		Hub.lockCard(s, "Flex", order)
		order += 1
	end
	order = plateSection(s, order)
	order = neonSection(s, order)
	koSection(s, order)
end

function FlexTab.build(c: any, container: Frame)
	ctx = c
	P, K, Lines, Hub = c.P, c.K, c.P.Lines, c.Hub
	Plates, Neon, KoFx = P.mod("Plates"), P.mod("Neon"), P.mod("KoFx")
	scroll = Hub.scroll(container)
	render()
end

function FlexTab.show(state: any)
	local st = state or ctx.Hub.state()
	if st and st.ok and type(st.settings) == "table" then
		settings = table.clone(st.settings)
	end
	render()
end

function FlexTab.hide() end

return FlexTab
