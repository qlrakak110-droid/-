-- GwangalliClubPlus.Dj: 게스트 DJ 타임 (server). One DJ at a time: a queue (Config.DJ.MaxQueue),
-- turns of Config.DJ.TurnSeconds, optional fee (refunded when the turn never happens), admins (place
-- owner, Config.DJ.Admins, group rank) can skip / clear. The DJ's pad (레이저 쇼 / CO2 / 폭죽 / 스트로브 /
-- 손 머리 위로 / LED 문구) works only within Config.DJ.BoothRadius of the booth, with per-pad cooldowns;
-- pad cues go to every client as Event "fx" (world effects, beat-quantised there), LED text goes
-- through the TextService broadcast filter and the Stage timeline. Public state: folder attribute DJ.

local Dj = {}

local C: any
local S: any
local cfg: any
local L: any

type Turn = { p: Player, u: number, n: string, at: number, untilT: number, arrived: boolean, pads: { [string]: number }, lastPad: number, lastGoto: number }
type Entry = { p: Player, u: number, n: string, paid: number }

local current: Turn? = nil
local queue: { Entry } = {}
local againAt: { [number]: number } = {}
local busy: { [Player]: boolean } = {}

local function publish()
	local q = {}
	for i, e in queue do
		if i > 6 then
			break
		end
		table.insert(q, { u = e.u, n = e.n })
	end
	local cur = current
	C.publish(S.Attr.DJ, {
		on = cur ~= nil,
		u = cur and cur.u or 0,
		n = cur and cur.n or "",
		at = cur and math.floor(cur.at * 10) / 10 or 0,
		untilT = cur and math.floor(cur.untilT * 10) / 10 or 0,
		queue = q,
		count = #queue,
	})
end

local function queueIndex(uid: number): number?
	for i, e in queue do
		if e.u == uid then
			return i
		end
	end
	return nil
end

function Dj.stateFor(p: Player): any
	local now = os.clock()
	local cur = current
	local pads = {}
	if cur and cur.p == p then
		for _, pad in cfg.Pads do
			pads[pad.id] = math.max(0, pad.cooldown - (now - (cur.pads[pad.id] or -1e9)))
		end
	end
	return {
		enabled = cfg.Enabled,
		on = cur ~= nil,
		me = cur ~= nil and cur.p == p,
		u = cur and cur.u or 0,
		n = cur and cur.n or "",
		untilT = cur and cur.untilT or 0,
		pos = queueIndex(p.UserId),
		count = #queue,
		price = cfg.Price,
		turn = cfg.TurnSeconds,
		again = math.max(0, (againAt[p.UserId] or 0) - now),
		admin = C.isAdmin(p),
		cooldowns = pads,
	}
end

local function notify(p: Player?)
	if p and C.isPlayer(p) then
		C.send(p, "dj", Dj.stateFor(p))
	end
end
local function notifyAll()
	if current then
		notify(current.p)
	end
	for _, e in queue do
		notify(e.p)
	end
end

function Dj.current(): any?
	local cur = current
	if cur then
		return { u = cur.u, n = cur.n, untilT = cur.untilT }
	end
	return nil
end

local function boothPos(): Vector3
	local a = C.anchor("Show_DJ")
	return if a then a.Position else S.Config.Fallback.DJ
end
local function nearBooth(p: Player): boolean
	local r = C.root(p)
	if not r then
		return false
	end
	local b = boothPos()
	local d = Vector3.new(r.Position.X - b.X, 0, r.Position.Z - b.Z).Magnitude
	return d <= cfg.BoothRadius and math.abs(r.Position.Y - b.Y) < 12
end

local function refund(e: Entry, why: string)
	if e.paid > 0 and C.isPlayer(e.p) then
		task.spawn(function()
			if C.refund(e.p, e.paid, "CLUB OCEAN DJ 신청비 환불") then
				C.toast(e.p, L.DJ.refund, "money", "💰", why)
			end
		end)
	end
end

local startNext: () -> ()

local function endTurn(reason: string)
	local cur = current
	if not cur then
		return
	end
	current = nil
	againAt[cur.u] = os.clock() + cfg.AgainCooldown
	if C.isPlayer(cur.p) then
		if reason == "skipped" then
			C.toast(cur.p, L.DJ.skipped, "warn", "🎧")
		else
			C.toast(cur.p, L.DJ.ended, "club", "🎧")
			if cur.arrived then
				C.addStats(cur.p, { happiness = 4, popularity = 3 }, "CLUB OCEAN 게스트 DJ 🎧")
			end
		end
		notify(cur.p)
	end
	C.broadcast("fx", { kind = "djoff", at = C.now(), u = cur.u, n = cur.n })
	publish()
	startNext()
