-- GwangalliGameplay/Relationships: 호감도 / 친구 system (server; owner: npc_social).
--   * affinity 0..100 per NPC per player (tiers 모르는 사이 20 아는 사이 50 친한 사이 75 친구 95 절친),
--     math + caps + cooldowns in ReplicatedStorage.GwangalliSocialShared, the roster (names, schedules,
--     likes, lines) in ReplicatedStorage.GwangalliCitizens
--   * many ways up: daily chat, replies the persona likes, compliments, gifts (paid through the ledger), errands,
--     visiting their workplace, invitations (beach / cafe / meal / 코노 / 볼링 / 클럽 / 우리 집), keeping
--     promises, hanging out (friend companion), dancing / a drink / a VIP table at the club,
--     housewarming, birthdays; ways down: rude replies, disliked gifts / topics, broken promises,
--     spamming. Diminishing returns + game-day and real-day caps make farming pointless.
--   * ask for their number (아는 사이: a chance, 친한 사이+: yes; automatic at 친한 사이) -> a phone contact
--     (snapshot.contacts with where they are right now); contacts text you (acquaintances: evening club
--     lures; friends: club invitations in the evening, beach / meals by day, asking for help),
--     can be called over, follow you as a COMPANION (server state; the client moves them) and give
--     perks (workplace discounts, club entry help, VIP discount, job / house tips); 절친 unlocks a
--     secret-spot event. NPCs remember you (name, where / when you last met, what you did).
--
-- START: Relationships.init(ctx) (idempotent) — call it from the gameplay bootstrap after the other
--   modules (or from NPC.init). It listens to Players itself and waits for each profile.
-- PERSISTENCE: the state lives in the profile table as d.social. When Profiles.sanitize keeps a `social`
--   key (probed at start: one line in Profiles.sanitize, `d.social = raw.social` when it is a table),
--   Profiles saves it atomically with the rest; until then it is kept in the DataStore
--   "GwangalliSocial_v1" (key u_<UserId>, per-NPC merge by last change, so a quick server hop cannot
--   lose progress). After the switch the fallback copy is read once (a profile without `social` yet)
--   and merged, so nothing saved before is lost (migration-safe).
-- REMOTES: Folder ReplicatedStorage.GwangalliSocial { SocialAction, SocialState, GetSocial } — contract in
--   GwangalliSocialShared. Roaming citizens talk through the existing Dialog remote (npcId = citizen
--   id, extra fields citizen = true, affinity, tier, tierName, emote = greet | think | refuse | dance |
--   cheer | shy | phone, also on SocialState "line"); their choices come back as the
--   PhoneAction "dialogChoice" the Dialog overlay already sends (handled here for roster ids that are
--   not G.NPCS).
-- SERVER API: BindableFunction ServerStorage.GwangalliSocialAPI:Invoke(method, player, ...):
--   "affinity" (id) -> a, tier          "tier" (id) -> tier, tierName      "isFriend" (id) -> bool
--   "friends" (minTier?) -> { {id, name, a, tier} }                         "companion" () -> id?, info
--   "award" (id, source, amount?) -> delta, a, tier   (source: GwangalliSocialShared.SOURCES key)
--   "joint" (activity, ids?) -> { [id] = delta }  award an activity (club / dance / drink / table /
--        home / housewarming / karaoke / bowling / meal / beach / cafe / job / api) to the companion
--        and/or up to 6 listed ids (club, homes and NPC code use this)
--   "perk" (kind, arg?) -> "discount" (Destination name | npc id | job id) -> 0 / 0.1 / 0.2,
--        "clubEntry" -> bool, "vipDiscount" -> 0 / 0.1 / 0.2, "tip" (npc id) -> string?
--   "onTalk" (id, remote?) -> greeting line, info   (key-NPC dialogs: memory-aware greeting + the
--        daily greet / workplace visit bookkeeping)
--   "greeting" (id) -> line   "smallTalk" (id) -> line
--   "menuChoice" (id) -> {id = "soc:menu", label} | nil
--   "choices" (id, remote?) -> { {id = "soc:...", label} }
--   "handleChoice" (id, choiceId, remote?) -> { handled, line?, node? = {text, choices}, close? }
--        key-NPC dialogs: add menuChoice to the root, forward every "soc:" choice here, send `node`
--        with your own dialog sender when present (it contains a "back" choice), else reopen your root
--        with `line` as the prefix. Phone calls: let "soc:" choices through the phone filter.
--   "snapshot" () -> the SocialState snapshot      "openDialog" (id, pos?, remote?)
--   The same functions are on the module table (Relationships.award(player, ...), ...) and on
--   ctx.social after init.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Relationships = {}

local started = false
local G: any
local Util: any
local Profiles: any
local ctx: any
local Social: any
local Citizens: any

local remotes: { Action: RemoteEvent?, State: RemoteEvent?, Get: RemoteFunction? } = {}
local profileHoldsSocial = false
local store: DataStore? = nil
local storeEnabled = false

local TALK_REACH = 28 -- studs between the player and a reported citizen position
local KEY_SLACK = 12 -- extra reach around a key NPC's server position
local DIALOG_REACH = 32 -- a face-to-face citizen conversation ends beyond this
local ARRIVE = 75 -- studs from a Destination part that count as "arrived"
local MEET_GAP = 1800 -- 30 real minutes apart = a new meeting
local DRINK_PRICE = 15000
local SOFT_DRINK_PRICE = 6000
local AUTOSAVE = 150
local CLUB_ZONE_TAG = "ClubZone" -- ClubShared.Tags.Zone
local COMPANION_OK_KEYS = { minji = true, junho = true } -- key NPCs who may leave their post with you
local CLUB_PEOPLE = { club_md = true, club_guard = true, promoter_ray = true, promoter_nana = true, bartender_rio = true, staff_yuri = true, jay = true }

type Sess = {
	state: any,
	ready: boolean,
	noSave: boolean,
	dirty: boolean,
	comp: any?,
	dlg: any?,
	q: any?,
	pendingErrand: any?,
	giftPage: number,
	seen: { [string]: any },
	talks: { [string]: any },
	inviteCd: { [string]: number },
	danceCd: { [string]: number },
	errandPos: { [string]: Vector3 },
	lastTextFrom: { [string]: number },
	active: { [string]: boolean },
	tokens: number,
	tokT: number,
	nextText: number,
	clubGuestUntil: number,
	jointT: number,
}
local sessions: { [Player]: Sess } = {}

-------------------------------------------------------------------------------------------------
-- Server-side lines (p polite / c casual)
-------------------------------------------------------------------------------------------------
local LINES = {
	again = { p = { "또 무슨 얘기 할까요? ㅎㅎ", "그리고요?" }, c = { "또 뭐 할까? ㅎㅎ", "그래서 그래서?" } },
	accept = { p = { "좋아요! 가요 😊", "오, 좋아요! 같이 가요!" }, c = { "좋아! 가자 😆", "콜! 바로 가자!" } },
	acceptLater = { p = { "좋아요! 그럼 이따 {place}에서 봐요!", "약속해요! {place}에서 만나요 🤙" }, c = { "좋아! 이따 {place}에서 보자!", "약속! {place}에서 만나 🤙" } },
	declineStranger = { p = { "에? 우리 아직 그런 사이는 아닌 것 같은데요 ㅎㅎ", "음… 조금 더 친해지면요!" }, c = { "에이, 아직 그런 사이는 아니잖아 ㅋㅋ" } },
	declineWork = { p = { "지금 일하는 중이라서요… 끝나고 연락할게요!" }, c = { "나 지금 일하는 중이야 ㅠ 끝나고 연락할게!" } },
	declineMinor = { p = { "저 아직 미성년자예요 ㅋㅋ 클럽은 못 가요!" }, c = { "나 아직 미성년자잖아 ㅋㅋ 클럽은 무리!" } },
	declineHome = { p = { "집은 좀… 조금 더 친해지면 갈게요!" }, c = { "너네 집? 음… 좀 더 친해지면 ㅎㅎ" } },
	declineNoHome = { p = { "어, 집이 아직 없으신 것 같은데요? ㅎㅎ" }, c = { "너 아직 집 없잖아 ㅋㅋ 부동산부터 가 봐!" } },
	decline = { p = { "오늘은 좀 피곤해서요… 다음에 가요!", "아쉽지만 오늘은 선약이 있어요 🙏" }, c = { "오늘은 좀 피곤해… 다음에 가자!", "아 오늘 선약 있어 ㅠ 다음에!" } },
	askedAlready = { p = { "아까 물어보셨잖아요 ㅎㅎ 다음에요!" }, c = { "아까 물어봤잖아 ㅋㅋ 다음에!" } },
	dance = { p = { "오, 춤 좀 추시네요? 🕺", "이 노래 너무 좋아요! 💃" }, c = { "오 춤 좀 추는데? 🕺", "이 노래 미쳤다!! 💃", "같이 추니까 더 신난다 ㅋㅋ" } },
	danceTired = { p = { "잠깐 숨 좀 돌리고요 ㅎㅎ" }, c = { "잠깐만, 숨 좀 쉬자 ㅋㅋ" } },
	drink = { p = { "와, 고마워요! 건배 🍹", "잘 마실게요! 오늘 최고예요 🥂" }, c = { "오 고마워!! 짠 🍹", "역시 너밖에 없다! 건배 🥂" } },
	noMoney = { p = { "어… 돈이 좀 모자라신 것 같아요 ㅎㅎ" }, c = { "야 너 돈 모자라잖아 ㅋㅋ 괜찮아!" } },
	errandThanks = { p = { "진짜 고마워요! 이거 사례예요 🙏", "덕분에 살았어요! 약소하지만 받아 주세요." }, c = { "진짜 고마워! 이거 받아 🙏", "역시 너밖에 없다! 이거 사례야." } },
	errandOk = { p = { "고마워요! 여기서 기다릴게요 🙏" }, c = { "고마워! 여기서 기다릴게 🙏" } },
	errandNo = { p = { "괜찮아요, 다음에 부탁할게요!" }, c = { "괜찮아, 다음에 부탁할게!" } },
	errandWaiting = { p = { "아까 부탁한 거… 잊지 않으셨죠? ㅎㅎ" }, c = { "아까 부탁한 거 잊지 마 ㅋㅋ" } },
	bdayKnown = { p = { "제 생일 기억해 주셨어요?! 너무 감동이에요 🎂" }, c = { "내 생일 기억해 줬구나!! 감동이야 🎂" } },
	bdayLucky = { p = { "어? 오늘 제 생일인 거 어떻게 아셨어요? 고마워요 🎂" }, c = { "헐 내 생일인 거 어떻게 알았어? 고마워 🎂" } },
	tellBday = { p = { "참, 제 생일은 {m}월 {d}일이에요. 기억해 주실 거죠? ㅎㅎ" }, c = { "참, 내 생일 {m}월 {d}일이야! 기억해 줘 ㅎㅎ" } },
	todayBday = { p = { "사실 오늘 제 생일이에요 🎂" }, c = { "사실 오늘 내 생일이다 🎂" } },
	visit = { p = { "일하는 데까지 와 주셨네요! 😊" }, c = { "일하는 데까지 와 줬네! 😊" } },
	tipDone = { p = { "오늘은 제가 아는 건 다 말씀드렸어요 ㅎㅎ" }, c = { "오늘 아는 건 다 말해 줬잖아 ㅋㅋ" } },
	callHello = { p = { "여보세요? 아, {name}님!" }, c = { "여보세요? 오 {name}! 웬일이야?" } },
	coming = { p = { "지금 갈게요! 조금만 기다려요 🏃" }, c = { "지금 갈게! 거기 있어 🏃" } },
	farewell = { p = { "오늘 즐거웠어요! 또 봐요 👋" }, c = { "오늘 즐거웠어! 또 놀자 👋" } },
	farewellWork = { p = { "저 이제 일하러 가야 해요! 또 봐요 👋" }, c = { "나 이제 일하러 가야 해! 또 보자 👋" } },
	farewellUpset = { p = { "…저 먼저 갈게요." }, c = { "…나 먼저 갈게." } },
	intro = { p = { "처음 뵙네요. 저는 {full} 😊", "안녕하세요, 저는 {full} 반가워요!" } },
	notHere = { p = { "(지금은 여기 없는 것 같아요)" } },
}

local function linesOf(key: string, reg: string): { string }
	local L = LINES[key]
	if not L then
		return { "…" }
	end
	return L[reg] or L.p or L.c or { "…" }
end

-------------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------------
local function now(): number
	return os.time()
end

local function clockNow(): number
	if ctx and ctx.env then
		local ok, env = pcall(ctx.env)
		if ok and type(env) == "table" and type(env.clock) == "number" then
			return env.clock % 24
		end
	end
	local wc = workspace:GetAttribute("GwangalliClock")
	if type(wc) == "number" and wc == wc then
		return wc % 24
	end
	return Lighting.ClockTime
end

local function won(n: number): string
	if G and G.format and G.format.won then
		return G.format.won(n)
	end
	return tostring(n) .. "원"
end

local function hourSeconds(): number
	return (G and G.HOUR_SECONDS) or 60
end

