-- GwangalliGameplay/Law/Jail (server; owner: law): 체포 -> 수갑 -> 경찰차 / 자동 이송 -> 광안지구대 유치장
-- -> 형기 -> 출구. Nobody respawns on an arrest and nobody is locked out of the game for long.
--
--   ARREST SCENE (Jail.begin): the suspect stops (WalkSpeed 0), the cuffs go on (a welded part between
--   the wrists + attribute LawCuffed: the client poses the arms behind the back), the officer says his
--   line. TRANSPORT: when a patrol car is near (or the one that ended the chase) the suspect is put in
--   the back seat (welded to the car root) and the car drives off toward the 지구대 for a few seconds
--   before the fade; without a car it is a short fade ("광안지구대로 이송 중…"). Player cops hand over
--   their own suspects (Cop) and call Jail.begin with info.cop.
--   THE CELL BLOCK (built once, above the 광안지구대 building so it never collides with the city): a
--   corridor with the duty desk (a guard), three cells behind bars. Every jailed player shares the
--   middle cell with an NPC inmate; the side cells hold two more. Benches are real Seats (앉기), a
--   push-up mat (팔굽혀펴기: -3 s a set, +근력, max 4), the 공기놀이 spot (a timing mini-game against the
--   inmate: a win takes JAIL_GAME_CUT seconds off, max 3), talking to the inmates (varied lines; other
--   jailed players see the bubbles too), 인사 to the cellmates, and 보석금 (bail: pay to leave now).
--   The timer is LawJail (server time the sentence ends); the client shows [남은 시간].
--   RELEASE: the guard opens up, the player appears at the 지구대 entrance with the cuffs off; the
--   remaining time is saved on leave (d.law.jail) and resumes on the next join.
-- Ops (Law.Action): jail {act = "sit" | "talk" | "greet" | "workout" | "gameStart" | "gameEnd" | "bail" | "state", ...}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jail = {}

local Law: any
local ctx: any
local LS: any
local Looks: any = nil

local jailed: { [Player]: any } = {}
local block: any = nil -- the built cell block
local rng = Random.new()

local function now(): number
	return os.clock()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function Police(): any
	return Law.children.Police
end

-------------------------------------------------------------------------------------------------
-- Station + cell block
-------------------------------------------------------------------------------------------------
local function dbg(msg: string)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		print("[GwangalliLaw:Jail] " .. msg)
	end
end

local stationCache: { cf: CFrame, exit: Vector3 }? = nil

-- the 지구대 model: a direct path first (scanning the whole map is far too slow), then the Landmarks
-- folders only
local function findStation(): Model?
	local map = workspace:FindFirstChild("Gwangalli")
	if not map then
		return nil
	end
	local up = map:FindFirstChild("uptown")
	local row = up and up:FindFirstChild("RowC_광남로-수영로")
	local lm = row and row:FindFirstChild("Landmarks")
	local m = lm and lm:FindFirstChild("광안지구대 (부산수영경찰서)")
	if m and m:IsA("Model") then
		return m
	end
	for _, district in map:GetChildren() do
		for _, rowF in district:GetChildren() do
			local l = rowF:FindFirstChild("Landmarks")
			if l then
				for _, c in l:GetChildren() do
					if c:IsA("Model") and string.sub(c.Name, 1, #"광안지구대") == "광안지구대" then
						return c
					end
				end
			end
		end
	end
	return nil
end

local function stationFrame(): (CFrame, Vector3)
	if stationCache then
		return stationCache.cf, stationCache.exit
	end
	-- the entrance (the Destination part the quick travel uses), else the station model, else a fallback
	local dest = ctx and ctx.dest and ctx.dest("광안지구대")
	local model = findStation()
	local exitPos: Vector3
	if dest then
		exitPos = dest.Position
	elseif model then
		exitPos = model:GetPivot().Position
	else
		exitPos = Vector3.new(-326, 7, 584)
	end
	local base = if model then model:GetPivot() else CFrame.new(exitPos)
	local cf = CFrame.new(base.Position.X, exitPos.Y + 380, base.Position.Z)
	stationCache = { cf = cf, exit = exitPos }
	return cf, exitPos
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3?, bg: Color3?, size: number?)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = if bg then 0 else 1
	t.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	t.Text = text
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextWrapped = true
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = size or 80
	lim.Parent = t
	t.Parent = g
	g.Parent = p
end

local function bars(parent: Instance, from: Vector3, to: Vector3, h: number, gap: number)
	local dir = to - from
	local n = math.floor(dir.Magnitude / gap)
	for i = 0, n do
		local p = from + dir.Unit * (i * gap)
		local b = part(parent, "Bar", Vector3.new(0.28, h, 0.28), CFrame.new(p + Vector3.new(0, h / 2, 0)), Color3.fromRGB(70, 74, 82), Enum.Material.Metal)
		b.CanQuery = false
	end
	local mid = (from + to) / 2
	part(parent, "BarTop", Vector3.new(dir.Magnitude + 0.3, 0.4, 0.4), CFrame.lookAt(mid + Vector3.new(0, h, 0), mid + Vector3.new(0, h, 0) + dir) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(60, 64, 72), Enum.Material.Metal)
	part(parent, "BarBottom", Vector3.new(dir.Magnitude + 0.3, 0.3, 0.4), CFrame.lookAt(mid + Vector3.new(0, 0.15, 0), mid + Vector3.new(0, 0.15, 0) + dir) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(60, 64, 72), Enum.Material.Metal)
