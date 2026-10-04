-- GwangalliClubShow/Booking (client): the 합석 이벤트 choreography from the folder attribute Booking.
-- Friends hanging out (all-ages): no romance, no physical contact beyond a wave / bow / cheers.
--   intro    LED wall "✨ 합석 이벤트 · G2 테이블 ✨", the spotlight sweeps to the hall door, the room
--            dims, a swell (flash + swoosh) on the next music beat
--   walk-in  the MD (suit + sunglasses) struts in front, 2-4 guests in club outfits follow on the
--            server's path (lobby -> hall door -> right aisle -> table); sparkle at their feet (+ a
--            light trail on the MD, mid / high tier); the walk clip runs at the strut speed
--   present  a line in front of the table: the MD presents, guests wave + bow, a confetti pop on the
--            beat; then the MD bows out and walks back
--   seats    each guest walks to a free seat, turns, and sits down in one smooth move (root eased
--            from standing to the seat while the sit pose blends in) with a glass in hand
--   hangout  speech bubbles from the roster by affinity tier (server lines), talk / listen gestures,
--            laughs; actions from the owner's card: 짠 (glasses up, clink sparkle), 같이 춤 (they get up
--            and dance in front of the table, then sit again), 번호 교환 (number lines, phone show),
--            잘 가요 (they stand, wave, say bye and walk out); the event ends by itself
-- All timing comes from server times in the record, so every client sees the same moment.

local Players = game:GetService("Players")

local Booking = {}

local C: any
local S: any
local Club: any
local Show: any
local Ui: any
local player = Players.LocalPlayer

local active: any = nil
local WALK = 4.6 -- short walks (spot <-> seat)
local SIT_TIME = 0.7
local TURN_TIME = 0.35
local SIT_HRP = 2.55 -- HumanoidRootPart above the seat top while in the seated pose (block R15, scale 1)

local POSE_SIT: any = nil
local POSE_SIT_CUP: any = nil
local POSE_SIT_CHEERS: any = nil
local POSE_PRESENT_MD = { RightShoulder = { 80, 0, -34 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 18, 0, 10 }, LeftElbow = { 30, 0, 0 }, Waist = { 0, -8, 0 } }

local function merge(a: any, b: any): any
	local out = {}
	for k, v in a or {} do
		out[k] = v
	end
	for k, v in b or {} do
		out[k] = v
	end
	return out
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function v3(t: any): Vector3?
	if type(t) == "table" and type(t[1]) == "number" then
		return Vector3.new(t[1], t[2] or 0, t[3] or 0)
	end
	return nil
end

local function parseSeat(s: any): (Vector3?, number?)
	if type(s) ~= "string" then
		return nil, nil
	end
	local x, y, z, yaw = string.match(s, "^(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)$")
	if not x then
		return nil, nil
	end
	return Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number), tonumber(yaw)
end

local function truncated(pts: { Vector3 }, cum: { number }, d: number): { Vector3 }
	local out: { Vector3 } = {}
	for i, p in pts do
		if cum[i] < d then
			table.insert(out, p)
		else
			break
		end
	end
	local p = S.sample(pts, cum, d)
	table.insert(out, p)
	return out
end

local function reversed(pts: { Vector3 }): { Vector3 }
	local out = {}
	for i = #pts, 1, -1 do
		table.insert(out, pts[i])
	end
	return out
end

local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function mdSpec(): any
	local Looks = C.Looks
	local spec = Looks.resolve({ body = "m", age = "young", style = "suit", night = "suit", hair = "twoblock", hc = "black", acc = "sunglasses", height = 1.04, skin = 2 }, "club_md_taeyang", true)
	table.insert(spec.acc, "earpiece")
	return spec
end