local function push(player: Player, payload: any)
	local r = remotes.State
	if r and player.Parent == Players then
		r:FireClient(player, payload)
	end
end

local function notify(player: Player, kind: string, title: string, body: string?, extra: any?)
	if ctx and ctx.notify then
		pcall(ctx.notify, player, kind, title, body, extra)
	end
end

local function setWaypoint(player: Player, dest: string?)
	if dest and ctx and ctx.setWaypoint then
		pcall(ctx.setWaypoint, player, dest)
	end
end

local function playerName(player: Player): string
	local n = player.DisplayName
	if type(n) ~= "string" or n == "" then
		n = player.Name
	end
	return n
end

local function citizen(id: any): any?
	return Citizens and Citizens.get(id) or nil
end

local function tierInfo(a: number): (number, any)
	return Social.tierOf(a)
end

local function vars(player: Player, extra: any?): any
	local v = { name = playerName(player) }
	if extra then
		for k, x in extra do
			v[k] = x
		end
	end
	return v
end

local function pickLine(key: string, reg: string, v: any?): string
	return Citizens.fill(Citizens.pick(linesOf(key, reg)) or "…", v)
end

-- Destination DisplayName -> short Korean label (area label when an area uses it).
local destLabelCache: { [string]: string } = {}
local function destLabel(dest: string): string
	local l = destLabelCache[dest]
	if l then
		return l
	end
	l = dest
	for _, a in Citizens.AREAS do
		if a.dest == dest then
			l = a.label
			break
		end
	end
	destLabelCache[dest] = l
	return l
end

-------------------------------------------------------------------------------------------------
-- World positions
-------------------------------------------------------------------------------------------------
local destMiss: { [string]: number } = {}
local function destPart(name: string): BasePart?
	if ctx and ctx.dest then
		local ok, p = pcall(ctx.dest, name)
		if ok and typeof(p) == "Instance" and p:IsA("BasePart") then
			return p
		end
	end
	local miss = destMiss[name]
	if miss and os.clock() - miss < 30 then
		return nil
	end
	for _, inst in CollectionService:GetTagged("Destination") do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local n = inst:GetAttribute("DisplayName")
			if (if type(n) == "string" and n ~= "" then n else inst.Name) == name then
				destMiss[name] = nil
				return inst
			end
		end
	end
	destMiss[name] = os.clock()
	return nil
end

local function destPos(name: string?): Vector3?
	if not name then
		return nil
	end
	local p = destPart(name)
	return p and p.Position or nil
end

local areaParts: { [string]: BasePart } = {}
local function areaPos(areaId: string): Vector3?
	local a = Citizens.AREAS[areaId]
	if not a then
		return nil
	end
	local p = areaParts[areaId]
	if p and p.Parent then
		return p.Position
	end
	local q = destPart(a.dest)
	if q then
		areaParts[areaId] = q
		return q.Position
	end
	return nil
end

local keyModels: { [string]: Instance } = {}
local function keyNpcPos(id: string): (Vector3?, boolean)
	local m = keyModels[id]
	if not (m and m.Parent) then
		m = nil
		local folder = workspace:FindFirstChild("GwangalliNPCs")
		if folder then
			for _, ch in folder:GetChildren() do
				if ch:GetAttribute("NpcId") == id or ch.Name == "NPC_" .. id then
					m = ch
					break
				end
			end
		end
		if m then
			keyModels[id] = m
		else
			keyModels[id] = nil
		end
	end
	if m then
		if m:IsA("Model") then
			local ok, cf = pcall(m.GetPivot, m)
			if ok then
				return cf.Position, true
			end
		elseif m:IsA("BasePart") then
			return m.Position, true
		end
	end
	local def = G.NPCS and G.NPCS[id]
	if def and def.dest then
		return destPos(def.dest), false
	end
	local c = citizen(id)
	if c and c.post then
		return areaPos(c.post), false
	end
	return nil, false
end

-- Club zone (ClubZone boxes with Zone ~= "Near", like Club.server). Without built zones, or with a
-- wristband right at the door, the area in front of the club counts too.
local zoneParts: { [BasePart]: boolean } = {}
local function inClub(player: Player): boolean
	local root = Util.rootPosition(player)
	if not root then
		return false
	end
	local anyZone = false
	for z in zoneParts do
		if z.Parent and z:GetAttribute("Zone") ~= "Near" then
			anyZone = true
			local lp = z.CFrame:PointToObjectSpace(root)
			local h = z.Size * 0.5
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				return true
			end
		end
	end
	local door = areaPos("club")
	if not door then
		return false
	end
	local reach = if not anyZone then 90 elseif player:GetAttribute("ClubOceanWristband") ~= nil then 60 else 0
	return reach > 0 and (root - door).Magnitude <= reach
end

-- In the player's OWN home (homes contract: attributes InHome / HomeRole).
local function atHome(player: Player): boolean
	local v = player:GetAttribute("InHome")
	if v == nil or v == false or v == "" or v == 0 then
		return false
	end
	local role = player:GetAttribute("HomeRole")
	return role == nil or role == "" or role == "owner"
end

local function near(player: Player, pos: Vector3?, radius: number): boolean
	local root = Util.rootPosition(player)
	return root ~= nil and pos ~= nil and (root - pos).Magnitude <= radius
end

local function vec(v: any): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z or math.abs(v.X) > 1e5 or math.abs(v.Y) > 1e5 or math.abs(v.Z) > 1e5 then
		return nil
	end
	return v
end

-------------------------------------------------------------------------------------------------
-- Records / sessions
-------------------------------------------------------------------------------------------------
local function recOf(sess: Sess, id: string, create: boolean): any?
	local st = sess.state
	local r = st.npcs[id]
	if not r and create then
		local c = citizen(id)
		local tdef = c and Social.TYPES and Social.TYPES[c.type]
		r = Social.newRecord(now(), c and c.start or 0, tdef and tdef.grudge or 0) -- 폭력적인 NPC: starts below zero
		st.npcs[id] = r
	end
	return r
end

local function affinityOf(sess: Sess, id: string): number
	local r = sess.state.npcs[id]
	if r then
		return r.a
	end
	local c = citizen(id)
	return c and c.start or 0
end

local function markDirty(player: Player, sess: Sess)
	sess.dirty = true
	sess.state.u = now()
	if Profiles and Profiles.markDirty then
		pcall(Profiles.markDirty, player)
	end
end

local function reindex(sess: Sess, id: string)
	local r = sess.state.npcs[id]
	if r and (r.pr or r.er or r.f.secret == "pending") then
		sess.active[id] = true
	else
		sess.active[id] = nil
	end
end

-- Bookkeeping when you interact with someone (call AFTER composing any memory line).
local function meet(player: Player, sess: Sess, id: string, rec: any, area: string?, act: string?)
	local t = now()
	if (rec.first or 0) == 0 then
		rec.first = t
	end
	if t - (rec.last or 0) > MEET_GAP then
		rec.met = (rec.met or 0) + 1
	end
	rec.last = t
	rec.dk = 0
	if area and area ~= "" then
		rec.la = area
	end
	if act then
		rec.lx = act
	end
	rec.u = t
	markDirty(player, sess)
end

local function memoryOf(player: Player, rec: any?): any?
	if not rec or (rec.met or 0) == 0 then
		return nil
	end
	local g = rec.lg ~= "" and Social.GIFTS[rec.lg]
	return {
		met = rec.met,
		since = now() - (rec.last or 0),
		area = rec.la,
		act = rec.lx,
		gift = g and g.name or nil,
		broken = rec.f.broken == true,
	}
end

local function isBirthday(c: any): boolean
	local m, d = Social.kstDate(now())
	return c.bday ~= nil and c.bday[1] == m and c.bday[2] == d
end

local function canCompanion(c: any): boolean
	return not c.key or COMPANION_OK_KEYS[c.id] == true
end

-------------------------------------------------------------------------------------------------
-- Awards + tier events
-------------------------------------------------------------------------------------------------
local endCompanion: (Player, Sess, string, boolean?) -> ()
local sendText: (Player, Sess, string, string, any?) -> ()

-- Phone number exchanged -> a contact (snapshot.contacts; calls, texts, club invitations).
local function giveNumber(player: Player, sess: Sess, id: string, rec: any, via: string, silent: boolean?)
	if rec.f.number then
		return
	end
	rec.f.number = true
	markDirty(player, sess)
	local c = citizen(id)
	local name = c and c.name or id
	push(player, { kind = "contact", id = id, name = name, added = true, via = via })
	if not silent then
		notify(player, "info", "📱 연락처 저장", string.format("%s의 번호를 받았어요. 전화 · 문자로 연락할 수 있어요", name), { social = id })
	end
end

local function onTierChange(player: Player, sess: Sess, id: string, rec: any, from: number, to: number, first: boolean)
	local c = citizen(id)
	if not c then
		return
	end
	local T = Social.TIERS[to]
	local who = Social.josa(c.name, "와", "과")
	local up = to > from
	local text
	if up then
		if to == 2 then
			text = who .. " 아는 사이가 됐어요. 이제 이름을 불러 줘요!"
		elseif to == 3 then
			text = who .. " 친한 사이! 연락처를 주고받았어요 📱 같이 다닐 수도 있어요."
			giveNumber(player, sess, id, rec, "tier", true)
			local fl = Citizens.friendsOf(id)
			if first and #fl > 0 then
				local names, list = {}, {}
				for _, f in fl do
					local fc = citizen(f)
					if fc then
						table.insert(names, Citizens.nameI(f))
						table.insert(list, { id = f, name = fc.name })
					end
				end
				text ..= string.format(" %s 친구 %s에게도 얘기해 둔대요.", Social.josa(c.name, "가", "이"), table.concat(names, ", "))
				push(player, { kind = "intro", id = id, friends = list })
			end
		elseif to == 4 then
			text = who .. " 친구가 됐어요! 💖 전화로 불러낼 수 있고 친구 혜택이 생겨요."
			giveNumber(player, sess, id, rec, "tier", true)
		else
			text = who .. " 절친이 됐어요! 💞 특별한 이벤트가 열려요."
		end
	else
		text = who .. " 사이가 조금 멀어졌어요… (" .. T.name .. ")"
	end
	push(player, { kind = "tier", id = id, from = from, to = to, up = up, first = first, text = text })
	if up or from >= Social.TIER_FRIEND then
		notify(player, "info", T.icon .. " " .. T.name, text, { social = id })
	end
	if up and first then
		if to == Social.TIER_FRIEND then
			sess.state.stats.friends = (sess.state.stats.friends or 0) + 1
			task.delay(4, function()
				if sessions[player] == sess then
					sendText(player, sess, id, "friend")
				end
			end)
		elseif to == Social.TIER_BESTIE then
			rec.f.secret = "pending"
			reindex(sess, id)
			task.delay(6, function()
				if sessions[player] == sess then
					sendText(player, sess, id, "bestie", { secret = true })
					setWaypoint(player, c.secret)
				end
			end)
		end
	end
	local comp = sess.comp
	if comp and comp.id == id and not up and to < Social.COMPANION_TIER then
		endCompanion(player, sess, "upset")
	end
end

-- The one place affinity changes. opts = { amount?, mult?, nocap?, silent? } -> result (Social.award)
local function award(player: Player, sess: Sess, id: string, source: string, opts: any?): any
	local rec = recOf(sess, id, true)
	local pkBefore = rec.pk or 1
	local c = citizen(id)
	local tdef = c and Social.TYPES and Social.TYPES[c.type]
	if tdef and tdef.grudgeCap then
		-- (a copy: callers may reuse their opts table)
		local o2 = if opts then table.clone(opts) else {}
		o2.grudgeCap = tdef.grudgeCap
		opts = o2
	end
	local res = Social.award(rec, source, now(), opts)
	markDirty(player, sess)
	if res.delta ~= 0 then
		local def = Social.SOURCES[source]
		push(player, { kind = "affinity", id = id, a = rec.a, delta = res.delta, tier = res.tierTo, source = source, reason = def and def.label or source })
		if res.tierTo ~= res.tierFrom then
			onTierChange(player, sess, id, rec, res.tierFrom, res.tierTo, res.tierTo > pkBefore)
		end
	end
	return res
end

-------------------------------------------------------------------------------------------------
-- Companion (server state; the client draws and moves the friend next to the player)
-------------------------------------------------------------------------------------------------
local function setCompanion(player: Player, sess: Sess, id: string, opts: any)
	local c = citizen(id)
	if not c then
		return
	end
	if sess.comp then
		endCompanion(player, sess, "swap", true)
	end
	local tier = Social.tierOf(affinityOf(sess, id))
	sess.comp = {
		id = id,
		since = os.clock(),
		untilT = os.clock() + Social.COMPANION_SECONDS,
		dest = opts.dest,
		source = opts.source,
		via = opts.via or "person",
		hangT = os.clock(),
		arrived = false,
	}
	player:SetAttribute(Social.Attr.Companion, id)
	player:SetAttribute(Social.Attr.CompanionTier, tier)
	push(player, {
		kind = "companion",
		id = id,
		name = c.name,
		tier = tier,
		state = if opts.via == "call" then "coming" else "follow",
		dest = opts.dest,
		untilIn = Social.COMPANION_SECONDS,
	})
	if opts.met then
		notify(player, "info", "🎉 " .. c.name, "만났어요! 같이 놀아요 (최대 15분)", { social = id })
		return
	end
	local body = if opts.dest then destLabel(opts.dest) .. "까지 같이 가요! (최대 15분)" else "같이 다녀요! (최대 15분)"
	notify(player, "info", "🚶 " .. c.name .. " 동행", body, { social = id })
	setWaypoint(player, opts.dest)
