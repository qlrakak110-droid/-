--!strict
-- RockPaperScissors/RpsClient: 가위바위보 screen (client only). "3 · 2 · 1 · 가위바위보!" follows the
-- server's shoot time; three big thumb buttons (✊ 바위 ✋ 보 ✌️ 가위) can be pressed any time during
-- the count (your pick is confirmed by the server, the other side's is never known before the
-- reveal). At the reveal both hands pop up in the middle and over each character's hand.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RpsClient = {}

local GLYPH = { "✊", "✋", "✌️" }
local NAME = { "바위", "보", "가위" }

function RpsClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local you = ctx.you
	local view = ctx.view
	local g: any = nil
	local tShoot = 0
	local round = 0
	local picked: number? = nil
	local lastCount = ""

	local bar = K.frame(ctx.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(math.min(420, 9999), 104) })
	local buttons: { TextButton } = {}
	if you > 0 then
		K.list(bar, true, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
		for i = 1, 3 do
			local b = K.Button(bar, { text = GLYPH[i], style = "glass", size = UDim2.fromOffset(104, 96), order = i, textSize = 50, onClick = function()
				if picked or not g or g.phase ~= "count" then
					return
				end
				picked = i
				Net.send("move", { hand = i })
				for k, bb in buttons do
					bb.BackgroundTransparency = if k == i then 0 else 0.6
					bb.TextTransparency = if k == i then 0 else 0.55
				end
				Fx.sound("pop")
			end })
			local lab = K.text(b, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, Text = NAME[i], TextColor3 = K.Color.sub })
			local _ = lab
			buttons[i] = b
		end
	end

	-- reveal card
	local reveal = K.Panel(ctx.gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(300, 150), Visible = false, Radius = K.Radius.xl, ZIndex = 20 })
	local left = K.text(reveal, { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(120, 90), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 72, ZIndex = 21 })
	local right = K.text(reveal, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(120, 90), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 72, ZIndex = 21 })
	K.text(reveal, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 36), Size = UDim2.fromOffset(40, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 18, Text = "VS", TextColor3 = K.Color.gold, ZIndex = 21 })
	local verdict = K.text(reveal, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 26, ZIndex = 21 })

	local function resetPick()
		picked = nil
		for _, b in buttons do
			b.BackgroundTransparency = 0.14
			b.TextTransparency = 0
		end
	end

	local stepConn = RunService.RenderStepped:Connect(function()
		if not g or g.phase ~= "count" or tShoot <= 0 then
			return
		end
		local left_ = tShoot - Workspace:GetServerTimeNow()
		local txt
		if left_ > 2 then
			txt = "3"
		elseif left_ > 1 then
			txt = "2"
		elseif left_ > 0 then
			txt = "1"
		else
			txt = "가위바위보!"
		end
		if txt ~= lastCount then
			lastCount = txt
			Stage.flash(txt, if txt == "가위바위보!" then K.Color.gold else nil, 1.0)
			Fx.sound(if txt == "가위바위보!" then "go" else "tick")
		end
	end)

	local api = {}
	function api.game(v: any)
		g = v
		Stage.updateScore(string.format("%d : %d", g.score[1], g.score[2]))
		Stage.setStatus(if g.phase == "count" then (if picked then "선택 완료!" elseif you > 0 then "하나를 골라요!" else "가위바위보!") else nil)
	end
	function api.event(e: any)
		if e.e == "rpsRound" then
			round = e.round
			tShoot = e.tShoot
			lastCount = ""
			reveal.Visible = false
			resetPick()
		elseif e.e == "rpsReveal" then
			local mine = if you == 2 then e.c2 else e.c1
			local theirs = if you == 2 then e.c1 else e.c2
			left.Text = GLYPH[mine] or "?"
			right.Text = GLYPH[theirs] or "?"
			local w = e.w
			if you == 0 then
				verdict.Text = if w == 0 then "비김" else (view.sides[w].name .. " 승!")
				verdict.TextColor3 = K.Color.text
			else
				verdict.Text = if w == 0 then "비김! 다시" elseif w == you then "이겼다!" else "졌다…"
				verdict.TextColor3 = if w == 0 then K.Color.text elseif w == you then K.Color.gold else K.Color.sub
			end
			if (you == 1 and e.late1) or (you == 2 and e.late2) then
				verdict.Text ..= " (늦어서 랜덤)"
			end
			reveal.Visible = true
			K.pop(reveal, 0.7)
			Fx.sound(if w == 0 then "pop" elseif w == you then "win" else "lose")
			-- hands over the characters
			for side = 1, 2 do
				local s = view.sides[side]
				local hand = if side == 1 then e.c1 else e.c2
				local char = if s.npc then nil else Fx.characterOf(s.userId)
				if char then
					Fx.hand(char, hand, 2.2)
				elseif s.npc and ctx.model then
					-- the NPC host rig is in workspace.GwangalliNPCs, tagged by its station
					local npcs = Workspace:FindFirstChild(ctx.MS.NpcFolder)
					if npcs then
						for _, m in npcs:GetChildren() do
							if m:GetAttribute("MiniGameHost") == view.station then
								Fx.hand(m :: Model, hand, 2.2)
							end
						end
					end
				end
			end
			Stage.updateScore(string.format("%d : %d", e.s1, e.s2))
			task.delay(2.2, function()
				reveal.Visible = false
			end)
		elseif e.e == "rpsPicked" then
			picked = e.hand
		end
		local _ = round
	end
	function api.update(_v: any) end
	function api.destroy()
		stepConn:Disconnect()
		bar:Destroy()
		reveal:Destroy()
		Stage.setStatus(nil)
	end
	return api
end

return RpsClient
