-- GwangalliStreetLife/Mind: the client side of the NPC mind (owner: npc_mind). The server
-- (GwangalliGameplay/Mind) decides what people say and feel; this module makes it visible and alive:
--   * BUBBLE CONVERSATIONS: 말 걸기 on a named citizen (or the citizen walking up to you) opens a
--     session: the NPC stops, faces you and talks in bubbles over the head (typing beat, one bubble
--     per line, a face + a gesture); your answers (chips or free text, MindUI) appear in a bubble over
--     YOUR head. People standing close hear it and sometimes chime in. Walking away ends it (걸렁뱅이 /
--     불량배 shout after you).
--   * WHO TALKS FIRST: 걸렁뱅이 stare then throw a line in passing or walk up (뭘 봐? / 야 너 잠깐 와봐 /
--     거기 너 말이야 ...), 동네바보 pranks (어깨빵 with a chance + cooldown, 길막, 앞에서 얼쩡, 갑자기
--     방향 틀기, 빤히 보고 따라오기, 이상한 말 하고 도망갔다 돌아오기), 노숙자 천원만, 불량배 at night,
--     a patrolling officer's question, friends who wave you over.
--   * FEELINGS ON THE STREET: scared people keep away from you, angry ones glare and mutter, friends
--     and lovers greet you (views from the server: disp = friendly | hostile | scared).
--   * NPC <-> NPC: pairs of people near the player play short scenes in bubbles (friends, couples,
--     clerk + customer, police + citizen, drunks arguing / fighting, 걸렁뱅이 picking on a passer-by,
--     동네바보, 노숙자, 부자, tourists asking the way, grannies and students).
--   * CRIME: after you hit somebody (or the server says you are wanted) the people around react by
--     personality - flee, watch, film, call 112, step in, cheer, gang up - and police officers (street
--     life agents) are dispatched to you: questioning (사과 / 변명 / 욕 / 도주), chase, arrest, fines.
-- Agents under this module's control carry a.ctl = {kind, ...}: Agent.think hands them to Mind.drive
-- and skips their own plan / schedule meanwhile (Agent / Crowd check a.ctl).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Mind = {}

local ctx: any
local M: any -- GwangalliMindShared
local L: any -- GwangalliMindLines
local UI: any -- MindUI
local Face: any
local Anim: any
local BUMP: any
local Social: any
local Citizens: any
local player = Players.LocalPlayer
local rng = Random.new()
local function rnd(): number
	return rng:NextNumber()
end

local remotes: { Talk: RemoteFunction?, Event: RemoteEvent?, Get: RemoteFunction? } = {}
local ready = false
local views: { [string]: any } = {}
local contacts: { [string]: boolean } = {}
local talk: any = nil
local police: any = { agent = nil, state = nil }
local scenes: { any } = {}
local nextScene = 0
local stats = { sessions = 0, says = 0, scenes = 0, pranks = 0, provokes = 0, witnesses = 0, dispatches = 0 }
Mind.stats = stats

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end
local function pack(v: Vector3): { number }
	return { math.floor(v.X * 10 + 0.5) / 10, math.floor(v.Y * 10 + 0.5) / 10, math.floor(v.Z * 10 + 0.5) / 10 }
