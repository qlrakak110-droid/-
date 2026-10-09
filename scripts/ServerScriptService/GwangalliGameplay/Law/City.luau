-- GwangalliGameplay/Law/City (server; owner: law): the city's own crime — NPC incidents that make the
-- streets feel alive and give the police (NPC and player cops) something to do. More and different at
-- night (LS.INCIDENTS weights, LS.INCIDENT_GAP): 소매치기 (a thief runs, the victim shouts), 취객 싸움
-- (two drunks push each other), 편의점 절도, 기물 파손, 소음 민원 (someone singing at 2 am).
-- Each incident is staged out of sight 60-130 studs from a player, reported (Cop.addCall: the player
-- cops' 신고 목록) and answered by an NPC officer (a patrol unit nearby or a new one) who walks there,
-- deals with it (arrest line, the suspect is taken away) or chases a running suspect NPC. A player cop
-- can make the arrest instead (Law.Action cop {act = "cuffNpc", id}) and gets the pay.

local Players = game:GetService("Players")

local City = {}

local Law: any
local ctx: any
local LS: any
local rng = Random.new()

local incidents: { [string]: any } = {}
local seq = 0
local nextAt = os.clock() + 45

local function now(): number
	return os.clock()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function P(): any
	return Law.children.Police
end

local LINES = {
	pickpocket = { victim = { "도둑이야!! 제 지갑!", "저 사람 잡아주세요! 소매치기예요!", "아악, 가방이!" }, suspect = { "비켜!", "헉헉…", "아 씨, 들켰다!" } },
	fight = { victim = { "니가 먼저 쳤잖아!", "뭘 봐 임마! 한 판 붙자!", "놔 봐, 놔 봐!" }, suspect = { "오냐 와라!", "술 깨면 후회할 거다!", "어이 친구, 진정해…" } },
	shoplift = { victim = { "저 사람 계산 안 했어요!", "경찰 불러요! 도둑이에요!" }, suspect = { "아 진짜 배고팠다고…", "튀자!" } },
	vandal = { victim = { "누가 간판 부쉈어요!", "야! 거기 뭐 하는 거야!" }, suspect = { "ㅋㅋㅋ 튀어!", "아무것도 안 했는데요?" } },
	noise = { victim = { "아 좀 조용히 해요! 몇 신데!", "신고할 거예요 진짜!" }, suspect = { "♪ 부산 갈매기~ 부산 갈매기~ ♪", "♪ 돌아와요 부산항에~ ♪", "나 노래 잘하지? 히끅" } },
}

local HINT = {
	pickpocket = { style = "street", age = "young" },
	fight = { style = "office", age = "adult" },
	shoplift = { style = "street", age = "young" },
	vandal = { style = "punk", age = "young" },
	noise = { style = "office", age = "adult" },
}

local function weightedKind(): string
	local night = Law.isNight()
	local total = 0
	for _, d in LS.INCIDENTS do
		total += if night then d.w.night else d.w.day
	end
	local r = rng:NextNumber() * total
	for k, d in LS.INCIDENTS do
		r -= if night then d.w.night else d.w.day
		if r <= 0 then
			return k
		end
	end
	return "pickpocket"
end

local function say(o: any, list: { string }?)
	local Pol = P()
	if Pol and o and list then
		Pol.say(o, LS.pick(list, function()
			return rng:NextNumber()
		end))
	end
end

local function cleanup(inc: any)
	incidents[inc.id] = nil
	local Pol = P()
	for _, a in { inc.suspect, inc.victim, inc.second } do
		if a and not a.gone and Pol then
			Pol.removeActor(a)
		end
	end
	if inc.officer and not inc.officer.gone then
		inc.officer.incident = nil
		inc.officer.role = "patrol"
		inc.officer.state = "patrol"
	end
	local C = Law.children.Cop
	if C then
		C.closeCall(function(c)
			return c.npcId == inc.id
		end, "closed")
	end
end

local function resolve(inc: any, by: string)
	inc.state = "done"
	local o = inc.officer
	if o and not o.gone then
		say(o, { "자, 갑시다. 지구대로.", "현행범으로 체포합니다.", "손 뒤로 하세요.", "진정하세요, 다 끝났어요." })
		P().emote(o, "point_proc")
	end
	if inc.suspect and not inc.suspect.gone then
		say(inc.suspect, { "…잘못했어요.", "아 진짜 운도 없네…", "히끅… 미안합니다…" })
		P().setAct(inc.suspect, "idle")
	end
	task.delay(4, function()
		cleanup(inc)
	end)
	local _ = by
end

local function spawnIncident()
	local plist = {}
	for _, p in Players:GetPlayers() do
		local j = p:GetAttribute(LS.Attr.Jail)
		if Law.posOf(p) and not (type(j) == "number" and j > 0) then
			table.insert(plist, p)
		end
	end
	if #plist == 0 then
		return
	end
	local Pol = P()
	if not Pol then
		return
	end
	local anchor = plist[rng:NextInteger(1, #plist)]
	local pp = Law.posOf(anchor) :: Vector3
	local at = Pol.hiddenSpot(pp, 60, 130)
	if not at then
		return
	end
	local kind = weightedKind()
	local def = LS.INCIDENTS[kind]
	seq += 1
	local id = "inc_" .. seq
	local inc = { id = id, kind = kind, pos = at, t = now(), state = "live", officer = nil, label = def.label, icon = def.icon }
	inc.suspect = Pol.newActor(at, id, HINT[kind], "suspect")
	if not inc.suspect then
		return
	end
	inc.suspect.model:SetAttribute("LawSuspect", id)
	if kind == "fight" then
		inc.second = Pol.newActor(at + Vector3.new(2.6, 0, 0.5), id .. "_b", { style = "office", age = "adult" }, "suspect")
		if inc.second then
			Pol.faceTo(inc.second, at)
			Pol.faceTo(inc.suspect, at + Vector3.new(2.6, 0, 0.5))
			Pol.setAct(inc.second, "idle")
		end
	elseif kind ~= "noise" then
		local vp = Pol.ringNode(at, 4, 9, nil) or (at + Vector3.new(4, 0, 0))
		inc.victim = Pol.newActor(vp, id .. "_v", { age = "adult" }, "victim")
		if inc.victim then
			Pol.faceTo(inc.victim, at)
			Pol.setAct(inc.victim, "phone")
		end
	end
	Pol.setAct(inc.suspect, if kind == "noise" then "cheer" else "idle")
	incidents[id] = inc
	say(inc.victim or inc.second or inc.suspect, (LINES[kind] or LINES.pickpocket).victim)
	-- report: the player cops' list + an NPC unit
	local C = Law.children.Cop
	if C then
		C.addCall({ label = def.label, icon = def.icon, pos = at, npcId = id, npcName = "용의자 (" .. def.label .. ")" })
	end
	task.delay(4 + rng:NextNumber() * 6, function()
		if incidents[id] ~= inc or inc.state ~= "live" then
			return
		end
		-- the nearest patrol officer takes it, else a new unit walks in
		local best, bd = nil, 220
		for _, o in Pol.officers() do
			if not o.gone and o.role == "patrol" and not o.incident then
				local d = flat(o.pos, at)
				if d < bd then
					best, bd = o, d
				end
			end
		end
		if not best then
			local sp = Pol.hiddenSpot(at, 60, 110)
			best = sp and Pol.newOfficer(sp, "patrol", nil)
		end
		if best then
			best.incident = inc
			inc.officer = best
			Pol.say(best, "무전: " .. def.label .. " 출동합니다.")
			Pol.assignGoal(best, at, 11, nil)
		end
	end)
end

local function suspectFlee(inc: any)
	if inc.state ~= "live" or not inc.suspect or inc.suspect.gone then
		return
	end
	local def = LS.INCIDENTS[inc.kind]
	if not def.flee then
		return
	end
	inc.state = "flee"
	local Pol = P()
	say(inc.suspect, LINES[inc.kind].suspect)
	local away = Pol.ringNode(inc.suspect.pos, 80, 150, inc.officer and inc.officer.pos or nil)
	if away then
		Pol.assignGoal(inc.suspect, away, 12.5, nil)
		inc.fleeGoal = away
	end
end

function City.tick(dt: number)
	local Pol = P()
	if not Pol then
		return
	end
	if now() >= nextAt then
		local gap = if Law.isNight() then LS.INCIDENT_GAP.night else LS.INCIDENT_GAP.day
		nextAt = now() + gap[1] + rng:NextNumber() * (gap[2] - gap[1])
		local n = 0
		for _ in incidents do
			n += 1
		end
		if n < 3 then
			pcall(spawnIncident)
		end
	end
	for _, inc in incidents do
		local s = inc.suspect
		if not s or s.gone then
			cleanup(inc)
			continue
		end
		s.pos = Pol.legPos(s, now())
		if Pol.syncRoot then
			pcall(Pol.syncRoot, s) -- (a fleeing suspect's server copy follows the run: streaming)
		end
		if now() - inc.t > 180 and inc.state ~= "done" then
			cleanup(inc)
			continue
		end
		local o = inc.officer
		if o and o.gone then
			inc.officer = nil
			o = nil
		end
		-- anyone in uniform close by makes a thief run
		if inc.state == "live" then
			local near = o and flat(o.pos, s.pos) < 26
			if not near then
				for _, p in Players:GetPlayers() do
					if p:GetAttribute(LS.Attr.Cop) == true then
						local cp = Law.posOf(p)
						if cp and flat(cp, s.pos) < 22 then
							near = true
						end
					end
				end
			end
			if near then
				suspectFlee(inc)
			elseif rng:NextNumber() < 0.03 then
				say(s, LINES[inc.kind].suspect)
				if inc.kind == "fight" and inc.second and not inc.second.gone then
					Pol.emote(inc.second, "stagger")
					Pol.emote(s, "shake")
				end
			end
		end
		if o then
			o.pos = Pol.legPos(o, now())
			local d = flat(o.pos, s.pos)
			if inc.state == "flee" then
				if d < 3.2 then
					Pol.standAt(o, o.pos)
					Pol.standAt(s, s.pos)
					resolve(inc, "npc")
				elseif now() - (inc.repath or 0) > 1.2 then
					inc.repath = now()
					Pol.assignGoal(o, s.pos, 13.6, nil)
					if rng:NextNumber() < 0.25 then
						Pol.say(o, LS.pick(LS.LINES.chase))
					end
				end
				-- got away
				if inc.fleeGoal and Pol.arrived(s) and d > 40 then
					Pol.say(o, LS.pick(LS.LINES.lost))
					cleanup(inc)
				end
			elseif inc.state == "live" and d < 4 then
				Pol.standAt(o, o.pos)
				Pol.faceTo(o, s.pos)
				resolve(inc, "npc")
			end
		elseif inc.state == "flee" and inc.fleeGoal and Pol.arrived(s) then
			cleanup(inc)
		end
	end
	local _ = dt
end

-- a player cop's arrest of an incident suspect
function City.arrestNpc(id: string, cop: Player): (boolean, string?)
	local inc = incidents[id]
	if not inc or inc.state == "done" or not inc.suspect or inc.suspect.gone then
		return false, "체포할 대상이 없어요"
	end
	local cp = Law.posOf(cop)
	local Pol = P()
	inc.suspect.pos = Pol.legPos(inc.suspect, now())
	if not cp or flat(cp, inc.suspect.pos) > LS.CUFF_RANGE + 1 then
		return false, "너무 멀어요"
	end
	Pol.standAt(inc.suspect, inc.suspect.pos)
	Pol.faceTo(inc.suspect, cp)
	resolve(inc, "cop")
	return true, inc.label
end

-- the nearest live suspect for a cop's HUD
function City.nearestSuspect(pos: Vector3, maxDist: number): any?
	local best, bd = nil, maxDist
	for id, inc in incidents do
		local s = inc.suspect
		if s and not s.gone and inc.state ~= "done" then
			local d = flat(P().legPos(s, now()), pos)
			if d < bd then
				best, bd = { id = id, label = inc.label, dist = d }, d
			end
		end
	end
	return best
end

function City.init(law: any, context: any)
	Law = law
	ctx = context
	LS = Law.shared()
	local _ = ctx
end

return City
