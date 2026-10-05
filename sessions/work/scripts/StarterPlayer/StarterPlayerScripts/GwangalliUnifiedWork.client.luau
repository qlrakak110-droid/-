--!nocheck
-- GwangalliUnifiedWork (LocalScript): the client of the 알바 work simulation (server: GwangalliGameplay/Work).
-- Server-authoritative: this script only shows the server's pushes and sends "do action X at station Y".
--   * 💼 알바 button → 구직 공고 (board): 근무처 · 숙련도 Lv / 직급 / XP · 다음 레벨 해금 · 근무 길이 · 지원 /
--     출근 · 목표 (돈의 쓰임)
--   * on shift: the work HUD (GwangalliUnifiedWork/Hud) + the world marker over the next station
--     (GwangalliUnifiedWork/Marker)
--   * toasts (보상 / 경고 / 호출 · 만족도), level-up popup (새 업무 · 기본급), end-of-shift prompt and the
--     정산서 (기본급 / 성과급 / 정확도 / 빠른 서비스 / 팁 / 할증 / 실수 차감 / 마감 수당 · XP · 목표)
-- Remote ReplicatedStorage.GwangalliRemotes.Work: client → server {op = board | apply | start | goal | hints |
-- end | cancel | focus | act}; server → client board / state / toast / levelup / endPrompt / settle / closed.
-- Test hook (workspace.GwangalliStreetLifeDebug == true): LocalPlayer.GwangalliWorkAPI (BindableFunction)
--   Invoke("send", payload) queues a remote call on this thread · Invoke("ui") -> a text summary.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("GwangalliRemotes", 60)
local remote = remotes and remotes:WaitForChild("Work", 60)
if not remote then
	return
end

local U = require(script:WaitForChild("UI"))
local Hud = require(script:WaitForChild("Hud"))
local Marker = require(script:WaitForChild("Marker"))
local C = U.C
local K = U.K

local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliUnifiedWork"
gui.ResetOnSpawn = false
gui.DisplayOrder = 24
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local busyUntil = 0
local function send(p: any)
	if os.clock() < busyUntil and p.op ~= "act" then
		return
	end
	busyUntil = os.clock() + 0.15
	remote:FireServer(p)
end

local function feedback(kind: string)
	if K and type(K.feedback) == "function" then
		pcall(K.feedback, kind)
	end
end

-------------------------------------------------------------------------------------------------
-- toggle + board panel
-------------------------------------------------------------------------------------------------
local toggle = U.button(gui, "💼 알바", nil, { Name = "Toggle", Size = UDim2.fromOffset(96, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 154), BackgroundColor3 = Color3.fromRGB(34, 46, 38) })

local panel = U.frame(gui, { Name = "Board", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.new(0.9, 0, 0.78, 0), BackgroundColor3 = C.bg, BackgroundTransparency = 0.04, Visible = false, ZIndex = 5 })
U.make("UISizeConstraint", { MaxSize = Vector2.new(560, 720), MinSize = Vector2.new(280, 240) }, panel)
U.corner(panel, 16)
U.stroke(panel)
local ptitle = U.text(panel, { Name = "Title", Font = U.BOLD, TextSize = 18, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -70, 0, 34), AutomaticSize = Enum.AutomaticSize.None, Text = "💼 알바 공고 · 근무 선택" })
U.button(panel, "×", function()
	panel.Visible = false
end, { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(1, -50, 0, 2), BackgroundTransparency = 1, TextSize = 26 })
local scroll = U.make("ScrollingFrame", { Name = "List", Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 1, -56), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, panel)
U.list(scroll, 8)

local lastBoard: any = nil
local lastState: any = nil
local selectedLength: { [string]: string } = {}

local function line(parent: Instance, text: string, props: any?): TextLabel
	local pr = props or {}
	pr.Text = text
	return U.text(parent, pr)
end

