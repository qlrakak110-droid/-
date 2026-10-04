-- Interact/World (server): senses + incidents.
--   SENSES: an NPC SEES what is inside its view cone (120°, or anything within 5 studs), within its
--   sight range (shorter at night) and not behind a wall (eye-to-eye raycast); it HEARS what is within
--   the sound's radius (a wall in between halves it). Raycasts are budgeted per broadcast.
--   INCIDENTS: { id, kind, label, pos, t0, tLast, sev (1-5), aggressor, victim (entity keys), witnesses
--   { [npcId] = { how = "seen" | "heard" | "told", t } }, playerWitness { [userId] = t }, report
--   { by, t, pos } (what the police were told), status "active" | "reported" | "police" | "resolved",
--   reason }. Only NPCs that saw / heard / were told about an incident know it (Mind.perceive).
-- Entity keys: "p:<userId>" player, "n:<id>" city NPC (Mind), "k:<id>" key NPC (NPC.luau), "x:<id>"
-- client-side street pedestrian (its last reported position is kept on the incident).

local Players = game:GetService("Players")

local World = {}

local I: any
local Mind: any
local Actors: any

local incidents: { [number]: any } = {}
World.incidents = incidents
local seq = 0

World.KINDS = {
	bump = { sev = 1, loud = 9, label = "어깨빵" },
	argument = { sev = 1, loud = 24, label = "말다툼" },
	threat = { sev = 2, loud = 26, label = "위협" },
	shove = { sev = 2, loud = 18, label = "몸싸움" },
	fight = { sev = 3, loud = 36, label = "싸움" },
	assault = { sev = 3, loud = 34, label = "폭행" },
	ko = { sev = 4, loud = 34, label = "폭행 (기절)" },
	robbery = { sev = 3, loud = 18, label = "강도" },
	near_miss = { sev = 1, loud = 26, label = "난폭 운전" },
	vehicle = { sev = 3, loud = 34, label = "교통사고" },
	disturbance = { sev = 1, loud = 26, label = "소란" },
	cop_assault = { sev = 4, loud = 34, label = "경찰관 폭행" },
}

local WHERE = {
	{ Vector3.new(-262, 6.5, 22), "만남의 광장" },
	{ Vector3.new(-262, 6.5, -4), "버스킹 무대 앞" },
	{ Vector3.new(-232, 6.5, 4), "포토존" },
	{ Vector3.new(-186, 7, 106), "편의점 앞" },
	{ Vector3.new(-178, 6.5, 44), "택시 승강장" },
	{ Vector3.new(-320, 6.5, 22), "광장 서쪽" },
	{ Vector3.new(-205, 6.5, 40), "해변 산책로" },
}
function World.placeName(pos: Vector3): string
	local best, bd = "이 근처", 70
	for _, w in WHERE do
		local d = (w[1] - pos).Magnitude
		if d < bd then
			best, bd = w[2], d
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------
-- entities
---------------------------------------------------------------------------------------------------
function World.playerOf(key: string?): Player?
	if type(key) ~= "string" or string.sub(key, 1, 2) ~= "p:" then
		return nil
	end
	return Players:GetPlayerByUserId(tonumber(string.sub(key, 3)) or 0)
end

function World.keyOf(player: Player): string
	return "p:" .. player.UserId
end

function World.posOf(key: string?, fallback: Vector3?): Vector3?
	if type(key) ~= "string" then
		return fallback
	end
	local kind, id = string.sub(key, 1, 1), string.sub(key, 3)
	if kind == "p" then
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		return (p and I.feetOf(p)) or fallback
	elseif kind == "n" then
		local n = Mind and Mind.get(id)
		if n and n.a and not n.a.gone then
			return Actors.pos(n.a)
		end
	elseif kind == "k" then
		local NPC = I.NPC
		if NPC and NPC.state then
			local ok, st = pcall(NPC.state, id)
			if ok and type(st) == "table" and typeof(st.pos) == "Vector3" then
				return st.pos
			end
		end
	end
	return fallback
end

