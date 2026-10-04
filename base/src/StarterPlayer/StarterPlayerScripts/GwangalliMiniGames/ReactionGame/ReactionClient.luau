--!strict
-- ReactionGame/ReactionClient: 순발력 대결 (client only). One huge round button in the middle of the
-- screen: red "준비…" while waiting (pressing now = 부정 출발!), green "지금!" the moment the server's
-- go event arrives. Your own reaction time is measured from that arrival on this device and sent with
-- the press; the server compares it with its own clock (see ReactionServer) and decides.
-- Keyboard: Space presses too.

local ContextActionService = game:GetService("ContextActionService")

local ReactionClient = {}

function ReactionClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local you = ctx.you
	local view = ctx.view
	local g: any = nil
	local round = 0
	local phase = "idle"
	local goAt = 0
	local pressed = false

	local size = 210
	local big = K.make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.fromRGB(180, 40, 56),
		AutoButtonColor = false,
		Text = "준비…",
		Font = K.Font.heavy,
		TextSize = 40,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 10,
		Visible = you > 0,
	}, ctx.gui)
	K.corner(big, UDim.new(0.5, 0))
	local ring = K.stroke(big, Color3.new(1, 1, 1), 4, 0.6)
	local _ = ring
	local info = K.text(ctx.gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.56, size / 2 + 10), Size = UDim2.fromOffset(360, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.bold, TextSize = K.Type.title2, TextStrokeTransparency = 0.5, ZIndex = 10 })

	local function setBig(color: Color3, text: string)
		big.BackgroundColor3 = color
		big.Text = text
	end

	local function press()
		if you == 0 or pressed or round == 0 then
			return
		end
		if phase == "ready" then
			pressed = true
			Net.send("move", { round = round, early = true })
			setBig(Color3.fromRGB(90, 90, 100), "부정 출발!")
			Fx.sound("buzz")
		elseif phase == "go" then
			pressed = true
			local rt = os.clock() - goAt
			Net.send("move", { round = round, rt = rt })
			setBig(Color3.fromRGB(40, 120, 200), string.format("%d ms", math.floor(rt * 1000)))
			Fx.sound("pop")
			K.haptic("tap")
		end
	end
	big.Activated:Connect(press)
	ContextActionService:BindAction("MiniGameReactionPress", function(_, state)
		if state == Enum.UserInputState.Begin then
			press()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	local api = {}
	function api.game(v: any)
		g = v
		Stage.updateScore(string.format("%d : %d", g.score[1], g.score[2]))
	end
	function api.event(e: any)
		if e.e == "reactReady" then
			round = e.round
			phase = "ready"
			pressed = false
			setBig(Color3.fromRGB(180, 40, 56), "준비…")
			info.Text = round .. "라운드 · 초록색이 되면 누르세요!"
			info.TextColor3 = K.Color.text
			Stage.setStatus("준비…")
		elseif e.e == "reactGo" then
			phase = "go"
			goAt = os.clock()
			setBig(Color3.fromRGB(40, 200, 110), "지금!")
			K.pop(big, 0.85)
			Fx.sound("go")
			Stage.setStatus("지금!")
		elseif e.e == "reactFoul" then
			local who = view.sides[e.side]
			info.Text = (if e.side == you then "부정 출발!" else (who and who.name or "상대") .. " 부정 출발!")
			info.TextColor3 = K.Color.orange
		elseif e.e == "reactResult" then
			phase = "show"
			local function fmt(t: number?, foul: boolean): string
				if foul then
					return "부정 출발"
				end
				return if t then (t .. "ms") else "안 누름"
			end
			local a = fmt(e.t1, e.foul1)
			local b = fmt(e.t2, e.foul2)
			local w = e.w
			info.Text = string.format("%s %s · %s %s", view.sides[1].name, a, view.sides[2].name, b)
			info.TextColor3 = if w == you and you > 0 then K.Color.gold else K.Color.text
			Stage.flash(if w == 0 then "무승부" elseif w == you then "승리!" elseif you > 0 then "패배" else (view.sides[w].name .. " 승!"), if w == you then K.Color.gold else nil, 1.6)
			Stage.updateScore(string.format("%d : %d", e.s1, e.s2))
			Stage.setStatus(nil)
		end
	end
	function api.update(_v: any) end
	function api.destroy()
		ContextActionService:UnbindAction("MiniGameReactionPress")
		big:Destroy()
		info:Destroy()
		Stage.setStatus(nil)
	end
	return api
end

return ReactionClient
