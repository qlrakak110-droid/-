-- GwangalliClubShow/Door (client): the CLUB OCEAN closed door, from this player's side.
--   * Barriers (club_front: ClubDoorBarrier*, one invisible collider per street opening) are turned
--     off LOCALLY while the player wears a valid wristband (ClubOceanWristbandUntil > server time),
--     so only paying players walk through; the server still walks anyone inside without one back out.
--   * The black-glass sliding leaves glide into the jambs (one TweenService CFrame tween per slider;
--     the leaf parts are welded to it) when a wristband holder comes close, after paying (the bouncer
--     waves you in), or when a street-life guest walks in from the queue (visual only: the barrier
--     stays for an unpaid player); they close CloseDelay seconds after the last person passed.
--   * The head bouncer is a local rig at ClubBouncerPost (GwangalliNPCLooks suit + earpiece):
--     arms crossed idle and a head turn toward you; nod + step aside + "after you" when you pay;
--     the 'stop' hand when you walk up to the closed door without a wristband.
--   * The velvet rope in front of the door unhooks (local) while the door is open.
-- Cost: a 0.15 s state loop near the club (nothing far away); the bouncer's procedural layer is
-- stepped by the Core driver only while the camera is within 70 studs.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Door = {}

local C: any
local S: any
local player = Players.LocalPlayer

