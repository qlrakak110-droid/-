--!nocheck
-- GwangalliJobs/Bar: the slim job STATUS BAR at the top-right edge (Layout slot "topRight", 44 px
-- high instead of the old 104 px shift card). Two lines: "🏪 편의점 알바 · 카운터 손님 계산하기 3/6" and
-- "오늘 +12,300원 · 이번 근무 4,600원 · 🔥x3 · 😮‍💨 -30%"; a 퇴근 button at the right end (confirm first).
-- While the bar is up the phone's own ShiftCard (GwangalliPhone/Overlay, same slot) is hidden locally
-- and the Player attribute GwangalliJobBar = true tells the phone owner (integration hook).
-- Event driven (WorkState + round results); no loops.

local Bar = {}

local J: any
local K: any
local gui: ScreenGui

local root: Frame? = nil
local icon: TextLabel
local line1: TextLabel
local line2: TextLabel
local endBtn: TextButton
local scale: UIScale
local shown = false
local last: any = nil
local shiftCard: GuiObject? = nil
local shiftConn: RBXScriptConnection? = nil
local suppressed = false

local function phoneShiftCard(): GuiObject?
	if shiftCard and shiftCard.Parent then
		return shiftCard
	end
	local pg = J.player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	for _, sg in pg:GetChildren() do
		if sg:IsA("ScreenGui") and sg ~= gui then
			local c = sg:FindFirstChild("ShiftCard", true)
			if c and c:IsA("GuiObject") then
				shiftCard = c
				return c
			end
		end
	end
	return nil
end

-- the phone's ShiftCard and this bar share the slot: hide the card while the bar is shown
local function suppressCard(on: boolean)
	suppressed = on
	J.player:SetAttribute("GwangalliJobBar", on)
	local c = phoneShiftCard()
	if not c then
		return
	end
	if on then
		c.Visible = false
		if not shiftConn then
			shiftConn = c:GetPropertyChangedSignal("Visible"):Connect(function()
				if suppressed and c.Visible then
					c.Visible = false
				end
			end)
		end
	elseif shiftConn then
		shiftConn:Disconnect()
		shiftConn = nil
	end
end

local function layout()
	if not root then
		return
	end
	local s = 1
	local r = nil
	pcall(function()
		s = J.Layout.metrics().s
		r = J.Layout.rect("topRight")
	end)
	scale.Scale = s
	local m = J.metrics()
	local w = if r then r.w else math.min(300, m.W - 16)
	w = math.clamp(w, 240, 340 * s)
	root.AnchorPoint = Vector2.new(1, 0)
	if r then
		root.Position = UDim2.fromOffset(r.x + r.w, r.y)
	else
		root.Position = UDim2.new(1, -8, 0, 64)
	end
	root.Size = UDim2.fromOffset(math.floor(w / s), 44)
end

local function askQuit()
	K.confirm(gui, {
		title = "퇴근할까요?",
		body = "지금까지 번 돈은 바로 통장으로 들어가요.",
		icon = "🏁",
		iconColor = K.Color.orange,
		confirmText = "퇴근하기",
		destructive = true,
		zIndex = 80,
		onConfirm = function()
			J.send({ op = "quit" })
		end,
	})
end

local function build()
	if root then
		return
	end
	root = K.frame(gui, { Name = "JobBar", Size = UDim2.fromOffset(280, 44), BackgroundTransparency = 0.1, BackgroundColor3 = K.Color.glass2, Visible = false, Active = false, ZIndex = 20 })
	scale = K.make("UIScale", { Scale = 1 }, root)
	K.corner(root, K.Radius.md)
	K.stroke(root, K.Color.gold, 1, 0.65)
	icon = K.text(root, { Name = "Icon", Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(32, 32), Text = "💼", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.8, BackgroundColor3 = K.Color.gold, ZIndex = 21 })
	K.corner(icon, K.Radius.sm)
	line1 = K.text(root, { Name = "Task", Position = UDim2.fromOffset(44, 5), Size = UDim2.new(1, -112, 0, 17), Text = "", Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	line2 = K.text(root, { Name = "Money", Position = UDim2.fromOffset(44, 23), Size = UDim2.new(1, -112, 0, 15), Text = "", TextColor3 = K.Color.green, Font = K.Font.bold, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	endBtn = K.Button(root, { name = "EndShift", text = "퇴근", style = "danger", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -4, 0.5, 0), size = UDim2.fromOffset(60, 36), textSize = K.Type.caption + 1, zIndex = 22, onClick = askQuit })
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	if J.Layout and J.Layout.changed then
		pcall(function()
			J.Layout.changed:Connect(layout)
		end)
	end
	layout()
end

local function render(w: any)
	if not root then
		return
	end
	icon.Text = tostring(w.icon or "💼")
	local t = w.task
	local prog = w.progress
	local step = ""
	if prog and (prog.total or 0) > 0 then
		step = string.format(" %d/%d", math.min(prog.total, (prog.done or 0) + 1), prog.total)
	end
	local taskText = if t and t.prompt then tostring(t.prompt) else "출근하는 중…"
	K.setText(line1, string.format("%s · %s%s", tostring(w.jobTitle or "알바"), taskText, step))
	local parts = { "오늘 +" .. K.won(tonumber(w.earnedToday) or 0) }
	if (tonumber(w.earnedShift) or 0) > 0 then
		table.insert(parts, "근무 " .. K.won(w.earnedShift))
	end
	if (tonumber(w.combo) or 0) > 1 then
		table.insert(parts, string.format("🔥x%d", w.combo))
	end
	local mult = tonumber(w.payMult) or 1
	if mult < 0.999 then
		table.insert(parts, string.format("😮‍💨 -%d%%", math.floor((1 - mult) * 100 + 0.5)))
	end
	if (tonumber(w.redLights) or 0) > 0 then
		table.insert(parts, string.format("🚦x%d", w.redLights))
	end
	K.setText(line2, table.concat(parts, " · "))
	line2.TextColor3 = if mult < 0.999 then K.Color.orange else K.Color.green
end

function Bar.update(w: any)
	last = w
	if type(w) ~= "table" or w.onShift ~= true then
		if shown and root then
			shown = false
			K.tween(root, 0.18, { BackgroundTransparency = 1 })
			root.Visible = false
			root.BackgroundTransparency = 0.1
		end
		suppressCard(false)
		return
	end
	build()
	render(w)
	if not shown then
		shown = true
		root.Visible = true
		layout()
		K.springIn(root, 0.92, { amount = 0.15, duration = 0.3 })
	end
	suppressCard(true)
end

-- a round result: bump the money line
function Bar.result(p: any)
	if not shown or not root or type(last) ~= "table" then
		return
	end
	if tonumber(p.earned) then
		last.earnedShift = p.earned
	end
	if tonumber(p.combo) then
		last.combo = p.combo
	end
	render(last)
	if (tonumber(p.pay) or 0) > 0 then
		K.pop(line2, 1.12)
	end
end

function Bar.isShown(): boolean
	return shown
end

function Bar.init(ctx: any)
	J = ctx
	K = ctx.K
	gui = ctx.gui
end

return Bar
