-- GwangalliGameplay/Bump (server, feature module: init(ctx) / onLoaded / onCharacter / onLeave).
-- 어깨빵 (shoulder bumps), the NPC-type dialogs that talk to the player first (chatty approaches), the
-- 걸렁뱅이's 천원만 and the 동네바보's laugh-it-off card. Contract: ReplicatedStorage.GwangalliBumpShared.
--
-- Server-authoritative: who falls (strength vs the target's type / build, streaks), 체력 -3 for a
-- knocked-down player, money given to a beggar (cash ledger), happiness / popularity, affinity
-- (Relationships via ctx.social). Every remote is validated (distance, facing, cooldown, token
-- bucket, plausibility of a client-side pedestrian's reported position) and rate limited.
-- Client-only pedestrians (GwangalliStreetLife) exist on one client: their knockdown motion plays
-- there (the "hit" event); when one of them knocks the local player over the client reports "fell",
-- which only ever affects that player's own stats. Key NPCs (NPC.luau) fall through the NpcKnock
-- attribute (NPC.knock) so everybody sees it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bump = {}

local ctx: any
local G: any
local Util: any
local Profiles: any
local Shared: any -- GwangalliBumpShared
local Social: any -- GwangalliSocialShared
local Citizens: any
local NPC: any -- NPC.luau (optional, via the gameplay module folder)

local remotes: { Action: RemoteEvent?, Event: RemoteEvent? } = {}
type Dlg = { id: string, kind: string, choices: { [string]: boolean }, openedAt: number, pos: Vector3?, refusals: number, c: any }
local dialogs: { [Player]: Dlg } = {}
local lastBump: { [Player]: number } = {} -- streak bookkeeping
local streak: { [Player]: number } = {}
local chatAt: { [Player]: { [string]: number } } = {}
local begRefusals: { [Player]: { [string]: number } } = {}
-- a player who was just put down (or staggered) cannot be bumped again until they are up plus a
-- short grace: no chained knockdowns, no griefing a player who is still on the ground
local downUntil: { [Player]: number } = {}
local DOWN_GRACE = 1.5
local forceOutcome: string? = nil -- test harness only (debug handler): the next bumps' outcome

local function requireShared(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 20)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliBump] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- debug trace (Workspace.GwangalliStreetLifeDebug = true: the sim scenarios / Studio only)
local function dbg(what: string, ...: any)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		print("[GwangalliBump:dbg] " .. what .. " " .. table.concat(parts, " "))
	end
end

local function citizen(id: any): any?
	return if type(id) == "string" and Citizens then Citizens.byId[id] else nil
end

local function typeOf(id: string): string
	local c = citizen(id)
	return (c and c.type) or "plain"
end

local function speechOf(id: string): string
	local c = citizen(id)
	return (c and c.speech) or "std"
end

local function line(id: string, kind: string): string?
	if not Social or type(Social.typeLine) ~= "function" then
		return nil
	end
	return Social.typeLine(typeOf(id), kind, speechOf(id))
end

local function clockNow(): number
	local ok, env = pcall(ctx.env)
	return if ok and env and type(env.clock) == "number" then env.clock % 24 else 12
end

local function areaPos(areaId: string): Vector3?
	local a = Citizens and Citizens.AREAS[areaId]
	local part = a and ctx.dest(a.dest)
	return part and part.Position or nil
end

local function send(player: Player, payload: any)
	local ev = remotes.Event
	if ev and player.Parent == Players then
		ev:FireClient(player, payload)
	end
end

local function sendAll(payload: any)
	local ev = remotes.Event
	if ev then
		ev:FireAllClients(payload)
	end
end

local function strengthOf(player: Player): number
	local d = Profiles.get(player)
	if d and d.stats and type(d.stats.strength) == "number" then
		return d.stats.strength
	end
	local a = player:GetAttribute(G.Attr.Strength)
	return if type(a) == "number" then a else 10
end

local function buildOf(id: string): string
	local c = citizen(id)
	return (c and c.look and c.look.build) or "avg"
end

local function award(player: Player, id: string, source: string, amount: number?)
	local social = ctx.social
	if social and type(social.award) == "function" and citizen(id) then
		pcall(social.award, player, id, source, amount)
	end
end

-- the player's state: alive, on foot, not working / riding / knocked down
local function canAct(player: Player): (boolean, string?)
	local character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return false, "dead"
	end
	if humanoid.Sit or humanoid.PlatformStand then
		return false, "seated"
	end
	if character:GetAttribute(Shared.Attr.Knocked) or os.clock() < (downUntil[player] or 0) then
		return false, "down"
	end
	if ctx.isRiding and ctx.isRiding(player) then
		return false, "taxi"
	end
	if ctx.onShift and ctx.onShift(player) then
		return false, "shift"
	end
	if player:GetAttribute(G.Attr.GymBusy) then
		return false, "gym"
	end
	return true
end

-- A key NPC's live position (nil when not spawned / hidden).
local function keyNpcPos(id: string): Vector3?
	if NPC and type(NPC.state) == "function" then
		local ok, st = pcall(NPC.state, id)
		if ok and st and not st.hidden and st.pos then
			return st.pos
		end
	end
	return nil
end

-- Validates a target position reported by the client for a pedestrian (one that only exists on
-- that client): close to the player and at their height. The third result says whether the spot is
-- plausible for that citizen's schedule (Citizens.plausible, generous slack: the client's crowd keeps
-- an agent for a while after the in-game clock moved its slot). The self-only remotes (fell / chat /
-- beg: they can only cost the reporting player 체력 or open a card for them) ignore plausibility;
-- 어깨빵 uses it only to decide whether affinity changes (no farming of far-away citizens).
local function pedestrianAt(player: Player, id: string, posT: any, reach: number): (Vector3?, string?, boolean)
	local pos = Shared.unpackV(posT)
	local myPos = Util.rootPosition(player)
	if not pos or not myPos then
		dbg("pedestrianAt", id, "nopos", posT)
		return nil, "nopos", false
	end
	if (flat(pos) - flat(myPos)).Magnitude > reach or math.abs(pos.Y - myPos.Y) > 8 then
		dbg("pedestrianAt", id, "far", (flat(pos) - flat(myPos)).Magnitude)
		return nil, "far", false
	end
	local plausible = true
	if Citizens and type(Citizens.plausible) == "function" then
		local ok, res = pcall(Citizens.plausible, id, pos, clockNow(), areaPos, 160)
		if ok and res == false then
			dbg("pedestrianAt", id, "implausible (no affinity change)")
			plausible = false
		end
	end
	return pos, nil, plausible