local function showBoard(p: any)
	lastBoard = p
	U.clear(scroll)
	ptitle.Text = "💼 알바 공고 · 근무 선택"
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if p.goal then
		local g = p.goal
		local card = U.card(scroll, { LayoutOrder = nextOrder(), BackgroundColor3 = Color3.fromRGB(30, 26, 54) })
		U.list(card, 4)
		line(card, string.format("🎯 목표: %s · %s", g.name or "", U.won(g.price or 0)), { Font = U.BOLD })
		U.bar(card, 6).set(g.progress or 0, C.gold)
		line(card, string.format("모은 돈 %s · 남은 %s%s", U.won(g.have or 0), U.won(g.left or 0), if g.shifts then string.format(" · 약 %d번 더 근무", g.shifts) else ""), { TextSize = 12, TextColor3 = C.sub })
	end
	for _, job in p.postings or {} do
		local j = job
		local card = U.card(scroll, { LayoutOrder = nextOrder() })
		U.list(card, 5)
		line(card, string.format("%s %s · %s", j.icon or "", j.title or j.jobId, j.place or ""), { Font = U.BOLD, TextSize = 16 })
		line(card, string.format("Lv.%d %s · %s · 기본급 %s/분", j.level or 1, j.rank or "", j.levelTitle or "", U.won(j.rate or 0)), { TextSize = 13, TextColor3 = C.cyan })
		U.bar(card, 5).set(j.xpProgress or 0, C.violet)
		line(card, j.duty or "", { TextSize = 12, TextColor3 = C.sub })
		line(card, j.perf or "", { TextSize = 12, TextColor3 = C.sub })
		if j.nextUnlocks and #j.nextUnlocks > 0 then
			line(card, "다음 레벨: " .. table.concat(j.nextUnlocks, " · "), { TextSize = 12, TextColor3 = C.gold })
		end
		if not j.ready then
			line(card, "🚧 준비 중인 근무처 (휴대폰 알바 앱의 기존 근무로 일할 수 있어요)", { TextSize = 12, TextColor3 = C.faint })
		elseif not j.canApply then
			line(card, "🔒 " .. (j.requires or "숙련도가 더 필요해요"), { TextSize = 13, TextColor3 = C.orange })
		elseif not j.applied then
			U.button(card, "📝 지원하기", function()
				send({ op = "apply", job = j.jobId })
			end, { BackgroundColor3 = Color3.fromRGB(26, 92, 110) })
		else
			local row = U.frame(card, { Size = UDim2.new(1, 0, 0, 46) })
			U.list(row, 6, true)
			local n = #(j.lengths or {})
			for _, l in j.lengths or {} do
				local len = l
				U.button(row, string.format("%s %d분\n~%s", len.label, math.floor(len.seconds / 60), U.won(len.base)), function()
					selectedLength[j.jobId] = len.id
					send({ op = "start", job = j.jobId, length = len.id })
					panel.Visible = false
				end, { Size = UDim2.new(1 / math.max(1, n), -6, 1, 0), TextSize = 13, BackgroundColor3 = if (p.length == len.id) then Color3.fromRGB(26, 92, 110) else C.card2 })
			end
		end
	end
	if p.goals and #p.goals > 0 then
		local card = U.card(scroll, { LayoutOrder = nextOrder() })
		U.list(card, 4)
		line(card, "🎯 목표 정하기 (정산 때 진행률을 보여 줘요)", { Font = U.BOLD, TextSize = 14 })
		for _, g in p.goals do
			local gg = g
			U.button(card, string.format("%s%s · %s", if gg.selected then "✅ " else "", gg.name, U.won(gg.price)), function()
				send({ op = "goal", index = if gg.selected then 0 else gg.index })
			end, { TextSize = 13, Size = UDim2.new(1, 0, 0, 40) })
		end
	end
	if p.onShift then
		line(scroll, "지금 근무 중이에요 · 화면의 작업 패널을 확인하세요", { TextColor3 = C.gold, LayoutOrder = nextOrder() })
	end