end
local function pick(list: { any }?): any
	if not list or #list == 0 then
		return nil
	end
	return list[1 + math.floor(rnd() * #list)]
end

local function playerPos(): Vector3?
	return ctx.Crowd.playerPos()
end

local function debugOn(): boolean
	return workspace:GetAttribute("GwangalliStreetLifeDebug") == true
end
local function dbg(...: any)
	if debugOn() then
		print("[GwangalliMind:dbg]", ...)
	end
end

-------------------------------------------------------------------------------------------------
-- remotes
-------------------------------------------------------------------------------------------------
local function invoke(op: string, payload: any): any
	local f = remotes.Talk
	if not f then
		return nil
	end
	local ok, res = pcall(function()
		return (f :: RemoteFunction):InvokeServer(op, payload)
	end)
	if not ok then
		dbg("invoke", op, res)
		return nil
	end
	return res
end
Mind.invoke = invoke

local function setView(id: string, v: any)
	if type(v) ~= "table" then
		return
	end
	local old = views[id]
	views[id] = v
	if v.number then
		contacts[id] = true
	end
	-- a newly learnt name shows on the chip
	if not old or old.name ~= v.name or old.stage ~= v.stage then
		local a = ctx.Crowd.byId[id]
		if a and a.rig and a.rig.chip then
			a.rig.chipDirty = true
		end
	end
end

function Mind.view(id: string): any?
	return views[id]
end

-- the name over a head: known names only (the job / type hint until they tell you)
function Mind.displayName(a: any): string?
	if not a or not a.named or not a.c then
		return nil
	end
	local v = views[a.id]
	if (v and v.name) or contacts[a.id] then
		return a.c.name
	end
	return "???"
end

function Mind.ready(): boolean
	return ready
end

-------------------------------------------------------------------------------------------------
-- bubbles / faces / gestures
-------------------------------------------------------------------------------------------------
local function pool(): any
	if not BUMP or type(BUMP.bubbles) ~= "function" then
		return nil
	end
	local ok, p = pcall(BUMP.bubbles, { types = Social and Social.TYPES })
	return if ok then p else nil
end

local function sayNpc(a: any, text: string, dur: number?)
	if a and not a.gone and type(text) == "string" and text ~= "" then
		ctx.SocialUI.say(a, text, dur or 4)
	end
end

local function lineDur(text: string): number
	local n = utf8.len(text) or #text / 3
	return math.clamp(1.7 + n * 0.075, 2.4, 6.5)
end

local function sayPlayer(text: string, dur: number?)
	local ch = player.Character
	local head = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
	local p = pool()
	if p and head and head:IsA("BasePart") then
		p:say(head, text, "player", dur or lineDur(text), if head.Name == "Head" then 2.4 else 4.2)
	end
end
Mind.sayPlayer = sayPlayer

local function face(a: any, expr: string?, dur: number?)
	if Face and a and a.rig and not a.gone then
		pcall(Face.set, a.rig, expr, dur)
	end
end

local function lookAtPlayer(a: any, dur: number)
	local pp = playerPos()
	if pp then
		a:lookAtPoint(pp + Vector3.new(0, 1.5, 0), dur, os.clock())
	end
end

local function gesture(a: any, emote: string?)
	if not emote or not a or a.gone or a.knock then
		return
	end
	local rig = a.rig
	local now = os.clock()
	if emote == "wave" or emote == "laugh" or emote == "cheer" or emote == "point" then
		if a.sitting or a.sitGround then
			Anim.flash(rig, if emote == "point" then "pointp" else "wavep", 1.4)
		else
			Anim.gesture(rig, emote)
		end
	elseif emote == "think" then
		Anim.flash(rig, "think", 2.4)
	elseif emote == "refuse" then
		a:emote("refuse")
	elseif emote == "shy" then
		Anim.flash(rig, "wavep", 1.0)
		Anim.look(rig, 0.35, -0.25)
		a.gazeUntil = now + 1.2
	elseif emote == "nod" then
		Anim.look(rig, 0, -0.35)
		a.gazeUntil = now + 0.45
		task.delay(0.35, function()
			if not a.gone then
				lookAtPlayer(a, 2)
			end
		end)
	elseif emote == "shrug" then
		Anim.flash(rig, "wait", 1.2)
	elseif emote == "cross" then
		Anim.flash(rig, "cross", 2.6)
	elseif emote == "startle" then
		Anim.flash(rig, "startle", 0.9)
	elseif emote == "clap" then
		Anim.flash(rig, "clap", 1.6)
	elseif emote == "phone" then
		Anim.setRestPose(rig, "phone")
		task.delay(3, function()
			if not a.gone and a.mode == "talk" then
				Anim.setRestPose(rig, "chat")
			end
		end)
	elseif emote == "dance" then
		a:setAnim("dance")
		task.delay(2.2, function()
			if not a.gone and a.animState == "dance" and a.mode ~= "walk" then
				a:setAnim("idle")
			end
		end)
	elseif emote == "turn" then
		-- looks away for a moment (무시 / 고개 돌리기)
		Anim.look(rig, if rnd() < 0.5 then 1.1 else -1.1, -0.1)
		a.gazeUntil = now + 1.6
	elseif emote == "look" then
		lookAtPlayer(a, 2.5)
	end
end

-------------------------------------------------------------------------------------------------
-- control helpers (a.ctl): movement primitives for agents this module drives
-------------------------------------------------------------------------------------------------
local function moveTo(a: any, p: Vector3, speed: number)
	local target = Vector3.new(p.X, a.pos.Y, p.Z)
	a.nav = { mode = "points", pts = { target }, i = 1 }
	a.mode = "walk"
	a.faceYaw = nil
	a.pauseUntil = 0
	a.want = speed
	a.sitting, a.lying, a.napping = false, false, false
	if a.sitGround then
		a.sitGround = false
		Anim.legs(a.rig, nil)
	end
	a:releasePoi()
	a:segTo(target, nil, nil)
	a.node = nil
	a.moved = true
end

local function hold(a: any, faceTo: Vector3?, pose: string?)
	a.want, a.speed, a.nav = 0, 0, nil
	if a.mode == "walk" then
		a:stopMoving()
	end
	a.mode = "idle"
	a.idleKind = "idle"
	a.idleUntil = os.clock() + 1e6
	if faceTo then
		a.faceYaw = yawOf(faceTo.X - a.pos.X, faceTo.Z - a.pos.Z)
	end
	if pose ~= nil then
		Anim.setRestPose(a.rig, if pose == "" then nil else pose)
	end
	a:setAnim("idle")
	a.moved = true
end

local function take(a: any, ctl: any): boolean
	if not a or a.gone or a.knock or a.companion or a.clubGuest or a.riding or a.mode == "follow" or a.mode == "member" then
		return false
	end
	if a.leader then
		ctx.Crowd.detachMember(a)
	end
	ctx.Crowd.queue.leave(a)
	a:releasePoi()
	a.chase = nil
	ctl.since = os.clock()
	a.ctl = ctl
	return true
end

local function release(a: any, leave: boolean?)
	if not a or not a.ctl then
		return
	end
	a.ctl = nil
	if a.gone then
		return
	end
	local now = os.clock()
	Anim.setRestPose(a.rig, nil)
	a.node = ctx.World.nearest(a.pos, 40)
	a.prev = nil
	a.want, a.speed, a.nav = 0, 0, nil
	if a.mode == "talk" then
		a:endTalk(now)
		return
	end
	if leave then
		a:setPlan({ kind = "leave", act = "walk" }, now)
	else
		a:idleFor("idle", 1 + rnd() * 1.5, now, a.faceYaw)
	end
end
Mind.release = release
Mind.take = take
Mind.street = function(id: string, ev: string, pos: Vector3?)
	task.spawn(function()
		invoke("street", { id = id, ev = ev, pos = if pos then pack(pos) else nil })
	end)
end
Mind.sayNpc = function(a: any, text: string, dur: number?)
	sayNpc(a, text, dur)
end
Mind.face = function(a: any, expr: string?, dur: number?)
	face(a, expr, dur)
end
Mind.hold = function(a: any, faceTo: Vector3?, pose: string?)
	hold(a, faceTo, pose)
end
Mind.moveTo = function(a: any, p: Vector3, speed: number)
	moveTo(a, p, speed)
end

-------------------------------------------------------------------------------------------------
-- conversation sessions
-------------------------------------------------------------------------------------------------
local ASK_LABEL = {
	how = "😊 요즘 어때?", doing = "👀 뭐 해?", name = "🏷️ 이름이 뭐예요?", age = "🎂 몇 살이에요?", job = "💼 무슨 일 해요?",
	food_q = "🍽️ 좋아하는 음식?", like_q = "💝 좋아하는 거?", hobby_q = "🎨 취미가 뭐예요?", place_q = "📍 추천할 곳?",
	news_q = "📰 요즘 무슨 일 있어요?", number = "📱 번호 줄래요?",
}
local TALK_LABEL = { food_talk = "🍢 음식 이야기", gift_talk = "🎁 선물 이야기", weather = "☀️ 날씨 이야기", comfort = "🫂 위로하기", brag = "😎 자랑하기", flirt = "😘 작업 걸기" }

-- answers to the NPC's own questions: label -> what it means
local ASK_CHIPS = {
	punk = { { label = "뭐요?", intent = "provoke" }, { label = "죄송합니다", intent = "apologize" }, { label = "그냥 지나가던 길이에요", intent = "no" }, { label = "너나 잘해", intent = "insult" }, { label = "(무시하고 간다)", ignore = true } },
	thug = { { label = "싫은데요", intent = "provoke" }, { label = "죄송합니다…", intent = "apologize" }, { label = "경찰 부를까요?", intent = "threaten" }, { label = "💵 만원 드릴게요", act = "money", arg = 10000 }, { label = "(무시하고 간다)", ignore = true } },
	beg = { { label = "💵 천원 드릴게요", act = "money", arg = 1000 }, { label = "💵 오천원 드릴게요", act = "money", arg = 5000 }, { label = "🍲 밥 사 드릴게요", sub = "food" }, { label = "죄송해요", intent = "no" } },
	fool = { { label = "그래 친구 하자", intent = "yes" }, { label = "ㅋㅋ 짜지", intent = "joke" }, { label = "✊ 가위바위보!", act = "play", arg = "rps" }, { label = "저리 가", intent = "no" } },
	foolbump = { { label = "ㅋㅋ 괜찮아요", street = "laughed", intent = "yes" }, { label = "야! 조심 좀 해!", street = "scolded", intent = "provoke" }, { label = "(무시한다)", ignore = true } },
}

local function closeTo(a: any): boolean
	local v = views[a.id]
	return v ~= nil and ((v.aff or 0) >= 50 or v.lover == true)
end

local function playerVars(): any
	return { you = player.DisplayName, tod = "하루" }
end

local function finish(reason: string?)
	local t = talk
	if not t then
		return
	end
	talk = nil
	UI.close()
	invoke("close", { id = t.id })
	local a = t.a
	if a and not a.gone then
		if a.chatState then
			a:endChat(os.clock(), false)
		end
		if a.ctl and a.ctl.kind == "talk" then
			a.ctl = nil
		end
		if reason == "leave" then
			a:setPlan({ kind = "leave", act = "walk" }, os.clock())
		elseif a.mode == "talk" then
			a:endTalk(os.clock())
		end
	end
	dbg("finish", t.id, reason)
end
Mind.finish = finish

function Mind.busy(): boolean
	return talk ~= nil
end

-- sequence the NPC's lines as bubbles; then(after) when done
local function playOut(a: any, out: any, after: (() -> ())?)
	if type(out) ~= "table" then
		if after then
			after()
		end
		return
	end
	local lines = out.lines or {}
	local delay = 0
	face(a, out.face, 2 + #lines * 3)
	gesture(a, out.emote)
	for i, text in lines do
		local d = lineDur(text)
		task.delay(delay, function()
			if not a.gone then
				sayNpc(a, text, d + 0.4)
			end
		end)
		delay += d * 0.85
	end
	task.delay(math.max(0.1, delay - 0.6), function()
		if after then
			after()
		end
	end)
	return delay
end

-- somebody close hears it: a turned head, sometimes a word
local CHIME = {
	insult = { "와… 말이 좀 심하다…", "헐, 저렇게까지?", "싸우는 거야?", "에이, 왜 그래요~" },
	provoke = { "어? 싸우나 봐…", "저기요, 진정하세요~", "괜히 끼지 말자…" },
	compliment = { "오~ 부럽다 ㅋㅋ", "나한테도 그런 말 해 줘 ㅋㅋ", "훈훈하네~" },
	joke = { "ㅋㅋㅋ 웃기네", "푸핫 ㅋㅋ", "아 나도 웃었다 ㅋㅋ" },
	flirt = { "어머 ㅋㅋㅋ", "오~ 분위기 뭐야 ㅋㅋ", "둘이 잘 어울린다~" },
	confess = { "헐 고백이다!!", "대박 ㅋㅋ 받아 줘!", "오오오~" },
	gift_r = { "와 선물이다!", "좋겠다~", "나도 받고 싶다 ㅋㅋ" },
	friend = { "얘 원래 이래요 ㅋㅋ", "아 쟤 내 친구예요!", "{b}야, 누구야? ㅋㅋ" },
}
local function chime(target: any, intent: string)
	local bank = CHIME[intent]
	if not bank then
		return
	end
	local now = os.clock()
	for _, o in ctx.Crowd.agents do
		if o ~= target and not o.gone and o.near and not o.ctl and o.mode ~= "talk" and not o.knock and not o.companion then
			local d = flatDist(o.pos, target.pos)
			if d < 9 then
				o:lookAtPoint(target.pos + Vector3.new(0, 1.6, 0), 3, now)
				if rnd() < 0.3 and ctx.Crowd.canSay(now) then
					local friends = o.named and target.named and Citizens and Citizens.areFriends(o.id, target.id)
					local line = if friends and rnd() < 0.6 then pick(CHIME.friend) else pick(bank)
					if line then
						line = string.gsub(line, "{b}", (Citizens and target.named and Citizens.shortName(target.id)) or "")
						task.delay(0.8 + rnd(), function()
							sayNpc(o, line, 3)
						end)
					end
					return
				end
			end
		end
	end
end

local refreshChips: (() -> ())

local handleAct: (any, any) -> ()

local function applyResult(res: any, intent: string?)
	local t = talk
	if not t or type(res) ~= "table" then
		return
	end
	if res.view then
		setView(t.id, res.view)
		UI.setView(res.view)
	end
	if type(res.wanted) == "number" then
		UI.setWanted(res.wanted)
	end
	local out = res.out
	if type(out) == "table" and type(out.lines) == "table" then
		stats.lastReply = table.concat(out.lines, " / ") .. " [" .. tostring(out.intent) .. "/" .. tostring(out.act) .. "]"
	end
	if not out then
		return
	end
	local a = t.a
	-- answers to the NPC's question (chips), mapped to what they mean
	if out.ask and type(out.ask.chips) == "table" then
		local mapped = ASK_CHIPS[out.ask.kind]
		local list = {}
		if mapped then
			for _, spec in mapped do
				table.insert(list, spec)
			end
		else
			for _, label in out.ask.chips do
				table.insert(list, { label = M.fill(label, playerVars()), text = M.fill(label, playerVars()) })
			end
		end
		UI.setAnswers(list)
	else
		UI.setAnswers(nil)
	end
	chime(a, out.intent or intent or "")
	playOut(a, out, function()
		if talk ~= t then
			return
		end
		handleAct(t, out)
	end)
	refreshChips()
end

local function send(spec: any)
	local t = talk
	if not t then
		return
	end
	if t.busy then
		-- they are still answering: say it right after (one message waits, the newest wins)
		t.pending = spec
		return
	end
	local a = t.a
	if a.gone then
		finish("gone")
		return
	end
	local pp = playerPos()
	if not pp or flatDist(pp, a.pos) > M.TALK_RANGE then
		finish("far")
		return
	end
	if spec.ignore then
		invoke("street", { id = t.id, ev = "ignored", pos = pack(a.pos) })
		sayPlayer(M.playerLine("ignore", false, playerVars(), rnd), 2.5)
		local l = M.line(a.c, "ignore", { you = player.DisplayName })
		finish("ignore")
		-- 걸렁뱅이: walking off on him mostly ends in a fight (GwangalliStreetLife/Characters)
		if t.kind == "punk" and Mind.punkIgnored and Mind.punkIgnored(a) then
			return
		end
		if l then
			task.delay(0.8, function()
				sayNpc(a, l, 3.5)
				gesture(a, "point")
			end)
		end
		return
	end
	if spec.street then
		invoke("street", { id = t.id, ev = spec.street, pos = pack(a.pos) })
	end
	if spec.sub == "food" then
		UI.openSub("🍲 뭐 사 드릴까요?", Mind.foodChips())
		return
	end
	if spec.act then
		Mind.act(spec.act, spec.arg)
		return
	end
	local close = closeTo(a)
	local text = spec.text
	local intent = spec.intent
	-- an answer chip says its own words; a topic chip gets a fresh sentence for that topic
	local said = text or (if spec.label and not spec.id then spec.label else nil) or (intent and M.playerLine(intent, close, { you = player.DisplayName, item = spec.itemName or "그거", tod = "하루" }, rnd)) or "…"
	sayPlayer(said)
	t.busy = true
	stats.says += 1
	local who = Mind.displayName(a) or ""
	UI.typing(true, who)
	-- NPC turns to listen: head on the player, a small listening pose
	lookAtPlayer(a, 3)
	task.spawn(function()
		local t0 = os.clock()
		local res = invoke("say", { id = t.id, pos = pack(a.pos), intent = if text then nil else intent, text = text, item = spec.item, polite = not close })
		local wait = 0.55 + rnd() * 0.5 - (os.clock() - t0)
		if wait > 0 then
			task.wait(wait)
		end
		if talk ~= t then
			return
		end
		t.busy = false
		UI.typing(false)
		if not res or not res.ok then
			if res and res.err == "far" then
				finish("far")
			elseif res and res.err == "slow" then
				sayNpc(a, "잠깐만, 천천히 말해 ㅎㅎ", 2.5)
			end
			return
		end
		applyResult(res, intent)
		local nxt = t.pending
		if nxt then
			t.pending = nil
			task.delay(1.6, function()
				if talk == t then
					send(nxt)
				end
			end)
		end
	end)
end

-- interactions: gift / food / money / play / meet / hit
local ACT_SAY = {
	gift = { "이거 선물이에요! 🎁", "작은 거지만 받아 주세요 🎁", "선물 받아 ㅎㅎ 🎁" },
	food = { "{item} 사 드릴게요!", "{item} 먹을래요? 제가 살게요!", "자, {item}! 먹어요 ㅎㅎ" },
	money = { "이거 받으세요 ({item})", "용돈이에요 ㅋㅋ ({item})", "({item}을 건넨다)" },
	play = { rps = "가위바위보 할래요? ✊", selfie = "우리 같이 셀카 찍어요! 📸", walk = "같이 다닐래요?", prank = "(장난을 친다) 왁!" },
	meet = { "{item} 어때요?", "우리 {item}! 콜?", "다음에 {item} 할래요?" },
	hit = { "(주먹을 휘두른다) 에잇!", "(퍽!)", "(밀쳐 버린다)" },
}

function Mind.act(act: string, arg: any)
	local t = talk
	if not t or t.busy then
		return
	end
	local a = t.a
	local pp = playerPos()
	if not pp or a.gone or flatDist(pp, a.pos) > M.TALK_RANGE then
		finish("far")
		return
	end
	local itemName = ""
	if act == "gift" then
		local g = Social.GIFTS[arg]
		itemName = g and g.name or "선물"
	elseif act == "food" then
		local f = M.FOODS[arg]
		itemName = f and f.name or "음식"
	elseif act == "money" then
		itemName = M.won(tonumber(arg) or 0)
	elseif act == "meet" then
		local inv = Social.INVITES[arg]
		itemName = inv and inv.label or "약속"
	end
	local bank = ACT_SAY[act]
	local said = if act == "play" then (bank[arg] or "같이 놀자!") else (pick(bank) or "")
	sayPlayer(M.fill(said, { item = itemName }))
	t.busy = true
	UI.typing(true, Mind.displayName(a) or "")
	if act == "hit" then
		-- the hit lands: they stagger / go down right away (the reaction follows the server's answer)
		local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
		local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
		local outcome = if rnd() < 0.35 then "knockdown" else "stagger"
		if a.mode == "talk" then
			a:endTalk(os.clock())
		end
		a:knockDown(dx / d, dz / d, outcome, pick(Social.PUK))
		if BUMP and BUMP.shakeCamera then
			pcall(BUMP.shakeCamera, 0.12, 0.25)
		end
	end
	task.spawn(function()
		local res = invoke("act", { id = t.id, pos = pack(a.pos), act = act, arg = arg })
		task.wait(0.35 + rnd() * 0.4)
		if talk ~= t then
			return
		end
		t.busy = false
		UI.typing(false)
		if not res or not res.ok then
			if res and res.err == "far" then
				finish("far")
			end
			return
		end
		applyResult(res, act .. "_r")
	end)
end

-- the reaction a reply asks for (after its bubbles)
handleAct = function(t: any, out: any)
	local a = t.a
	local act = out.act
	if not act or a.gone then
		return
	end
	local pp = playerPos()
	if act == "end" then
		finish("bye")
	elseif act == "block" then
		-- they won't talk to you now (GwangalliGameplay.Mind gate): a turned head, then they move on
		face(a, "annoyed", 3)
		gesture(a, "turn")
		finish("leave")
	elseif act == "ignore" or act == "brush" then
		-- they never really stopped: back to their way at once
		finish("leave")
	elseif act == "leave" or act == "backoff" then
		finish("leave")
	elseif act == "flee" then
		finish("flee")
		if pp then
			Mind.flee(a, pp, 6)
		end
	elseif act == "report" then
		finish("report")
		Mind.report(a)
	elseif act == "fight" and ctx.Crowd.api then
		-- they hit back: a real scuffle (several swings that only land within reach)
		finish("fight")
		ctx.Crowd.api("brawl", a.id, 9 + rnd() * 5)
		ctx.Crowd.api("remember", a.id, "anger", 2)
	elseif act == "ko" and ctx.Crowd.api then
		finish("ko")
		local dx, dz = 0, -1
		if pp then
			local ddx, ddz = a.pos.X - pp.X, a.pos.Z - pp.Z
			local dd = math.max(0.1, math.sqrt(ddx * ddx + ddz * ddz))
			dx, dz = ddx / dd, ddz / dd
		end
		ctx.Crowd.api("ko", a.id, dx, dz, 26)
	elseif act == "cower" and ctx.Crowd.api then
		finish("flee")
		ctx.Crowd.api("react", a.id, "cower")
		ctx.Crowd.api("remember", a.id, "fear", 2)
	elseif act == "shove" or act == "fight" then
		if pp and a.hitPlayer then
			local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
			local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
			task.delay(0.3, function()
				if not a.gone and not a.knock then
					Anim.flash(a.rig, "pointp", 0.6)
					a:hitPlayer(dx / d, dz / d, if act == "fight" then "knockdown" else "stagger", nil)
				end
			end)
		end
		if act == "fight" then
			finish("fight")
		end
	elseif act == "escalate" then
		face(a, "angry", 5)
		gesture(a, "cross")
	elseif act == "arrest" then
		finish("arrest")
		Mind.policeEncounter(a, true)
	elseif act == "meet_menu" then
		UI.openSub("📅 뭐 할까?", Mind.meetChips(a))
	elseif act == "lover" then
		gesture(a, "cheer")
		face(a, "love", 8)
	elseif act == "breakup" then
		face(a, "sad", 6)
		finish("leave")
	end
end

-------------------------------------------------------------------------------------------------
-- chips
-------------------------------------------------------------------------------------------------
function Mind.foodChips(): { any }
	local out = {}
	local v = talk and views[talk.id]
	local minor = talk and talk.a.c and talk.a.c.minor
	for _, fid in M.FOOD_ORDER do
		local f = M.FOODS[fid]
		if f and not (f.adult and minor) then
			local mark = ""
			if v and v.known then
				for _, k in v.known.foods or {} do
					if string.find(k, f.name, 1, true) then
						mark = " 💖"
					end
				end
				if v.known.nofood == f.name then
					mark = " 😕"
				end
			end
			table.insert(out, { id = "food:" .. fid, label = string.format("%s %s %s%s", f.icon, f.name, M.won(f.price), mark), act = "food", arg = fid })
		end
	end
	return out
end

local function giftChips(): { any }
	local out = {}
	local v = talk and views[talk.id]
	for _, gid in Social.GIFT_ORDER do
		local g = Social.GIFTS[gid]
		if g then
			local mark = ""
			if v and v.known then
				for _, k in v.known.gifts or {} do
					if string.find(k, g.name, 1, true) then
						mark = " 💖"
					end
				end
			end
			table.insert(out, { id = "gift:" .. gid, label = string.format("%s %s %s%s", g.icon, g.name, M.won(g.price), mark), act = "gift", arg = gid })
		end
	end
	return out
end

function Mind.meetChips(a: any): { any }
	local out = {}
	local minor = a and a.c and a.c.minor
	for _, m in M.MEET do
		local inv = Social.INVITES[m.id]
		if inv and not (minor and (inv.adult or m.id == "club")) then
			table.insert(out, { id = "meet:" .. m.id, label = m.label, act = "meet", arg = m.id })
		end
	end
	return out
end

local function topicFoodChips(): { any }
	local out = {}
	for i, fid in M.FOOD_ORDER do
		if i % 2 == 1 or #out < 6 then
			local f = M.FOODS[fid]
			table.insert(out, { id = "ft:" .. fid, label = f.icon .. " " .. f.name, intent = "food_talk", item = fid, itemName = f.name })
		end
		if #out >= 9 then
			break
		end
	end
	return out
end

refreshChips = function()
	local t = talk
	if not t then
		return
	end
	local v = views[t.id] or {}
	local a = t.a
	local aff = v.aff or 0
	local adult = not (a.c and a.c.minor)
	local list = {}
	local function add(spec)
		table.insert(list, spec)
	end
	add({ id = "greet", label = "👋 인사", intent = "greet" })
	local askSub = {}
	for _, intent in { "how", "doing", "name", "age", "job", "food_q", "like_q", "hobby_q", "place_q", "news_q", "number" } do
		if not (intent == "name" and v.name) then
			table.insert(askSub, { id = intent, label = ASK_LABEL[intent], intent = intent })
		end
	end
	add({ id = "ask", label = "❓ 질문", sub = askSub })
	add({ id = "joke", label = "😂 농담", intent = "joke" })
	add({ id = "compliment", label = "😊 칭찬", intent = "compliment" })
	local talkSub = { { id = "food_talk", label = TALK_LABEL.food_talk, openSub = true } }
	for _, k in { "gift_talk", "weather", "comfort", "brag" } do
		table.insert(talkSub, { id = k, label = TALK_LABEL[k], intent = k })
	end
	if adult then
		table.insert(talkSub, { id = "flirt", label = TALK_LABEL.flirt, intent = "flirt" })
	end
	add({ id = "talkabout", label = "💬 이야기", sub = talkSub })
	add({ id = "request", label = "🤝 부탁", intent = "request" })
	add({ id = "apologize", label = "🙏 사과", intent = "apologize" })
	add({ id = "gift", label = "🎁 선물", sub = giftChips })
	add({ id = "food", label = "🍢 음식 사주기", sub = Mind.foodChips })
	add({ id = "money", label = "💵 돈 주기", sub = function()
		local s = {}
		for _, n in M.MONEY do
			table.insert(s, { id = "money:" .. n, label = "💵 " .. M.won(n), act = "money", arg = n })
		end
		return s
	end })
	add({ id = "play", label = "🎮 같이 놀기", sub = function()
		local s = {}
		for _, p in M.PLAY do
			table.insert(s, { id = "play:" .. p.id, label = p.label, act = "play", arg = p.id })
		end
		return s
	end })
	if aff >= 15 or v.lover then
		add({ id = "meet", label = "📅 약속 잡기", sub = function()
			return Mind.meetChips(a)
		end })
	end
	if adult and (aff >= 55 or v.lover) then
		add({ id = "confess", label = if v.lover then "💘 사랑해" else "💘 고백하기", intent = if v.lover then "flirt" else "confess" })
	end
	add({ id = "insult", label = "🤬 욕하기", intent = "insult", danger = true })
	add({ id = "provoke", label = "😠 시비 걸기", intent = "provoke", danger = true })
	add({ id = "hit", label = "👊 때리기", act = "hit", danger = true })
	add({ id = "bye", label = "👋 작별", intent = "bye" })
	UI.setChips(list)
end

local function onChip(spec: any)
	if spec.openSub then
		UI.openSub("🍢 무슨 음식?", topicFoodChips())
		return
	end
	if spec.act then
		Mind.act(spec.act, spec.arg)
	elseif spec.intent then
		send({ intent = spec.intent, item = spec.item, itemName = spec.itemName })
	elseif spec.text then
		send({ text = spec.text })
	end
end

-- open a conversation with a citizen agent. kind: who started it ("talk" = the player)
function Mind.begin(a: any, kind: string?): boolean
	if not ready or not a or a.gone or not a.named or not a.c or a.c.key then
		return false
	end
	if talk and talk.a == a then
		return true
	end
	if talk then
		finish("switch")
	end
	if police.agent and police.state then
		return false -- the police have the player's attention
	end
	local now = os.clock()
	if a.ctl then
		release(a)
	end
	a:beginTalk(now, 600)
	a.ctl = { kind = "talk", since = now }
	local t = { a = a, id = a.id, kind = kind or "talk", busy = true, since = now }
	talk = t
	stats.sessions += 1
	local v = views[a.id] or { label = "", job = a.c.job, stageIcon = "🤍", stageLabel = "모르는 사이" }
	UI.open(v, {
		onChip = onChip,
		onAnswer = function(spec)
			send(spec)
		end,
		onSend = function(text)
			send({ text = text })
		end,
		onClose = function()
			if talk and (talk.kind == "punk" or talk.kind == "thug") then
				send({ ignore = true })
			else
				send({ intent = "bye" })
				task.delay(2.5, function()
					if talk == t then
						finish("close")
					end
				end)
			end
		end,
	})
	refreshChips()
	lookAtPlayer(a, 4)
	task.spawn(function()
		local res = invoke("open", { id = a.id, pos = pack(a.pos), kind = t.kind })
		if talk ~= t then
			return
		end
		t.busy = false
		if not res or not res.ok then
			dbg("open failed", a.id, res and res.err)
			finish("open")
			return
		end
		if res.view then
			setView(a.id, res.view)
			UI.setView(res.view)
		end
		if res.out then
			applyResult(res, nil)
		else
			-- the player starts: an automatic hello from the player
			send({ intent = "greet" })
		end
	end)
	return true
end

-- the agent walked up to the player itself (Agent.startChat) / a prank ended in a talk
function Mind.npcStart(a: any, kind: string): boolean
	if talk or police.state then
		return false
	end
	return Mind.begin(a, kind)
end

-------------------------------------------------------------------------------------------------
-- street behaviours (called from Agent.typeReact for close agents; true = handled)
-------------------------------------------------------------------------------------------------
local lastPrank = -1e9
local lastProvoke = -1e9
local lastQuarrel = -1e9
local lastMood = -1e9

local function canAct(now: number, a: any): boolean
	if talk or police.state or not ready then
		return false
	end
	if ctx.Crowd.playerSeated() or not ctx.Crowd.canChat(now, a) then
		return false
	end
	return true
end

-- 동네바보: pick a prank (each with its own odds); never the same one twice in a row
local PRANKS = { { "bump", 6 }, { "block", 3 }, { "cut", 2 }, { "stare", 2 }, { "weird", 2 } }
local function choosePrank(a: any): string
	local total = 0
	for _, p in PRANKS do
		if p[1] ~= a.lastPrank then
			total += p[2]
		end
	end
	local x = rnd() * total
	for _, p in PRANKS do
		if p[1] ~= a.lastPrank then
			x -= p[2]
			if x <= 0 then
				return p[1]
			end
		end
	end
	return "bump"
end

local function foolLine(a: any, key: string): string?
	return M.line(a.c or { id = a.id, type = "fool", speech = "std" }, key, { you = player.DisplayName })
end

function Mind.react(a: any, now: number, pp: Vector3, d: number, pspeed: number): boolean
	if not ready or a.ctl or a.knock or a.chatState or a.mode == "talk" or a.companion then
		return false
	end
	local t = a.type
	local standing = not (a.sitting or a.lying or a.sitGround or a.napping)
	-- what you did to them a moment ago (short memory, GwangalliStreetAPI "remember"): you come
	-- close again -> the angry ones glare and tell you off, the scared ones back away
	local mem = a.memory
	if mem and now < mem.untilT and d < 7.5 and now >= (a.memNext or 0) and standing then
		a.memNext = now + 8
		if mem.fear >= mem.anger then
			face(a, "scared", 3)
			if ctx.Crowd.canSay(now) then
				sayNpc(a, pick({ "오, 오지 마세요!", "또 왜 와요…!", "저리 가요, 경찰 부를 거예요!", "(움찔한다)" }), 2.5)
			end
			Mind.flee(a, pp, 4)
		else
			face(a, "angry", 4)
			lookAtPlayer(a, 3)
			if ctx.Crowd.canSay(now) then
				sayNpc(a, pick({ "또 너냐?", "아까 그 사람이네… 저리 가.", "한 번만 더 해 봐.", "눈 깔아라." }), 3)
			end
			gesture(a, "point")
		end
		return true
	end
	-- the relation (-100..100) and their personality decide the street reaction (Mind.policy)
	local v = a.named and views[a.id]
	local ap = v and v.approach
	if ap and standing and now >= (a.apNext or 0) and ctx.Crowd.canChat(now, a) then
		local RL = M.REL_LINES
		if ap == "flee" and d < 12 then
			a.apNext = now + 10
			face(a, "scared", 3)
			sayNpc(a, pick(RL.scared), 2.5)
			Mind.flee(a, pp, 5)
			return true
		elseif ap == "avoid" and d < 8 then
			a.apNext = now + 12
			if take(a, { kind = "flee", untilT = now + 4, from = pp }) then
				local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				moveTo(a, Vector3.new(a.pos.X + dx / dd * 10, a.pos.Y, a.pos.Z + dz / dd * 10), 5.5)
				if rnd() < 0.5 then
					sayNpc(a, pick(RL.avoid), 2.2)
				end
				return true
			end
		elseif ap == "glare" and d < 9 then
			a.apNext = now + 14
			face(a, "angry", 3)
			lookAtPlayer(a, 2.5)
			sayNpc(a, pick(RL.glare), 2.2)
		elseif (ap == "provoke" or ap == "hostile") and d < (if ap == "hostile" then 14 else 9) and d > 1.5 then
			a.apNext = now + (if ap == "hostile" then 18 else 26)
			face(a, "angry", 4)
			lookAtPlayer(a, 3)
			sayNpc(a, pick(if ap == "hostile" then RL.hostile else RL.provoke), 3)
			gesture(a, "point")
			if d < 4 and a.hitPlayer and rnd() < (if ap == "hostile" then 0.6 else 0.35) then
				-- 밀치기
				local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				a:hitPlayer(dx / dd, dz / dd, "stagger", nil)
			elseif ap == "hostile" and Mind.startFight and rnd() < 0.35 then
				Mind.startFight(a, "hostile")
			elseif d >= 4 and a.approachPlayer and rnd() < 0.5 then
				a:approachPlayer(now, pp, 2.5, "approach")
			end
			return true
		elseif ap == "greet" and d < 11 and d > 2.5 and now - (a.greetAt or -1e9) > 240 then
			a.apNext = now + 30
			a.greetAt = now
			local rel = v.rel or 0
			local list = if v.npcMood == "DRUNK" then RL.greet_drunk elseif rel >= 50 then RL.greet_close elseif rel >= 20 then RL.greet_friendly else RL.greet_kind
			face(a, "smile", 3)
			lookAtPlayer(a, 2)
			gesture(a, "wave")
			sayNpc(a, pick(list), 2.8)
		end
	end
	-- feelings first: people who are scared of you keep away, angry ones glare
	if v and d < 11 and now - (a.moodAt or -1e9) > 14 and now - lastMood > 3 then
		if v.disp == "scared" and standing then
			a.moodAt = now
			lastMood = now
			face(a, "scared", 3)
			if ctx.Crowd.canSay(now) then
				sayNpc(a, pick({ "히익…", "저, 저리 가요…", "또 왜 와요…!", "(슬금슬금 피한다)" }), 2.5)
			end
			Mind.flee(a, pp, 3)
			return true
		elseif v.disp == "hostile" and d < 9 then
			a.moodAt = now
			lastMood = now
			face(a, "angry", 4)
			lookAtPlayer(a, 3)
			if ctx.Crowd.canSay(now) then
				sayNpc(a, pick({ "…뭘 봐.", "저 사람이다, 그때 그…", "말 걸지 마.", "쳇.", "아직도 기분 나빠." }), 3)
			end
			if (t == "thug" or t == "punk" or t == "violent") and d < 4 and rnd() < 0.4 and a.hitPlayer then
				local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				a:hitPlayer(dx / dd, dz / dd, "stagger", "저리 가라고.")
			end
			return false
		elseif v.disp == "friendly" and v.lover and d < 14 and now - (a.loverWave or -1e9) > 90 then
			a.loverWave = now
			face(a, "love", 4)
			gesture(a, "wave")
			sayNpc(a, pick({ "자기야~! 💕", "어? 우리 자기다 ㅎㅎ", "보고 싶었어 💕" }), 3)
		end
	end
	-- 걸렁뱅이: stares, then throws a line in passing or walks up
	if t == "punk" and standing and d < 15 and d > 2.5 and now >= (a.nextProvoke or 0) and now - lastProvoke > 18 and pspeed < 18 then
		a.nextProvoke = now + 15 + rnd() * 20
		if rnd() < 0.7 and canAct(now, a) then
			lastProvoke = now
			stats.provokes += 1
			face(a, "smug", 4)
			lookAtPlayer(a, 2.2)
			if a.mode == "walk" then
				a.pauseUntil = now + 1.4
			end
			task.delay(1 + rnd() * 0.6, function()
				if a.gone or a.ctl or a.knock or talk then
					return
				end
				local p2 = playerPos()
				if not p2 then
					return
				end
				local dd = flatDist(p2, a.pos)
				if dd > 18 then
					return
				end
				if rnd() < 0.25 or dd > 10 then
					-- 지나가면서 툭: a line, a glare, nothing else
					local env = { now = os.time(), aff = (views[a.id] and views[a.id].aff) or 0, you = player.DisplayName, rnd = rnd }
					local out = M.opener(a.c, M.newRec(a.c, os.time()), "punk_toss", env)
					sayNpc(a, out.lines[#out.lines], 3.2)
					gesture(a, "point")
					a.lookUntil = os.clock() + 2.5
				else
					a:approachPlayer(os.clock(), p2, 3, "approach")
				end
			end)
			return true
		end
	end
	-- 불량배: at night (or when they already dislike you) they come over
	if t == "thug" and standing and d < 12 and d > 3 and now >= (a.nextThug or 0) then
		a.nextThug = now + 40 + rnd() * 40
		local clock = ctx.clock()
		local night = clock >= 19 or clock < 4
		if (night or (v and v.disp == "hostile")) and rnd() < 0.5 and canAct(now, a) then
			face(a, "smug", 3)
			lookAtPlayer(a, 2)
			a:approachPlayer(now, pp, 3, "approach")
			return true
		end
	end
	-- 취객 시비: late at night a drunk picks a quarrel — slurs at you, follows you around a while and
	-- shoves you if you stay in his face; walk away and he gives up (Crowd's chase hook runs it)
	if t == "drunk" and standing and d < 13 and d > 2.5 and now >= (a.nextQuarrel or 0) and now - lastQuarrel > 25 and pspeed < 14 and a.startChase then
		a.nextQuarrel = now + 40 + rnd() * 40
		local clock = ctx.clock()
		local late = (clock >= 19 or clock < 5) or rnd() < 0.45 -- mostly at night, sometimes in the day
		local FSm = ReplicatedStorage:FindFirstChild("GwangalliFightShared")
		local okF, FS = pcall(require, FSm :: any)
		if late and okF and FS and rnd() < 0.65 and canAct(now, a) then
			lastQuarrel = now
			stats.quarrels = (stats.quarrels or 0) + 1
			face(a, "angry", 5)
			lookAtPlayer(a, 3)
			a.quarrel = { untilT = now + 10 + rnd() * 5, nextLine = now + 3.2, nextShove = now + 4.5, lines = FS.DRUNK_LINES }
			a:startChase(now, pp)
			sayNpc(a, pick(FS.DRUNK_LINES.start), 3.2)
			return true
		end
	end
	-- 동네바보: pranks with a chance and a cooldown
	if t == "fool" and standing and d < 16 and d > 2 and now >= (a.nextPrank or 0) and now - lastPrank > 14 and pspeed < 18 then
		a.nextPrank = now + 14 + rnd() * 20
		if rnd() < 0.8 and canAct(now, a) then
			lastPrank = now
			stats.pranks += 1
			local kind = choosePrank(a)
			a.lastPrank = kind
			Mind.prank(a, kind, now)
			return true
		end
	end
	-- a patrolling officer asks a question now and then
	if t == "police" and standing and d < 9 and d > 2.5 and now >= (a.nextQuestion or 0) then
		a.nextQuestion = now + 120 + rnd() * 120
		local wanted = player:GetAttribute(M.Attr.Wanted) or 0
		if wanted == 0 and rnd() < 0.25 and canAct(now, a) then
			a:approachPlayer(now, pp, 3, "approach")
			return true
		end
	end
	return false
end

-- the kind of opener for an agent that walked up (Agent.startChat)
function Mind.kindFor(a: any): string
	local t = a.type
	if t == "beggar" then
		return "beg"
	elseif t == "fool" then
		return "fool"
	elseif t == "punk" then
		return "punk"
	elseif t == "thug" then
		return "thug"
	elseif t == "police" then
		return "police"
	end
	local v = views[a.id]
	if v and (v.aff or 0) >= 50 then
		return "friend"
	end
	return "chatty"
end

-------------------------------------------------------------------------------------------------
-- 동네바보 pranks (a.ctl kinds: bump | block | cut | stare | follow | weird | runaway | back)
-------------------------------------------------------------------------------------------------
function Mind.prank(a: any, kind: string, now: number)
	if not take(a, { kind = kind, keep = true }) then
		return
	end
	local ctl = a.ctl
	ctl.untilT = now + (if kind == "block" then 3.5 + rnd() * 2 elseif kind == "stare" then 2.6 + rnd() * 1.5 elseif kind == "cut" then 4 else 7)
	ctl.retarget = 0
	ctl.side = if rnd() < 0.5 then 1 else -1
	face(a, if kind == "stare" then nil else "laugh", 6)
	dbg("prank", a.id, kind)
	if kind == "block" then
		local l = foolLine(a, "block")
		if l then
			sayNpc(a, l, 3)
		end
	elseif kind == "stare" then
		local l = foolLine(a, "stare")
		if l then
			sayNpc(a, l, 2.5)
		end
	elseif kind == "weird" then
		ctl.stage = "go"
	end
end

local function playerAhead(dist: number): Vector3?
	local pp = playerPos()
	if not pp then
		return nil
	end
	local v = ctx.Crowd.playerVel()
	local look = ctx.Crowd.playerLook()
	local hx, hz = look.X, look.Z
	local sp = math.sqrt(v.X * v.X + v.Z * v.Z)
	if sp > 1.5 then
		hx, hz = v.X / sp, v.Z / sp
	end
	local m = math.sqrt(hx * hx + hz * hz)
	if m < 1e-3 then
		hx, hz, m = 0, -1, 1
	end
	return Vector3.new(pp.X + hx / m * dist, pp.Y, pp.Z + hz / m * dist), Vector3.new(hx / m, 0, hz / m)
end

local function driveFool(a: any, ctl: any, now: number, pp: Vector3)
	local d = flatDist(a.pos, pp)
	local kind = ctl.kind
	if d > 30 or now > (ctl.untilT or now) and kind ~= "weird" and kind ~= "runaway" and kind ~= "back" then
		if kind == "stare" and d < 22 then
			-- staring turns into following you around
			ctl.kind = "follow"
			ctl.untilT = now + 6 + rnd() * 6
			local l = foolLine(a, "follow")
			if l then
				sayNpc(a, l, 3)
			end
			return
		end
		face(a, nil)
		release(a)
		return
	end
	local run = a.walkSpeed * 1.25
	if kind == "bump" then
		-- aim at the player's shoulder; the contact check (Agent.bump / fool branch) does the 어깨빵
		if now >= ctl.retarget then
			ctl.retarget = now + 0.3
			local ahead = playerAhead(1.2) or pp
			moveTo(a, ahead, run)
		end
		if d < 2.4 then
			if a.foolBump and now - (a.lastFoolBump or -1e9) > ((BUMP and BUMP.FOOL and BUMP.FOOL.bumpCooldown) or 6) then
				a:foolBump(now, pp)
				ctl.done = true
			end
			release(a)
		end
	elseif kind == "block" then
		-- 길막: stand right in front of the player, sway left / right with them
		if now >= ctl.retarget then
			ctl.retarget = now + 0.35
			local ahead, dir = playerAhead(2.6)
			if ahead and dir then
				local sway = math.sin(now * 3.2) * 0.9
				local target = Vector3.new(ahead.X - dir.Z * sway, ahead.Y, ahead.Z + dir.X * sway)
				if flatDist(a.pos, target) > 0.8 then
					moveTo(a, target, run * 1.1)
				else
					hold(a, pp, nil)
				end
			end
		end
		if now >= (ctl.nextLine or 0) and d < 6 and ctx.Crowd.canSay(now) then
			ctl.nextLine = now + 3 + rnd() * 2
			local l = foolLine(a, "block")
			if l then
				sayNpc(a, l, 2.6)
			end
			gesture(a, "dance")
		end
	elseif kind == "cut" then
		-- walks alongside, then suddenly turns across the player's path
		if now >= ctl.retarget then
			ctl.retarget = now + 0.4
			local ahead, dir = playerAhead(if now - ctl.since < 1.6 then 1 else 3.5)
			if ahead and dir then
				local s = if now - ctl.since < 1.6 then ctl.side * 2.2 else -ctl.side * 2.6
				local target = Vector3.new(ahead.X - dir.Z * s, ahead.Y, ahead.Z + dir.X * s)
				moveTo(a, target, run * (if now - ctl.since < 1.6 then 1 else 1.4))
				if now - ctl.since >= 1.6 and not ctl.said then
					ctl.said = true
					local l = foolLine(a, "giggle") or "히히"
					sayNpc(a, l, 2.2)
				end
			end
		end
	elseif kind == "stare" then
		hold(a, pp, "")
		lookAtPlayer(a, 1)
	elseif kind == "follow" then
		if now >= ctl.retarget then
			ctl.retarget = now + 0.5
			if d > 3.8 then
				local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				moveTo(a, Vector3.new(pp.X + dx / dd * 3, pp.Y, pp.Z + dz / dd * 3), math.max(run, ctx.Crowd.playerSpeed() * 0.95))
			else
				hold(a, pp, nil)
				lookAtPlayer(a, 1)
			end
		end
		if now >= (ctl.nextLine or 0) and ctx.Crowd.canSay(now) then
			ctl.nextLine = now + 4 + rnd() * 3
			local l = foolLine(a, if rnd() < 0.5 then "follow" else "giggle")
			if l then
				sayNpc(a, l, 2.6)
			end
		end
	elseif kind == "weird" then
		-- walk up, say something strange, run off giggling, come back once
		if ctl.stage == "go" then
			if d > 3.4 then
				if now >= ctl.retarget then
					ctl.retarget = now + 0.6
					moveTo(a, pp, run)
				end
			else
				ctl.stage = "talk"
				ctl.stageAt = now
				hold(a, pp, "")
				local env = { now = os.time(), aff = 0, you = player.DisplayName, rnd = rnd }
				local out = M.opener(a.c, M.newRec(a.c, os.time()), "fool_weird", env)
				sayNpc(a, out.lines[#out.lines], 4)
				face(a, "laugh", 4)
				gesture(a, "point")
			end
			if now - ctl.since > 9 then
				release(a)
			end
		elseif ctl.stage == "talk" then
			hold(a, pp, nil)
			if now - ctl.stageAt > 3.4 then
				ctl.stage = "run"
				ctl.stageAt = now
				local l = foolLine(a, "runaway")
				if l then
					sayNpc(a, l, 2.5)
				end
				local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				moveTo(a, Vector3.new(a.pos.X + dx / dd * 22, a.pos.Y, a.pos.Z + dz / dd * 22), 13)
			end
		elseif ctl.stage == "run" then
			if now - ctl.stageAt > 4 + rnd() * 0.5 then
				ctl.stage = "wait"
				ctl.stageAt = now
				hold(a, pp, "")
			end
		elseif ctl.stage == "wait" then
			lookAtPlayer(a, 1)
			if now - ctl.stageAt > 2.5 + rnd() * 3 then
				ctl.stage = "back"
				ctl.stageAt = now
			end
		elseif ctl.stage == "back" then
			if d > 3.5 then
				if now >= ctl.retarget then
					ctl.retarget = now + 0.5
					moveTo(a, pp, run)
				end
				if now - ctl.stageAt > 10 then
					release(a)
				end
			else
				local l = foolLine(a, "back")
				if l then
					sayNpc(a, l, 3)
				end
				face(a, "laugh", 3)
				release(a)
				-- sometimes he stays to talk
				if rnd() < 0.45 then
					task.delay(1.5, function()
						if not a.gone and not a.ctl and not talk then
							Mind.npcStart(a, "fool")
						end
					end)
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- flee / report / watch (witnesses, scared people)
-------------------------------------------------------------------------------------------------
function Mind.flee(a: any, from: Vector3, dur: number)
	if a.ctl and a.ctl.kind ~= "talk" then
		return
	end
	if not take(a, { kind = "flee", untilT = os.clock() + dur, from = from }) then
		return
	end
	face(a, "scared", dur)
	local dx, dz = a.pos.X - from.X, a.pos.Z - from.Z
	local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
	moveTo(a, Vector3.new(a.pos.X + dx / d * 24, a.pos.Y, a.pos.Z + dz / d * 24), 12 + rnd() * 3)
	Anim.flash(a.rig, "startle", 0.8)
end

function Mind.report(a: any)
	if not take(a, { kind = "report", untilT = os.clock() + 5 }) then
		return
	end
	local pp = playerPos()
	hold(a, pp, "phone")
	face(a, "scared", 5)
	task.delay(0.8, function()
		sayNpc(a, M.witnessLine("report", rnd) or "112죠? 여기 사람이…", 4)
	end)
	task.delay(2.4, function()
		invoke("report", { id = a.id, pos = pack(a.pos) })
	end)
end

local function witnessReact(a: any, kind: string, pos: Vector3, now: number)
	stats.witnesses += 1
	if kind == "flee" then
		Mind.flee(a, pos, 5 + rnd() * 3)
		if ctx.Crowd.canSay(now) then
			sayNpc(a, M.witnessLine("flee", rnd) or "꺄악!", 2.5)
		end
	elseif kind == "watch" or kind == "film" or kind == "cheer" then
		if not take(a, { kind = "watch", untilT = now + 5 + rnd() * 4, at = pos, film = kind == "film" }) then
			return
		end
		hold(a, pos, if kind == "film" then "photo" else "")
		face(a, if kind == "cheer" then "laugh" else "surprised", 5)
		task.delay(0.4 + rnd() * 1.2, function()
			if ctx.Crowd.canSay(os.clock()) then
				sayNpc(a, M.witnessLine(kind, rnd) or "헐…", 3)
			end
		end)
		if kind == "cheer" then
			gesture(a, "cheer")
		end
	elseif kind == "report" then
		Mind.report(a)
	elseif kind == "stop" or kind == "gang" then
		if not take(a, { kind = "intervene", untilT = now + 6, at = pos, gang = kind == "gang" }) then
			return
		end
		face(a, "angry", 6)
		sayNpc(a, M.witnessLine(kind, rnd) or "그만해요!", 3)
	elseif kind == "police" then
		Mind.dispatch(a)
	end
end

local CRIME_SEVERITY = { kill = 3, assault = 3, assault_police = 3, reckless = 2, shove = 2, threat = 2, bumps = 2, insult_police = 1, flee = 1, bribe = 1 }
function Mind.onCrime(msg: any)
	local pos = msg.pos and Vector3.new(msg.pos[1], msg.pos[2], msg.pos[3]) or playerPos()
	if not pos then
		return
	end
	local sev = CRIME_SEVERITY[msg.crime] or 2
	local now = os.clock()
	local n = 0
	local list = {}
	for _, a in ctx.Crowd.agents do
		if not a.gone and a.id ~= msg.victim and not a.companion and not a.clubGuest and not a.knock and a.mode ~= "talk" and (not a.ctl or a.ctl.kind == "watch") then
			local d = flatDist(a.pos, pos)
			if d < 42 then
				table.insert(list, { a = a, d = d })
			end
		end
	end
	table.sort(list, function(x, y)
		return x.d < y.d
	end)
	for _, e in list do
		if n >= 7 then
			break
		end
		local a = e.a
		if rnd() < 1.1 - e.d / 50 then
			n += 1
			local c = a.c or { id = a.id, type = a.type, persona = "uni" }
			local kind = M.witness(c, sev, rnd)
			task.delay(0.2 + rnd() * 0.9, function()
				-- (meanwhile somebody else may have taken them: the KO bystander's call, a justice witness)
				if not a.gone and not a.knock and (not a.ctl or a.ctl.kind == "watch") then
					witnessReact(a, kind, pos, os.clock())
				end
			end)
		end
	end
	if (msg.stars or 0) >= 1 then
		task.delay(2.5, function()
			Mind.dispatch(nil)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- police: dispatch, questioning, chase
-------------------------------------------------------------------------------------------------
local function wantedStars(): number
	local w = player:GetAttribute(M.Attr.Wanted)
	return if type(w) == "number" then w else 0
end

function Mind.dispatch(cop: any?)
	if workspace:GetAttribute("GwangalliLawActive") == true then
		return -- the server police (GwangalliGameplay.Law) own dispatch, chases and arrests
	end
	if police.agent and not police.agent.gone and police.agent.ctl and police.agent.ctl.kind == "respond" then
		return
	end
	if wantedStars() <= 0 then
		return
	end
	local pp = playerPos()
	if not pp then
		return
	end
	local a = cop
	if not a then
		-- the closest officer on the street, else one walks in from out of sight
		local best, bd = nil, 160
		for _, o in ctx.Crowd.agents do
			if not o.gone and o.type == "police" and not o.companion and not o.clubGuest then
				local d = flatDist(o.pos, pp)
				if d < bd then
					best, bd = o, d
				end
			end
		end
		a = best
		if not a and ctx.Crowd.spawnResponder then
			for _, id in Citizens.ofType("police") do
				if not ctx.Crowd.byId[id] then
					local ok, res = pcall(ctx.Crowd.spawnResponder, id, pp, os.clock())
					if ok and res then
						a = res
						break
					end
				end
			end
		end
	end
	if not a or a.gone then
		return
	end
	if talk and talk.a == a then
		finish("police")
	end
	if a.ctl then
		release(a)
	end
	if not take(a, { kind = "respond", keep = true, retarget = 0, lostSince = nil }) then
		return
	end
	police.agent = a
	police.state = nil
	stats.dispatches += 1
	a.walkPose = nil
	face(a, "wary", 6)
	if a.onScreen and a.dist < 60 then
		sayNpc(a, M.policeLine("coming", {}, rnd), 3)
	end
	dbg("dispatch", a.id)
end

local function policeUI(chips: { any }?, line: string?)
	local a = police.agent
	if not a then
		return
	end
	local v = views[a.id] or { label = "경찰", job = a.c and a.c.job or "경찰", stageIcon = "👮", stageLabel = "출동 중" }
	UI.open(v, {
		onChip = function(spec)
			Mind.policeChoice(spec.id)
		end,
		onAnswer = function(spec)
			Mind.policeChoice(spec.id)
		end,
		onSend = function(text)
			sayPlayer(text)
			local it = M.parse(text, nil)
			Mind.policeChoice(if it == "apologize" then "sorry" elseif it == "insult" or it == "provoke" then "insult" else "excuse")
		end,
		onClose = function()
			Mind.policeChoice("flee")
		end,
	})
	UI.setChips({})
	UI.setAnswers(chips or {})
	if line then
		sayNpc(a, line, lineDur(line))
	end
end

function Mind.policeEncounter(a: any, arrest: boolean?)
	if workspace:GetAttribute("GwangalliLawActive") == true then
		return -- the server police (GwangalliGameplay.Law) own dispatch, chases and arrests
	end
	if not a or a.gone then
		return
	end
	if police.agent ~= a then
		if a.ctl then
			release(a)
		end
		take(a, { kind = "respond", keep = true, retarget = 0 })
		police.agent = a
	end
	a.ctl.kind = "question"
	police.state = "question"
	hold(a, playerPos(), "")
	face(a, "wary", 10)
	gesture(a, "point")
	task.spawn(function()
		local res = invoke("police", { op = "open", copId = a.id })
		if police.agent ~= a then
			return
		end
		if not res or not res.ok then
			police.state = nil
			release(a, true)
			police.agent = nil
			return
		end
		if res.done then
			sayNpc(a, res.line or "안전하게 다니세요.", 3)
			police.state = nil
			release(a, true)
			police.agent = nil
			return
		end
		policeUI(res.chips, res.line)
		if arrest then
			Mind.policeChoice("insult")
		end
	end)
end

function Mind.policeChoice(op: string)
	local a = police.agent
	if not a or a.gone or police.state ~= "question" then
		return
	end
	local said = ({ sorry = "잘못했어요… 죄송합니다.", excuse = "제가 그런 게 아니라요…", insult = "아 짜증나네, 꺼져요!", flee = "(도망친다!)" })[op]
	if said then
		sayPlayer(said)
	end
	police.state = "wait"
	task.spawn(function()
		local res = invoke("police", { op = op, copId = a.id })
		if police.agent ~= a then
			return
		end
		UI.close()
		if not res or not res.ok then
			police.state = nil
			police.agent = nil
			release(a, true)
			return
		end
		if res.line then
			sayNpc(a, res.line, lineDur(res.line))
		end
		if res.chase then
			police.state = "chase"
			a.ctl.kind = "chase"
			a.ctl.retarget = 0
			a.ctl.lostSince = nil
			a.ctl.since = os.clock()
			face(a, "angry", 20)
		else
			police.state = nil
			police.agent = nil
			face(a, "neutral")
			task.delay(3.5, function()
				release(a, true)
			end)
		end
		UI.setWanted(wantedStars())
	end)
end

local function drivePolice(a: any, ctl: any, now: number, pp: Vector3)
	local d = flatDist(a.pos, pp)
	if ctl.kind == "respond" then
		if wantedStars() <= 0 then
			police.agent = nil
			release(a, true)
			return
		end
		if ctx.Crowd.playerSeated() then
			-- in a car: they lose you after a while
			if now - ctl.since > 45 then
				invoke("police", { op = "lost", copId = a.id })
				police.agent = nil
				release(a, true)
			end
			return
		end
		if d < 4.2 then
			Mind.policeEncounter(a, false)
			return
		end
		if now >= ctl.retarget then
			ctl.retarget = now + 0.4
			local speed = if d > 30 then 15 else 11
			moveTo(a, pp, speed)
		end
		if now - ctl.since > 90 then
			police.agent = nil
			release(a, true)
		end
	elseif ctl.kind == "question" then
		hold(a, pp, nil)
		lookAtPlayer(a, 1)
		-- walking off in the middle of the questioning = running away
		if d > 14 and police.state == "question" then
			UI.close()
			Mind.policeChoice("flee")
		end
	elseif ctl.kind == "chase" then
		if d < 3.2 then
			local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
			local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
			if a.hitPlayer then
				a:hitPlayer(dx / dd, dz / dd, "stagger", nil)
			end
			police.state = "wait"
			ctl.kind = "question"
			hold(a, pp, "")
			task.spawn(function()
				local res = invoke("police", { op = "caught", copId = a.id })
				if res and res.line then
					sayNpc(a, res.line, lineDur(res.line))
				end
				police.state = nil
				police.agent = nil
				UI.setWanted(wantedStars())
				task.delay(4, function()
					release(a, true)
				end)
			end)
			return
		end
		if d > 70 or ctx.Crowd.playerSeated() then
			ctl.lostSince = ctl.lostSince or now
			if now - ctl.lostSince > 5 then
				task.spawn(function()
					local res = invoke("police", { op = "lost", copId = a.id })
					if res and res.line then
						sayNpc(a, res.line, 3)
					end
				end)
				police.state = nil
				police.agent = nil
				release(a, true)
				return
			end
		else
			ctl.lostSince = nil
		end
		if now >= ctl.retarget then
			ctl.retarget = now + 0.3
			moveTo(a, pp, math.max(15, ctx.Crowd.playerSpeed() * 0.92 + 1))
		end
		if now >= (ctl.nextShout or 0) and ctx.Crowd.canSay(now) then
			ctl.nextShout = now + 3 + rnd() * 2
			sayNpc(a, M.policeLine("chase", {}, rnd), 2.5)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- NPC <-> NPC scenes
-------------------------------------------------------------------------------------------------
local function nameFor(a: any, other: any): string
	if a.named and other.named and Citizens then
		local ok, n = pcall(Citizens.callName, other.id, a.id)
		if ok and type(n) == "string" then
			return n
		end
	end
	if a.named and Citizens then
		local ok, n = pcall(Citizens.shortName, a.id)
		if ok then
			return n
		end
	end
	return "저기요"
end

local function cOf(a: any): any
	return a.c or { id = a.id, type = a.type, persona = if a.def and a.def.extra then "uni" else "uni", speech = "std" }
end

local sceneEnding: number? = nil -- test harness: force the next fight scene's ending
local function playScene(a: any, b: any, key: string, lines: { any })
	local now = os.clock()
	local dur = 2 + #lines * 3.2
	if not take(a, { kind = "scene", untilT = now + dur, other = b, keep = true }) then
		return
	end
	if not take(b, { kind = "scene", untilT = now + dur, other = a, keep = true }) then
		release(a)
		return
	end
	stats.scenes += 1
	hold(a, b.pos, "chat")
	hold(b, a.pos, "chat")
	local sc = { a = a, b = b, key = key, untilT = now + dur }
	table.insert(scenes, sc)
	dbg("scene", key, a.id, b.id)
	local delay = 0.3
	for i, ln in lines do
		local who = if ln[1] == "a" then a else b
		local other = if who == a then b else a
		local text = string.gsub(string.gsub(ln[2], "{a}", nameFor(a, b)), "{b}", nameFor(b, a))
		text = string.gsub(text, "{time}", "지금")
		local v = M.voice(text, M.archOf(cOf(who)), rnd)
		if who.c and who.c.speech == "busan" then
			v = M.dialect(v, if (who.type == "punk" or who.type == "thug" or who.type == "drunk" or who.type == "fool") then "c" else "p", rnd)
		end
		local emote = ln[3]
		task.delay(delay, function()
			if who.gone or not who.ctl or who.ctl.kind ~= "scene" then
				return
			end
			sayNpc(who, v, lineDur(v))
			if emote == "scared" then
				face(who, "scared", 3)
			elseif emote then
				gesture(who, emote)
				if emote == "laugh" then
					face(who, "laugh", 3)
				end
			end
			other:lookAtPoint(who.pos + Vector3.new(0, 1.6, 0), 3, os.clock())
			-- bystanders turn their heads
			for _, o in ctx.Crowd.agents do
				if o ~= who and o ~= other and not o.gone and o.near and not o.ctl and o.mode ~= "talk" then
					if flatDist(o.pos, who.pos) < 8 and rnd() < 0.35 then
						o:lookAtPoint(who.pos + Vector3.new(0, 1.6, 0), 2.5, os.clock())
					end
				end
			end
		end)
		delay += lineDur(v) * 0.9
	end
	task.delay(delay + 0.6, function()
		if key == "drunkfight" and not a.gone and not b.gone and a.ctl and b.ctl then
			-- the argument turns into a scuffle: shoves both ways (3-4), the last one puts somebody down;
			-- the people around stop and look, somebody calls it in (an officer comes to break it up)
			release(a)
			release(b)
			-- not every argument turns into a fight: an apology, a bystander stepping in, or one of
			-- them just walking off end it as often as a scuffle does
			local ending = sceneEnding or rnd()
			sceneEnding = nil
			local scuffle = true
			if ending < 0.2 then
				sayNpc(b, pick({ "아 미안 미안, 내가 취했나 봐…", "됐다 됐어, 내가 잘못했다.", "에휴… 미안하다." }), 3)
				task.delay(1.6, function()
					if not a.gone then
						sayNpc(a, pick({ "…그래, 됐다.", "다음부턴 조심해라.", "쳇, 알았어." }), 2.5)
					end
				end)
				scuffle = false
			elseif ending < 0.4 then
				local peace
				for _, o in ctx.Crowd.agents do
					if o ~= a and o ~= b and not o.gone and not o.ctl and o.mode ~= "talk" and not o.knock and flatDist(o.pos, a.pos) < 16 then
						peace = o
						break
					end
				end
				if peace then
					peace:lookAtPoint(a.pos + Vector3.new(0, 1.6, 0), 3, os.clock())
					gesture(peace, "point")
					sayNpc(peace, pick({ "아이고, 그만들 하세요!", "두 분 다 진정하세요~", "여기서 이러시면 안 돼요!" }), 3)
					task.delay(1.8, function()
						if not a.gone then
							sayNpc(a, pick({ "…알았어요.", "에이, 기분 잡쳤네.", "흥." }), 2.5)
						end
					end)
					scuffle = false
				end
			elseif ending < 0.55 then
				sayNpc(b, pick({ "됐어, 상대 안 해!", "에이 씨, 간다 가.", "말이 안 통하네." }), 3)
				if Mind.flee then
					Mind.flee(b, a.pos, 4)
				end
				scuffle = false
			end
			if scuffle then
			local rounds = 3 + math.floor(rnd() * 2)
			local function round(i: number)
				if a.gone or b.gone then
					return
				end
				local hitter, target = if i % 2 == 1 then a else b, if i % 2 == 1 then b else a
				local dx, dz = target.pos.X - hitter.pos.X, target.pos.Z - hitter.pos.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				if dd > 5.5 then
					return -- somebody walked off: it is over
				end
				hitter:lookAtPoint(target.pos + Vector3.new(0, 1.6, 0), 2, os.clock())
				gesture(hitter, "point")
				target:knockDown(dx / dd, dz / dd, if i == rounds then "knockdown" else "stagger", pick(Social.PUK))
				for _, o in ctx.Crowd.agents do
					if o ~= a and o ~= b and not o.gone and not o.ctl and o.mode ~= "talk" and flatDist(o.pos, target.pos) < 16 then
						o:lookAtPoint(target.pos + Vector3.new(0, 1.2, 0), 3, os.clock())
					end
				end
				if i < rounds then
					task.delay(1.5 + rnd() * 0.5, round, i + 1)
					return
				end
				-- over: the winner gloats, a bystander phones it in
				task.delay(1.2, function()
					if not hitter.gone then
						sayNpc(hitter, pick({ "어때! 덤벼 봐!", "술 깨면 사과해라!", "에잇, 다시는 보지 말자!" }), 3)
					end
					if rnd() < 0.6 then
						local caller
						for _, o in ctx.Crowd.agents do
							if o ~= a and o ~= b and not o.gone and not o.ctl and o.mode ~= "talk" and flatDist(o.pos, target.pos) < 18 then
								caller = o
								break
							end
						end
						-- (only the phone call: Mind.report would report the PLAYER's own pending crime)
						if caller and take(caller, { kind = "report", untilT = os.clock() + 5 }) then
							hold(caller, target.pos, "phone")
							task.delay(0.8, function()
								sayNpc(caller, pick({ "여보세요, 112죠? 여기 싸움 났어요!", "경찰 좀 보내 주세요, 취객들이 싸워요!", "저기요, 경찰이죠? 사람이 맞고 있어요!" }), 3.5)
							end)
						end
						local ff = ReplicatedStorage:FindFirstChild("GwangalliFight")
						local act = ff and ff:FindFirstChild("Action")
						if act and act:IsA("RemoteEvent") then
							act:FireServer("npcFight", { pos = { target.pos.X, target.pos.Y, target.pos.Z }, a = a.id, b = b.id })
						end
					end
				end)
			end
			round(1)
			end
		elseif key == "punk" and not b.gone then
			face(b, "scared", 3)
			release(b, true)
		end
		if a.ctl and a.ctl.kind == "scene" then
			release(a)
		end
		if b.ctl and b.ctl.kind == "scene" then
			release(b)
		end
		for i, s in scenes do
			if s == sc then
				table.remove(scenes, i)
				break
			end
		end
	end)
end

-- 취객 시비 / a stranger following you: the person walks up and stays on you a while (the chase hook in
-- Crowd runs it: lines every few seconds, a shove when he catches you unless noShove; keep = how
-- close he comes)
function Mind.startQuarrel(a: any, lines: any, opts: any?): boolean
	local pp = playerPos()
	if not a or a.gone or not pp or not a.startChase or a.knock or a.ko then
		return false
	end
	local o = opts or {}
	local now = os.clock()
	a.quarrel = { untilT = now + (o.secs or 14), nextLine = now + 3, nextShove = if o.noShove then math.huge else now + 4, lines = lines, keep = o.keep }
	a:startChase(now, pp)
	local first = lines and lines.start
	if first then
		sayNpc(a, pick(first), 3.2)
	end
	return true
end

local function nearestAgent(pos: Vector3, maxD: number, filter: ((any) -> boolean)?): any?
	local best, bd = nil, maxD
	for _, a in ctx.Crowd.agents do
		if not a.gone and not a.ctl and not a.knock and not a.ko and not a.companion and not a.clubGuest and a.mode ~= "talk" and (not filter or filter(a)) then
			local d = flatDist(pos, a.pos)
			if d < bd and d > 2.5 then
				best, bd = a, d
			end
		end
	end
	return best
end

local INCIDENT_LINES = {
	lost = { start = { "저기요… 혹시 광안리 해변이 어느 쪽이에요?", "실례지만 지하철역 가려면 어디로 가요?", "길을 잃었는데 좀 알려 주실 수 있어요?" }, follow = { "저기요~", "잠깐만요!" } },
	help = { start = { "저기요! 도와주세요, 지갑을 잃어버렸어요…", "혹시 휴대폰 좀 빌려주실 수 있어요? 급해서요…", "저 좀 도와주실 수 있어요?" }, follow = { "제발요…", "잠깐만요!" } },
	suspicious = { start = { "…", "(힐끔)" }, follow = { "…", "(힐끔힐끔)", "(따라온다)" } },
}

-- 생활콘텐츠 -> NPC: "an incident happened"; the NPC system casts and plays it.
--   kind = "drunk_quarrel" | "stall_fight" | "street_fight" | "lost" | "help" | "suspicious"
--   data = { pos = Vector3? (where, default: around the player), id = citizen/agent id? }
local function incidentImpl(kind: string, data: any?): (boolean, string?)
	local d = if type(data) == "table" then data else {}
	local pp = playerPos()
	local at = if typeof(d.pos) == "Vector3" then d.pos else pp
	if not at then
		return false
	end
	local okF, FS = pcall(require, ReplicatedStorage:FindFirstChild("GwangalliFightShared") :: any)
	if kind == "drunk_quarrel" then
		local a = (d.id and ctx.Crowd.byId[d.id]) or nearestAgent(at, 45, function(x)
			return x.type == "drunk"
		end) or nearestAgent(at, 45)
		if not a or not okF then
			return false
		end
		a.type = "drunk"
		return Mind.startQuarrel(a, FS.DRUNK_LINES), a.id
	elseif kind == "stall_fight" or kind == "street_fight" then
		local a = nearestAgent(at, 40)
		local b = a and nearestAgent(a.pos, 12, function(x)
			return x ~= a
		end)
		local lines = M.scene("drunkfight", rnd)
		if not a or not b or not lines then
			return false
		end
		playScene(a, b, "drunkfight", lines)
		return true, a.id .. "+" .. b.id
	elseif INCIDENT_LINES[kind] then
		local a = (d.id and ctx.Crowd.byId[d.id]) or nearestAgent(at, 45)
		if not a then
			return false
		end
		return Mind.startQuarrel(a, INCIDENT_LINES[kind], { noShove = true, secs = if kind == "suspicious" then 22 else 10, keep = if kind == "suspicious" then 10 else 3.2 }), a.id
	end
	return false, nil
end

function Mind.incident(kind: string, data: any?): boolean
	local ok, who = incidentImpl(kind, data)
	if debugOn() then
		workspace:SetAttribute("GwangalliIncidentResult", string.format("%s:%s:%s", tostring(kind), tostring(ok), tostring(who)))
	end
	return ok
end

local function sceneTick(now: number)
	if now < nextScene then
		return
	end
	nextScene = now + 2.5 + rnd() * 2.5
	if #scenes >= 2 or talk then
		return
	end
	local pp = playerPos()
	if not pp then
		return
	end
	local cands = {}
	for _, a in ctx.Crowd.agents do
		if not a.gone and a.near and a.dist < 42 and not a.ctl and not a.knock and not a.companion and not a.clubGuest and not a.chatState and a.mode ~= "talk" and a.mode ~= "follow" and a.mode ~= "member" and a.mode ~= "dodge" and not a.lying and not a.napping and now - (a.sceneAt or -1e9) > 70 then
			table.insert(cands, a)
		end
	end
	if #cands < 2 then
		return
	end
	for _ = 1, 4 do
		local a = cands[1 + math.floor(rnd() * #cands)]
		local b = a:neighbour(7.5, function(o)
			return o ~= a and not o.gone and o.near and not o.ctl and not o.knock and not o.companion and not o.clubGuest and not o.chatState and o.mode ~= "talk" and o.mode ~= "follow" and o.mode ~= "dodge" and not o.lying and not o.napping and now - (o.sceneAt or -1e9) > 70
		end)
		if b then
			local ca, cb = cOf(a), cOf(b)
			local rel = {
				friends = a.named and b.named and Citizens and (Citizens.areFriends(a.id, b.id)) or (a.leader == b or b.leader == a),
				couple = a.named and b.named and Citizens and Citizens.isCouple(a.id, b.id),
				atWork = (a.plan and a.plan.act == "work") or (b.plan and b.plan.act == "work"),
			}
			local key, x, _y = M.scenePair(ca, cb, rel, rnd)
			-- strangers only talk now and then (mostly people who know each other / have a reason)
			if key == "strangers" and rnd() < 0.55 then
				continue
			end
			local first = if x == ca then a else b
			local second = if first == a then b else a
			local lines = key and M.scene(key, rnd)
			if lines then
				a.sceneAt, b.sceneAt = now, now
				playScene(first, second, key, lines)
				return
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- the per-agent drive (Agent.think hands a.ctl agents here)
-------------------------------------------------------------------------------------------------
function Mind.drive(a: any, now: number)
	local ctl = a.ctl
	if not ctl then
		return
	end
	local pp = playerPos()
	if not pp then
		return
	end
	local kind = ctl.kind
	if kind == "talk" then
		-- the conversation keeps them facing the player; the session checks the distance
		if a.mode ~= "talk" and not a.knock then
			a:beginTalk(now, 600)
		end
		if not talk or talk.a ~= a then
			ctl.kind = "done"
			a.ctl = nil
			if a.mode == "talk" then
				a:endTalk(now)
			end
		end
		return
	elseif kind == "bump" or kind == "block" or kind == "cut" or kind == "stare" or kind == "follow" or kind == "weird" then
		driveFool(a, ctl, now, pp)
	elseif kind == "respond" or kind == "question" or kind == "chase" then
		drivePolice(a, ctl, now, pp)
	elseif kind == "flee" then
		if now > ctl.untilT then
			release(a, true)
		end
	elseif kind == "report" then
		if now > ctl.untilT then
			release(a, true)
		end
	elseif kind == "watch" then
		if ctl.at then
			a.faceYaw = yawOf(ctl.at.X - a.pos.X, ctl.at.Z - a.pos.Z)
			a:lookAtPoint(ctl.at + Vector3.new(0, 1.5, 0), 1, now)
		end
		if now > ctl.untilT then
			release(a)
		end
	elseif kind == "intervene" then
		local d = flatDist(a.pos, pp)
		if d > 3.2 and now - ctl.since < 4 then
			if now >= (ctl.retarget or 0) then
				ctl.retarget = now + 0.5
				moveTo(a, pp, 9)
			end
		else
			hold(a, pp, "")
			if ctl.gang and not ctl.hit and d < 3.5 and a.hitPlayer then
				ctl.hit = true
				local dx, dz = pp.X - a.pos.X, pp.Z - a.pos.Z
				local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
				a:hitPlayer(dx / dd, dz / dd, "stagger", "우리 애 건드리지 마라.")
			end
		end
		if now > ctl.untilT then
			release(a)
		end
	elseif kind == "threat" or kind == "custom" then
		-- a weapon pointed at them (GwangalliStreetLife/Delivery drives it: surrender / freeze / call)
		if type(ctl.drive) == "function" then
			ctl.drive(a, ctl, now, pp)
		elseif now > (ctl.untilT or 0) then
			release(a)
		end
	elseif kind == "scene" then
		local o = ctl.other
		if o and not o.gone then
			a.faceYaw = yawOf(o.pos.X - a.pos.X, o.pos.Z - a.pos.Z)
		end
		if now > ctl.untilT + 2 then
			release(a)
		end
	else
		release(a)
	end
end

-------------------------------------------------------------------------------------------------
-- the player was bumped (fool) / the session watchdog
-------------------------------------------------------------------------------------------------
local REACT = { "아 뭐야!", "어우 깜짝이야!", "아야…", "뭐 하는 거예요?!", "어어…?!", "아 진짜…" }
function Mind.playerBumped(a: any, outcome: string)
	task.delay(0.7, function()
		sayPlayer(pick(REACT) or "아!", 2.4)
	end)
	if a and a.type == "fool" and not talk then
		task.delay(1.6, function()
			if not a.gone and not talk and not police.state then
				Mind.npcStart(a, "fool_bump")
			end
		end)
	end
	local _ = outcome
end

local lastWatch = 0
local testQueue: { any } = {} -- test harness commands, run on the client thread
local function watchdog(now: number)
	if now - lastWatch < 0.25 then
		return
	end
	lastWatch = now
	while #testQueue > 0 do
		local cmd = table.remove(testQueue, 1)
		task.spawn(function()
			local ok, err = pcall(cmd)
			if not ok then
				warn("[GwangalliMind] test command: " .. tostring(err))
			end
		end)
	end
	local t = talk
	if t then
		local a = t.a
		local pp = playerPos()
		if a.gone or not pp then
			finish("gone")
		elseif a.knock and t.kind ~= "hit" then
			-- knocked over mid-conversation: it's over
			if now - t.since > 1 then
				finish("knock")
			end
		else
			local d = flatDist(pp, a.pos)
			if d > M.TALK_RANGE then
				t.farSince = t.farSince or now
				if now - t.farSince > 1.2 then
					local hostile = t.kind == "punk" or t.kind == "thug"
					if hostile then
						invoke("street", { id = t.id, ev = "ignored", pos = pack(a.pos) })
						local l = M.line(a.c, "ignore", { you = player.DisplayName })
						if l then
							sayNpc(a, l, 3)
						end
					end
					finish("far")
				end
			else
				t.farSince = nil
			end
		end
	end
	sceneTick(now)
	-- police: a wanted player gets an officer
	if wantedStars() > 0 and not police.agent and now >= (police.nextTry or 0) then
		police.nextTry = now + 6
		Mind.dispatch(nil)
	end
	if police.agent and police.agent.gone then
		police.agent = nil
		police.state = nil
	end
end

-------------------------------------------------------------------------------------------------
-- server events
-------------------------------------------------------------------------------------------------
local function onEvent(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local kind = msg.kind
	if kind == "crime" then
		UI.setWanted(msg.stars or wantedStars())
		Mind.onCrime(msg)
	elseif kind == "wanted" then
		UI.setWanted(msg.stars or 0)
		if (msg.stars or 0) > 0 then
			task.delay(3, function()
				Mind.dispatch(nil)
			end)
		end
	elseif kind == "dispatch" then
		Mind.dispatch(nil)
	elseif kind == "view" and type(msg.id) == "string" then
		setView(msg.id, msg.view)
	elseif kind == "text" then
		-- the phone shows it (GwangalliPhone/Apps/People listens too); a buzz here
		local a = type(msg.id) == "string" and ctx.Crowd.byId[msg.id]
		if a and a.near then
			gesture(a, "phone")
		end
	end
end

function Mind.snapshot(): any?
	local f = remotes.Get
	if not f then
		return nil
	end
	local ok, snap = pcall(function()
		return (f :: RemoteFunction):InvokeServer()
	end)
	if ok and type(snap) == "table" then
		if type(snap.npcs) == "table" then
			for id, v in snap.npcs do
				setView(id, v)
			end
		end
		if type(snap.contacts) == "table" then
			for _, v in snap.contacts do
				if type(v) == "table" and v.id then
					contacts[v.id] = true
					setView(v.id, v)
				end
			end
		end
		UI.setWanted(snap.wanted or 0)
		return snap
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- start
-------------------------------------------------------------------------------------------------
function Mind.init(context: any)
	ctx = context
	Anim = ctx.Anim
	BUMP = ctx.BumpShared
	Social = ctx.Social
	Citizens = ctx.Citizens
	local function shared(name: string): any
		local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 10)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				return res
			end
			warn("[GwangalliMind] " .. name .. " failed to load: " .. tostring(res))
		end
		return nil
	end
	M = shared("GwangalliMindShared")
	L = shared("GwangalliMindLines")
	UI = ctx.MindUI
	Face = ctx.Face
	if not M or not UI then
		warn("[GwangalliMind] client: shared modules missing, the NPC mind is off")
		return false
	end
	pcall(UI.init, ctx.UIKit, shared("GwangalliLayout"))
	return true
end

function Mind.start()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(M.Folder, 60)
		if not folder then
			warn("[GwangalliMind] client: remotes missing")
			return
		end
		remotes.Talk = folder:WaitForChild(M.Remote.Talk, 20) :: RemoteFunction
		remotes.Event = folder:WaitForChild(M.Remote.Event, 20) :: RemoteEvent
		remotes.Get = folder:WaitForChild(M.Remote.Get, 20) :: RemoteFunction
		if remotes.Event then
			(remotes.Event :: RemoteEvent).OnClientEvent:Connect(function(msg)
				local ok, err = pcall(onEvent, msg)
				if not ok then
					warn("[GwangalliMind] event: " .. tostring(err))
				end
			end)
		end
		for _ = 1, 20 do
			if player:GetAttribute(M.Attr.Ready) then
				break
			end
			task.wait(1)
		end
		Mind.snapshot()
		ready = true
		player:GetAttributeChangedSignal(M.Attr.Wanted):Connect(function()
			UI.setWanted(wantedStars())
		end)
		RunService.Heartbeat:Connect(function()
			local ok, err = pcall(watchdog, os.clock())
			if not ok then
				warn("[GwangalliMind] watchdog: " .. tostring(err))
			end
		end)
		-- LocalPlayer.GwangalliMindAPI: the phone app (and the test harness) reach the mind here
		local api = player:FindFirstChild("GwangalliMindAPI")
		if not api then
			api = Instance.new("BindableFunction")
			api.Name = "GwangalliMindAPI"
			api.Parent = player
		end
		(api :: BindableFunction).OnInvoke = function(method: any, ...: any)
			if method == "invoke" then
				return invoke(...)
			elseif method == "snapshot" then
				return Mind.snapshot()
			elseif method == "stats" then
				return stats
			elseif method == "view" then
				return views[(...)]
			elseif method == "talking" then
				return talk and talk.id or nil
			elseif method == "incident" then
				-- 생활콘텐츠 -> NPC (GwangalliFight relays the server's GwangalliNPCEvents)
				return Mind.incident(...)
			elseif method == "crime" then
				-- a crime from the fight path (GwangalliFight relays it): the witnesses around react
				local msg = ...
				if type(msg) == "table" and type(msg.crime) == "string" then
					Mind.onCrime(msg)
					return true
				end
				return false
			elseif method == "nearest" then
				-- GwangalliLaw (소매치기): the closest pedestrian within reach and whether we stand behind them
				local pp = playerPos()
				if not pp then
					return nil
				end
				local best, bd = nil, (tonumber((...)) or 3.6)
				for _, a in ctx.Crowd.agents do
					if not a.gone and a.pos and not a.companion and not a.clubGuest then
						local d = flatDist(pp, a.pos)
						if d < bd then
							best, bd = a, d
						end
					end
				end
				if not best then
					return nil
				end
				local hx, hz = -math.sin(best.yaw or 0), -math.cos(best.yaw or 0)
				local tx, tz = pp.X - best.pos.X, pp.Z - best.pos.Z
				local m = math.sqrt(tx * tx + tz * tz)
				local behind = m > 0.01 and (hx * tx + hz * tz) / m < -0.2
				local c = cOf(best)
				return { id = best.id, arch = M.archOf(c), name = c and c.name or nil, x = best.pos.X, y = best.pos.Y, z = best.pos.Z, dist = bd, behind = behind, talking = talk ~= nil and talk.a == best }
			elseif debugOn() then
				-- test harness only (queued: remotes must be called from the client's own thread)
				local args = table.pack(...)
				local function q(fn)
					table.insert(testQueue, fn)
					return true
				end
				if method == "begin" then
					return q(function()
						local a = ctx.Crowd.byId[args[1]]
						if a then
							-- test: bring them next to the player first
							local pp = playerPos()
							if pp and flatDist(pp, a.pos) > 6 then
								if a.mode == "talk" then
									a:endTalk(os.clock())
								end
								a.pos = Vector3.new(pp.X + 3, a.pos.Y, pp.Z + 1)
								a.node = ctx.World.nearest(a.pos, 40)
								a:idleFor("idle", 3, os.clock())
								a.moved = true
							end
							Mind.begin(a, args[2] or "talk")
						end
					end)
				elseif method == "summon" then
					return q(function()
						local a = ctx.Crowd.byId[args[1]]
						local pp = playerPos()
						if a and pp then
							a.pos = Vector3.new(pp.X + (args[2] or 6), a.pos.Y, pp.Z + (args[3] or 0))
							a.node = ctx.World.nearest(a.pos, 40)
							a:idleFor("idle", 2, os.clock())
							a.moved = true
						end
					end)
				elseif method == "lastreply" then
					return stats.lastReply or ""
				elseif method == "say" then
					return q(function()
						send({ text = args[1] })
					end)
				elseif method == "chip" then
					return q(function()
						send({ intent = args[1], item = args[2] })
					end)
				elseif method == "act" then
					return q(function()
						Mind.act(args[1], args[2])
					end)
				elseif method == "prank" then
					return q(function()
						local a = ctx.Crowd.byId[args[1]]
						if a then
							Mind.prank(a, args[2], os.clock())
						end
					end)
				elseif method == "scene" then
					return q(function()
						nextScene = 0
						sceneTick(os.clock())
					end)
				elseif method == "fightscene" then
					-- the two people nearest the player have it out (drunkfight)
					return q(function()
						local pp = playerPos()
						if not pp then
							return
						end
						local list = {}
						for _, a in ctx.Crowd.agents do
							if not a.gone and not a.ctl and not a.knock and not a.companion and not a.clubGuest and a.mode ~= "talk" then
								table.insert(list, a)
							end
						end
						table.sort(list, function(x, y)
							return flatDist(pp, x.pos) < flatDist(pp, y.pos)
						end)
						local a, b = list[1], list[2]
						local lines = M.scene("drunkfight", rnd)
						sceneEnding = tonumber(args[1])
						if a and b and lines then
							playScene(a, b, "drunkfight", lines)
						end
					end)
				elseif method == "quarrel" then
					-- the nearest person turns into a drunk and picks a quarrel right away
					return q(function()
						local pp = playerPos()
						local best, bd = nil, math.huge
						for _, a in ctx.Crowd.agents do
							if pp and not a.gone and not a.ctl and not a.knock and not a.companion and not a.clubGuest then
								local d = flatDist(pp, a.pos)
								if d < bd and d > 2.5 then
									best, bd = a, d
								end
							end
						end
						if not best or not pp then
							return
						end
						best.type = "drunk"
						local okF, FS = pcall(require, ReplicatedStorage:FindFirstChild("GwangalliFightShared") :: any)
						if okF and FS and best.startChase then
							local now = os.clock()
							best.quarrel = { untilT = now + 14, nextLine = now + 3, nextShove = now + 4, lines = FS.DRUNK_LINES }
							best:startChase(now, pp)
							sayNpc(best, pick(FS.DRUNK_LINES.start), 3.2)
							workspace:SetAttribute("GwangalliQuarrelId", best.id) -- (test harness)
						end
					end)
				elseif method == "police" then
					return q(function()
						Mind.policeChoice(args[1])
					end)
				elseif method == "phone" then
					return q(function()
						local ps = player:FindFirstChild("PlayerScripts")
						local m = ps and ps:FindFirstChild("GwangalliPhone")
						m = m and m:FindFirstChild("Phone")
						if m then
							local Phone = require(m :: ModuleScript) :: any
							Phone.open(args[1] or "people", args[2])
						end
					end)
				elseif method == "finish" then
					return q(function()
						finish("test")
					end)
				elseif method == "scenes" then
					return #scenes
				elseif method == "bubbles" then
					local p = pool()
					local out = {}
					if p then
						for _, it in p.items do
							table.insert(out, string.format("%s|%s|%s|%s", tostring(it.adornee and it.adornee:GetFullName()), tostring(it.gui.Enabled), it.label.Text, tostring(it.gui.Parent and it.gui.Parent:GetFullName())))
						end
					end
					return table.concat(out, "\n")
				elseif method == "bbtest" then
					return q(function()
						local pg = player:FindFirstChildOfClass("PlayerGui")
						local ch = player.Character
						local function mk(adornee, text, y, inWorld)
							local bb = Instance.new("BillboardGui")
							bb.Size = UDim2.fromOffset(220, 50)
							bb.StudsOffsetWorldSpace = Vector3.new(0, y, 0)
							bb.Adornee = adornee
							bb.AlwaysOnTop = true
							local t = Instance.new("TextLabel")
							t.Size = UDim2.fromScale(1, 1)
							t.Text = text
							t.TextSize = 16
							t.BackgroundColor3 = Color3.new(1, 1, 1)
							t.Parent = bb
							bb.Parent = if inWorld then adornee else pg
						end
						mk(ch and ch:FindFirstChild("Head"), "플레이어 머리", 2.5)
						mk(ch and ch:FindFirstChild("HumanoidRootPart"), "플레이어 루트", 5)
						local pp = playerPos()
						local best, bd = nil, 1e9
						for _, o in ctx.Crowd.agents do
							if not o.gone and o.rig.head and pp then
								local d = flatDist(o.pos, pp)
								if d < bd then
									best, bd = o, d
								end
							end
						end
						if best then
							mk(best.rig.head, "NPC 머리(world) " .. best.id, 2.5, true)
							mk(best.rig.root, "NPC 루트(world)", 5, true)
						end
						mk(ch and ch:FindFirstChild("Head"), "플레이어 머리(world)", 3.5, true)
					end)
				elseif method == "saytest" then
					return q(function()
						sayPlayer("테스트 말풍선입니다!", 8)
					end)
				elseif method == "pstate" then
					return { state = police.state, agent = police.agent and police.agent.id or nil, ctl = police.agent and police.agent.ctl and police.agent.ctl.kind or nil }
				end
			end
			return nil
		end
		print("[GwangalliMind] client ready (" .. tostring(#ctx.Crowd.agents) .. " people around)")
	end)
end

return Mind
