--!strict
-- GwangalliMiniGames/Stage: the match screen around every game (client only, GwangalliUI kit).
--   * VS bar (top centre, compact): both players (rank / NPC level), whose turn it is (glow), the
--     state line ("자리에 앉는 중", "3 2 1", the game's own status), 상금, the game's score.
--   * the game panel (bottom, at most ~40 % of the screen so the table and the bay stay visible):
--     each game client draws its controls in Stage.panel.
--   * small buttons: 기권 (with confirm), 무승부 제안 / 수락 (turn games), 관전 종료 (spectators).
--   * countdown overlay, and the RESULT card: "OOO 승리!", +₩20,000 / -₩10,000 (count-up),
--     the record line (오목 33승 18패 · 승률 64% · 🥇 골드 +12), 재대결 / 나가기.
-- The ScreenGui carries HideGwangalliHUD while a match is shown, so the walking HUD steps aside.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Stage = {}

local K: any = nil
local MS: any = nil
local Net: any = nil
local Fx: any = nil
local gui: ScreenGui = nil :: any
local player = Players.LocalPlayer

local root: Frame = nil :: any
local vsBar: Frame = nil :: any
local sideFrames: { any } = {}
local center: TextLabel = nil :: any
local status: TextLabel = nil :: any
local potPill: TextLabel = nil :: any
local scoreLabel: TextLabel = nil :: any
local timerBar: Frame = nil :: any
local timerFill: Frame = nil :: any
local buttons: Frame = nil :: any
local forfeitBtn: TextButton = nil :: any
local drawBtn: TextButton = nil :: any
local leaveSpecBtn: TextButton = nil :: any
local countdown: TextLabel = nil :: any
local resultCard: Frame = nil :: any
Stage.panel = nil :: any -- Frame the game clients draw into

local current: any = nil -- last match view
local deadline: number = 0
local deadlineSpan: number = 1
local statusOverride: string? = nil
local scale: UIScale = nil :: any

function Stage.init(k: any, ms: any, net: any, fx: any, screen: ScreenGui)
	K, MS, Net, Fx, gui = k, ms, net, fx, screen
	Stage.build()
	RunService.RenderStepped:Connect(Stage.step)
end

local function sideCard(parent: Instance, align: string): any
	local f = K.frame(parent, { Size = UDim2.new(0.5, -34, 1, 0), Position = if align == "left" then UDim2.fromOffset(0, 0) else UDim2.new(0.5, 34, 0, 0) })
	local avatar = K.frame(f, { Size = UDim2.fromOffset(38, 38), AnchorPoint = Vector2.new(0, 0.5), Position = if align == "left" then UDim2.new(0, 10, 0.5, 0) else UDim2.new(1, -48, 0.5, 0), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2 })
	K.corner(avatar, UDim.new(0.5, 0))
	local glow = K.stroke(avatar, K.Color.cyan, 2.5, 1)
	local icon = K.text(avatar, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 20, Text = "🙂" })
	local name = K.text(f, { Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -66, 0, 18), Position = if align == "left" then UDim2.new(0, 56, 0, 9) else UDim2.new(0, 10, 0, 9), TextXAlignment = if align == "left" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right })
	local sub = K.text(f, { TextColor3 = K.Color.sub, TextSize = K.Type.micro, Size = UDim2.new(1, -66, 0, 14), Position = if align == "left" then UDim2.new(0, 56, 0, 29) else UDim2.new(0, 10, 0, 29), TextXAlignment = if align == "left" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right })
	return { frame = f, icon = icon, name = name, sub = sub, glow = glow, avatar = avatar }
end