end

-------------------------------------------------------------------------------------------------
-- toasts
-------------------------------------------------------------------------------------------------
local toastBox = U.frame(gui, { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.new(0.5, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 8 })
U.make("UISizeConstraint", { MaxSize = Vector2.new(520, 400), MinSize = Vector2.new(260, 0) }, toastBox)
U.list(toastBox, 4, false, Enum.HorizontalAlignment.Center)
local toastSerial = 0

local function toast(p: any)
	toastSerial += 1
	local kids = 0
	for _, c in toastBox:GetChildren() do
		if c:IsA("Frame") then
			kids += 1
		end
	end
	if kids >= 4 then
		for _, c in toastBox:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
	local f = U.frame(toastBox, { BackgroundColor3 = U.KIND_COLOR[p.kind or "info"] or U.KIND_COLOR.info, BackgroundTransparency = 0.08, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = toastSerial, ZIndex = 8 })
	U.corner(f, 10)
	U.pad(f, 10, 10, 6, 6)
	local text = tostring(p.text or "")
	if p.satisfaction then
		text ..= string.format("  · 만족도 %d", p.satisfaction)
	end
	U.text(f, { Text = text, Font = U.BOLD, TextSize = 14, ZIndex = 8, TextXAlignment = Enum.TextXAlignment.Center })
	if p.kind == "bad" or p.kind == "warn" then
		feedback("error")
	elseif p.kind == "reward" then
		feedback("money")
	elseif p.kind == "call" or p.kind == "order" then
		feedback("notify")
	end
	task.delay(if p.kind == "reward" or p.kind == "bad" then 4.5 else 3.5, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- modals: level-up, end prompt, 정산서
-------------------------------------------------------------------------------------------------
local modal = U.frame(gui, { Name = "Modal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false, ZIndex = 20, Active = true })
local sheet = U.frame(modal, { Name = "Sheet", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.82, 0), BackgroundColor3 = C.bg, BackgroundTransparency = 0.02, ZIndex = 21 })
U.make("UISizeConstraint", { MaxSize = Vector2.new(520, 720), MinSize = Vector2.new(280, 220) }, sheet)
U.corner(sheet, 18)
U.stroke(sheet, C.gold, 0.6)
local sheetScroll = U.make("ScrollingFrame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 22 }, sheet)
U.list(sheetScroll, 6)
local modalQueue: { () -> () } = {}

local function closeModal()
	modal.Visible = false
	local nxt = table.remove(modalQueue, 1)
	if nxt then
		nxt()
	end
end

local function openModal(build: () -> ())
	if modal.Visible then
		table.insert(modalQueue, function()
			openModal(build)
		end)
		return
	end
	U.clear(sheetScroll)
	build()
	modal.Visible = true
	if K and type(K.pop) == "function" then
		pcall(K.pop, sheet)
	end
end

local function mline(text: string, props: any?): TextLabel
	local pr = props or {}
	pr.Text = text
	pr.ZIndex = 23
	return U.text(sheetScroll, pr)
end

local function mbutton(text: string, fn: () -> (), color: Color3?)
	local b = U.button(sheetScroll, text, fn, { ZIndex = 23, BackgroundColor3 = color or C.card2 })
	return b
end

local function showLevelUp(p: any)
	feedback("success")
	openModal(function()
		mline("🎉 숙련도 레벨 업!", { Font = U.BOLD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.gold })
		mline(string.format("Lv.%d · %s", p.level or 0, p.title or ""), { Font = U.BOLD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center })
		for _, u in p.unlocks or {} do
			mline("✨ " .. u, { TextSize = 15 })
		end
		mbutton("좋아요!", closeModal, Color3.fromRGB(26, 92, 110))
	end)
end

local function showEndPrompt(p: any)
	openModal(function()
		mline(if p.early then "🏁 지금 퇴근할까요?" else "🏁 근무 완료!", { Font = U.BOLD, TextSize = 20 })
		mline(p.text or "", { TextSize = 14, TextColor3 = C.sub })
		mbutton(if p.early then "중도 퇴근 · 정산" else "정산하고 퇴근", function()
			closeModal()
			send({ op = "end", reason = if p.early then "early" else "done" })
		end, Color3.fromRGB(110, 40, 50))
		mbutton("계속 일하기", closeModal)
	end)
end

local function showSettle(p: any)
	feedback("money")
	openModal(function()
		mline(string.format("%s %s 정산서", p.icon or "💼", p.title or "근무"), { Font = U.BOLD, TextSize = 20 })
		mline(string.format("%s · %s · 근무 %s", p.place or "", p.reason or "", U.clock(p.worked or 0)), { TextSize = 13, TextColor3 = C.sub })
		for _, l in p.lines or {} do
			local row = U.frame(sheetScroll, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 23 })
			U.text(row, { Text = l.label .. (if l.note then "\n" .. l.note else ""), TextSize = 14, Size = UDim2.new(0.62, 0, 0, 18), ZIndex = 23 })
			U.text(row, { Text = U.won(l.amount), TextSize = 15, Font = U.BOLD, Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.38, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if l.amount < 0 then C.red else C.text, ZIndex = 23 })
		end
		mline(string.format("합계 %s%s", U.won(p.total or 0), if (p.paid or 0) > 0 then " · 통장 입금 완료" else ""), { Font = U.BOLD, TextSize = 20, TextColor3 = C.gold })
		local stats = {}
		table.insert(stats, string.format("완료 %d건", p.orders or 0))
		if p.accuracy then
			table.insert(stats, string.format("정확도 %d%%", p.accuracy))
		end
		if p.satisfaction then
			table.insert(stats, string.format("만족도 %d", p.satisfaction))
		end
		if (p.walkouts or 0) > 0 then
			table.insert(stats, string.format("떠난 손님 %d", p.walkouts))
		end
		if (p.remakes or 0) > 0 then
			table.insert(stats, string.format("다시 만들기 %d", p.remakes))
		end
		if (p.mistakes or 0) > 0 then
			table.insert(stats, string.format("실수 %d", p.mistakes))
		end
		if (p.tasks or 0) > 0 then
			table.insert(stats, string.format("작업 %d건", p.tasks))
		end
		mline(table.concat(stats, " · "), { TextSize = 13, TextColor3 = C.sub })
		mline(string.format("숙련도 +%d XP · Lv.%d %s · %s", p.xpGain or 0, p.level or 1, p.rank or "", p.levelTitle or ""), { TextSize = 14, TextColor3 = C.violet })
		U.bar(sheetScroll, 6, { ZIndex = 23 }).set(p.xpProgress or 0, C.violet)
		if p.nextUnlocks and #p.nextUnlocks > 0 then
			mline("다음 레벨: " .. table.concat(p.nextUnlocks, " · "), { TextSize = 12, TextColor3 = C.gold })
		end
		if p.goal then
			mline(string.format("🎯 %s · %d%% (+%s)%s", p.goal.name or "", math.floor((p.goal.progress or 0) * 100), U.won(p.goal.gained or 0), if p.goal.shifts then string.format(" · 약 %d번 더", p.goal.shifts) else ""), { TextSize = 13 })
			U.bar(sheetScroll, 6, { ZIndex = 23 }).set(p.goal.progress or 0, C.gold)
		end
		mbutton("확인", closeModal, Color3.fromRGB(26, 92, 110))
		mbutton("공고 다시 보기", function()
			closeModal()
			panel.Visible = true
			send({ op = "board" })
		end)
	end)
end

-------------------------------------------------------------------------------------------------
-- HUD + marker
-------------------------------------------------------------------------------------------------
local hud = Hud.new(gui, send)
local marker = Marker.new()
hud.onEndRequest = function(p: any)
	showEndPrompt({ early = not p.canFinish, text = if p.canFinish then "마감까지 끝냈어요. 정산하고 퇴근할까요?" else "지금 퇴근하면 근무한 시간의 기본급과 이미 끝낸 일의 성과급만 받아요. 마감 수당은 없어요." })
end

local function onState(p: any)
	lastState = p
	toggle.Text = (p.icon or "💼") .. " 근무 중"
	hud:update(p)
	local h = p.hint
	if h and h.pos and typeof(h.pos) == "Vector3" then
		marker:set(h.pos, h.label or "다음 할 일")
	else
		marker:set(nil)
	end
end

local function offShift()
	lastState = nil
	hud:show(false)
	marker:set(nil)
	toggle.Text = "💼 알바"
end

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		send({ op = "board" })
	end
end)

remote.OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if p.op == "board" then
			showBoard(p)
		elseif p.op == "state" then
			onState(p)
		elseif p.op == "settle" then
			offShift()
			showSettle(p)
		elseif p.op == "closed" then
			offShift()
			send({ op = "board" })
		elseif p.op == "toast" then
			toast(p)
		elseif p.op == "levelup" then
			showLevelUp(p)
		elseif p.op == "endPrompt" then
			showEndPrompt(p)
		end
	end)
	if not ok then
		warn("[GwangalliWork] client " .. tostring(p.op) .. ": " .. tostring(err))
	end
end)

