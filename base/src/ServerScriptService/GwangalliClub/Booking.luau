-- GwangalliClub/Booking (server): the 합석 이벤트. All-ages social framing: the MD brings 2-4 roster
-- people (adults, mixed, friendly) over to hang out at the player's table - greet, sit, 짠, small
-- talk by affinity tier, dance together, swap numbers (= friends via Relationships), say bye.
--   Booking.stateFor(player, tableId) -> "none" | "available" | "running" | "busy" | "cooldown" | "locked"
--   Booking.request(player, tableId)      the menu's "합석 이벤트" button (tier >= Booking.MinTier)
--   Booking.start(player, tableId, tier, auto)   (BottleService: tier >= AutoTier after the parade)
--   Booking.act(player, kind)             "cheers" | "dance" | "number" | "bye"
-- ONE event at a time in the club. State = folder attribute Booking (JSON):
--   { id, table, owner, name, at, path, y, total, serve, centre, seatedAt, endAt, rev,
--     guests = { { id, name, g, tier, seat = "x,y,z,yaw"?, lines = { arrive, talk = {..}, laugh,
--     dance, bye, number? } } }, act = { kind, at, n, untilT?, results? } }
-- Guest seats get the Seat attribute ClubGuestSeat = endAt (Club.server's sit prompt skips them).

local Booking = {}

local C: any
local S: any
local Citizens: any

local current: any = nil
local serial = 0
local lastBy: { [number]: number } = {} -- UserId -> os.clock() of their last event
local lastAct: { [Player]: number } = {}
local seatsInUse: { Instance } = {}

local function publish()
	if current then
		C.publish(S.Attr.Booking, current)
	else
		C.publish(S.Attr.Booking, { id = 0 })
	end
end

local function clearSeats()
	for _, seat in seatsInUse do
		if seat.Parent then
			seat:SetAttribute(S.Attr.GuestSeat, nil)
		end
	end
	table.clear(seatsInUse)
end

function Booking.stateFor(plr: Player, tableId: string): string
	if current and C.now() < current.endAt then
		if current.table == tableId then
			return "running"
		end
	end
	local t = C.BottleService and C.BottleService.entry(tableId)
	if not t or t.owner ~= plr.UserId then
		return "none"
	end
	if (t.tier or 0) < (S.Booking.MinTier or 3) then
		return "locked"
	end
	if current and C.now() < current.endAt then
		return "busy"
	end
	local last = lastBy[plr.UserId]
	if last and os.clock() - last < (S.Booking.Cooldown or 240) then
		return "cooldown"
	end
	return "available"
end

local function routeFrom(k: number): { Vector3 }
	local pts = C.hook("route")
	local out: { Vector3 } = {}
	if type(pts) == "table" then
		for i = k, #pts do
			if typeof(pts[i]) == "Vector3" then
				table.insert(out, pts[i])
			end
		end
	end
	return out
end

-- "x,y,z,yaw": the seat's TOP surface centre and the way the sitter faces (CFrame.Angles(0, yaw, 0))
local function seatString(cf: CFrame, size: Vector3?): string
	local look = cf.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local top = cf.Position + cf.UpVector * ((if size then size.Y else 1) / 2)
	return string.format("%.2f,%.2f,%.2f,%.3f", top.X, top.Y, top.Z, yaw)
end

function Booking.start(plr: Player, tableId: string, tier: number, auto: boolean?): boolean
	if not Citizens then
		return false
	end
	if current and C.now() < current.endAt then
		if not auto then
			C.send(plr, "booking", { status = "busy", table = tableId })
		end
		return false
	end
	local info = C.hook("tableInfo", tableId)
	if type(info) ~= "table" then
		return false
	end
	local n = if tier >= 5 then 4 elseif tier >= 4 then 3 else 2
	local seed = (os.time() % 100000) + plr.UserId % 1000
	local exclude = {}
	local ids = S.pickGuests(Citizens, n, seed, exclude)
	if #ids == 0 then
		return false
	end
	n = #ids
	local name = C.filteredName(plr)
	local clock = C.clock()
	local B = S.Booking

	-- path: lobby -> hall door -> the turn into the right aisle -> ParadeRoute from WP3 -> table
	local lead: { Vector3 } = {}
	for _, an in { "Show_Lobby", "Show_HallDoor", "Show_HallTurn" } do
		local p = C.anchor(an)
		if p then
			table.insert(lead, p.Position)
		end
	end
	local pts, total = C.pathTo(lead, routeFrom(3), info.serve, C.tableModel(tableId))
	local speed = B.Speed or 5.4
	local now = C.now()
	local at = now + 0.6
	local walk = math.max(0, total - (S.Show.Stand or 3)) / speed + n * (B.Gap or 2.6) / speed
	local arrive = at + (B.Intro or 2.4) + walk
	local seatedAt = arrive + (B.Present or 4.5) + 3
	local endAt = seatedAt + (B.Duration or 150)

	-- seats: the free ones nearest the table centre (standing tables: none -> they stand around it)
	clearSeats()
	local free = {}
	for _, s in info.seats or {} do
		if s.free and typeof(s.cf) == "CFrame" then
			table.insert(free, s)
		end
	end
	table.sort(free, function(a, b)
		return (a.cf.Position - info.centre).Magnitude < (b.cf.Position - info.centre).Magnitude
	end)

	local guests = {}
	for i, id in ids do
		local c = Citizens.byId[id]
		local t = C.social("tier", plr, id)
		t = if type(t) == "number" then math.clamp(t, 1, 5) else 1
		local rnd = Random.new(seed * 7 + i * 131)
		local function r(): number
			return rnd:NextNumber()
		end
		local vars = { name = name }
		local talk = {}
		local okT, l1 = pcall(Citizens.smallTalk, id, t, clock, r, vars)
		table.insert(talk, if okT and type(l1) == "string" then l1 else S.line("talk", t, r(), name))
		table.insert(talk, S.line("talk", t, r(), name))
		local okT2, l2 = pcall(Citizens.smallTalk, id, t, clock, r, vars)
		table.insert(talk, if okT2 and type(l2) == "string" then l2 else S.line("talk", t, r(), name))
		local arriveLine = S.line("arrive", t, r(), name)
		if t >= 2 then
			local okG, g = pcall(Citizens.greeting, id, t, clock, nil, vars, r)
			if okG and type(g) == "string" and g ~= "" then
				arriveLine = g
			end
		end
		local seat = free[i]
		local seatStr = nil
		if seat then
			seatStr = seatString(seat.cf, seat.size)
			if seat.seat and seat.seat.Parent then
				seat.seat:SetAttribute(S.Attr.GuestSeat, endAt)
				table.insert(seatsInUse, seat.seat)
			end
		end
		guests[i] = {
			id = id,
			name = c and c.name or id,
			g = c and c.g or "f",
			tier = t,
			seat = seatStr,
			lines = {
				arrive = arriveLine,
				talk = talk,
				laugh = S.line("laugh", t, r(), name),
				dance = S.line("dance", t, r(), name),
				bye = S.line("bye", t, r(), name),
			},
		}
	end
	serial += 1
	current = {
		id = serial,
		table = tableId,
		owner = plr.UserId,
		name = name,
		md = B.MD or "MD 태양",
		at = at,
		path = C.Club.encodePath(pts),
		y = pts[1].Y,
		total = total,
		serve = { info.serve.X, info.serve.Y, info.serve.Z },
		centre = { info.centre.X, info.centre.Y, info.centre.Z },
		arriveAt = arrive,
		seatedAt = seatedAt,
		endAt = endAt,
		guests = guests,
		act = { kind = "", at = 0, n = 0 },
		rev = 1,
		aa = C.aa(),
	}
	lastBy[plr.UserId] = os.clock()
	publish()
	C.hook("hold", arrive - now + 6) -- no house parade through the aisle during the walk-in
	C.send(plr, "booking", { status = "started", table = tableId, count = n, auto = auto == true })
	local id = serial
	task.delay(math.max(0, arrive - now), function()
		if current and current.id == id and C.isPlayer(plr) then
			C.social("joint", plr, "table", ids)
			C.social("joint", plr, "club", ids)
		end
	end)
	return true
end

function Booking.request(plr: Player, tableId: any)
	if type(tableId) ~= "string" or #tableId > 12 then
		return
	end
	local state = Booking.stateFor(plr, tableId)
	if state ~= "available" then
		C.send(plr, "booking", { status = state, table = tableId })
		return
	end
	if C.hook("reach", plr, tableId, (S.Show.MaxDistance or 18) + 10) ~= true then
		C.send(plr, "booking", { status = "far", table = tableId })
		return
	end
	local t = C.BottleService.entry(tableId)
	Booking.start(plr, tableId, t and t.tier or 3, false)
end

local function ids(): { string }
	local out = {}
	for _, g in current.guests do
		table.insert(out, g.id)
	end
	return out
end

function Booking.act(plr: Player, kind: any)
	if type(kind) ~= "string" or not current or current.owner ~= plr.UserId then
		return
	end
	local now = C.now()
	if now >= current.endAt then
		return
	end
	local clockNow = os.clock()
	if lastAct[plr] and clockNow - lastAct[plr] < 2.5 then
		return
	end
	if now < current.seatedAt - 1 and kind ~= "bye" then
		C.send(plr, "booking", { status = "notyet" })
		return
	end
	if current.act.kind == "dance" and current.act.untilT and now < current.act.untilT and kind ~= "bye" then
		C.send(plr, "booking", { status = "dancing" })
		return
	end
	lastAct[plr] = clockNow
	local act = current.act
	current.flags = current.flags or {}
	if kind == "cheers" then
		current.act = { kind = "cheers", at = now + 0.3, n = (act.n or 0) + 1 }
		if not current.flags.drink then
			current.flags.drink = true
			C.social("joint", plr, "drink", ids())
		end
	elseif kind == "dance" then
		local secs = S.Booking.DanceSeconds or 45
		current.act = { kind = "dance", at = now + 0.3, n = (act.n or 0) + 1, untilT = now + 0.3 + secs }
		current.endAt = math.max(current.endAt, now + secs + 20)
		if not current.flags.dance then
			current.flags.dance = true
			C.social("joint", plr, "dance", ids())
		end
	elseif kind == "number" then
		if current.flags.number then
			C.send(plr, "booking", { status = "numberDone" })
			return
		end
		current.flags.number = true
		local results, lines = {}, {}
		for i, g in current.guests do
			local a = C.social("affinity", plr, g.id)
			a = if type(a) == "number" then a else 0
			local yes = a >= 20 or g.tier >= 2 or ((plr.UserId + i * 37 + current.id) % 3 ~= 0)
			local rnd = Random.new(current.id * 13 + i)
			local okL, line = pcall(Citizens.numberLine, g.id, math.max(g.tier, 2), if yes then "yes" else "no", function()
				return rnd:NextNumber()
			end, { name = current.name })
			results[i] = if yes then "yes" else "no"
			lines[i] = if okL and type(line) == "string" then line else (if yes then "번호 찍어 줄게요! 연락해요 📱" else "번호는 다음에 또 만나면요 ㅎㅎ")
			if yes then
				C.social("award", plr, g.id, "number")
				C.social("giveNumber", plr, g.id, "club") -- Relationships API extension (integration_todo); nil when absent
			end
		end
		current.act = { kind = "number", at = now + 0.3, n = (act.n or 0) + 1, results = results, lines = lines }
	elseif kind == "bye" then
		current.act = { kind = "bye", at = now + 0.3, n = (act.n or 0) + 1 }
		current.endAt = math.min(current.endAt, now + 10)
	else
		return
	end
	current.rev = (current.rev or 0) + 1
	publish()
end

function Booking.tick()
	if current and C.now() >= current.endAt + 1 then
		current = nil
		clearSeats()
		publish()
	end
end

function Booking.onLeave(plr: Player)
	lastAct[plr] = nil
	if current and current.owner == plr.UserId then
		current.act = { kind = "bye", at = C.now(), n = (current.act.n or 0) + 1 }
		current.endAt = math.min(current.endAt, C.now() + 8)
		current.rev = (current.rev or 0) + 1
		publish()
	end
end

function Booking.init(ctx: any)
	C = ctx
	S = ctx.Shared
	Citizens = ctx.Citizens
	publish()
end

return Booking