local st: any = {
	model = nil :: Instance?,
	barriers = {} :: { BasePart },
	main = nil :: BasePart?,
	sliders = {} :: { any },
	ropeClosed = {} :: { BasePart },
	ropeOpen = nil :: BasePart?,
	post = nil :: BasePart?,
	inward = Vector3.new(1, 0, 0),
	open = false,
	closeAt = 0,
	scriptedUntil = 0, -- os.clock(): the door stays open for the welcome
	npcUntil = 0,
	lastNpcScan = 0,
	lastStop = 0,
	lastNod = 0,
	bouncer = nil :: any,
	home = nil :: CFrame?,
	move = nil :: any, -- { from, to, t0, dur, face }
	state = "idle",
	stateUntil = 0,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function bind(model: Instance)
	if st.model == model then
		return
	end
	st.model = model
	table.clear(st.barriers)
	table.clear(st.sliders)
	table.clear(st.ropeClosed)
	st.main, st.ropeOpen, st.post = nil, nil, nil
	local inward = model:GetAttribute("Inward")
	if typeof(inward) == "Vector3" and inward.Magnitude > 0.1 then
		st.inward = flat(inward).Unit
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = d.Name
			if string.sub(n, 1, 15) == "ClubDoorBarrier" then
				table.insert(st.barriers, d)
				if n == "ClubDoorBarrier" then
					st.main = d
				end
			elseif string.sub(n, 1, 15) == "ClubDoorSlider_" then
				local slide = d:GetAttribute("Slide")
				if type(slide) == "number" then
					table.insert(st.sliders, { part = d, closed = d.CFrame, open = d.CFrame * CFrame.new(slide, 0, 0) })
				end
			elseif n == "ClubRopeClosed" then
				table.insert(st.ropeClosed, d)
			elseif n == "ClubRopeOpen" then
				st.ropeOpen = d
			elseif n == "ClubBouncerPost" then
				st.post = d
			end
		end
	end
end

local function setOpen(on: boolean, quiet: boolean?)
	if st.open == on then
		return
	end
	st.open = on
	local t = S.Door.SlideTime or 0.75
	for _, s in st.sliders do
		if s.part.Parent then
			C.tween(s.part, t, { CFrame = if on then s.open else s.closed }, if on then Enum.EasingStyle.Quint else Enum.EasingStyle.Sine, if on then Enum.EasingDirection.Out else Enum.EasingDirection.InOut)
		end
	end
	for _, r in st.ropeClosed do
		C.tween(r, 0.25, { Transparency = if on then 1 else 0 }, Enum.EasingStyle.Quad)
	end
	if st.ropeOpen then
		C.tween(st.ropeOpen, 0.25, { Transparency = if on then 0 else 1 }, Enum.EasingStyle.Quad)
	end
	if not quiet and st.main then
		local root = C.rootPart()
		if root and (root.Position - st.main.Position).Magnitude < 40 then
			C.sound("rbxasset://sounds/swoosh.wav", 0.18, if on then 0.62 else 0.5, st.main)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Bouncer
---------------------------------------------------------------------------------------------------
local function bouncerSpec(): any
	local Looks = C.Looks
	local spec = Looks.resolve({ body = "m", age = "adult", style = "black", night = "suit", build = "broad", height = 1.07, hair = "buzz", hc = "black", skin = 3, acc = "earpiece" }, "club_ocean_head_bouncer", true)
	return spec
end

local function homeCF(): CFrame?
	local post = st.post
	if not post or not post.Parent then
		return nil
	end
	local ground = post.Position.Y - post.Size.Y / 2
	local look = flat(post.CFrame.LookVector)
	local base = Vector3.new(post.Position.X, ground, post.Position.Z)
	return CFrame.lookAt(base, base + (if look.Magnitude > 0.1 then look.Unit else -st.inward))
end

local function ensureBouncer()
	if st.bouncer then
		return
	end
	local home = homeCF()
	if not home then
		return
	end
	local rec = C.rig(bouncerSpec(), "ClubHeadBouncer")
	if not rec then
		return
	end
	st.bouncer = rec
	st.home = home
	st.state = "idle"
	rec.root.CFrame = home * CFrame.new(0, rec.ground, 0)
	pcall(function()
		rec.ctl:setAct("arms_crossed")
	end)
end

local function releaseBouncer()
	if st.bouncer then
		C.release(st.bouncer)
		st.bouncer = nil
		st.move = nil
		C.removeJob("doorBouncer")
	end
end

local function moveTo(to: CFrame, dur: number)
	local b = st.bouncer
	if not b then
		return
	end
	st.move = { from = b.root.CFrame, to = to, t0 = os.clock(), dur = dur }
end

local function faceCF(at: CFrame, target: Vector3): CFrame
	local p = at.Position
	local d = flat(target - p)
	if d.Magnitude < 0.1 then
		return at
	end
	return CFrame.lookAt(p, p + d.Unit)
end

-- per-frame (driver job): movement lerp + procedural step while the camera is close
local function bouncerJob(_dt: number, _now: number): boolean
	local b = st.bouncer
	if not b or b.released then
		return false
	end
	local m = st.move
	if m then
		local a = math.clamp((os.clock() - m.t0) / m.dur, 0, 1)
		local e = a * a * (3 - 2 * a)
		C.queueMove(b.root, m.from:Lerp(m.to, e))
		pcall(b.ctl.setMoving, b.ctl, if a < 1 and (m.from.Position - m.to.Position).Magnitude > 0.3 then 3.2 else nil)
		if a >= 1 then
			st.move = nil
		end
	end
	C.step(b.ctl)
	return true
end

local function bouncerHomeRoot(): CFrame?
	local b = st.bouncer
	if not b or not st.home then
		return nil
	end
	return st.home * CFrame.new(0, b.ground, 0)
end

-- the paying player is waved in: nod, step aside toward the jamb, turn to the door, "after you"
function Door.welcome()
	st.scriptedUntil = os.clock() + 5.5
	local b = st.bouncer
	local home = bouncerHomeRoot()
	if not b or not home or not st.main then
		return
	end
	st.state = "aside"
	st.stateUntil = os.clock() + 7
	pcall(function()
		b.ctl:look(nil)
		b.ctl:emote("nod")
	end)
	task.delay(0.55, function()
		if st.bouncer ~= b then
			return
		end
		-- one step back and to the side (toward the jamb), facing the door centre
		local side = flat(st.main.Position - home.Position)
		local away = if side.Magnitude > 0.1 then -side.Unit else Vector3.zero
		local aside = home + away * 1.7 + st.inward * 0.8
		moveTo(faceCF(aside, Vector3.new(st.main.Position.X, aside.Y, st.main.Position.Z) - st.inward * 3), 0.7)
		pcall(function()
			b.ctl:setAct("idle")
		end)
		task.delay(0.8, function()
			if st.bouncer == b then
				pcall(function()
					b.ctl:emote("beckon")
				end)
			end
		end)
	end)
	task.delay(7, function()
		if st.bouncer == b and st.state == "aside" then
			st.state = "idle"
			local h = bouncerHomeRoot()
			if h then
				moveTo(h, 0.8)
			end
			pcall(function()
				b.ctl:setAct("arms_crossed")
			end)
		end
	end)
end

-- 'stop' hand toward a position (an unpaid player at the closed door / just walked back out)
function Door.stop(at: Vector3?)
	local b = st.bouncer
	local home = bouncerHomeRoot()
	if not b or not home or st.state == "aside" then
		return
	end
	st.state = "stop"
	local target = at or (home.Position - st.inward * 6)
	moveTo(faceCF(home * CFrame.new(0, 0, -0.5), target), 0.35)
	pcall(function()
		b.ctl:setAct("idle")
		b.ctl:look(target + Vector3.new(0, 1.5, 0))
		b.ctl:emote("stop_hand")
	end)
	task.delay(1.6, function()
		if st.bouncer == b and st.state == "stop" then
			st.state = "idle"
			local h = bouncerHomeRoot()
			if h then
				moveTo(h, 0.5)
			end
			pcall(function()
				b.ctl:setAct("arms_crossed")
			end)
		end
	end)
end

function Door.nod()
	local b = st.bouncer
	if b and st.state == "idle" and os.clock() - st.lastNod > 3 then
		st.lastNod = os.clock()
		pcall(function()
			b.ctl:emote("nod")
		end)
	end
end

function Door.bouncerPart(): BasePart?
	local b = st.bouncer
	return if b then b.rig.head else nil
end

---------------------------------------------------------------------------------------------------
-- State loop
---------------------------------------------------------------------------------------------------
local function scanNpcs(doorOut: Vector3)
	local f = workspace:FindFirstChild("GwangalliStreetLife")
	if not f then
		return
	end
	for _, m in f:GetChildren() do
		if m:IsA("Model") then
			local pp = m.PrimaryPart
			if pp and flat(pp.Position - doorOut).Magnitude < 5 then
				st.npcUntil = os.clock() + 2.4
				Door.nod()
				return
			end
		end
	end
end

local function update()
	if not st.model or not st.model.Parent then
		return
	end
	local now = C.now()
	local valid = S.wristbandValid(player:GetAttribute(S.Attr.WristbandUntil), now)
	local free = workspace:GetAttribute("GwangalliClubFreeEntry") == true or S.Door.Enabled == false
	local pass = valid or free
	for _, b in st.barriers do
		if b.Parent and b.CanCollide == pass then
			b.CanCollide = not pass
		end
	end
	local main = st.main
	if not main then
		return
	end
	local center = main.Position
	local camDist = (C.cameraPos() - center).Magnitude
	if camDist < (S.Door.BouncerRadius or 140) then
		ensureBouncer()
	else
		releaseBouncer()
	end
	local b = st.bouncer
	if b then
		if camDist < 70 then
			if not C.hasJob("doorBouncer") then
				C.addJob("doorBouncer", bouncerJob)
			end
		elseif st.move == nil then
			C.removeJob("doorBouncer")
		end
	end
	if camDist > 160 then
		return
	end
	local root = C.rootPart()
	local dist = if root then flat(root.Position - center).Magnitude else math.huge
	local outside = root ~= nil and (root.Position - center):Dot(st.inward) < 0
	-- street-life guests entering from the queue (night only; visual)
	if C.isNight() and camDist < 90 and os.clock() - st.lastNpcScan > 0.5 then
		st.lastNpcScan = os.clock()
		scanNpcs(center - st.inward * 1.8)
	end
	local clockNow = os.clock()
	local want = (pass and dist < (S.Door.OpenRadius or 8.5)) or clockNow < st.scriptedUntil or clockNow < st.npcUntil
	if want then
		st.closeAt = clockNow + (S.Door.CloseDelay or 1.4)
		setOpen(true)
	elseif st.open and clockNow > st.closeAt then
		setOpen(false)
	end
	-- an unpaid player walking up to the closed door: the bouncer's hand + a hint
	if not pass and root and outside and dist < (S.Door.StopRadius or 4.2) and clockNow - st.lastStop > 6 then
		st.lastStop = clockNow
		Door.stop(root.Position)
		local fee = S.doorFee(now)
		C.toast("입장 팔찌가 필요해요 🖐️", string.format("가드에게 '입장하기' · 오늘 입장료 %s", C.won(fee)), "🖐️", "warn")
	end
	-- the idle bouncer keeps an eye on a player close by
	if b and st.state == "idle" and root then
		local d = (root.Position - b.root.Position).Magnitude
		pcall(function()
			b.ctl:look(if d < 16 then root.Position + Vector3.new(0, 1.5, 0) else nil)
		end)
	end
end

function Door.init(core: any)
	C = core
	S = core.S
	local tag = S.Tags.Door
	for _, m in CollectionService:GetTagged(tag) do
		bind(m)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(update)
			if not ok then
				warn("[GwangalliClubShow] door:", err)
				task.wait(2)
			end
		end
	end)
	-- a respawn / teleport leaves the door closed behind
	player.CharacterAdded:Connect(function()
		st.scriptedUntil = 0
	end)
end

-- debug / sim: current state
function Door.state(): any
	return { open = st.open, barriers = #st.barriers, bouncer = st.bouncer ~= nil, state = st.state }
end

return Door
