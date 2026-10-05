--!nocheck
-- GwangalliUnifiedWork/UI: tiny builders for the 알바 HUD (colours from the shared GwangalliUI kit when it
-- loads, plain fallbacks otherwise). Client only; nothing is created at require time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local U = {}

local K: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliUI")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			K = res
		end
	end
end
U.K = K

local KC = K and K.Color or {}
U.C = {
	bg = KC.glass or Color3.fromRGB(15, 18, 31),
	card = KC.card or Color3.fromRGB(25, 29, 45),
	card2 = KC.card2 or Color3.fromRGB(37, 42, 61),
	track = KC.card3 or Color3.fromRGB(54, 60, 84),
	text = KC.text or Color3.fromRGB(245, 247, 251),
	sub = KC.sub or Color3.fromRGB(170, 177, 196),
	faint = KC.faint or Color3.fromRGB(116, 124, 146),
	cyan = KC.cyan or Color3.fromRGB(61, 214, 245),
	gold = KC.gold or Color3.fromRGB(255, 194, 71),
	green = KC.green or Color3.fromRGB(61, 220, 132),
	orange = KC.orange or Color3.fromRGB(255, 176, 32),
	red = KC.red or Color3.fromRGB(255, 90, 95),
	violet = KC.violet or Color3.fromRGB(139, 108, 255),
	magenta = KC.magenta or Color3.fromRGB(255, 79, 163),
	onAccent = KC.onAccent or Color3.fromRGB(4, 22, 32),
}
U.FONT = Enum.Font.GothamMedium
U.BOLD = Enum.Font.GothamBold

-- every GuiObject gets a rising LayoutOrder unless one is given: list layouts keep the build order
local seq = 0
local function order(inst: Instance, props: any?)
	if inst:IsA("GuiObject") and not (props and props.LayoutOrder) then
		seq += 1
		inst.LayoutOrder = seq
	end
end
U.order = order

function U.make(className: string, props: any?, parent: Instance?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			inst[k] = v
		end
	end
	order(inst, props)
	if parent then
		inst.Parent = parent
	end
	return inst
end

function U.corner(inst: Instance, r: number?)
	U.make("UICorner", { CornerRadius = UDim.new(0, r or 10) }, inst)
end

function U.stroke(inst: Instance, color: Color3?, t: number?)
	U.make("UIStroke", { Color = color or Color3.new(1, 1, 1), Transparency = t or 0.86, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inst)
end

function U.pad(inst: Instance, l: number, r: number?, t: number?, b: number?)
	U.make("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l), PaddingTop = UDim.new(0, t or l), PaddingBottom = UDim.new(0, b or t or l) }, inst)
end

function U.list(inst: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	return U.make("UIListLayout", { Padding = UDim.new(0, padding or 6), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, HorizontalAlignment = align or Enum.HorizontalAlignment.Left }, inst)
end

function U.frame(parent: Instance?, props: any?): Frame
	local f = U.make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0 })
	if props then
		for k, v in props do
			f[k] = v
		end
	end
	order(f, props)
	f.Parent = parent
	return f
end

-- a card: rounded, dark glass
function U.card(parent: Instance?, props: any?): Frame
	local f = U.frame(parent, { BackgroundColor3 = U.C.bg, BackgroundTransparency = 0.12, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	if props then
		for k, v in props do
			f[k] = v
		end
	end
	order(f, props)
	U.corner(f, 12)
	U.stroke(f)
	U.pad(f, 8)
	return f
end

function U.text(parent: Instance?, props: any?): TextLabel
	local l = U.make("TextLabel", { BackgroundTransparency = 1, BorderSizePixel = 0, TextColor3 = U.C.text, Font = U.FONT, TextSize = 14, Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y })
	if props then
		for k, v in props do
			l[k] = v
		end
	end
	order(l, props)
	l.Parent = parent
	return l
end

-- a big touch button; onClick(btn)
function U.button(parent: Instance?, text: string, onClick: (() -> ())?, props: any?): TextButton
	local b = U.make("TextButton", { AutoButtonColor = true, BackgroundColor3 = U.C.card2, BorderSizePixel = 0, TextColor3 = U.C.text, Font = U.BOLD, TextSize = 15, Text = text, TextWrapped = true, Size = UDim2.new(1, 0, 0, 46) })
	if props then
		for k, v in props do
			b[k] = v
		end
	end
	order(b, props)
	U.corner(b, 10)
	b.Parent = parent
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- a progress bar -> api { set(frac, color?), frame }
function U.bar(parent: Instance?, height: number?, props: any?): any
	local track = U.frame(parent, { BackgroundColor3 = U.C.track, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, height or 6) })
	if props then
		for k, v in props do
			track[k] = v
		end
	end
	order(track, props)
	U.corner(track, 4)
	local fill = U.frame(track, { BackgroundColor3 = U.C.cyan, BackgroundTransparency = 0, Size = UDim2.fromScale(0, 1) })
	U.corner(fill, 4)
	return {
		frame = track,
		fill = fill,
		set = function(frac: number, color: Color3?)
			fill.Size = UDim2.fromScale(math.clamp(frac or 0, 0, 1), 1)
			if color then
				fill.BackgroundColor3 = color
			end
		end,
	}
end

function U.clear(inst: Instance, keepClass: { string }?)
	for _, c in inst:GetChildren() do
		local keep = false
		for _, cls in keepClass or { "UIListLayout", "UIPadding", "UICorner", "UIStroke", "UISizeConstraint" } do
			if c:IsA(cls) then
				keep = true
			end
		end
		if not keep then
			c:Destroy()
		end
	end
end

function U.won(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return (if v < 0 then "-" else "") .. s .. out .. "원"
end

function U.clock(sec: number): string
	local s = math.max(0, math.floor(sec))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- a cheap signature of a value (to skip rebuilding a section whose data did not change)
function U.sig(v: any, depth: number?): string
	local d = depth or 0
	local t = type(v)
	if t ~= "table" then
		return tostring(v)
	end
	if d > 5 then
		return "{…}"
	end
	local keys = {}
	for k in v do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		local val = v[k]
		if val == nil then
			val = v[tonumber(k)]
		end
		table.insert(parts, k .. "=" .. U.sig(val, d + 1))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

U.KIND_COLOR = {
	info = Color3.fromRGB(60, 120, 200),
	good = Color3.fromRGB(40, 160, 90),
	reward = Color3.fromRGB(200, 150, 30),
	warn = Color3.fromRGB(210, 120, 30),
	bad = Color3.fromRGB(200, 60, 60),
	order = Color3.fromRGB(120, 80, 200),
	call = Color3.fromRGB(0, 140, 110),
	change = Color3.fromRGB(180, 90, 160),
	job = Color3.fromRGB(40, 110, 160),
}

return U
