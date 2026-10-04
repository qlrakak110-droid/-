--!strict
-- Quiz/QuizClient: 퀴즈 대결 (client only). The question card sits under the VS bar, four big answer
-- buttons (2 x 2) at the bottom. One tap locks your answer (the time since the question appeared on
-- this device is sent with it); the reveal colours the right answer green, wrong picks red, and
-- tells who scored.

local Workspace = game:GetService("Workspace")

local QuizClient = {}

function QuizClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local you = ctx.you
	local view = ctx.view
	local qi = 0
	local shownAt = 0
	local locked: number? = nil

	local card = K.Panel(ctx.gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(460, 92), Radius = K.Radius.xl, ZIndex = 5 })
	local head = K.text(card, { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 16), TextSize = K.Type.caption, TextColor3 = K.Color.cyan, Font = K.Font.bold, ZIndex = 6 })
	local qText = K.text(card, { Position = UDim2.fromOffset(16, 26), Size = UDim2.new(1, -32, 0, 58), TextWrapped = true, Font = K.Font.bold, TextSize = K.Type.title2, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6 })

	local grid = K.frame(ctx.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(520, 124) })
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -5, 0, 56)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local buttons: { TextButton } = {}
	for i = 1, 4 do
		local b = K.Button(grid, { text = "", style = "glass", order = i, textSize = K.Type.body, onClick = function()
			if you == 0 or locked or qi == 0 then
				return
			end
			locked = i
			Net.send("move", { q = qi, choice = i, t = os.clock() - shownAt })
			for k, bb in buttons do
				bb.BackgroundTransparency = if k == i then 0 else 0.5
			end
			Fx.sound("pop")
		end })
		buttons[i] = b
	end

	local function resetButtons(choices: { string })
		for i, b in buttons do
			b.Text = string.char(64 + i) .. ".  " .. (choices[i] or "")
			b.BackgroundColor3 = K.Color.glass
			b.BackgroundTransparency = K.GLASS_T
			b.TextColor3 = K.Color.text
		end
	end

	local api = {}
	function api.game(g: any)
		Stage.updateScore(string.format("%d : %d", g.score[1], g.score[2]))
		if g.phase == "q" then
			Stage.setDeadline(g.deadline, g.qtime)
		end
	end
	function api.event(e: any)
		if e.e == "quizQ" then
			qi = e.qi
			locked = nil
			shownAt = os.clock()
			head.Text = if e.extra then "서든데스!" else ("Q" .. e.qi .. " / 5")
			qText.Text = e.q
			resetButtons(e.c)
			K.pop(card, 0.92)
			Fx.sound("whoosh")
			Stage.setStatus(if you > 0 then "빨리 맞히면 1점!" else nil)
			Stage.setDeadline(e.deadline, math.max(1, e.deadline - Workspace:GetServerTimeNow()))
		elseif e.e == "quizLocked" then
			locked = e.c
		elseif e.e == "quizReveal" then
			for i, b in buttons do
				if i == e.a then
					b.BackgroundColor3 = Color3.fromRGB(30, 120, 70)
					b.BackgroundTransparency = 0
				elseif i == e.c1 or i == e.c2 then
					b.BackgroundColor3 = Color3.fromRGB(130, 36, 44)
					b.BackgroundTransparency = 0
				end
			end
			local w = e.w
			Stage.flash(if w == 0 then "아무도 못 맞혔어요" elseif w == you then "+1점!" else (view.sides[w].name .. " +1점"), if w == you and you > 0 then K.Color.gold else nil, 1.4)
			Fx.sound(if w == you and you > 0 then "win" elseif w == 0 then "buzz" else "pop")
			Stage.updateScore(string.format("%d : %d", e.s1, e.s2))
			Stage.setStatus(nil)
		elseif e.e == "quizSudden" then
			Stage.flash("동점! 서든데스", K.Color.magenta, 1.5)
		end
	end
	function api.update(_v: any) end
	function api.destroy()
		card:Destroy()
		grid:Destroy()
		Stage.setStatus(nil)
		Stage.setDeadline(nil)
	end
	return api
end

return QuizClient
