-- Interact/Verbs (server): what a player's action does to a city NPC. The same button never means the
-- same line: every verb looks at the person (traits, mood, patience, drunk), the relationship with this
-- player (Memory tier + what happened before), the current situation (a conflict with you or with
-- somebody else, busy with another player, an incident nearby, embarrassed, knocked down) and only then
-- picks a reaction, a line (Talk) and its consequences (Memory, mood, conflict ladder, incidents, money).
-- Verbs: greet talk ask joke tease apologize give food help report shove punch rob flee

local Players = game:GetService("Players")

local Verbs = {}

local I: any
local C: any
local Mind: any
local Talk: any
local Memory: any
local World: any
local Actors: any
local Routine: any
local Police: any
local Places: any
local rnd = Random.new()

local TIER_BONUS = { friend = 0.25, friendly = 0.12, known = 0.04, stranger = 0, wary = -0.2, enemy = -0.45 }

local function say(n: any, situation: string, vars: any?): string?
	return Mind.say(n, situation, vars)
end

-- a short exchange: the NPC stops and faces the player for a while (talkStep ends it)
local function engage(n: any, p: Player, secs: number)
	if n.mode ~= "routine" and n.mode ~= "talk" then
		return
	end
	if n.mode ~= "talk" then
		Mind.setMode(n, "talk")
	end
	n.talkWith = p.UserId
	n.talkT = os.clock() - math.max(0, 25 - secs)
	Mind.faceKey(n, "p:" .. p.UserId)
	Actors.pose(n.a, "talk")
	task.delay(math.min(secs, 4), function()
		if n.a and n.mode == "talk" then
			Actors.pose(n.a, "")
		end
	end)
end

local function hasConflict(n: any, key: string): any?
	local c = n.conf[key]
	if c and c.level >= 1 then
		return c
	end
	return nil
end

-- somebody threatening this player right now (for 도움 요청)
local function threatTo(key: string, near: Vector3): any?
	for _, o in Mind.list do
		local c = o.conf[key]
		if o.present and c and c.level >= 2 and c.starter == "self" then
			local op = Mind.pos(o)
			if op and (op - near).Magnitude < 25 then
				return o
			end
		end
	end
	return nil
end

local function placeOf(n: any): (string, string?)
	-- where a person sends you when you ask for directions (and the Destination for the waypoint)
	local r = rnd:NextNumber()
	if n.arch == "police" or r < 0.3 then
		return "광안지구대", "광안지구대"
	elseif r < 0.65 then
		return "GS25 광안리점", "GS25 광안리점"
	end
	return "만남의 광장", "광안리 만남의 광장"
end