local function feetFx(rec: any, trail: boolean)
	local caps = C.caps()
	local foot = rec.rig.parts and rec.rig.parts.LeftFoot
	if not foot or caps.feet <= 0 then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "Sparkle"
	att.Position = Vector3.new(0, -0.2, 0)
	att.Parent = foot
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = caps.feet
	pe.Lifetime = NumberRange.new(0.35, 0.7)
	pe.Speed = NumberRange.new(0.4, 1.6)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(1, 0.02) })
	pe.Color = ColorSequence.new(Color3.fromRGB(61, 214, 245), Color3.fromRGB(255, 79, 163))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Parent = att
	table.insert(rec.props, att)
	rec.feet = pe
	if trail and caps.trails then
		local rf = rec.rig.parts.RightFoot
		if rf then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, -0.2, 0.25)
			a0.Parent = rf
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.2, -0.25)
			a1.Parent = rf
			local tr = Instance.new("Trail")
			tr.Attachment0 = a0
			tr.Attachment1 = a1
			tr.Lifetime = 0.35
			tr.LightEmission = 1
			tr.Color = ColorSequence.new(Color3.fromRGB(255, 79, 163), Color3.fromRGB(61, 214, 245))
			tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			tr.FaceCamera = true
			tr.Parent = rf
			table.insert(rec.props, a0)
			table.insert(rec.props, a1)
			table.insert(rec.props, tr)
			rec.trail = tr
		end
	end
end

local function feetOff(rec: any)
	if rec.feet then
		rec.feet.Enabled = false
	end
	if rec.trail then
		rec.trail.Enabled = false
	end
end

local function giveGlass(rec: any, aa: boolean)
	local g = C.part("HangGlass", Vector3.new(0.5, 0.26, 0.26), CFrame.new(), Color3.fromRGB(235, 245, 255), Enum.Material.Glass, rec.model, Enum.PartType.Cylinder)
	g.Transparency = 0.45
	C.attach(rec, "RightHand", g, CFrame.new(0, -0.35, -0.12) * CFrame.Angles(0, 0, math.pi / 2))
	local drink = C.part("HangDrink", Vector3.new(0.3, 0.2, 0.2), CFrame.new(), if aa then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(255, 214, 120), Enum.Material.Neon, rec.model, Enum.PartType.Cylinder)
	drink.Transparency = 0.35
	C.attach(rec, "RightHand", drink, CFrame.new(0, -0.3, -0.12) * CFrame.Angles(0, 0, math.pi / 2))
end

local function stop()
	local a = active
	if not a then
		return
	end
	active = nil
	for _, w in a.walkers do
		if w.kill then
			pcall(w.kill)
			w.kill = nil
		end
		if w.rec then
			C.release(w.rec)
			w.rec = nil
		end
	end
	C.removeJob("booking")
	if a.dimmed then
		Show.dim(false)
	end
	if a.spot then
		Show.spotOff()
	end
	Ui.actions(false)
end

-- standing CFrame at a floor point (HRP at the path height) facing dir
local function standCF(a: any, pos: Vector3, dir: Vector3): CFrame
	return C.rootCF(Vector3.new(pos.X, a.y, pos.Z), dir)
end

local function seatedCF(w: any, ground: number): CFrame
	local top = w.seatTop :: Vector3
	return CFrame.new(top + Vector3.new(0, SIT_HRP * (ground / 3), 0)) * CFrame.Angles(0, w.seatYaw, 0)
end