function Stage.build()
	root = K.frame(gui, { Name = "Stage", Size = UDim2.fromScale(1, 1), Visible = false })
	scale = Instance.new("UIScale")
	scale.Parent = root
	-- VS bar
	vsBar = K.Panel(root, { Name = "VsBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(520, 58), Radius = K.Radius.lg })
	sideFrames[1] = sideCard(vsBar, "left")
	sideFrames[2] = sideCard(vsBar, "right")
	center = K.text(vsBar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(68, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 20, Text = "VS", TextColor3 = K.Color.gold })
	scoreLabel = K.text(vsBar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(80, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.text, Font = K.Font.bold })
	timerBar = K.frame(vsBar, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -28, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3 })
	K.corner(timerBar, UDim.new(0.5, 0))
	timerFill = K.frame(timerBar, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = K.Color.cyan })
	K.corner(timerFill, UDim.new(0.5, 0))
	-- status + pot under the bar
	local under = K.frame(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(520, 26) })
	K.list(under, true, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	potPill = K.text(under, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 0.15, BackgroundColor3 = Color3.fromRGB(44, 34, 8), TextColor3 = K.Color.gold, Font = K.Font.bold, TextSize = K.Type.caption, LayoutOrder = 1 })
	K.corner(potPill, UDim.new(0.5, 0))
	K.pad(potPill, 10, 10, 0, 0)
	status = K.text(under, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 0.25, BackgroundColor3 = K.Color.glass, TextColor3 = K.Color.text, Font = K.Font.bold, TextSize = K.Type.caption, LayoutOrder = 2 })
	K.corner(status, UDim.new(0.5, 0))
	K.pad(status, 10, 10, 0, 0)
	-- small action buttons (top right of the bar)
	buttons = K.frame(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(110, 140) })
	K.list(buttons, false, 6, Enum.HorizontalAlignment.Right)
	forfeitBtn = K.Button(buttons, { text = "기권", icon = "🏳", style = "danger", size = UDim2.fromOffset(104, 40), order = 1, textSize = K.Type.caption, onClick = function()
		K.confirm(gui, {
			title = "기권할까요?",
			body = "상대가 승리하고 참가비는 돌려받지 못해요.",
			confirmText = "기권",
			destructive = true,
			onConfirm = function()
				Net.send("forfeit")
			end,
		})
	end })
	drawBtn = K.Button(buttons, { text = "무승부", icon = "🤝", style = "secondary", size = UDim2.fromOffset(104, 40), order = 2, textSize = K.Type.caption, onClick = function()
		if current and current.drawOffer ~= 0 and current.drawOffer ~= current.you then
			Net.send("draw", { offer = true })
		elseif current and current.drawOffer == 0 then
			Net.send("draw", { offer = true })
			K.toast({ kind = "info", title = "무승부 제안", body = "상대의 답을 기다려요" })
		end
	end })
	leaveSpecBtn = K.Button(buttons, { text = "관전 종료", icon = "👀", style = "glass", size = UDim2.fromOffset(104, 40), order = 3, textSize = K.Type.caption, onClick = function()
		Net.send("unspectate")
	end })
	-- game panel
	Stage.panel = K.frame(root, { Name = "GamePanel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -16, 0.4, 0) })
	-- countdown
	countdown = K.text(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(300, 140), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 96, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Visible = false, ZIndex = 30 })
	-- result
	resultCard = K.Panel(root, { Name = "Result", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 300), Visible = false, ZIndex = 40, BackgroundTransparency = 0.04, Radius = K.Radius.xl })
	Stage.layout()
end

function Stage.layout()
	local cam = Workspace.CurrentCamera
	if not cam or not root then
		return
	end
	local vp = cam.ViewportSize
	local s = 1
	if vp.X < 700 or vp.Y < 420 then
		s = math.clamp(math.min(vp.X / 640, vp.Y / 400), 0.72, 1)
	end
	scale.Scale = s
	local w = math.min(520, vp.X / s - 140)
	vsBar.Size = UDim2.fromOffset(w, 58)
end

function Stage.root(): Frame
	return root
end

function Stage.setStatus(text: string?)
	statusOverride = text
end

-- deadline in server time (workspace:GetServerTimeNow()) and the full span for the timer bar
function Stage.setDeadline(t: number?, span: number?)
	deadline = t or 0
	deadlineSpan = span or 10
end

local STATE_TEXT = { seating = "자리에 앉는 중…", countdown = "곧 시작해요!", playing = "", result = "경기 종료" }