---------------------------------------------------------------------------------------------------
-- the conversation card (대화): three topics that depend on who they are
---------------------------------------------------------------------------------------------------
local function talkCard(p: Player, n: any, s: any)
	local key = "p:" .. p.UserId
	local rec = Memory.get(p, n.id)
	local tier = Memory.tier(rec)
	engage(n, p, 25)
	local opener
	if rec.helped > 0 and rec.met <= 3 then
		opener = Talk.line(n, "remember_helped")
	elseif tier == "enemy" then
		opener = Talk.line(n, "greet_enemy")
	elseif tier == "wary" then
		opener = Talk.line(n, "greet_wary")
	elseif n.mood.v < -0.25 or n.patience < 35 then
		opener = Talk.line(n, "talk_tired")
	else
		opener = Talk.line(n, if tier == "friend" or tier == "friendly" then "greet_friend" else "talk_good")
	end
	opener = opener or "네?"
	Actors.say(n.a, opener, 3.5)
	local choices = {
		{ id = "mood", label = "요즘 어때요?" },
		{ id = "rumor", label = "이 동네 무슨 일 없어요?" },
	}
	local extra = nil
	if n.arch == "fool" then
		extra = { id = "play", label = "같이 놀자!" }
	elseif n.arch == "homeless" then
		extra = { id = "favor", label = "도와드릴 거 있어요?" }
	elseif n.arch == "police" then
		extra = { id = "report", label = "신고할 게 있어요" }
	elseif n.arch == "clerk" then
		extra = { id = "buy", label = "삼각김밥 하나 살게요 (2,000원)" }
	elseif n.arch == "drunk" then
		extra = { id = "drunk", label = "많이 취하셨네요?" }
	elseif n.arch == "thug" then
		extra = { id = "boast", label = "형님, 이 동네 오래 사셨어요?" }
	else
		extra = { id = "bio", label = "무슨 일 하세요?" }
	end
	table.insert(choices, extra)
	local card = { name = n.name, role = n.def.role, color = { 120, 150, 200 }, icon = "💬", bye = "이만 갈게요" }
	I.card(p, n.id, card, opener, choices, function(choice)
		if not n.a or n.a.gone then
			return
		end
		if choice == "bye" or choice == "close" then
			if n.talkWith == p.UserId then
				n.talkWith = nil
				if n.mode == "talk" then
					Mind.toRoutine(n, 0.5)
				end
			end
			return
		end
		Memory.event(p, n.id, "talk")
		n.talkT = os.clock()
		if choice == "mood" then
			say(n, if n.mood.v >= 0 and n.patience > 40 then "talk_good" else "talk_bad")
		elseif choice == "rumor" then
			local inc, info = World.recentKnown(n, 600)
			if inc then
				say(n, if info.how == "told" then "rumor_heard" else "rumor", World.describe(inc, info))
				-- what you were told, you know now (you can report it)
				inc.playerWitness[p.UserId] = os.clock()
			else
				say(n, "rumor_none")
			end
		elseif choice == "bio" then
			Actors.say(n.a, n.def.bio or (Talk.line(n, "talk_bio") or "…"), 4.5)
		elseif choice == "boast" then
			say(n, "boast")
		elseif choice == "drunk" then
			say(n, if n.style == "drunk_sad" then "sentimental" else "forget")
		elseif choice == "play" then
			say(n, "dance")
			Actors.emote(n.a, "dance")
			Memory.event(p, n.id, "joke_good")
			pcall(I.ctx.addStats, p, { happiness = 2 }, nil, true)
		elseif choice == "favor" then
			n.favorFor = p.UserId
			say(n, "favor_ask")
		elseif choice == "report" then
			Verbs.act(p, n, "report", s)
		elseif choice == "buy" then
			Verbs.buyFood(p, n)
		end
		Mind.feel(n, { v = 0.04 })
	end)
end

function Verbs.buyFood(p: Player, clerk: any)
	if p:GetAttribute("GwCarryFood") then
		Actors.say(clerk.a, "손님, 이미 하나 들고 계신데요?", 3)
		return
	end
	if not I.ctx.spend(p, 2000, "GS25 광안리점 · 삼각김밥", false) then
		Actors.say(clerk.a, "결제가 안 되네요… 잔액 확인해 주세요!", 3)
		return
	end
	say(clerk, "clerk_hand", { item = "삼각김밥" })
	Actors.emote(clerk.a, "give")
	I.setCarry(p, "삼각김밥")
end

