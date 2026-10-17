--!strict
-- GwangalliDecorPlus/Visit: the always-on home pill (above the life game's HomeBar) —
--   owner at home: ✨ 자유 배치 (K) · ⭐ 점수 · ❤️ 좋아요 수 · 📝 방명록 (지우기)
--   guest (집들이): 🏠 OO님의 집 · ⭐ · ❤️ 좋아요 (하루 1번) · 📝 방명록 남기기 (필터링) · 🔍 구경 · 📸 사진
--   Visit.mount(api) / Visit.update(state) / Visit.setVisible(b)
--   api = { openEditor(), photo(), role() -> ("owner" | "guest" | nil, ownerId?), model() -> Model? }

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Catalog, Text, Config = Shared.Catalog, Shared.Text, Shared.Config

local Ui = require(script.Parent:WaitForChild("Ui"))
local Net = require(script.Parent:WaitForChild("Net"))
local C, F = Ui.C, Ui.F

local Visit = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local row: Frame? = nil
local api: any = nil
local state: any = nil
local inspecting = false
local inspectConn: RBXScriptConnection? = nil
local lastRole: string? = nil

local function homeBarTop(): number?
	local pg = player:FindFirstChild("PlayerGui")
	local hg = pg and pg:FindFirstChild("GwangalliHome")
	local bar = hg and hg:FindFirstChild("HomeBar", true)
	if bar and bar:IsA("GuiObject") and bar.Visible and (hg :: ScreenGui).Enabled then
		return bar.AbsolutePosition.Y
	end
	return nil
end

local function timeAgo(t: number): string
	local d = os.time() - t
	if d < 60 then
		return "방금"
	elseif d < 3600 then
		return string.format("%d분 전", d // 60)
	elseif d < 86400 then
		return string.format("%d시간 전", d // 3600)
	end
	return string.format("%d일 전", d // 86400)
end

local function refreshState()
	local role, ownerId = api.role()
	if not role then
		return
	end
	local res = Net.call("state", { ownerId = ownerId })
	if res.ok then
		state = res
		Visit.draw()
	end
end

function Visit.guestbook()
	if not state or not gui then
		return
	end
	local isOwner = state.isOwner
	local m = Ui.modal("📝 " .. (if isOwner then "우리 집 방명록" else (state.ownerName .. "님의 방명록")), { gui = gui, w = 520, h = 0.8 })
	local function draw(entries: { any })
		for _, c in m.body:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not isOwner then
			local box = Ui.textbox(m.body, Text.UI.gbWrite, { LayoutOrder = 1 })
			local send = Ui.button(m.body, { text = "✍️ " .. Text.UI.gbSend, w = UDim2.new(1, 0, 0, 44), style = "primary", order = 2 })
			send.Activated:Connect(function()
				local text = Text.clip(box.Text, Config.GUESTBOOK_LEN)
				if text == "" then
					Ui.toast(Text.reason("empty"), "bad")
					return
				end
				send.Text = "보내는 중…"
				local res = Net.call("guestbook", { ownerId = state.ownerId, text = text })
				if res.ok then
					state.gb = res.entries
					Ui.toast("📝 방명록을 남겼어요", "good")
					draw(res.entries)
				else
					send.Text = "✍️ " .. Text.UI.gbSend
					Ui.toast("❌ " .. res.msg, "bad")
				end
			end)
		end
		if #entries == 0 then
			Ui.label(m.body, Text.UI.gbEmpty, 14, C.sub, F.medium, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y })
		end
		for i, e in entries do
			local card = Ui.new("Frame", { BackgroundColor3 = C.card, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 10 + i, Parent = m.body })
			Ui.corner(card, 12)
			Ui.pad(card, 12, 8, if isOwner then 56 else 12, 10)
			Ui.list(card, "y", 2)
			Ui.label(card, string.format("<b>%s</b>  <font color=\"#8a90a6\">%s</font>", e.n, timeAgo(e.t)), 13, C.text, F.medium, { LayoutOrder = 1 })
			Ui.label(card, e.m, 14, C.text, F.medium, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.Y, RichText = false })
			if isOwner then
				local del = Ui.button(card, { text = "🗑", w = 40, h = 36, style = "ghost" })
				del.Position = UDim2.new(1, 8, 0, 0)
				del.Activated:Connect(function()
					local res = Net.call("gbDelete", { t = e.t, u = e.u })
					if res.ok then
						state.gb = res.entries
						draw(res.entries)
					end
				end)
			end
		end
	end
	draw(state.gb or {})
end

local function inspectAt(p: Vector2)
	local model = api.model()
	local folder = model and model:FindFirstChild(Config.FOLDER_NAME)
	if not folder then
		return
	end
	local cam = workspace.CurrentCamera :: Camera
	local r = cam:ViewportPointToRay(p.X, p.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(r.Origin, r.Direction * 300, params)
	if not hit then
		return
	end
	local m = hit.Instance:FindFirstAncestorWhichIsA("Model")
	while m and m.Parent ~= folder do
		m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model")
	end
	local id = m and m:GetAttribute("ItemId")
	local def = type(id) == "string" and Catalog.get(id) or nil
	if not def or not gui then
		return
	end
	local catInfo = Catalog.CAT_BY_ID[def.cat]
	local st = Catalog.STYLE_BY_ID[def.style]
	local look = m and m:GetAttribute("Look")
	local c, mm = nil, nil
	if type(look) == "string" then
		local parts = string.split(look, "|")
		if parts[1] and parts[1] ~= "" then
			c = {}
			for i, h in string.split(parts[1], ",") do
				c[i] = if h ~= "" then h else false
			end
		end
		if parts[2] and parts[2] ~= "" then
			mm = {}
			for i = 1, #parts[2] do
				mm[i] = tonumber(string.sub(parts[2], i, i))
			end
		end
	end
	local modal = Ui.modal("🔍 " .. def.name, { gui = gui, w = 420, h = 0.5 })
	local lines = {
		string.format("%s %s · %s", catInfo.icon, catInfo.name, st and st.name or ""),
		"지금 모습: " .. Catalog.lookName(id, c, mm),
		string.format("가격 %s · ⭐ 인테리어 +%d", Text.won(def.price), def.decor),
		string.format("이 가구는 ✨ 자유 배치의 '%s' 탭에 있어요", catInfo.name),
	}
	for i, l in lines do
		Ui.label(modal.body, l, 14, if i == 3 then C.gold else C.text, F.medium, { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.Y })
	end
end

local function setInspect(on: boolean)
	inspecting = on
	if inspectConn then
		inspectConn:Disconnect()
		inspectConn = nil
	end
	if on then
		Ui.toast("🔍 궁금한 가구를 눌러 보세요")
		inspectConn = UserInputService.InputEnded:Connect(function(input, gp)
			if gp then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				inspectAt(UserInputService:GetMouseLocation())
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local inset = game:GetService("GuiService"):GetGuiInset()
				inspectAt(Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y))
			end
		end)
	end
	Visit.draw()
end

local function pillBtn(text: string, style: string, order: number, fn: () -> ()): TextButton
	return Ui.button(row, { text = text, auto = true, h = 46, style = style, order = order, size = 15, onClick = fn })
end

function Visit.draw()
	if not row then
		return
	end
	for _, c in (row :: Frame):GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local role = api.role()
	if role == "owner" then
		pillBtn("✨ 자유 배치" .. (if UserInputService.KeyboardEnabled then " (K)" else ""), "primary", 1, function()
			api.openEditor()
		end)
		if state then
			pillBtn(string.format("⭐ %d", state.score and state.score.total or 0), "tonal", 2, function()
				Ui.toast(string.format("⭐ 인테리어 %d점 · %s", state.score.total, state.score.grade), "gold")
			end)
			pillBtn(string.format("❤️ %d · 📝 %d", state.likes or 0, #(state.gb or {})), "tonal", 3, function()
				Visit.guestbook()
			end)
		end
	elseif role == "guest" and state then
		local info = Ui.label(row, string.format("🏠 %s님의 집 · ⭐ %d", state.ownerName, state.score and state.score.total or 0), 14, C.text, F.bold, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 46),
			LayoutOrder = 0,
			BackgroundColor3 = C.glass,
			BackgroundTransparency = 0.15,
			TextWrapped = false,
		})
		Ui.corner(info, 12)
		Ui.pad(info, 12, 0, 12, 0)
		pillBtn((if state.liked then "💖 " else "❤️ ") .. tostring(state.likes or 0), if state.liked then "magenta" else "tonal", 1, function()
			if state.liked then
				Ui.toast(Text.reason("liked"))
				return
			end
			local res = Net.call("like", { ownerId = state.ownerId })
			if res.ok then
				state.likes = res.likes
				state.liked = true
				Ui.toast(Text.UI.liked, "good")
				Visit.draw()
			else
				Ui.toast("❌ " .. res.msg, "bad")
				if res.code == "liked" then
					state.liked = true
					Visit.draw()
				end
			end
		end)
		pillBtn(Text.UI.guestbook, "tonal", 2, function()
			Visit.guestbook()
		end)
		pillBtn(if inspecting then "🔍 구경 끄기" else Text.UI.inspect, if inspecting then "primary" else "tonal", 3, function()
			setInspect(not inspecting)
		end)
		pillBtn("📸", "tonal", 4, function()
			api.photo()
		end)
	end
end

function Visit.update()
	local role, _ = api.role()
	if role ~= lastRole then
		lastRole = role
		state = nil
		if inspecting then
			setInspect(false)
		end
		if role then
			task.spawn(refreshState)
		end
		Visit.draw()
	end
	if not gui or not row then
		return
	end
	local top = homeBarTop()
	local scale = (gui :: ScreenGui):FindFirstChildOfClass("UIScale")
	local s = scale and scale.Scale or 1
	local r = row :: Frame
	r.AnchorPoint = Vector2.new(0.5, 0)
	if top then
		local inset = game:GetService("GuiService"):GetGuiInset()
		r.Position = UDim2.new(0.5, 0, 0, (top - inset.Y) / s - 54)
	else
		r.Position = UDim2.new(0.5, 0, 1, -150)
	end
end

function Visit.setVisible(b: boolean)
	if gui then
		gui.Enabled = b
	end
end

function Visit.refresh()
	task.spawn(refreshState)
end

function Visit.mount(a: any)
	api = a
	gui = Ui.screen("GwangalliDecorPlusPill", 13)
	Ui.scale(gui :: ScreenGui)
	row = Ui.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 48), Position = UDim2.new(0.5, 0, 1, -150), AnchorPoint = Vector2.new(0.5, 0), Parent = gui })
	Ui.list(row :: Frame, "x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	Net.on("liked", function(p)
		if state then
			state.likes = p.likes
			Visit.draw()
		end
	end)
	Net.on("guestbook", function(p)
		if state and p.entry then
			state.gb = state.gb or {}
			table.insert(state.gb, 1, p.entry)
			Visit.draw()
		end
	end)
	Net.on("score", function(p)
		if state and p.score then
			state.score = p.score
			Visit.draw()
		end
	end)
end

return Visit