end

local function inmateRig(id: string, cf: CFrame, act: string, hint: any): any?
	if not Looks then
		return nil
	end
	local ok, rig = pcall(function()
		return Looks.build(Looks.random(id, hint), { name = "Inmate_" .. id, anchored = true, shadow = false })
	end)
	if not ok or type(rig) ~= "table" or not rig.model then
		return nil
	end
	local g = rig.ground or 3
	local m = rig.model
	m:SetAttribute("NpcId", id)
	m:SetAttribute("NpcKind", "inmate")
	m:SetAttribute("NpcGround", g)
	m:SetAttribute("NpcAct", act)
	local _, yaw = cf:ToOrientation()
	m:SetAttribute("NpcYaw", math.deg(yaw))
	local p = cf.Position
	m:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", p.X, p.Y, p.Z, p.X, p.Y, p.Z, serverNow()))
	m:PivotTo(cf + Vector3.new(0, g, 0)) -- the whole rig (see Police.newOfficer)
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local f = workspace:FindFirstChild("GwangalliNPCs")
	m.Parent = f or workspace
	return { model = m, root = rig.root, id = id }
end

local function build(): any
	if block then
		return block
	end
	local base, exitPos = stationFrame()
	local folder = Instance.new("Model")
	folder.Name = "GwangalliJail"
	local CONC = Color3.fromRGB(176, 178, 182)
	local WALL = Color3.fromRGB(206, 210, 214)
	local DARK = Color3.fromRGB(60, 64, 70)
	local o = base.Position
	local W, Dp, H = 54, 34, 13
	-- shell
	part(folder, "Floor", Vector3.new(W, 1, Dp), CFrame.new(o), CONC, Enum.Material.Concrete)
	part(folder, "Ceiling", Vector3.new(W, 1, Dp), CFrame.new(o + Vector3.new(0, H, 0)), WALL, Enum.Material.SmoothPlastic)
	part(folder, "WallN", Vector3.new(W, H, 1), CFrame.new(o + Vector3.new(0, H / 2, -Dp / 2)), WALL)
	part(folder, "WallS", Vector3.new(W, H, 1), CFrame.new(o + Vector3.new(0, H / 2, Dp / 2)), WALL)
	part(folder, "WallW", Vector3.new(1, H, Dp), CFrame.new(o + Vector3.new(-W / 2, H / 2, 0)), WALL)
	part(folder, "WallE", Vector3.new(1, H, Dp), CFrame.new(o + Vector3.new(W / 2, H / 2, 0)), WALL)
	-- a stripe + the sign on the corridor wall (south)
	local stripe = part(folder, "Stripe", Vector3.new(W - 1, 1.2, 0.2), CFrame.new(o + Vector3.new(0, 3.2, Dp / 2 - 0.6)), Color3.fromRGB(30, 60, 140), Enum.Material.SmoothPlastic, false)
	local _ = stripe
	local signP = part(folder, "Sign", Vector3.new(16, 2.6, 0.2), CFrame.new(o + Vector3.new(0, 8.5, Dp / 2 - 0.6)), Color3.fromRGB(20, 40, 100), Enum.Material.SmoothPlastic, false)
	sign(signP, Enum.NormalId.Front, "🚓 광안지구대 유치장", Color3.new(1, 1, 1), Color3.fromRGB(20, 40, 100), 70)
	-- ceiling lamps
	for i = -2, 2 do
		local lamp = part(folder, "Lamp", Vector3.new(4, 0.3, 1.2), CFrame.new(o + Vector3.new(i * 10, H - 0.7, 0)), Color3.fromRGB(255, 252, 236), Enum.Material.Neon, false)
		local l = Instance.new("PointLight")
		l.Range = 22
		l.Brightness = 1.6
		l.Color = Color3.fromRGB(255, 246, 226)
		l.Parent = lamp
	end
	-- cells: back half (north), corridor south of the bars
	local cellDepth = 15
	local barZ = -Dp / 2 + cellDepth
	local cellW = W / 3
	local cells = {}
	for c = 1, 3 do
		local x0 = -W / 2 + (c - 1) * cellW
		if c > 1 then
			part(folder, "CellWall" .. c, Vector3.new(0.8, H, cellDepth), CFrame.new(o + Vector3.new(x0, H / 2, -Dp / 2 + cellDepth / 2)), WALL)
		end
		bars(folder, o + Vector3.new(x0 + 0.6, 0.5, barZ), o + Vector3.new(x0 + cellW - 0.6, 0.5, barZ), H - 1, 1.3)
		local cx = x0 + cellW / 2
		-- bench (a real Seat) along the back wall
		local seatA = Instance.new("Seat")
		seatA.Name = "JailBench"
		seatA.Size = Vector3.new(6, 1, 2)
		seatA.CFrame = CFrame.new(o + Vector3.new(cx - 3.5, 1.6, -Dp / 2 + 1.8))
		seatA.Anchored = true
		seatA.Color = Color3.fromRGB(120, 92, 64)
		seatA.Material = Enum.Material.Wood
		seatA.Parent = folder
		local seatB = Instance.new("Seat")
		seatB.Name = "JailBench"
		seatB.Size = Vector3.new(6, 1, 2)
		seatB.CFrame = CFrame.new(o + Vector3.new(cx + 3.5, 1.6, -Dp / 2 + 1.8))
		seatB.Anchored = true
		seatB.Color = Color3.fromRGB(120, 92, 64)
		seatB.Material = Enum.Material.Wood
		seatB.Parent = folder
		-- a barred window (city glow)
		local win = part(folder, "Window", Vector3.new(4, 2.2, 0.2), CFrame.new(o + Vector3.new(cx, 9, -Dp / 2 + 0.6)), Color3.fromRGB(255, 196, 120), Enum.Material.Neon, false)
		sign(win, Enum.NormalId.Back, "· · 광안대교 · ·", Color3.fromRGB(80, 40, 10), nil, 30)
		for k = -1, 1 do
			part(folder, "WinBar", Vector3.new(0.18, 2.3, 0.3), CFrame.new(o + Vector3.new(cx + k * 1.2, 9, -Dp / 2 + 0.75)), DARK, Enum.Material.Metal, false)
		end
		cells[c] = { x0 = x0, cx = cx, seats = { seatA, seatB } }
	end
	-- the middle cell: the players' cell — push-up mat, the 공기 spot, a scribbled wall
	local mid = cells[2]
	local mat = part(folder, "PushupMat", Vector3.new(4, 0.15, 6), CFrame.new(o + Vector3.new(mid.cx + 5, 0.58, -Dp / 2 + 9)), Color3.fromRGB(40, 110, 160), Enum.Material.Fabric, false)
	local gonggi = part(folder, "GonggiSpot", Vector3.new(3, 0.12, 3), CFrame.new(o + Vector3.new(mid.cx - 5, 0.56, -Dp / 2 + 9.5)), Color3.fromRGB(200, 170, 120), Enum.Material.Fabric, false)
	for k = 1, 5 do
		part(folder, "Gonggi" .. k, Vector3.new(0.3, 0.3, 0.3), CFrame.new(o + Vector3.new(mid.cx - 5 + (k - 3) * 0.45, 0.8, -Dp / 2 + 9.5 + ((k % 2) - 0.5) * 0.4)), Color3.fromHSV(k / 5, 0.7, 1), Enum.Material.SmoothPlastic, false)
	end
	local scribble = part(folder, "Scribble", Vector3.new(6, 3, 0.1), CFrame.new(o + Vector3.new(mid.x0 + 0.5, 5.5, -Dp / 2 + 8)) * CFrame.Angles(0, math.rad(90), 0), WALL, Enum.Material.SmoothPlastic, false)
	sign(scribble, Enum.NormalId.Front, "착하게 살자 ㅠㅠ\n국밥 먹고 싶다\n||||  ||||  ||", Color3.fromRGB(70, 70, 80), nil, 34)
	-- the duty desk in the corridor
	local desk = part(folder, "DutyDesk", Vector3.new(8, 3, 2.5), CFrame.new(o + Vector3.new(-W / 2 + 7, 1.9, Dp / 2 - 4)), Color3.fromRGB(110, 120, 140), Enum.Material.SmoothPlastic)
	local _ = desk
	local exitDoor = part(folder, "ExitDoor", Vector3.new(5, 9, 0.4), CFrame.new(o + Vector3.new(W / 2 - 6, 5, Dp / 2 - 0.7)), Color3.fromRGB(80, 90, 110), Enum.Material.Metal)
	sign(exitDoor, Enum.NormalId.Back, "출구 EXIT", Color3.fromRGB(120, 255, 140), Color3.fromRGB(20, 30, 24), 60)
	folder.Parent = workspace
	-- NPCs: the guard and three inmates (one shares the players' cell)
	local guard = nil
	local okG, gr = pcall(function()
		return Looks and Looks.build(Looks.random("jail_guard", { style = "police", body = "m", age = "adult" }), { name = "JailGuard", anchored = true, shadow = false })
	end)
	if okG and type(gr) == "table" and gr.model then
		local g = gr.ground or 3
		local at = o + Vector3.new(-W / 2 + 7, 0.5, Dp / 2 - 6.4)
		gr.model:SetAttribute("NpcId", "jail_guard")
		gr.model:SetAttribute("NpcKind", "inmate")
		gr.model:SetAttribute("NpcGround", g)
		gr.model:SetAttribute("NpcAct", "clipboard")
		gr.model:SetAttribute("NpcYaw", 180)
		gr.model:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", at.X, at.Y, at.Z, at.X, at.Y, at.Z, serverNow()))
		gr.model:PivotTo(CFrame.new(at + Vector3.new(0, g, 0)) * CFrame.Angles(0, math.rad(180), 0))
		gr.model.Parent = workspace:FindFirstChild("GwangalliNPCs") or workspace
		guard = { model = gr.model, root = gr.root, id = "jail_guard" }
	end
	local inmates = {}
	local spots = {
		{ cell = 2, x = 3.5, z = 1.8, act = "sit", hint = { style = "street", body = "m", age = "young" }, name = "덕배" },
		{ cell = 1, x = 0, z = 1.8, act = "sit", hint = { style = "punk", body = "m", age = "young" }, name = "짱돌" },
		{ cell = 3, x = -2, z = 6, act = "idle", hint = { style = "office", body = "m", age = "adult" }, name = "김 부장" },
	}
	for i, sp in spots do
		local c = cells[sp.cell]
		local at = o + Vector3.new(c.cx + sp.x, 0.5, -Dp / 2 + sp.z + (if sp.act == "sit" then 0.6 else 0))
		local im = inmateRig("inmate_" .. i, CFrame.new(at) * CFrame.Angles(0, math.rad(180), 0), sp.act, sp.hint)
		if im then
			im.name = sp.name
			im.cell = sp.cell
			im.model:SetAttribute("LawName", sp.name)
			if sp.cell == 2 then
				local pr = Instance.new("ProximityPrompt")
				pr.Name = "TalkPrompt"
				pr.ActionText = "대화하기"
				pr.ObjectText = "수감자 " .. sp.name
				pr.HoldDuration = 0
				pr.MaxActivationDistance = 9
				pr.RequiresLineOfSight = false
				pr.Parent = im.root
				pr.Triggered:Connect(function(p)
					Jail.act(p, { act = "talk" })
				end)
			end
			table.insert(inmates, im)
		end
	end
	-- prompts on the activity spots
	local function prompt(at: BasePart, action: string, object: string, act: string)
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = action
		pr.ObjectText = object
		pr.HoldDuration = 0
		pr.MaxActivationDistance = 8
		pr.RequiresLineOfSight = false
		pr.Parent = at
		pr.Triggered:Connect(function(p)
			Jail.act(p, { act = act })
		end)
	end
	prompt(mat, "팔굽혀펴기", "운동 매트", "workout")
	prompt(gonggi, "공기놀이", "수감자랑 한 판", "gameStart")
	local cellMin = o + Vector3.new(mid.x0 + 0.6, -2, -Dp / 2 + 0.6)
	local cellMax = o + Vector3.new(mid.x0 + cellW - 0.6, H + 2, barZ - 0.4)
	block = {
		model = folder,
		origin = o,
		exitPos = exitPos,
		cell = mid,
		cellMin = cellMin,
		cellMax = cellMax,
		spawnCF = CFrame.new(o + Vector3.new(mid.cx, 3.6, -Dp / 2 + 10)) * CFrame.Angles(0, math.rad(180), 0),
		guard = guard,
		inmates = inmates,
		lastInmateLine = nil,
	}
	return block
end

local function inCell(pos: Vector3): boolean
	local b = block
	if not b then
		return false
	end
	return pos.X >= b.cellMin.X and pos.X <= b.cellMax.X and pos.Z >= b.cellMin.Z and pos.Z <= b.cellMax.Z and pos.Y >= b.cellMin.Y and pos.Y <= b.cellMax.Y
end

-------------------------------------------------------------------------------------------------
-- Character helpers
-------------------------------------------------------------------------------------------------
local function humanoidOf(player: Player): Humanoid?
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function freeze(player: Player, on: boolean)
	local h = humanoidOf(player)
	if not h then
		return
	end
	if on then
		if player:GetAttribute("LawWalk") == nil then
			player:SetAttribute("LawWalk", h.WalkSpeed)
			player:SetAttribute("LawJump", h.JumpPower)
		end
		h.WalkSpeed = 0
		h.JumpPower = 0
		pcall(function()
			h.Sit = false
		end)
	else
		local w = player:GetAttribute("LawWalk")
		local j = player:GetAttribute("LawJump")
		h.WalkSpeed = if type(w) == "number" and w > 0 then w else 16
		h.JumpPower = if type(j) == "number" and j > 0 then j else 50
		player:SetAttribute("LawWalk", nil)
		player:SetAttribute("LawJump", nil)
	end
end

local function cuffs(player: Player, on: boolean)
	local ch = player.Character
	if not ch then
		return
	end
	local old = ch:FindFirstChild("LawHandcuffs")
	if old then
		old:Destroy()
	end
	player:SetAttribute(LS.Attr.Cuffed, on)
	if not on then
		return
	end
	local hand = ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		local c = Instance.new("Part")
		c.Name = "LawHandcuffs"
		c.Size = Vector3.new(0.9, 0.25, 0.35)
		c.Color = Color3.fromRGB(190, 194, 200)
		c.Material = Enum.Material.Metal
		c.CanCollide, c.CanQuery, c.CanTouch, c.Massless = false, false, false, true
		c.CFrame = hand.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = c
		w.Parent = c
		c.Parent = ch
	end
end

local function ejectFromVehicle(player: Player)
	local h = humanoidOf(player)
	if h and h.SeatPart then
		pcall(function()
			local api = game:GetService("ServerStorage"):FindFirstChild("GwangalliVehiclesAPI")
			local car = h.SeatPart and h.SeatPart:FindFirstAncestorOfClass("Model")
			if api and car then
				(api :: BindableFunction):Invoke("eject", car)
			end
		end)
		pcall(function()
			h.Sit = false
		end)
		local w = h.SeatPart and h.SeatPart:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
	end
end

local function place(player: Player, cf: CFrame)
	local ch = player.Character
	if not ch then
		return
	end
	if ctx and ctx.allowTeleport then
		pcall(ctx.allowTeleport, player, 6)
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 4)
	end)
	local U = ctx and ctx.Util
	if not (U and U.placeCharacter and U.placeCharacter(player, cf)) then
		ch:PivotTo(cf)
	end
