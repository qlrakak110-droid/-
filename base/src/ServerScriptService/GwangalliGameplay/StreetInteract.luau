-- GwangalliGameplay/Interact (server feature module: init(ctx) / onLoaded / onCharacter / onLeave; the
-- "Interact" slot of GwangalliGameplay's FEATURE_MODULES — no other script is edited).
-- 광안리 GTA city life: the entry point of the city-NPC system. Children:
--   Cast (people data), Lines (dialogue data), Talk (line picking), Memory (relationships), World
--   (senses + incidents), Places (seats / doors / the GS25 광안리점 store / elevators adapters), Mind
--   (brains: mood, conflict ladder, reactions), Routine (schedules + activities), Verbs (the player's
--   actions on city NPCs), Police (cases, patrol cars, arrests), Hazard (cars vs pedestrians), Actors
--   (bodies + motion attributes).
-- This module owns the player side: the remotes, the player's combat HP, crimes -> wanted stars (only
-- once the police KNOW: a cop saw it or somebody reported it), BUSTED / WASTED / tickets, dialog cards,
-- the small carried-food slot, and the verbs on street pedestrians (client-side) and key NPCs.
-- Contract: ReplicatedStorage.GwangalliStreetCombatShared. Client: StarterPlayerScripts.GwangalliInteractClient.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Interact = {}

local ctx: any
local G: any
local Util: any
local Profiles: any
local C: any
local Citizens: any
local NPC: any
local M: { [string]: any } = {} -- children

local remotes: { Action: RemoteEvent?, Event: RemoteEvent? } = {}

local PS: { [Player]: any } = {}
local rnd = Random.new()
local function range(t: { number }): number
	return t[1] + (t[2] - t[1]) * rnd:NextNumber()
end

local function S(player: Player): any
	local s = PS[player]
	if not s then
		s = {
			hp = 100,
			lastHurt = -1e9,
			busy = nil,
			wanted = 0,
			stars = 0,
			seenT = 0,
			lastSeenPos = nil,
			combo = 0,
			lastPunch = -1e9,
			fighters = {},
			pedHp = {},
			keyHp = {},
			pending = {},
			pendingAt = nil,
			reportAt = nil,
			handsUp = false,
			dialog = nil,
			frozen = nil,
			koSeq = 0,
			strength = 20,
			crimeLog = {},
		}
		PS[player] = s
	end
	return s
end
Interact.state = S

local function fire(player: Player, payload: any)
	if remotes.Event and player.Parent == Players then
		(remotes.Event :: RemoteEvent):FireClient(player, payload)
	end
end
Interact.fire = fire

local function fireAll(payload: any)
	if remotes.Event then
		(remotes.Event :: RemoteEvent):FireAllClients(payload)
	end
end
Interact.fireAll = fireAll

---------------------------------------------------------------------------------------------------
-- player helpers
---------------------------------------------------------------------------------------------------
local function charOf(player: Player): (Model?, Humanoid?, BasePart?)
	local ch = player.Character
	if not ch then
		return nil
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local root = ch:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") or hum.Health <= 0 then
		return nil
	end
	return ch, hum, root :: BasePart
end
Interact.charOf = charOf

local function feetOf(player: Player): Vector3?
	local _, hum, root = charOf(player)
	if not hum or not root then
		return nil
	end
	return root.Position - Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5, 0)
end
Interact.feetOf = feetOf

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
Interact.flatDist = flatDist

local function facing(player: Player, pos: Vector3): number
	local _, _, root = charOf(player)
	if not root then
		return -1
	end
	local look = root.CFrame.LookVector
	local d = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
	if d.Magnitude < 0.6 then
		return 1
	end
	local l = Vector3.new(look.X, 0, look.Z)
	if l.Magnitude < 1e-3 then
		return 1
	end
	return l.Unit:Dot(d.Unit)
end

local function canAct(player: Player): boolean
	local s = S(player)
	if s.busy then
		return false
	end
	local _, hum = charOf(player)
	if not hum or hum.Sit or hum.SeatPart then
		return false
	end
	if ctx.isRiding and ctx.isRiding(player) then
		return false
	end
	return true
end
Interact.canAct = canAct

local function strengthOf(player: Player): number
	local d = Profiles.get(player)
	local st = d and d.stats and d.stats.strength
	return if type(st) == "number" then math.clamp(st, 0, 100) else 20
end

local function notify(player: Player, kind: string, title: string, body: string?, extra: any?)
	pcall(ctx.notify, player, kind, title, body, extra)
end
Interact.notify = notify

local function setAttr(inst: Instance, k: string, v: any)
	if inst:GetAttribute(k) ~= v then
		inst:SetAttribute(k, v)
	end
end

local function pushHP(player: Player, s: any)
	setAttr(player, C.Attr.HP, math.floor(s.hp + 0.5))
	setAttr(player, C.Attr.Max, C.PLAYER_HP)
end

local function freeze(player: Player, on: boolean)
	local s = S(player)
	local _, hum = charOf(player)
	local ch = player.Character
	local h = hum or (ch and ch:FindFirstChildOfClass("Humanoid"))
	if on then
		if h and not s.frozen then
			s.frozen = { ws = h.WalkSpeed, jp = h.JumpPower, jh = h.JumpHeight, hum = h }
			h.WalkSpeed = 0
			h.JumpPower = 0
			h.JumpHeight = 0
		end
	else
		local f = s.frozen
		s.frozen = nil
		if f and f.hum and f.hum.Parent then
			f.hum.WalkSpeed = if f.ws and f.ws > 0 then f.ws else 16
			f.hum.JumpPower = if f.jp and f.jp > 0 then f.jp else 50
			f.hum.JumpHeight = if f.jh and f.jh > 0 then f.jh else 7.2
		end
	end
end
Interact.freeze = freeze

---------------------------------------------------------------------------------------------------
-- player HP
---------------------------------------------------------------------------------------------------
local knockout -- forward

