-- GwangalliClubPlus.Stage: the centre LED wall's timeline (server).
-- The club's own order intros and the 합석 card own fixed windows ("blocks": they follow the club's
-- show and are never moved). Paid 후원 / DJ cues queue FIFO around them: a waiting cue is slotted
-- into the next free gap; a running cue that a new block overlaps is paused for the block ("holds")
-- and resumes after it, so every paid second is shown. Clients render from the Stage attribute:
--   Stage = { v, serial, cues = { { id, kind, at, dur, tier, holds = { {from, to} }, data } },
--             ticker = { { k, n, t, w, at } } }

local Stage = {}

local C: any
local S: any
local cues: { any } = {}
local blocks: { { from: number, to: number, kind: string } } = {}
local ticker: { any } = {}
local nextId = 0
local serial = 0
local dirty = false

local function holdTotal(c: any): number
	local t = 0
	for _, h in c.holds do
		t += h[2] - h[1]
	end
	return t
end
local function endOf(c: any): number
	return c.at + c.dur + holdTotal(c)
end
Stage.endOf = endOf

-- earliest start >= t where [start - gap, start + dur + gap] touches no block
local function freeFrom(t: number, dur: number, gap: number): number
	local moved = true
	local guard = 0
	while moved and guard < 64 do
		moved = false
		guard += 1
		for _, b in blocks do
			if t < b.to + gap and t + dur + gap > b.from then
				t = b.to + gap
				moved = true
			end
		end
	end
	return t
end

-- re-slot every waiting cue (FIFO) after the running ones
local function reflow(now: number)
	local cfg = S.Config.Stage
	local nextFree = now + cfg.Lead
	for _, c in cues do
		if c.at <= now then
			nextFree = math.max(nextFree, endOf(c) + cfg.Gap)
		end
	end
	for _, c in cues do
		if c.at > now then
			local at = freeFrom(math.max(nextFree, now + cfg.Lead), c.dur, cfg.Gap)
			if math.abs(at - c.at) > 0.01 then
				c.at = at
				dirty = true
			end
			nextFree = at + c.dur + cfg.Gap
		end
	end
end

function Stage.init(ctx: any)
	C = ctx
	S = ctx.S
end

-- a fixed window (order intro / 합석 card) on the main screen
function Stage.block(from: number, to: number, kind: string)
	local now = C.now()
	if to <= now then
		return
	end
	table.insert(blocks, { from = from, to = to, kind = kind })
	-- a running cue pauses for it
	for _, c in cues do
		if c.at <= now then
			local e = endOf(c)
			if from < e and to > math.max(c.at, now) then
				local h1 = math.max(from, now)
				table.insert(c.holds, { h1, to })
				dirty = true
			end
		end
	end
	reflow(now)
	dirty = true
	Stage.publish()
end

-- queue a cue: -> position (1 = next / running), start time; nil when the queue is full
-- (`force`: an already paid cue always gets a slot)
function Stage.push(kind: string, dur: number, tier: number, data: any, owner: number?, force: boolean?): (number?, number)
	local now = C.now()
	if #cues >= S.Config.Stage.MaxCues and not force then
		return nil, 0
	end
	nextId += 1
	local c = { id = nextId, kind = kind, at = math.huge, dur = dur, tier = tier, holds = {}, data = data, owner = owner }
	table.insert(cues, c)
	reflow(now)
	dirty = true
	Stage.publish()
	local pos = 0
	for _, x in cues do
		pos += 1
		if x == c then
			break
		end
	end
	return pos, c.at
end

function Stage.count(): number
	return #cues
end
function Stage.pendingFor(uid: number): number
	local n = 0
	for _, c in cues do
		if c.owner == uid then
			n += 1
		end
	end
	return n
end
function Stage.waitingTime(): number
	local now = C.now()
	local last = now
	for _, c in cues do
		last = math.max(last, endOf(c))
	end
	return last - now
end

-- ticker line (the side boards scroll them; names are filtered)
function Stage.ticker(kind: string, name: string?, text: string, won: number?)
	table.insert(ticker, { k = kind, n = name, t = text, w = won, at = math.floor(C.now()) })
	while #ticker > S.Config.Stage.Ticker do
		table.remove(ticker, 1)
	end
	dirty = true
end

function Stage.publish()
	if not dirty then
		return
	end
	dirty = false
	serial += 1
	local out = {}
	for _, c in cues do
		local holds = {}
		for _, h in c.holds do
			table.insert(holds, { math.floor(h[1] * 100) / 100, math.floor(h[2] * 100) / 100 })
		end
		table.insert(out, {
			id = c.id,
			kind = c.kind,
			at = math.floor(c.at * 100) / 100,
			dur = c.dur,
			tier = c.tier,
			holds = holds,
			data = c.data,
		})
	end
	C.publish(S.Attr.Stage, { v = 1, serial = serial, cues = out, ticker = ticker })
end

function Stage.tick(now: number)
	for i = #cues, 1, -1 do
		if endOf(cues[i]) < now - 1 then
			table.remove(cues, i)
			dirty = true
		end
	end
	for i = #blocks, 1, -1 do
		if blocks[i].to < now - 1 then
			table.remove(blocks, i)
		end
	end
	Stage.publish()
end

return Stage