end

local function fade(player: Player, on: boolean, seconds: number, caption: string?)
	local U = ctx and ctx.Util
	if U and U.fade then
		pcall(U.fade, player, on, seconds, caption)
	end
end

-------------------------------------------------------------------------------------------------
-- Arrest -> transport -> cell
-------------------------------------------------------------------------------------------------
local function view(player: Player): any?
	local j = jailed[player]
	if not j then
		return nil
	end
	return {
		left = math.max(0, j.endsAt - serverNow()),
		total = j.total,
		label = j.label,
		crimes = j.crimes,
		bail = LS.bailFor(j.sev, math.max(0, j.endsAt - serverNow()), j.total),
		games = j.games,
		workouts = j.workouts,
		inCell = j.inCell,
		cop = j.copName,
	}
end
Jail.view = view

local function intoCell(player: Player, j: any)
	local b = build()
	j.inCell = true
	freeze(player, false)
	cuffs(player, false)
	local spot = b.spawnCF * CFrame.new((rng:NextNumber() - 0.5) * 6, 0, (rng:NextNumber() - 0.5) * 3)
	place(player, spot)
	player:SetAttribute(LS.Attr.Jail, j.endsAt)
	local s = Law.sess(player)
	if s then
		s.cuffed = false
		s.jail = j
		Law.writeAttrs(player, s)
	end
	fade(player, false, 0.8, nil)
	Law.push(player, { kind = "jail", state = view(player) })
	if b.guard then
		task.delay(1.2, function()
			if b.guard and b.guard.model.Parent then
				Police().say(b.guard, "들어가세요. " .. LS.fmtTime(j.endsAt - serverNow()) .. " 있다가 나가실 수 있어요.", 4)
			end
		end)
	end