end

local function facing(player: Player, target: Vector3): boolean
	local _, _, root = Util.alive(player)
	if not root then
		return false
	end
	local to = flat(target - root.Position)
	if to.Magnitude < 0.3 then
		return true
	end
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		return true
	end
	return look.Unit:Dot(to.Unit) >= Shared.FACING
end

local function noteStreak(player: Player): number
	local now = os.clock()
	local last = lastBump[player] or -1e9
	local s = if now - last < Shared.STREAK_WINDOW then (streak[player] or 0) + 1 else 1
	streak[player] = s
	lastBump[player] = now
	player:SetAttribute(Shared.Attr.Streak, s)
	return s
end

local function dirFrom(from: Vector3, to: Vector3): (number, number)
	local d = flat(to - from)
	if d.Magnitude < 1e-3 then
		return 0, -1
	end
	d = d.Unit
	return d.X, d.Z
end

-- The victim's motion time (server side: knockdown / stagger + get up + grace).
local function noteDown(player: Player, outcome: string)
	local dur = if outcome == "knockdown" then Shared.KNOCK_DUR + Shared.GETUP_DUR else Shared.STAGGER_DUR
	downUntil[player] = math.max(downUntil[player] or 0, os.clock() + dur + DOWN_GRACE)
end

-- 체력 -3 and the knocked-down bookkeeping for a player who went down.
local function playerDown(player: Player, byLabel: string?)
	noteDown(player, "knockdown")
	if not Profiles.get(player) then
		return
	end
	pcall(ctx.addStats, player, { stamina = Shared.STAMINA_HIT }, nil, true)
	if byLabel then
		ctx.notify(player, "info", "어깨빵 맞음!", byLabel .. " · 체력 " .. tostring(Shared.STAMINA_HIT), { icon = "💥" })
	end
end

