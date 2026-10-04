--!strict
-- TimingGame/TimingClient: 타이밍 게임 (client only). A marker sweeps a bar (faster each round); the
-- big STOP button (or Space) freezes it - the closer to the gold centre the more points (0-100).
-- The bar starts when the server's go event ARRIVES here, and the elapsed time on this device is
-- what is sent, so lag does not move your marker (TimingServer cross-checks it).

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local TimingClient = {}

local function posAt(t: number, period: number): number
	local u = (t / period) % 2
	return if u <= 1 then u else 2 - u
end

function TimingClient.mount(ctx: any): any
	local K, Net, Stage, Fx = ctx.K, ctx.Net, ctx.Stage, ctx.Fx
	local you = ctx.you
	local view = ctx.view
	local round = 0
	local period = 1.5
	local running = false
	local startAt = 0
	local stoppedAt: number? = nil

	local wrap = K.Panel(ctx.gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.new(0.8, 0, 0, 96), Radius = K.Radius.xl, ZIndex = 5 })
	local title = K.text(wrap, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.sub, ZIndex = 6 })
	local bar = K.frame(wrap, { Position = UDim2.new(0, 16, 0, 32), Size = UDim2.new(1, -32, 0, 34), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, ZIndex = 6 })
	K.corner(bar, K.Radius.sm)
	local zone2 = K.frame(bar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.3, 1), BackgroundTransparency = 0.55, BackgroundColor3 = K.Color.green, ZIndex = 7 })
	local zone1 = K.frame(bar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.08, 1), BackgroundTransparency = 0.1, BackgroundColor3 = K.Color.gold, ZIndex = 8 })
	local _ = zone2
	local _2 = zone1
	local marker = K.frame(bar, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 6, 1, 14), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 9 })
	K.corner(marker, UDim.new(0.5, 0))
	local other = K.frame(bar, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 6, 1, 14), BackgroundTransparency = 0, BackgroundColor3 = K.Color.magenta, Visible = false, ZIndex = 9 })
	K.corner(other, UDim.new(0.5, 0))
	local pts = K.text(wrap, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.bold, TextSize = K.Type.bodySm, ZIndex = 6 })

	local stop = K.make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = Color3.fromRGB(255, 176, 32),
		AutoButtonColor = false,
		Text = "STOP",
		Font = K.Font.heavy,
		TextSize = 40,
		TextColor3 = Color3.fromRGB(40, 24, 0),
		Visible = you > 0,
	}, ctx.panel)
	K.corner(stop, UDim.new(0.5, 0))
	K.stroke(stop, Color3.new(1, 1, 1), 4, 0.5)

	local function press()
		if you == 0 or not running or stoppedAt then
			return
		end
		local t = os.clock() - startAt
		stoppedAt = t
		Net.send("move", { round = round, t = t })
		Fx.sound("pop")
		K.haptic("tap")
		local p = posAt(t, period)
		marker.Position = UDim2.fromScale(p, 0.5)
		pts.Text = string.format("%d점", math.max(0, math.floor(100 - math.abs(p - 0.5) * 200 + 0.5)))
	end
	stop.Activated:Connect(press)
	ContextActionService:BindAction("MiniGameTimingStop", function(_, state)
		if state == Enum.UserInputState.Begin then
			press()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	local stepConn = RunService.RenderStepped:Connect(function()
		if running and not stoppedAt then
			marker.Position = UDim2.fromScale(posAt(os.clock() - startAt, period), 0.5)
		end
	end)

	local api = {}
	function api.game(g: any)
		Stage.updateScore(string.format("%d : %d", g.total[1], g.total[2]))
	end
	function api.event(e: any)
		if e.e == "timingReady" then
			round = e.round
			period = e.period
			running = false
			stoppedAt = nil
			other.Visible = false
			marker.Position = UDim2.fromScale(0, 0.5)
			pts.Text = ""
			title.Text = round .. " / 3 라운드 · 가운데 금색에 맞춰 멈추세요"
			Stage.flash(round .. "라운드", nil, 1.0)
		elseif e.e == "timingGo" then
			running = true
			startAt = os.clock()
			Fx.sound("go")
		elseif e.e == "timingResult" then
			running = false
			local mine = if you == 2 then e.p2 else e.p1
			local theirs = if you == 2 then e.p1 else e.p2
			if you == 0 then
				mine, theirs = e.p1, e.p2
			end
			if mine then
				marker.Position = UDim2.fromScale(mine, 0.5)
			end
			if theirs then
				other.Visible = true
				other.Position = UDim2.fromScale(theirs, 0.5)
			end
			pts.Text = string.format("%s %d점 · %s %d점", view.sides[1].name, e.s1, view.sides[2].name, e.s2)
			Stage.updateScore(string.format("%d : %d", e.t1, e.t2))
		end
	end
	function api.update(_v: any) end
	function api.destroy()
		ContextActionService:UnbindAction("MiniGameTimingStop")
		stepConn:Disconnect()
		wrap:Destroy()
		stop:Destroy()
	end
	return api
end

return TimingClient