function World.nameOf(key: string?): string
	if type(key) ~= "string" then
		return "누군가"
	end
	local kind, id = string.sub(key, 1, 1), string.sub(key, 3)
	if kind == "p" then
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		return p and p.DisplayName or "누군가"
	elseif kind == "n" then
		local n = Mind and Mind.get(id)
		return n and n.name or "누군가"
	end
	return "행인"
end

---------------------------------------------------------------------------------------------------
-- senses
---------------------------------------------------------------------------------------------------
local EYE = Vector3.new(0, 2.6, 0)
local budget = 0

local function night(): boolean
	local ok, env = pcall(I.ctx.env)
	return ok and type(env) == "table" and env.night == true
end

-- facing (unit, flat) of an NPC body: walking direction, else its yaw attribute
function World.facingOf(n: any): Vector3
	local a = n.a
	if a and a.path and Actors.moving(a) then
		local p0 = Actors.pos(a)
		local p1 = Actors.pos(a, workspace:GetServerTimeNow() + 0.3)
		local d = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z)
		if d.Magnitude > 0.05 then
			return d.Unit
		end
	end
	local yaw = math.rad(tonumber(a and a.attrs.GiYaw) or 0)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function World.sightRange(n: any): number
	local r = if night() then 30 else 46
	if n.drunk and n.drunk > 0.5 then
		r *= 0.75
	end
	return r
end

-- does NPC n see the point (feet position)?
function World.canSee(n: any, pos: Vector3, range: number?): boolean
	if not n.a or n.a.gone or Actors.isDown(n.a) then
		return false
	end
	local me = Actors.pos(n.a)
	local d = Vector3.new(pos.X - me.X, 0, pos.Z - me.Z)
	local dist = d.Magnitude
	if dist > (range or World.sightRange(n)) or math.abs(pos.Y - me.Y) > 14 then
		return false
	end
	if dist > 5 then
		local f = World.facingOf(n)
		if f:Dot(d.Unit) < 0.5 and n.mode ~= "watch" and n.mode ~= "police" then
			return false
		end
	end
	if dist < 3 then
		return true
	end
	budget -= 1
	if budget < -40 then
		return false
	end
	return Actors.clear(me + EYE, pos + EYE)
end

-- does NPC n hear something of loudness `loud` at pos?
function World.canHear(n: any, pos: Vector3, loud: number): boolean
	if not n.a or n.a.gone then
		return false
	end
	local me = Actors.pos(n.a)
	local dist = (pos - me).Magnitude
	if dist > loud then
		return false
	end
	if dist < loud * 0.45 then
		return true
	end
	budget -= 1
	return Actors.clear(me + EYE, pos + EYE)
end

---------------------------------------------------------------------------------------------------
-- incidents
---------------------------------------------------------------------------------------------------
local function involved(inc: any, key: string): boolean
	return inc.aggressor == key or inc.victim == key
end

