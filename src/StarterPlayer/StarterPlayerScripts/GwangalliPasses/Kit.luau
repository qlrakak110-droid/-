-- GwangalliPasses/Kit (client): the place's shared UI kit ReplicatedStorage.GwangalliUI (K), so the pass screens
-- look like every other phone app. If the kit is missing, a small fallback with the same calls keeps the
-- screens working (plain frames, the same colour tokens).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function loadKit(): any
	local m = ReplicatedStorage:WaitForChild("GwangalliUI", 15)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and type(res.Button) == "function" then
			return res
		end
	end
	return nil
end

local K = loadKit()
if K then
	return K
end

---------------------------------------------------------------------------------------------------
-- fallback
---------------------------------------------------------------------------------------------------
local F: any = {}
F.Color = {
	bg = Color3.fromRGB(10, 12, 20), card = Color3.fromRGB(25, 29, 45), card2 = Color3.fromRGB(37, 42, 61), card3 = Color3.fromRGB(54, 60, 84),
	text = Color3.fromRGB(245, 247, 251), sub = Color3.fromRGB(170, 177, 196), faint = Color3.fromRGB(116, 124, 146),
	cyan = Color3.fromRGB(61, 214, 245), magenta = Color3.fromRGB(255, 79, 163), gold = Color3.fromRGB(255, 194, 71),
	violet = Color3.fromRGB(150, 110, 255), green = Color3.fromRGB(70, 220, 140), orange = Color3.fromRGB(255, 150, 60),
	red = Color3.fromRGB(240, 80, 90), onAccent = Color3.fromRGB(4, 22, 32), onGold = Color3.fromRGB(44, 28, 0), glass = Color3.fromRGB(15, 18, 31),
}
F.Grad = { gold = { Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 166, 50) }, primary = { Color3.fromRGB(88, 226, 250), Color3.fromRGB(56, 170, 255) }, bridge = { F.Color.cyan, F.Color.violet, F.Color.magenta } }
F.Font = { regular = Enum.Font.Gotham, medium = Enum.Font.GothamMedium, bold = Enum.Font.GothamBold, heavy = Enum.Font.GothamBlack, mono = Enum.Font.RobotoMono }
F.Type = { display = 28, title = 22, title2 = 18, body = 15, bodySm = 14, caption = 12, micro = 11 }
F.Radius = { sm = 12, md = 16, lg = 20, xl = 24, pill = 999 }
F.GLASS_T = 0.14

function F.reduced(): boolean
	return false
end
function F.tier(): string
	return "mid"
end
function F.sound() end
function F.feedback() end
function F.pressable() end
function F.won(n: any): string
	return tostring(math.floor(tonumber(n) or 0)) .. "원"
end

function F.frame(parent: Instance?, props: any): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in props or {} do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end
function F.text(parent: Instance?, props: any): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.TextColor3 = F.Color.text
	l.Font = F.Font.medium
	l.TextSize = F.Type.bodySm
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end
function F.corner(inst: Instance, r: any): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, tonumber(r) or 12)
	c.Parent = inst
	return c
