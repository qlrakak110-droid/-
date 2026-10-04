-- GwangalliClub/Show (server): the bottle-service show schedule.
--   Show.start(spec) -> status ("now" | "queued" | "full"), wait seconds
--     spec = { player, item (GwangalliClubShowShared.Menu entry), tableId, onArrive? (fn) }
--   One show at a time; up to Show.MaxQueue wait (FIFO). A show is ONE write of the folder
--   attribute Show (JSON: id, tier, item, table, owner, name, at, staff, path, y, total, endAt,
--   arriveAt, dj, confetti, booking, aa). The staff come out of the staff door (anchor
--   Show_StaffDoor), join the ParadeRoute after WP1 (the house staff wait there) and branch to the
--   table (ClubShared.paradePath). While it runs the house parade is held (ClubShowHook "hold").
--   When the line reaches the table: ClubShowHook "stamp" (ClubLights' sparkler bottles) and the
--   table life entry (BottleService.setTable) take the arrival time.

local Show = {}

local C: any
local S: any -- GwangalliClubShowShared

local current: any = nil -- the running show record
local queue: { any } = {}
local serial = 0

local function routeAfterStart(): { Vector3 }
	local pts = C.hook("route")
	local out: { Vector3 } = {}
	if type(pts) == "table" then
		for i = 2, #pts do -- WP1 is where the house parade staff wait
			if typeof(pts[i]) == "Vector3" then
				table.insert(out, pts[i])
			end
		end
	end
	return out
end

local function build(spec: any): any?
	local plr = spec.player
	local item = spec.item
	local info = C.hook("tableInfo", spec.tableId)
	if type(info) ~= "table" or typeof(info.serve) ~= "Vector3" then
		return nil
	end
	local door = C.anchor("Show_StaffDoor")
	local lead: { Vector3 } = {}
	if door then
		table.insert(lead, door.Position)
	end
	local route = routeAfterStart()
	if #lead == 0 and #route == 0 then
		return nil
	end
	local pts, total = C.pathTo(lead, route, info.serve, C.tableModel(spec.tableId))
	serial += 1
	local aa = C.aa()
	local now = C.now()
	local rec = {
		id = serial,
		tier = item.tier,
		item = item.id,
		label = S.label(item, aa),
		table = spec.tableId,
		owner = plr.UserId,
		name = C.filteredName(plr),
		staff = math.clamp(item.staff or 1, 1, 5),
		path = C.Club.encodePath(pts),
		y = pts[1].Y,
		total = total,
		dj = item.dj == true,
		confetti = item.confetti == true,
		booking = item.booking == true,
		aa = aa,
		at = 0,
		arriveAt = 0,
		endAt = 0,
		serve = { info.serve.X, info.serve.Y, info.serve.Z },
	}
	rec._spec = spec
	return rec
end

local function arrival(rec: any): number
	local P = S.Show
	local speed = if rec.tier <= 1 then P.BasicSpeed else P.Speed
	local walk = math.max(0, rec.total - P.Stand) / speed
	return rec.at + P.LeadIn + walk + (rec.staff - 1) * P.Gap / speed
end

local function begin(rec: any)
	local now = C.now()
	rec.at = now + 0.4 -- clients start the dim / LED a beat after the attribute lands
	rec.endAt = rec.at + S.showLength(rec.total, rec.staff, rec.tier)
	rec.arriveAt = arrival(rec)
	current = rec
	local spec = rec._spec
	local publishRec = table.clone(rec)
	publishRec._spec = nil
	C.publish(S.Attr.Show, publishRec)
	C.hook("hold", rec.endAt - now + 4)
	-- the table: busy for the old Club.server order flow, bottles + props at the arrival
	C.hook("markBusy", rec.table, rec.endAt)
	if rec.tier >= 2 then
		C.hook("stamp", rec.table, rec.arriveAt, rec.owner)
	end
	if C.BottleService then
		C.BottleService.setTable(spec.player, rec.table, spec.item, rec.arriveAt)
	end
	local id = rec.id
	task.delay(math.max(0, rec.arriveAt - now), function()
		if current and current.id == id then
			if spec.onArrive then
				pcall(spec.onArrive, rec)
			end
		end
	end)
end

function Show.start(spec: any): (string, number)
	if current and C.now() < current.endAt then
		if #queue >= (S.Show.MaxQueue or 3) then
			return "full", 0
		end
		table.insert(queue, spec)
		local wait = current.endAt - C.now()
		for i = 1, #queue - 1 do
			local q = queue[i]
			wait += S.showLength(60, math.clamp(q.item.staff or 1, 1, 5), q.item.tier)
		end
		return "queued", math.max(0, wait)
	end
	local rec = build(spec)
	if not rec then
		return "error", 0
	end
	begin(rec)
	return "now", 0
end

function Show.queueFull(): boolean
	return Show.busy() and #queue >= (S.Show.MaxQueue or 3)
end

function Show.current(): any?
	return current
end

function Show.busy(): boolean
	return current ~= nil and C.now() < current.endAt
end

function Show.tick()
	if current and C.now() >= current.endAt then
		current = nil
	end
	if not current and #queue > 0 then
		local spec = table.remove(queue, 1)
		if spec and C.isPlayer(spec.player) then
			local rec = build(spec)
			if rec then
				begin(rec)
				C.toast(spec.player, "보틀 서비스 출발! ✨", string.format("%s 테이블로 스태프가 가고 있어요", spec.tableId), "🍾")
			end
		end
	end
end

function Show.onLeave(plr: Player)
	for i = #queue, 1, -1 do
		if queue[i].player == plr then
			table.remove(queue, i)
		end
	end
end

function Show.init(ctx: any)
	C = ctx
	S = ctx.Shared
	C.publish(S.Attr.Show, { id = 0 })
end

return Show
