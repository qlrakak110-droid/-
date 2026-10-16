-- GwangalliClinic/Queue: 번호표 · 대기열 · 호출 (server-wide, shared by every player).
--   desk queue   번호표 순서 (위급 환자 / 편의 패스는 앞쪽) -> 창구 1 · 2 가 동시에 처리
--   consult queue 접수 끝난 환자 (진료과 표시) -> 진료실 1 (김선생) 이 한 명씩
--   pharmacy     조제 중 / 조제 완료 번호
-- Virtual patients (가상 환자, masked names) keep the clinic alive while a real player is inside; they are
-- served on short timers so a real patient never waits long (Config.Wait / Config.Virtual).
-- Shared state for every client (Configuration GwangalliClinicShared.State):
--   Board = JSON { serving = { w1, w2, c1 }, waiting = { { n, name, st, dept } ... }, counts = { desk,
--           consult, treat, pharm }, depts = { im = n, ... }, doctor, t }
--   Call  = JSON { seq, n, to = "desk" | "consult" | "pharm", win?, name, text, t }
--   Rx    = JSON { cooking = { n ... }, ready = { n ... } }

local Players = game:GetService("Players")

local Queue = {}

local K: any
local S: any
local C: any

type Entry = {
	n: number,
	uid: number,
	player: Player?,
	name: string,
	dept: string,
	prio: boolean,
	pass: boolean,
	virtual: boolean,
	t: number,
	holds: number,
}

local desk: { Entry } = {}
local consult: { Entry } = {}
local windows: { [number]: { entry: Entry?, untilT: number? } } = { [1] = {}, [2] = {} }
local room: { entry: Entry?, untilT: number? } = {}
local rxCooking: { { n: number, uid: number, readyAt: number } } = {}
local rxReady: { { n: number, uid: number, t: number } } = {}
local counter = 0
local callSeq = 0
local boardDirty = true
local treatCount = 0
local nextSpawn = 0
local rng = Random.new()

Queue.callbacks = {
	desk = nil :: ((Player, any, number) -> ())?,
	consult = nil :: ((Player, any) -> ())?,
}

local function now(): number
	return os.clock()
end

