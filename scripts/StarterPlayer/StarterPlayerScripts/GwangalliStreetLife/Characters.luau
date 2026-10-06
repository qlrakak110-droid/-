-- GwangalliStreetLife/Characters (client; owner: npc_mind): the street "characters" with an edge.
--   * 동네바보 (fool): 시비 아닌 시비 — walks into people on purpose (어깨빵 on other pedestrians, a
--     daft line, the victim snaps back), talks with misspelt words (GwangalliMindShared.typo, every
--     fool line), and if the player keeps chasing him he runs, whines, and in the end trips over his
--     own feet and goes down in a heap (local only: no crime, nobody to blame; reward 0 like any KO).
--   * 주정뱅이 (drunk): the quarrel (Crowd's chase hook: slurring lines, following) turns into a real
--     scuffle when the player stays in his face — he talks a LOT first (lines every ~2 s).
--   * 걸렁뱅이 (punk): walks up and demands money (GwangalliGameplay.Mind: no money / no = a fight);
--     ignoring him (closing the talk) mostly ends in a fight too.
-- A fight = GwangalliFight "npcStart" (the server lets that NPC's swings land a while) + the crowd
-- brawl (Crowd.api "brawl").

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

local function rnd(): number
	return math.random()
end

local function pick(list: { string }): string
	return list[1 + math.floor(rnd() * #list)]
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
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
	deps.fire("npcStart", { id = a.id, ptype = a.type, pos = { a.pos.X, a.pos.Y, a.pos.Z }, why = why })
	deps.api("brawl", a.id, 9 + rnd() * 5)
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
		a.qT0 = nil
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
			elseif t == "drunk" then
				drunkTick(a, now, pp)
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
