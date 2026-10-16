-- GwangalliClinic/Screens (client): the clinic's world displays, live from the shared State.
--   call   lobby LED (map 1F.Lobby.LEDScreen): 🔔 last call (number → 창구 / 진료실 / 약국) + serving ticker
--   wait   waiting-room TV (map 1F.WaitingRoom.LEDScreen, 2F lounge) and the interior's hanging monitor:
--          진료 대기 현황 (masked names, 진료과, 상태) + counts
--   rx     pharmacy PrescriptionScreen: 조제 중 / 조제 완료 numbers
--   door   the interior's monitor by the consult door: 진료 중 / 다음 순서
--   callno the interior's "호출번호" board: "042 → 1번 창구"
--   kiosk  the interior's kiosk screen: 대기 n명 · 내 번호
-- SurfaceGuis live in PlayerGui (Adornee = the part), never under map parts. The screen's own gui
-- (map SignGui / the interior's "Gw"..name) is switched off locally while ours covers it. A 딩동 chime
-- plays for every call while the player is inside the clinic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Screens = {}

local ctx: any
local S: any
local C: any
local Ui: any
local player = Players.LocalPlayer

local folder: Folder
local screens: { [BasePart]: any } = {}
local board: any = {}
local call: any = nil
local rx: any = { cooking = {}, ready = {} }
local lastSeq = -1
local flashUntil = 0

local LED = Color3.fromRGB(255, 96, 40)
local LED2 = Color3.fromRGB(255, 196, 70)
local LEDBG = Color3.fromRGB(8, 10, 12)

local function new(class: string, props: any, parent: Instance?): any
	return Ui.new(class, props, parent)
end

local FACE_NORMALS = {
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
}

local function faceToward(part: BasePart, viewer: Vector3?): Enum.NormalId
	if not viewer then
		return Enum.NormalId.Front
	end
	local dir = viewer - part.Position
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for id, n in FACE_NORMALS do
		if id ~= Enum.NormalId.Top and id ~= Enum.NormalId.Bottom then
			local wn = part.CFrame:VectorToWorldSpace(n)
			local d = wn:Dot(dir)
			if d > bestDot then
				best, bestDot = id, d
			end
		end
	end
	return best
end

local function faceSize(part: BasePart, face: Enum.NormalId): (number, number)
	local s = part.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return s.X, s.Z
	end
	return s.X, s.Y
end

-- switch the part's own SurfaceGuis off (kept off while we own the screen)
local function silence(part: BasePart, rec: any)
	local face: Enum.NormalId? = nil
	for _, g in part:GetChildren() do
		if g:IsA("SurfaceGui") then
			face = face or g.Face
			g.Enabled = false
			table.insert(rec.conns, g:GetPropertyChangedSignal("Enabled"):Connect(function()
				if g.Enabled and screens[part] then
					g.Enabled = false
				end
			end))
			table.insert(rec.silenced, g)
		end
	end
	return face
end

local function label(parent: Instance, props: any): TextLabel
	local p = { BackgroundTransparency = 1, Font = Ui.F.black, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, TextWrapped = true, Size = UDim2.fromScale(1, 1) }
	for k, v in props do
		p[k] = v
	end
	return new("TextLabel", p, parent)
end

-------------------------------------------------------------------------------------------------
-- renderers (build once, update texts)
-------------------------------------------------------------------------------------------------
local BUILD: { [string]: (Frame, any) -> () } = {}
local RENDER: { [string]: (any) -> () } = {}

local function servingLine(): string
	local sv = board.serving or {}
	local function n(x: any): string
		return if x then S.ticket(x) else "---"
	end
	local counts = board.counts or {}
	return string.format("창구1 %s   창구2 %s   진료실1 %s   대기 %d명", n(sv.w1), n(sv.w2), n(sv.c1), (counts.desk or 0) + (counts.consult or 0))
end

local function callTarget(c: any): string
	if not c then
		return ""
	end
	if c.to == "desk" then
		return string.format("%d번 창구", c.win or 1)
	elseif c.to == "consult" then
		return "진료실 1"
	elseif c.to == "pharm" then
		return "약국"
	end
	return ""
end

BUILD.call = function(root, rec)
	root.BackgroundColor3 = LEDBG
	local top = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.72) }, root)
	rec.bell = label(top, { Text = "🔔 호출", TextColor3 = LED2, Size = UDim2.fromScale(0.22, 0.5), Position = UDim2.fromScale(0.02, 0.08) })
	rec.num = label(top, { Text = "---", Font = Ui.F.mono, TextColor3 = LED, Size = UDim2.fromScale(0.3, 0.9), Position = UDim2.fromScale(0.03, 0.06), TextXAlignment = Enum.TextXAlignment.Left })
	rec.num.Position = UDim2.fromScale(0.25, 0.05)
	rec.to = label(top, { Text = "접수 후 잠시만 기다려 주세요", TextColor3 = LED2, Size = UDim2.fromScale(0.42, 0.62), Position = UDim2.fromScale(0.56, 0.2), TextXAlignment = Enum.TextXAlignment.Left })
	rec.ticker = label(root, { Text = "", Font = Ui.F.bold, TextColor3 = Color3.fromRGB(120, 255, 190), Size = UDim2.fromScale(0.96, 0.22), Position = UDim2.fromScale(0.02, 0.75), TextXAlignment = Enum.TextXAlignment.Left })
	rec.bell.Size = UDim2.fromScale(0.21, 0.46)
	rec.bell.Position = UDim2.fromScale(0.02, 0.27)