end
function F.stroke(inst: Instance, color: Color3?, th: number?, tr: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Thickness = th or 1
	s.Transparency = tr or 0.85
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
function F.pad(inst: Instance, l: number, r: number?, t: number?, b: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingRight = UDim.new(0, r or l)
	p.PaddingTop = UDim.new(0, t or l)
	p.PaddingBottom = UDim.new(0, b or t or l)
	p.Parent = inst
	return p
end
function F.list(inst: Instance, horizontal: boolean?, padding: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding or 0)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = inst
	return l
end
function F.gradient(inst: Instance, colors: any, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	local kps = {}
	for i, c in colors do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
	end
	if #kps == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
	end
	g.Color = ColorSequence.new(kps)
	g.Rotation = rotation or 0
	g.Parent = inst
	return g
end
function F.Card(parent: Instance?, props: any): Frame
	local c = F.frame(nil, { BackgroundTransparency = 0, BackgroundColor3 = F.Color.card, Size = UDim2.new(1, 0, 0, 64) })
	for k, v in props or {} do
		if k ~= "Radius" then
			(c :: any)[k] = v
		end
	end
	F.corner(c, 16)
	c.Parent = parent
	return c
end
function F.Button(parent: Instance?, opts: any): TextButton
	local b = Instance.new("TextButton")
	b.Name = opts.name or "Button"
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = if opts.style == "gold" then F.Color.gold elseif opts.style == "secondary" or opts.style == "tonal" then F.Color.card2 elseif opts.style == "danger" then Color3.fromRGB(64, 24, 30) else F.Color.cyan
	b.TextColor3 = if opts.style == "secondary" or opts.style == "tonal" or opts.style == "danger" then F.Color.text else F.Color.onAccent
	b.Font = F.Font.bold
	b.TextSize = opts.textSize or F.Type.bodySm
	b.Text = if opts.icon and opts.text then opts.icon .. "  " .. opts.text else (opts.text or opts.icon or "")
	b.Size = opts.size or UDim2.new(1, 0, 0, 44)
	b.Position = opts.position or UDim2.new()
	b.AnchorPoint = opts.anchor or Vector2.zero
	b.LayoutOrder = opts.order or 0
	b.ZIndex = opts.zIndex or 1
	F.corner(b, 12)
	if opts.onClick then
		b.Activated:Connect(function()
			if not b:GetAttribute("Disabled") then
				pcall(opts.onClick)
			end
		end)
	end
	b.Parent = parent
	return b
end
function F.setButtonEnabled(b: TextButton, enabled: boolean)
	b:SetAttribute("Disabled", if enabled then nil else true)
	b.TextTransparency = if enabled then 0 else 0.5
end
function F.setButtonLoading(b: TextButton, loading: boolean, text: string?)
	if loading then
		b:SetAttribute("IdleText", b.Text)
		b.Text = text or "처리 중…"
		b:SetAttribute("Disabled", true)
	else
		b.Text = b:GetAttribute("IdleText") or b.Text
		b:SetAttribute("Disabled", nil)
	end
end
function F.Segmented(parent: Instance?, opts: any): any
	local holder = F.frame(nil, { Name = "Segmented", Size = UDim2.new(1, 0, 0, (opts.height or 40) + 6), BackgroundTransparency = 0, BackgroundColor3 = F.Color.card, LayoutOrder = opts.order or 0 })
	F.corner(holder, 12)
	local api = { frame = holder, value = opts.value or opts.items[1].id }
	local buttons = {}
	function api.set(id: string, silent: boolean?)
		for _, t in opts.items do
			buttons[t.id].BackgroundTransparency = if t.id == id then 0 else 1
		end
		local changed = api.value ~= id
		api.value = id
		if not silent and changed and opts.onChange then
			task.spawn(opts.onChange, id)
		end
	end
	local n = #opts.items
	for i, t in opts.items do
		local b = Instance.new("TextButton")
		b.Name = "Seg_" .. t.id
		b.Size = UDim2.new(1 / n, 0, 1, 0)
		b.Position = UDim2.new((i - 1) / n, 0, 0, 0)
		b.BackgroundColor3 = F.Color.cyan
		b.BackgroundTransparency = 1
		b.Text = t.label
		b.Font = F.Font.bold
		b.TextSize = 13
		b.TextColor3 = F.Color.text
		F.corner(b, 10)
		b.Parent = holder
		buttons[t.id] = b
		b.Activated:Connect(function()
			api.set(t.id)
		end)
	end
	holder.Parent = parent
	api.set(api.value, true)
	return api
end

local toastGui: ScreenGui? = nil
function F.toast(data: any)
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	if not toastGui or not toastGui.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "GwangalliPassesToast"
		g.ResetOnSpawn = false
		g.DisplayOrder = 80
		g.Parent = pg
		toastGui = g
	end
	local f = F.frame(toastGui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(360, 58), BackgroundTransparency = 0.1, BackgroundColor3 = F.Color.card })
	F.corner(f, 14)
	F.text(f, { Text = tostring(data.icon or "") .. "  " .. tostring(data.title or ""), Font = F.Font.bold, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 22) })
	F.text(f, { Text = tostring(data.body or ""), TextColor3 = F.Color.sub, TextSize = 12, Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	task.delay(3.2, function()
		f:Destroy()
	end)
end

function F.confirm(host: Instance, opts: any): any
	local shade = F.frame(host, { Name = "Confirm", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.4, BackgroundColor3 = Color3.new(0, 0, 0), Active = true, ZIndex = 50 })
	local box = F.Card(shade, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.86, 0, 0, 170), ZIndex = 51 })
	F.text(box, { Text = tostring(opts.title or ""), Font = F.Font.bold, TextSize = 16, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 22), ZIndex = 52 })
	F.text(box, { Text = tostring(opts.body or ""), TextWrapped = true, TextColor3 = F.Color.sub, TextSize = 13, Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 0, 60), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 52 })
	local function close()
		shade:Destroy()
	end
	F.Button(box, { text = opts.cancelText or "취소", style = "secondary", position = UDim2.new(0, 12, 1, -54), size = UDim2.new(0.5, -18, 0, 42), zIndex = 52, onClick = function()
		close()
		if opts.onCancel then
			opts.onCancel()
		end
	end })
	F.Button(box, { text = opts.confirmText or "확인", style = opts.style or "primary", position = UDim2.new(0.5, 6, 1, -54), size = UDim2.new(0.5, -18, 0, 42), zIndex = 52, onClick = function()
		close()
		if opts.onConfirm then
			opts.onConfirm()
		end
	end })
	return { close = close }
end

return F