-------------------------------------------------------------------------------------------------
-- 어깨빵
-------------------------------------------------------------------------------------------------
local function bumpNpc(player: Player, id: string, payload: any)
	local c = citizen(id)
	if not c then
		return
	end
	local myPos = Util.rootPosition(player)
	if not myPos then
		return
	end
	local isKey = c.key == true
	local target: Vector3? = nil
	local why: string? = nil
	local plausible = true
	if isKey then
		target = keyNpcPos(id)
		if not target then
			why = "gone"
		elseif (flat(target) - flat(myPos)).Magnitude > Shared.RANGE + Shared.RANGE_SLACK then
			target, why = nil, "far"
		end
	else
		target, why, plausible = pedestrianAt(player, id, payload.pos, Shared.RANGE + Shared.RANGE_SLACK)
	end
	if not target then
		dbg("miss", id, why or "far")
		send(player, { kind = "miss", reason = why or "far" })
		return
	end
	if not facing(player, target) then
		dbg("miss", id, "facing")
		send(player, { kind = "miss", reason = "facing" })
		return
	end
	local s = noteStreak(player)
	local outcome = Shared.outcome(strengthOf(player), c.type, buildOf(id), s)
	if forceOutcome and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		outcome = forceOutcome
	end
	local dx, dz = dirFrom(myPos, target)
	local puk = if outcome == "knockdown" then Social.KNOCK_PUK[math.random(#Social.KNOCK_PUK)] else Social.PUK[math.random(#Social.PUK)]
	send(player, { kind = "hit", target = "npc", id = id, outcome = outcome, dx = dx, dz = dz, puk = puk, typeId = c.type })
	if plausible then
		award(player, id, "bump", Shared.AFFINITY[outcome] or -3)
	end
	if isKey and NPC and type(NPC.knock) == "function" then
		pcall(NPC.knock, id, dx, dz, outcome, player)
		local text = line(id, if outcome == "knockdown" then "down" else "bumped")
		if text then
			task.delay(if outcome == "knockdown" then Shared.KNOCK_DUR + 0.4 else 0.5, function()
				sendAll({ kind = "say", id = id, text = text, typeId = c.type, dur = 3.5 })
			end)
		end
	end
	-- 폭력적인 NPC: bumps back HARD (the player goes down) a beat later
	if c.type == "violent" then
		task.delay(if outcome == "knockdown" then Shared.KNOCK_DUR + Shared.GETUP_DUR + 0.3 else 0.9, function()
			if player.Parent ~= Players then
				return
			end
			local ok = canAct(player)
			if not ok then
				return
			end
			local pp = Util.rootPosition(player)
			if not pp or (flat(pp) - flat(target)).Magnitude > 14 then
				return
			end
			local rx, rz = dirFrom(target, pp)
			send(player, { kind = "fall", outcome = "knockdown", dx = rx, dz = rz, by = id, typeId = c.type, puk = Social.KNOCK_PUK[math.random(#Social.KNOCK_PUK)], text = line(id, "retaliate") })
			playerDown(player, c.name .. "의 반격")
		end)
	end
end

local function bumpPlayer(player: Player, userId: any, payload: any)
	local uid = tonumber(userId)
	if not uid then
		return
	end
	local victim = Players:GetPlayerByUserId(uid)
	if not victim or victim == player then
		return
	end
	if player:GetAttribute(Shared.Attr.Enabled) == false or victim:GetAttribute(Shared.Attr.Enabled) == false then
		send(player, { kind = "miss", reason = "protected" })
		return
	end
	if not Util.cooldown(player, "bump:pvp", Shared.COOLDOWN_PVP) then
		return
	end
	local ok = canAct(victim)
	if not ok then
		send(player, { kind = "miss", reason = "victim" })
		return
	end
	local myPos = Util.rootPosition(player)
	local vPos = Util.rootPosition(victim)
	if not myPos or not vPos or (flat(vPos) - flat(myPos)).Magnitude > Shared.RANGE + Shared.RANGE_SLACK then
		send(player, { kind = "miss", reason = "far" })
		return
	end
	if not facing(player, vPos) then
		send(player, { kind = "miss", reason = "facing" })
		return
	end
	noteStreak(player)
	local outcome = Shared.outcomePvp(strengthOf(player), strengthOf(victim))
	local dx, dz = dirFrom(myPos, vPos)
	local puk = if outcome == "knockdown" then Social.KNOCK_PUK[math.random(#Social.KNOCK_PUK)] else Social.PUK[math.random(#Social.PUK)]
	send(player, { kind = "hit", target = "player", id = uid, outcome = outcome, dx = dx, dz = dz, puk = puk })
	send(victim, { kind = "fall", outcome = outcome, dx = dx, dz = dz, byUser = player.UserId, puk = puk })
	if outcome == "knockdown" then
		playerDown(victim, player.DisplayName .. "의 어깨빵")
	else
		noteDown(victim, "stagger")
	end
end

-- an anonymous passer-by (GwangalliStreetLife "x<n>", client-only, no roster entry)
local function bumpAnon(player: Player, id: string, payload: any)
	local myPos = Util.rootPosition(player)
	if not myPos then
		return
	end
	local target, why = pedestrianAt(player, id, payload.pos, Shared.RANGE + Shared.RANGE_SLACK)
	if not target then
		send(player, { kind = "miss", reason = why or "far" })
		return
	end
	if not facing(player, target) then
		send(player, { kind = "miss", reason = "facing" })
		return
	end
	local s = noteStreak(player)
	local outcome = Shared.outcome(strengthOf(player), "plain", "avg", s)
	if forceOutcome and workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		outcome = forceOutcome
	end
	local dx, dz = dirFrom(myPos, target)
	local puk = if outcome == "knockdown" then Social.KNOCK_PUK[math.random(#Social.KNOCK_PUK)] else Social.PUK[math.random(#Social.PUK)]
	send(player, { kind = "hit", target = "npc", id = id, outcome = outcome, dx = dx, dz = dz, puk = puk, typeId = "plain" })
end

local function onBump(player: Player, payload: any)
	local ok, why = canAct(player)
	if not ok then
		send(player, { kind = "miss", reason = why })
		return
	end
	if payload.target == "player" then
		bumpPlayer(player, payload.id, payload)
		return
	end
	if not Util.cooldown(player, "bump:npc", Shared.COOLDOWN) then
		return
	end
	local id = Util.str(payload.id, 40)
	if id and citizen(id) then
		bumpNpc(player, id, payload)
	elseif id and string.match(id, "^x%d+$") then
		bumpAnon(player, id, payload)
	end
end

-------------------------------------------------------------------------------------------------
-- Dialogs (chatty approaches, the beggar, the fool's laugh-it-off card)
-------------------------------------------------------------------------------------------------
local function portrait(c: any): Color3
	local def = Social and Social.typeDef(c.type)
	local col = (c.type ~= "plain" and def and def.color) or c.accent
	if type(col) == "table" and #col >= 3 then
		return Color3.fromRGB(col[1], col[2], col[3])
	end
	return Color3.fromRGB(120, 120, 140)
end

-- A card never carries more than 3 choices + 안녕히 가세요 (4 buttons fit the phone card: the sim
-- flagged a 5th button as < 11 px text / < 44 px tap target). noBye: the card's ✕ closes it instead.
local function sendDialog(player: Player, dlg: Dlg, text: string, choices: { { id: string, label: string } }, emote: string?, noBye: boolean?)
	local out = {}
	table.clear(dlg.choices)
	local STYLES = { "primary", "secondary", "tonal" }
	for i, ch in choices do
		if i > 3 then
			break
		end
		dlg.choices[ch.id] = true
		table.insert(out, { id = ch.id, label = ch.label, style = STYLES[i] })
	end
	dlg.choices.bye = true
	if not noBye then
		table.insert(out, { id = "bye", label = "안녕히 가세요", style = "ghost" })
	end
	dlg.choices.close = true
	dialogs[player] = dlg
	ctx.remotes.Dialog:FireClient(player, {
		npcId = dlg.id,
		name = dlg.c.name,
		role = (Social and Social.typeDef(dlg.c.type).label) or dlg.c.job,
		portraitColor = portrait(dlg.c),
		text = text,
		choices = out,
		emote = emote,
	})
end

local function closeDialog(player: Player, bye: boolean?)
	local dlg = dialogs[player]
	if not dlg then
		return
	end
	dialogs[player] = nil
	if player.Parent == Players then
		ctx.remotes.Dialog:FireClient(player, { close = true })
		if bye then
			local text = line(dlg.id, "bye")
			if text then
				send(player, { kind = "say", id = dlg.id, text = text, typeId = dlg.c.type, dur = 3 })
			end
		end
	end
end

local JOB_HINTS = {
	"GS25 광안리점에서 알바 뽑는대요! 폰 알바 앱 한번 봐요 📱",
	"배달의광안 라이더 허브에서 사람 구한다던데… 알바 앱에 떠 있을 거예요.",
	"밀락더마켓 카페 알바 소문 들었어요? 폰 알바 앱 확인!",
}
local FOOD_HINTS = {
	{ text = "민락회타운 가봐요! 바다 보면서 회 한 접시 😋", dest = "민락회타운" },
	{ text = "밀락더마켓 수제버거 세트 강추! 먹방 인증각이에요.", dest = "밀락더마켓" },
	{ text = "스타벅스 광안리점 창가 자리가 광안대교 명당이에요 ☕", dest = "스타벅스 광안리점" },
}
local WAY_HINTS = {
	{ text = "광안대교요? 저쪽 해변 끝으로 쭉 가면 보여요! 지도에 찍어 드릴게요.", dest = "광안대교 상판" },
	{ text = "만남의 광장은 바로 저 앞이에요. 지도에 표시해 둘게요!", dest = "광안리 만남의 광장" },
	{ text = "CLUB OCEAN은 뒷골목으로 들어가면 돼요. 밤에 가요!", dest = "CLUB OCEAN 광안" },
}

local function openChat(player: Player, id: string, pos: Vector3?)
	local c = citizen(id)
	if not c then
		return
	end
	local now = os.clock()
	local per = chatAt[player]
	if not per then
		per = {}
		chatAt[player] = per
	end
	if now - (per[id] or -1e9) < Shared.CHAT_COOLDOWN or now - (per["*"] or -1e9) < Shared.CHAT_GLOBAL_GAP * 0.5 then
		dbg("openChat", id, "cooldown")
		return
	end
	per[id] = now
	per["*"] = now
	local dlg: Dlg = { id = id, kind = c.type, choices = {}, openedAt = now, pos = pos, refusals = 0, c = c }
	local opener = line(id, "opener") or "저기요! 혹시…"
	if c.type == "beggar" then
		local text = line(id, "beg") or opener
		sendDialog(player, dlg, text, {
			{ id = "give1", label = "천원 주기 (1,000원)" },
			{ id = "give5", label = "오천원 주기 (5,000원)" },
			{ id = "refuse", label = "죄송해요… 다음에요 (거절)" },
		}, "shy", true)
	elseif c.type == "fool" then
		sendDialog(player, dlg, opener, {
			{ id = "way", label = "길 묻기" },
			{ id = "joke", label = "농담 들어주기" },
			{ id = "photo", label = "사진 찍어 달라기" },
		}, "laugh")
	else
		-- 3 choices: 길 묻기 + 사진 + (추천 맛집 | 알바 소문), the third alternating per citizen
		local third = if (#id + (c.age or 0)) % 2 == 0 then { id = "food", label = "추천 맛집" } else { id = "job", label = "알바 소문" }
		sendDialog(player, dlg, opener, {
			{ id = "way", label = "길 묻기" },
			{ id = "photo", label = "사진 찍어 달라기" },
			third,
		}, "greet")
	end
end

local function openLaughOff(player: Player, id: string, outcome: string)
	local c = citizen(id)
	if not c or dialogs[player] then
		dbg("laughoff", id, "blocked", dialogs[player] and dialogs[player].id)
		return
	end
	local dlg: Dlg = { id = id, kind = "foolbump", choices = {}, openedAt = os.clock(), pos = nil, refusals = 0, c = c }
	local text = (line(id, "foolbump") or "어깨빵~ 히히") .. (if outcome == "knockdown" then "\n(넘어졌다… 체력 -3)" else "")
	sendDialog(player, dlg, text, {
		{ id = "laugh", label = "ㅋㅋ 괜찮아요 (웃어넘기기)" },
		{ id = "scold", label = "야! 조심 좀 해!" },
	}, "laugh")
end

local function followUp(player: Player, dlg: Dlg, text: string, emote: string?)
	sendDialog(player, dlg, text, {}, emote)
end

local function onChoice(player: Player, dlg: Dlg, choiceId: string)
	local id, c = dlg.id, dlg.c
	if choiceId == "close" then
		closeDialog(player, false)
		return
	elseif choiceId == "bye" then
		closeDialog(player, true)
		return
	end
	if not Util.cooldown(player, "bump:choice", 0.25) then
		return
	end
	local won = G.format and G.format.won or function(n)
		return tostring(n) .. "원"
	end
	if choiceId == "give1" or choiceId == "give5" then
		local amount = if choiceId == "give1" then Shared.GIVE[1] else Shared.GIVE[2]
		if not ctx.ledger(player, "cash", -amount, c.name .. "에게 적선", true) then
			followUp(player, dlg, "현금이 없네요… 괜찮아요, 마음만 받을게요.", "shy")
			return
		end
		ctx.notify(player, "money", "-" .. won(amount), c.name .. "에게 적선 · 행복 +2 · 인기도 +1")
		pcall(ctx.addStats, player, { happiness = 2, popularity = if amount >= 5000 then 2 else 1 }, nil, true)
		award(player, id, "give", if amount >= 5000 then 6 else 4)
		send(player, { kind = "say", id = id, text = line(id, "thanks") or "감사합니다!", typeId = c.type, dur = 4 })
		followUp(player, dlg, line(id, "thanks") or "아이고 감사합니다!", "cheer")
	elseif choiceId == "refuse" then
		local per = begRefusals[player]
		if not per then
			per = {}
			begRefusals[player] = per
		end
		per[id] = (per[id] or 0) + 1
		if per[id] >= 2 then
			send(player, { kind = "say", id = id, text = line(id, "leave") or "쩝…", typeId = c.type, dur = 3 })
			send(player, { kind = "leave", id = id })
			dialogs[player] = nil
			ctx.remotes.Dialog:FireClient(player, { close = true })
		else
			send(player, { kind = "say", id = id, text = line(id, "grumble") or "쩝…", typeId = c.type, dur = 3 })
			sendDialog(player, dlg, line(id, "grumble") or "쳇… 부자 되세요…", {
				{ id = "give1", label = "그래도 천원 (1,000원)" },
				{ id = "refuse", label = "정말 죄송해요 (거절)" },
			}, "refuse", true)
		end
	elseif choiceId == "laugh" then
		pcall(ctx.addStats, player, { happiness = 1 }, nil, true)
		award(player, id, "laughoff", 3)
		followUp(player, dlg, line(id, "laughed") or "히히 좋은 사람이네~", "cheer")
	elseif choiceId == "scold" then
		award(player, id, "spam", -2)
		followUp(player, dlg, line(id, "scolded") or "히이… 미안해…", "refuse")
	elseif choiceId == "way" then
		local h = WAY_HINTS[math.random(#WAY_HINTS)]
		award(player, id, "chatty", 2)
		if ctx.setWaypoint and ctx.dest(h.dest) then
			pcall(ctx.setWaypoint, player, h.dest)
		end
		send(player, { kind = "hint", app = "map", dest = h.dest })
		followUp(player, dlg, h.text, "think")
	elseif choiceId == "photo" then
		award(player, id, "chatty", 2)
		pcall(ctx.addStats, player, { happiness = 2, popularity = 1 }, "인생샷 한 장", true)
		followUp(player, dlg, if c.type == "fool" then "히히 찰칵! 어… 손가락이 찍혔다 히히 (행복 +2)" else "찰칵! 광안대교 배경으로 인생샷 나왔어요 📸 (행복 +2 · 인기도 +1)", "cheer")
	elseif choiceId == "food" then
		local h = FOOD_HINTS[math.random(#FOOD_HINTS)]
		award(player, id, "chatty", 2)
		if ctx.setWaypoint and ctx.dest(h.dest) then
			pcall(ctx.setWaypoint, player, h.dest)
		end
		send(player, { kind = "hint", app = "map", dest = h.dest })
		followUp(player, dlg, h.text, "nod")
	elseif choiceId == "job" then
		award(player, id, "chatty", 1)
		send(player, { kind = "hint", app = "jobs" })
		followUp(player, dlg, JOB_HINTS[math.random(#JOB_HINTS)], "think")
	elseif choiceId == "joke" then
		award(player, id, "chatty", 2)
		pcall(ctx.addStats, player, { happiness = 2 }, nil, true)
		local jokes = { "바다가 왜 짠 줄 알아? 물고기들이 자꾸 울어서! 히히히", "광안대교가 밤에 빛나는 이유? 자기도 셀카 찍고 싶어서~ 에헤헤", "갈매기가 치킨집 앞에 모이면? 치킨 콜! 히히" }
		followUp(player, dlg, jokes[math.random(#jokes)] .. "\n(행복 +2)", "laugh")
	end
end

local function dialogChoice(player: Player, payload: any)
	local dlg = dialogs[player]
	if not dlg then
		return
	end
	local id = Util.str(payload.npcId, 40)
	local choiceId = Util.str(payload.choiceId or payload.choice, 60)
	if not id or not choiceId or dlg.id ~= id or not dlg.choices[choiceId] then
		return
	end
	onChoice(player, dlg, choiceId)
end

-------------------------------------------------------------------------------------------------
-- Remote dispatch
-------------------------------------------------------------------------------------------------
local handlers: { [string]: (Player, any) -> () } = {}

handlers.bump = onBump

handlers.fell = function(player, p)
	if not Util.cooldown(player, "bump:fell", 4) then
		return
	end
	local id = Util.str(p.id, 40)
	local c = id and citizen(id)
	if not c or (c.type ~= "fool" and c.type ~= "violent" and c.type ~= "drunk") then
		dbg("fell", id, "type", c and c.type)
		return
	end
	local pos = pedestrianAt(player, id, p.pos, 12)
	if not pos then
		return
	end
	local outcome = if p.outcome == "knockdown" then "knockdown" else "stagger"
	if os.clock() < (downUntil[player] or 0) then
		return -- already down (e.g. the server's bump back landed first): one fall, one 체력 hit
	end
	if outcome == "stagger" then
		noteDown(player, "stagger")
	end
	if outcome == "knockdown" then
		-- the fool's card says "체력 -3" itself: no toast on top of the card header
		playerDown(player, if c.type == "fool" then nil else c.name .. "의 어깨빵")
	end
	if c.type == "fool" then
		openLaughOff(player, id, outcome)
	end
end

handlers.chat = function(player, p)
	if not Util.cooldown(player, "bump:chat", 2) then
		return
	end
	local id = Util.str(p.id, 40)
	local c = id and citizen(id)
	if not c or not c.chatty then
		dbg("chat", id, "not chatty")
		return
	end
	if dialogs[player] then
		dbg("chat", id, "dialog open", dialogs[player].id)
		return
	end
	local ok, why = canAct(player)
	if not ok then
		dbg("chat", id, "cannot", why)
		return
	end
	local pos = pedestrianAt(player, id, p.pos, 12)
	if not pos then
		return
	end
	openChat(player, id, pos)
end

handlers.beg = function(player, p)
	if not Util.cooldown(player, "bump:beg", 2) then
		return
	end
	local id = Util.str(p.id, 40)
	local c = id and citizen(id)
	if not c or c.type ~= "beggar" or dialogs[player] then
		dbg("beg", id, "blocked", c and c.type, dialogs[player] and dialogs[player].id)
		return
	end
	local ok, why = canAct(player)
	if not ok then
		dbg("beg", id, "cannot", why)
		return
	end
	local pos = pedestrianAt(player, id, p.pos, 12)
	if not pos then
		return
	end
	openChat(player, id, pos)
end

handlers.setting = function(player, p)
	player:SetAttribute(Shared.Attr.Enabled, p.enabled ~= false)
end

-- test harness only (tools/sim scenarios): retype a citizen while Workspace.GwangalliStreetLifeDebug
-- is true (an attribute only the server / Studio can set)
handlers.debug = function(_player, p)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
		return
	end
	local c = citizen(Util.str(p.id, 40))
	if not c then
		return
	end
	if type(p.type) == "string" and Social.TYPES[p.type] then
		c.type = p.type
	end
	if p.chatty ~= nil then
		c.chatty = p.chatty == true
	end
	if p.force == "knockdown" or p.force == "stagger" then
		forceOutcome = p.force
	elseif p.force == false then
		forceOutcome = nil
	end
	chatAt = {}
	begRefusals = {}
end

local function onAction(player: Player, kind: any, payload: any)
	if type(kind) ~= "string" or not handlers[kind] then
		return
	end
	if payload ~= nil and type(payload) ~= "table" then
		return
	end
	dbg("action", kind, payload and payload.id, payload and payload.outcome)
	if not Util.bucket(player, 6, 12) then
		dbg("action", kind, "bucket")
		return
	end
	if not Profiles.get(player) then
		dbg("action", kind, "noprofile")
		return
	end
	local ok, err = pcall(handlers[kind], player, payload or {})
	if not ok then
		warn(string.format("[GwangalliBump] %s from %s failed: %s", kind, player.Name, tostring(err)))
	end
end

local function tick()
	local now = os.clock()
	for player, dlg in dialogs do
		if player.Parent ~= Players then
			dialogs[player] = nil
		elseif now - dlg.openedAt > 75 then
			closeDialog(player, false)
		elseif dlg.pos then
			local pp = Util.rootPosition(player)
			if pp and (flat(pp) - flat(dlg.pos)).Magnitude > 18 then
				closeDialog(player, false)
				local text = line(dlg.id, "shrug")
				if text then
					send(player, { kind = "say", id = dlg.id, text = text, typeId = dlg.c.type, dur = 3 })
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Feature hooks
-------------------------------------------------------------------------------------------------
function Bump.enabled(player: Player): boolean
	return player:GetAttribute(Shared.Attr.Enabled) ~= false
end

function Bump.hasDialog(player: Player): boolean
	return dialogs[player] ~= nil
end

function Bump.onLoaded(player: Player)
	if player:GetAttribute(Shared.Attr.Enabled) == nil then
		player:SetAttribute(Shared.Attr.Enabled, true)
	end
end

function Bump.onCharacter(player: Player, _character: Model)
	if dialogs[player] then
		closeDialog(player, false)
	end
end

function Bump.onLeave(player: Player)
	dialogs[player] = nil
	lastBump[player] = nil
	streak[player] = nil
	chatAt[player] = nil
	begRefusals[player] = nil
	downUntil[player] = nil
end

function Bump.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	Shared = requireShared("GwangalliBumpShared")
	Social = requireShared("GwangalliSocialShared")
	Citizens = requireShared("GwangalliCitizens")
	if not Shared or not Social or not Citizens then
		warn("[GwangalliBump] shared modules missing; 어깨빵 disabled")
		return
	end
	-- NPC.luau (key NPC knockdowns) lives next to this module
	local folder = script.Parent
	local npcModule = folder and folder:FindFirstChild("NPC")
	if npcModule and npcModule:IsA("ModuleScript") then
		local ok, res = pcall(require, npcModule)
		if ok and type(res) == "table" then
			NPC = res
		end
	end
	-- remotes (parented last so clients that find the folder find both)
	local rf = ReplicatedStorage:FindFirstChild(Shared.Folder)
	if rf and not rf:IsA("Folder") then
		rf:Destroy()
		rf = nil
	end
	local fresh = rf == nil
	if not rf then
		rf = Instance.new("Folder")
		rf.Name = Shared.Folder
	end
	local function remote(name: string): RemoteEvent
		local r = (rf :: Instance):FindFirstChild(name)
		if r and not r:IsA("RemoteEvent") then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = rf
		end
		return r :: RemoteEvent
	end
	remotes.Action = remote(Shared.Remote.Action)
	remotes.Event = remote(Shared.Remote.Event)
	if fresh then
		(rf :: Instance).Parent = ReplicatedStorage
	end
	(remotes.Action :: RemoteEvent).OnServerEvent:Connect(onAction)
	-- dialog choices come back through the overlay's PhoneAction "dialogChoice"
	local phoneAction = ctx.remotes and ctx.remotes.PhoneAction
	if phoneAction then
		phoneAction.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
			if action ~= "dialogChoice" or type(payload) ~= "table" or not dialogs[player] then
				return
			end
			local ok, err = pcall(dialogChoice, player, payload)
			if not ok then
				warn("[GwangalliBump] dialog choice failed: " .. tostring(err))
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Shared.Attr.Enabled) == nil then
			player:SetAttribute(Shared.Attr.Enabled, true)
		end
	end
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliBump] tick failed: " .. tostring(err))
			end
		end
	end)
	ctx.bump = Bump
	print("[GwangalliBump] ready (어깨빵 + NPC type dialogs)")
end

return Bump