function Interact.hurtPlayer(player: Player, dmg: number, opts: any?): boolean
	local s = S(player)
	if s.busy then
		return false
	end
	local _, hum = charOf(player)
	if not hum then
		return false
	end
	local o = opts or {}
	dmg = math.max(0, math.floor(dmg + 0.5))
	s.hp = math.max(0, s.hp - dmg)
	s.lastHurt = os.clock()
	pushHP(player, s)
	local outcome = o.outcome
	if s.hp <= 0 then
		outcome = "knockdown"
	end
	fire(player, { kind = "hurt", dmg = dmg, hp = s.hp, max = C.PLAYER_HP, by = o.by, dx = o.dx or 0, dz = o.dz or 0, outcome = outcome, line = o.line, actor = o.actor, ped = o.ped })
	if outcome == "knockdown" then
		pcall(ctx.addStats, player, { stamina = -2 }, nil, true)
	end
	if s.hp <= 0 then
		task.delay(0.5, function()
			knockout(player, o.by)
		end)
	end
	return true
end

function Interact.heal(player: Player, amount: number)
	local s = S(player)
	s.hp = math.min(C.PLAYER_HP, s.hp + amount)
	pushHP(player, s)
end

---------------------------------------------------------------------------------------------------
-- crime -> wanted stars. A crime is "pending" until the police know about it (a cop sees it, or a
-- witness / the victim calls 112 -> Police.report -> Interact.policeKnow). Crimes on the street
-- pedestrians (client-side, no server witnesses) are called in by a passer-by after a few seconds
-- when the client says people were around.
---------------------------------------------------------------------------------------------------
local function applyStars(player: Player, s: any)
	local stars = math.clamp(math.floor(s.wanted + 1e-6), 0, C.MAX_STARS)
	if s.wanted > 0 and stars == 0 then
		stars = 1
	end
	local prev = s.stars
	s.stars = stars
	setAttr(player, C.Attr.Wanted, stars)
	setAttr(player, C.Attr.Chase, stars > 0)
	if stars > prev then
		s.seenT = os.clock()
		s.lastSeenPos = feetOf(player)
		if M.Police then
			M.Police.onWanted(player, stars, prev)
		end
	end
end

local function commit(player: Player, s: any, witnessed: boolean)
	if s.busy then
		return
	end
	local labels, seen = {}, {}
	local before = s.wanted
	local kinds = {}
	for k in s.pending do
		table.insert(kinds, k)
	end
	table.clear(s.pending)
	s.reportAt = nil
	table.sort(kinds)
	for _, kind in kinds do
		local def = C.CRIMES[kind]
		if def then
			s.wanted = math.clamp(math.max(s.wanted + def.add, def.min), 0, C.MAX_STARS)
			if not seen[def.label] then
				seen[def.label] = true
				table.insert(labels, def.label)
			end
			table.insert(s.crimeLog, def.label)
			if #s.crimeLog > 6 then
				table.remove(s.crimeLog, 1)
			end
		end
	end
	if #labels == 0 or s.wanted <= before and s.stars > 0 then
		if #labels > 0 then
			fire(player, { kind = "crime", label = table.concat(labels, " · "), stars = s.stars, witnessed = witnessed })
		end
		return
	end
	applyStars(player, s)
	fire(player, { kind = "crime", label = table.concat(labels, " · "), stars = s.stars, witnessed = witnessed })
end

-- the police learned about something this player did
function Interact.policeKnow(player: Player, _inc: any?, witnessed: boolean)
	local s = S(player)
	if next(s.pending) then
		commit(player, s, witnessed)
	end
end

-- kind = C.CRIMES key; pos = where; opts.ambient = number of client-side passers-by who saw it
function Interact.crime(player: Player, kind: string, pos: Vector3?, opts: any?)
	local s = S(player)
	local def = C.CRIMES[kind]
	if not def or s.busy then
		return
	end
	local at = pos or feetOf(player)
	s.pending[kind] = true
	s.pendingAt = at
	local copSees = M.Police and at and M.Police.copSees(at, player) or false
	if copSees or kind == "cop" or kind == "cop_ko" then
		commit(player, s, true)
		return
	end
	if def.onlyCop then
		s.pending[kind] = nil
		return
	end
	-- crimes on pedestrians / key NPCs: a passer-by calls it in (the city NPCs report on their own)
	local o = opts or {}
	if (o.ambient or 0) > 0 and not s.reportAt and rnd:NextNumber() < 0.8 then
		s.reportAt = os.clock() + range(C.REPORT_DELAY)
		s.reportInc = o.inc
		fire(player, { kind = "witness" })
	end
end

function Interact.clearWanted(player: Player, reason: string)
	local s = S(player)
	local had = s.stars > 0 or s.wanted > 0
	s.wanted = 0
	s.stars = 0
	s.reportAt = nil
	table.clear(s.pending)
	s.handsUp = false
	setAttr(player, C.Attr.Wanted, 0)
	setAttr(player, C.Attr.Chase, false)
	setAttr(player, C.Attr.Seen, false)
	if M.Police then
		M.Police.standDown(player, reason)
	end
	if had then
		fire(player, { kind = "cleared", reason = reason })
		if reason == "evaded" then
			notify(player, "success", "수배 해제 😎", "경찰을 따돌렸어요", { icon = "🚓" })
			fire(player, { kind = "radio", text = C.RADIO.lost })
		end
	end
end

---------------------------------------------------------------------------------------------------
-- money
---------------------------------------------------------------------------------------------------
local function balance(player: Player): (number, number)
	local d = Profiles.get(player)
	if not d then
		return 0, 0
	end
	return math.max(0, d.cash or 0), math.max(0, d.bank or 0)
end

-- pays up to `amount` (bank first, then cash); returns what was paid
local function payUpTo(player: Player, amount: number, label: string): number
	if amount <= 0 then
		return 0
	end
	if ctx.spend(player, amount, label, true, "bank") then
		return amount
	end
	local paid = 0
	local cash, bank = balance(player)
	local takeBank = math.min(amount, bank)
	if takeBank > 0 and ctx.ledger(player, "bank", -takeBank, label, true) then
		paid += takeBank
	end
	local takeCash = math.min(amount - paid, cash)
	if takeCash > 0 and ctx.ledger(player, "cash", -takeCash, label, true) then
		paid += takeCash
	end
	return paid
end
Interact.payUpTo = payUpTo