end
RENDER.call = function(rec)
	local c = call
	if c then
		rec.num.Text = S.ticket(c.n)
		rec.to.Text = string.format("%s%s", if c.name and c.name ~= "" then c.name .. "님 → " else "→ ", callTarget(c))
	else
		rec.num.Text = if board.last then S.ticket(board.last) else "---"
		rec.to.Text = "접수 후 잠시만 기다려 주세요"
	end
	rec.ticker.Text = servingLine()
end

BUILD.callno = function(root, rec)
	root.BackgroundColor3 = LEDBG
	rec.num = label(root, { Text = "---", Font = Ui.F.mono, TextColor3 = LED, Size = UDim2.fromScale(0.96, 0.9), Position = UDim2.fromScale(0.02, 0.05) })
end
RENDER.callno = function(rec)
	local c = call
	if c and c.to == "desk" then
		rec.num.Text = string.format("%s → %d번 창구", S.ticket(c.n), c.win or 1)
	elseif c then
		rec.num.Text = string.format("%s → %s", S.ticket(c.n), callTarget(c))
	else
		rec.num.Text = "--- 대기"
	end
end

BUILD.wait = function(root, rec)
	root.BackgroundColor3 = Color3.fromRGB(10, 46, 52)
	local head = new("Frame", { BackgroundColor3 = Color3.fromRGB(15, 163, 163), BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.16) }, root)
	rec.title = label(head, { Text = "진료 대기 현황", Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.02, 0.1), TextXAlignment = Enum.TextXAlignment.Left })
	rec.clock = label(head, { Text = "", Font = Ui.F.mono, Size = UDim2.fromScale(0.3, 0.7), Position = UDim2.fromScale(0.68, 0.15), TextXAlignment = Enum.TextXAlignment.Right })
	local list = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.64, 0.8), Position = UDim2.fromScale(0.02, 0.18) }, root)
	rec.rows = {}
	for i = 1, 6 do
		local r = new("Frame", { BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(14, 58, 64) else Color3.fromRGB(12, 52, 58), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1 / 6, -3), Position = UDim2.new(0, 0, (i - 1) / 6, 0) }, list)
		local n = label(r, { Text = "", Font = Ui.F.mono, TextColor3 = LED2, Size = UDim2.fromScale(0.18, 0.8), Position = UDim2.fromScale(0.02, 0.1), TextXAlignment = Enum.TextXAlignment.Left })
		local nm = label(r, { Text = "", Size = UDim2.fromScale(0.3, 0.8), Position = UDim2.fromScale(0.2, 0.1), TextXAlignment = Enum.TextXAlignment.Left })
		local st = label(r, { Text = "", Font = Ui.F.bold, TextColor3 = Color3.fromRGB(150, 240, 220), Size = UDim2.fromScale(0.46, 0.7), Position = UDim2.fromScale(0.52, 0.15), TextXAlignment = Enum.TextXAlignment.Right })
		rec.rows[i] = { frame = r, n = n, name = nm, st = st }
	end
	local side = new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 34, 38), BorderSizePixel = 0, Size = UDim2.fromScale(0.31, 0.8), Position = UDim2.fromScale(0.675, 0.18) }, root)
	rec.side = label(side, { Text = "", Font = Ui.F.bold, Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
end
RENDER.wait = function(rec)
	rec.title.Text = string.format("진료 대기 현황 · 진료실 1 내과 %s", board.doctor or C.Doctor.name)
	rec.clock.Text = S.clockText(S.clock())
	local waiting = board.waiting or {}
	for i, row in rec.rows do
		local w = waiting[i]
		if w then
			row.frame.Visible = true
			row.n.Text = S.ticket(w.n)
			row.name.Text = w.name or ""
			local dept = w.dept and C.Depts[w.dept] and C.Depts[w.dept].name or ""
			row.st.Text = if dept ~= "" then string.format("%s · %s", dept, w.st or "") else (w.st or "")
			row.st.TextColor3 = if w.st == "진료 중" then LED else Color3.fromRGB(150, 240, 220)
		else
			row.frame.Visible = i == 1
			row.n.Text = ""
			row.name.Text = if i == 1 then "대기 환자 없음" else ""
			row.st.Text = ""
		end
	end
	local c = board.counts or {}
	rec.side.Text = string.format("접수 대기  %d명\n진료 대기  %d명\n주사실  %d명\n조제 중  %d건\n\n오늘도 건강하세요 🌿", c.desk or 0, c.consult or 0, c.treat or 0, c.pharm or 0)
end

BUILD.rx = function(root, rec)
	root.BackgroundColor3 = Color3.fromRGB(10, 40, 30)
	rec.title = label(root, { Text = "원내 약국 · 처방 접수", Size = UDim2.fromScale(0.96, 0.24), Position = UDim2.fromScale(0.02, 0.03) })
	rec.cooking = label(root, { Text = "", Font = Ui.F.bold, TextColor3 = LED2, Size = UDim2.fromScale(0.96, 0.32), Position = UDim2.fromScale(0.02, 0.3), TextXAlignment = Enum.TextXAlignment.Left })
	rec.ready = label(root, { Text = "", Font = Ui.F.bold, TextColor3 = Color3.fromRGB(110, 255, 160), Size = UDim2.fromScale(0.96, 0.32), Position = UDim2.fromScale(0.02, 0.64), TextXAlignment = Enum.TextXAlignment.Left })
end
local function nums(list: any, max: number): string
	local out = {}
	for i, n in list or {} do
		if i > max then
			break
		end
		table.insert(out, S.ticket(n))
	end
	return if #out > 0 then table.concat(out, "  ") else "-"
end
RENDER.rx = function(rec)
	rec.cooking.Text = "조제 중   " .. nums(rx.cooking, 5)
	rec.ready.Text = "조제 완료 " .. nums(rx.ready, 5) .. (if #(rx.ready or {}) > 0 then "  · 받아 가세요" else "")
end

BUILD.door = function(root, rec)
	root.BackgroundColor3 = Color3.fromRGB(12, 30, 48)
	rec.a = label(root, { Text = "진료실 1 · 내과", Size = UDim2.fromScale(0.96, 0.28), Position = UDim2.fromScale(0.02, 0.03) })
	rec.b = label(root, { Text = "", Font = Ui.F.mono, TextColor3 = LED, Size = UDim2.fromScale(0.96, 0.34), Position = UDim2.fromScale(0.02, 0.32) })
	rec.c = label(root, { Text = "", Font = Ui.F.bold, TextColor3 = LED2, Size = UDim2.fromScale(0.96, 0.28), Position = UDim2.fromScale(0.02, 0.68) })
end
RENDER.door = function(rec)
	local sv = board.serving or {}
	rec.b.Text = if sv.c1 then string.format("진료 중 %s", S.ticket(sv.c1)) else "진료 대기"
	local nextOne = nil
	for _, w in board.waiting or {} do
		if w.st ~= "진료 중" and w.st ~= "접수 대기" then
			nextOne = w
			break
		end
	end
	rec.c.Text = if nextOne then string.format("다음 %s %s", S.ticket(nextOne.n), nextOne.name or "") else "다음 순서 없음"
end

BUILD.kiosk = function(root, rec)
	root.BackgroundColor3 = Color3.fromRGB(20, 60, 70)
	rec.a = label(root, { Text = "무인 접수 · 수납", Size = UDim2.fromScale(0.94, 0.2), Position = UDim2.fromScale(0.03, 0.04) })
	rec.b = label(root, { Text = "", Font = Ui.F.bold, TextColor3 = Color3.fromRGB(236, 248, 246), Size = UDim2.fromScale(0.94, 0.46), Position = UDim2.fromScale(0.03, 0.28) })
	rec.c = label(root, { Text = "번호표 뽑기 ▶", TextColor3 = Color3.fromRGB(120, 255, 210), Size = UDim2.fromScale(0.94, 0.2), Position = UDim2.fromScale(0.03, 0.76) })
end
RENDER.kiosk = function(rec)
	local c = board.counts or {}
	local v = ctx.visit
	if v and v.ticket then
		rec.b.Text = string.format("내 번호 %s\n%s", S.ticket(v.ticket), v.stepLabel or "")
	else
		rec.b.Text = string.format("대기 %d명\n약 %d분", (c.desk or 0) + (c.consult or 0), math.max(1, math.ceil(((c.desk or 0) * 5 + (c.consult or 0) * 8) / 60)))
	end
end

-------------------------------------------------------------------------------------------------
-- registry
-------------------------------------------------------------------------------------------------
local function unregister(part: BasePart)
	local rec = screens[part]
	if not rec then
		return
	end
	screens[part] = nil
	for _, c in rec.conns do
		c:Disconnect()
	end
	for _, g in rec.silenced do
		if g.Parent then
			g.Enabled = true
		end
	end
	if rec.gui then
		rec.gui:Destroy()
	end
end

local function register(part: BasePart, kind: string, viewer: Vector3?)
	if screens[part] or not BUILD[kind] then
		return
	end
	local rec: any = { part = part, kind = kind, conns = {}, silenced = {} }
	local face = silence(part, rec) or faceToward(part, viewer)
	local w, h = faceSize(part, face)
	local px = math.clamp(math.floor(900 / math.max(w, h)), 30, 90)
	local gui = new("SurfaceGui", {
		Name = "Clinic_" .. kind .. "_" .. part.Name,
		Face = face,
		Adornee = part,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = px,
		LightInfluence = 0,
		Brightness = 1.6,
		MaxDistance = 90,
		ZOffset = 2,
		ClipsDescendants = true,
		ResetOnSpawn = false,
	}, nil)
	pcall(function()
		(gui :: any).AlwaysOnTop = false
	end)
	local root = new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, gui)
	rec.root = root
	BUILD[kind](root, rec)
	gui.Parent = folder
	rec.gui = gui
	screens[part] = rec
	table.insert(rec.conns, part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			unregister(part)
		end
	end))
	pcall(RENDER[kind], rec)
end

local function renderAll()
	for _, rec in screens do
		local ok, err = pcall(RENDER[rec.kind], rec)
		if not ok then
			warn("[GwangalliClinic] screen", rec.kind, err)
		end
	end
end
Screens.renderAll = renderAll

local function venue(): Instance?
	local cur: Instance? = workspace
	for _, n in C.Venue.Path do
		cur = cur and cur:FindFirstChild(n)
	end
	return cur
end

local function byPath(root: Instance, path: string): Instance?
	local cur: Instance? = root
	for seg in string.gmatch(path, "[^/]+") do
		cur = cur and cur:FindFirstChild(seg)
	end
	return cur
end

local function scanMap()
	local v = venue()
	if not v then
		return
	end
	for _, spec in S.Sites.SCREENS do
		local p = byPath(v, spec.path)
		if p and p:IsA("BasePart") and not screens[p] then
			register(p, spec.kind, spec.viewer)
		end
	end
end

local function considerInterior(d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	local attr = d:GetAttribute(C.Interior.ScreenAttribute)
	local kind = if type(attr) == "string" then attr else C.Interior.Screens[d.Name]
	if kind and BUILD[kind] then
		-- the interior builds its text parts first and their SurfaceGui right after: wait a frame
		task.defer(function()
			if d.Parent then
				register(d, kind, nil)
			end
		end)
	end
end

local function decode()
	local st = ctx.state
	board = S.decode(st:GetAttribute("Board")) or board
	rx = S.decode(st:GetAttribute("Rx")) or rx
	local c = S.decode(st:GetAttribute("Call"))
	if c then
		call = c
	end
end

local function inClinic(): boolean
	local p = ctx.rootPos()
	local a = ctx.anchor("Kiosk")
	if not p or not a then
		return false
	end
	local d = p - a.Position
	return math.abs(d.X) < 90 and math.abs(d.Z) < 70 and math.abs(d.Y) < 28
end
Screens.inClinic = inClinic

function Screens.board(): any
	return board
end

function Screens.onVisit(_v: any)
	renderAll()
end

function Screens.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(S.NAMES.Screens)
	if old then
		old:Destroy()
	end
	local function makeFolder()
		folder = Instance.new("Folder")
		folder.Name = S.NAMES.Screens
		folder.Parent = pg
	end
	makeFolder()
	-- a respawn may clear PlayerGui: rebuild every overlay
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if not folder.Parent then
			local parts = {}
			for part, rec in screens do
				table.insert(parts, { part = part, kind = rec.kind })
			end
			for _, e in parts do
				unregister(e.part)
			end
			makeFolder()
			for _, e in parts do
				if e.part:IsDescendantOf(workspace) then
					register(e.part, e.kind, nil)
				end
			end
		end
	end)
	decode()
	local st = ctx.state
	st:GetAttributeChangedSignal("Board"):Connect(function()
		decode()
		renderAll()
	end)
	st:GetAttributeChangedSignal("Rx"):Connect(function()
		decode()
		renderAll()
	end)
	st:GetAttributeChangedSignal("Call"):Connect(function()
		decode()
		if call and call.seq ~= lastSeq then
			local first = lastSeq == -1
			lastSeq = call.seq
			flashUntil = os.clock() + 2.4
			if not first and inClinic() then
				Ui.ding()
			end
		end
		renderAll()
	end)
	do
		local c0 = S.decode(st:GetAttribute("Call"))
		lastSeq = c0 and c0.seq or 0
	end
	-- interior parts (client-only decor) come and go with streaming
	task.spawn(function()
		local f = workspace:WaitForChild(C.Interior.Folder, 600)
		if not f then
			return
		end
		for _, d in f:GetDescendants() do
			considerInterior(d)
		end
		f.DescendantAdded:Connect(considerInterior)
	end)
	-- map screens (stream in later)
	task.spawn(function()
		while true do
			pcall(scanMap)
			task.wait(4)
		end
	end)
	-- LED flash on a new call + the TV clock
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		local flashing = os.clock() < flashUntil
		for _, rec in screens do
			if rec.kind == "call" or rec.kind == "callno" then
				local on = flashing and (math.floor(os.clock() * 4) % 2 == 0)
				rec.num.TextColor3 = if on then Color3.new(1, 1, 1) else LED
			end
		end
		if acc >= 15 then
			acc = 0
			renderAll()
		end
	end)
end

return Screens