end

-- the car for the ride: info.car, else the nearest police car with a live crew (not a 119 / 특임대
-- car, not one already leaving / riding / recalling its crew); one with its crew seated is preferred
local function rideCar(P: any, pp: Vector3?, info: any): any?
	local car = info.car
	if car and not car.gone and car.model and car.model.Parent then
		return car
	end
	if not pp then
		return nil
	end
	local best, bestScore = nil, math.huge
	for _, c in P.cars() do
		if not c.gone and not c.unit and c.model and c.model.Parent and c.state ~= "leave" and c.state ~= "transport" and c.state ~= "recall" and c.state ~= "demo" then
			local live = false
			for _, o in c.crew do
				if not o.gone then
					live = true
					break
				end
			end
			local d = Law.flat((P.carPos(c)), pp)
			if live and d < 90 then
				local score = d - (if P.seatedCount(c) > 0 then 40 else 0)
				if score < bestScore then
					best, bestScore = c, score
				end
			end
		end
	end
	return best
end

-- the crew gets back in before the ride (the cuffed player watches them walk to the car): never a
-- ride behind two empty front seats. nil = nobody could get in (the fade-only transfer then)
local function crewIn(P: any, car: any, player: Player, j: any, info: any): any?
	if P.seatedCount(car) > 0 then
		return car
	end
	car.holdUntil = math.max(car.holdUntil or 0, now() + 15) -- (Police keeps a "hold" car standing)
	for _, o in car.crew do
		if not o.gone and not o.seated and o.state ~= "board" then
			P.boardOfficer(o, car, 11)
		end
	end
	local o = info.officer
	if P.boardingCount(car) == 0 and o and not o.gone and not o.seated and not o.unit then
		P.boardOfficer(o, car, 11)
	end
	local deadline = now() + 10
	while now() < deadline and not car.gone and player.Parent and jailed[player] == j and P.boardingCount(car) > 0 do
		task.wait(0.25)
	end
	-- stragglers walk off on foot (as the recall does)
	for _, x in car.crew do
		if not x.gone and x.state == "board" then
			x.boardSlot, x.boardStep, x.car = nil, nil, nil
			x.role = "patrol"
			x.state = "leave"
			x.leaveAt = now() + 30
		end
	end
	if car.gone or P.seatedCount(car) == 0 then
		return nil
	end
	return car
