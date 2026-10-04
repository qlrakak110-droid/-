--!strict
-- Omok/OmokClient: your side of an 오목 match (client only). The board is the real 3D board on the
-- table (OmokBoards draws the stones); you play by touching it:
--   tap / click a point -> a see-through ghost stone appears there (red with the reason when it is a
--   forbidden point for 흑 under the korean rule) -> tap the same point again or press [착수].
-- Small drags still orbit the camera (CameraDirector), so only short taps count as a choice.
-- The panel stays small (bottom-right): colour, whose turn, the chosen point, [착수].

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local OmokClient = {}

local Boards = require(script.Parent:WaitForChild("OmokBoards")) :: any

function OmokClient.mount(ctx: any): any
	local K, MS, Net, Stage = ctx.K, ctx.MS, ctx.Net, ctx.Stage
	local OC = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliMiniGamesShared"):WaitForChild("OmokConfig")) :: any
	local model: Model? = ctx.model
	local you = ctx.you
	local g: any = nil
	local selected: number? = nil
	local conns: { RBXScriptConnection } = {}
	local matchState = ctx.view and ctx.view.state or "seating"

	local panel = K.Panel(ctx.panel, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(250, if you > 0 then 128 else 60), Radius = K.Radius.lg })
	local line1 = K.text(panel, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 20), Font = K.Font.bold, TextSize = K.Type.body })
	local line2 = K.text(panel, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 18), TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextWrapped = true })
	local placeBtn: TextButton? = nil
	if you > 0 then
		placeBtn = K.Button(panel, { text = "착수", icon = "⚫", style = "primary", size = UDim2.new(1, -24, 0, 56), position = UDim2.new(0, 12, 1, -64), textSize = K.Type.title2, onClick = function()
			if selected and g and g.turn == you then
				Net.send("move", { cell = selected })
				selected = nil
				if model then
					Boards.ghost(model, nil, 0)
				end
			end
		end })
	end

	local function myColor(): number
		return if g then g.color else 0
	end

	local function refresh()
		if not g then
			return
		end
		local mine = you > 0 and g.turn == you and matchState == "playing"
		local colorName = if myColor() == 1 then "⚫ 흑" elseif myColor() == 2 then "⚪ 백" else ""
		if you > 0 then
			line1.Text = colorName .. (if matchState ~= "playing" then "" elseif mine then " · 내 차례!" else " · 상대 차례")
			line1.TextColor3 = if mine then K.Color.cyan else K.Color.text
			if selected then
				local x, y = OC.xy(selected)
				local b = OC.decode(g.board)
				local bad = OC.forbidden(b, x, y, myColor(), g.rule)
				line2.Text = OC.label(selected) .. (if bad then " · " .. OC.FORBIDDEN_TEXT[bad] else " · 한 번 더 탭하거나 착수")
				line2.TextColor3 = if bad then K.Color.red else K.Color.sub
				if placeBtn then
					K.setButtonEnabled(placeBtn, mine and not bad)
				end
			else
				line2.Text = if matchState ~= "playing" then "곧 시작해요!" elseif mine then "판을 탭해서 둘 곳을 고르세요" else "상대가 생각 중이에요…"
				line2.TextColor3 = K.Color.sub
				if placeBtn then
					K.setButtonEnabled(placeBtn, false)
				end
			end
			if g.strikes and g.strikes[you] and g.strikes[you] > 0 and mine then
				line2.Text ..= " (시간 초과 1회!)"
			end
		else
			local blackSide = g.black
			line1.Text = (if g.turn == blackSide then "⚫ 흑" else "⚪ 백") .. " 차례"
			line2.Text = ""
		end
		Stage.turn(g.turn)
		Stage.setDeadline(g.deadline, g.moveTime)
		Stage.setStatus(if mine then "내 차례 · " .. colorName else nil)
	end

	local function choose(cell: number)
		if not g or g.turn ~= you or matchState ~= "playing" then
			return
		end
		local b = OC.decode(g.board)
		if b[cell] ~= 0 then
			return
		end
		if selected == cell then
			local x, y = OC.xy(cell)
			if not OC.forbidden(b, x, y, myColor(), g.rule) then
				Net.send("move", { cell = cell })
				selected = nil
				if model then
					Boards.ghost(model, nil, 0)
				end
				refresh()
				return
			end
		end
		selected = cell
		local x, y = OC.xy(cell)
		if model then
			Boards.ghost(model, cell, myColor(), OC.forbidden(b, x, y, myColor(), g.rule) ~= nil)
		end
		ctx.Fx.sound("pop", nil, 0.6)
		refresh()
	end

	if you > 0 and model then
		local downAt: Vector2? = nil
		table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				downAt = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))
		table.insert(conns, UserInputService.InputEnded:Connect(function(input, processed)
			if processed or not downAt then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local moved = (p - (downAt :: Vector2)).Magnitude
			downAt = nil
			if moved > 14 then
				return
			end
			local cam = Workspace.CurrentCamera
			local board = Boards.boardPart(model :: Model)
			if not cam or not board then
				return
			end
			local ray = cam:ViewportPointToRay(p.X, p.Y + (if input.UserInputType == Enum.UserInputType.MouseButton1 then 0 else 0))
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { board }
			local hit = Workspace:Raycast(ray.Origin, ray.Direction * 60, params)
			if hit then
				local cell = Boards.cellAt(model :: Model, hit.Position)
				if cell then
					choose(cell)
				end
			end
		end))
	end

	local api = {}
	function api.update(view: any)
		matchState = view.state
		if view.state ~= "playing" then
			Stage.setStatus(nil)
			selected = nil
			if model then
				Boards.ghost(model, nil, 0)
			end
		end
		refresh()
		if view.state ~= "playing" then
			Stage.setStatus(nil)
		end
	end
	function api.game(view: any)
		g = view
		if selected and g.board and string.sub(g.board, selected, selected) ~= "0" then
			selected = nil
			if model then
				Boards.ghost(model, nil, 0)
			end
		end
		refresh()
	end
	function api.event(e: any)
		if e.e == "omokStart" then
			Stage.flash(if you > 0 and e.black == you then "⚫ 흑 (선공)" elseif you > 0 then "⚪ 백 (후공)" else "흑 선공", nil, 1.4)
		end
	end
	function api.destroy()
		for _, c in conns do
			c:Disconnect()
		end
		if model then
			Boards.ghost(model, nil, 0)
		end
		Stage.setStatus(nil)
		Stage.setDeadline(nil)
		panel:Destroy()
	end
	return api
end

return OmokClient
