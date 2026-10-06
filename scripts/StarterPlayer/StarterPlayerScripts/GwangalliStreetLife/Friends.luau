-- GwangalliStreetLife/Friends (client; owner: npc_mind): 친구 퍼레이드 — the Friend Avatar NPC
-- System. A few of this player's Roblox friends, in their real avatars (loaded by the server script
-- GwangalliFriendAvatars into PlayerGui.GwangalliFriendAvatars), appear for this player only:
--   * WHERE / WHEN: the evening plaza (만남의 광장, 17-23.5 h) and the club-night parade in front of
--     CLUB OCEAN (19-3 h). They appear when the player comes within NEAR studs and go when the
--     player is FAR away (or the hour is over): never more than MAX at once, local models only.
--   * WHAT: a loose parade loop around the spot (walk), then a dance (each their own), again; a
--     friend the player walks up to waves. A small name tag shows who it is.
--   * NEVER a negative role: they are not crowd agents (no 어깨빵 / fights / robbery / police /
--     witness), tagged GwFriendAvatar = true and GwRobbable = false for any other system, and the
--     avatar is used as it is.
-- Placeholder entries (test: names only) are dressed with roster looks (GwangalliNPCLooks).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Friends = {}

Friends.MAX = 6
Friends.NEAR = 90
Friends.FAR = 150
Friends.MARCH_S = 16
Friends.DANCE_S = 18
Friends.WALK = 3.4 -- studs/s along the loop
Friends.WAVE_R = 7

local player = Players.LocalPlayer
local ctx: any
local W: any
local Night: any
local Looks: any
local Anim: any
local entries: { any } = {}
local show: any = nil
local nextCheck = 0

local function clockNow(): number
	local ok, c = pcall(function()
		return ctx.clock()
	end)
	return if ok and type(c) == "number" then c else 12
end

local function playerPos(): Vector3?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position or nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-------------------------------------------------------------------------------------------------
-- entries (from the server folder)
-------------------------------------------------------------------------------------------------
local function rebuildEntries(folder: Instance)
	table.clear(entries)
	for _, ch in folder:GetChildren() do
		local name = ch:GetAttribute("FriendName")
		if type(name) == "string" then
			table.insert(entries, { key = ch.Name, name = name, template = if ch:IsA("Model") then ch else nil })
		end
	end
end

-------------------------------------------------------------------------------------------------
-- one friend on the street
-------------------------------------------------------------------------------------------------
local DANCES = { "dance", "dance2", "dance3" }