---------------------------------------------------------------------------------------------------
-- BUSTED / WASTED (both always end with the controls back: a timed task, plus onCharacter resets)
---------------------------------------------------------------------------------------------------
local function placeAt(player: Player, part: BasePart?, sitBed: boolean)
	if not part then
		return
	end
	pcall(ctx.allowTeleport, player, 10)
	pcall(ctx.jobsResetPosition, player)
	local ok = pcall(Util.teleportTo, player, part, 6)
	if ok and sitBed and part:IsA("Seat") then
		local _, hum = charOf(player)
		if hum then
			pcall(function()
				(part :: any):Sit(hum)
			end)
		end
	end
end

local function endShiftIf(player: Player)
	if ctx.onShift and ctx.onShift(player) then
		pcall(ctx.endShift, player)
	end
end

function Interact.arrest(player: Player, officer: any?)
	local s = S(player)
	if s.busy then
		return
	end
	s.busy = "busted"
	local stars = math.max(1, s.stars)
	local fine = C.FINES[stars] or C.FINES[#C.FINES]
	if s.handsUp then
		fine = math.floor(fine * 0.5)
	end
	local reasons = if #s.crimeLog > 0 then table.concat(s.crimeLog, ", ") else "범죄 혐의"
	table.clear(s.fighters)
	setAttr(player, C.Attr.Arrested, true)
	setAttr(player, C.Attr.Chase, false)
	freeze(player, true)
	endShiftIf(player)
	Interact.closeCard(player)
	fire(player, { kind = "busted", fine = fine, stars = stars, by = officer and officer.name, reasons = reasons, half = s.handsUp })
	if M.Police then
		M.Police.onArrest(player, officer)
	end
	task.spawn(function()
		task.wait(3.6)
		if player.Parent ~= Players then
			return
		end
		pcall(Util.fade, player, true, 0.8, "🚓 광안지구대로 연행 중…")
		local paid = payUpTo(player, fine, "벌금 · 광안지구대")
		pcall(ctx.addStats, player, { happiness = -6 }, nil, true)
		table.clear(s.crimeLog)
		Interact.clearWanted(player, "arrested")
		freeze(player, false)
		placeAt(player, ctx.dest(C.ARREST_PLACE), false)
		task.wait(0.6)
		pcall(Util.fade, player, false, 0.8)
		setAttr(player, C.Attr.Arrested, false)
		s.busy = nil
		s.hp = math.max(s.hp, 60)
		pushHP(player, s)
		local body = if paid >= fine then string.format("사유: %s · 벌금 %s 납부", reasons, C.won(fine)) else string.format("사유: %s · 벌금 %s 중 %s 납부 (잔액 부족으로 훈방)", reasons, C.won(fine), C.won(paid))
		notify(player, "warn", "광안지구대에서 풀려났어요 🚓", body, { icon = "🚓" })
		fire(player, { kind = "released", paid = paid, fine = fine, reasons = reasons })
	end)
end

knockout = function(player: Player, by: string?)
	local s = S(player)
	if s.busy then
		return
	end
	s.busy = "wasted"
	s.koSeq += 1
	s.hp = 0
	pushHP(player, s)
	table.clear(s.fighters)
	local ch = player.Character
	if ch then
		ch:SetAttribute(C.Attr.KO, true)
	end
	freeze(player, true)
	endShiftIf(player)
	Interact.closeCard(player)
	fire(player, { kind = "wasted", by = by, fee = C.HOSPITAL_FEE })
	if M.Police then
		M.Police.standDown(player, "wasted")
	end
	local seq = s.koSeq
	task.spawn(function()
		task.wait(4.4)
		if player.Parent ~= Players or s.koSeq ~= seq then
			return
		end
		pcall(Util.fade, player, true, 0.8, "🚑 광안메디컬로 이송 중…")
		local paid = payUpTo(player, C.HOSPITAL_FEE, "광안메디컬 응급 진료 (폭행 부상)")
		pcall(ctx.addStats, player, { stamina = -12, happiness = -6 }, nil, true)
		Interact.clearWanted(player, "hospital")
		local ch2 = player.Character
		if ch2 then
			ch2:SetAttribute(C.Attr.KO, nil)
		end
		freeze(player, false)
		local bed = nil
		pcall(function()
			bed = ctx.health and ctx.health.findBed and ctx.health.findBed("ward", nil)
		end)
		if bed then
			placeAt(player, bed, true)
		else
			placeAt(player, ctx.dest(G.HEALTH and G.HEALTH.place or "광안메디컬"), false)
		end
		task.wait(0.6)
		pcall(Util.fade, player, false, 0.8)
		s.hp = C.PLAYER_HP
		pushHP(player, s)
		s.busy = nil
		notify(player, "home", "광안메디컬에서 눈을 떴어요 🏥", string.format("%s · 응급 진료비 %s · 체력 -12", if by then by .. "에게 맞아 기절" else "기절", C.won(paid)), { icon = "🏥" })
		fire(player, { kind = "revived", paid = paid })
	end)
end
Interact.knockout = knockout

---------------------------------------------------------------------------------------------------
-- dialog cards (shared Dialog remote; 3 choices + bye; walking away closes it on the client)
---------------------------------------------------------------------------------------------------
function Interact.card(player: Player, npcId: string, card: any, text: string, choices: { any }, handler: (string) -> ())
	local s = S(player)
	local out = {}
	local ok = { close = true, bye = true }
	local STYLES = { "primary", "secondary", "tonal" }
	for i, ch in choices do
		if i > 3 then
			break
		end
		ok[ch.id] = true
		table.insert(out, { id = ch.id, label = ch.label, style = ch.style or STYLES[i] })
	end
	table.insert(out, { id = "bye", label = card.bye or "됐어요", style = "ghost" })
	if NPC and NPC.close then
		pcall(NPC.close, player)
	end
	s.dialog = { npcId = npcId, ok = ok, handler = handler, t = os.clock() }
	local col = card.color or { 120, 120, 140 }
	ctx.remotes.Dialog:FireClient(player, {
		npcId = npcId,
		name = card.name,
		role = card.role,
		portraitColor = Color3.fromRGB(col[1], col[2], col[3]),
		icon = card.icon,
		text = text,
		choices = out,
		emote = card.emote,
	})
end

function Interact.closeCard(player: Player, npcId: string?)
	local s = PS[player]
	if s and s.dialog and (npcId == nil or s.dialog.npcId == npcId) then
		local dlg = s.dialog
		s.dialog = nil
		pcall(function()
			ctx.remotes.Dialog:FireClient(player, { close = true })
		end)
		if npcId then
			pcall(dlg.handler, "close")
		end
	end
end

local function onDialogChoice(player: Player, payload: any)
	local s = PS[player]
	local dlg = s and s.dialog
	if not dlg or type(payload) ~= "table" or payload.npcId ~= dlg.npcId then
		return
	end
	local choice = payload.choiceId
	if type(choice) ~= "string" or not dlg.ok[choice] then
		return
	end
	s.dialog = nil
	local ok, err = pcall(dlg.handler, choice)
	if not ok then
		warn("[GwangalliInteract] dialog choice failed: " .. tostring(err))
	end
end

---------------------------------------------------------------------------------------------------
-- the carried-food slot (no item system exists yet: one item, bought from our clerk; Player
-- attribute GwCarryFood + a prop in the right hand)
---------------------------------------------------------------------------------------------------
function Interact.setCarry(player: Player, item: string?)
	player:SetAttribute("GwCarryFood", item)
	local ch = player.Character
	if not ch then
		return
	end
	local old = ch:FindFirstChild("GiCarryProp")
	if old then
		old:Destroy()
	end
	if not item then
		return
	end
	local hand = ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		local p = Instance.new("Part")
		p.Name = "GiCarryProp"
		p.Size = Vector3.new(0.7, 0.55, 0.3)
		p.Color = Color3.fromRGB(245, 245, 240)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = hand.CFrame * CFrame.new(0, -0.5, -0.2)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = p
		w.Parent = p
		p.Parent = ch
	end
end

---------------------------------------------------------------------------------------------------
-- targets
---------------------------------------------------------------------------------------------------
local PED_TYPES = { plain = true, violent = true, drunk = true, fool = true, beggar = true }

local function citizenName(id: string): string?
	local c = Citizens and Citizens.byId and Citizens.byId[id]
	if c then
		return c.name
	end
	local n = G and G.NPCS and G.NPCS[id]
	return n and n.name or nil
end

local function resolveTarget(player: Player, payload: any): any?
	if type(payload) ~= "table" then
		return nil
	end
	local kind = payload.target
	local id = Util.str(payload.id, 48)
	if not id or id == "" then
		return nil
	end
	if kind == "ped" then
		local c = Citizens and Citizens.byId and Citizens.byId[id]
		if not c and not string.match(id, "^x%d+$") then
			return nil
		end
		if c and Citizens.KEY_IDS and table.find(Citizens.KEY_IDS, id) then
			return nil
		end
		local pos = C.unpackV(payload.pos)
		if not pos then
			return nil
		end
		local t = (c and c.type) or (if type(payload.ptype) == "string" and PED_TYPES[payload.ptype] then payload.ptype else "plain")
		if not PED_TYPES[t] then
			t = "plain"
		end
		return { kind = "ped", id = id, key = "x:" .. id, pos = pos, type = t, name = (c and c.name) or "행인" }
	elseif kind == "npc" then
		if not NPC or not NPC.state then
			return nil
		end
		local okS, st = pcall(NPC.state, id)
		if not okS or type(st) ~= "table" or st.hidden or typeof(st.pos) ~= "Vector3" then
			return nil
		end
		return { kind = "npc", id = id, key = "k:" .. id, pos = st.pos, type = "key", name = citizenName(id) or "시민", model = st.model }
	elseif kind == "actor" then
		local n = M.Mind and M.Mind.get(id)
		if not n or not n.present or not n.a or n.a.gone then
			return nil
		end
		return { kind = "actor", id = id, key = "n:" .. id, pos = M.Actors.pos(n.a), type = n.arch, name = n.name, n = n }
	end
	return nil
end
Interact.resolveTarget = resolveTarget

local function playerSay(player: Player, text: string)
	fireAll({ kind = "say", target = "player", id = tostring(player.UserId), text = text, dur = 2.4 })
end
Interact.playerSay = playerSay

local function hpOf(s: any, tgt: any): any
	local tbl = if tgt.kind == "npc" then s.keyHp else s.pedHp
	local e = tbl[tgt.id]
	local now = os.clock()
	if not e or now - e.t > 90 then
		local max = C.typeOf(tgt.type).hp
		e = { hp = max, max = max, t = now }
		tbl[tgt.id] = e
	end
	e.t = now
	return e
end

local function awardSocial(player: Player, tgt: any, source: string, amount: number?)
	local social = ctx.social
	if tgt.kind ~= "actor" and social and social.award and Citizens and Citizens.byId and Citizens.byId[tgt.id] then
		pcall(social.award, player, tgt.id, source, amount)
	end
end

local function rollReact(tgt: any, verb: string, s: any): string
	local T = C.typeOf(tgt.type)
	if tgt.kind == "npc" then
		return "upset"
	end
	if tgt.type == "fool" then
		return if verb == "provoke" or verb == "tease" then "laugh" else "flee"
	elseif tgt.type == "beggar" then
		return if verb == "provoke" or verb == "tease" then "sad" else "cower"
	end
	local f = s.fighters[tgt.key]
	if f and os.clock() < f.untilT then
		return "fight"
	end
	local fight = T.fight
	if verb == "provoke" or verb == "tease" then
		fight = if tgt.type == "violent" then 0.75 else fight * 0.7
	elseif verb == "shove" then
		fight = math.min(1, fight * 1.25)
	end
	local r = rnd:NextNumber()
	if r < fight then
		return "fight"
	end
	if verb == "provoke" or verb == "tease" then
		return "provoked"
	end
	if r < fight + T.flee then
		return "flee"
	end
	return "cower"
end

local function startFight(s: any, tgt: any)
	s.fighters[tgt.key] = { untilT = os.clock() + C.NPC_FIGHT.timeout, lastHit = -1e9, t = tgt.type }
end

local function punchDamage(player: Player, s: any): (number, boolean)
	local hook = s.combo % 3 == 0
	local dmg = (C.PUNCH_DMG + s.strength * 0.12) * (0.88 + rnd:NextNumber() * 0.24)
	if hook then
		dmg *= 1.6
	end
	return math.floor(dmg + 0.5), hook
end

local function dirTo(player: Player, pos: Vector3): (number, number)
	local f = feetOf(player)
	if not f then
		return 0, -1
	end
	local d = Vector3.new(pos.X - f.X, 0, pos.Z - f.Z)
	if d.Magnitude < 1e-3 then
		return 0, -1
	end
	d = d.Unit
	return d.X, d.Z
end

-- a street pedestrian / key NPC was hit: also a real incident for the city NPCs who see it
local function hitTarget(player: Player, s: any, tgt: any, verb: string, ambient: number)
	local dx, dz = dirTo(player, tgt.pos)
	local dmg, hook = 0, false
	if verb == "punch" then
		dmg, hook = punchDamage(player, s)
	else
		dmg = 3
	end
	local e = hpOf(s, tgt)
	e.hp = math.max(0, e.hp - dmg)
	local outcome = "stagger"
	if e.hp <= 0 then
		outcome = "ko"
	elseif verb == "punch" and (hook or dmg >= 24) then
		outcome = "knockdown"
	end
	local react = rollReact(tgt, verb, s)
	if outcome == "ko" then
		react = "ko"
		s.fighters[tgt.key] = nil
		e.hp = math.floor(e.max * 0.5)
	elseif react == "fight" then
		startFight(s, tgt)
	end
	local line = nil
	if outcome ~= "ko" then
		line = if react == "fight" then C.typeLine(tgt.type, "fight") elseif verb == "shove" then C.typeLine(tgt.type, "shoved") else C.typeLine(tgt.type, "hurt")
	end
	if tgt.kind == "npc" and NPC and NPC.knock then
		pcall(NPC.knock, tgt.id, dx, dz, if outcome == "stagger" then "stagger" else "knockdown", player)
		fireAll({ kind = "say", target = "npc", id = tgt.id, text = C.line("key_hurt"), dur = 2.5, typeId = "plain" })
	end
	fire(player, { kind = "hit", target = tgt.kind, id = tgt.id, verb = verb, dmg = dmg, hp = e.hp, max = e.max, outcome = outcome, dx = dx, dz = dz, react = react, line = line, crit = hook, ko = outcome == "ko" })
	awardSocial(player, tgt, "rude", if verb == "punch" then -8 else -4)
	local key = "p:" .. player.UserId
	local inc = M.World.incident(if outcome == "ko" then "ko" elseif verb == "punch" then "assault" else "shove", tgt.pos, { aggressor = key, victim = tgt.key })
	local amb = ambient + (if tgt.kind == "npc" then 2 else 0)
	if verb == "punch" then
		Interact.crime(player, "assault", tgt.pos, { ambient = amb, inc = inc })
		if tgt.type == "beggar" or tgt.type == "fool" then
			Interact.crime(player, "weak", tgt.pos, { ambient = amb, inc = inc })
		end
		if outcome == "ko" then
			Interact.crime(player, "ko", tgt.pos, { ambient = amb, inc = inc })
		end
	else
		Interact.crime(player, "shove", tgt.pos, { ambient = amb, inc = inc })
	end
end

-- the other verbs on pedestrians (client-side people: lines by type) and key NPCs (NPC.luau owns them)
local function softVerb(player: Player, s: any, tgt: any, verb: string)
	local key = "p:" .. player.UserId
	local f = s.fighters[tgt.key]
	local fighting = f and os.clock() < f.untilT
	if tgt.kind == "npc" then
		if verb == "talk" or verb == "greet" or verb == "ask" then
			local model = tgt.model
			if model and model:GetAttribute("NpcKind") == "street" and ctx.social and ctx.social.openDialog then
				pcall(ctx.social.openDialog, player, tgt.id, tgt.pos + Vector3.new(0, 3, 0), false)
				if NPC.engage then
					pcall(NPC.engage, tgt.id, player, 45)
				end
			elseif NPC.open then
				pcall(NPC.open, player, tgt.id, false)
			end
		elseif verb == "give" or verb == "food" then
			if verb == "give" and not ctx.ledger(player, "cash", -C.GIVE_AMOUNT, tgt.name .. "에게 " .. C.won(C.GIVE_AMOUNT), false) then
				return
			end
			if verb == "food" then
				if not player:GetAttribute("GwCarryFood") then
					fire(player, { kind = "miss", reason = "nofood" })
					return
				end
				Interact.setCarry(player, nil)
			end
			pcall(NPC.react, tgt.id, "bow")
			fireAll({ kind = "say", target = "npc", id = tgt.id, text = C.line("plain_given"), dur = 3, typeId = "plain" })
		elseif verb == "rob" then
			fireAll({ kind = "say", target = "npc", id = tgt.id, text = C.line("plain_rob_fail"), dur = 3, typeId = "plain" })
			M.World.incident("threat", tgt.pos, { aggressor = key, victim = tgt.key })
			Interact.crime(player, "rob_try", tgt.pos, { ambient = 2 })
		else
			pcall(NPC.react, tgt.id, if verb == "tease" or verb == "provoke" then "shake" else "nod")
			local lines = { joke = "plain_given", tease = "plain_provoked", provoke = "plain_provoked", apologize = "plain_calm", help = "plain_talk", report = "plain_talk", flee = "plain_calm" }
			fireAll({ kind = "say", target = "npc", id = tgt.id, text = C.line(lines[verb] or "plain_talk"), dur = 3, typeId = "plain" })
		end
		return
	end
	-- street pedestrians
	local react, line = "talk", nil
	if verb == "greet" or verb == "talk" then
		if Citizens.byId[tgt.id] and ctx.social and ctx.social.openDialog and verb == "talk" then
			if pcall(ctx.social.openDialog, player, tgt.id, tgt.pos + Vector3.new(0, 3, 0), false) then
				fire(player, { kind = "pedReact", id = tgt.id, react = "talk" })
				return
			end
		end
		playerSay(player, C.line("player_talk"))
		line = if fighting then C.typeLine(tgt.type, "fight") else C.typeLine(tgt.type, "talk")
		react = if fighting then "fight" else "talk"
	elseif verb == "ask" then
		line = if rnd:NextNumber() < 0.5 then "GS25요? 저 위쪽 골목으로 쭉 가세요." else "지구대는 광남로 쪽이에요~"
		pcall(ctx.setWaypoint, player, if string.find(line, "GS25") then "GS25 광안리점" else "광안지구대")
	elseif verb == "joke" then
		line = if rnd:NextNumber() < 0.5 then "ㅋㅋㅋ 뭐예요 그게" else "…네?"
		react = if fighting then "fight" else "laugh"
	elseif verb == "tease" or verb == "provoke" then
		playerSay(player, C.line("player_provoke"))
		react = rollReact(tgt, verb, s)
		if react == "fight" then
			startFight(s, tgt)
		end
		line = if react == "fight" then C.typeLine(tgt.type, "fight") elseif react == "laugh" then C.line("fool_provoked") elseif react == "sad" then C.line("beggar_provoked") else C.typeLine(tgt.type, "provoked")
		awardSocial(player, tgt, "rude", -3)
	elseif verb == "apologize" then
		playerSay(player, C.line("player_sorry"))
		if fighting then
			local p = ({ plain = 0.8, violent = 0.35, drunk = 0.6 })[tgt.type] or 0.7
			if rnd:NextNumber() < p then
				s.fighters[tgt.key] = nil
				react, line = "calm", C.typeLine(tgt.type, "calm")
			else
				f.untilT = os.clock() + C.NPC_FIGHT.timeout
				react, line = "fight", C.typeLine(tgt.type, "stay_mad")
			end
		else
			line = C.typeLine(tgt.type, "calm")
		end
	elseif verb == "give" or verb == "food" then
		if verb == "give" then
			if not ctx.ledger(player, "cash", -C.GIVE_AMOUNT, tgt.name .. "에게 " .. C.won(C.GIVE_AMOUNT), false) then
				fire(player, { kind = "miss", reason = "nocash" })
				notify(player, "info", "현금이 없어요", "ATM에서 현금을 뽑아 주세요", { icon = "💸" })
				return
			end
		else
			if not player:GetAttribute("GwCarryFood") then
				fire(player, { kind = "miss", reason = "nofood" })
				return
			end
			Interact.setCarry(player, nil)
		end
		playerSay(player, C.line("player_give"))
		if fighting and (tgt.type ~= "violent" or rnd:NextNumber() < 0.5) then
			s.fighters[tgt.key] = nil
		end
		pcall(ctx.addStats, player, { happiness = if tgt.type == "beggar" then 2 else 1 }, nil, true)
		awardSocial(player, tgt, "give", if tgt.type == "beggar" then 4 else 2)
		line = if tgt.type == "beggar" then C.line("beggar_thanks") elseif tgt.type == "fool" then C.line("fool_given") else C.typeLine(tgt.type, "given")
		react = if s.fighters[tgt.key] then "fight" else "given"
	elseif verb == "help" then
		if s.hp < 55 then
			Interact.heal(player, 10)
			line = "괜찮으세요? 물 좀 드세요."
		else
			line = if rnd:NextNumber() < 0.5 then "네? 무슨 도움이요?" else "저도 바빠서요…"
		end
	elseif verb == "report" then
		local inc = M.World.playerKnown(player, 180)
		if inc and M.Police then
			line = "알겠어요, 제가 112에 신고할게요!"
			task.delay(2.5, function()
				M.Police.report(inc, { by = tgt.key, pos = inc.pos, name = "행인" })
			end)
		else
			line = "무슨 일인데요?"
		end
	elseif verb == "flee" then
		playerSay(player, "튀어!")
		line = if fighting then "어딜 도망가!" else nil
	elseif verb == "rob" then
		playerSay(player, C.line("player_rob"))
		local T = C.typeOf(tgt.type)
		local chance = T.rob * (0.8 + s.strength / 250) * (if fighting then 0.5 else 1)
		if rnd:NextNumber() < chance then
			local won = math.floor(range(T.robWon) / 100 + 0.5) * 100
			if won > 0 then
				ctx.ledger(player, "cash", won, "삥 뜯기 (" .. tgt.name .. ")", false)
			end
			pcall(ctx.addStats, player, { happiness = -2 }, nil, true)
			awardSocial(player, tgt, "rude", -10)
			line = if tgt.type == "beggar" then C.line("beggar_robbed") elseif tgt.type == "fool" then C.line("fool_robbed") else C.typeLine(tgt.type, "robbed")
			fire(player, { kind = "pedReact", id = tgt.id, react = "robbed", line = line, won = won })
			local inc = M.World.incident("robbery", tgt.pos, { aggressor = key, victim = tgt.key })
			Interact.crime(player, "robbery", tgt.pos, { ambient = s.ambient or 1, inc = inc })
			if tgt.type == "beggar" or tgt.type == "fool" then
				Interact.crime(player, "weak", tgt.pos, { ambient = s.ambient or 1, inc = inc })
			end
			return
		end
		react = if tgt.type == "violent" or tgt.type == "drunk" or rnd:NextNumber() < 0.3 then "fight" else "flee"
		if react == "fight" then
			startFight(s, tgt)
		end
		line = C.typeLine(tgt.type, "rob_fail")
		local inc = M.World.incident("threat", tgt.pos, { aggressor = key, victim = tgt.key })
		Interact.crime(player, "rob_try", tgt.pos, { ambient = s.ambient or 1, inc = inc })
	end
	fire(player, { kind = "pedReact", id = tgt.id, react = react, line = line })
end

local PHYSICAL = { punch = true, shove = true, rob = true, give = true, food = true }

local function onAct(player: Player, payload: any)
	local verb = payload and payload.verb
	if type(verb) ~= "string" or not C.VERB[verb] then
		return
	end
	local s = S(player)
	if not canAct(player) then
		fire(player, { kind = "miss", reason = "busy" })
		return
	end
	local tgt = resolveTarget(player, payload)
	if not tgt then
		fire(player, { kind = "miss", reason = "target" })
		return
	end
	local me = feetOf(player)
	if not me then
		return
	end
	local reach = if PHYSICAL[verb] then C.REACH + C.REACH_SLACK else C.PICK_RANGE + C.REACH_SLACK
	if flatDist(me, tgt.pos) > reach or math.abs(me.Y - tgt.pos.Y) > 8 then
		fire(player, { kind = "miss", reason = "far" })
		return
	end
	s.ambient = math.clamp(tonumber(payload.peds) or 0, 0, 30)
	s.strength = strengthOf(player)
	local now = os.clock()
	if verb == "punch" or verb == "shove" then
		if now - s.lastPunch < 0.26 then
			return
		end
		if facing(player, tgt.pos) < C.FACING and flatDist(me, tgt.pos) > 2.5 then
			fire(player, { kind = "miss", reason = "facing" })
			return
		end
		s.combo = if now - s.lastPunch < C.COMBO_WINDOW then s.combo + 1 else 1
		s.lastPunch = now
		s.handsUp = false
	elseif not Util.cooldown(player, "interact:" .. verb, if verb == "greet" or verb == "talk" then 0.7 else 1.0) then
		return
	end
	if tgt.kind == "actor" then
		-- a city NPC: Verbs decides from the person, the relationship and the situation
		local ok, err = pcall(M.Verbs.act, player, tgt.n, if verb == "provoke" then "tease" else verb, s)
		if not ok then
			warn("[GwangalliInteract] verb " .. verb .. " on " .. tgt.id .. ": " .. tostring(err))
		end
		return
	end
	if verb == "punch" or verb == "shove" then
		hitTarget(player, s, tgt, verb, s.ambient)
	else
		softVerb(player, s, tgt, verb)
	end
end

-- punch / shove on a city NPC: damage numbers + the hit event (Verbs / Mind do the rest)
function Interact.hitActor(player: Player, s: any, a: any, verb: string): (number, string, boolean, number, number)
	local dmg, hook = 3, false
	if verb == "punch" then
		dmg, hook = punchDamage(player, s)
	end
	local hpNow = math.max(0, (a.hp or a.max or 60) - dmg)
	local outcome = "stagger"
	if hpNow <= 0 then
		outcome = "ko"
	elseif verb == "punch" and (hook or dmg >= 24) then
		outcome = "knockdown"
	end
	local pos = M.Actors.pos(a)
	local dx, dz = dirTo(player, pos)
	fire(player, { kind = "hit", target = "actor", id = a.id, verb = verb, dmg = dmg, hp = hpNow, max = a.max, outcome = outcome, dx = dx, dz = dz, crit = hook, ko = outcome == "ko" })
	return dmg, outcome, hook, dx, dz
end

local function onPedHit(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local s = S(player)
	local id = Util.str(payload.id, 48)
	if not id then
		return
	end
	local f = s.fighters["x:" .. id]
	local now = os.clock()
	if not f or now > f.untilT or s.busy then
		return
	end
	if now - f.lastHit < 0.75 then
		return
	end
	local pos = C.unpackV(payload.pos)
	local me = feetOf(player)
	if not pos or not me or flatDist(pos, me) > C.NPC_FIGHT.reach + 2.5 or math.abs(pos.Y - me.Y) > 8 then
		return
	end
	f.lastHit = now
	f.hits = (f.hits or 0) + 1
	local T = C.typeOf(f.t)
	local dmg = math.floor(range(T.dmg) + 0.5)
	local d = Vector3.new(me.X - pos.X, 0, me.Z - pos.Z)
	local dx, dz = 0, 0
	if d.Magnitude > 1e-3 then
		d = d.Unit
		dx, dz = d.X, d.Z
	end
	local outcome = if f.hits % C.NPC_FIGHT.knock_every == 0 then "knockdown" else "stagger"
	Interact.hurtPlayer(player, dmg, { by = citizenName(id) or "행인", dx = dx, dz = dz, outcome = outcome, ped = id })
	M.World.incident("fight", pos, { aggressor = "x:" .. id, victim = "p:" .. player.UserId })
end

local function onAction(player: Player, kind: any, payload: any)
	if type(kind) ~= "string" then
		return
	end
	if not Profiles.get(player) then
		return
	end
	local ok, err = pcall(function()
		if kind == "act" then
			onAct(player, payload)
		elseif kind == "air" then
			local s = S(player)
			local now = os.clock()
			if canAct(player) and now - s.lastPunch >= 0.26 then
				s.combo = if now - s.lastPunch < C.COMBO_WINDOW then s.combo + 1 else 1
				s.lastPunch = now
				s.handsUp = false
			end
		elseif kind == "pedHit" then
			onPedHit(player, payload)
		elseif kind == "surrender" then
			local s = S(player)
			if s.stars > 0 and not s.busy then
				s.handsUp = true
				playerSay(player, C.line("player_surrender"))
				if M.Police then
					M.Police.onSurrender(player, s)
				end
			end
		elseif kind == "fightOver" then
			local id = type(payload) == "table" and Util.str(payload.id, 48)
			if id then
				S(player).fighters["x:" .. id] = nil
			end
		elseif kind == "call112" then
			-- the player phones the police about something they saw
			local inc = M.World.playerKnown(player, 180)
			if inc and M.Police and Util.cooldown(player, "interact:call112", 20) then
				playerSay(player, "여보세요, 112죠? 여기 " .. M.World.placeName(inc.pos) .. "에서 " .. (inc.label or "사건") .. "이요!")
				M.Police.report(inc, { by = "p:" .. player.UserId, pos = inc.pos, suspectPos = M.World.posOf(inc.aggressor), name = player.DisplayName })
				fire(player, { kind = "radio", text = "📻 [무전] 시민 신고 접수 — 순찰 경찰이 " .. M.World.placeName(inc.pos) .. "(으)로 갑니다." })
			elseif not inc then
				fire(player, { kind = "miss", reason = "noincident" })
			end
		end
	end)
	if not ok then
		warn("[GwangalliInteract] action " .. kind .. " failed: " .. tostring(err))
	end
end

---------------------------------------------------------------------------------------------------
-- tick (4 Hz): passer-by reports, the wanted level's evasion, HP regen, fights timing out
---------------------------------------------------------------------------------------------------
local function tick()
	local now = os.clock()
	for player, s in PS do
		if player.Parent ~= Players then
			PS[player] = nil
			continue
		end
		if s.reportAt and now >= s.reportAt then
			s.reportAt = nil
			if next(s.pending) then
				local inc = s.reportInc
				if inc and M.Police then
					M.Police.report(inc, { by = "x:passerby", pos = inc.pos, suspectPos = s.pendingAt, name = "행인" })
				end
				commit(player, s, false)
			end
		end
		if s.stars > 0 and not s.busy then
			local pos = feetOf(player)
			local seen, near = false, false
			if M.Police and pos then
				seen, near = M.Police.sight(player, pos)
			end
			if seen then
				s.seenT = now
				s.lastSeenPos = pos
			end
			setAttr(player, C.Attr.Seen, seen)
			local need = C.EVADE[s.stars] or 30
			if now - s.seenT > need and not near then
				Interact.clearWanted(player, "evaded")
			end
		end
		if not s.busy and s.hp < C.PLAYER_HP and now - s.lastHurt > C.REGEN_DELAY then
			s.hp = math.min(C.PLAYER_HP, s.hp + C.REGEN_RATE * 0.25)
			pushHP(player, s)
		end
		for key, f in s.fighters do
			if now > f.untilT then
				s.fighters[key] = nil
			end
		end
		if s.dialog and now - s.dialog.t > 90 then
			s.dialog = nil
		end
	end
	if M.World then
		M.World.tick()
	end
end

---------------------------------------------------------------------------------------------------
-- feature hooks
---------------------------------------------------------------------------------------------------
function Interact.onLoaded(player: Player)
	local s = S(player)
	pushHP(player, s)
	setAttr(player, C.Attr.Wanted, 0)
	setAttr(player, C.Attr.Chase, false)
	setAttr(player, C.Attr.Arrested, false)
	if M.Memory then
		M.Memory.onLoaded(player)
	end
end

function Interact.onCharacter(player: Player, character: Model)
	local s = S(player)
	-- a fresh body: never stuck knocked out / frozen / cuffed
	s.frozen = nil
	if s.busy == "wasted" then
		s.busy = nil
		s.koSeq += 1
		s.hp = C.PLAYER_HP
		Interact.clearWanted(player, "hospital")
	end
	character:SetAttribute(C.Attr.KO, nil)
	player:SetAttribute("GwCarryFood", nil)
	pushHP(player, s)
end

function Interact.onLeave(player: Player)
	for _, name in { "Police", "Mind", "Memory" } do
		local m = M[name]
		if m and m.onLeave then
			pcall(m.onLeave, player)
		end
	end
	PS[player] = nil
end

local function requireShared(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 20)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliInteract] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local function child(name: string): any
	local m = script:FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliInteract] missing child module " .. name)
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliInteract] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