end

local function transport(player: Player, j: any, info: any)
	local P = Police()
	local pp = Law.posOf(player)
	local car = P and rideCar(P, pp, info)
	if car and P then
		car = crewIn(P, car, player, j, info)
	end
	if not player.Parent or jailed[player] ~= j then
		return
	end
	if car and car.model and car.model.Parent and P then
		-- into the back seat, then a short drive toward the 지구대 before the fade
		fade(player, true, 0.5, "🚓 경찰차에 태워지는 중…")
		task.wait(0.6)
		dbg("transport: in car " .. tostring(car.id))
		local ch = player.Character
		local root = Law.rootOf(player)
		local carRoot = car.model.PrimaryPart
		if ch and root and carRoot then
			ejectFromVehicle(player)
			car.state = "transport"
			local seatCF = carRoot.CFrame * CFrame.new(-1.3, 0.6, 1.6)
			ch:PivotTo(seatCF)
			local w = Instance.new("WeldConstraint")
			w.Name = "LawTransportWeld"
			w.Part0 = carRoot
			w.Part1 = root
			w.Parent = root
			j.weld = w
			local _, exitPos = stationFrame()
			dbg("transport: welded")
			local path = P.carRoute(car, exitPos, { cruise = 34, v0 = 0, v1 = 0 })
			dbg("transport: route " .. tostring(path ~= nil))
			if path then
				P.setCarPath(car, path)
			end
			fade(player, false, 0.4, nil)
			Law.push(player, { kind = "arrest", stage = "ride", text = "🚓 광안지구대로 이송 중…" })
			task.wait(5)
			fade(player, true, 0.8, "🚓 광안지구대 도착")
			task.wait(0.9)
			if j.weld then
				j.weld:Destroy()
				j.weld = nil
			end
			P.releaseCar(car)
			return
		end
	end
	fade(player, true, 0.8, "🚓 광안지구대로 이송 중…")
	Law.push(player, { kind = "arrest", stage = "ride", text = "🚓 광안지구대로 이송 중…" })
	task.wait(2.6)
