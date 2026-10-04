--!strict
-- WordChain/WordChainClient: 끝말잇기 screen (client only).
--   centre: 현재 단어 (big) + the next start syllable ("차" / "력(역)") and the remaining time;
--   bottom: the mobile-keyboard input ("차______" placeholder, 보내기 / Enter) - only on your turn -
--   and the chain so far as chips. A refused word shows the server's reason in red under the input
--   while your clock keeps running. Accepted words also pop as bubbles over the speaker's head.

local Workspace = game:GetService("Workspace")

local WordChainClient = {}

function WordChainClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local WR = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliMiniGamesShared"):WaitForChild("WordRules")) :: any
	local you = ctx.you
	local g: any = nil

	local wordCard = K.Panel(ctx.gui, { Name = "WordCard", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(300, 112), Radius = K.Radius.xl, ZIndex = 5 })
	K.text(wordCard, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Text = "현재 단어", ZIndex = 6 })
	local word = K.text(wordCard, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 46), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 38, Text = "…", ZIndex = 6 })
	local timeL = K.text(wordCard, { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.bold, TextSize = K.Type.title2, TextColor3 = K.Color.cyan, ZIndex = 6 })

	local bottom = K.Panel(ctx.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, if you > 0 then 138 else 64), Radius = K.Radius.xl })
	local chips = K.make("ScrollingFrame", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 34), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new() }, bottom)
	K.list(chips, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local box: TextBox? = nil
	local sendBtn: TextButton? = nil
	local err: TextLabel? = nil
	if you > 0 then
		local b = K.make("TextBox", {
			Position = UDim2.fromOffset(12, 48),
			Size = UDim2.new(1, -118, 0, 52),
			BackgroundColor3 = K.Color.card,
			TextColor3 = K.Color.text,
			PlaceholderColor3 = K.Color.faint,
			Font = K.Font.bold,
			TextSize = 22,
			ClearTextOnFocus = false,
			Text = "",
			PlaceholderText = "",
			TextXAlignment = Enum.TextXAlignment.Left,
		}, bottom)
		K.corner(b, K.Radius.md)
		K.pad(b, 14, 14, 0, 0)
		box = b
		local function send()
			if not g or g.turn ~= you then
				return
			end
			local w = WR.normalize(b.Text)
			if w == "" then
				return
			end
			local ok, why = WR.shape(w)
			if not ok then
				(err :: TextLabel).Text = why or ""
				return
			end
			if not WR.follows(g.current, w) then
				(err :: TextLabel).Text = "'" .. g.hint .. "'(으)로 시작해야 해요"
				return
			end
			(err :: TextLabel).Text = "확인 중…"
			Net.send("move", { word = w })
		end
		sendBtn = K.Button(bottom, { text = "보내기", style = "primary", size = UDim2.fromOffset(94, 52), position = UDim2.new(1, -106, 0, 48), textSize = K.Type.body, onClick = send })
		b.FocusLost:Connect(function(enter)
			if enter then
				send()
			end
		end)
		err = K.text(bottom, { Position = UDim2.fromOffset(14, 104), Size = UDim2.new(1, -28, 0, 22), TextSize = K.Type.caption, TextColor3 = K.Color.red, Text = "" })
	end

	local function setChips()
		for _, c in chips:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		if not g then
			return
		end
		for i, c in g.chain do
			local mine = c.s == you and you > 0
			local chip = K.text(chips, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), BackgroundTransparency = 0, BackgroundColor3 = if c.s == 0 then K.Color.card3 elseif mine then Color3.fromRGB(22, 58, 76) else K.Color.card2, TextColor3 = if mine then K.Color.cyan else K.Color.text, TextSize = K.Type.bodySm, Font = K.Font.bold, Text = c.w, LayoutOrder = i })
			K.corner(chip, UDim.new(0.5, 0))
			K.pad(chip, 10, 10, 0, 0)
		end
		chips.CanvasPosition = Vector2.new(1e5, 0)
	end

	local function refresh()
		if not g then
			return
		end
		word.Text = g.current
		local mine = you > 0 and g.turn == you
		Stage.turn(g.turn)
		Stage.setDeadline(g.deadline, g.turnTime)
		Stage.updateScore(g.count .. "단어")
		Stage.setStatus(if mine then "내 차례! '" .. g.hint .. "'(으)로 시작" else ("다음: '" .. g.hint .. "'"))
		if box then
			box.PlaceholderText = if mine then (g.starts[1] or "") .. "______" else "상대 차례…"
			box.TextEditable = mine
			if mine and not box:IsFocused() then
				box.Text = ""
				pcall(function()
					(box :: TextBox):CaptureFocus()
				end)
			end
			if sendBtn then
				K.setButtonEnabled(sendBtn, mine)
			end
		end
		setChips()
	end

	local stepConn = game:GetService("RunService").RenderStepped:Connect(function()
		if g then
			local left = math.max(0, g.deadline - Workspace:GetServerTimeNow())
			timeL.Text = string.format("남은 시간 %.1f초", left)
			timeL.TextColor3 = if left < 3 then K.Color.red else K.Color.cyan
		end
	end)

	local api = {}
	function api.game(view: any)
		local prevTurn = g and g.turn
		g = view
		if prevTurn ~= nil and prevTurn ~= g.turn and err then
			err.Text = ""
		end
		refresh()
	end
	function api.event(e: any)
		if e.e == "wordReject" and err then
			err.Text = "✖ " .. tostring(e.reason)
			Fx.sound("buzz")
			if box then
				box.Text = ""
			end
		elseif e.e == "word" then
			K.pop(word, 0.8)
			Fx.sound("pop")
		elseif e.e == "wordStart" then
			Stage.flash("시작 단어: " .. e.word, nil, 1.6)
		elseif e.e == "wordTimeout" then
			Stage.flash("시간 초과!", K.Color.red, 1.5)
		end
	end
	function api.update(_view: any) end
	function api.destroy()
		stepConn:Disconnect()
		wordCard:Destroy()
		bottom:Destroy()
		Stage.setStatus(nil)
		Stage.setDeadline(nil)
	end
	return api
end

return WordChainClient