local function start(rec: any)
	stop()
	local pts = Club.decodePath(rec.path, rec.y)
	if not pts then
		return
	end
	if not POSE_SIT then
		local base = (C.Anim.POSES and C.Anim.POSES.sit_bench) or {}
		POSE_SIT = base
		POSE_SIT_CUP = merge(base, { RightShoulder = { 30, 0, -10 }, RightElbow = { 96, 0, 0 } })
		POSE_SIT_CHEERS = merge(base, { RightShoulder = { 128, 0, -16 }, RightElbow = { 40, 0, 0 }, Neck = { 10, 0, 0 } })
	end
	local B = S.Booking
	local cum, total = S.polyline(pts)
	local stopD = math.max(0, total - S.Show.Stand)
	local front, dir = S.sample(pts, cum, stopD)
	local guests = rec.guests or {}
	local n = #guests
	local spots = S.lineup(front, dir, n + 1, 2.4)
	local mid = math.ceil((n + 1) / 2)
	local speed = B.Speed or 5.4
	local walkStart = rec.at + (B.Intro or 2.4)
	local centre = v3(rec.centre) or front
	local a = {
		rec = rec,
		id = rec.id,
		y = rec.y,
		walkers = {},
		events = {},
		front = front,
		centre = centre,
		actN = 0,
		dimmed = false,
		spot = false,
		aa = rec.aa == true,
		mine = rec.owner == player.UserId,
		byeAt = math.huge,
	}
	-- walkers: 1 = the MD (middle spot), then the guests on the remaining spots
	local order = { mid }
	for k = 1, n + 1 do
		if k ~= mid then
			table.insert(order, k)
		end
	end
	local allArrive = walkStart
	for k = 0, n do
		local spot = spots[order[k + 1]]
		local outPts = truncated(pts, cum, stopD)
		table.insert(outPts, spot)
		local oc, ot = S.polyline(outPts)
		local d0 = walkStart + k * (B.Gap or 2.6) / speed
		local w = { k = k, md = k == 0, data = if k > 0 then guests[k] else nil, outPts = outPts, outCum = oc, outTotal = ot, d0 = d0, arrive = d0 + ot / speed, spot = spot, rec = nil, phase = "" }
		allArrive = math.max(allArrive, w.arrive)
		if w.data then
			local top, yaw = parseSeat(w.data.seat)
			if top and yaw then
				w.seatTop, w.seatYaw = top, yaw
				local look = (CFrame.Angles(0, yaw, 0)).LookVector
				w.seatLook = flat(look).Unit
				w.approach = top + w.seatLook * 1.8
			end
		end
		table.insert(a.walkers, w)
	end
	a.allArrive = allArrive
	a.presentEnd = allArrive + (B.Present or 4.5)
	for _, w in a.walkers do
		if w.md then
			w.backPts = reversed(w.outPts)
			w.backCum, w.backTotal = S.polyline(w.backPts)
			w.back0 = a.presentEnd + 0.4
			w.done = w.back0 + w.backTotal / speed
		else
			local gi = w.k
			w.seat0 = a.presentEnd + 0.25 + (gi - 1) * 0.35
			if w.approach then
				w.seatWalk = flat(w.approach - w.spot).Magnitude / WALK
				w.seated = w.seat0 + w.seatWalk + TURN_TIME + SIT_TIME
			else
				w.seated = w.seat0
			end
		end
	end
	a.speed = speed
	active = a
	local title = S.bookingTitle(rec.table)
	local function at(t: number, fn: () -> ())
		table.insert(a.events, { t = t, fn = fn, done = C.now() > t + 1.5 })
	end
	at(rec.at, function()
		Show.led(title, string.format("%s · 새 친구 %d명이 %s님 테이블로!", rec.md or "MD 태양", n, rec.name or "손님"), math.max(5, a.presentEnd - C.now()))
		if C.inside() and not Show.current() then
			Show.dim(true)
			a.dimmed = true
		end
		local door = C.anchor("Show_HallDoor")
		if door then
			Show.spotTo(door.Position, a.y - 3)
			a.spot = true
		end
	end)
	at(walkStart, function()
		C.onBeat(0.5, function()
			Show.pulse()
			if C.nearClub() then
				local door = C.anchor("Show_HallDoor")
				C.sound("rbxasset://sounds/swoosh.wav", 0.32, 0.72, door or nil)
			end
		end)
	end)
	at(allArrive + 0.2, function()
		C.onBeat(0.6, function()
			Show.confetti(a.front, 55, false)
		end)
		C.Bus.playerDanceAt = os.clock()
	end)
	at(a.presentEnd + 1, function()
		if a.spot then
			Show.spotOff()
			a.spot = false
		end
		if a.dimmed then
			Show.dim(false)
			a.dimmed = false
		end
	end)
	C.addJob("booking", function(_dt: number, now: number): boolean
		if active ~= a then
			return false
		end
		local ok, err = pcall(Booking.step, a, now)
		if not ok then
			warn("[GwangalliClubShow] booking:", err)
		end
		return active == a
	end)