end

function Jail.begin(player: Player, s: any, episode: any, info: any)
	local seconds = episode.seconds
	local j = {
		total = seconds,
		endsAt = serverNow() + seconds + 6, -- the transport is not counted
		sev = episode.sev,
		label = episode.band,
		crimes = episode.crimes,
		games = 0,
		workouts = 0,
		inCell = false,
		copName = info.cop and info.cop.DisplayName or (info.officer and info.officer.name) or "광안지구대",
		gameT = nil,
		started = serverNow(),
	}
	jailed[player] = j
	s.jail = j
	ejectFromVehicle(player)
	freeze(player, true)
	cuffs(player, true)
	Law.push(player, { kind = "arrest", stage = "cuffs", fine = episode.fine, paid = episode.paid, owed = episode.owed, seized = episode.seized, crimes = episode.crimes, seconds = seconds, band = episode.band, cop = j.copName, surrender = episode.surrender })
	Law.notify(player, "warn", "🚓 체포", (episode.crimes ~= "" and episode.crimes or "범죄") .. " · 벌금 " .. LS.won(episode.fine) .. " · 유치장 " .. LS.fmtTime(seconds))
	if info.officer and Police() then
		Police().say(info.officer, LS.pick(LS.LINES.cuffed), 3)
		Police().emote(info.officer, "point_proc")
	end
	task.spawn(function()
		task.wait(2.4)
		if not player.Parent or jailed[player] ~= j then
			return
		end
		if info.cop then
			-- a player cop already escorted / drove the suspect: straight in
			fade(player, true, 0.7, "🚓 광안지구대 인계")
			task.wait(0.8)
		else
			transport(player, j, info)
		end
		dbg("begin: into cell")
		if player.Parent and jailed[player] == j then
			intoCell(player, j)
		end
		dbg("begin: done")
	end)
end

-- the saved remainder of a sentence (rejoin)
function Jail.resume(player: Player, s: any, saved: any)
	local j = {
		total = saved.total,
		endsAt = serverNow() + saved.left,
		sev = saved.sev,
		label = saved.label,
		crimes = "",
		games = 0,
		workouts = 0,
		inCell = false,
		copName = "광안지구대",
		started = serverNow(),
	}
	jailed[player] = j
	s.jail = j
	task.spawn(function()
		local tries = 0
		while player.Parent and not Law.rootOf(player) and tries < 40 do
			task.wait(0.25)
			tries += 1
		end
		if player.Parent and jailed[player] == j then
			Law.notify(player, "warn", "🚓 남은 형기", "지난번 유치장 시간이 남아 있어요 (" .. LS.fmtTime(saved.left) .. ")")
			intoCell(player, j)
		end
	end)