end

-- You met up at the place of a promise / text invitation: close friends join you (the activity is
-- then awarded by companionTick when you are there together); others count the activity right away.
local function meetUp(player: Player, sess: Sess, id: string, kind: string)
	local c = citizen(id)
	local inv = Social.INVITES[kind]
	if not c then
		return
	end
	local tier = Social.tierOf(affinityOf(sess, id))
	if canCompanion(c) and not sess.comp and tier >= Social.COMPANION_TIER then
		setCompanion(player, sess, id, { via = "promise", met = true, source = inv and inv.source or nil, dest = inv and inv.dest or nil })
	elseif inv and inv.source then
		award(player, sess, id, inv.source)
		local rec = recOf(sess, id, true)
		rec.lx = inv.source
	end
end

endCompanion = function(player: Player, sess: Sess, why: string, silent: boolean?)
	local comp = sess.comp
	if not comp then
		return
	end
	sess.comp = nil
	if player.Parent == Players then
		player:SetAttribute(Social.Attr.Companion, "")
		player:SetAttribute(Social.Attr.CompanionTier, 0)
	end
	local rec = recOf(sess, comp.id, false)
	if rec and (rec.lx == "" or rec.lx == "talk") then
		rec.lx = "hangout"
	end
	push(player, { kind = "companion", id = false, prev = comp.id, reason = why })
	if not silent then
		local c = citizen(comp.id)
		local reg = Citizens.register(Social.tierOf(affinityOf(sess, comp.id)))
		local key = if why == "work" then "farewellWork" elseif why == "upset" then "farewellUpset" else "farewell"
		if c then
			notify(player, "info", "👋 " .. c.name, pickLine(key, reg, vars(player)), { social = comp.id })
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Texts (inbox; key NPCs with a phone contact also write into the real Messages thread)
-------------------------------------------------------------------------------------------------
local function contactFor(id: string): string?
	if not G.CONTACTS then
		return nil
	end
	if G.CONTACTS[id] then
		return id
	end
	for cid, c in G.CONTACTS do
		if c.npc == id then
			return cid
		end
	end
	return nil
end

local function msgView(m: any): any
	local out = { id = m.id, from = m.from, text = m.text, t = m.t, kind = m.kind, state = m.state }
	local c = citizen(m.from)
	out.name = c and c.name or m.from
	if m.invite then
		out.invite = { kind = m.invite.kind, dest = m.invite.dest, untilIn = math.max(0, m.invite.untilT - now()) }
		out.choices = if m.state == "new" then { { id = "accept", label = "좋아! 👍" }, { id = "decline", label = "다음에 ㅠ" } } else nil
	end
	return out
end

sendText = function(player: Player, sess: Sess, id: string, kind: string, invite: any?)
	local c = citizen(id)
	if not c then
		return
	end
	local place = ""
	if invite and invite.dest then
		place = destLabel(invite.dest)
	elseif kind == "bestie" then
		place = destLabel(c.secret)
	end
	local text = Citizens.textFor(id, kind, nil, vars(player, { place = place }))
	if text == "" then
		return
	end
	local st = sess.state
	local msg = { id = st.nextMsg, from = id, text = text, t = now(), kind = kind, state = "new", invite = nil :: any }
	if invite and invite.dest and invite.kind and Social.INVITES[invite.kind] then
		msg.invite = { kind = invite.kind, dest = invite.dest, untilT = invite.untilT or (now() + Social.PROMISE_SECONDS) }
	elseif kind ~= "help" then
		msg.state = "read"
	end
	st.nextMsg += 1
	table.insert(st.inbox, msg)
	while #st.inbox > Social.INBOX_MAX do
		table.remove(st.inbox, 1)
	end
	sess.lastTextFrom[id] = os.clock()
	markDirty(player, sess)
	push(player, { kind = "text", msg = msgView(msg) })
	local cid = contactFor(id)
	if cid and ctx.sendMessage then
		pcall(ctx.sendMessage, player, cid, text)
	else
		notify(player, "info", "💬 " .. c.name, text, { social = id, sound = "message" })
	end
end

-------------------------------------------------------------------------------------------------
-- Promises (meet at a place) / errands / the 절친 secret spot
-------------------------------------------------------------------------------------------------
local function secondsUntilClock(target: number): number
	return ((target - clockNow()) % 24) * hourSeconds()
end

local function clubDue(): number
	local c = clockNow()
	local target = if c >= 17 and c < 22 then 23.5 else 2
	return now() + math.clamp(math.floor(secondsUntilClock(target)), 240, 900)
end

local function makePromise(player: Player, sess: Sess, id: string, kind: string, dest: string, due: number)
	local rec = recOf(sess, id, true)
	rec.pr = { kind = kind, dest = dest, due = due, made = now() }
	reindex(sess, id)
	markDirty(player, sess)
	local c = citizen(id)
	setWaypoint(player, dest)
	push(player, { kind = "promise", id = id, promise = kind, dest = dest, untilIn = due - now(), state = "made" })
	notify(player, "info", "📍 약속", string.format("%s · %s에서 만나요 (%d분 안에)", c and c.name or id, destLabel(dest), math.max(1, math.floor((due - now()) / 60))), { social = id })
end

local function arrivedAt(player: Player, kind: string?, dest: string?): boolean
	if kind == "club" and inClub(player) then
		return true
	end
	if kind == "home" then
		return atHome(player)
	end
	local p = destPos(dest)
	if not p then
		return false
	end
	local part = dest and destPart(dest)
	local extra = if part then math.min(60, math.max(part.Size.X, part.Size.Z) * 0.5) else 0
	return near(player, p, ARRIVE + extra)
end

local function checkPromises(player: Player, sess: Sess)
	for id in sess.active do
		local rec = sess.state.npcs[id]
		local c = citizen(id)
		if not rec or not c then
			sess.active[id] = nil
			continue
		end
		local pr = rec.pr
		if pr then
			if arrivedAt(player, pr.kind, pr.dest) then
				rec.pr = nil
				rec.f.broken = nil
				award(player, sess, id, "promise")
				meet(player, sess, id, rec, nil, "promise")
				sendText(player, sess, id, "kept")
				push(player, { kind = "promise", id = id, promise = pr.kind, dest = pr.dest, state = "kept" })
				if pr.kind == "club" then
					sess.clubGuestUntil = os.clock() + (G.CLUB and G.CLUB.passSeconds or 1440)
				end
				if not (sess.comp and sess.comp.id == id) then
					meetUp(player, sess, id, pr.kind)
				end
			elseif now() > pr.due then
				rec.pr = nil
				rec.f.broken = true
				award(player, sess, id, "broken")
				sendText(player, sess, id, "broken")
				push(player, { kind = "promise", id = id, promise = pr.kind, dest = pr.dest, state = "broken" })
			end
		end
		local er = rec.er
		if er then
			if now() > er.due then
				rec.er = nil
				award(player, sess, id, "errandfail")
				notify(player, "warn", "⌛ 부탁 시간 초과", string.format("%s의 부탁을 못 들어줬어요…", c.name), { social = id })
				push(player, { kind = "errand", id = id, stage = "failed" })
			elseif er.stage == "go" and arrivedAt(player, nil, er.dest) then
				er.stage = "back"
				markDirty(player, sess)
				local def = Citizens.ERRANDS[er.id]
				notify(player, "info", "📦 " .. (def and def.item or "물건") .. " 챙김!", c.name .. "에게 돌아가서 전해 주세요", { social = id })
				push(player, { kind = "errand", id = id, stage = "back", untilIn = er.due - now() })
				local back = sess.errandPos[id]
				if not back then
					local area = Citizens.whereNow(id, clockNow())
					local a = area and Citizens.AREAS[area]
					setWaypoint(player, a and a.dest or nil)
				end
			end
		end
		if rec.f.secret == "pending" and arrivedAt(player, nil, c.secret) then
			rec.f.secret = "done"
			award(player, sess, id, "bestie")
			if ctx.addStats then
				pcall(ctx.addStats, player, { happiness = 10, popularity = 2 }, "절친의 비밀 장소 💞")
			end
			sendText(player, sess, id, "secret")
			push(player, { kind = "event", id = id, event = "bestie", text = Citizens.textFor(id, "secret", nil, vars(player)) })
			if canCompanion(c) and not sess.comp then
				setCompanion(player, sess, id, { via = "promise" })
			end
		end
		reindex(sess, id)
	end
end

local function completeErrand(player: Player, sess: Sess, id: string): string?
	local rec = recOf(sess, id, false)
	if not rec or not rec.er or rec.er.stage ~= "back" then
		return nil
	end
	local def = Citizens.ERRANDS[rec.er.id]
	rec.er = nil
	sess.errandPos[id] = nil
	reindex(sess, id)
	award(player, sess, id, "errand")
	meet(player, sess, id, rec, nil, "errand")
	sess.state.stats.errands = (sess.state.stats.errands or 0) + 1
	local tip = def and def.tip or 3000
	local c = citizen(id)
	if ctx.ledger then
		pcall(ctx.ledger, player, "cash", tip, "심부름 사례비 · " .. (c and c.name or id))
	end
	push(player, { kind = "errand", id = id, stage = "done" })
	return pickLine("errandThanks", Citizens.register(Social.tierOf(rec.a)), vars(player))
end

-------------------------------------------------------------------------------------------------
-- Conversation nodes ("soc:" choices; shared by citizen dialogs and key-NPC dialogs)
-------------------------------------------------------------------------------------------------
type Node = { text: string, choices: { { id: string, label: string } }, emote: string? }

local function socialChoices(player: Player, sess: Sess, id: string, remote: boolean): { { id: string, label: string } }
	local c = citizen(id)
	local out = {}
	if not c then
		return out
	end
	local rec = recOf(sess, id, false)
	local tier = Social.tierOf(affinityOf(sess, id))
	local function add(cid: string, label: string)
		table.insert(out, { id = cid, label = label })
	end
	add("soc:talk", if remote then "📞 수다 떨기" else "💬 수다 떨기")
	if not remote then
		add("soc:compliment", "😊 칭찬하기")
		add("soc:gift", "🎁 선물하기")
		if not (rec and rec.f.number) then
			add("soc:number", "📱 번호 물어보기")
		end
	end
	if rec and rec.er then
		if rec.er.stage == "back" and not remote then
			add("soc:errand_done", "📦 부탁한 거 가져왔어요")
		end
	elseif tier >= Social.TIER_ACQ and not remote then
		add("soc:errand", if rec and rec.f.help then "🤝 부탁 들어줄게!" else "🤝 도와줄 일 있어요?")
	end
	local comp = sess.comp
	if comp and comp.id == id then
		add("soc:dismiss", "👋 오늘은 여기까지")
	elseif canCompanion(c) and (not remote or tier >= Social.CALL_TIER) then
		add("soc:invite", if remote then "🎉 지금 나올래?" else "🎉 같이 놀자!")
	end
	if not remote and inClub(player) and ((comp and comp.id == id) or Citizens.atClub(id, clockNow())) then
		add("soc:dance", "💃 같이 춤추자")
		add("soc:drink", string.format("🍹 한잔 살게 (%s)", won(if c.minor then SOFT_DRINK_PRICE else DRINK_PRICE)))
	end
	if isBirthday(c) and tier >= Social.TIER_ACQ then
		local _, _, year = Social.kstDate(now())
		if not (rec and rec.f.bdayYear == year) then
			add("soc:bday", "🎂 생일 축하해!")
		end
	end
	if tier >= Social.TIER_FRIEND then
		add("soc:tip", "💡 요즘 좋은 정보 없어?")
	end
	return out
end

