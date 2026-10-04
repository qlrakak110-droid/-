--!strict
-- MemoryGame/MemoryClient: 기억력 대결 (client only). The digits appear big in the middle for 2-3 s,
-- vanish, then a thumb keypad (1-9, 0, ⌫) fills the slots "_ _ _ _ _"; the answer is sent when the
-- last slot is filled. Each round shows ✔ / ✖ for both players; rounds get one digit longer.

local Workspace = game:GetService("Workspace")

local MemoryClient = {}

function MemoryClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local you = ctx.you
	local view = ctx.view
	local round = 0
	local len = 0
	local typed = ""
	local sent = false
	local phase = "idle"
	local inputDeadline = 0
	local inputSpan = 10

	local card = K.Panel(ctx.gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(420, 96), Radius = K.Radius.xl, ZIndex = 5 })
	local big = K.text(card, { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 6), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 44, Text = "", ZIndex = 6 })
	local sub = K.text(card, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 70), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Text = "", ZIndex = 6 })

	local pad = K.frame(ctx.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(300, 228), Visible = false })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -6, 0, 50)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = pad

	local function slots(): string
		local parts = {}
		for i = 1, len do
			parts[i] = if i <= #typed then string.sub(typed, i, i) else "_"
		end
		return table.concat(parts, " ")
	end

	local function submit()
		if sent or phase ~= "input" then
			return
		end
		sent = true
		Net.send("move", { round = round, answer = typed })
		sub.Text = "제출했어요 · 상대를 기다려요"
		Fx.sound("pop")
	end

	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✔" }
	for i, kname in keys do
		K.Button(pad, { text = kname, style = if kname == "✔" then "primary" elseif kname == "⌫" then "secondary" else "glass", order = i, textSize = 24, onClick = function()
			if sent or phase ~= "input" then
				return
			end
			if kname == "⌫" then
				typed = string.sub(typed, 1, math.max(0, #typed - 1))
			elseif kname == "✔" then
				submit()
				return
			elseif #typed < len then
				typed ..= kname
			end
			big.Text = slots()
			if #typed >= len then
				submit()
			end
		end })
	end

	local api = {}
	function api.game(g: any)
		Stage.updateScore(g.len .. "자리")
	end
	function api.event(e: any)
		if e.e == "memShow" then
			round = e.round
			len = e.len
			typed = ""
			sent = false
			phase = "show"
			big.Text = table.concat(string.split(e.seq, ""), " ")
			big.TextColor3 = K.Color.gold
			sub.Text = round .. "라운드 · " .. len .. "자리 외우기!"
			pad.Visible = false
			Stage.setDeadline(e.until_, math.max(0.5, e.until_ - Workspace:GetServerTimeNow()))
			inputDeadline = e.deadline
			inputSpan = math.max(1, e.deadline - e.until_)
			Stage.setStatus("외우세요!")
			K.pop(card, 0.9)
			Fx.sound("whoosh")
			card.Size = UDim2.fromOffset(math.max(300, 52 * len + 60), 96)
		elseif e.e == "memHide" then
			phase = "input"
			big.TextColor3 = K.Color.text
			big.Text = slots()
			sub.Text = if you > 0 then "순서대로 입력하세요" else "입력 중…"
			pad.Visible = you > 0
			Stage.setStatus("입력!")
			Stage.setDeadline(inputDeadline, inputSpan)
			Fx.sound("tick")
		elseif e.e == "memSent" then
			sent = true
		elseif e.e == "memJudge" then
			phase = "judge"
			pad.Visible = false
			big.Text = table.concat(string.split(e.seq, ""), " ")
			big.TextColor3 = K.Color.text
			local function mark(ok: boolean): string
				return if ok then "✔" else "✖"
			end
			sub.Text = string.format("%s %s   ·   %s %s", view.sides[1].name, mark(e.ok1), view.sides[2].name, mark(e.ok2))
			local mine = if you == 1 then e.ok1 elseif you == 2 then e.ok2 else nil
			if mine ~= nil then
				Stage.flash(if mine then "정답!" else "땡!", if mine then K.Color.green else K.Color.red, 1.2)
				Fx.sound(if mine then "win" else "buzz")
			end
			Stage.setStatus(nil)
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

return MemoryClient