end

-- talk schedule while seated: one speaker per slot
local SLOT = 5.5
local function lineFor(w: any, idx: number): string?
	local L = w.data and w.data.lines
	if not L then
		return nil
	end
	if idx == 0 then
		return L.arrive
	end
	local talk = L.talk or {}
	if idx <= #talk then
		return talk[idx]
	end
	if idx == #talk + 1 then
		return L.laugh
	end
	return talk[((idx - 1) % math.max(1, #talk)) + 1]
end

function Booking.step(a: any, now: number)
	local rec = a.rec
	for _, e in a.events do
		if not e.done and now >= e.t then
			e.done = true
			pcall(e.fn)
		end
	end
	if now > (rec.endAt or 0) + 1 then
		stop()
		return
	end
	local near = C.nearClub()
	local speed = a.speed
	local act = rec.act or {}
	-- the auto goodbye before the end
	local byeAt = if act.kind == "bye" then act.at else (rec.endAt or now) - 9
	a.byeAt = byeAt
	local danceOn = act.kind == "dance" and act.untilT and now >= act.at and now < act.untilT + 6
	-- the spotlight follows the MD while walking in
	if a.spot and now >= a.walkers[1].d0 and now < a.allArrive then
		local w = a.walkers[1]
		local p = S.sample(w.outPts, w.outCum, math.clamp((now - w.d0) * speed, 0, w.outTotal))
		Show.spotTo(p, a.y - 3)
	elseif a.spot and now >= a.allArrive then
		Show.spotTo(a.front, a.y - 3)
	end
	-- owner's action card
	if a.mine then
		local names = {}
		for _, w in a.walkers do
			if w.data then
				table.insert(names, w.data.name)
			end
		end
		local numberDone = act.kind == "number" or (rec.flags and rec.flags.number)
		local on = now >= (rec.seatedAt or 0) - 1 and now < byeAt
		local key = tostring(on) .. "|" .. table.concat(names, " · ") .. "|" .. tostring(numberDone == true)
		if key ~= a.uiKey then
			a.uiKey = key
			Ui.actions(on, table.concat(names, " · "), numberDone == true)
		end
	end
	local cam = C.cameraPos()
	for _, w in a.walkers do
		local endT = if w.md then w.done else (w.leaveEnd or math.huge)
		local live = near and now >= w.d0 - 0.4 and now < endT
		if not live then
			if w.rec then
				if w.kill then
					pcall(w.kill)
					w.kill = nil
				end
				C.release(w.rec)
				w.rec = nil
				w.phase = ""
			end
			continue
		end
		local r = w.rec
		if not r then
			r = C.rig(if w.md then mdSpec() else C.guestSpec(w.data.id, w.data.g), if w.md then "ClubShowMD" else ("ClubShowGuest" .. w.k))
			if not r then
				continue
			end
			w.rec = r
			w.phase = ""
			feetFx(r, w.md)
			if not w.md then
				giveGlass(r, a.aa)
			end
		end
		local ctl = r.ctl
		local cf: CFrame
		local phase: string
		local ground = r.ground or 3
		if now < w.d0 then
			cf = standCF(a, w.outPts[1], (w.outPts[2] or w.outPts[1] + Vector3.new(0, 0, 1)) - w.outPts[1])
			phase = "wait"
		elseif now < w.arrive then
			local p, d = S.sample(w.outPts, w.outCum, (now - w.d0) * speed)
			cf = standCF(a, p, d)
			phase = "walk"
		elseif w.md then
			if now < w.back0 then
				cf = standCF(a, w.spot, flat(a.centre - w.spot))
				phase = "present"
			else
				local p, d = S.sample(w.backPts, w.backCum, (now - w.back0) * speed)
				cf = standCF(a, p, d)
				phase = "leave"
			end
		else
			-- guests: present -> seat -> hangout (dance / bye overrides)
			if now >= byeAt then
				-- stand up, wave, walk out the way they came
				if not w.leavePts then
					local from = if w.approach and now >= w.seated then w.approach else w.spot
					w.leaveFrom = from
					local back = reversed(w.outPts)
					back[1] = w.spot
					table.insert(back, 1, from)
					w.leavePts = back
					w.leaveCum, w.leaveTotal = S.polyline(back)
					w.leave0 = byeAt + 2.2 + (w.k - 1) * 0.5
					w.leaveEnd = w.leave0 + w.leaveTotal / speed
					w.wasSeated = w.approach ~= nil and now >= w.seated
				end
				if now < byeAt + 0.6 and w.wasSeated then
					local u = ease((now - byeAt) / 0.6)
					cf = seatedCF(w, ground):Lerp(standCF(a, w.approach, w.seatLook), u)
					phase = "standup"
				elseif now < w.leave0 then
					cf = standCF(a, w.leaveFrom, flat(a.centre - w.leaveFrom))
					phase = "bye"
				else
					local p, d = S.sample(w.leavePts, w.leaveCum, (now - w.leave0) * speed)
					cf = standCF(a, p, d)
					phase = "leave"
				end
			elseif now < w.seat0 then
				cf = standCF(a, w.spot, flat(a.centre - w.spot))
				phase = "present"
			elseif not w.approach then
				cf = standCF(a, w.spot, flat(a.centre - w.spot))
				phase = if danceOn and now < act.untilT then "dance" else "standhang"
			elseif danceOn then
				-- up from the seat, to the spot, dance, back, sit
				local t0 = act.at
				local walkD = math.max(0.05, flat(w.approach - w.spot).Magnitude / WALK)
				local tUp, tSpot = t0 + 0.5, t0 + 0.5 + walkD
				local tBack0 = act.untilT
				local tBack1 = tBack0 + walkD
				if now < tUp then
					cf = seatedCF(w, ground):Lerp(standCF(a, w.approach, w.seatLook), ease((now - t0) / 0.5))
					phase = "standup"
				elseif now < tSpot then
					local p = w.approach:Lerp(w.spot, (now - tUp) / walkD)
					cf = standCF(a, p, w.spot - w.approach)
					phase = "shortwalk"
				elseif now < tBack0 then
					cf = standCF(a, w.spot, flat(a.centre - w.spot))
					phase = "dance"
				elseif now < tBack1 then
					local p = w.spot:Lerp(w.approach, (now - tBack0) / walkD)
					cf = standCF(a, p, w.approach - w.spot)
					phase = "shortwalk"
				elseif now < tBack1 + TURN_TIME then
					local u = ease((now - tBack1) / TURN_TIME)
					cf = standCF(a, w.approach, w.approach - w.spot):Lerp(standCF(a, w.approach, w.seatLook), u)
					phase = "turn"
				else
					local u = ease((now - tBack1 - TURN_TIME) / SIT_TIME)
					cf = standCF(a, w.approach, w.seatLook):Lerp(seatedCF(w, ground), u)
					phase = if u >= 1 then "seated" else "sitdown"
				end
			else
				local tWalk1 = w.seat0 + w.seatWalk
				local tTurn1 = tWalk1 + TURN_TIME
				if now < tWalk1 then
					local p = w.spot:Lerp(w.approach, (now - w.seat0) / math.max(0.05, w.seatWalk))
					cf = standCF(a, p, w.approach - w.spot)
					phase = "shortwalk"
				elseif now < tTurn1 then
					local u = ease((now - tWalk1) / TURN_TIME)
					cf = standCF(a, w.approach, w.approach - w.spot):Lerp(standCF(a, w.approach, w.seatLook), u)
					phase = "turn"
				elseif now < w.seated then
					local u = ease((now - tTurn1) / SIT_TIME)
					cf = standCF(a, w.approach, w.seatLook):Lerp(seatedCF(w, ground), u)
					phase = "sitdown"
				else
					cf = seatedCF(w, ground)
					phase = "seated"
				end
			end
		end
		if phase ~= w.phase then
			local prev = w.phase
			w.phase = phase
			pcall(Booking.enter, a, w, phase, prev)
		end
		-- hangout talk + acts while seated / standing at the table
		if phase == "seated" or phase == "standhang" then
			Booking.hang(a, w, now)
		end
		C.queueMove(r.root, cf)
		if (cam - cf.Position).Magnitude < 110 then
			C.step(ctl)
		end
	end
end

-- one-time changes when a walker enters a phase
function Booking.enter(a: any, w: any, phase: string, prev: string)
	local r = w.rec
	local ctl = r.ctl
	if phase == "walk" then
		ctl:setMoving(a.speed)
		ctl:pose(if w.md then "pockets" else nil, 0.3)
		if r.feet then
			r.feet.Enabled = true
		end
	elseif phase == "present" then
		feetOff(r)
		ctl:setMoving(nil)
		if w.md then
			ctl:pose(POSE_PRESENT_MD, 0.4)
			ctl:emote("beckon")
		else
			ctl:pose(nil, 0.3)
			task.delay(0.2 + w.k * 0.25, function()
				if w.rec == r and w.phase == "present" then
					pcall(function()
						ctl:emote("wave")
					end)
					task.delay(1.9, function()
						if w.rec == r and w.phase == "present" then
							pcall(function()
								ctl:emote("bow")
							end)
						end
					end)
				end
			end)
		end
	elseif phase == "leave" then
		ctl:pose(nil, 0.3)
		ctl:gesture(nil)
		ctl:setMoving(a.speed)
		if w.md and prev == "present" then
			pcall(function()
				ctl:emote("bow")
			end)
		end
	elseif phase == "shortwalk" then
		ctl:pose(nil, 0.3)
		ctl:setAct("idle")
		ctl:setMoving(WALK)
	elseif phase == "turn" then
		ctl:setMoving(nil)
	elseif phase == "sitdown" then
		ctl:setMoving(nil)
		ctl:pose(POSE_SIT_CUP, SIT_TIME * 0.8)
	elseif phase == "seated" then
		ctl:setMoving(nil)
		ctl:pose(POSE_SIT_CUP, 0.2)
		ctl:gesture("listen")
	elseif phase == "standup" then
		ctl:gesture(nil)
		ctl:pose(nil, 0.45)
	elseif phase == "dance" then
		ctl:setMoving(nil)
		ctl:pose(nil, 0.3)
		pcall(function()
			C.Anim.play(r.model, "dance" .. tostring(((w.k - 1) % 3) + 1), { fade = 0.3, offset = true })
		end)
		if w.kill then
			pcall(w.kill)
		end
		local lines = w.data and w.data.lines
		if lines and lines.dance and w.k == 1 then
			w.kill = C.bubble(r.rig.head, lines.dance, 3.5, Color3.fromRGB(61, 214, 245))
		end
	elseif phase == "standhang" then
		ctl:setMoving(nil)
		ctl:pose("cup", 0.3)
		ctl:gesture("listen")
	elseif phase == "bye" then
		ctl:setMoving(nil)
		ctl:pose(nil, 0.3)
		ctl:gesture(nil)
		task.delay(0.15 * w.k, function()
			if w.rec == r then
				pcall(function()
					ctl:emote("wave")
				end)
			end
		end)
		local lines = w.data and w.data.lines
		if lines and lines.bye and w.rec then
			if w.kill then
				pcall(w.kill)
			end
			w.kill = C.bubble(r.rig.head, lines.bye, 2.8, Color3.fromRGB(255, 194, 71))
		end
	end
	if prev == "dance" and phase ~= "dance" then
		for _, n in { "dance1", "dance2", "dance3" } do
			C.Anim.stop(r.model, n, 0.3)
		end
	end
end

-- seated / standing hangout: talk slots, laughs, and the owner's acts (cheers / number)
function Booking.hang(a: any, w: any, now: number)
	local rec = a.rec
	local r = w.rec
	local ctl = r.ctl
	local act = rec.act or {}
	-- acts (each act number is played once per walker)
	if act.n and act.n ~= w.actN and now >= (act.at or 0) then
		w.actN = act.n
		if act.kind == "cheers" then
			local seated = w.phase == "seated"
			pcall(function()
				ctl:pose(if seated then POSE_SIT_CHEERS else { RightShoulder = { 128, 0, -16 }, RightElbow = { 40, 0, 0 } }, 0.25)
			end)
			task.delay(1.6, function()
				if w.rec == r and (w.phase == "seated" or w.phase == "standhang") then
					pcall(function()
						ctl:pose(if w.phase == "seated" then POSE_SIT_CUP else "cup", 0.4)
					end)
				end
			end)
			if w.k == 1 then
				if w.kill then
					pcall(w.kill)
				end
				w.kill = C.bubble(r.rig.head, S.cheersWord(a.aa), 2.4, Color3.fromRGB(255, 194, 71))
				Show.confetti(a.centre + Vector3.new(0, -9, 0), 18, false)
			end
		elseif act.kind == "number" then
			local res = act.results and act.results[w.k]
			local line = act.lines and act.lines[w.k]
			task.delay((w.k - 1) * 1.6, function()
				if w.rec ~= r then
					return
				end
				if line then
					if w.kill then
						pcall(w.kill)
					end
					w.kill = C.bubble(r.rig.head, line, 3.4, if res == "yes" then Color3.fromRGB(61, 220, 132) else Color3.fromRGB(170, 177, 196))
				end
				pcall(function()
					ctl:emote(if res == "yes" then "phone_show" else "shy")
				end)
			end)
			if a.mine and w.k == 1 then
				local got = {}
				for i, g in rec.guests do
					if act.results and act.results[i] == "yes" then
						table.insert(got, g.name)
					end
				end
				task.delay(0.6, function()
					if #got > 0 then
						C.toast("📱 번호 교환 완료", table.concat(got, " · ") .. " · 이제 연락처에서 볼 수 있어요", "📱", "club")
					else
						C.toast("📱 번호는 다음 기회에", "조금 더 친해지면 알려 준대요 ㅎㅎ", "📱", "club")
					end
				end)
			end
		end
	end
	-- talk slots
	local seatedAt = rec.seatedAt or now
	if now < seatedAt then
		return
	end
	local n = #rec.guests
	local slot = math.floor((now - seatedAt) / SLOT)
	if slot ~= w.slot then
		w.slot = slot
		local speaker = (slot % n) + 1
		local idx = math.floor(slot / n)
		if speaker == w.k then
			local line = lineFor(w, idx)
			if line and line ~= "" then
				if w.kill then
					pcall(w.kill)
				end
				w.kill = C.bubble(r.rig.head, line, SLOT - 1.2)
			end
			pcall(function()
				ctl:gesture("talk")
			end)
		else
			pcall(function()
				ctl:gesture("listen")
			end)
			-- a laugh from one listener now and then
			if idx >= 1 and ((slot + w.k) % 3 == 0) then
				task.delay(2.2, function()
					if w.rec == r and (w.phase == "seated" or w.phase == "standhang") then
						pcall(function()
							ctl:emote("laugh_proc")
						end)
					end
				end)
			end
		end
	end
	-- look at the player when close (the table owner, anyone near)
	local root = C.rootPart()
	if root then
		local d = (root.Position - r.root.Position).Magnitude
		pcall(function()
			ctl:look(if d < 22 then root.Position + Vector3.new(0, 1.5, 0) else nil)
		end)
	end
end

function Booking.onBooking(rec: any)
	if type(rec) ~= "table" or type(rec.id) ~= "number" then
		return
	end
	if rec.id == 0 then
		if active and C.now() > (active.rec.endAt or 0) then
			stop()
		end
		return
	end
	if active and active.id == rec.id then
		active.rec = rec -- an act (rev) or a new end time
		return
	end
	if C.now() >= (rec.endAt or 0) then
		return
	end
	local ok, err = pcall(start, rec)
	if not ok then
		warn("[GwangalliClubShow] booking start:", err)
	end
end

function Booking.current(): any?
	return active
end

function Booking.init(core: any, show: any, ui: any)
	C = core
	S = core.S
	Club = core.Club
	Show = show
	Ui = ui
end

return Booking