---------------------------------------------------------------------------------------------------
-- verbs
---------------------------------------------------------------------------------------------------
function Verbs.act(p: Player, n: any, verb: string, s: any)
	if not n.a or n.a.gone or not n.present then
		return
	end
	local key = "p:" .. p.UserId
	local T = n.traits
	local rec, fresh = Memory.meet(p, n.id)
	local tier = Memory.tier(rec)
	local tb = TIER_BONUS[tier] or 0
	local c = hasConflict(n, key)
	local busyOther = n.talkWith and n.talkWith ~= p.UserId and n.mode == "talk"
	local me = I.feetOf(p) or Mind.pos(n)
	local pos = Mind.pos(n)
	local physical = verb == "shove" or verb == "punch" or verb == "rob"

	if n.mode == "custody" then
		say(n, "idle_grumpy")
		return
	end
	-- 만복이 just fell on his face showing off: what you do now decides how he takes it
	if n.mode == "embarrassed" and n.embarrassedBy == p.UserId and not physical then
		n.embarrassedReact = verb
		if verb == "tease" or verb == "joke" then
			if T.humor - T.pride * 0.4 + rnd:NextNumber() * 0.4 > 0.55 then
				say(n, "tease_laugh")
				Actors.emote(n.a, "laugh")
				Memory.event(p, n.id, "tease_ok")
			else
				say(n, "fall_angry")
				Mind.provoke(n, key, 1.2, "laughed_at", "self")
				Memory.event(p, n.id, "tease")
			end
		elseif verb == "help" or verb == "talk" or verb == "greet" or verb == "give" or verb == "food" then
			say(n, "favor_thanks")
			Actors.emote(n.a, "bow")
			Memory.event(p, n.id, "help")
			Mind.toRoutine(n, 1)
		else
			say(n, "embarrassed")
		end
		return
	end
	if n.mode == "down" and not physical then
		say(n, "hurt")
		return
	end
	if busyOther and not physical then
		say(n, "busy_other")
		return
	end
	-- something is going on: small talk gets an answer about that first (money / food / help still count)
	local chat = verb == "greet" or verb == "talk" or verb == "ask" or verb == "joke" or verb == "tease"
	if chat and not c and (n.mode == "watch" or n.mode == "flee" or n.mode == "report") then
		local inc = n.watchInc or n.fleeInc
		say(n, "distracted", inc and World.describe(inc) or nil)
		return
	end

	if verb == "greet" then
		local count = Memory.greet(p, n.id, 60)
		if c then
			say(n, "busy_conflict")
			if c.level >= 2 and n.arch == "thug" then
				Mind.provoke(n, key, 0.5, "mock", "other")
			end
			return
		end
		if count >= 3 then
			say(n, "greet_annoyed")
			Mind.feel(n, { patience = -15 })
			Memory.event(p, n.id, "follow")
			if n.patience < 25 then
				Mind.provoke(n, key, 1, "pester", "self")
			end
			return
		elseif count == 2 then
			say(n, "greet_again")
			engage(n, p, 4)
			return
		end
		if fresh and rec.helped > 0 and tier ~= "enemy" then
			say(n, "remember_helped")
		elseif tier == "enemy" then
			say(n, if rec.hurt > 0 or rec.robbed > 0 then "remember_hurt" else "greet_enemy")
			if n.arch == "thug" then
				Mind.provoke(n, key, 1.5, "grudge", "self")
				return
			elseif rec.fear > 35 then
				Mind.flee(n, me, 4, false)
				return
			end
		elseif tier == "wary" then
			say(n, "greet_wary")
		elseif tier == "friend" or tier == "friendly" then
			say(n, "greet_friend")
		elseif tier == "known" then
			say(n, "greet_known")
		else
			say(n, "greet_first")
		end
		Memory.event(p, n.id, "greet")
		Mind.feel(n, { v = 0.03 })
		if tier ~= "wary" and tier ~= "enemy" then
			Actors.emote(n.a, "wave")
		end
		engage(n, p, 6)
	elseif verb == "talk" then
		if c then
			say(n, "busy_conflict")
			return
		end
		talkCard(p, n, s)
	elseif verb == "ask" then
		if c then
			say(n, "busy_conflict")
			return
		end
		engage(n, p, 8)
		local inc, info = World.recentKnown(n, 300)
		if inc then
			say(n, if info.how == "told" then "rumor_heard" else "rumor", World.describe(inc, info))
			inc.playerWitness[p.UserId] = os.clock()
		elseif n.style == "tourist" then
			say(n, "ask_unknown")
		else
			local name, dest = placeOf(n)
			say(n, "ask_direction", { place = name })
			Actors.emote(n.a, "point")
			if dest then
				pcall(I.ctx.setWaypoint, p, dest)
			end
		end
		Memory.event(p, n.id, "talk", 0.5)
	elseif verb == "joke" then
		local good = T.humor * 0.55 + n.mood.v * 0.25 + tb + n.drunk * 0.15 - (1 - n.patience / 100) * 0.3 + rnd:NextNumber() * 0.25
		if c then
			if good > 0.6 then
				say(n, "joke_laugh")
				Mind.calm(n, key, 1, "joke")
			else
				say(n, "tease_angry")
				Mind.provoke(n, key, 0.8, "joke_in_fight", "other")
			end
			return
		end
		engage(n, p, 5)
		if good > 0.55 then
			say(n, "joke_laugh")
			Actors.emote(n.a, "laugh")
			Memory.event(p, n.id, "joke_good")
			Mind.feel(n, { v = 0.12 })
		elseif good > 0.3 then
			say(n, "joke_meh")
			Actors.emote(n.a, "shrug")
		else
			say(n, "joke_annoyed")
			Memory.event(p, n.id, "joke_bad")
			Mind.feel(n, { patience = -10, v = -0.05 })
		end
	elseif verb == "tease" then
		local take = T.humor * 0.6 - T.pride * 0.5 + tb * 0.5 + rnd:NextNumber() * 0.3 - n.mood.anger * 0.3
		if take > 0.25 and not c then
			say(n, "tease_laugh")
			Actors.emote(n.a, "laugh")
			Memory.event(p, n.id, "tease_ok")
			engage(n, p, 4)
		elseif T.pride + T.temper > 1.1 or n.arch == "thug" or n.arch == "drunk" or c then
			say(n, "tease_angry")
			Memory.event(p, n.id, "tease")
			Mind.provoke(n, key, if n.arch == "thug" then 2 else 1.2, "tease", "other")
		else
			say(n, "tease_hurt")
			Memory.event(p, n.id, "tease")
			Mind.feel(n, { v = -0.2 })
			Mind.setMode(n, "recover", 4)
			Actors.face(n.a, (pos or me) * 2 - me)
		end
	elseif verb == "apologize" then
		if not c then
			local le = rec.lastEvent
			if le and (le.kind == "bump" or le.kind == "shove" or le.kind == "tease" or le.kind == "punch") and os.time() - le.t < 180 then
				say(n, "apologize_accept")
				Memory.event(p, n.id, "apology")
				Mind.feel(n, { anger = -0.2, v = 0.05 })
			else
				say(n, "apologize_confused")
			end
			return
		end
		local chance = T.kindness * 0.5 + (1 - T.pride) * 0.3 + tb * 0.3 - (c.level - 1) * 0.12 - n.mood.anger * 0.3 + (if rec.apologies < 3 then 0.1 else -0.2) + rnd:NextNumber() * 0.2
		if chance > 0.45 then
			say(n, "apologize_accept")
			Mind.calm(n, key, if c.level >= 4 then 2.5 else 4, "apology")
			Memory.event(p, n.id, "apology")
			Mind.feel(n, { anger = -0.25 })
		else
			say(n, "apologize_reject")
			Mind.calm(n, key, 0.3, "apology_try")
			Mind.feel(n, { anger = -0.05 })
		end
	elseif verb == "give" then
		if n.arch == "police" then
			say(n, "cop_bribe")
			return
		end
		if n.style == "homeless_grumpy" and T.pride > 0.8 and rec.helped == 0 then
			say(n, "gift_money_refuse")
			return
		end
		if not I.ctx.ledger(p, "cash", -C.GIVE_AMOUNT, n.name .. "에게 " .. C.won(C.GIVE_AMOUNT), false) then
			I.notify(p, "info", "현금이 없어요", "ATM에서 현금을 뽑아 주세요", { icon = "💸" })
			return
		end
		I.playerSay(p, C.line("player_give"))
		if n.favorFor == p.UserId then
			n.favorFor = nil
			say(n, "favor_thanks")
			Memory.event(p, n.id, "favor")
		elseif T.suspicion > 0.6 and n.arch == "citizen" and tier == "stranger" then
			say(n, "gift_money_suspicious")
			Memory.event(p, n.id, "gift", 0.5)
		else
			say(n, "gift_money_thanks")
			Memory.event(p, n.id, "gift")
		end
		Actors.emote(n.a, if n.arch == "fool" then "cheer" else "bow")
		Mind.feel(n, { v = 0.15, anger = -0.1 })
		if n.arch == "homeless" then
			pcall(I.ctx.addStats, p, { happiness = 2, popularity = 1 }, nil, true)
		end
		if c then
			Mind.calm(n, key, 1 + T.greed * 2, "money")
		end
	elseif verb == "food" then
		local item = p:GetAttribute("GwCarryFood")
		if type(item) ~= "string" then
			I.fire(p, { kind = "miss", reason = "nofood" })
			I.notify(p, "info", "줄 음식이 없어요", "GS25 광안리점 알바생에게 사거나 편의점에서 사 오세요", { icon = "🍙" })
			return
		end
		I.setCarry(p, nil)
		I.playerSay(p, item .. " 드세요~")
		if n.arch == "homeless" or n.favorFor == p.UserId or rnd:NextNumber() < 0.7 then
			if n.favorFor == p.UserId then
				n.favorFor = nil
				say(n, "favor_thanks")
				Memory.event(p, n.id, "favor")
			else
				say(n, "gift_food_thanks")
				Memory.event(p, n.id, "food")
			end
			Actors.emote(n.a, "receive")
			Mind.feel(n, { v = 0.25, anger = -0.2 })
			pcall(I.ctx.addStats, p, { happiness = 2 }, nil, true)
			if c then
				Mind.calm(n, key, 2, "food")
			end
		else
			say(n, "gift_food_refuse")
			I.setCarry(p, item)
		end
	elseif verb == "help" then
		engage(n, p, 6)
		local threat = me and threatTo(key, me)
		if s.stars > 0 and n.arch ~= "thug" then
			say(n, "help_no")
			Mind.feel(n, { fear = 0.15 })
		elseif threat and threat ~= n then
			if n.arch == "police" then
				say(n, "cop_warn")
				if Police then
					Police.interveneFor(n, threat, p)
				end
			elseif T.courage * T.kindness > 0.32 then
				say(n, "help_defend")
				Mind.setMode(n, "intervene", 10)
				local inc = World.incident("argument", Mind.pos(threat), { aggressor = "n:" .. threat.id, victim = key })
				n.watchInc = inc
				Actors.walkTo(n.a, Places.nearPoint(Mind.pos(n), Mind.pos(threat), 3), 8)
				Memory.event(p, n.id, "talk")
			elseif T.civic > 0.5 then
				say(n, "help_call_police")
				local inc = World.incident("threat", Mind.pos(threat), { aggressor = "n:" .. threat.id, victim = key })
				Mind.report(n, inc)
			else
				say(n, "help_no")
			end
		elseif s.hp < 55 then
			say(n, "help_yes")
			Actors.emote(n.a, "give")
			I.heal(p, 15)
			Memory.event(p, n.id, "talk")
		elseif T.kindness > 0.6 and T.greed < 0.45 and rnd:NextNumber() < 0.35 and (os.time() - (rec.lentT or 0)) > 3600 then
			rec.lentT = os.time()
			say(n, "help_lend")
			I.ctx.ledger(p, "cash", 1000, n.name .. "이(가) 빌려준 돈", false)
		elseif T.kindness > 0.45 then
			local name, dest = placeOf(n)
			say(n, "help_yes")
			say(n, "ask_direction", { place = name })
			if dest then
				pcall(I.ctx.setWaypoint, p, dest)
			end
		else
			say(n, "help_no")
		end
	elseif verb == "report" then
		local inc = World.playerKnown(p, 180)
		if n.arch == "police" then
			if inc and Police then
				Police.report(inc, { by = key, pos = inc.pos, suspectPos = World.posOf(inc.aggressor), name = p.DisplayName })
				say(n, "cop_thanks_report")
				Memory.event(p, n.id, "police_help")
			else
				say(n, "cop_assess")
			end
			return
		end
		engage(n, p, 6)
		if inc then
			if T.civic * (0.5 + T.courage) > 0.35 then
				say(n, "report_will_call")
				task.delay(1.5, function()
					if n.present and (n.mode == "talk" or n.mode == "routine") then
						Mind.report(n, inc)
					end
				end)
			else
				say(n, "report_no")
			end
		else
			say(n, "rumor_none")
		end
	elseif verb == "flee" then
		I.playerSay(p, "튀어!")
		if c then
			if c.level >= 3 and T.aggression * (0.5 + n.mood.anger) > 0.45 and T.courage > 0.4 then
				say(n, "taunt_flee")
				c.t = os.clock()
			else
				say(n, "taunt_flee")
				Mind.calm(n, key, 1.5, "fled")
			end
		end
	elseif verb == "shove" or verb == "punch" then
		local dmg, outcome, _hook, dx, dz = I.hitActor(p, s, n.a, verb)
		local per = n.seen[p.UserId]
		if per then
			per.shoves = ((per.shoveT and os.clock() - per.shoveT < 60) and per.shoves or 0) + 1
			per.shoveT = os.clock()
		end
		if verb == "shove" then
			Memory.event(p, n.id, "shove")
			Mind.hitNPC(n, nil, dmg, "stagger", dx, dz, key)
			local times = per and per.shoves or 1
			if n.downThen == "fight" or (times >= 2 and n.traits.courage > 0.55) then
				say(n, "shove_fight")
				Mind.provoke(n, key, if times >= 2 then 2 else 1.5, "shove", "other")
				n.downThen = "fight"
				n.downKey = key
			elseif times >= 3 and n.traits.civic > 0.5 then
				say(n, "shove_backoff")
				n.downThen = nil
				local inc = World.incident("shove", pos, { aggressor = key, victim = "n:" .. n.id })
				task.delay(1.2, function()
					if n.present and n.mode ~= "custody" then
						Mind.report(n, inc)
					end
				end)
			elseif n.downThen == "flee" or n.downThen == "cower" or n.traits.courage < 0.35 then
				say(n, "shove_backoff")
			else
				say(n, "shove_complain")
				Mind.provoke(n, key, 1, "shove", "other")
				n.downThen = "conflict"
			end
			World.incident("shove", pos, { aggressor = key, victim = "n:" .. n.id })
			I.crime(p, "shove", pos)
		else
			Memory.event(p, n.id, "punch")
			local res = Mind.hitNPC(n, nil, dmg, outcome, dx, dz, key)
			if res ~= "ko" then
				if n.downThen == "fight" then
					say(n, "fight_start")
					Mind.provoke(n, key, 3, "punch", "other")
					n.downThen = "fight"
					n.downKey = key
				elseif n.downThen == "cower" then
					say(n, "cower")
				else
					say(n, "hurt")
				end
			end
			local kind = if res == "ko" then "ko" else "assault"
			if n.arch == "police" then
				kind = "cop_assault"
			end
			World.incident(kind, pos, { aggressor = key, victim = "n:" .. n.id })
			-- self-defence against somebody who started it is a brawl, not an assault
			local selfDefence = c and c.starter == "self"
			if n.arch == "police" then
				I.crime(p, if res == "ko" then "cop_ko" else "cop", pos)
				if Police then
					Police.onCopHit(n, p)
				end
			elseif selfDefence then
				I.crime(p, "brawl", pos)
			else
				I.crime(p, "assault", pos)
				if n.arch == "homeless" or n.arch == "fool" then
					I.crime(p, "weak", pos)
				end
				if res == "ko" then
					I.crime(p, "ko", pos)
				end
			end
		end
	elseif verb == "rob" then
		I.playerSay(p, C.line("player_rob"))
		local TT = C.typeOf(if n.arch == "thug" then "violent" elseif n.arch == "homeless" then "beggar" elseif n.arch == "fool" then "fool" elseif n.arch == "drunk" then "drunk" elseif n.arch == "police" then "police" else "plain")
		local chance = TT.rob * (0.8 + (s.strength or 20) / 250) * (1 - T.courage * 0.4)
		if n.arch == "police" then
			say(n, "rob_refuse")
			Mind.provoke(n, key, 3, "rob_cop", "other")
			I.crime(p, "cop", pos)
			return
		end
		if rnd:NextNumber() < chance then
			local won = math.floor(Mind.range(TT.robWon) / 100 + 0.5) * 100
			if won > 0 then
				I.ctx.ledger(p, "cash", won, "삥 뜯기 (" .. n.name .. ")", false)
			end
			say(n, "robbed")
			Memory.event(p, n.id, "rob")
			Mind.feel(n, { fear = 0.5, v = -0.4 })
			Mind.cower(n, 3)
			task.delay(3, function()
				if n.present and n.mode == "cower" then
					Mind.flee(n, I.feetOf(p), 8, true)
				end
			end)
			I.fire(p, { kind = "pedReact", id = n.id, react = "robbed", won = won })
			World.incident("robbery", pos, { aggressor = key, victim = "n:" .. n.id })
			I.crime(p, "robbery", pos)
			if n.arch == "homeless" or n.arch == "fool" then
				I.crime(p, "weak", pos)
			end
		else
			say(n, "rob_refuse")
			if T.courage + T.aggression > 1 then
				Mind.provoke(n, key, 2.5, "rob", "other")
			else
				Mind.flee(n, me, 6, true)
			end
			World.incident("threat", pos, { aggressor = key, victim = "n:" .. n.id })
			I.crime(p, "rob_try", pos)
		end
	end
end

function Verbs.init(interact: any)
	I = interact
	C = I.C
	Mind = I.Mind
	Talk = I.Talk
	Memory = I.Memory
	World = I.World
	Actors = I.Actors
	Routine = I.Routine
	Police = I.Police
	Places = I.Places
end

return Verbs