function Stage.show(view: any)
	current = view
	gui:SetAttribute("HideGwangalliHUD", true)
	root.Visible = true
	Stage.layout()
	local info = MS.GAMES[view.game]
	for i = 1, 2 do
		local s = view.sides[i]
		local f = sideFrames[i]
		f.name.Text = s.name .. (if i == view.you then " (나)" else "")
		f.sub.Text = if s.npc then ("NPC · " .. (s.difficulty or "")) else (s.rankIcon .. " " .. s.rank)
		f.icon.Text = if s.npc then "🧑" else s.rankIcon
	end
	potPill.Text = if view.stake > 0 then ("상금 " .. MS.won(view.pot)) else "친선전"
	center.Text = info and info.icon or "VS"
	local participant = view.you > 0
	forfeitBtn.Visible = participant and view.state == "playing"
	drawBtn.Visible = participant and view.state == "playing" and info ~= nil and info.turn and view.sides[3 - view.you] and not view.sides[3 - view.you].npc
	if drawBtn.Visible then
		drawBtn.Text = if view.drawOffer ~= 0 and view.drawOffer ~= view.you then "🤝  무승부 수락" elseif view.drawOffer == view.you then "🤝  제안함" else "🤝  무승부"
	end
	leaveSpecBtn.Visible = not participant
	-- countdown / seating overlay
	if view.state == "countdown" then
		countdown.Visible = true
	else
		countdown.Visible = false
	end
	if view.state == "result" and view.result then
		Stage.showResult(view)
	else
		resultCard.Visible = false
	end
end

function Stage.updateScore(text: string?)
	scoreLabel.Text = text or ""
end

function Stage.turn(side: number)
	for i = 1, 2 do
		local f = sideFrames[i]
		local on = side == i
		f.glow.Transparency = if on then 0 else 1
		f.name.TextColor3 = if on then K.Color.cyan else K.Color.text
	end
end

function Stage.hide()
	current = nil
	root.Visible = false
	resultCard.Visible = false
	countdown.Visible = false
	gui:SetAttribute("HideGwangalliHUD", nil)
	statusOverride = nil
	deadline = 0
	for _, c in Stage.panel:GetChildren() do
		c:Destroy()
	end
end

function Stage.flash(text: string, color: Color3?, dur: number?)
	countdown.Text = text
	countdown.TextColor3 = color or Color3.new(1, 1, 1)
	countdown.Visible = true
	countdown.TextSize = 72
	K.pop(countdown, 0.6)
	local token = os.clock()
	countdown:SetAttribute("Token", token)
	task.delay(dur or 1.2, function()
		if countdown:GetAttribute("Token") == token and not (current and current.state == "countdown") then
			countdown.Visible = false
		end
	end)
end

function Stage.step()
	if not current or not root.Visible then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if current.state == "countdown" then
		local left = math.max(0, current.tEnd - now)
		local n = math.ceil(left)
		local txt = if n > 0 then tostring(n) else "시작!"
		if countdown.Text ~= txt then
			countdown.Text = txt
			countdown.TextSize = 96
			countdown.TextColor3 = if n > 0 then Color3.new(1, 1, 1) else K.Color.gold
			K.pop(countdown, 0.5)
			Fx.sound(if n > 0 then "tick" else "go")
		end
	end
	local st = statusOverride or STATE_TEXT[current.state] or ""
	if st == "" and current.state == "playing" then
		st = MS.GAMES[current.game].name
	end
	status.Text = st
	status.Visible = st ~= ""
	if deadline > 0 and current.state == "playing" then
		local left = math.max(0, deadline - now)
		timerBar.Visible = true
		timerFill.Size = UDim2.fromScale(math.clamp(left / deadlineSpan, 0, 1), 1)
		timerFill.BackgroundColor3 = if left < 3 then K.Color.red elseif left < 6 then K.Color.orange else K.Color.cyan
	else
		timerBar.Visible = false
	end
end

-------------------------------------------------------------------------------------------------
-- result card
-------------------------------------------------------------------------------------------------
local REASONS = {
	five = "오목 완성!",
	full = "판이 가득 찼어요",
	timeout = "시간 초과",
	forfeit = "기권",
	left = "상대가 자리를 떠났어요",
	agreed = "무승부 합의",
	score = "",
	rounds = "",
	points = "",
	memory = "",
	exact = "정답!",
}

local resultShownFor = 0

