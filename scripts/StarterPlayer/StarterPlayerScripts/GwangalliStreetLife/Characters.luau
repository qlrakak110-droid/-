-- GwangalliStreetLife/Characters (client; owner: npc_mind): the street "characters" with an edge.
--   * 동네바보 (fool): 시비 아닌 시비 — walks into people on purpose (어깨빵 on other pedestrians, a
--     daft line, the victim snaps back), talks with misspelt words (GwangalliMindShared.typo, every
--     fool line), and if the player keeps chasing him he runs, whines, and in the end trips over his
--     own feet and goes down in a heap (local only: no crime, nobody to blame; reward 0 like any KO).
--   * 주정뱅이 (drunk): the quarrel (Crowd's chase hook: slurring lines, following) turns into a real
--     scuffle when the player stays in his face — he talks a LOT first (lines every ~2 s).
--   * 걸렁뱅이 (punk): walks up and demands money (GwangalliGameplay.Mind: no money / no = a fight);
--     ignoring him (closing the talk) mostly ends in a fight too.
--   * 어깨빵 / walking into someone (Characters.bumped): who they are decides it - 친절 "괜찮아요",
--     예민 annoyed + a look + maybe an argument, 공격적 시비 / a shove / maybe a fight, 겁 많음 backs off
--     and runs, 취함 sways and may pick a quarrel, 무관심 walks on, 장난기 laughs it off.
--   * someone keeps walking right behind them (followTick): "왜 자꾸 따라와요?" by personality.
-- A fight = GwangalliFight "npcStart" (the server lets that NPC's swings land a while) + the crowd
-- brawl (Crowd.api "brawl").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MS: any = nil -- GwangalliMindShared (personality / lines)
pcall(function()
	MS = require(ReplicatedStorage:WaitForChild("GwangalliMindShared", 10) :: any)
end)
local FS: any = nil -- GwangalliFightShared (the warn / fight lines, the drunk quarrel)
pcall(function()
	FS = require(ReplicatedStorage:WaitForChild("GwangalliFightShared", 10) :: any)
end)
local SOCIAL: any = nil -- GwangalliSocialShared (the crowd types' own lines)
pcall(function()
	SOCIAL = require(ReplicatedStorage:WaitForChild("GwangalliSocialShared", 10) :: any)
end)

local Characters = {}

local player = Players.LocalPlayer
local deps: any

Characters.FOOL_BUMP_GAP = { 12, 24 } -- s between a fool's own 어깨빵 runs
Characters.CHASE_TEASE = 2.5 -- s of being chased
Characters.CHASE_WHINE = 7
Characters.CHASE_FALL = 11
Characters.DRUNK_FIGHT_AFTER = 6 -- s of quarrel before it can turn into a scuffle

local FOOL_BUMP = { "앗 미아내 ㅋㅋ 몬 바써~", "어깨빵 성공 ㅋㅋㅋ", "니가 거기 잇엇자나~ 히히", "부딧혀따 ㅋㅋㅋ 아프냐?", "나 일부러 그런거 아니얌~ ㅋ", "어 미아내 칭구야 ㅋㅋ" }
local BUMPED = { "아 뭐야!", "저 바보가 또…", "조심 좀 해요!", "어휴, 저 사람 진짜…", "아야! 앞 좀 보고 다녀!", "또 너냐?!" }
local TEASE = { "머야 왜 따라와 ㅋㅋㅋ", "나 잡아 바라~ 히히", "우와 술래잡기 하는고야?", "따라오지마 ㅋㅋ 무섭게 왜그래" }
local WHINE = { "헉헉… 따라오지 마아 나 무셔…!", "엄마아… 저 사람이 나 쫒아와…", "그만 쫒아와 나 숨차 주꺼가타…", "히잉 나 심장 약하단 마리야…!" }
local FALL = { "으악 나 넘어진다—!", "어어어 다리가 꼬여써…!", "헉… 나 이제 몬 뛰어… (꽈당)" }
local WITNESS = { "헐… 쟤 혼자 넘어졌어…", "동네바보 또 저런다…", "괜찮아요?! …숨은 쉬네.", "아이고 저걸 어째…", "ㅋㅋㅋ 아니 왜 혼자 넘어져" }
local DRUNK_MORE = { "야 내 말 좀 들어 봐 어? 딸꾹", "내가 왕년에 말이야~ 이 동네 짱이었어!", "너 지금 나 무시하냐? 어?", "한잔 하자니까~ 왜 대답을 안 해", "어딜 가 이야기 아직 안 끝났어!", "너 나 알지? 모른다고? 딸꾹", "야 이리 와 봐, 이리 와 보라고~" }
local DRUNK_FIGHT = { "이 자식이 말로 해선 안 되겠네! 딸꾹", "에잇 한 판 붙자 이거야~!", "오냐 오늘 끝장 보자!" }
local PUNK_IGNORE = { "어딜 가? 말 씹냐?", "야 대답 안 하고 가? 이리 와.", "무시해? 오늘 제대로 걸렸다." }
local followTick: (any, number, number, Vector3, number) -> ()

local function rnd(): number
	return math.random()
end

local function pick(list: { string }): string
	return list[1 + math.floor(rnd() * #list)]
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- a GwangalliFightShared line (warn / fight)
local function fsLine(key: string): string
	local L = FS and FS.LINES and FS.LINES[key]
	return if L and #L > 0 then pick(L) else "…"
end

local function say(a: any, text: string, dur: number?)
	if deps.Mind and deps.Mind.sayNpc then
		deps.Mind.sayNpc(a, text, dur or 2.8)
	end
end

local function busy(a: any): boolean
	return a.gone or a.ko or a.knock or a.ctl ~= nil or a.mode == "talk" or a.companion or a.clubGuest or a.brawl ~= nil or a.sitting or a.lying
end

-- a fight this NPC starts with the player
function Characters.startFight(a: any, why: string?): boolean
	if not a or a.gone or a.ko or a.brawl then
		return false
	end
	if deps.Mind and deps.Mind.release and a.ctl then
		pcall(deps.Mind.release, a)
	end
	-- one window: the server counts the swings exactly as long as this brawl lasts (a refusal calls it
	-- off here: GwangalliFight "brawlEnd")
	local secs = 9 + rnd() * 5
	deps.fire("npcStart", { id = a.id, ptype = a.type, pos = { a.pos.X, a.pos.Y, a.pos.Z }, why = why, secs = secs })
	deps.api("brawl", a.id, secs)
	deps.api("remember", a.id, "anger", 2)
	return true
end

-------------------------------------------------------------------------------------------------
-- 동네바보
-------------------------------------------------------------------------------------------------
local function foolBumpRun(f: any, now: number)
	-- the nearest walking stranger within 15 studs: he walks right into them
	local best, bd = nil, 15
	for _, o in deps.agents() do
		if o ~= f and not busy(o) and o.type ~= "fool" and o.type ~= "police" and o.mode == "walk" then
			local d = flat(o.pos, f.pos)
			if d < bd and d > 1.5 then
				best, bd = o, d
			end
		end
	end
	if not best then
		return
	end
	local target = best
	local ok = deps.Mind.take(f, { kind = "custom", untilT = now + 9, drive = function(a: any, ctl: any, t: number)
		if target.gone or target.knock or t > ctl.untilT then
			deps.Mind.release(a)
			return
		end
		local d = flat(target.pos, a.pos)
		if d < 2.1 then
			-- 어깨빵
			local dx, dz = target.pos.X - a.pos.X, target.pos.Z - a.pos.Z
			local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
			pcall(target.knockDown, target, dx / dd, dz / dd, "stagger", nil)
			say(a, pick(FOOL_BUMP), 2.8)
			task.delay(0.9, function()
				if not target.gone and not target.ko then
					say(target, pick(BUMPED), 2.6)
				end
			end)
			deps.Mind.release(a)
			return
		end
		if t >= (ctl.retarget or 0) then
			ctl.retarget = t + 0.4
			deps.Mind.moveTo(a, target.pos, 7.5)
		end
	end })
	if not ok then
		return
	end
end

local function foolFalls(f: any, pp: Vector3)
	local now = os.clock()
	if deps.Mind.release and f.ctl then
		pcall(deps.Mind.release, f)
	end
	say(f, pick(FALL), 2.4)
	task.delay(0.8, function()
		if f.gone or f.ko then
			return
		end
		local dx, dz = f.pos.X - pp.X, f.pos.Z - pp.Z
		local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
		-- down for good (local: a trip, no crime); taken away after a while like any KO
		pcall(f.knockDown, f, dx / dd, dz / dd, "knockdown", "꽈당!")
		f.ko = { untilT = os.clock() + 22, t0 = os.clock(), trip = true }
		f.brawl, f.quarrel, f.chase = nil, nil, nil
		-- two people nearby react (no 119 / 112 call: he fell by himself)
		local n = 0
		for _, o in deps.agents() do
			if n >= 2 then
				break
			end
			if o ~= f and not o.gone and not o.ko and not o.knock and o.pos and flat(o.pos, f.pos) < 18 then
				n += 1
				task.delay(0.6 + n * 0.9, function()
					if not o.gone then
						say(o, pick(WITNESS), 3)
					end
				end)
			end
		end
	end)
	local _ = now
end

local function foolChase(f: any, now: number, dt: number, pp: Vector3, pspeed: number)
	local d = flat(f.pos, pp)
	local ch = f.chased or { acc = 0, last = now, stage = 0 }
	f.chased = ch
	if now - ch.last > 20 then
		ch.acc, ch.stage = 0, 0
	end
	if d < 8 and pspeed > 3.5 and not f.knock and not f.ko and f.mode ~= "talk" then
		ch.acc += dt
		ch.last = now
	else
		ch.acc = math.max(0, ch.acc - dt * 0.4)
	end
	if ch.stage == 0 and ch.acc >= Characters.CHASE_TEASE then
		ch.stage = 1
		say(f, pick(TEASE), 2.5)
		if deps.Mind.flee then
			deps.Mind.flee(f, pp, 5)
		end
	elseif ch.stage == 1 and ch.acc >= Characters.CHASE_WHINE then
		ch.stage = 2
		say(f, pick(WHINE), 3)
		if deps.Mind.flee then
			deps.Mind.flee(f, pp, 5)
		end
	elseif ch.stage == 2 and ch.acc >= Characters.CHASE_FALL then
		ch.stage = 3
		foolFalls(f, pp)
	end
end

-------------------------------------------------------------------------------------------------
-- 주정뱅이: a quarrel that talks a lot and turns into a scuffle
-------------------------------------------------------------------------------------------------
local function drunkTick(a: any, now: number, pp: Vector3)
	local q = a.quarrel
	if not q then
		a.qT0, a.qDecided = nil, nil -- (every quarrel gets its own fight roll)
		return
	end
	a.qT0 = a.qT0 or now
	a.qLines = a.qLines or 0
	local d = flat(a.pos, pp)
	if now >= (a.qNext or 0) and d < 12 then
		a.qNext = now + 1.9 + rnd() * 0.8
		a.qLines += 1
		say(a, pick(DRUNK_MORE), 2.2)
	end
	if not a.qDecided and now - a.qT0 > Characters.DRUNK_FIGHT_AFTER and d < 5.5 then
		a.qDecided = true
		if rnd() < 0.7 then
			say(a, pick(DRUNK_FIGHT), 2.6)
			Characters.startFight(a, "drunk")
		end
	end
end

-------------------------------------------------------------------------------------------------
-- danger: a gun out, gunfire nearby, an assault seen (personality decides: run / stand / call / help)
-------------------------------------------------------------------------------------------------
local function persOf(a: any): any
	if MS and MS.personality then
		local ok, p = pcall(MS.personality, a.c or { id = a.id, type = a.type })
		if ok and type(p) == "table" then
			return p
		end
	end
	return { fear = 0.5, aggr = 0.3, justice = 0.4, isTimid = false, fearful = false, violent = false, just = false }
end

local function rl(key: string): string
	local L = MS and MS.REL_LINES and MS.REL_LINES[key]
	return if L then pick(L) else "…"
end

local GUN_WORDS = { "gun", "pistol", "rifle", "glock", "revolver", "shotgun", "smg", "uzi", "ak47", "m4", "deagle", "총", "권총", "소총", "엽총", "기관총" }
local function heldGun(char: Model?): boolean
	if not char then
		return false
	end
	if workspace:GetAttribute("GwangalliTestGun") == true then
		return true
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end
	local w = tool:GetAttribute("GwWeapon") or tool:GetAttribute("WeaponType")
	if w == "gun" or tool:GetAttribute("IsGun") == true or tool:GetAttribute("Gun") == true then
		return true
	end
	local n = string.lower(tool.Name)
	for _, word in GUN_WORDS do
		if string.find(n, word, 1, true) then
			return true
		end
	end
	return false
end

local function runFrom(a: any, from: Vector3, dur: number)
	if deps.Mind and deps.Mind.flee then
		pcall(deps.Mind.flee, a, from, dur)
	end
end

local function backOff(a: any, from: Vector3)
	if a.ctl then
		return -- (somebody else's control - a rider walking back to his scooter, a witness on the phone)
	end
	if not deps.Mind.take(a, { kind = "custom", untilT = os.clock() + 4, drive = function(ag: any, ctl: any, t: number)
		if t > ctl.untilT then
			deps.Mind.release(ag)
		end
	end }) then
		return
	end
	local dx, dz = a.pos.X - from.X, a.pos.Z - from.Z
	local dd = math.max(0.1, math.sqrt(dx * dx + dz * dz))
	deps.Mind.moveTo(a, Vector3.new(a.pos.X + dx / dd * 7, a.pos.Y, a.pos.Z + dz / dd * 7), 4)
end

-- the player holds a gun close by (riders: GwangalliStreetLife/Delivery does theirs)
local function gunTick(now: number, pp: Vector3)
	if not heldGun(player.Character) then
		return
	end
	for _, a in deps.agents() do
		if not a.gone and not a.delivery and not a.ko and not a.knock and a.type ~= "police" and a.pos and flat(a.pos, pp) < 18 and now >= (a.gunNext or 0) then
			a.gunNext = now + 9
			local p = persOf(a)
			if a.ctl and a.ctl.kind == "talk" then
				-- (the talk ends: a gun is not small talk)
				pcall(deps.Mind.release, a)
			end
			if (p.violent and not p.fearful and rnd() < 0.6) then
				say(a, rl("gun_stand"), 2.6)
				backOff(a, pp)
			else
				say(a, rl("gun_flee"), 2.4)
				runFrom(a, pp, if p.fearful or p.isTimid then 8 else 5)
			end
			if a.named and deps.Mind.street then
				deps.Mind.street(a.id, "gun", a.pos)
			end
		end
	end
end

function Characters.gunfire(pos: Vector3)
	local now = os.clock()
	for _, a in deps.agents() do
		if not a.gone and not a.ko and not a.knock and a.pos and flat(a.pos, pos) < 45 and now >= (a.shotNext or 0) and a.type ~= "police" then
			a.shotNext = now + 6
			local p = persOf(a)
			local stays = p.violent and not p.fearful and rnd() < 0.4
			if not stays then
				if rnd() < 0.35 then
					say(a, rl("gun_flee"), 2.2)
				end
				runFrom(a, pos, 6 + p.fear * 4)
			end
		end
	end
end

-- the player hit someone: people with a sense of justice react (dislike, call, help the victim)
function Characters.witness(victimId: string)
	local victim = nil
	for _, a in deps.agents() do
		if a.id == victimId then
			victim = a
		end
	end
	if not victim or not victim.pos then
		return
	end
	local n = 0
	for _, a in deps.agents() do
		if n >= 2 then
			break
		end
		if a ~= victim and not a.gone and not a.ko and not a.knock and a.pos and flat(a.pos, victim.pos) < 22 and a.type ~= "police" and os.clock() >= (a.justNext or 0) then
			local p = persOf(a)
			if p.just then
				n += 1
				a.justNext = os.clock() + 30
				say(a, rl("justice"), 3)
				if a.named and deps.Mind.street then
					deps.Mind.street(a.id, "witnessed", a.pos)
				end
				-- the braver ones go to the victim and help (kneel by them a while)
				if p.fear < 0.45 and not victim.gone then
					local vpos = victim.pos
					deps.Mind.take(a, { kind = "custom", untilT = os.clock() + 12, drive = function(ag: any, ctl: any, t: number)
						if t > ctl.untilT or victim.gone then
							deps.Mind.release(ag)
							return
						end
						if flat(ag.pos, vpos) > 2.2 then
							if t >= (ctl.re or 0) then
								ctl.re = t + 0.6
								deps.Mind.moveTo(ag, vpos, 7)
							end
						elseif not ctl.helped then
							ctl.helped = true
							say(ag, pick({ "괜찮아요? 정신 차려요!", "많이 다쳤어요? 119 불러 줄게요!", "일어날 수 있겠어요?" }), 3)
							ctl.untilT = t + 6
						end
					end })
				elseif deps.Mind.report then
					pcall(deps.Mind.report, a)
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- 어깨빵 / walking into someone: what they do depends on who they are (spec 3; the shared personality
-- GwangalliMindShared.personality, the same one Mind / Fight read). Crowd calls in: bumpKind before
-- the base reaction (to swap its line), bumped after it. Types with their own base reaction (fool /
-- beggar) and officers keep it.
-------------------------------------------------------------------------------------------------
local BUMP_SKIP = { fool = true, beggar = true, police = true }
local TOUCHY_Q = nil -- the verbal quarrel of 예민한 사람 (no start line: the bump line said it)

-- "kind" | "touchy" | "aggro" | "violent" | "timid" | "drunk" | "cold" | "playful" | "normal" (the
-- base line) | nil (not handled here: the base reaction only)
-- (somebody under another control - a.ctl: a rider walking back to his scooter or hands up, a witness
-- on a 112 call, a fight they stepped into - keeps it: the base reaction only)
function Characters.bumpKind(a: any): string?
	if not deps or not a or a.gone or a.ko or a.brawl or a.quarrel or a.ctl ~= nil or a.companion or a.clubGuest or a.mounted or a.riding or BUMP_SKIP[a.type] then
		return nil
	end
	if not (MS and MS.bumpStyle) then
		return nil -- (no shared personality here: the base reaction)
	end
	-- (GwangalliMindShared.bumpStyle: the same answer the server's memory of a named citizen's 어깨빵
	-- reads, GwangalliGameplay/Fight; again = bumped by the player a moment ago or still remembering
	-- something: no 괜찮아요 twice)
	local v = a.named and deps.Mind and deps.Mind.view and deps.Mind.view(a.id)
	local now = os.clock()
	local mem = a.memory
	local again = (a.bumpLastAt ~= nil and now - a.bumpLastAt < 120) or (mem ~= nil and now < mem.untilT and (mem.anger or 0) + (mem.fear or 0) >= 1)
	local okS, st = pcall(MS.bumpStyle, persOf(a), a.type, again, (v and v.npcMood == "DRUNK") == true)
	return if okS and type(st) == "string" then st else nil
end

-- the line they say getting up after a 어깨빵 (in place of the base "조심 좀 하세요!"); nil = the base
-- line, "" = none
function Characters.bumpLine(a: any, kind: string, down: boolean): string?
	if a.type ~= "plain" then
		return nil -- (a type with its own bump lines - 부자, 걸렁뱅이 - keeps them; what follows is still theirs)
	end
	if kind == "kind" then
		return rl(if down then "bump_kind_down" else "bump_kind")
	elseif kind == "timid" then
		return rl("bump_timid")
	elseif kind == "touchy" then
		local L = MS and MS.REL_LINES and MS.REL_LINES.bump_touchy
		return if L then pick(L.start) else rl("touchy")
	elseif kind == "cold" then
		return if rnd() < 0.5 then rl("bump_cold") else ""
	elseif kind == "playful" then
		return rl("bump_playful")
	elseif kind == "aggro" then
		return rl("bump_aggro")
	end
	return nil
end

-- 취한 사람 in the DRUNK mood (a named citizen, not the drunk type): sways into you like a drunk
function Characters.drunkBump(a: any, pp: Vector3): boolean
	if not deps or a.sitting or a.lying or a.sitGround or a.napping or not a.knockDown or not a.hitPlayer then
		return false
	end
	local dx, dz = a.pos.X - pp.X, a.pos.Z - pp.Z
	local d = math.max(0.05, math.sqrt(dx * dx + dz * dz))
	a.playerBumpAt = os.clock()
	a:knockDown(dx / d, dz / d, "stagger", nil)
	-- (the drunk's own bump line, GwangalliSocialShared: their speech too)
	local okL, oops = pcall(function()
		return SOCIAL and SOCIAL.typeLine("drunk", "accident", a.c and a.c.speech)
	end)
	a:hitPlayer(-dx / d, -dz / d, "stagger", if okL and type(oops) == "string" then oops else nil)
	return true
end

-- the walk-into line by personality; a crowd type with its own bump lines (부자, 걸렁뱅이) says one of
-- those (Crowd keeps the base quip quiet for this reaction)
local function walkLine(a: any, key: string): string
	if a.type ~= "plain" and a.typeLine then
		local okT, l = pcall(a.typeLine, a, "bumped")
		if okT and type(l) == "string" and l ~= "" then
			return l
		end
	end
	return rl(key)
end

local function freeNow(a: any): boolean
	return not (a.gone or a.ko or a.knock or a.brawl or a.ctl or a.mode == "talk")
end

local function playerFree(): boolean
	return not (deps.seated and deps.seated())
end

-- after the base reaction: how = "walk" (walked into them) | "knock" (a 어깨빵 put them down / made
-- them stagger, back on their feet now)
function Characters.bumped(a: any, how: string, kind: string, now: number)
	local pp = deps and deps.playerPos()
	local M = deps and deps.Mind
	if not pp or not M or a.gone or a.ko then
		return
	end
	local d = flat(a.pos, pp)
	local run = a.bumpRun
	if not run or now - run.t > 20 then
		run = { n = 0, t = now }
		a.bumpRun = run
	end
	run.n += 1
	run.t = now
	a.bumpLastAt = now -- (bumpKind: the next one within 2 min is not shrugged off)
	local mem = a.memory
	local rep = run.n >= 2 or (mem ~= nil and now < mem.untilT and (mem.anger or 0) >= 2)
	local walk = how == "walk"
	local talkOk = not walk or (deps.canSay == nil or deps.canSay(now))
	local remember: string? = nil
	a.memNext = now + 6 -- (Mind.react's "또 너냐?" not on top of this one)
	if kind == "kind" then
		if walk and talkOk then
			say(a, walkLine(a, "bump_kind"), 2.5)
		end
		M.face(a, "smile", 2.5)
	elseif kind == "playful" then
		if walk and talkOk then
			say(a, walkLine(a, "bump_playful"), 2.6)
		end
		M.face(a, "laugh", 2.5)
		if M.gesture then
			M.gesture(a, "laugh")
		end
	elseif kind == "cold" then
		if walk and talkOk and rnd() < 0.4 then
			say(a, walkLine(a, "bump_cold"), 2)
		end
		a.lookUntil = now -- (not even a look)
	elseif kind == "timid" then
		remember = "fear"
		if walk and talkOk then
			say(a, walkLine(a, "bump_timid"), 2.4)
		end
		M.face(a, "scared", 3)
		if walk then
			backOff(a, pp)
		else
			runFrom(a, pp, 5)
		end
	elseif kind == "touchy" then
		remember = "anger"
		M.face(a, "annoyed", 4)
		a.lookUntil = now + 3.5
		if M.lookAtPlayer then
			M.lookAtPlayer(a, 3)
		end
		if walk and talkOk then
			say(a, walkLine(a, "touchy"), 2.8)
		end
		-- 말싸움 maybe: a verbal quarrel (follows a few steps, no shove; walk off and it is over)
		if playerFree() and d < 9 and (rep or rnd() < 0.3) and now >= (a.nextQuarrel or 0) and M.startQuarrel then
			a.nextQuarrel = now + 40
			local L = MS and MS.REL_LINES and MS.REL_LINES.bump_touchy
			TOUCHY_Q = TOUCHY_Q or (L and { follow = L.follow, calm = L.calm })
			task.delay(1.8, function()
				if freeNow(a) and not a.chase and playerFree() and TOUCHY_Q then
					M.startQuarrel(a, TOUCHY_Q, { secs = 7 + rnd() * 3, noShove = true, keep = 3.5 })
				end
			end)
		end
	elseif kind == "aggro" or kind == "violent" then
		remember = "anger"
		M.face(a, "angry", 4)
		a.lookUntil = now + 3
		if kind == "violent" and a.type == "thug" and not walk and not a.chase and playerFree() and d > 6 and d < 32 and a.startChase then
			-- (the base runs after you only for the violent type; a 불량배 too)
			a:startChase(now, pp)
		end
		-- 시비 -> 밀치기 -> 싸움 maybe (a violent type's hard bump-back comes from the server: no shove)
		task.delay(if walk then 0.6 else 1.2, function()
			local p2 = deps.playerPos()
			if not p2 or not freeNow(a) or not playerFree() then
				return
			end
			local dd = flat(a.pos, p2)
			if dd > 12 then
				return
			end
			a.lookUntil = os.clock() + 3
			if M.gesture then
				M.gesture(a, "point")
			end
			if kind == "aggro" then
				if walk then
					local l = if a.type ~= "plain" then a:typeLine("bumped") else nil
					say(a, l or rl("bump_aggro"), 2.8)
				else
					say(a, fsLine("warn"), 2.8)
				end
				if dd < 4 and a.hitPlayer and rnd() < (if rep then 0.8 else 0.5) then
					local ux, uz = (p2.X - a.pos.X) / math.max(dd, 0.05), (p2.Z - a.pos.Z) / math.max(dd, 0.05)
					a:hitPlayer(ux, uz, "stagger", nil)
				end
			elseif walk and dd < 4 and a.hitPlayer and rnd() < 0.4 then
				local ux, uz = (p2.X - a.pos.X) / math.max(dd, 0.05), (p2.Z - a.pos.Z) / math.max(dd, 0.05)
				a:hitPlayer(ux, uz, "stagger", nil)
			end
			local chance = if kind == "aggro" then (if rep then 0.7 else 0.35) else (if rep then 0.6 else 0.3)
			-- (one fight over a bump in a while: after it they walk on, a brush in passing is not round two)
			if os.clock() >= (a.bumpFightAt or -1e9) + 45 and rnd() < chance then
				a.bumpFightAt = os.clock()
				task.delay(if kind == "violent" and not walk then 1.6 else 1.4, function()
					local p3 = deps.playerPos()
					if p3 and freeNow(a) and not a.chase and playerFree() and flat(a.pos, p3) < 10 then
						say(a, fsLine("fight"), 2.6)
						Characters.startFight(a, "bump")
					end
				end)
			end
		end)
	elseif kind == "normal" then
		-- 평범함: the base scold line; shoved again and again (the short memory) they call it in or square up
		if not walk then
			remember = "anger"
			if rep and mem ~= nil and (mem.anger or 0) >= 2 then
				task.delay(0.6, function()
					if not freeNow(a) then
						return
					end
					if rnd() < 0.5 and M.report then
						M.report(a)
					else
						M.face(a, "angry", 3)
						if M.lookAtPlayer then
							M.lookAtPlayer(a, 3)
						end
						say(a, fsLine("warn"), 2.8)
					end
				end)
			end
		end
	elseif kind == "drunk" then
		remember = "anger"
		if playerFree() and d < 8 and now >= (a.nextQuarrel or 0) and now - (a.carHitAt or -1e9) > 4 and rnd() < 0.5 and M.startQuarrel then
			a.nextQuarrel = now + 40 + rnd() * 40 -- (the same field Mind.react uses: the two do not stack)
			local FSx = FS
			if FSx and FSx.DRUNK_LINES then
				task.delay(0.8, function()
					if freeNow(a) and not a.chase and playerFree() and M.startQuarrel(a, FSx.DRUNK_LINES, { secs = 10 + rnd() * 5 }) and a.quarrel then
						a.quarrel.drunk = true -- (drunkTick runs it, the named DRUNK-mood ones too)
						a.qDecided, a.qT0 = nil, nil
					end
				end)
			end
		end
	end
	if remember then
		-- the short memory (anonymous: only here; a named citizen's 어깨빵 comes back from the server as
		-- "remember", a walk-into does not)
		if not a.named or walk then
			deps.api("remember", a.id, remember, 1)
		end
		if a.named and walk and M.street then
			M.street(a.id, "bumped_by", a.pos)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- following someone: keep walking right behind a person a few seconds and they say something
-------------------------------------------------------------------------------------------------
local FOLLOW_SKIP = { fool = true, drunk = true, punk = true, police = true, thug = true, beggar = true }
local FOLLOW_KIND = { "저기, 혹시 길 찾으세요?", "저한테 볼일 있으세요?", "어… 저 따라오시는 거예요?" }
local FOLLOW_AGAIN = { "계속 따라오시면 진짜 경찰 불러요!", "아 진짜 왜 이래요?! 따라오지 마세요!", "그만 좀 따라와요, 무섭게!" }
function followTick(a: any, now: number, dt: number, pp: Vector3, pspeed: number)
	if FOLLOW_SKIP[a.type] or a.mounted or a.riding or a.leader or a.mode ~= "walk" or busy(a) or (a.speed or 0) < 1 or not playerFree() then
		a.folAcc = if a.folAcc then math.max(0, a.folAcc - dt) else nil
		return
	end
	local d = flat(a.pos, pp)
	-- close behind them while they walk (not in front: that is walking toward them)
	local fx, fz = -math.sin(a.yaw or 0), -math.cos(a.yaw or 0)
	local behind = ((pp.X - a.pos.X) * fx + (pp.Z - a.pos.Z) * fz) < 0.5 * d
	if d < 6.5 and pspeed > 2.5 and behind then
		a.folAcc = (a.folAcc or 0) + dt
	else
		a.folAcc = math.max(0, (a.folAcc or 0) - dt * 0.5)
	end
	if a.folAcc < 5 or now < (a.folNext or 0) or (deps.canSay and not deps.canSay(now)) then
		return
	end
	a.folAcc, a.folNext = 0, now + 20
	local again = now - (a.folLast or -1e9) < 60
	a.folLast = now
	a.memNext = now + 8
	local p = persOf(a)
	local M = deps.Mind
	local mood = "anger"
	if p.fearful or p.isTimid then
		mood = "fear"
		say(a, if again then pick(FOLLOW_AGAIN) else rl("scared"), 2.6)
		runFrom(a, pp, if again then 7 else 5)
	elseif p.violent then
		say(a, rl("provoke"), 2.8)
		if M.face then
			M.face(a, "angry", 3)
		end
		if d < 5 and now >= (a.bumpFightAt or -1e9) + 45 and rnd() < (if again then 0.6 else 0.3) then
			a.bumpFightAt = now
			task.delay(1.2, function()
				if freeNow(a) then
					Characters.startFight(a, "followed")
				end
			end)
		end
	elseif p.cold and not again then
		say(a, rl("ignore"), 2) -- (no stop: they walk on)
	elseif p.isKind and not again then
		mood = "fear"
		say(a, pick(FOLLOW_KIND), 2.8)
		if M.lookAtPlayer then
			M.lookAtPlayer(a, 2)
		end
	else
		say(a, if again then pick(FOLLOW_AGAIN) else rl("followed"), 2.8)
		if M.face then
			M.face(a, if again then "scared" else "annoyed", 3)
		end
		if M.lookAtPlayer then
			M.lookAtPlayer(a, 2.5)
		end
		if again then
			mood = "fear"
			runFrom(a, pp, 4)
		end
	end
	if a.named and M.street then
		M.street(a.id, "chased", a.pos)
	end
	deps.api("remember", a.id, mood, 1)
end

-------------------------------------------------------------------------------------------------
-- step
-------------------------------------------------------------------------------------------------
local queued: { any } = {}
local lastT = os.clock()
local nextFoolRun = 0
local function step()
	local now = os.clock()
	local dt = math.min(0.5, now - lastT)
	if dt < 0.15 then
		return
	end
	lastT = now
	while #queued > 0 do
		Characters.startFight(table.remove(queued, 1), "test")
	end
	local pp = deps.playerPos()
	if not pp then
		return
	end
	local pspeed = deps.playerSpeed()
	gunTick(now, pp)
	for _, a in deps.agents() do
		if not a.gone and a.pos and flat(a.pos, pp) < 70 then
			local t = a.type
			if t == "fool" then
				foolChase(a, now, dt, pp, pspeed)
				if now >= nextFoolRun and now >= (a.nextBumpRun or 0) and not busy(a) then
					a.nextBumpRun = now + Characters.FOOL_BUMP_GAP[1] + rnd() * (Characters.FOOL_BUMP_GAP[2] - Characters.FOOL_BUMP_GAP[1])
					nextFoolRun = now + 5
					foolBumpRun(a, now)
				end
			elseif t == "drunk" or (a.quarrel and a.quarrel.drunk) then
				drunkTick(a, now, pp)
			elseif flat(a.pos, pp) < 12 then
				followTick(a, now, dt, pp, pspeed)
			end
		end
	end
end

-- test harness only (GwangalliStreetAPI "chartest")
function Characters.test(kind: string, id: string): any
	local a = nil
	for _, o in deps.agents() do
		if o.id == id then
			a = o
		end
	end
	if not a then
		return false
	end
	local pp = deps.playerPos()
	if kind == "foolfall" and pp then
		foolFalls(a, pp)
		return true
	elseif kind == "bumprun" then
		foolBumpRun(a, os.clock())
		return a.ctl ~= nil
	elseif kind == "fight" then
		table.insert(queued, a) -- (run on the client thread: FireServer)
		return true
	elseif kind == "state" then
		return { ko = a.ko ~= nil, trip = a.ko and a.ko.trip == true or false, brawl = a.brawl ~= nil, ctl = a.ctl and a.ctl.kind or nil, quarrel = a.quarrel ~= nil }
	end
	return nil
end

function Characters.init(d: any)
	deps = d
	if deps.Mind then
		deps.Mind.startFight = Characters.startFight
		deps.Mind.punkIgnored = function(a: any)
			if a and not a.gone and rnd() < 0.75 then
				task.delay(0.6, function()
					if not a.gone and not a.ko then
						say(a, pick(PUNK_IGNORE), 2.6)
						Characters.startFight(a, "ignored")
					end
				end)
				return true
			end
			return false
		end
	end
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[GwangalliStreetLife.Characters] " .. tostring(err))
		end
	end)
end

return Characters