end

function startNext()
	if current then
		return
	end
	while #queue > 0 do
		local e = table.remove(queue, 1) :: Entry
		if C.isPlayer(e.p) then
			local now = C.now()
			current = {
				p = e.p,
				u = e.u,
				n = e.n,
				at = now,
				untilT = now + cfg.TurnSeconds,
				arrived = C.Bridge.inClub(e.p),
				pads = {},
				lastPad = 0,
				lastGoto = 0,
			}
			C.toast(e.p, L.DJ.turn, "club", "🎧", math.floor(cfg.TurnSeconds / 60))
			C.Stage.push("djon", S.Durations.djon, 3, { u = e.u, n = e.n, un = e.p.Name }, e.u, true)
			C.Stage.ticker("dj", e.n, string.format(L.Ticker.dj, e.n), nil)
			C.broadcast("fx", { kind = "djon", at = now + 0.3, u = e.u, n = e.n })
			if queue[1] then
				C.toast(queue[1].p, L.DJ.soon, "club", "🎧")
			end
			break
		end
	end
	publish()
	notifyAll()
end

local function doJoin(p: Player)
	if not cfg.Enabled then
		C.toast(p, S.Lines.Receipt.off, "warn")
		return
	end
	if not (C.gate(p)) then
		C.toast(p, S.Lines.Receipt.gate, "warn", "🎧")
		return
	end
	if (current and current.p == p) or queueIndex(p.UserId) then
		C.toast(p, L.DJ.already, "info", "🎧")
		return
	end
	local wait = (againAt[p.UserId] or 0) - os.clock()
	if wait > 0 then
		C.toast(p, L.DJ.again, "warn", "🎧", math.ceil(wait))
		return
	end
	if #queue >= cfg.MaxQueue then
		C.toast(p, L.DJ.full, "warn", "🎧")
		return
	end
	local function enqueue(paid: number)
		if not C.isPlayer(p) then
			return
		end
		table.insert(queue, { p = p, u = p.UserId, n = C.filteredName(p), paid = paid })
		C.toast(p, L.DJ.joined, "club", "🎧", #queue)
		publish()
		if not current then
			startNext()
		else
			notifyAll()
		end
	end
	if cfg.Price > 0 and C.hasWallet() then
		busy[p] = true
		local settled = false
		C.charge(p, cfg.Price, "CLUB OCEAN 게스트 DJ 신청", function(status: string)
			if status == "paid" then
				settled = true
				busy[p] = nil
				C.toast(p, L.DJ.paid, "money", "🎧", S.won(cfg.Price))
				enqueue(cfg.Price)
			elseif status == "paid-late" then
				-- paid after the timeout: give the money back (the player was told it failed)
				refund({ p = p, u = p.UserId, n = "", paid = cfg.Price }, "결제가 늦게 확인됐어요")
			elseif not settled then
				settled = true
				busy[p] = nil
				if status == "declined" then
					C.toast(p, S.Lines.Receipt.nofunds, "warn")
				elseif status == "timeout" then
					C.toast(p, S.Lines.Receipt.error, "warn")
				else
					C.toast(p, S.Lines.Receipt.error, "warn")
				end
			end
		end)
	else
		enqueue(0)
	end
end

local function doLeave(p: Player)
	if current and current.p == p then
		endTurn("left")
		return
	end
	local i = queueIndex(p.UserId)
	if i then
		local e = table.remove(queue, i) :: Entry
		refund(e, "대기열에서 나왔어요")
		C.toast(p, L.DJ.left, "info", "🎧")
		publish()
		notifyAll()
		notify(p)
	end
end

local function doGoto(p: Player)
	local cur = current
	if not cur or cur.p ~= p then
		C.toast(p, L.DJ.notDj, "warn", "🎧")
		return
	end
	if os.clock() - cur.lastGoto < 5 or not (C.gate(p)) then
		return
	end
	local r = C.root(p)
	if not r then
		return
	end
	cur.lastGoto = os.clock()
	local spot = boothPos() + S.Config.Fallback.DJSpotOffset
	local wall = C.anchor("Show_LEDWall")
	local look = if wall then wall.CFrame.LookVector else Vector3.new(-1, 0, 0)
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(-1, 0, 0)
	end
	local ch = p.Character
	if ch then
		pcall(function()
			ch:PivotTo(CFrame.lookAt(spot, spot + look.Unit))
		end)
	end
end

local function doPad(p: Player, padId: any, text: any)
	local cur = current
	if not cur or cur.p ~= p then
		C.toast(p, L.DJ.notDj, "warn", "🎧")
		return
	end
	local pad = S.pad(padId)
	if not pad then
		return
	end
	if not nearBooth(p) then
		C.toast(p, L.DJ.far, "warn", "🎧")
		return
	end
	local t = os.clock()
	local left = pad.cooldown - (t - (cur.pads[pad.id] or -1e9))
	if left > 0 then
		C.toast(p, L.DJ.cool, "info", pad.icon, math.ceil(left))
		return
	end
	if t - cur.lastPad < cfg.PadGap then
		return
	end
	if pad.id == "text" then
		local clean = S.cleanText(text, cfg.TextMax)
		if not clean then
			C.toast(p, S.Lines.Receipt.filter, "warn")
			return
		end
		cur.pads[pad.id] = t -- (the cooldown starts before the yield: no double sends)
		cur.lastPad = t
		local filtered = C.filterText(p, clean)
		if not filtered then
			cur.pads[pad.id] = nil
			C.toast(p, S.Lines.Receipt.filter, "warn")
			return
		end
		if current ~= cur then
			return
		end
		C.Stage.push("dj", S.Durations.dj, 2, { u = cur.u, n = cur.n, t = filtered }, cur.u, true)
	else
		cur.pads[pad.id] = t
		cur.lastPad = t
		C.broadcast("fx", { kind = pad.id, at = C.now() + 0.25, u = cur.u, n = cur.n })
	end
	notify(p)
end

local function doAdmin(p: Player, op: any)
	if not C.isAdmin(p) then
		C.toast(p, L.DJ.noAdmin, "warn")
		return
	end
	if op == "skip" then
		endTurn("admin")
		C.toast(p, L.DJ.admin, "info", "🛠️", "다음 DJ로 넘겼어요")
	elseif op == "clear" then
		for _, e in queue do
			refund(e, "관리자가 대기열을 비웠어요")
			notify(e.p)
		end
		table.clear(queue)
		publish()
		C.toast(p, L.DJ.admin, "info", "🛠️", "DJ 대기열을 비웠어요")
	elseif op == "stop" then
		for _, e in queue do
			refund(e, "관리자가 DJ 타임을 멈췄어요")
			notify(e.p)
		end
		table.clear(queue)
		endTurn("admin")
		C.toast(p, L.DJ.admin, "info", "🛠️", "DJ 타임을 멈췄어요")
	end
	notify(p)
end

function Dj.request(p: Player, payload: { [string]: any })
	if busy[p] then
		return
	end
	local op = payload.op
	if op == "join" then
		doJoin(p)
	elseif op == "leave" then
		doLeave(p)
	elseif op == "goto" then
		doGoto(p)
	elseif op == "pad" then
		doPad(p, payload.pad, payload.text)
	elseif op == "admin" then
		doAdmin(p, payload.admin)
	elseif op == "state" then
		notify(p)
	end
end

function Dj.init(ctx: any)
	C = ctx
	S = ctx.S
	cfg = S.Config.DJ
	L = S.Lines
	publish()
end

function Dj.playerLeft(p: Player)
	busy[p] = nil
	if current and current.p == p then
		current = nil
		publish()
		task.defer(startNext)
	end
	local i = queueIndex(p.UserId)
	if i then
		table.remove(queue, i)
		publish()
	end
end

function Dj.tick(now: number)
	local cur = current
	if cur then
		if not C.isPlayer(cur.p) then
			current = nil
			publish()
			startNext()
			return
		end
		if not cur.arrived then
			if C.Bridge.inClub(cur.p) then
				cur.arrived = true
			elseif now - cur.at > cfg.ArriveSeconds then
				endTurn("skipped")
				return
			end
		end
		if now >= cur.untilT then
			endTurn("time")
		end
	elseif #queue > 0 then
		startNext()
	end
end

return Dj
