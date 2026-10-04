-- GwangalliVenues/Gym: 광안 휘트니스 24 on the client (owner: venues_detail).
--   * session HUD (compact card in the bottom-centre band, never over the screen centre): machine,
--     set n/N, rep counter, rhythm meter + '리듬' tap button (form bonus <= V.GYM.formBonus, sent once
--     per set as gymForm), live 근력 / 체력 bars with gain pops, '그만' (gymStop)
--   * own character: the run track on the treadmill (replicated through the Animator); the other
--     styles are pose loops from the shared act driver (Common: GwVenueAct = gym:<style>)
--   * equipment motion for EVERY active station in range (attribute InUse): barbells, weight stacks,
--     rower seat, bike cranks — local CFrame writes, restored when the station frees up
--   * routine chip (오늘의 루틴, trainer quest) under the money chip
-- Events: gymStart / gymSet / gymEnd / routine.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Gym = {}

local C: any
local K: any
local V: any
local Anim: any

type Session = { part: BasePart?, style: string, machine: string, sets: number, setSeconds: number, rest: number, period: number, info: boolean, set: number, setStart: number, perfect: number, good: number, taps: number, sentForm: boolean, runTrack: any }
local session: Session? = nil
local hud: any = nil

-------------------------------------------------------------------------------------------------
-- HUD
-------------------------------------------------------------------------------------------------
local function stat(name: string): number
	return tonumber(C.player:GetAttribute(name)) or 0
end