end

local function release(player: Player, why: string)
	local j = jailed[player]
	if not j then
		return
	end
	jailed[player] = nil
	if j.weld then
		j.weld:Destroy()
	end
	local s = Law.sess(player)
	if s then
		s.jail = nil
		s.cuffed = false
	end
	player:SetAttribute(LS.Attr.Jail, 0)
	cuffs(player, false)
	freeze(player, false)
	local b = block
	if b and b.guard and Police() then
		Police().say(b.guard, LS.pick(LS.LINES.release), 3)
	end
	if s then
		Law.writeAttrs(player, s)
	end
	task.spawn(function()
		fade(player, true, 0.6, if why == "bail" then "💸 보석금 납부 · 석방" else "🚪 출소")
		task.wait(0.7)
		local exitPos = b and b.exitPos or select(2, stationFrame())
		place(player, CFrame.new(exitPos + Vector3.new(0, 3.5, 0)))
		fade(player, false, 0.8, nil)
		Law.push(player, { kind = "release", why = why })
		Law.notify(player, "info", "🚪 석방", if why == "bail" then "보석금을 내고 나왔어요" else "형기를 마치고 나왔어요. 착하게 삽시다!")
		Law.sendState(player)
	end)
end

-------------------------------------------------------------------------------------------------
-- Cell activities
-------------------------------------------------------------------------------------------------
local function cut(player: Player, j: any, seconds: number, why: string)
	j.endsAt = math.max(serverNow() + 3, j.endsAt - seconds)
	player:SetAttribute(LS.Attr.Jail, j.endsAt)
	Law.push(player, { kind = "jail", state = view(player), toast = "⏱️ -" .. seconds .. "초 (" .. why .. ")" })
end

local function inmateSay(text: string, im: any?)
	local b = block
	if not b or #b.inmates == 0 or not Police() then
		return
	end
	local who = im or b.inmates[1]
	Police().say(who, text, 4)
end

local function bubbleOver(player: Player, text: string)
	-- the player's line as a bubble everyone in the cell block sees
	for p in jailed do
		Law.push(p, { kind = "cellChat", from = player.DisplayName, userId = player.UserId, text = text })
	end
end

function Jail.act(player: Player, p: any): any
	local j = jailed[player]
	if not j or not j.inCell then
		return { ok = false, err = "notjailed" }
	end
	local act = p and p.act
	local b = build()
	if act == "state" then
		return { ok = true, state = view(player) }
	elseif act == "sit" then
		local h = humanoidOf(player)
		local pp = Law.posOf(player)
		if h and pp then
			local best, bd = nil, math.huge
			for _, seat in b.cell.seats do
				if not seat.Occupant then
					local d = (seat.Position - pp).Magnitude
					if d < bd then
						best, bd = seat, d
					end
				end
			end
			if best then
				best:Sit(h)
				return { ok = true }
			end
		end
		return { ok = false, err = "noseat" }
	elseif act == "talk" then
		if now() - (j.lastTalk or 0) < 2.5 then
			return { ok = false, err = "slow" }
		end
		j.lastTalk = now()
		local line = LS.pick(LS.LINES.inmate, function()
			return rng:NextNumber()
		end, b.lastInmateLine)
		b.lastInmateLine = line
		local im = b.inmates[1]
		inmateSay(line, im)
		bubbleOver(player, LS.pick({ "저기요…", "형님, 여기 오래 있었어요?", "안녕하세요…", "여기 밥 나와요?", "심심하다…" }))
		task.delay(2.6, function()
			if jailed[player] then
				inmateSay(LS.pick(LS.LINES.inmate_reply), im)
			end
		end)
		return { ok = true, line = line }
	elseif act == "greet" then
		if now() - (j.lastGreet or 0) < 3 then
			return { ok = false, err = "slow" }
		end
		j.lastGreet = now()
		bubbleOver(player, LS.pick({ "다들 안녕하세요 👋", "같이 힘내요!", "여기 처음이에요 ㅠ", "나가면 국밥 한 그릇 해요!" }))
		return { ok = true }
	elseif act == "workout" then
		if j.workouts >= 4 then
			return { ok = false, err = "tired", text = "오늘 운동은 충분해요" }
		end
		if now() - (j.lastWorkout or 0) < 4 then
			return { ok = false, err = "slow", text = "숨 좀 돌리고 해요" }
		end
		j.lastWorkout = now()
		j.workouts += 1
		if ctx and ctx.addStats then
			pcall(ctx.addStats, player, { strength = 1 }, "유치장 운동", true)
		end
		cut(player, j, LS.JAIL_WORKOUT_CUT, "팔굽혀펴기 " .. j.workouts .. "세트")
		return { ok = true, sets = j.workouts }
	elseif act == "gameStart" then
		if j.games >= 3 then
			inmateSay("또? 이제 그만하자 ㅋㅋ 손목 아파.")
			return { ok = false, err = "done", text = "오늘은 그만하재요" }
		end
		-- timing game: catch the stone when the marker is inside the zone (server picks the zone)
		local zone = 0.25 + rng:NextNumber() * 0.5
		local width = math.max(0.1, 0.2 - j.games * 0.03)
		j.gameT = now()
		j.game = { zone = zone, width = width, speed = 0.9 + j.games * 0.25 }
		inmateSay(LS.pick({ "공기 할 줄 알아? 꺾기까지 해 봐.", "좋아, 지면 내일 국 양보하기다 ㅋㅋ", "내가 동네 공기 챔피언이었어." }))
		Law.push(player, { kind = "jailGame", zone = zone, width = width, speed = j.game.speed })
		return { ok = true, zone = zone, width = width, speed = j.game.speed }
	elseif act == "gameEnd" then
		local g = j.game
		if not g or not j.gameT then
			return { ok = false }
		end
		j.game = nil
		local took = now() - j.gameT
		local hit = type(p.hit) == "number" and p.hit or -1
		-- a real round takes a moment and the reported stop must be inside the zone
		local win = took > 1.2 and took < 30 and math.abs(hit - g.zone) <= g.width / 2 + 0.02
		if win then
			j.games += 1
			cut(player, j, LS.JAIL_GAME_CUT, "공기놀이 승리")
			inmateSay(LS.pick({ "헐, 잘하네?", "에이 봐준 거야!", "오… 인정." }))
		else
			inmateSay(LS.pick({ "ㅋㅋㅋ 내가 이겼다!", "아깝다~ 한 번 더?", "공기는 손목이야 손목." }))
		end
		return { ok = true, win = win, state = view(player) }
	elseif act == "bail" then
		local left = j.endsAt - serverNow()
		local cost = LS.bailFor(j.sev, left, j.total)
		local d = Law.profile(player)
		local cash, bank = d and d.cash or 0, d and d.bank or 0
		if cash + bank < cost then
			return { ok = false, err = "money", text = "보석금 " .. LS.won(cost) .. "이 부족해요" }
		end
		if not (ctx.spend and ctx.spend(player, cost, "🚓 보석금 · 광안지구대")) then
			return { ok = false, err = "money" }
		end
		Law.stat(player, "bails")
		release(player, "bail")
		return { ok = true, paid = cost }
	end
	return { ok = false, err = "bad" }
