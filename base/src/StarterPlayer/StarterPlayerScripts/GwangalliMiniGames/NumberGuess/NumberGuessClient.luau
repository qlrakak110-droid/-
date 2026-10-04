--!strict
-- NumberGuess/NumberGuessClient: 숫자 맞히기 (업다운) screen (client only). The open range is shown big
-- ("23 ~ 61"), every guess so far as chips (48 ▲UP / 70 ▼DOWN), and on your turn a thumb keypad
-- builds the number (확인 sends it; numbers outside the open range are refused here and on the server).

local NumberGuessClient = {}

function NumberGuessClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local you = ctx.you
	local view = ctx.view
	local g: any = nil
	local typed = ""

	local card = K.Panel(ctx.gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(320, 120), Radius = K.Radius.xl, ZIndex = 5 })
	K.text(card, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Text = "비밀 숫자는 이 사이에 있어요", ZIndex = 6 })
	local range = K.text(card, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 36, ZIndex = 6 })
	local chips = K.frame(card, { Position = UDim2.fromOffset(10, 78), Size = UDim2.new(1, -20, 0, 30), ZIndex = 6 })
	K.list(chips, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local pad = K.Panel(ctx.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(300, 262), Visible = false, Radius = K.Radius.xl })
	local entry = K.text(pad, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 30, Text = "_" })
	local keys = K.frame(pad, { Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 1, -60) })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -6, 0, 44)
	grid.CellPadding = UDim2.fromOffset(8, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = keys

	local function show()
		entry.Text = if typed == "" then "_" else typed
	end
	local labels = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "확인" }
	for i, kname in labels do
		K.Button(keys, { text = kname, style = if kname == "확인" then "primary" elseif kname == "⌫" then "secondary" else "glass", order = i, textSize = 22, onClick = function()
			if not g or g.turn ~= you then
				return
			end
			if kname == "⌫" then
				typed = string.sub(typed, 1, math.max(0, #typed - 1))
			elseif kname == "확인" then
				local n = tonumber(typed)
				if n and n >= g.lo and n <= g.hi then
					Net.send("move", { n = n })
					typed = ""
				else
					Fx.sound("buzz")
					K.toast({ kind = "info", title = "범위 밖이에요", body = g.lo .. " ~ " .. g.hi .. " 사이로 골라 주세요" })
				end
			elseif #typed < 3 then
				typed ..= kname
				if tonumber(typed) and (tonumber(typed) :: number) > 100 then
					typed = string.sub(typed, 1, #typed - 1)
				end
			end
			show()
		end })
	end

	local api = {}
	function api.game(v: any)
		g = v
		range.Text = if g.secret then ("정답: " .. g.secret) else (g.lo .. " ~ " .. g.hi)
		for _, c in chips:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		for i, h in g.history do
			local up = h.r == "UP"
			local chip = K.text(chips, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 26),
				BackgroundTransparency = 0,
				BackgroundColor3 = if h.r == "정답" then Color3.fromRGB(70, 56, 10) elseif up then Color3.fromRGB(20, 60, 40) else Color3.fromRGB(70, 24, 30),
				TextColor3 = if h.r == "정답" then K.Color.gold elseif up then K.Color.green else K.Color.red,
				Font = K.Font.bold,
				TextSize = K.Type.caption,
				Text = h.n .. (if h.r == "정답" then " ✔" elseif up then " ▲" else " ▼"),
				LayoutOrder = i,
				ZIndex = 7,
			})
			K.corner(chip, UDim.new(0.5, 0))
			K.pad(chip, 8, 8, 0, 0)
		end
		local mine = you > 0 and g.turn == you
		pad.Visible = mine
		Stage.turn(g.turn)
		Stage.setDeadline(g.deadline, g.turnTime)
		Stage.updateScore(g.lo .. "~" .. g.hi)
		Stage.setStatus(if mine then "내 차례! 숫자를 골라요" else (view.sides[g.turn].name .. " 차례"))
	end
	function api.event(e: any)
		if e.e == "guess" then
			if e.r == "정답" then
				Stage.flash(e.n .. " 정답!", K.Color.gold, 1.6)
			else
				Stage.flash(e.n .. (if e.r == "UP" then "  UP ▲" else "  DOWN ▼"), if e.r == "UP" then K.Color.green else K.Color.red, 1.1)
			end
			Fx.sound("pop")
		end
	end
	function api.update(_v: any) end
	function api.destroy()
		card:Destroy()
		pad:Destroy()
		Stage.setStatus(nil)
		Stage.setDeadline(nil)
	end
	return api
end

return NumberGuessClient