local function buildHud()
	if hud then
		return hud
	end
	local s = 1
	pcall(function()
		s = C.Layout.metrics().s or 1
	end)
	local card = K.make("Frame", { Name = "GymHud", BackgroundColor3 = K.Color.glass, BackgroundTransparency = 0.12, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 30 }, C.gui)
	K.corner(card, K.Radius.lg)
	K.stroke(card, K.Color.cyan, 1, 0.7)
	local title = K.text(card, { Name = "Title", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.bodySm, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31 })
	local setPill = K.text(card, { Name = "SetPill", Position = UDim2.new(1, -140, 0, 6), Size = UDim2.fromOffset(70, 20), Text = "", Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.gold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 31 })
	local stop = K.Button(card, { name = "GymStop", text = "그만", style = "secondary", size = UDim2.fromOffset(60, 44), position = UDim2.new(1, -66, 0, 4), zIndex = 32, textSize = 13 })
	local reps = K.text(card, { Name = "Reps", Position = UDim2.fromOffset(12, 30), Size = UDim2.fromOffset(84, 40), Text = "0/8", Font = K.Font.heavy, TextSize = 30, ZIndex = 31 })
	local repLbl = K.text(card, { Name = "RepLabel", Position = UDim2.fromOffset(12, 68), Size = UDim2.fromOffset(84, 14), Text = "REPS", Font = K.Font.bold, TextSize = K.Type.micro, TextColor3 = K.Color.sub, ZIndex = 31 })
	-- rhythm meter
	local meter = K.frame(card, { Name = "Meter", Position = UDim2.fromOffset(100, 36), Size = UDim2.new(1, -184, 0, 14), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, ZIndex = 31 })
	K.corner(meter, UDim.new(0.5, 0))
	local sweet = K.frame(meter, { Name = "Sweet", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.24, 1), BackgroundTransparency = 0.25, BackgroundColor3 = K.Color.green, ZIndex = 32 })
	K.corner(sweet, UDim.new(0.5, 0))
	local marker = K.frame(meter, { Name = "Marker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(6, 22), BackgroundTransparency = 0, BackgroundColor3 = K.Color.text, ZIndex = 33 })
	K.corner(marker, UDim.new(0.5, 0))
	-- stat bars
	local function bar(y: number, icon: string, color: Color3)
		local l = K.text(card, { Name = "StatLabel", Position = UDim2.fromOffset(100, y), Size = UDim2.new(1, -184, 0, 14), Text = icon, Font = K.Font.bold, TextSize = K.Type.micro, TextColor3 = K.Color.sub, ZIndex = 31 })
		local b = K.ProgressBar(card, { height = 5, color = color })
		b.frame.Position = UDim2.fromOffset(100, y + 15)
		b.frame.Size = UDim2.new(1, -184, 0, 5)
		b.frame.ZIndex = 31
		b.fill.ZIndex = 32
		return l, b
	end
	local strL, strB = bar(56, "💪 근력", K.Color.magenta)
	local staL, staB = bar(78, "🔋 체력", K.Color.green)
	-- rhythm tap button (round, >= 64 px)
	local tap = K.Button(card, { name = "GymTap", text = "리듬", icon = "💪", style = "primary", size = UDim2.fromOffset(68, 68), position = UDim2.new(1, -76, 0, 44), zIndex = 32, textSize = 12, radius = 34 })
	hud = { card = card, title = title, setPill = setPill, stop = stop, reps = reps, repLbl = repLbl, meter = meter, marker = marker, strL = strL, strB = strB, staL = staL, staB = staB, tap = tap, s = s }
	local function place()
		local ok, r = pcall(C.Layout.rect, "bottomCenter")
		local w, x, yb = 340, C.gui.AbsoluteSize.X / 2, C.gui.AbsoluteSize.Y - 8
		if ok and r then
			w = math.clamp(r.w, 280, 380)
			x = r.x + r.w / 2
			yb = r.y + r.h
		end
		card.Size = UDim2.fromOffset(w, 122)
		card.Position = UDim2.fromOffset(x, yb)
	end
	place()
	pcall(function()
		C.Layout.onChanged(place)
	end)
	stop.Activated:Connect(function()
		C.sound("tap")
		task.spawn(C.request, "gymStop", {})
	end)
	tap.Activated:Connect(function()
		Gym.tap()
	end)
	return hud
end

local function refreshStats(gains: any?)
	if not hud then
		return
	end
	local st, sa = stat("Strength"), stat("Stamina")
	hud.strL.Text = string.format("💪 근력 %d", st)
	hud.staL.Text = string.format("🔋 체력 %d", sa)
	hud.strB.set(st / 100)
	hud.staB.set(sa / 100)
	if gains then
		local parts = {}
		local names = { strength = "근력", stamina = "체력", appearance = "외모" }
		for k, v in gains do
			if names[k] and type(v) == "number" and v > 0 then
				table.insert(parts, string.format("%s +%s", names[k], tostring(v)))
			end
		end
		if #parts > 0 then
			C.pop(hud.card, table.concat(parts, "  "), K.Color.gold, UDim2.new(0.5, 0, 0, -14), 18, 1.4)
		end
	end
end

local function phase(): number
	local s = session
	if not s then
		return 0
	end
	local t = C.serverNow() - (tonumber(C.player:GetAttribute(V.Attr.ActT)) or C.serverNow())
	return (t / s.period) % 1
end

function Gym.tap()
	local s = session
	if not s or s.info or not hud then
		return
	end
	local ph = phase()
	local d = math.abs(ph - 0.5)
	s.taps += 1
	if d < 0.12 then
		s.perfect += 1
		C.sound("ping", 1.5, 0.25)
		C.pop(hud.card, "PERFECT", K.Color.green, UDim2.new(0.5, 0, 0, 8), 20, 0.6)
	elseif d < 0.22 then
		s.good += 1
		C.sound("tap", 1.2, 0.3)
		C.pop(hud.card, "GOOD", K.Color.cyan, UDim2.new(0.5, 0, 0, 8), 18, 0.6)
	else
		C.sound("tap", 0.8, 0.25)
		C.pop(hud.card, "MISS", K.Color.faint, UDim2.new(0.5, 0, 0, 8), 16, 0.5)
	end
end

local function sendForm()
	local s = session
	if not s or s.sentForm or s.info then
		return
	end
	s.sentForm = true
	local reps = math.max(1, math.floor(s.setSeconds / s.period))
	local form = math.clamp((s.perfect + 0.5 * s.good) / reps, 0, 1)
	task.spawn(C.request, "gymForm", { form = form })
end

local function updateHud()
	local s = session
	if not s or not hud then
		return
	end
	local now = os.clock()
	local repsTotal = math.max(1, math.floor(s.setSeconds / s.period))
	local inSet = now - s.setStart
	if s.info then
		hud.reps.Text = string.format("%d%%", math.clamp(math.floor(inSet / s.setSeconds * 100), 0, 100))
		hud.repLbl.Text = "SCAN"
	elseif inSet < 0 then
		hud.reps.Text = "휴식"
		hud.repLbl.Text = string.format("%.1fs", -inSet)
	else
		hud.reps.Text = string.format("%d/%d", math.clamp(math.floor(inSet / s.period), 0, repsTotal), repsTotal)
		hud.repLbl.Text = "REPS"
		if inSet > s.setSeconds - 0.7 then
			sendForm()
		end
	end
	hud.setPill.Text = if s.info then "인바디" else string.format("세트 %d/%d", math.min(s.set, s.sets), s.sets)
	hud.marker.Position = UDim2.fromScale(phase(), 0.5)
end

-------------------------------------------------------------------------------------------------
-- Equipment motion (every active station in range)
-------------------------------------------------------------------------------------------------
type Eq = { part: BasePart, base: CFrame, mode: string, amount: number }
local active: { [Instance]: { eq: { Eq }, style: string, userId: number } } = {}

local function containerOf(st: BasePart): Instance
	local p = st.Parent
	if p and p:IsA("Model") and p ~= workspace then
		return p
	end
	return st
end

local function collect(st: BasePart, style: string): { Eq }
	local out: { Eq } = {}
	local cont = containerOf(st)
	local function add(p: Instance?, mode: string, amount: number)
		if p and p:IsA("BasePart") then
			table.insert(out, { part = p, base = p.CFrame, mode = mode, amount = amount })
		end
	end
	if style == "bench" or style == "squat" then
		local eq = cont:FindFirstChild("Equipment")
		if eq then
			for _, d in eq:GetDescendants() do
				add(d, "up", if style == "bench" then 1.3 else -1.1)
			end
			if eq:IsA("BasePart") then
				add(eq, "up", if style == "bench" then 1.3 else -1.1)
			end
		end
	elseif style == "lat" then
		for _, d in cont:GetDescendants() do
			if d.Name == "WeightStack" then
				add(d, "up", 0.9)
			elseif d.Name == "LatBar" then
				add(d, "up", -1.5)
			end
		end
	elseif style == "legpress" then
		for _, d in cont:GetDescendants() do
			if d.Name == "Plate" or d.Name == "Sled" or d.Name == "Footplate" then
				add(d, "back", 1.2)
			end
		end
	elseif style == "row" then
		for _, d in cont:GetDescendants() do
			if d.Name == "RowerSeat" then
				add(d, "back", 1.6)
			end
		end
	elseif style == "cycle" then
		for _, d in cont:GetDescendants() do
			if d.Name == "Crank" or d.Name == "Flywheel" then
				add(d, "spin", if d.Name == "Crank" then 1 else 2.4)
			end
		end
	elseif style == "curl" then
		local eq = cont:FindFirstChild("Equipment")
		if eq then
			for _, d in eq:GetDescendants() do
				add(d, "hide", 1)
			end
		end
	end
	return out
end

local function restore(rec: any)
	for _, e in rec.eq do
		if e.part.Parent then
			if e.mode == "hide" then
				e.part.LocalTransparencyModifier = 0
			else
				e.part.CFrame = e.base
			end
		end
	end
end

local function stationChanged(st: Instance)
	if not st:IsA("BasePart") then
		return
	end
	local uid = st:GetAttribute(V.Attr.InUse)
	local rec = active[st]
	if type(uid) == "number" and uid ~= 0 then
		if rec and rec.userId == uid then
			return
		end
		if rec then
			restore(rec)
		end
		local style = st:GetAttribute("RepStyle")
		style = if type(style) == "string" then style else "scan"
		active[st] = { eq = collect(st, style), style = style, userId = uid }
	elseif rec then
		restore(rec)
		active[st] = nil
	end
end

local function equipmentStep()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local now = C.serverNow()
	for st, rec in active do
		if not st.Parent then
			active[st] = nil
			continue
		end
		if ((st :: BasePart).Position - camPos).Magnitude > 90 then
			continue
		end
		local pl = Players:GetPlayerByUserId(rec.userId)
		local t0 = pl and tonumber(pl:GetAttribute(V.Attr.ActT)) or now
		local period = (V.STYLE[rec.style] and V.STYLE[rec.style].period) or 1
		local ph = ((now - t0) / period) % 1
		local s = 0.5 - 0.5 * math.cos(ph * 2 * math.pi)
		local look = (st :: BasePart).CFrame.LookVector
		for _, e in rec.eq do
			if not e.part.Parent then
				continue
			end
			if e.mode == "up" then
				e.part.CFrame = e.base + Vector3.new(0, e.amount * s, 0)
			elseif e.mode == "back" then
				e.part.CFrame = e.base - Vector3.new(look.X, 0, look.Z) * (e.amount * s)
			elseif e.mode == "spin" then
				e.part.CFrame = e.base * CFrame.Angles((now - t0) * 6 * e.amount, 0, 0)
			elseif e.mode == "hide" then
				e.part.LocalTransparencyModifier = 1
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Routine chip
-------------------------------------------------------------------------------------------------
local chip: Frame? = nil
local chipHideAt = 0

local function showRoutine(p: any)
	if not chip then
		chip = K.make("Frame", { Name = "RoutineChip", BackgroundColor3 = K.Color.glass, BackgroundTransparency = 0.14, BorderSizePixel = 0, Size = UDim2.fromOffset(200, 96), ZIndex = 28 }, C.gui)
		K.corner(chip :: Frame, K.Radius.md)
		K.stroke(chip :: Frame, K.Color.gold, 1, 0.7)
		K.text(chip, { Name = "Head", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), Text = "📋 오늘의 루틴 · 김코치", Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.gold, ZIndex = 29 })
		for i = 1, 3 do
			K.text(chip, { Name = "Item" .. i, Position = UDim2.fromOffset(12, 6 + i * 21), Size = UDim2.new(1, -24, 0, 18), Text = "", Font = K.Font.medium, TextSize = K.Type.caption, ZIndex = 29 })
		end
	end
	local f = chip :: Frame
	local ok, r = pcall(C.Layout.rect, "topLeftChips")
	if ok and r then
		f.Position = UDim2.fromOffset(r.x, r.y + r.h + 8)
	else
		f.Position = UDim2.fromOffset(8, 52)
	end
	for i = 1, 3 do
		local k = p.kinds and p.kinds[i]
		local l = f:FindFirstChild("Item" .. i) :: TextLabel?
		if l then
			if k then
				local done = p.done and p.done[k]
				l.Text = string.format("%s %s", if done then "✅" else "⬜", (p.labels and p.labels[k]) or k)
				l.TextColor3 = if done then K.Color.green else K.Color.text
			else
				l.Text = ""
			end
		end
	end
	if p.complete then
		(f:FindFirstChild("Head") :: TextLabel).Text = "🏅 오늘의 루틴 완료!"
	end
	f.Visible = true
	chipHideAt = os.clock() + 12
end

-------------------------------------------------------------------------------------------------
-- Session events
-------------------------------------------------------------------------------------------------
local function stopRun()
	local s = session
	if s and s.runTrack then
		pcall(function()
			s.runTrack:Stop(0.3)
		end)
		s.runTrack = nil
	end
end

function Gym.init(ctx: any)
	C = ctx
	K = ctx.K
	V = ctx.V
	Anim = ctx.Anim

	C.on("gymStart", function(p)
		buildHud()
		stopRun()
		session = {
			part = if typeof(p.part) == "Instance" then p.part else nil,
			style = tostring(p.style or "scan"),
			machine = tostring(p.machine or "운동"),
			sets = tonumber(p.sets) or 1,
			setSeconds = tonumber(p.setSeconds) or 5,
			rest = tonumber(p.rest) or 1.5,
			period = tonumber(p.period) or 1,
			info = p.info == true,
			set = 1,
			setStart = os.clock(),
			perfect = 0,
			good = 0,
			taps = 0,
			sentForm = false,
			runTrack = nil,
		}
		local s = session :: Session
		hud.title.Text = "🏋️ " .. s.machine
		hud.tap.Visible = not s.info
		hud.meter.Visible = not s.info
		hud.card.Visible = true
		C.hideHud("gym", true)
		refreshStats(nil)
		K.pop(hud.card)
		C.sound("swoosh", 1.1, 0.35)
		if s.style == "run" and Anim then
			local h = C.humanoid()
			if h then
				s.runTrack = Anim.play(h, "run", { speed = 0.85, fade = 0.3, priority = Enum.AnimationPriority.Action, looped = true })
			end
		end
	end)
	C.on("gymSet", function(p)
		local s = session
		if not s then
			return
		end
		C.sound("ping", 1.25, 0.35)
		refreshStats(p.gains)
		if p.report then
			return
		end
		s.set = (tonumber(p.set) or s.set) + 1
		s.setStart = os.clock() + s.rest
		s.perfect, s.good, s.taps, s.sentForm = 0, 0, 0, false
		if p.form and p.form >= 0.8 then
			C.pop(hud.card, "완벽한 자세! 🔥", K.Color.magenta, UDim2.new(0.5, 0, 0, -40), 18, 1.4)
		end
	end)
	C.on("gymEnd", function(_p)
		stopRun()
		session = nil
		if hud then
			hud.card.Visible = false
		end
		C.hideHud("gym", false)
	end)
	C.on("routine", function(p)
		showRoutine(p)
	end)

	-- keyboard: Space / F also taps the rhythm on PC
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not session then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.F then
			Gym.tap()
		end
	end)

	-- stations (streamed in on this client) -> equipment motion while InUse
	local function watch(st: Instance)
		st:GetAttributeChangedSignal(V.Attr.InUse):Connect(function()
			stationChanged(st)
		end)
		stationChanged(st)
	end
	CollectionService:GetInstanceAddedSignal("GymStation"):Connect(watch)
	CollectionService:GetInstanceRemovedSignal("GymStation"):Connect(function(st)
		local rec = active[st]
		if rec then
			restore(rec)
			active[st] = nil
		end
	end)
	for _, st in CollectionService:GetTagged("GymStation") do
		watch(st)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		acc = 0
		if session then
			pcall(updateHud)
		end
		if next(active) then
			pcall(equipmentStep)
		end
		if chip and chip.Visible and os.clock() > chipHideAt and not session then
			chip.Visible = false
		end
	end)
end

return Gym