function Interact.init(context: any)
	ctx = context
	G = ctx.G
	Util = ctx.Util
	Profiles = ctx.Profiles
	C = requireShared("GwangalliStreetCombatShared")
	Citizens = requireShared("GwangalliCitizens")
	if not C or not Citizens then
		warn("[GwangalliInteract] shared modules missing; city NPCs disabled")
		return
	end
	local npcModule = script.Parent and script.Parent:FindFirstChild("NPC")
	if npcModule and npcModule:IsA("ModuleScript") then
		local ok, res = pcall(require, npcModule)
		if ok and type(res) == "table" then
			NPC = res
		end
	end
	Interact.C = C
	Interact.ctx = ctx
	Interact.NPC = NPC
	Interact.Citizens = Citizens
	-- remotes
	local rf = ReplicatedStorage:FindFirstChild(C.Folder)
	if rf and not rf:IsA("Folder") then
		rf:Destroy()
		rf = nil
	end
	local fresh = rf == nil
	if not rf then
		rf = Instance.new("Folder")
		rf.Name = C.Folder
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
	remotes.Action = remote(C.Remote.Action)
	remotes.Event = remote(C.Remote.Event)
	if fresh then
		(rf :: Instance).Parent = ReplicatedStorage
	end
	(remotes.Action :: RemoteEvent).OnServerEvent:Connect(onAction)
	local phoneAction = ctx.remotes and ctx.remotes.PhoneAction
	if phoneAction then
		phoneAction.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
			if action == "dialogChoice" and PS[player] and PS[player].dialog then
				onDialogChoice(player, payload)
			end
		end)
	end
	-- the city: every child first (they reach each other through Interact), then init in order
	for _, name in { "Actors", "Cast", "Talk", "Memory", "World", "Places", "Mind", "Routine", "Verbs", "Police", "Hazard" } do
		M[name] = child(name)
		Interact[name] = M[name]
	end
	if not (M.Actors and M.Cast and M.Talk and M.Memory and M.World and M.Places and M.Mind and M.Routine and M.Verbs) then
		warn("[GwangalliInteract] city modules missing; city NPCs disabled")
		return
	end
	local order = { "Actors", "Talk", "Memory", "World", "Places", "Mind", "Routine", "Verbs", "Police", "Hazard" }
	for _, name in order do
		local m = M[name]
		if m and m.init then
			local ok, err = pcall(m.init, Interact)
			if not ok then
				warn("[GwangalliInteract] " .. name .. " init failed: " .. tostring(err))
				if name == "Police" or name == "Hazard" then
					M[name] = nil
					Interact[name] = nil
				end
			end
		end
	end
	for _, player in Players:GetPlayers() do
		S(player)
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliInteract] tick failed: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(M.Mind.loop)
			if not ok then
				warn("[GwangalliInteract] city loop failed: " .. tostring(err))
			end
		end
	end)
	ctx.streetInteract = Interact
	print(string.format("[GwangalliInteract] ready: %d city NPCs (성격·기분·기억·인식·사건·갈등·경찰·가게) + street pedestrians + key NPCs", #M.Cast.LIST))
end

return Interact