-------------------------------------------------------------------------------------------------
-- test hook
-------------------------------------------------------------------------------------------------
local apiQueue: { any } = {}
local function setupApi()
	if player:FindFirstChild("GwangalliWorkAPI") then
		return
	end
	local api = Instance.new("BindableFunction")
	api.Name = "GwangalliWorkAPI"
	api.OnInvoke = function(method: string, a: any, b: any): any
		if method == "ui" then
			return string.format("board=%s hud=%s modal=%s marker=%s\n%s", tostring(panel.Visible), tostring(hud.root.Visible), tostring(modal.Visible), tostring(marker.bb.Enabled), hud:summary())
		elseif method == "send" then
			table.insert(apiQueue, a)
			return true
		elseif method == "board" then
			panel.Visible = a == true
			return true
		elseif method == "camera" then
			table.insert(apiQueue, { camera = a, target = b })
			return true
		elseif method == "teleport" then
			table.insert(apiQueue, { teleport = a, look = b })
			return true
		elseif method == "closeModal" then
			table.insert(apiQueue, "closeModal")
			return true
		end
		return nil
	end
	api.Parent = player
end
if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
	setupApi()
end
workspace:GetAttributeChangedSignal("GwangalliStreetLifeDebug"):Connect(function()
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		setupApi()
	end
end)
task.spawn(function()
	while true do
		task.wait(0.2)
		local item = table.remove(apiQueue, 1)
		if item == "closeModal" then
			closeModal()
		elseif type(item) == "table" and item.camera ~= nil then
			local cam = workspace.CurrentCamera
			if cam then
				pcall(function()
					if typeof(item.camera) == "Vector3" and typeof(item.target) == "Vector3" then
						cam.CameraType = Enum.CameraType.Scriptable
						cam.CFrame = CFrame.lookAt(item.camera, item.target)
					else
						cam.CameraType = Enum.CameraType.Custom
					end
				end)
			end
		elseif type(item) == "table" and item.teleport then
			local char = player.Character
			if char then
				pcall(function()
					local pos = item.teleport
					char:PivotTo(if typeof(item.look) == "Vector3" then CFrame.lookAt(pos, pos + item.look) else CFrame.new(pos))
				end)
			end
		elseif type(item) == "table" then
			remote:FireServer(item)
		end
	end
end)

send({ op = "board" })