end

-------------------------------------------------------------------------------------------------
-- Ticks / hooks
-------------------------------------------------------------------------------------------------
local acc = 0
function Jail.tick(dt: number)
	acc += dt
	if acc < 0.5 then
		return
	end
	acc = 0
	for player, j in jailed do
		if not player.Parent then
			jailed[player] = nil
		elseif j.inCell then
			if serverNow() >= j.endsAt then
				release(player, "served")
			else
				-- keep them in the cell (a glitch / a jump through the bars puts them back)
				local pp = Law.posOf(player)
				if pp and not inCell(pp) and block then
					place(player, block.spawnCF)
				end
			end
		end
	end
	-- the inmates chat among themselves now and then when someone is inside
	if next(jailed) and block and rng:NextNumber() < 0.05 then
		local im = block.inmates[rng:NextInteger(1, #block.inmates)]
		if im then
			inmateSay(LS.pick(LS.LINES.inmate, nil, block.lastInmateLine), im)
		end
	end
end

function Jail.onCharacter(player: Player, s: any, _character: Model)
	local j = jailed[player]
	if j and j.inCell then
		task.delay(0.5, function()
			if jailed[player] == j and block then
				place(player, block.spawnCF)
			end
		end)
	elseif j then
		-- respawned during the arrest scene: straight to the cell
		task.delay(0.5, function()
			if jailed[player] == j then
				intoCell(player, j)
			end
		end)
	end
end

function Jail.onLeave(player: Player, s: any)
	local j = jailed[player]
	if not j then
		return
	end
	local left = math.max(1, j.endsAt - serverNow())
	local L = Law.data(player)
	L.jail = { left = math.min(LS.JAIL_MAX, left), total = j.total, sev = j.sev, label = j.label }
	Law.dirty(player)
	jailed[player] = nil
end

Jail.cuffs = cuffs
Jail.freeze = freeze

function Jail.isJailed(player: Player): boolean
	return jailed[player] ~= nil
end

function Jail.init(law: any, context: any)
	Law = law
	ctx = context
	LS = Law.shared()
	local lm = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if lm and lm:IsA("ModuleScript") then
		local ok, res = pcall(require, lm)
		if ok then
			Looks = res
		end
	end
	Law.ops.jail = function(player, _s, p)
		return Jail.act(player, p)
	end
	-- build the block once the map is in (Destination parts are tagged at boot)
	task.delay(8, function()
		local ok, err = pcall(build)
		if not ok then
			warn("[GwangalliLaw] jail build failed: " .. tostring(err))
		end
	end)
	local _ = Players
end

return Jail