local function tag(model: Model, adornee: BasePart?, name: string, high: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "GwFriendTag"
	bb.Size = UDim2.fromOffset(150, 26)
	bb.StudsOffsetWorldSpace = Vector3.new(0, high, 0)
	bb.MaxDistance = 70
	bb.AlwaysOnTop = false
	bb.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "👥 " .. name
	t.TextColor3 = Color3.fromRGB(255, 255, 255)
	t.TextStrokeTransparency = 0.4
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = bb
	bb.Parent = adornee or model -- (on the part, like the street chips)
end

local function trackFor(m: any, name: string): AnimationTrack?
	if m.tracks[name] ~= nil then
		return m.tracks[name] or nil
	end
	local id = nil
	local AL = ctx.AnimLib
	if AL and type(AL.id) == "function" then
		local nm = if name == "dance" then "dance1" else name
		local ok, v = pcall(AL.id, nm, "R15", 1)
		id = if ok then v else nil
	end
	local tr = nil
	if type(id) == "string" and m.animator then
		local a = Instance.new("Animation")
		a.AnimationId = id
		a.Name = "GwFriend_" .. name
		local ok, t = pcall(function()
			return m.animator:LoadAnimation(a)
		end)
		tr = if ok then t else nil
		if tr then
			tr.Looped = name ~= "wave"
		end
	end
	m.tracks[name] = tr or false
	return tr
end

local function play(m: any, name: string)
	if m.anim == name and name ~= "wave" then
		return
	end
	if m.rig then
		if name == "wave" then
			Anim.gesture(m.rig, "wave")
		else
			Anim.base(m.rig, name)
			m.anim = name
		end
		return
	end
	if name ~= "wave" then
		for k, tr in m.tracks do
			if tr and k ~= name and k ~= "wave" then
				tr:Stop(0.25)
			end
		end
		m.anim = name
	end
	local tr = trackFor(m, name)
	if tr then
		tr:Play(0.25)
	end
end

local function spawnFriend(e: any, i: number, at: Vector3): any?
	local folder = workspace:FindFirstChild("GwangalliStreetLife") or workspace
	local m: any = { entry = e, tracks = {}, i = i }
	if e.template then
		local model = e.template:Clone()
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not root or not hum then
			model:Destroy()
			return nil
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
		root.Anchored = true
		model.PrimaryPart = root
		m.model = model
		m.lift = hum.HipHeight + root.Size.Y / 2
		m.animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		tag(model, model:FindFirstChild("Head") :: BasePart?, e.name, 1.6)
	else
		-- placeholder (tests): a roster-style look
		local spec = Looks.random("friend:" .. e.key, { night = clockNow() >= 19 or clockNow() < 5 })
		local rig = Looks.build(spec, { name = "Friend_" .. e.name, shadow = false })
		m.rig = rig
		m.model = rig.model
		m.lift = rig.ground or 3
		tag(rig.model, rig.head or rig.parts.Head, e.name, 1.6)
	end
	m.model.Name = "GwFriend_" .. e.name
	m.model:SetAttribute("GwFriendAvatar", true)
	m.model:SetAttribute("GwRobbable", false)
	m.model:SetAttribute("FriendName", e.name)
	-- placed BEFORE it is parented: a rig parented at the origin and moved later loses its limbs on
	-- the emulator's NPC renderer (the same root cause as the invisible-NPC bug)
	m.model:PivotTo(CFrame.new(at.X, at.Y + m.lift, at.Z))
	m.model.Parent = folder
	if m.rig then
		Anim.setup(m.rig) -- after it is in the Workspace (as GwangalliStreetLife/Pool does)
	end
	m.dance = DANCES[1 + (i - 1) % #DANCES]
	m.waveAt = 0
	return m
end

local function removeFriend(m: any)
	if m.model then
		pcall(m.model.Destroy, m.model)
	end
end

-------------------------------------------------------------------------------------------------
-- the parade
-------------------------------------------------------------------------------------------------
local function spots(clock: number): { any }
	local out = {}
	local test = workspace:GetAttribute("GwangalliFriendAvatarTest") == true
	if test and workspace:GetAttribute("GwangalliFriendAvatarTestHere") == true then
		local pp = playerPos()
		if pp then
			show = show and show.spot.key == "here" and show or nil
			table.insert(out, { key = "here", center = show and show.spot.center or (pp - Vector3.new(0, 3, 0)) })
		end
	end
	if clock >= 19 or clock < 3 then
		local e = Night and Night.clubEntrance and Night.clubEntrance()
		local c = e and (e.hangCenter or e.door)
		if c then
			table.insert(out, { key = "club", center = c })
		end
	end
	if test or (clock >= 17 and clock < 23.5) then
		local p = W and W.areaPos and W.areaPos("plaza")
		if p then
			table.insert(out, { key = "plaza", center = p })
		end
	end
	return out
end

-- a loop of walkable points around the centre (nav nodes, sorted by angle)
local function loopAround(center: Vector3): { Vector3 }
	local pts = {}
	local ok, nodes = pcall(W.nearNodes, center, 20)
	if ok and type(nodes) == "table" then
		for _, n in nodes do
			local p = W.pos[n]
			if p then
				local d = flat(p, center)
				if d > 5 and d < 20 and math.abs(p.Y - center.Y) < 6 then
					table.insert(pts, p)
				end
			end
		end
	end
	if #pts < 4 then
		pts = {}
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			table.insert(pts, center + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9))
		end
	end
	table.sort(pts, function(a, b)
		return math.atan2(a.Z - center.Z, a.X - center.X) < math.atan2(b.Z - center.Z, b.X - center.X)
	end)
	-- thin out to at most 12 evenly spread
	if #pts > 12 then
		local out = {}
		for k = 1, 12 do
			table.insert(out, pts[1 + math.floor((k - 1) * #pts / 12)])
		end
		pts = out
	end
	return pts
end

-- position on the loop at arc length s
local function along(s: number): (Vector3, Vector3)
	local loop, seg = show.loop, show.seg
	s = s % show.total
	for k = 1, #loop do
		local len = seg[k]
		if s <= len or k == #loop then
			local a, b = loop[k], loop[k % #loop + 1]
			local u = if len > 1e-3 then math.clamp(s / len, 0, 1) else 0
			local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			return a:Lerp(b, u), (if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1))
		end
		s -= len
	end
	return loop[1], Vector3.new(0, 0, -1)
end

local function startShow(spot: any)
	local loop = loopAround(spot.center)
	local total = 0
	local seg = {}
	for k = 1, #loop do
		local a, b = loop[k], loop[k % #loop + 1]
		local len = flat(a, b)
		table.insert(seg, len)
		total += len
	end
	show = { spot = spot, loop = loop, seg = seg, total = math.max(total, 1), members = {}, t0 = os.clock(), dist = 0 }
	local n = math.min(Friends.MAX, #entries)
	for i = 1, n do
		local off = (i - 1) / n * show.total
		local at = along(off)
		local m = spawnFriend(entries[i], i, at)
		if m then
			m.offset = off
			table.insert(show.members, m)
		end
	end
end

local function stopShow()
	if not show then
		return
	end
	for _, m in show.members do
		removeFriend(m)
	end
	show = nil
end

local function stepShow(dt: number)
	local now = os.clock()
	local cycle = Friends.MARCH_S + Friends.DANCE_S
	local phase = (now - show.t0) % cycle
	local marching = phase < Friends.MARCH_S
	if marching then
		show.dist += Friends.WALK * dt
	end
	local pp = playerPos()
	local center = show.spot.center
	for _, m in show.members do
		local pos, dir = along(show.dist + m.offset)
		local look = dir
		if not marching then
			-- dance facing the middle (or the player when they are close)
			local to = if pp and flat(pp, pos) < 14 then pp else center
			local v = Vector3.new(to.X - pos.X, 0, to.Z - pos.Z)
			if v.Magnitude > 0.1 then
				look = v.Unit
			end
		end
		local p = Vector3.new(pos.X, pos.Y + m.lift, pos.Z)
		m.model:PivotTo(CFrame.lookAt(p, p + look))
		play(m, if marching then "walk" else m.dance)
		if pp and flat(pp, pos) < Friends.WAVE_R and now > m.waveAt then
			m.waveAt = now + 20
			play(m, "wave")
		end
	end
end

local function step(dt: number)
	if workspace:GetAttribute("GwangalliFriendAvatars") == false then
		stopShow()
		return
	end
	local now = os.clock()
	if now >= nextCheck then
		nextCheck = now + 0.5
		local pp = playerPos()
		local clock = clockNow()
		if show then
			local still = false
			for _, s in spots(clock) do
				if s.key == show.spot.key then
					still = true
				end
			end
			if not still or not pp or flat(pp, show.spot.center) > Friends.FAR then
				stopShow()
			end
		elseif pp and #entries > 0 then
			for _, s in spots(clock) do
				if flat(pp, s.center) < Friends.NEAR then
					startShow(s)
					break
				end
			end
		end
	end
	if show then
		stepShow(dt)
	end
end

function Friends.init(context: any)
	ctx = context
	W = ctx.World
	Night = ctx.Night
	Looks = ctx.Looks
	Anim = ctx.Anim
	task.spawn(function()
		local pg = player:WaitForChild("PlayerGui", 60)
		local f = pg and pg:WaitForChild("GwangalliFriendAvatars", 120)
		if not f then
			return
		end
		rebuildEntries(f)
		f.ChildAdded:Connect(function()
			task.defer(rebuildEntries, f)
		end)
		f.ChildRemoved:Connect(function()
			task.defer(rebuildEntries, f)
		end)
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[GwangalliStreetLife.Friends] " .. tostring(err))
			stopShow()
		end
	end)
end

function Friends.stats(): any
	return { entries = #entries, showing = show and show.spot.key or nil, members = show and #show.members or 0 }
end

return Friends