local function giftChoices(sess: Sess, id: string): { { id: string, label: string } }
	local order = Social.GIFT_ORDER
	local per = 6
	local pages = math.ceil(#order / per)
	local page = ((sess.giftPage or 0) % pages)
	local out = {}
	local rec = recOf(sess, id, false)
	for i = page * per + 1, math.min(#order, page * per + per) do
		local gid = order[i]
		local g = Social.GIFTS[gid]
		local known = rec and rec.gk[gid]
		local mark = if known == "love" then " 💖" elseif known == "like" then " 🙂" elseif known == "dislike" then " 😕" else ""
		table.insert(out, { id = "soc:g:" .. gid, label = string.format("%s %s %s%s", g.icon, g.name, won(g.price), mark) })
	end
	table.insert(out, { id = "soc:giftmore", label = "다른 선물 보기" })
	return out
end

local function inviteChoices(player: Player, sess: Sess, id: string, remote: boolean): { { id: string, label: string } }
	local out = {}
	local d = Profiles.get(player)
	for _, kind in Social.INVITE_ORDER do
		local inv = Social.INVITES[kind]
		local ok = true
		if inv.needsHome and not (d and d.home) then
			ok = false
		end
		if remote and kind == "now" then
			ok = true
		end
		if ok then
			table.insert(out, { id = "soc:inv:" .. kind, label = inv.icon .. " " .. inv.label })
		end
	end
	return out
end

local function backChoice(forKey: boolean): { id: string, label: string }
	return if forKey then { id = "back", label = "돌아가기" } else { id = "soc:back", label = "돌아가기" }
end

local function rootNode(player: Player, sess: Sess, id: string, remote: boolean, text: string?): Node
	local reg = Citizens.register(Social.tierOf(affinityOf(sess, id)))
	return { text = text or pickLine("again", reg, vars(player)), choices = socialChoices(player, sess, id, remote) }
end

-- Accept / decline an invitation.
-- forced = the NPC suggested it themselves (the evening club lure): no dice roll.
local function tryInvite(player: Player, sess: Sess, id: string, kind: string, remote: boolean, forced: boolean?): (string, Node?)
	local c = citizen(id)
	local inv = Social.INVITES[kind]
	if not c or not inv or not canCompanion(c) then
		return "…", nil
	end
	local rec = recOf(sess, id, true)
	local tier = Social.tierOf(rec.a)
	local reg = Citizens.register(tier)
	local v = vars(player)
	if not forced and (sess.inviteCd[id] or 0) > os.clock() then
		return pickLine("askedAlready", reg, v), nil
	end
	local d = Profiles.get(player)
	local clock = clockNow()
	local _, act = Citizens.whereNow(id, clock)
	local info = {
		tier = tier,
		social = c.social,
		working = act == "work",
		sleeping = act == "sleep",
		minor = c.minor,
		clubber = c.club,
		hasHome = d ~= nil and d.home ~= nil,
	}
	local p = if forced then 1 else Social.acceptChance(kind, info)
	if math.random() >= p then
		sess.inviteCd[id] = os.clock() + Social.INVITE_DECLINE_COOLDOWN
		local key = "decline"
		if (kind == "club" or inv.adult) and c.minor then
			key = "declineMinor"
		elseif inv.needsHome and not info.hasHome then
			key = "declineNoHome"
		elseif kind == "home" and tier < Social.TIER_CLOSE + 1 then
			key = "declineHome"
		elseif tier < inv.minTier or tier == 1 then
			key = "declineStranger"
		elseif info.working then
			key = "declineWork"
		end
		return pickLine(key, reg, v), nil
	end
	award(player, sess, id, "invite")
	local companionOK = tier >= Social.COMPANION_TIER or (remote and tier >= Social.CALL_TIER)
	local via = if remote then "call" else "person"
	if kind == "now" then
		setCompanion(player, sess, id, { via = via })
		return pickLine(if remote then "coming" else "accept", reg, v), nil
	elseif kind == "home" then
		local l = d and d.home and G.LISTINGS and G.LISTINGS[d.home.listingId]
		setCompanion(player, sess, id, { via = via, source = "home", dest = l and l.place or nil })
		return pickLine(if remote then "coming" else "accept", reg, v), nil
	elseif kind == "club" then
		if companionOK and Citizens.hype(clock) >= 0.2 then
			setCompanion(player, sess, id, { via = via, dest = inv.dest, source = "club" })
			return pickLine(if remote then "coming" else "accept", reg, v), nil
		end
		makePromise(player, sess, id, "club", inv.dest, clubDue())
		return pickLine("acceptLater", reg, vars(player, { place = destLabel(inv.dest) })), nil
	end
	if companionOK then
		setCompanion(player, sess, id, { via = via, dest = inv.dest, source = inv.source })
		return pickLine(if remote then "coming" else "accept", reg, v), nil
	end
	makePromise(player, sess, id, kind, inv.dest, now() + Social.PROMISE_SECONDS)
	return pickLine("acceptLater", reg, vars(player, { place = destLabel(inv.dest) })), nil
end

local function tipLine(player: Player, sess: Sess, id: string): string
	local rec = recOf(sess, id, true)
	local reg = Citizens.register(Social.tierOf(rec.a))
	local gd = Social.gameDay(now())
	if rec.f.tipDay == gd then
		return pickLine("tipDone", reg, vars(player))
	end
	rec.f.tipDay = gd
	markDirty(player, sess)
	local d = Profiles.get(player)
	local lines = {}
	if d and not d.job and G.JOB_ORDER then
		local jid = G.JOB_ORDER[math.random(1, #G.JOB_ORDER)]
		local j = G.JOBS[jid]
		if j and j.levels and j.levels[1] then
			table.insert(lines, string.format("%s에서 %s 구한대! 시급 %s부터래. 가 봐!", j.place or "근처", j.title or "알바", won(j.levels[1].wage or 0)))
		end
	end
	if d and G.LISTING_ORDER and G.LISTINGS then
		local cur = d.home and G.LISTINGS[d.home.listingId]
		local curTier = cur and cur.tier or 0
		for _, lid in G.LISTING_ORDER do
			local l = G.LISTINGS[lid]
			if l and l.tier == curTier + 1 then
				local price = if l.kind == "rent" then string.format("보증금 %s · 하루 %s", won(l.deposit or 0), won(l.rentPerDay or 0)) else won(l.price or 0)
				table.insert(lines, string.format("정실장님네 부동산에 '%s' 매물 나왔대! (%s)", l.name, price))
				break
			end
		end
	end
	table.insert(lines, "오늘 밤 10시 반부터 클럽 오션 피크래. 그때 가면 제일 신나!")
	local c = citizen(id)
	if c and not c.key and c.work then
		local a = Citizens.AREAS[c.work]
		if a then
			table.insert(lines, string.format("%s 오면 내가 챙겨 줄게! 친구 할인 있다 ㅋㅋ", a.label))
		end
	end
	local tip = lines[math.random(1, #lines)]
	return tip
end

-- Handles one "soc:" choice. Returns { handled, line?, node?, close? }.
local function handle(player: Player, sess: Sess, id: string, choiceId: string, remote: boolean, forKey: boolean): any
	local c = citizen(id)
	if not c or string.sub(choiceId, 1, 4) ~= "soc:" then
		return { handled = false }
	end
	local rec = recOf(sess, id, true)
	local tier = Social.tierOf(rec.a)
	local reg = Citizens.register(tier)
	local v = vars(player)
	local clock = clockNow()
	local back = backChoice(forKey)
	local cmd = string.sub(choiceId, 5)

	if cmd == "menu" or cmd == "back" then
		local text = if cmd == "menu" then Citizens.smallTalk(id, tier, clock, nil, v, (rec.met or 0) > 0) else nil
		local node = rootNode(player, sess, id, remote, text)
		if forKey then
			table.insert(node.choices, backChoice(true))
		end
		return { handled = true, node = node }
	elseif cmd == "talk" then
		if (rec.up or 0) > now() then
			return { handled = true, line = Citizens.reactLine(id, tier, "upset", nil, v) }
		end
		award(player, sess, id, if remote then "call" else "chat")
		meet(player, sess, id, rec, nil, nil)
		local q = Citizens.question(id, tier, clock)
		if not q then
			return { handled = true, line = Citizens.smallTalk(id, tier, clock, nil, v, true) }
		end
		local order = { 1, 2, 3 }
		for i = 3, 2, -1 do
			local j = math.random(1, i)
			order[i], order[j] = order[j], order[i]
		end
		sess.q = { id = id, topic = q.topic, replies = q.replies, order = order }
		local choices = {}
		for i = 1, 3 do
			choices[i] = { id = "soc:r:" .. i, label = q.replies[order[i]].t }
		end
		return { handled = true, node = { text = Citizens.fill(q.text, v), choices = choices, emote = "think" } }
	elseif string.sub(cmd, 1, 2) == "r:" then
		local q = sess.q
		local n = tonumber(string.sub(cmd, 3))
		if not q or q.id ~= id or not n or not q.order[n] then
			return { handled = true }
		end
		sess.q = nil
		local rep = q.replies[q.order[n]]
		local outcome = Citizens.react(id, rep.tone, q.topic)
		if outcome == "rude" then
			award(player, sess, id, "rude")
			return { handled = true, line = Citizens.reactLine(id, tier, "rude", nil, v), close = true }
		elseif outcome == "dislike" then
			award(player, sess, id, "dislike")
		else
			local gain = Social.REPLY_GAIN[outcome] or 0
			if gain > 0 then
				award(player, sess, id, "reply", { amount = gain })
			end
		end
		local line = Citizens.reactLine(id, Social.tierOf(rec.a), outcome, nil, v)
		-- close friends tell you their birthday once
		if Social.tierOf(rec.a) >= Social.TIER_CLOSE and not rec.f.bdayKnown and math.random() < 0.35 then
			rec.f.bdayKnown = true
			line ..= "\n" .. pickLine("tellBday", Citizens.register(Social.tierOf(rec.a)), vars(player, { m = c.bday[1], d = c.bday[2] }))
		end
		if rep.effect == "club" and outcome ~= "dislike" and outcome ~= "meh" and canCompanion(c) and not c.minor and (c.club or 0) > 0 and not rec.pr then
			local l2 = tryInvite(player, sess, id, "club", remote, true)
			line ..= "\n" .. l2
		end
		return { handled = true, line = line }
	elseif cmd == "gift" or cmd == "giftmore" then
		if remote then
			return { handled = true }
		end
		if cmd == "giftmore" then
			sess.giftPage = (sess.giftPage or 0) + 1
		end
		local choices = giftChoices(sess, id)
		table.insert(choices, back)
		return { handled = true, node = { text = "뭘 선물할까요? (현금 → 체크카드 순으로 결제)", choices = choices } }
	elseif string.sub(cmd, 1, 2) == "g:" then
		if remote then
			return { handled = true }
		end
		local gid = string.sub(cmd, 3)
		local g = Social.GIFTS[gid]
		if not g then
			return { handled = true }
		end
		local pref = Citizens.giftPref(id, gid, g.cat, g.adult)
		local gv = vars(player, { gift = g.name })
		if pref == "refuse" then
			rec.gk[gid] = "refuse"
			return { handled = true, line = Citizens.giftLine(id, tier, "refuse", nil, gv) }
		end
		if not (ctx.spend and ctx.spend(player, g.price, string.format("선물 · %s → %s", g.name, c.name))) then
			return { handled = true, line = pickLine("noMoney", reg, v) .. string.format(" (%s)", won(g.price)) }
		end
		local gd = Social.gameDay(now())
		if rec.f.gday ~= gd then
			rec.f.gday = gd
			rec.f.gcount = 0
		end
		rec.f.gcount = (rec.f.gcount or 0) + 1
		sess.state.stats.gifts = (sess.state.stats.gifts or 0) + 1
		local line
		if rec.f.gcount >= Social.GIFT_SPAM_AT then
			award(player, sess, id, "spam")
			line = Citizens.giftLine(id, tier, "much", nil, gv)
		else
			local bday = isBirthday(c)
			local same = rec.lg == gid
			local amount, source = Social.giftGain(gid, pref, same, bday)
			local res = nil
			if source == "gift" then
				res = award(player, sess, id, "gift", { amount = amount, nocap = bday })
			elseif source == "giftbad" then
				award(player, sess, id, "giftbad")
			end
			local kind = if bday and pref ~= "dislike" then "bday" elseif same and pref ~= "dislike" then "again" else pref
			line = Citizens.giftLine(id, Social.tierOf(rec.a), kind, nil, gv)
			if res and (res.reason == "limit" or res.reason == "cap") then
				line ..= "\n(오늘은 호감도가 더 오르지 않아요)"
			end
		end
		rec.lg = gid
		rec.gk[gid] = pref
		meet(player, sess, id, rec, nil, "gift")
		return { handled = true, line = line }
	elseif cmd == "errand" then
		if remote then
			return { handled = true }
		end
		if rec.er then
			return { handled = true, line = pickLine("errandWaiting", reg, v) }
		end
		local eid, def = Citizens.errandFor(id)
		if not eid or not def then
			return { handled = true, line = pickLine("errandNo", reg, v) }
		end
		sess.pendingErrand = { id = id, eid = eid }
		return {
			handled = true,
			node = { text = if reg == "c" then def.c else def.p, choices = { { id = "soc:errand_ok", label = "좋아요, 다녀올게요!" }, { id = "soc:errand_no", label = "지금은 좀 바빠요" }, back } },
		}
	elseif cmd == "errand_ok" then
		local pe = sess.pendingErrand
		sess.pendingErrand = nil
		if not pe or pe.id ~= id or rec.er then
			return { handled = true }
		end
		local def = Citizens.ERRANDS[pe.eid]
		rec.er = { id = pe.eid, stage = "go", due = now() + Social.ERRAND_SECONDS, dest = def.dest }
		rec.f.help = nil
		local dlg = sess.dlg
		if dlg and dlg.id == id and dlg.pos then
			sess.errandPos[id] = dlg.pos
		end
		reindex(sess, id)
		markDirty(player, sess)
		setWaypoint(player, def.dest)
		notify(player, "info", "🤝 부탁 · " .. c.name, string.format("%s에서 %s 챙기기 (%d분)", destLabel(def.dest), def.item, Social.ERRAND_SECONDS // 60), { social = id })
		push(player, { kind = "errand", id = id, stage = "go", text = if reg == "c" then def.c else def.p, dest = def.dest, untilIn = Social.ERRAND_SECONDS })
		return { handled = true, line = pickLine("errandOk", reg, v) }
	elseif cmd == "errand_no" then
		sess.pendingErrand = nil
		return { handled = true, line = pickLine("errandNo", reg, v) }
	elseif cmd == "errand_done" then
		local line = completeErrand(player, sess, id)
		return { handled = true, line = line }
	elseif cmd == "invite" then
		local choices = inviteChoices(player, sess, id, remote)
		table.insert(choices, back)
		return { handled = true, node = { text = if reg == "c" then "뭐 하고 놀까?" else "어디 갈까요?", choices = choices } }
	elseif string.sub(cmd, 1, 4) == "inv:" then
		local kind = string.sub(cmd, 5)
		if not Social.INVITES[kind] then
			return { handled = true }
		end
		local line = tryInvite(player, sess, id, kind, remote)
		return { handled = true, line = line }
	elseif cmd == "dismiss" then
		if sess.comp and sess.comp.id == id then
			endCompanion(player, sess, "dismiss")
		end
		return { handled = true, line = pickLine("farewell", reg, v) }
	elseif cmd == "dance" then
		if remote or not inClub(player) then
			return { handled = true }
		end
		if (sess.danceCd[id] or 0) > os.clock() then
			return { handled = true, line = pickLine("danceTired", reg, v) }
		end
		sess.danceCd[id] = os.clock() + 30
		award(player, sess, id, "dance")
		meet(player, sess, id, rec, "club", "dance")
		sess.state.stats.dances = (sess.state.stats.dances or 0) + 1
		return { handled = true, line = pickLine("dance", reg, v), emote = "dance" }
	elseif cmd == "drink" then
		if remote or not inClub(player) then
			return { handled = true }
		end
		local price = if c.minor then SOFT_DRINK_PRICE else DRINK_PRICE
		local disc = Relationships.perk(player, "discount", "CLUB OCEAN 광안")
		price = math.floor(price * (1 - (disc or 0)) / 100) * 100
		local label = string.format("%s → %s", if c.minor then "에이드 한 잔" else "칵테일 한 잔", c.name)
		if not (ctx.spend and ctx.spend(player, price, label)) then
			return { handled = true, line = pickLine("noMoney", reg, v) .. string.format(" (%s)", won(price)) }
		end
		award(player, sess, id, "drink")
		meet(player, sess, id, rec, "club", "drink")
		return { handled = true, line = pickLine("drink", reg, v) }
	elseif cmd == "bday" then
		if not isBirthday(c) then
			return { handled = true }
		end
		local _, _, year = Social.kstDate(now())
		if rec.f.bdayYear == year then
			return { handled = true }
		end
		rec.f.bdayYear = year
		local known = rec.f.bdayKnown == true
		rec.f.bdayKnown = true
		award(player, sess, id, "bday", { mult = (if known then 1 else 0.6) * (if remote then 0.7 else 1) })
		push(player, { kind = "event", id = id, event = "birthday", text = c.name .. "의 생일을 축하했어요 🎂" })
		return { handled = true, line = pickLine(if known then "bdayKnown" else "bdayLucky", reg, v) }
	elseif cmd == "tip" then
		if tier < Social.TIER_FRIEND then
			return { handled = true }
		end
		return { handled = true, line = tipLine(player, sess, id) }
	elseif cmd == "compliment" then
		if remote then
			return { handled = true }
		end
		if (rec.up or 0) > now() then
			return { handled = true, line = Citizens.reactLine(id, tier, "upset", nil, v) }
		end
		local gd = Social.gameDay(now())
		if rec.f.cday == gd then
			return { handled = true, line = Citizens.complimentLine(id, tier, "again", nil, v) }
		end
		rec.f.cday = gd
		local outcome = Citizens.complimentOutcome(id, tier)
		if outcome == "dislike" then
			award(player, sess, id, "dislike")
		else
			local gain = Social.COMPLIMENT_GAIN[outcome] or 0
			if gain > 0 then
				award(player, sess, id, "compliment", { amount = gain })
			end
		end
		meet(player, sess, id, rec, nil, nil)
		local shy = outcome == "love" or outcome == "like"
		return { handled = true, line = Citizens.complimentLine(id, Social.tierOf(rec.a), outcome, nil, v), emote = if shy then "shy" else nil }
	elseif cmd == "number" then
		if remote then
			return { handled = true }
		end
		if rec.f.number then
			return { handled = true, line = Citizens.numberLine(id, tier, "already", nil, v) }
		end
		local gd = Social.gameDay(now())
		if rec.f.numAsk == gd then
			return { handled = true, line = Citizens.numberLine(id, tier, "later", nil, v) }
		end
		if math.random() >= Social.numberChance(rec.a, c.social) then
			rec.f.numAsk = gd
			markDirty(player, sess)
			return { handled = true, line = Citizens.numberLine(id, tier, if tier < Social.NUMBER_ASK_TIER then "stranger" else "no", nil, v), emote = "refuse" }
		end
		rec.f.numAsk = nil
		giveNumber(player, sess, id, rec, "ask")
		award(player, sess, id, "number")
		meet(player, sess, id, rec, nil, nil)
		return { handled = true, line = Citizens.numberLine(id, Social.tierOf(rec.a), "yes", nil, v), emote = "phone" }
	end
	return { handled = false }
end

-------------------------------------------------------------------------------------------------
-- Citizen dialogs (the Dialog remote; choices return as PhoneAction "dialogChoice")
-------------------------------------------------------------------------------------------------
local function sendDialog(player: Player, sess: Sess, id: string, node: Node, remote: boolean, prefix: string?)
	local c = citizen(id)
	local dialogRemote = ctx.remotes and ctx.remotes.Dialog
	if not c or not dialogRemote or player.Parent ~= Players then
		return
	end
	local choices: { [string]: boolean } = { close = true }
	local out = {}
	for _, ch in node.choices do
		if not choices[ch.id] then
			choices[ch.id] = true
			table.insert(out, { id = ch.id, label = ch.label })
		end
	end
	if not choices.bye then
		choices.bye = true
		table.insert(out, { id = "bye", label = if remote then "전화 끊기" else "안녕!" })
	end
	local prev = sess.dlg
	sess.dlg = {
		id = id,
		choices = choices,
		remote = remote,
		pos = if prev and prev.id == id then prev.pos else nil,
		openedAt = os.clock(),
	}
	local a = affinityOf(sess, id)
	local tier, T = tierInfo(a)
	dialogRemote:FireClient(player, {
		npcId = id,
		name = c.name,
		role = string.format("%s · %s %s", c.job or "", T.icon, T.name),
		portraitColor = Color3.fromRGB(c.accent[1], c.accent[2], c.accent[3]),
		text = (if prefix and prefix ~= "" then prefix .. "\n" else "") .. node.text,
		choices = out,
		remote = if remote then true else nil,
		citizen = true,
		affinity = a,
		tier = tier,
		tierName = T.name,
		emote = node.emote,
	})
end

local function closeDialog(player: Player, sess: Sess, fire: boolean)
	if not sess.dlg then
		return
	end
	sess.dlg = nil
	sess.q = nil
	sess.pendingErrand = nil
	if fire and player.Parent == Players and ctx.remotes and ctx.remotes.Dialog then
		ctx.remotes.Dialog:FireClient(player, { close = true })
	end
end

-- Counts talks to one NPC; true when this one is spam (penalised once per window).
local function spamCheck(player: Player, sess: Sess, id: string): boolean
	local t = sess.talks[id]
	local nowc = os.clock()
	if not t or nowc - t.t0 > Social.SPAM_WINDOW then
		t = { n = 0, t0 = nowc, warned = false }
		sess.talks[id] = t
	end
	t.n += 1
	if t.n > Social.SPAM_TALKS then
		if not t.warned then
			t.warned = true
			award(player, sess, id, "spam")
		end
		return true
	end
	return false
end

-- Workplace visit: talking to someone while they work at their workplace (once per game day).
local function visitBonus(player: Player, sess: Sess, id: string): string?
	local c = citizen(id)
	if not c then
		return nil
	end
	local area, act = Citizens.whereNow(id, clockNow())
	if act ~= "work" or (not c.key and area ~= c.work) then
		return nil
	end
	local res = award(player, sess, id, "visit")
	if res.delta > 0 then
		return pickLine("visit", Citizens.register(Social.tierOf(affinityOf(sess, id))), vars(player))
	end
	return nil
end

-- The friend of `id` the player is closest to, when that is at least 친한 사이 (else nil).
local function friendIntro(sess: Sess, id: string): string?
	local best, bestA = nil, Social.tierMin(Social.TIER_CLOSE) - 1e-6
	for _, f in Citizens.friendsOf(id) do
		local r = sess.state.npcs[f]
		if r and r.a > bestA then
			best, bestA = f, r.a
		end
	end
	return best
end

local function greetingFor(player: Player, sess: Sess, id: string, remote: boolean): string
	local c = citizen(id)
	local rec = recOf(sess, id, false)
	local a = affinityOf(sess, id)
	local tier = Social.tierOf(a)
	local reg = Citizens.register(tier)
	local v = vars(player)
	if remote then
		return pickLine("callHello", reg, v) .. " " .. Citizens.smallTalk(id, tier, clockNow(), nil, v, true)
	end
	local text = Citizens.greeting(id, tier, clockNow(), memoryOf(player, rec), v)
	if rec and rec.f.broken then
		rec.f.broken = nil
	end
	if (not rec or (rec.met or 0) == 0) and c then
		text ..= "\n" .. Citizens.fill(Citizens.pick(LINES.intro.p) or "", { full = Social.josa(c.fullName, "예요.", "이에요.") })
		-- a friend of someone you are close to has heard about you (once per NPC)
		local f = rec and not rec.f.intro and friendIntro(sess, id)
		if f then
			rec.f.intro = f
			text ..= "\n" .. Citizens.introLine(id, f, v)
			award(player, sess, id, "intro")
		end
	elseif c and not c.key and tier >= Social.TIER_ACQ then
		local tl = Citizens.togetherLine(id, tier, clockNow())
		if tl then
			text ..= "\n" .. tl -- "오늘은 도현이랑 같이 나왔어요 ㅎㅎ"
		end
	end
	if c and isBirthday(c) and tier >= Social.TIER_ACQ then
		text ..= "\n" .. pickLine("todayBday", reg, v)
		if rec then
			rec.f.bdayKnown = true
		end
	end
	return text
end

local function openCitizenDialog(player: Player, sess: Sess, id: string, pos: Vector3?, remote: boolean)
	local c = citizen(id)
	if not c then
		return
	end
	if not remote and spamCheck(player, sess, id) then
		push(player, { kind = "line", id = id, text = Citizens.reactLine(id, Social.tierOf(affinityOf(sess, id)), "spam", nil, vars(player)), emote = "refuse" })
		return
	end
	local rec = recOf(sess, id, true)
	local text = greetingFor(player, sess, id, remote)
	if not remote then
		local extra = visitBonus(player, sess, id)
		if extra then
			text ..= "\n" .. extra
		end
		award(player, sess, id, "greet")
	end
	local area = if not remote then (Citizens.whereNow(id, clockNow())) else nil
	meet(player, sess, id, rec, area, "talk")
	sess.giftPage = 0
	sess.dlg = { id = id, choices = {}, remote = remote, pos = pos, openedAt = os.clock() }
	sendDialog(player, sess, id, { text = text, choices = socialChoices(player, sess, id, remote), emote = "greet" }, remote)
end

local function stillNear(player: Player, dlg: any): boolean
	if dlg.remote then
		return true
	end
	if dlg.pos then
		return near(player, dlg.pos, DIALOG_REACH)
	end
	local c = citizen(dlg.id)
	if c and c.key then
		local p = keyNpcPos(dlg.id)
		return near(player, p, (G.NPC_TALK_RADIUS or 16) + 20)
	end
	return true
end

local function citizenChoice(player: Player, p: any)
	local sess = sessions[player]
	if not sess or not sess.ready then
		return
	end
	local dlg = sess.dlg
	local id = Util.str(p.npcId, 40)
	local choiceId = Util.str(p.choiceId or p.choice, 60)
	if not dlg or not id or not choiceId or dlg.id ~= id or not dlg.choices[choiceId] then
		return
	end
	if choiceId == "close" then
		closeDialog(player, sess, false)
		return
	elseif choiceId == "bye" then
		closeDialog(player, sess, true)
		return
	end
	if not stillNear(player, dlg) then
		closeDialog(player, sess, true)
		return
	end
	if not Util.cooldown(player, "soc:choice", 0.25) then
		return
	end
	local res = handle(player, sess, id, choiceId, dlg.remote, false)
	if not res.handled then
		return
	end
	if res.close then
		sendDialog(player, sess, id, { text = res.line or "…", choices = {}, emote = "refuse" }, dlg.remote)
	elseif res.node then
		sendDialog(player, sess, id, res.node, dlg.remote, res.line)
	else
		local node = rootNode(player, sess, id, dlg.remote)
		node.emote = res.emote
		sendDialog(player, sess, id, node, dlg.remote, res.line)
	end
end

-------------------------------------------------------------------------------------------------
-- SocialAction (client -> server)
-------------------------------------------------------------------------------------------------
local ACTION_CD = { greet = 1.5, talk = 0.8, reply = 0.3, gift = 1.5, invite = 2, hangout = 2, dance = 3, drink = 3, errand = 1, bday = 2, call = 2, textReply = 0.5, dismiss = 1, compliment = 1.5, number = 2 }

local function bucket(sess: Sess): boolean
	local t = os.clock()
	sess.tokens = math.min(10, sess.tokens + (t - sess.tokT) * 4)
	sess.tokT = t
	if sess.tokens < 1 then
		return false
	end
	sess.tokens -= 1
	return true
end

-- (ok, position of the NPC)
local function validateNear(player: Player, sess: Sess, id: string, pos: any): (boolean, Vector3?)
	local root = Util.rootPosition(player)
	if not root then
		return false, nil
	end
	local c = citizen(id)
	if not c then
		return false, nil
	end
	local comp = sess.comp
	if comp and comp.id == id then
		return true, root -- the companion walks with you
	end
	if c.key then
		local at, exact = keyNpcPos(id)
		if not at then
			return false, nil
		end
		local reach = (G.NPC_TALK_RADIUS or 16) + KEY_SLACK + (if exact then 0 else 25)
		return (root - at).Magnitude <= reach, at
	end
	local p = vec(pos)
	if not p or (root - p).Magnitude > TALK_REACH then
		return false, nil
	end
	if not Citizens.plausible(id, p, clockNow(), areaPos, 240) then
		return false, nil
	end
	local seen = sess.seen[id]
	local t = os.clock()
	if seen and t - seen.t < 30 and (seen.pos - p).Magnitude > 40 * (t - seen.t) + 30 then
		return false, nil
	end
	sess.seen[id] = { pos = p, t = t }
	return true, p
end

local function quickLine(player: Player, sess: Sess, id: string, text: string, emote: string?)
	local a = affinityOf(sess, id)
	push(player, { kind = "line", id = id, text = text, emote = emote, tier = (Social.tierOf(a)), a = a })
end

local actions: { [string]: (Player, Sess, string, any) -> () } = {}

actions.greet = function(player, sess, id, p)
	local ok = validateNear(player, sess, id, p.pos)
	if not ok then
		return
	end
	if spamCheck(player, sess, id) then
		quickLine(player, sess, id, Citizens.reactLine(id, Social.tierOf(affinityOf(sess, id)), "spam", nil, vars(player)), "refuse")
		return
	end
	local rec = recOf(sess, id, true)
	local tier = Social.tierOf(rec.a)
	local text
	if (rec.met or 0) == 0 or now() - (rec.last or 0) > MEET_GAP then
		text = greetingFor(player, sess, id, false)
	elseif (rec.up or 0) > now() then
		text = Citizens.reactLine(id, tier, "upset", nil, vars(player))
	else
		text = Citizens.smallTalk(id, tier, clockNow(), nil, vars(player), (rec.met or 0) > 0)
	end
	local extra = visitBonus(player, sess, id)
	if extra then
		text ..= " " .. extra
	end
	if rec.er and rec.er.stage == "back" then
		local l = completeErrand(player, sess, id)
		if l then
			text = l
		end
	end
	award(player, sess, id, "greet")
	meet(player, sess, id, rec, (Citizens.whereNow(id, clockNow())), nil)
	quickLine(player, sess, id, text, "greet")
end

actions.talk = function(player, sess, id, p)
	local c = citizen(id)
	if c and c.key and G.NPCS and G.NPCS[id] and ctx.openDialog then
		pcall(ctx.openDialog, player, id, false) -- key NPCs have their own dialog (with the soc: menu)
		return
	end
	-- somebody who went down in a fight (GwangalliGameplay/Fight: KO -> hospital) does not talk
	if ctx.fight and type(ctx.fight.inHospital) == "function" and ctx.fight.inHospital(id) then
		return
	end
	local ok, at = validateNear(player, sess, id, p.pos)
	if not ok then
		return
	end
	openCitizenDialog(player, sess, id, at, false)
end

actions.call = function(player, sess, id, _p)
	local c = citizen(id)
	local rec = recOf(sess, id, false)
	if not c or not rec or not rec.f.number or Social.tierOf(rec.a) < Social.NUMBER_ASK_TIER then
		return
	end
	local cid = contactFor(id)
	if cid and c.key and ctx.openDialog then
		pcall(ctx.openDialog, player, id, true)
		return
	end
	openCitizenDialog(player, sess, id, nil, true)
end

local function viaChoice(player: Player, sess: Sess, id: string, choiceId: string, remote: boolean)
	local res = handle(player, sess, id, choiceId, remote, false)
	if res.handled and res.line then
		quickLine(player, sess, id, res.line, if res.close then "refuse" else res.emote)
	end
	return res
end

actions.reply = function(player, sess, id, p)
	local n = Util.int(p.choice, 1, 3)
	if not n or not sess.q or sess.q.id ~= id then
		return
	end
	viaChoice(player, sess, id, "soc:r:" .. n, sess.dlg ~= nil and sess.dlg.remote == true)
end

actions.gift = function(player, sess, id, p)
	local gid = Util.str(p.gift, 32)
	if not gid or not Social.GIFTS[gid] then
		return
	end
	if not validateNear(player, sess, id, p.pos) then
		return
	end
	viaChoice(player, sess, id, "soc:g:" .. gid, false)
end

actions.invite = function(player, sess, id, p)
	local kind = Util.str(p.kind, 16)
	if not kind or not Social.INVITES[kind] then
		return
	end
	if not validateNear(player, sess, id, p.pos) then
		return
	end
	viaChoice(player, sess, id, "soc:inv:" .. kind, false)
end

actions.hangout = function(player, sess, id, p)
	local op = p.op
	if op == "stop" then
		if sess.comp and sess.comp.id == id then
			endCompanion(player, sess, "dismiss")
		end
		return
	end
	local c = citizen(id)
	local rec = recOf(sess, id, false)
	if not c or not rec or not canCompanion(c) then
		return
	end
	local tier = Social.tierOf(rec.a)
	if op == "call" then
		if tier < Social.CALL_TIER or not rec.f.number then
			return
		end
		viaChoice(player, sess, id, "soc:inv:now", true)
		return
	end
	if tier < Social.COMPANION_TIER or not validateNear(player, sess, id, p.pos) then
		return
	end
	viaChoice(player, sess, id, "soc:inv:now", false)
end

actions.dance = function(player, sess, id, p)
	local comp = sess.comp
	if not (comp and comp.id == id) and not Citizens.atClub(id, clockNow()) then
		return
	end
	if not inClub(player) then
		return
	end
	local _ = p
	viaChoice(player, sess, id, "soc:dance", false)
end

actions.drink = function(player, sess, id, _p)
	local comp = sess.comp
	if not (comp and comp.id == id) and not Citizens.atClub(id, clockNow()) then
		return
	end
	viaChoice(player, sess, id, "soc:drink", false)
end

actions.errand = function(player, sess, id, p)
	local op = p.op
	if op == "accept" then
		local rec = recOf(sess, id, false)
		if not rec or (Social.tierOf(rec.a) < Social.TIER_ACQ and not rec.f.help) then
			return -- strangers do not hand you errands (same gate as the dialog)
		end
		if not validateNear(player, sess, id, p.pos) then
			return
		end
		if not sess.pendingErrand or sess.pendingErrand.id ~= id then
			local eid = Citizens.errandFor(id)
			sess.pendingErrand = eid and { id = id, eid = eid } or nil
		end
		viaChoice(player, sess, id, "soc:errand_ok", false)
	elseif op == "decline" then
		sess.pendingErrand = nil
	elseif op == "done" then
		if not validateNear(player, sess, id, p.pos) then
			return
		end
		viaChoice(player, sess, id, "soc:errand_done", false)
	end
end

actions.compliment = function(player, sess, id, p)
	if not validateNear(player, sess, id, p.pos) then
		return
	end
	viaChoice(player, sess, id, "soc:compliment", false)
end

actions.number = function(player, sess, id, p)
	if not validateNear(player, sess, id, p.pos) then
		return
	end
	viaChoice(player, sess, id, "soc:number", false)
end

actions.bday = function(player, sess, id, p)
	if not validateNear(player, sess, id, p.pos) then
		return
	end
	viaChoice(player, sess, id, "soc:bday", false)
end

actions.dismiss = function(player, sess, id, _p)
	if sess.comp and sess.comp.id == id then
		endCompanion(player, sess, "dismiss")
	end
end

actions.textReply = function(player, sess, id, p)
	local mid = Util.int(p.msg, 0, 1e9)
	local choice = p.choice
	if not mid or (choice ~= "accept" and choice ~= "decline") then
		return
	end
	for _, m in sess.state.inbox do
		if m.id == mid and m.from == id and m.state == "new" then
			local c = citizen(id)
			if choice == "decline" or not m.invite or now() > m.invite.untilT then
				m.state = if choice == "decline" then "declined" else "expired"
			else
				m.state = "accepted"
				if c and m.invite.dest then
					makePromise(player, sess, id, m.invite.kind, m.invite.dest, m.invite.untilT)
				end
			end
			markDirty(player, sess)
			push(player, { kind = "text", msg = msgView(m) })
			return
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Snapshot (GetSocial / SocialState "snapshot")
-------------------------------------------------------------------------------------------------
local function friendViews(sess: Sess, id: string): { any }?
	local fl = Citizens.friendsOf(id)
	if #fl == 0 then
		return nil
	end
	local out = {}
	for _, f in fl do
		local fc = citizen(f)
		local r = sess.state.npcs[f]
		if fc then
			table.insert(out, { id = f, name = fc.name, met = r ~= nil and (r.met or 0) > 0, a = r and r.a or 0 })
		end
	end
	return out
end

function Relationships.snapshot(player: Player): any?
	local sess = sessions[player]
	if not sess or not sess.ready then
		return nil
	end
	local st = sess.state
	local npcs = {}
	local friends = {}
	local contacts = {}
	local birthdays = {}
	local clock = clockNow()
	for id, rec in st.npcs do
		local c = citizen(id)
		if c then
			local tier = Social.tierOf(rec.a)
			local gk = {}
			for g, x in rec.gk do
				gk[g] = x
			end
			npcs[id] = {
				a = rec.a,
				tier = tier,
				met = rec.met,
				last = rec.last,
				area = rec.la,
				number = rec.f.number == true,
				gifts = gk,
				errand = if rec.er then { id = rec.er.id, stage = rec.er.stage, dest = rec.er.dest, untilIn = math.max(0, rec.er.due - now()) } else nil,
				promise = if rec.pr then { kind = rec.pr.kind, dest = rec.pr.dest, untilIn = math.max(0, rec.pr.due - now()) } else nil,
				secret = if rec.f.secret == "pending" then c.secret else nil,
				capLeft = Social.capLeft(rec, now()),
			}
			if tier >= Social.TIER_FRIEND then
				table.insert(friends, id)
			end
			if rec.f.number then
				local T = Social.TIERS[tier]
				local wa = c.work and Citizens.AREAS[c.work] or (c.post and Citizens.AREAS[c.post])
				local where, whereArea, _, here = Citizens.status(id, clock)
				table.insert(contacts, {
					id = id,
					name = c.name,
					job = c.job,
					a = rec.a,
					tier = tier,
					tierName = T.name,
					icon = T.icon,
					color = c.accent,
					canCall = true,
					canHangout = tier >= Social.CALL_TIER and canCompanion(c),
					workplace = wa and wa.label or nil,
					friends = friendViews(sess, id), -- their crew friends { {id, name, met, a} }
					where = where, -- "해변 · 산책 중" / "해변 · 도현이랑 사진 찍는 중" (Citizens.status)
					whereArea = whereArea,
					whereDest = whereArea and Citizens.AREAS[whereArea] and Citizens.AREAS[whereArea].dest or nil,
					here = here, -- out and about right now (worth going there)
				})
			end
			if rec.f.bdayKnown then
				table.insert(birthdays, { id = id, name = c.name, m = c.bday[1], d = c.bday[2] })
			end
		end
	end
	table.sort(friends, function(x, y)
		return st.npcs[x].a > st.npcs[y].a
	end)
	table.sort(contacts, function(x, y)
		return x.a > y.a
	end)
	local inbox = {}
	for i = math.max(1, #st.inbox - 9), #st.inbox do
		table.insert(inbox, msgView(st.inbox[i]))
	end
	local comp = sess.comp
	local compView: any = false
	if comp then
		local c = citizen(comp.id)
		compView = { id = comp.id, name = c and c.name or comp.id, dest = comp.dest, untilIn = math.max(0, math.floor(comp.untilT - os.clock())), tier = (Social.tierOf(affinityOf(sess, comp.id))) }
	end
	return {
		kind = "snapshot",
		v = Social.VERSION,
		npcs = npcs,
		friends = friends,
		contacts = contacts,
		birthdays = birthdays,
		companion = compView,
		inbox = inbox,
		stats = table.clone(st.stats),
		gameDay = Social.gameDay(now()),
	}
end

-------------------------------------------------------------------------------------------------
-- Public server API
-------------------------------------------------------------------------------------------------
local function sessOf(player: any): Sess?
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	local s = sessions[player]
	return if s and s.ready then s else nil
end

function Relationships.ready(player: Player): boolean
	return sessOf(player) ~= nil
end

function Relationships.affinity(player: Player, id: string): (number, number)
	local sess = sessOf(player)
	local c = citizen(id)
	if not sess or not c then
		return 0, 1
	end
	local a = affinityOf(sess, id)
	return a, (Social.tierOf(a))
end

function Relationships.tier(player: Player, id: string): (number, string)
	local a, t = Relationships.affinity(player, id)
	local _ = a
	return t, Social.TIERS[t].name
end

function Relationships.isFriend(player: Player, id: string): boolean
	local _, t = Relationships.affinity(player, id)
	return t >= Social.TIER_FRIEND
end

function Relationships.friends(player: Player, minTier: number?): { any }
	local sess = sessOf(player)
	local out = {}
	if not sess then
		return out
	end
	local lim = minTier or Social.TIER_FRIEND
	for id, rec in sess.state.npcs do
		local c = citizen(id)
		local t = Social.tierOf(rec.a)
		if c and t >= lim then
			table.insert(out, { id = id, name = c.name, a = rec.a, tier = t })
		end
	end
	table.sort(out, function(x, y)
		return x.a > y.a
	end)
	return out
end

function Relationships.award(player: Player, id: string, source: string, amount: number?): (number, number, number)
	local sess = sessOf(player)
	if not sess or not citizen(id) or not Social.SOURCES[source] then
		return 0, 0, 1
	end
	local opts = nil
	if type(amount) == "number" and amount == amount then
		opts = { amount = math.clamp(amount, -10, 10) }
	end
	local res = award(player, sess, id, source, opts)
	return res.delta, res.after, res.tierTo
end

-- Test harness only (workspace.GwangalliStreetLifeDebug): set an affinity outright (tier perks such as
-- the number exchange fire as if it had been earned).
function Relationships.debugSet(player: Player, id: string, a: number): (boolean, number)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") ~= true then
		return false, 0
	end
	local sess = sessOf(player)
	if not sess or not citizen(id) or type(a) ~= "number" then
		return false, 0
	end
	local rec = recOf(sess, id, true)
	local pkBefore = rec.pk or 1
	local from = Social.tierOf(rec.a)
	rec.a = Social.clampA(a)
	local to = Social.tierOf(rec.a)
	markDirty(player, sess)
	push(player, { kind = "affinity", id = id, a = rec.a, delta = 0, tier = to, source = "talk", reason = "test" })
	if to ~= from then
		onTierChange(player, sess, id, rec, from, to, to > pkBefore)
	end
	return true, to
end

-- A joint activity (club / homes / NPC code): the companion and/or explicit ids get `activity`.
function Relationships.joint(player: Player, activity: string, ids: { string }?): { [string]: number }
	local sess = sessOf(player)
	local out = {}
	if not sess or not Social.SOURCES[activity] or (Social.SOURCES[activity].base or 0) < 0 then
		return out
	end
	local list = {}
	if sess.comp then
		table.insert(list, sess.comp.id)
	end
	if type(ids) == "table" then
		for i, id in ids do
			if i > 6 then
				break
			end
			if type(id) == "string" and citizen(id) and not table.find(list, id) then
				table.insert(list, id)
			end
		end
	end
	for _, id in list do
		local res = award(player, sess, id, activity)
		local rec = recOf(sess, id, true)
		meet(player, sess, id, rec, nil, activity)
		if activity == "housewarming" then
			rec.f.home = true
		end
		out[id] = res.delta
	end
	return out
end

function Relationships.companion(player: Player): (string?, any)
	local sess = sessOf(player)
	local comp = sess and sess.comp
	if not comp then
		return nil, nil
	end
	local c = citizen(comp.id)
	return comp.id, { name = c and c.name, tier = (Social.tierOf(affinityOf(sess :: Sess, comp.id))), since = os.clock() - comp.since, dest = comp.dest }
end

local function workplaceDest(c: any): string?
	if c.key then
		local def = G.NPCS and G.NPCS[c.id]
		if def and def.dest then
			return def.dest
		end
		local a = c.post and Citizens.AREAS[c.post]
		return a and a.dest or nil
	end
	local a = c.work and Citizens.AREAS[c.work]
	return a and a.dest or nil
end

function Relationships.perk(player: Player, kind: string, arg: any?): any
	local sess = sessOf(player)
	if not sess then
		return if kind == "clubEntry" then false else 0
	end
	if kind == "discount" then
		local best = 0
		for id, rec in sess.state.npcs do
			local t = Social.tierOf(rec.a)
			if t >= Social.TIER_FRIEND then
				local c = citizen(id)
				if c then
					local def = G.NPCS and G.NPCS[id]
					local match = arg == id or (arg ~= nil and arg == workplaceDest(c)) or (def and def.job ~= nil and arg == def.job)
					if match then
						best = math.max(best, if t >= Social.TIER_BESTIE then 0.2 else 0.1)
					end
				end
			end
		end
		return best
	elseif kind == "clubEntry" then
		if os.clock() < (sess.clubGuestUntil or 0) then
			return true
		end
		local comp = sess.comp
		if comp and Social.tierOf(affinityOf(sess, comp.id)) >= Social.TIER_FRIEND then
			return true
		end
		for id in CLUB_PEOPLE do
			if Social.tierOf(affinityOf(sess, id)) >= Social.TIER_FRIEND then
				return true
			end
		end
		return false
	elseif kind == "vipDiscount" then
		local best = 0
		for id in CLUB_PEOPLE do
			local t = Social.tierOf(affinityOf(sess, id))
			if t >= Social.TIER_BESTIE then
				best = math.max(best, 0.2)
			elseif t >= Social.TIER_FRIEND then
				best = math.max(best, 0.1)
			end
		end
		return best
	elseif kind == "tip" then
		if type(arg) ~= "string" or not citizen(arg) or Social.tierOf(affinityOf(sess, arg)) < Social.TIER_FRIEND then
			return nil
		end
		return tipLine(player, sess, arg)
	end
	return nil
end

-- For key-NPC dialogs: memory-aware greeting + the daily greet / workplace visit bookkeeping.
function Relationships.onTalk(player: Player, id: string, remote: boolean?): (string?, any)
	local sess = sessOf(player)
	if not sess or not citizen(id) then
		return nil, nil
	end
	local rec = recOf(sess, id, true)
	local text = greetingFor(player, sess, id, remote == true)
	if not remote then
		local extra = visitBonus(player, sess, id)
		if extra then
			text ..= "\n" .. extra
		end
		award(player, sess, id, "greet")
		if rec.er and rec.er.stage == "back" then
			local l = completeErrand(player, sess, id)
			if l then
				text ..= "\n" .. l
			end
		end
	end
	local c = citizen(id)
	meet(player, sess, id, rec, if remote then nil else (c and c.post), nil)
	local a = rec.a
	local tier, T = tierInfo(a)
	return text, { a = a, tier = tier, tierName = T.name, icon = T.icon, met = rec.met }
end

function Relationships.greeting(player: Player, id: string): string?
	local sess = sessOf(player)
	if not sess or not citizen(id) then
		return nil
	end
	return greetingFor(player, sess, id, false)
end

function Relationships.smallTalk(player: Player, id: string): string?
	local sess = sessOf(player)
	if not sess or not citizen(id) then
		return nil
	end
	local rec = recOf(sess, id, false)
	return Citizens.smallTalk(id, Social.tierOf(affinityOf(sess, id)), clockNow(), nil, vars(player), rec ~= nil and (rec.met or 0) > 0)
end

function Relationships.menuChoice(player: Player, id: string): any?
	local sess = sessOf(player)
	if not sess or not citizen(id) then
		return nil
	end
	local T = Social.TIERS[Social.tierOf(affinityOf(sess, id))]
	return { id = "soc:menu", label = string.format("💕 친해지기 (%s %s)", T.icon, T.name) }
end

function Relationships.choices(player: Player, id: string, remote: boolean?): { any }
	local sess = sessOf(player)
	if not sess or not citizen(id) then
		return {}
	end
	return socialChoices(player, sess, id, remote == true)
end

function Relationships.handleChoice(player: Player, id: string, choiceId: string, remote: boolean?): any
	local sess = sessOf(player)
	if not sess or type(choiceId) ~= "string" or not citizen(id) then
		return { handled = false }
	end
	return handle(player, sess, id, choiceId, remote == true, true)
end

function Relationships.openDialog(player: Player, id: string, pos: any?, remote: boolean?)
	local sess = sessOf(player)
	local c = citizen(id)
	if not sess or not c then
		return
	end
	if c.key and G.NPCS and G.NPCS[id] and ctx.openDialog then
		pcall(ctx.openDialog, player, id, remote == true)
		return
	end
	openCitizenDialog(player, sess, id, vec(pos), remote == true)
end

-------------------------------------------------------------------------------------------------
-- Persistence (fallback DataStore; see the header)
-------------------------------------------------------------------------------------------------
local function keyOf(player: Player): string
	return Social.KEY_PREFIX .. tostring(player.UserId)
end

local function loadSide(player: Player): (boolean, any)
	local s = store
	if not storeEnabled or not s then
		return true, nil
	end
	for attempt = 1, 3 do
		local ok, res = pcall(s.GetAsync, s, keyOf(player))
		if ok then
			return true, res
		end
		warn(string.format("[GwangalliSocial] load %s failed (try %d): %s", player.Name, attempt, tostring(res)))
		if attempt < 3 then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

local function saveSide(player: Player, sess: Sess): boolean
	local s = store
	if profileHoldsSocial or not storeEnabled or not s or sess.noSave or not sess.dirty then
		return true
	end
	local snap = Util.deepCopy(sess.state)
	sess.dirty = false
	local merged: any = nil
	local ok, err = pcall(function()
		s:UpdateAsync(keyOf(player), function(old: any)
			local base = if old ~= nil then Social.sanitize(old, os.time(), nil) else nil
			merged = Social.merge(base, snap)
			return merged
		end)
	end)
	if not ok then
		sess.dirty = true
		warn(string.format("[GwangalliSocial] save %s failed: %s", player.Name, tostring(err)))
		return false
	end
	if merged and type(merged.npcs) == "table" then
		for id, r in merged.npcs do
			local mine = sess.state.npcs[id]
			if not mine or (r.u or 0) > (mine.u or 0) then
				sess.state.npcs[id] = r
			end
		end
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- Player lifecycle
-------------------------------------------------------------------------------------------------
local function newSession(state: any, noSave: boolean): Sess
	return {
		state = state,
		ready = false,
		noSave = noSave,
		dirty = false,
		comp = nil,
		dlg = nil,
		q = nil,
		pendingErrand = nil,
		giftPage = 0,
		seen = {},
		talks = {},
		inviteCd = {},
		danceCd = {},
		errandPos = {},
		lastTextFrom = {},
		active = {},
		tokens = 10,
		tokT = os.clock(),
		nextText = os.clock() + math.random(150, 260),
		clubGuestUntil = 0,
		jointT = 0,
	}
end

local attaching: { [Player]: boolean } = {}

local function attach(player: Player)
	if attaching[player] or sessions[player] then
		return
	end
	attaching[player] = true
	local d = Profiles.wait(player, 120)
	if not d or player.Parent ~= Players then
		attaching[player] = nil
		return
	end
	local t = now()
	local fromProfile = if type(d.social) == "table" then Social.sanitize(d.social, t, nil) else nil
	local side = nil
	local noSave = false
	if not profileHoldsSocial or fromProfile == nil then
		local ok, raw = loadSide(player)
		if not ok then
			noSave = true
		elseif raw ~= nil then
			side = Social.sanitize(raw, t, nil)
		end
	end
	attaching[player] = nil
	if player.Parent ~= Players then
		return
	end
	local st = Social.sanitize(Social.merge(fromProfile, side), t, Citizens.starts())
	for _, rec in st.npcs do
		Social.decay(rec, t)
		if Social.tierOf(rec.a) >= Social.NUMBER_TIER then
			rec.f.number = true -- seeded friends (민지 / 준호) and older saves already have each other's number
		end
	end
	d.social = st
	local sess = newSession(st, noSave)
	sessions[player] = sess
	for id in st.npcs do
		reindex(sess, id)
	end
	sess.ready = true
	player:SetAttribute(Social.Attr.Companion, "")
	player:SetAttribute(Social.Attr.CompanionTier, 0)
	player:SetAttribute(Social.Attr.Ready, true)
	push(player, Relationships.snapshot(player))
	if noSave then
		warn("[GwangalliSocial] " .. player.Name .. ": relationships could not be loaded; this session's changes will not be saved")
	end
end

local function detach(player: Player)
	attaching[player] = nil
	local sess = sessions[player]
	if not sess then
		return
	end
	sess.comp = nil
	sess.dlg = nil
	sessions[player] = nil
	task.spawn(function()
		local ok, err = pcall(saveSide, player, sess)
		if not ok then
			warn("[GwangalliSocial] final save failed: " .. tostring(err))
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Ticks
-------------------------------------------------------------------------------------------------
local function companionTick(player: Player, sess: Sess)
	local comp = sess.comp
	if not comp then
		return
	end
	local t = os.clock()
	local rec = recOf(sess, comp.id, true)
	if t > comp.untilT then
		endCompanion(player, sess, "time")
		return
	end
	if rec.a < Social.tierMin(Social.COMPANION_TIER) - 8 then
		endCompanion(player, sess, "upset")
		return
	end
	if not Util.rootPosition(player) then
		return
	end
	if t - comp.hangT >= Social.HANGOUT_TICK then
		comp.hangT = t
		award(player, sess, comp.id, "hangout")
	end
	if not comp.clubbed and inClub(player) then
		comp.clubbed = true
		award(player, sess, comp.id, "club")
		meet(player, sess, comp.id, rec, "club", "club")
		sess.clubGuestUntil = math.max(sess.clubGuestUntil, os.clock() + 600)
		quickLine(player, sess, comp.id, Citizens.smallTalk(comp.id, Social.tierOf(rec.a), 23, nil, vars(player)), "cheer")
	end
	if not comp.tabled and player:GetAttribute("ClubVIPTable") == true and inClub(player) then
		comp.tabled = true
		award(player, sess, comp.id, "table")
	end
	if not comp.homed and atHome(player) then
		comp.homed = true
		if not rec.f.home then
			rec.f.home = true
			award(player, sess, comp.id, "housewarming")
			push(player, { kind = "event", id = comp.id, event = "housewarming", text = "첫 집들이! 🏠" })
		else
			award(player, sess, comp.id, "home")
		end
		meet(player, sess, comp.id, rec, nil, "home")
	end
	if comp.dest and not comp.arrived and comp.source ~= "home" then
		if arrivedAt(player, comp.source, comp.dest) then
			comp.arrived = true
			if comp.source and comp.source ~= "club" then
				award(player, sess, comp.id, comp.source)
				meet(player, sess, comp.id, rec, nil, comp.source)
			end
			local c = citizen(comp.id)
			notify(player, "info", "📍 도착!", string.format("%s · %s에서 즐거운 시간 💕", c and c.name or "", destLabel(comp.dest)), { social = comp.id })
		end
	end
end

-- A text from a friend now and then (club invitations in the evening, meet-ups by day, help).
local DAY_KINDS = { "beach", "cafe", "meal", "karaoke", "bowling", "help" }
local function textTick(player: Player, sess: Sess)
	if os.clock() < sess.nextText then
		return
	end
	sess.nextText = os.clock() + math.random(Social.TEXT_GAP[1], Social.TEXT_GAP[2])
	local pool = {}
	for id, rec in sess.state.npcs do
		local c = citizen(id)
		local tier = Social.tierOf(rec.a)
		if c and tier >= Social.NUMBER_ASK_TIER and rec.f.number and not (sess.comp and sess.comp.id == id) and os.clock() - (sess.lastTextFrom[id] or -1e9) > 900 then
			for _ = 1, (if tier >= Social.TIER_FRIEND then 3 else 1) do
				table.insert(pool, id)
			end
		end
	end
	if #pool == 0 then
		return
	end
	local id = pool[math.random(1, #pool)]
	local c = citizen(id)
	local rec = recOf(sess, id, true)
	local clock = clockNow()
	if Social.tierOf(rec.a) < Social.TIER_CLOSE then
		-- acquaintances only text to lure you to the club in the evening
		if canCompanion(c) and Citizens.isEvening(clock) and (c.club or 0) > 0 and not c.minor then
			local inv = Social.INVITES.club
			sendText(player, sess, id, "club", { kind = "club", dest = inv.dest, untilT = clubDue() })
		end
		return
	end
	if isBirthday(c) and not rec.f.bdayKnown then
		rec.f.bdayKnown = true
		sendText(player, sess, id, "bday")
		return
	end
	if now() - (rec.last or 0) > 2 * 86400 and math.random() < 0.3 then
		sendText(player, sess, id, "miss")
		return
	end
	if not canCompanion(c) then
		return -- key NPCs at work do not invite you out
	end
	if Citizens.isEvening(clock) and (c.club or 0) > 0 and not c.minor and math.random() < 0.65 then
		local inv = Social.INVITES.club
		sendText(player, sess, id, "club", { kind = "club", dest = inv.dest, untilT = clubDue() })
		return
	end
	local kind = DAY_KINDS[math.random(1, #DAY_KINDS)]
	if kind == "help" then
		rec.f.help = true
		sendText(player, sess, id, "help")
		return
	end
	local inv = Social.INVITES[kind]
	if inv and inv.dest then
		sendText(player, sess, id, kind, { kind = kind, dest = inv.dest, untilT = now() + Social.PROMISE_SECONDS })
	end
end

-- Unanswered text invitations: showing up anyway still counts (+ the friend joins you).
local function inboxTick(player: Player, sess: Sess)
	for _, m in sess.state.inbox do
		if m.state == "new" and m.invite then
			if now() > m.invite.untilT then
				m.state = "expired"
				markDirty(player, sess)
			elseif arrivedAt(player, m.invite.kind, m.invite.dest) then
				m.state = "read"
				local c = citizen(m.from)
				if c then
					award(player, sess, m.from, "invite")
					local rec = recOf(sess, m.from, true)
					meet(player, sess, m.from, rec, nil, "promise")
					if not (sess.comp and sess.comp.id == m.from) then
						meetUp(player, sess, m.from, m.invite.kind)
					end
					sendText(player, sess, m.from, "kept")
				end
			end
		end
	end
end

local function dialogTick(player: Player, sess: Sess)
	local dlg = sess.dlg
	if dlg then
		local idle = os.clock() - dlg.openedAt > (if dlg.remote then 60 else 180)
		if idle or not stillNear(player, dlg) then
			closeDialog(player, sess, false) -- the overlay closes itself when you walk away / hang up
		end
	end
end

local function tick()
	for player, sess in sessions do
		if player.Parent ~= Players then
			continue
		end
		if not sess.ready then
			continue
		end
		for _, f in { companionTick, checkPromises, inboxTick, textTick, dialogTick } do
			local ok, err = pcall(f, player, sess)
			if not ok then
				warn("[GwangalliSocial] tick failed: " .. tostring(err))
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
local function requireShared(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 20)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliSocial] " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local function makeRemotes()
	local folder = ReplicatedStorage:FindFirstChild(Social.Folder)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	local fresh = folder == nil
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Social.Folder
	end
	local function remote(name: string, className: string): any
		local r = (folder :: Instance):FindFirstChild(name)
		if r and r.ClassName ~= className then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	remotes.Action = remote(Social.Remote.Action, "RemoteEvent")
	remotes.State = remote(Social.Remote.State, "RemoteEvent")
	remotes.Get = remote(Social.Remote.Get, "RemoteFunction")
	if fresh then
		(folder :: Instance).Parent = ReplicatedStorage -- parented last: clients that find it find every remote
	end
end

local API_METHODS = {
	affinity = Relationships.affinity,
	tier = Relationships.tier,
	isFriend = Relationships.isFriend,
	friends = Relationships.friends,
	award = Relationships.award,
	joint = Relationships.joint,
	companion = Relationships.companion,
	perk = Relationships.perk,
	onTalk = Relationships.onTalk,
	greeting = Relationships.greeting,
	smallTalk = Relationships.smallTalk,
	menuChoice = Relationships.menuChoice,
	choices = Relationships.choices,
	handleChoice = Relationships.handleChoice,
	snapshot = Relationships.snapshot,
	openDialog = Relationships.openDialog,
	ready = Relationships.ready,
}

local function makeApi()
	local f = ServerStorage:FindFirstChild(Social.API_NAME)
	if f and not f:IsA("BindableFunction") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = Social.API_NAME
		f.Parent = ServerStorage
	end
	(f :: BindableFunction).OnInvoke = function(method: any, player: any, ...: any)
		local fn = type(method) == "string" and API_METHODS[method]
		if not fn or typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil
		end
		local res = table.pack(pcall(fn, player, ...))
		if not res[1] then
			warn("[GwangalliSocial] API " .. tostring(method) .. " failed: " .. tostring(res[2]))
			return nil
		end
		return table.unpack(res, 2, res.n)
	end
end

local function onAction(player: Player, id: any, action: any, payload: any)
	local sess = sessions[player]
	if not sess or not sess.ready then
		return
	end
	if type(action) ~= "string" or not Social.ACTIONS[action] or not actions[action] then
		return
	end
	local cid = Util.str(id, 40)
	if not cid or not citizen(cid) then
		return
	end
	if payload ~= nil and type(payload) ~= "table" then
		return
	end
	if not bucket(sess) then
		return
	end
	if not Util.cooldown(player, "soc:" .. action .. ":" .. cid, ACTION_CD[action] or 0.5) then
		return
	end
	local ok, err = pcall(actions[action], player, sess, cid, payload or {})
	if not ok then
		warn(string.format("[GwangalliSocial] %s from %s failed: %s", action, player.Name, tostring(err)))
	end
end

function Relationships.init(context: any)
	if started then
		return
	end
	started = true
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	Social = requireShared("GwangalliSocialShared")
	Citizens = requireShared("GwangalliCitizens")
	if not Social or not Citizens or not G or not Util or not Profiles then
		warn("[GwangalliSocial] shared modules missing; relationships disabled")
		return
	end
	for _, p in Social.validate() do
		warn("[GwangalliSocial] data: " .. p)
	end
	for _, p in Citizens.validate() do
		warn("[GwangalliSocial] roster: " .. p)
	end
	ctx.social = Relationships

	-- Does Profiles keep d.social itself? (a pass-through in Profiles.sanitize)
	local okProbe, probe = pcall(Profiles.sanitize, { v = G.VERSION, social = { v = Social.VERSION, u = 1, npcs = {} } })
	profileHoldsSocial = okProbe and type(probe) == "table" and type(probe.social) == "table"
	-- the fallback store: written only while Profiles drops d.social; read once per player after the
	-- switch to the profile (migrates progress saved before Profiles kept `social`)
	local okEnabled, en = pcall(Profiles.enabled)
	if game.PlaceId ~= 0 and okEnabled and en then
		local ok, res = pcall(DataStoreService.GetDataStore, DataStoreService, Social.DATASTORE)
		if ok and res then
			store = res
			storeEnabled = true
		end
	end

	makeRemotes()
	makeApi()

	-- club zones
	local function addZone(z: Instance)
		if z:IsA("BasePart") then
			zoneParts[z] = true
		end
	end
	for _, z in CollectionService:GetTagged(CLUB_ZONE_TAG) do
		addZone(z)
	end
	CollectionService:GetInstanceAddedSignal(CLUB_ZONE_TAG):Connect(addZone)
	CollectionService:GetInstanceRemovedSignal(CLUB_ZONE_TAG):Connect(function(z)
		zoneParts[z :: BasePart] = nil
	end)

	;(remotes.Action :: RemoteEvent).OnServerEvent:Connect(onAction)
	;(remotes.Get :: RemoteFunction).OnServerInvoke = function(player: Player)
		if not Util.cooldown(player, "soc:get", 0.5) then
			return nil
		end
		local t0 = os.clock()
		while player.Parent == Players and not (sessions[player] and sessions[player].ready) and os.clock() - t0 < 10 do
			task.wait(0.25)
		end
		local ok, snap = pcall(Relationships.snapshot, player)
		return if ok then snap else nil
	end
	-- citizen dialog choices come back through the Dialog overlay's PhoneAction "dialogChoice"
	local phoneAction = ctx.remotes and ctx.remotes.PhoneAction
	if phoneAction then
		phoneAction.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
			if action ~= "dialogChoice" or type(payload) ~= "table" then
				return
			end
			local id = payload.npcId
			if type(id) ~= "string" or (G.NPCS and G.NPCS[id]) or not citizen(id) then
				return
			end
			local ok, err = pcall(citizenChoice, player, payload)
			if not ok then
				warn("[GwangalliSocial] dialog choice failed: " .. tostring(err))
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(attach, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(attach, player)
	end
	Players.PlayerRemoving:Connect(detach)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliSocial] tick failed: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			local due = {}
			for player, sess in sessions do
				if sess.dirty and player.Parent == Players then
					table.insert(due, { player, sess })
				end
			end
			for _, e in due do -- (a copy: players join / leave while this loop waits)
				if sessions[e[1]] == e[2] then
					task.spawn(saveSide, e[1], e[2])
				end
				task.wait(0.5)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player, sess in sessions do
			pending += 1
			task.spawn(function()
				pcall(saveSide, player, sess)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		local limit = if RunService:IsStudio() then 5 else 20
		while pending > 0 and os.clock() - t0 < limit do
			task.wait(0.1)
		end
	end)
	print(string.format("[GwangalliSocial] relationships ready: %d people, persistence = %s", #Citizens.LIST, if profileHoldsSocial then "profile" elseif storeEnabled then Social.DATASTORE else "memory"))
end

return Relationships