function Stage.showResult(view: any)
	local r = view.result
	local first = resultShownFor ~= view.id
	resultShownFor = view.id
	for _, c in resultCard:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") and c.Name ~= "Sheen" then
			c:Destroy()
		end
	end
	resultCard.Visible = true
	local content = K.frame(resultCard, { Size = UDim2.new(1, -32, 1, -28), Position = UDim2.fromOffset(16, 14), ZIndex = 41 })
	K.list(content, false, 8, Enum.HorizontalAlignment.Center)
	local you = view.you
	local won = you > 0 and r.winner == you
	local lost = you > 0 and r.winner > 0 and r.winner ~= you
	local title = if r.winner == 0 then "무승부" else (r.winnerName .. " 승리!")
	local t = K.text(content, { Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 26, Text = title, TextColor3 = if won then K.Color.gold elseif lost then K.Color.sub else K.Color.text, LayoutOrder = 1, ZIndex = 42 })
	local _ = t
	local reason = REASONS[r.reason] or ""
	if reason ~= "" then
		K.text(content, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.sub, Text = reason, LayoutOrder = 2, ZIndex = 42 })
	end
	if you > 0 then
		local net = r.net[you] or 0
		local money = K.text(content, { Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, Font = K.Font.heavy, TextSize = 28, LayoutOrder = 3, ZIndex = 42, TextColor3 = if net > 0 then K.Color.green elseif net < 0 then K.Color.red else K.Color.text })
		if view.stake <= 0 then
			money.Text = "친선전"
			money.TextSize = 18
		elseif net == 0 then
			money.Text = if r.winner == 0 then "참가비 반환" else "±₩0"
			money.TextSize = 20
		else
			money.Text = (if net > 0 then "+" else "-") .. MS.won(math.abs(net))
			if first then
				pcall(function()
					K.countUp(money, math.abs(net), { prefix = (if net > 0 then "+₩" else "-₩") })
				end)
			end
		end
		if won and view.stake > 0 then
			K.text(content, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, TextColor3 = K.Color.gold, Text = "상금 " .. MS.won(if view.sides[3 - you].npc then view.stake + net else view.pot) .. " 획득", LayoutOrder = 4, ZIndex = 42 })
		end
		if r.capped then
			K.text(content, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.micro, TextColor3 = K.Color.orange, Text = "오늘 NPC 상금 한도에 도달해서 참가비만 돌려받았어요", LayoutOrder = 5, ZIndex = 42 })
		end
		local rec = r.records and r.records[you]
		if rec then
			local info = MS.GAMES[view.game]
			local line = string.format("%s %d승 %d패%s · 승률 %d%%", info.name, rec.w, rec.l, if rec.d > 0 then " " .. rec.d .. "무" else "", MS.winRate(rec.w, rec.l))
			K.text(content, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.caption, Text = line, LayoutOrder = 6, ZIndex = 42 })
			local d = rec.delta or 0
			K.text(content, {
				Size = UDim2.new(1, 0, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = K.Type.caption,
				Font = K.Font.bold,
				TextColor3 = if rec.rankUp then K.Color.gold else K.Color.sub,
				Text = string.format("%s %s · %d점 (%s%d)%s", rec.rankIcon, rec.rank, rec.rating, if d >= 0 then "+" else "", d, if rec.rankUp then " · 랭크 UP!" else ""),
				LayoutOrder = 7,
				ZIndex = 42,
			})
			if rec.streak and rec.streak >= 2 and won then
				K.text(content, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = K.Type.micro, TextColor3 = K.Color.magenta, Text = "🔥 " .. rec.streak .. "연승 중", LayoutOrder = 8, ZIndex = 42 })
			end
		end
		local row = K.frame(content, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 9, ZIndex = 42 })
		local other = 3 - you
		local otherVoted = view.votes[other]
		local meVoted = view.votes[you]
		local opponentGone = false
		local rb = K.Button(row, {
			text = if meVoted then "기다리는 중…" elseif otherVoted then "재대결 수락" else "재대결",
			icon = "🔁",
			style = if otherVoted then "gold" else "primary",
			size = UDim2.new(0.5, -4, 1, 0),
			zIndex = 43,
			onClick = function()
				Net.send("rematch")
			end,
		})
		if meVoted or opponentGone then
			K.setButtonEnabled(rb, false)
		end
		K.Button(row, { text = "나가기", style = "secondary", size = UDim2.new(0.5, -4, 1, 0), position = UDim2.new(0.5, 4, 0, 0), zIndex = 43, onClick = function()
			Net.send("leave")
		end })
		if first and won then
			Fx.sound("win")
			K.feedback("money")
		elseif first and lost then
			Fx.sound("lose")
		end
	else
		K.Button(content, { text = "관전 종료", style = "secondary", size = UDim2.new(1, 0, 0, 44), order = 9, zIndex = 43, onClick = function()
			Net.send("unspectate")
		end })
	end
	if first then
		K.pop(resultCard, 0.85)
	end
end

return Stage