-- tell everybody around who can perceive it (also the players' clients for the street pedestrians)
function World.broadcast(inc: any)
	budget = 24
	local def = World.KINDS[inc.kind] or World.KINDS.disturbance
	local loud = def.loud
	local list = {}
	for _, n in Mind.list do
		if n.present and n.a and not n.a.gone and not involved(inc, "n:" .. n.id) then
			local d = (Actors.pos(n.a) - inc.pos).Magnitude
			if d <= math.max(loud, World.sightRange(n)) then
				table.insert(list, { n = n, d = d })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	for _, e in list do
		local n = e.n
		local prev = inc.witnesses[n.id]
		local how = nil
		if World.canSee(n, inc.pos) then
			how = "seen"
		elseif (not prev) and World.canHear(n, inc.pos, loud) then
			how = "heard"
		end
		if how and (not prev or (prev.how ~= "seen" and how == "seen")) then
			inc.witnesses[n.id] = { how = how, t = os.clock() }
			n.knows[inc.id] = { how = how, t = os.clock() }
			Mind.perceive(n, inc, how)
		end
	end
	-- players near it saw it too (for 신고 / 소문)
	for _, p in Players:GetPlayers() do
		local f = I.feetOf(p)
		if f and (f - inc.pos).Magnitude < 45 and not involved(inc, "p:" .. p.UserId) then
			inc.playerWitness[p.UserId] = os.clock()
		end
	end
	-- the street pedestrians live on the clients: each client decides who of them notices
	I.fireAll({ kind = "incident", id = inc.id, ikind = inc.kind, pos = I.C.packV(inc.pos), sev = inc.sev, loud = loud })
end

-- new incident, or the escalation of an active one between the same people nearby
function World.incident(kind: string, pos: Vector3, opts: any?): any
	local o = opts or {}
	local def = World.KINDS[kind] or World.KINDS.disturbance
	local now = os.clock()
	for _, inc in incidents do
		if inc.status ~= "resolved" and now - inc.tLast < 25 and (inc.pos - pos).Magnitude < 22 then
			local same = (o.aggressor and (inc.aggressor == o.aggressor or inc.victim == o.aggressor)) or (o.victim and (inc.victim == o.victim or inc.aggressor == o.victim))
			if same then
				inc.tLast = now
				inc.pos = pos
				local sev = o.sev or def.sev
				if sev >= inc.sev then
					inc.sev = sev
					inc.kind = kind
					inc.label = def.label
				end
				if now - (inc.lastCast or 0) > 1 then
					inc.lastCast = now
					World.broadcast(inc)
				end
				return inc
			end
		end
	end
	seq += 1
	local inc = {
		id = seq,
		kind = kind,
		label = def.label,
		pos = pos,
		t0 = now,
		tLast = now,
		sev = o.sev or def.sev,
		aggressor = o.aggressor,
		victim = o.victim,
		witnesses = {},
		playerWitness = {},
		report = nil,
		status = "active",
		lastCast = now,
	}
	incidents[seq] = inc
	World.broadcast(inc)
	return inc
end

-- gossip: `from` (NPC) tells `to` (NPC) about what it knows
function World.tell(from: any, to: any, inc: any)
	if not inc or to.knows[inc.id] then
		return
	end
	to.knows[inc.id] = { how = "told", t = os.clock(), from = from.id }
	inc.witnesses[to.id] = inc.witnesses[to.id] or { how = "told", t = os.clock() }
end

-- the most recent incident an NPC knows (optionally only within maxAge seconds)
function World.recentKnown(n: any, maxAge: number?): (any?, any?)
	local best, info, bt = nil, nil, -1
	for id, k in n.knows do
		local inc = incidents[id]
		if inc and k.t > bt and os.clock() - k.t < (maxAge or 600) then
			best, info, bt = inc, k, k.t
		end
	end
	return best, info
end

-- the most recent incident a player witnessed (and did not cause) — what they can report
function World.playerKnown(player: Player, maxAge: number?): any?
	local best, bt = nil, -1
	for _, inc in incidents do
		local t = inc.playerWitness[player.UserId]
		if t and t > bt and os.clock() - t < (maxAge or 180) and inc.status ~= "resolved" and inc.aggressor ~= "p:" .. player.UserId then
			best, bt = inc, t
		end
	end
	return best
end

-- words for an incident (for the Lines placeholders)
function World.describe(inc: any, info: any?): any
	local age = os.clock() - (info and info.t or inc.t0)
	return {
		what = inc.label or "소란",
		where = World.placeName(inc.pos),
		when = if age < 25 then "방금" elseif age < 120 then "아까" else "조금 전",
		target = World.nameOf(inc.aggressor),
	}
end

function World.resolve(inc: any, reason: string)
	if inc.status == "resolved" then
		return
	end
	inc.status = "resolved"
	inc.reason = reason
	inc.tResolved = os.clock()
	Mind.onResolved(inc)
	I.fireAll({ kind = "incidentEnd", id = inc.id })
end

function World.tick()
	local now = os.clock()
	for id, inc in incidents do
		if inc.status ~= "resolved" then
			-- nobody keeps it going and the police are not on it: it calms down by itself
			if inc.status ~= "police" and now - inc.tLast > 30 then
				World.resolve(inc, "calmed")
			elseif inc.status == "police" and now - inc.tLast > 150 then
				World.resolve(inc, "stale")
			end
		elseif now - (inc.tResolved or now) > 240 then
			incidents[id] = nil
		end
	end
end

function World.init(interact: any)
	I = interact
	Mind = I.Mind
	Actors = I.Actors
end

return World