local function randIn(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

function Queue.mark()
	boardDirty = true
end

function Queue.ticket(): number
	counter += 1
	if counter > 999 then
		counter = 1
	end
	return counter
end

local function virtualName(): string
	local names = C.Virtual.Names
	return names[rng:NextInteger(1, #names)]
end

local function insert(list: { Entry }, e: Entry)
	-- priority: urgent first (after other urgent), then pass holders ahead of virtual patients
	local pos = #list + 1
	if e.prio then
		pos = 1
		for i, x in list do
			if x.prio then
				pos = i + 1
			end
		end
	elseif e.pass then
		for i, x in list do
			if x.virtual and not x.prio then
				pos = i
				break
			end
		end
	end
	table.insert(list, pos, e)
	boardDirty = true
end

local function removeFrom(list: { Entry }, pred: (Entry) -> boolean): Entry?
	for i, x in list do
		if pred(x) then
			table.remove(list, i)
			boardDirty = true
			return x
		end
	end
	return nil
end

function Queue.joinDesk(player: Player, n: number, prio: boolean, pass: boolean): Entry
	local e: Entry = { n = n, uid = player.UserId, player = player, name = S.mask(player.DisplayName), dept = "", prio = prio, pass = pass, virtual = false, t = now(), holds = 0 }
	insert(desk, e)
	return e
end

function Queue.joinConsult(player: Player, n: number, dept: string, prio: boolean, pass: boolean): Entry
	local e: Entry = { n = n, uid = player.UserId, player = player, name = S.mask(player.DisplayName), dept = dept, prio = prio, pass = pass, virtual = false, t = now(), holds = 0 }
	insert(consult, e)
	return e
end

-- removes the player from every queue / window / room
function Queue.leave(player: Player)
	local uid = player.UserId
	removeFrom(desk, function(x)
		return x.uid == uid and not x.virtual
	end)
	removeFrom(consult, function(x)
		return x.uid == uid and not x.virtual
	end)
	for _, w in windows do
		if w.entry and w.entry.uid == uid and not w.entry.virtual then
			w.entry = nil
			w.untilT = nil
			boardDirty = true
		end
	end
	if room.entry and room.entry.uid == uid and not room.entry.virtual then
		room.entry = nil
		room.untilT = nil
		boardDirty = true
	end
	for i = #rxCooking, 1, -1 do
		if rxCooking[i].uid == uid then
			table.remove(rxCooking, i)
		end
	end
	for i = #rxReady, 1, -1 do
		if rxReady[i].uid == uid then
			table.remove(rxReady, i)
		end
	end
	boardDirty = true
end

function Queue.releaseWindow(w: number)
	local slot = windows[w]
	if slot then
		slot.entry = nil
		slot.untilT = nil
		boardDirty = true
	end
end

function Queue.releaseRoom()
	room.entry = nil
	room.untilT = nil
	boardDirty = true
end

-- a called patient did not come: back one place (returns the hold count)
function Queue.hold(player: Player, which: string): number
	local uid = player.UserId
	local e: Entry? = nil
	if which == "desk" then
		for w, slot in windows do
			if slot.entry and slot.entry.uid == uid and not slot.entry.virtual then
				e = slot.entry
				Queue.releaseWindow(w)
			end
		end
		if e then
			e.holds += 1
			table.insert(desk, math.min(#desk + 1, 2), e)
		end
	else
		if room.entry and room.entry.uid == uid and not room.entry.virtual then
			e = room.entry
			Queue.releaseRoom()
		end
		if e then
			e.holds += 1
			table.insert(consult, math.min(#consult + 1, 2), e)
		end
	end
	boardDirty = true
	return if e then e.holds else 0
end

-- place in line (1 = next) and estimated seconds
function Queue.place(player: Player, which: string): (number, number)
	local list = if which == "desk" then desk else consult
	local uid = player.UserId
	local speed = 1
	for i, x in list do
		if x.uid == uid and not x.virtual then
			speed = if x.pass then C.Pass.WaitFactor else 1
			local W = C.Wait
			local per = if which == "desk" then W.DeskPerAhead else W.ConsultPerAhead
			local busy = 0
			if which == "desk" then
				local anyFree = (windows[1].entry == nil) or (windows[2].entry == nil)
				busy = if anyFree then 0 else 1
			else
				busy = if room.entry then 1 else 0
			end
			local eta = ((i - 1) + busy) * per * speed / (if which == "desk" then 2 else 1) + (if which == "desk" then W.DeskBase else W.ConsultBase)
			return i, math.floor(eta + 0.5)
		end
	end
	return 0, 0
end

function Queue.ahead(which: string): number
	return if which == "desk" then #desk else #consult
end

-------------------------------------------------------------------------------------------------
-- pharmacy board
-------------------------------------------------------------------------------------------------
function Queue.rxSubmit(n: number, uid: number, seconds: number)
	table.insert(rxCooking, { n = n, uid = uid, readyAt = now() + seconds })
	boardDirty = true
end

function Queue.rxCollect(n: number, uid: number)
	for i = #rxReady, 1, -1 do
		if rxReady[i].n == n and rxReady[i].uid == uid then
			table.remove(rxReady, i)
		end
	end
	for i = #rxCooking, 1, -1 do
		if rxCooking[i].n == n and rxCooking[i].uid == uid then
			table.remove(rxCooking, i)
		end
	end
	boardDirty = true
end

function Queue.rxIsReady(n: number, uid: number): boolean
	for _, r in rxReady do
		if r.n == n and r.uid == uid then
			return true
		end
	end
	return false
end

function Queue.setTreatCount(n: number)
	if n ~= treatCount then
		treatCount = n
		boardDirty = true
	end
end

-------------------------------------------------------------------------------------------------
-- announcements
-------------------------------------------------------------------------------------------------
function Queue.announce(to: string, n: number, name: string, win: number?, text: string)
	callSeq += 1
	local st = K.state
	if st then
		st:SetAttribute("Call", S.encode({ seq = callSeq, n = n, to = to, win = win, name = name, text = text, t = S.now() }))
	end
	boardDirty = true
end

local function writeBoard()
	local st = K.state
	if not st then
		return
	end
	local waiting = {}
	if room.entry then
		table.insert(waiting, { n = room.entry.n, name = room.entry.name, st = "진료 중", dept = room.entry.dept })
	end
	for _, e in consult do
		if #waiting >= 8 then
			break
		end
		table.insert(waiting, { n = e.n, name = e.name, st = if e.prio then "응급 우선" else "진료 대기", dept = e.dept })
	end
	for _, e in desk do
		if #waiting >= 8 then
			break
		end
		table.insert(waiting, { n = e.n, name = e.name, st = "접수 대기", dept = "" })
	end
	local depts = {}
	for _, e in consult do
		depts[e.dept] = (depts[e.dept] or 0) + 1
	end
	local board = {
		serving = {
			w1 = windows[1].entry and windows[1].entry.n or nil,
			w2 = windows[2].entry and windows[2].entry.n or nil,
			c1 = room.entry and room.entry.n or nil,
		},
		waiting = waiting,
		counts = { desk = #desk, consult = #consult + (if room.entry then 1 else 0), treat = treatCount, pharm = #rxCooking },
		depts = depts,
		doctor = C.Doctor.name,
		last = counter,
		t = S.now(),
	}
	st:SetAttribute("Board", S.encode(board))
	local cooking, ready = {}, {}
	for _, r in rxCooking do
		table.insert(cooking, r.n)
	end
	for _, r in rxReady do
		table.insert(ready, r.n)
	end
	st:SetAttribute("Rx", S.encode({ cooking = cooking, ready = ready }))
end

-------------------------------------------------------------------------------------------------
-- service loop
-------------------------------------------------------------------------------------------------
local function anyoneInside(): boolean
	for _, p in Players:GetPlayers() do
		if K.Site.playerInZone(p) then
			return true
		end
	end
	return false
end

-- service speed for virtual patients: a waiting pass holder behind makes the line move faster
local function speedOf(list: { Entry }): number
	for _, x in list do
		if not x.virtual and x.pass then
			return C.Pass.WaitFactor
		end
	end
	return 1
end

local function countVirtual(list: { Entry }): number
	local n = 0
	for _, x in list do
		if x.virtual then
			n += 1
		end
	end
	return n
end

local function realValid(e: Entry): boolean
	return e.player ~= nil and (e.player :: Player).Parent == Players
end

local function serveDesk()
	for w = 1, 2 do
		local slot = windows[w]
		if slot.entry and slot.entry.virtual and slot.untilT and now() >= slot.untilT then
			-- virtual patient finished 접수 -> maybe to the consult queue
			local e = slot.entry :: Entry
			slot.entry = nil
			slot.untilT = nil
			boardDirty = true
			if C.Virtual.Enabled and countVirtual(consult) < C.Virtual.MaxConsult and rng:NextNumber() < 0.75 then
				local depts = { "im", "im", "fm", "ped" }
				local v: Entry = { n = e.n, uid = 0, player = nil, name = e.name, dept = depts[rng:NextInteger(1, #depts)], prio = false, pass = false, virtual = true, t = now(), holds = 0 }
				insert(consult, v)
			end
		end
		if not slot.entry and #desk > 0 then
			local e = desk[1]
			if not e.virtual and not realValid(e) then
				table.remove(desk, 1)
				boardDirty = true
			elseif e.virtual or now() - e.t >= C.Wait.DeskBase * (if e.pass then C.Pass.WaitFactor else 1) then
				table.remove(desk, 1)
				slot.entry = e
				boardDirty = true
				local text = string.format("%s번 %s님, %d번 창구로 와 주세요", S.ticket(e.n), e.name, w)
				Queue.announce("desk", e.n, e.name, w, text)
				if e.virtual then
					slot.untilT = now() + randIn(C.Virtual.DeskTime) * speedOf(desk)
					K.Site.setAct("desk" .. w, "beckon", 0)
				else
					slot.untilT = nil
					local cb = Queue.callbacks.desk
					if cb then
						task.spawn(cb, e.player :: Player, e, w)
					end
				end
			end
		end
	end
end

local function serveRoom()
	if room.entry and room.entry.virtual and room.untilT and now() >= room.untilT then
		local e = room.entry :: Entry
		room.entry = nil
		room.untilT = nil
		boardDirty = true
		if rng:NextNumber() < C.Virtual.PharmChance then
			Queue.rxSubmit(e.n, 0, C.Wait.Dispense + rng:NextNumber(0, 4))
		end
	end
	if not room.entry and #consult > 0 then
		local e = consult[1]
		if not e.virtual and not realValid(e) then
			table.remove(consult, 1)
			boardDirty = true
			return
		end
		local base = C.Wait.ConsultBase * (if e.pass then C.Pass.WaitFactor else 1) * (if e.prio then C.Wait.UrgentFactor else 1)
		if e.virtual or now() - e.t >= base then
			table.remove(consult, 1)
			room.entry = e
			boardDirty = true
			local text = string.format("%s번 %s님, %s로 들어오세요", S.ticket(e.n), e.name, C.Doctor.room)
			Queue.announce("consult", e.n, e.name, nil, text)
			if e.virtual then
				room.untilT = now() + randIn(C.Virtual.ConsultTime) * speedOf(consult)
			else
				local cb = Queue.callbacks.consult
				if cb then
					task.spawn(cb, e.player :: Player, e)
				end
			end
		end
	end
end

local function serveRx()
	for i = #rxCooking, 1, -1 do
		local r = rxCooking[i]
		if now() >= r.readyAt then
			table.remove(rxCooking, i)
			table.insert(rxReady, { n = r.n, uid = r.uid, t = now() })
			boardDirty = true
			if r.uid == 0 then
				Queue.announce("pharm", r.n, "", nil, string.format("%s번 환자분, 약 나왔습니다", S.ticket(r.n)))
			end
		end
	end
	for i = #rxReady, 1, -1 do
		local r = rxReady[i]
		if r.uid == 0 and now() - r.t > 14 then
			table.remove(rxReady, i)
			boardDirty = true
		end
	end
end

local function spawnVirtual()
	if not C.Virtual.Enabled or now() < nextSpawn then
		return
	end
	nextSpawn = now() + randIn(C.Virtual.SpawnEvery)
	if not anyoneInside() then
		return
	end
	if countVirtual(desk) >= C.Virtual.MaxDesk then
		return
	end
	local v: Entry = { n = Queue.ticket(), uid = 0, player = nil, name = virtualName(), dept = "", prio = false, pass = false, virtual = true, t = now(), holds = 0 }
	insert(desk, v)
end

function Queue.init(k: any)
	K = k
	S = k.S
	C = S.Config
	counter = rng:NextInteger(18, 38)
end

function Queue.start()
	-- a couple of patients already in line when the first player walks in
	nextSpawn = now() + 4
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.5)
			local ok, err = pcall(function()
				spawnVirtual()
				serveDesk()
				serveRoom()
				serveRx()
			end)
			if not ok then
				warn("[GwangalliClinic] queue:", err)
			end
			acc += 0.5
			if boardDirty and acc >= 0.5 then
				acc = 0
				boardDirty = false
				pcall(writeBoard)
			end
		end
	end)
end

return Queue
