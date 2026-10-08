--!nocheck
-- GwangalliGameplay/WeaponDealer (server, feature module; owner: npc_mind · NPC session): 총기상 NPCs in the
-- back alleys. They notice the player, talk, ask the crime session's WeaponShopSystem whether this player may
-- trade right now and pass the request on (RequestWeaponShop). THEY NEVER SELL: no prices, no stats, no money,
-- no gun is given here. The contract is ReplicatedStorage.GwangalliWeaponDealerShared.
--
--   * LOOK: dark clothes, sunglasses, a cap, broad build; idle acts (팔짱 / 망보기 / 폰 / 주머니 / 기대기).
--   * PERSONALITY (GwangalliMindShared.personality pers override): 경계심 0.85 · 사교성 0.2 · 공격성 0.5 ·
--     겁 0.5 · 친절 0.25 (cold to strangers). Per-player RELATION -100..100 per dealer (saved in the profile,
--     slice `dealer`; Mind.relChange scales it by that personality): visits / trades raise it; a hit, a gun
--     pulled on him, pestering lower it; a bad relation slowly heals once the trouble is old. Tiers: >= 25
--     friendly (softer lines, never fed up), -15..25 curt / stranger, -50..-15 rough (no special stock,
--     sometimes no deal at all), < -50 no talk until it heals.
--   * DIALOG: the existing phone dialog sheet (remotes.Dialog / PhoneAction "dialogChoice", data only):
--       "뭘 찾는데?" -> 물건 좀 보여줘. / 그냥 지나가던 길이야. / 특별한 물건 있어?
--     a trade choice -> access + danger + mood checks -> the offer line -> RequestWeaponShop (offer basic |
--     special) -> the answer line -> the sheet closes (the shop system opens OpenWeaponShopUI itself).
--     A normal player asking for special stock is offered the basic stock only.
--   * MAFIA (lines + the request's mafia flag only): access().mafia from the shop system, else a job
--     attribute, else the crime system's own rank (crime level >= 조직 수습). The shop system decides.
--   * DANGER: an officer / SWAT / police car / on-duty player cop very close -> "오늘은 장사 안 한다." (refuses);
--     gunfire / an engaged SWAT team / a 총격전 nearby -> the talk stops, he hides (Police.hiddenSpot) and comes
--     back when it is quiet; a street fight right there -> the talk stops. A gun in the customer's hand -> no
--     deal. An open shop is CANCELLED through the contract (WeaponShopCancel) when any of that happens.
--   * ATTACKED (Fight.hitHooks "dealer_" via Fight.onPunch, a 어깨빵, or ctx.weaponDealer.attacked from another
--     combat system): the talk and the trade end, trades with this player are blocked TRADE_BLOCK_S, the
--     relation drops (the other dealers hear of it), then by personality: fights back (his own swings,
--     FightShared damage) or runs.
--   * LINES: pools by situation x tier x mafia, picked with Mind.pick per player (no line again within 15 min
--     while the pool has others).
--   API: ctx.weaponDealer (see the shared contract) + ServerStorage.GwangalliWeaponDealerAPI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WeaponDealer = {}

local ctx: any
local M: any = nil -- GwangalliMindShared
local LS: any = nil -- GwangalliLawShared
local FS: any = nil -- GwangalliFightShared
local Looks: any = nil
local D: any = nil -- GwangalliWeaponDealerShared
local NPC: any = nil -- base NPC.luau (to close its stale dialogs)

local rng = Random.new()
local function rnd(): number
	return rng:NextNumber()
end

local function now(): number
	return os.clock()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-------------------------------------------------------------------------------------------------
-- Tunables
-------------------------------------------------------------------------------------------------
local CFG = {
	TALK_R = 14, -- the dialog ends beyond this (the client sheet closes itself at 24)
	PROMPT_R = 9,
	NOTICE_R = 11, -- "볼일 있냐?" when somebody walks up
	POLICE_R = 22, -- an officer (police / SWAT) this close: no business
	COPCAR_R = 30,
	SWAT_R = 80, -- an engaged SWAT team
	GUNFIRE_R = 90,
	GUNFIRE_S = 12,
	GUNFIGHT_R = 120,
	BRAWL_R = 30,
	HIDE_MIN = 25,
	HIDE_MAX = 60,
	HIDE_QUIET_S = 20, -- quiet this long after the last scare: back to the corner
	RUN = 13,
	WALK = 6,
	TRADE_BLOCK_S = 300, -- after a hit on him
	RUMOUR_BLOCK_S = 120, -- the other dealers heard about it
	REQUEST_TIMEOUT = 4,
	TRADE_MAX_S = 600, -- a shop left open this long: cancelled
	TRADE_LEAVE_R = 30,
	IDLE_CLOSE_S = 25, -- a sheet left open on the choices
	WAIT_CLOSE_S = 45,
	GREET_COOLDOWN = 300, -- the small 'visit' relation gain
	NOTICE_COOLDOWN = 90,
	PESTER_N = 6, -- dialogs opened in PESTER_S -> he is fed up (not with friends / family)
	PESTER_S = 60,
	BLOCK_REL = -50,
	ROUGH_REL = -15,
	FRIEND_REL = 25,
	REL_RECOVER_PER_S = 0.05, -- a bad relation heals (up to ROUGH_REL) once the last hit is old
}

-- the dealers (feet positions on the back lane; each stands a few studs off the lane, facing it)
local SPOTS = {
	{ id = "dealer_1", name = "칼자국", at = Vector3.new(-107.5, 6.5, 252.2), seed = 11, skin = 3, hair = "buzz", style = "black", age = "adult" },
	{ id = "dealer_2", name = "박씨", at = Vector3.new(-862.7, 6.5, 228.9), seed = 23, skin = 2, hair = "side", style = "thug", age = "middle" },
	{ id = "dealer_3", name = "까마귀", at = Vector3.new(227.5, 6.5, 251.0), seed = 37, skin = 4, hair = "twoblock", style = "black", age = "young" },
}

-- 경계심 높음 · 사교성 낮음 · 공격성 중간 · 겁 중간 · 낯선 사람에게 친절하지 않음
local PERS = { kind = 0.25, timid = 0.25, aggr = 0.5, wary = 0.85, greed = 0.75, social = 0.2, patience = 0.35, fear = 0.5, curious = 0.3, justice = 0.05 }

local IDLE_ACTS = { "arms_crossed", "lookout", "pockets", "phone", "lean", "arms_crossed", "lookout" }

-------------------------------------------------------------------------------------------------
-- Lines (situation -> tier -> list)
-------------------------------------------------------------------------------------------------
local FIRST_LINE = "뭘 찾는데?"
local L = {
	greet = {
		stranger = { "뭘 찾는데?", "...뭘 찾는데?", "볼일 있으면 빨리 말해.", "처음 보는 얼굴인데. 뭘 찾는데?", "여기 아무나 오는 데 아니다. 뭘 찾는데?" },
		curt = { "뭘 찾는데?", "또 왔냐. 뭘 찾는데?", "용건만 말해.", "짧게 하자. 뭐 필요해?" },
		friendly = { "왔냐. 오늘은 뭘 찾는데?", "어, 너구나. 뭘 찾는데?", "마침 잘 왔다. 뭘 찾는데?", "어이, 단골. 뭐 필요해?" },
		friendly_long = { "오랜만이네. 뭘 찾는데?", "한동안 안 보이더니. 뭐 필요해?" },
		rough = { "...또 너냐. 뭘 찾는데.", "할 말 있으면 빨리 해.", "너랑 오래 얘기할 생각 없다.", "뭐. 용건만." },
		mafia = { "어이, 왔냐. 뭘 찾는데?", "형님들은 잘 계시고? 뭘 찾는데?", "너 같은 손님은 언제든 환영이지. 뭘 찾는데?", "왔냐. 오늘은 뭐 보러 왔어?" },
	},
	pass = {
		stranger = { "그럼 가던 길 가.", "...그래, 그냥 가.", "볼일 없으면 얼쩡대지 마.", "여기서 본 건 잊어." },
		curt = { "그래. 가.", "다음엔 용건 있을 때 와.", "그럼 됐다." },
		friendly = { "그래, 필요하면 또 와.", "조심해서 다녀라.", "언제든 와. 물건은 있다." },
		rough = { "그럼 꺼져.", "다시 얼쩡대지 마라.", "잘 됐네. 가." },
		mafia = { "그래, 형님들한테 안부 전해.", "필요하면 연락해.", "언제든지. 넌 특별 손님이다." },
	},
	basic = {
		stranger = { "기본적인 것들은 있다.", "돈은 있지?", "괜히 문제 만들지 마.", "보는 건 공짜다. 문제는 만들지 마라." },
		curt = { "기본적인 것들은 있다.", "돈은 있지?", "빨리 골라.", "괜히 문제 만들지 마." },
		friendly = { "좋지. 기본적인 것들은 다 있다.", "골라 봐. 물건은 확실하다.", "천천히 봐." },
		rough = { "...보기만 해. 돈 없으면 꺼지고.", "빨리 골라. 오래 못 기다린다.", "괜히 문제 만들지 마라. 경고다." },
		mafia = { "기본 물건이야 당연히 있지.", "골라 봐. 너한텐 잘해 줄게.", "필요한 만큼 가져가." },
	},
	special = {
		mafia = { "너라면 위에 물건도 보여줄 수 있지.", "새 물건 들어왔다.", "일반 손님한테는 안 보여주는 거다.", "이건 아무한테나 안 꺼낸다. 조용히 봐." },
	},
	special_no = { "특별한 거? 그런 건 아무한테나 안 보여준다.", "그건 식구한테만 꺼낸다.", "그런 건 없다.", "특별한 물건은 아는 사람한테만 판다." },
	special_rough = { "너한테 그런 건 없어.", "특별한 거? 너한텐 안 판다.", "꿈 깨." },
	rough_refuse = { "오늘은 기분 아니다. 다음에 와.", "너한테 팔 물건 없어.", "됐다. 다른 데 알아봐." },
	blocked = { "꺼져. 너랑은 얘기 안 해.", "말 걸지 마라.", "할 말 없다. 가.", "...(무시한다)" },
	pester = { "그만 좀 와. 장사 방해하지 마.", "자꾸 왔다 갔다 하지 마. 눈에 띈다.", "용건 없으면 얼쩡대지 마라." },
	attacked_block = { "너 같은 놈한테 팔 물건 없어.", "아까 그 짓 해 놓고 뭘 바라?", "꺼져. 장사 끝났다." },
	rumour_block = { "얘기 들었다. 너랑은 장사 안 해.", "소문 다 났다. 딴 데 가 봐.", "우리 쪽 사람 건드렸다며? 꺼져." },
	police = { "오늘은 장사 안 한다.", "...짭새 있다. 오늘은 안 돼.", "지금은 안 돼. 눈 많다.", "오늘은 장사 안 한다. 가." },
	cop_player = { "...뭐야, 경찰이냐? 난 그냥 서 있는 거다.", "근무 중이면 볼일 없다.", "난 아무것도 모른다." },
	armed = { "총 치워. 그 상태로 장사 안 한다.", "총 들고 와서 뭘 사겠다고? 치워.", "손에 든 거 내려놔. 얘기는 그다음이다." },
	brawl = { "여기서 소란 피우지 마.", "시끄럽다. 오늘은 접는다.", "싸움판 옆에서 장사 안 한다." },
	gunfire = { "씨X, 총소리다!", "튀어!", "오늘 장사 끝!", "엎드려!" },
	back = { "...조용해졌네.", "후. 다시 장사나 하자.", "아까 그거 뭐였냐." },
	notice = {
		stranger = { "...볼일 있냐?", "뭘 봐.", "지나가는 거면 그냥 가.", "(힐끗 쳐다본다)" },
		curt = { "또 왔네.", "볼일 있으면 말해.", "..." },
		friendly = { "오, 왔네.", "어이.", "물건 들어왔다." },
		rough = { "또 너냐.", "가까이 오지 마.", "..." },
		mafia = { "형님 오셨네.", "어, 왔어?", "어이, 왔냐." },
	},
	mutter = { "...", "(주변을 살핀다)", "오늘따라 조용하네.", "(폰을 확인한다)", "짭새는 안 보이고...", "장사가 영 시원찮네." },
	ok_tail = { "조용히 보고 가.", "천천히 골라.", "빨리 보고 가." },
	after_buy = { "탈 없게 써라.", "조용히 다녀.", "어디서 샀는지는 잊어라." },
	after_look = { "다 봤으면 가 봐.", "필요한 거 생기면 또 와.", "구경만 할 거면 다음엔 그냥 가." },
	none = { "지금은 물건이 없다. 나중에 와.", "오늘은 물건이 안 들어왔다.", "물건 떨어졌다. 다음에 와." },
	timeout = { "...연락이 안 되네. 다음에 와.", "오늘은 안 되겠다. 나중에 와." },
	reason = {
		denied = { "오늘은 너한테 팔 게 없다.", "안 된다. 이유는 묻지 마." },
		not_allowed = { "너한텐 못 판다.", "안 돼. 위에서 안 된다더라." },
		cooldown = { "방금 왔잖아. 좀 있다 와.", "너무 자주 온다. 나중에 와." },
		not_mafia = { "그건 아무한테나 안 보여준다.", "특별한 건 식구한테만 판다." },
		closed = { "오늘은 문 닫았다.", "장사 끝났다. 내일 와." },
		no_stock = { "물건이 다 떨어졌다.", "지금은 재고가 없다." },
		wanted = { "너 지금 너무 시끄러워. 짭새 붙었다.", "수배 떨어지면 와. 지금은 위험해." },
		money = { "돈도 없으면서 뭘 보겠다고.", "돈부터 만들어 와." },
		busy = { "지금 손님 있다. 기다려.", "잠깐만, 다른 손님 먼저." },
		level = { "넌 아직 멀었다.", "좀 더 굴러먹고 와." },
		default = { "...오늘은 안 되겠다.", "오늘은 안 돼." },
	},
	fight = { "죽고 싶냐?", "이게 미쳤나!", "너 오늘 잘못 걸렸다.", "감히 나를 건드려?" },
	flee = { "미친놈이네!", "이 미친...!", "건드리지 마!", "씨X, 튀어!" },
	after_fight = { "다시는 오지 마라.", "꺼져. 다음엔 안 봐준다.", "...장사 망쳤네." },
}

-------------------------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------------------------
type Dealer = any
local dealers: { Dealer } = {}
local byId: { [string]: Dealer } = {}
local P: any = nil -- Law/Police (motion helpers)
local recs: { [number]: { [string]: any } } = {} -- [UserId][dealerId] = relation record
local dialogs: { [Player]: any } = {}
local pending: { [string]: any } = {} -- requestId -> { player, dealer, dlg, t, done }
local trading: { [Player]: any } = {} -- the shop is open for this player: { dealer, t, reqId }
local gunfire: { { pos: Vector3, t: number } } = {} -- shots any gun system reported
local reqSeq = 0
local emoteSeq = 0
local requestEvent: BindableEvent? = nil
local cancelEvent: BindableEvent? = nil
local lastCancel: string? = nil -- (debug)

local C = { id = "weapon_dealer", pers = PERS } -- the pseudo citizen for Mind.personality / relChange

local function debugOn(): boolean
	return workspace:GetAttribute("GwangalliStreetLifeDebug") == true
end

local function dbg(...)
	if debugOn() then
		print("[GwangalliWeaponDealer:dbg]", ...)
	end
end

-------------------------------------------------------------------------------------------------
-- Relation records (kept for the server session, saved in the profile slice `dealer`)
-------------------------------------------------------------------------------------------------
local function profileOf(player: Player): any?
	local Pr = ctx and ctx.Profiles
	if Pr and type(Pr.get) == "function" then
		local ok, d = pcall(Pr.get, player)
		if ok and type(d) == "table" then
			return d
		end
	end
	return nil
end

-- os.clock deadline <-> os.time deadline (os.clock values mean nothing on another server)
local function toWall(deadline: number): number
	return math.floor(os.time() + math.max(0, deadline - now()))
end
local function fromWall(wall: any): number
	if type(wall) ~= "number" then
		return 0
	end
	local left = wall - os.time()
	return if left > 0 then now() + left else 0
end

local function newRec(): any
	local t = now()
	return { rel = 0, relT = t, said = {}, tk = 0, lastTalk = 0, visitT = -1e9, blockUntil = 0, tradeBlockUntil = 0, rumourUntil = 0, opens = {}, noticeT = -1e9, hits = 0, hitT = nil, gunT = -1e9, trades = 0, boughtT = 0, synced = false }
end

local function syncRec(player: Player, id: string, r: any)
	if r.synced then
		return
	end
	local prof = profileOf(player)
	if not prof then
		return -- (the profile is not loaded yet: try again next time)
	end
	r.synced = true
	local s = type(prof.dealer) == "table" and prof.dealer[id]
	if type(s) == "table" then
		if not r.touched and type(s.rel) == "number" and s.rel == s.rel then
			r.rel = math.clamp(s.rel, -100, 100)
			r.relT = now()
		end
		r.tradeBlockUntil = math.max(r.tradeBlockUntil, fromWall(s.tb))
		r.blockUntil = math.max(r.blockUntil, fromWall(s.bu))
		r.rumourUntil = math.max(r.rumourUntil, fromWall(s.ru))
		if type(s.tr) == "number" and s.tr == s.tr then
			r.trades = math.max(r.trades, math.clamp(math.floor(s.tr), 0, 1e6))
		end
		if type(s.tk) == "number" and s.tk == s.tk then
			r.tk = math.max(r.tk, math.clamp(math.floor(s.tk), 0, 1e6))
		end
		if type(s.ht) == "number" and s.ht > os.time() - CFG.TRADE_BLOCK_S then
			r.hitT = now() - math.max(0, os.time() - s.ht)
		end
	end
end

local function saveRec(player: Player, id: string, r: any)
	if r.gone or typeof(player) ~= "Instance" then
		return
	end
	local prof = profileOf(player)
	if not prof then
		return
	end
	if type(prof.dealer) ~= "table" then
		prof.dealer = {}
	end
	local t = now()
	prof.dealer[id] = {
		rel = math.floor((r.rel or 0) * 10 + 0.5) / 10,
		tb = if r.tradeBlockUntil > t then toWall(r.tradeBlockUntil) else nil,
		bu = if r.blockUntil > t then toWall(r.blockUntil) else nil,
		ru = if r.rumourUntil > t then toWall(r.rumourUntil) else nil,
		tr = r.trades,
		tk = math.min(r.tk, 999),
		ht = if r.hitT and t - r.hitT < CFG.TRADE_BLOCK_S then math.floor(os.time() - (t - r.hitT)) else nil,
	}
	local Pr = ctx.Profiles
	if Pr and type(Pr.markDirty) == "function" then
		pcall(Pr.markDirty, player)
	end
end

local function recOf(player: Player, id: string): any
	if typeof(player) ~= "Instance" or player.Parent ~= Players then
		local r = newRec()
		r.gone = true -- (a player who left: a throwaway record, never stored)
		return r
	end
	local u = recs[player.UserId]
	if not u then
		u = {}
		recs[player.UserId] = u
	end
	local r = u[id]
	if not r then
		r = newRec()
		u[id] = r
	end
	syncRec(player, id, r)
	return r
end

-- the relation, after the slow healing of a bad one (no hit on this dealer for TRADE_BLOCK_S)
local function relOf(rec: any): number
	local t = now()
	local rel = (M and M.relOf(rec)) or rec.rel or 0
	if rel < CFG.ROUGH_REL and (not rec.hitT or t - rec.hitT > CFG.TRADE_BLOCK_S) then
		rel = math.min(CFG.ROUGH_REL, rel + math.max(0, t - (rec.relT or t)) * CFG.REL_RECOVER_PER_S)
		rec.rel = rel
	end
	rec.relT = t
	return rel
end

local function relEvent(player: Player?, id: string?, rec: any, kind: string, mult: number?)
	local base = M and M.REL_EVENT[kind]
	if kind == "trade" then
		base = 4
	elseif kind == "deal" then
		base = 2
	elseif kind == "haggle" then
		base = -2
	elseif kind == "scam" then
		base = -30
	end
	if not base then
		return
	end
	relOf(rec)
	if M then
		M.relChange(C, rec, base * (mult or 1))
	else
		rec.rel = math.clamp((rec.rel or 0) + base * (mult or 1), -100, 100)
	end
	rec.touched = true
	rec.relT = now()
	if player and id then
		saveRec(player, id, rec)
	end
end

local function pickLine(list: { string }?, rec: any?): string
	if not list or #list == 0 then
		return "..."
	end
	if M and rec then
		return M.pick(list, rec, now(), rnd) or list[1]
	end
	return list[rng:NextInteger(1, #list)]
end

-------------------------------------------------------------------------------------------------
-- Who the player is (read-only)
-------------------------------------------------------------------------------------------------
local function lawData(player: Player): any?
	local Law = ctx and ctx.law
	if Law and type(Law.data) == "function" then
		local ok, d = pcall(Law.data, player)
		if ok and type(d) == "table" then
			return d
		end
	end
	return nil
end

local function shopSystem(): any?
	local w = ctx and ctx.weaponShop
	return if type(w) == "table" then w else nil
end

local function shopFolder(): Folder?
	local f = ServerStorage:FindFirstChild(D and D.FOLDER or "GwangalliWeaponShop")
	return if f and f:IsA("Folder") then f else nil
end

-- the crime / job system's view of this player (access().mafia / allowed), or nil. May yield (<= 1.5 s).
local function accessOf(player: Player): any?
	local w = shopSystem()
	if w and type(w.access) == "function" then
		local ok, a = pcall(w.access, player)
		if ok and type(a) == "table" then
			return a
		end
		return nil
	end
	local f = shopFolder()
	local bf = f and f:FindFirstChild(D.ACCESS_FUNCTION)
	if bf and bf:IsA("BindableFunction") then
		-- a BindableFunction with no handler would yield forever: never wait more than a moment
		local out, done = nil, false
		task.spawn(function()
			local ok, a = pcall(function()
				return (bf :: BindableFunction):Invoke(player)
			end)
			if ok and type(a) == "table" then
				out = a
			end
			done = true
		end)
		local t0 = now()
		while not done and now() - t0 < 1.5 do
			task.wait()
		end
		return out
	end
	return nil
end

-- 마피아: from the crime / job side only. Returns (mafia, source)
local function mafiaOf(player: Player, access: any?): (boolean, string)
	if access and access.mafia ~= nil then
		return access.mafia == true, "access"
	end
	local MA = D and D.MAFIA or {}
	for _, a in MA.attrs or {} do
		if player:GetAttribute(a) == true then
			return true, "job"
		end
	end
	for _, a in MA.jobAttrs or {} do
		local v = player:GetAttribute(a)
		if type(v) == "string" and MA.jobIds and MA.jobIds[string.lower(v)] then
			return true, "job"
		end
	end
	if MA.useCrimeLevel and LS and type(LS.crimeLevel) == "function" then
		local lv = player:GetAttribute("LawCrimeLevel")
		if type(lv) ~= "number" then
			local d = lawData(player)
			lv = d and type(d.crimeXp) == "number" and LS.crimeLevel(d.crimeXp) or nil
		end
		if type(lv) == "number" and lv >= (LS.ORG_LEVEL or 5) then
			return true, "crime"
		end
	end
	return false, "none"
end

local GUN_WORDS = { "gun", "pistol", "rifle", "glock", "revolver", "shotgun", "smg", "uzi", "ak47", "m4", "deagle", "총", "권총", "소총", "엽총" }
local function armed(player: Player): boolean
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then
		return false
	end
	local w = tool:GetAttribute("GwWeapon") or tool:GetAttribute("WeaponType")
	if w == "gun" or tool:GetAttribute("IsGun") == true then
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

local function posOf(player: Player): Vector3?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else nil
end

local function isCop(player: Player): boolean
	return player:GetAttribute((LS and LS.Attr and LS.Attr.Cop) or "LawCop") == true
end

-- the tier of the talk with this player
local function tierOf(rec: any, mafia: boolean): string
	local rel = relOf(rec)
	if rel < CFG.ROUGH_REL then
		return "rough"
	end
	if mafia then
		return "mafia"
	end
	if rel >= CFG.FRIEND_REL then
		return "friendly"
	end
	-- 경계심: a stranger stays a stranger for a few visits (wary 0.85 -> 2 talks)
	local wary = (M and M.personality(C).wary) or PERS.wary
	if rec.tk <= math.floor(wary * 2.5) and rel < 15 then
		return "stranger"
	end
	return "curt"
end

local function moodOf(d: Dealer, rec: any): string
	if now() < (d.scaredUntil or 0) then
		return "SCARED"
	end
	if M and type(M.npcMood) == "function" then
		local ok, m = pcall(M.npcMood, C, rec, { now = now(), recent = { scared = d.scaredAt, angry = rec.hitT } })
		if ok and type(m) == "string" then
			return m
		end
	end
	return if relOf(rec) < CFG.ROUGH_REL then "ANNOYED" else "NORMAL"
end

-------------------------------------------------------------------------------------------------
-- Danger around a point
-------------------------------------------------------------------------------------------------
-- "police" (no business, stay put) | "gunfire" (hide) | "brawl" (stop the talk) | nil
local function dangerAt(pos: Vector3, asking: Player?): (string?, string?)
	local t = now()
	-- shots: SWAT rounds, any gun system's GwangalliGunfire, a 총격전 nearby
	for i = #gunfire, 1, -1 do
		local g = gunfire[i]
		if t - g.t > CFG.GUNFIRE_S then
			break
		end
		if flat(g.pos, pos) < CFG.GUNFIRE_R then
			return "gunfire", "shot"
		end
	end
	local sw = ctx and ctx.swat
	if sw then
		if type(sw.gunfireNear) == "function" then
			local ok, hit = pcall(sw.gunfireNear, pos, CFG.GUNFIRE_R, CFG.GUNFIRE_S)
			if ok and hit then
				return "gunfire", "swat_shot"
			end
		end
		if type(sw.activeNear) == "function" then
			local ok, hit = pcall(sw.activeNear, pos, CFG.SWAT_R)
			if ok and hit then
				return "gunfire", "swat"
			end
		end
	end
	local Law = ctx and ctx.law
	if Law and type(Law.sessions) == "function" then
		local ok, all = pcall(Law.sessions)
		if ok and type(all) == "table" then
			for _, s in all do
				if type(s) == "table" and s.majorKind == "gunfight" and (s.majorUntil or 0) > t and type(s.crimes) == "table" then
					for _, cr in s.crimes do
						if type(cr) == "table" and cr.kind == "gunfight" and typeof(cr.pos) == "Vector3" and flat(cr.pos, pos) < CFG.GUNFIGHT_R and t - (cr.t or 0) < 60 then
							return "gunfire", "gunfight"
						end
					end
				end
			end
		end
	end
	-- the law right here
	local Pol = Law and Law.children and Law.children.Police
	if Pol then
		if type(Pol.nearestOfficer) == "function" then
			local ok, o = pcall(Pol.nearestOfficer, pos, CFG.POLICE_R)
			if ok and o then
				return "police", if o.unit == "swat" then "swat_near" else "officer"
			end
		end
		if type(Pol.nearestCar) == "function" then
			local ok, c = pcall(Pol.nearestCar, pos, CFG.COPCAR_R)
			if ok and c and c.unit ~= "ems" then
				return "police", "car"
			end
		end
	end
	for _, pl in Players:GetPlayers() do
		if pl ~= asking and isCop(pl) then
			local pp = posOf(pl)
			if pp and flat(pp, pos) < CFG.POLICE_R then
				return "police", "cop_player"
			end
		end
	end
	local F = ctx and ctx.fight
	if F and type(F.fightingNear) == "function" then
		local ok, hit = pcall(F.fightingNear, pos, CFG.BRAWL_R)
		if ok and hit then
			return "brawl", "fight"
		end
	end
	return nil, nil
end

local function dangerLine(danger: string?, rec: any?): string
	if danger == "police" then
		return pickLine(L.police, rec)
	elseif danger == "brawl" then
		return pickLine(L.brawl, rec)
	end
	return pickLine(L.gunfire, rec)
end

-------------------------------------------------------------------------------------------------
-- Rig + motion (Police actor helpers when Law is there; a plain standing rig otherwise)
-------------------------------------------------------------------------------------------------
local function setAct(d: Dealer, act: string)
	if P and type(P.setAct) == "function" then
		P.setAct(d.o, act)
	elseif d.o.model then
		d.o.model:SetAttribute("NpcAct", act)
		d.o.act = act
	end
end

local function faceTo(d: Dealer, p: Vector3)
	if P and type(P.faceTo) == "function" then
		P.faceTo(d.o, p)
	end
end

local function emote(d: Dealer, name: string)
	if d.o.model then
		emoteSeq += 1
		d.o.model:SetAttribute("NpcEmote", name .. "#" .. emoteSeq .. "#" .. string.format("%.2f", serverNow()))
	end
end

local function curPos(d: Dealer): Vector3
	if P and type(P.legPos) == "function" then
		local ok, p = pcall(P.legPos, d.o, now())
		if ok and typeof(p) == "Vector3" then
			return p
		end
	end
	return d.o.pos
end

local function goTo(d: Dealer, p: Vector3, speed: number)
	if P and type(P.assignGoal) == "function" then
		local ok = pcall(P.assignGoal, d.o, p, speed)
		if ok then
			return
		end
	end
	d.o.pos = p
	if P and type(P.standAt) == "function" then
		pcall(P.standAt, d.o, p)
	end
end

local function arrived(d: Dealer): boolean
	if P and type(P.arrived) == "function" then
		local ok, a = pcall(P.arrived, d.o)
		return not ok or a
	end
	return true
end

local function standHome(d: Dealer)
	d.o.yaw = d.yaw
	if P and type(P.standAt) == "function" then
		pcall(P.standAt, d.o, d.home)
	end
	if d.o.model then
		d.o.model:SetAttribute("NpcYaw", d.yaw)
	end
	setAct(d, d.idleAct or "arms_crossed")
end

-- head bubble (every client sees it)
local function say(d: Dealer, text: string, secs: number?)
	local m = d.o.model
	local head = m and m:FindFirstChild("Head")
	if not head or text == "" then
		return
	end
	local bb = d.bubble
	if not bb or not bb.Parent then
		bb = Instance.new("BillboardGui")
		bb.Name = "DealerSay"
		bb.Size = UDim2.fromOffset(230, 44)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 70
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = Color3.fromRGB(24, 22, 26)
		t.BackgroundTransparency = 0.1
		t.TextColor3 = Color3.fromRGB(236, 230, 214)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextWrapped = true
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = t
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = t
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 17
		lim.Parent = t
		t.Parent = bb
		bb.Adornee = head
		bb.Parent = head
		d.bubble = bb
	end
	(bb:FindFirstChild("Text") :: TextLabel).Text = text
	bb.Enabled = true
	emoteSeq += 1
	local stamp = emoteSeq
	d.sayStamp = stamp
	d.lastSay = now()
	task.delay(secs or 3.2, function()
		if d.sayStamp == stamp and bb.Parent then
			bb.Enabled = false
		end
	end)
end

local function groundAt(p: Vector3): number
	if P and type(P.groundAt) == "function" then
		local ok, y = pcall(P.groundAt, p, p.Y)
		if ok and type(y) == "number" then
			return y
		end
	end
	return p.Y
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local function standClear(feet: Vector3): boolean
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 2.8, 0)), Vector3.new(2, 3, 2), overlap)
	end)
	if not ok then
		return true
	end
	for _, q in parts do
		if q.CanCollide and q.Transparency < 0.95 then
			return false
		end
	end
	return true
end

-- a few studs off the lane centre (the side with room), facing the lane
local function placeSpot(spot: any): (Vector3, number)
	local base = spot.at
	local ex = {}
	for _, n in { "GwangalliNPCs", "GwangalliStreetLife", "GwangalliLawCars", "GwangalliPlayerCars", "GwangalliShopStaff" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ex, f)
		end
	end
	overlap.FilterDescendantsInstances = ex
	for _, off in { Vector3.new(0, 0, 5.5), Vector3.new(0, 0, -5.5), Vector3.new(2.5, 0, 6.5), Vector3.new(-2.5, 0, -6.5), Vector3.new(0, 0, 4), Vector3.new(0, 0, -4), Vector3.new(0, 0, 0) } do
		local p = base + off
		local y = groundAt(p)
		if math.abs(y - base.Y) < 3 then
			local feet = Vector3.new(p.X, y, p.Z)
			if standClear(feet) then
				local d = base - feet
				local yaw = if Vector3.new(d.X, 0, d.Z).Magnitude > 0.5 then math.deg(math.atan2(-d.X, -d.Z)) else 0
				return feet, yaw
			end
		end
	end
	return Vector3.new(base.X, groundAt(base), base.Z), 0
end

local function buildRig(spot: any, feet: Vector3, yaw: number): any?
	if not Looks then
		return nil
	end
	local ok, rig = pcall(function()
		local spec = Looks.resolve({ body = "m", age = spot.age or "adult", style = spot.style or "black", hair = spot.hair or "buzz", skin = spot.skin, build = "broad", acc = "sunglasses", gear = { "cap" } }, spot.seed or spot.id, false)
		return Looks.build(spec, { name = "Dealer_" .. spot.id, anchored = true, shadow = false })
	end)
	if not ok or type(rig) ~= "table" or not rig.model then
		warn("[GwangalliWeaponDealer] rig failed: " .. tostring(rig))
		return nil
	end
	local m = rig.model
	local g = rig.ground or 3
	m:SetAttribute("NpcId", spot.id)
	m:SetAttribute("NpcKind", "key") -- (GwangalliFight's client targets key / street models: he can be hit)
	m:SetAttribute("NpcGround", g)
	m:SetAttribute("NpcAct", "arms_crossed")
	m:SetAttribute("NpcYaw", yaw)
	m:SetAttribute("WeaponDealer", true)
	m:SetAttribute("NpcLeg", string.format("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,0", feet.X, feet.Y, feet.Z, feet.X, feet.Y, feet.Z, serverNow()))
	m:PivotTo(CFrame.new(feet + Vector3.new(0, g, 0)) * CFrame.Angles(0, math.rad(yaw), 0))
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GwangalliNPCs"
		f.Parent = workspace
	end
	m.Parent = f
	return { model = m, root = rig.root or m:FindFirstChild("HumanoidRootPart"), ground = g }
end

-------------------------------------------------------------------------------------------------
-- The shop side: cancel an open shop / a request in flight (the contract's WeaponShopCancel)
-------------------------------------------------------------------------------------------------
local function cancelShop(player: Player, d: Dealer, reason: string, reqId: string?)
	local tr = trading[player]
	if tr and tr.dealer == d then
		reqId = reqId or tr.reqId
		trading[player] = nil
	end
	if d.tradingWith == player then
		d.tradingWith = nil
	end
	if reqId and pending[reqId] then
		pending[reqId].done = true
		pending[reqId] = nil
	end
	lastCancel = reason
	local info = { requestId = reqId, dealerId = d.id, reason = reason }
	local w = shopSystem()
	if w and type(w.cancel) == "function" then
		task.spawn(function()
			local ok, err = pcall(w.cancel, player, info)
			if not ok then
				warn("[GwangalliWeaponDealer] WeaponShopSystem.cancel failed: " .. tostring(err))
			end
		end)
	end
	if cancelEvent then
		cancelEvent:Fire(player, info)
	end
	dbg("cancel", player.Name, d.id, reason, reqId)
end

-- every shop / request of this dealer ends (danger, an attack, he runs)
local function cancelAllOf(d: Dealer, reason: string)
	local list = {}
	for player, tr in trading do
		if tr.dealer == d then
			table.insert(list, { player, tr.reqId })
		end
	end
	for id, pr in pending do
		if pr.dealer == d and not pr.done then
			table.insert(list, { pr.player, id })
		end
	end
	for _, e in list do
		cancelShop(e[1], d, reason, e[2])
	end
end

-------------------------------------------------------------------------------------------------
-- Dialog (the existing phone dialog sheet; data only)
-------------------------------------------------------------------------------------------------
local PORTRAIT = Color3.fromRGB(46, 42, 48)

local function sendSheet(player: Player, dlg: any, text: string, choices: { any }?)
	table.clear(dlg.choices)
	local out = {}
	for _, ch in choices or {} do
		dlg.choices[ch.id] = true
		table.insert(out, { id = ch.id, label = ch.label, style = ch.style })
	end
	dlg.choices.close = true
	dlg.lastSent = now()
	dlg.lastText = text
	dlg.lastChoices = choices
	local Rm = ctx.remotes and ctx.remotes.Dialog
	if Rm and player.Parent == Players then
		Rm:FireClient(player, {
			npcId = dlg.dealer.id,
			name = "총기상 " .. dlg.dealer.name,
			role = "뒷골목",
			portraitColor = PORTRAIT,
			icon = "🕶️",
			text = text,
			choices = out,
		})
	end
end

local function closeSheet(player: Player, keepTrading: boolean?)
	local dlg = dialogs[player]
	if not dlg then
		return
	end
	dialogs[player] = nil
	local d = dlg.dealer
	if d.talkingWith == player then
		d.talkingWith = nil
	end
	-- a request still in flight for this sheet is dropped (the shop must not open for a closed talk)
	if dlg.reqId and pending[dlg.reqId] and not keepTrading then
		cancelShop(player, d, "closed", dlg.reqId)
	end
	if player.Parent == Players and ctx.remotes and ctx.remotes.Dialog then
		ctx.remotes.Dialog:FireClient(player, { close = true })
	end
	if not keepTrading then
		task.delay(1.2, function()
			if not d.talkingWith and not d.tradingWith and d.state == "idle" then
				standHome(d)
			end
		end)
	end
end

-- a final line in the sheet (only 닫기), closing by itself a moment later
local function endWith(player: Player, dlg: any, text: string, secs: number?)
	sendSheet(player, dlg, text, nil)
	say(dlg.dealer, text, 3)
	dlg.closing = true
	local stamp = dlg.lastSent
	task.delay(secs or 3.2, function()
		local cur = dialogs[player]
		if cur == dlg and dlg.lastSent == stamp then
			closeSheet(player)
		end
	end)
end

-- the sheet is still this one, open, and the dealer still at his corner
local function stillOn(player: Player, dlg: any, step: string?): boolean
	if dialogs[player] ~= dlg or dlg.closing or dlg.dealer.state ~= "idle" then
		return false
	end
	if step and dlg.step ~= step then
		return false
	end
	local pp = posOf(player)
	return pp ~= nil and flat(pp, curPos(dlg.dealer)) <= CFG.TALK_R
end

local TRADE_CHOICES = {
	{ id = "show", label = "물건 좀 보여줘.", style = "primary" },
	{ id = "pass", label = "그냥 지나가던 길이야.", style = "ghost" },
	{ id = "special", label = "특별한 물건 있어?", style = "secondary" },
}

-- the refusals before any talk (returns the line or nil)
local function gateLine(player: Player, d: Dealer, rec: any, mafiaHint: boolean): string?
	local t = now()
	if (rec.hitT and t - rec.hitT < CFG.TRADE_BLOCK_S) or t < rec.tradeBlockUntil then
		return pickLine(L.attacked_block, rec)
	end
	if t < rec.rumourUntil then
		return pickLine(L.rumour_block, rec)
	end
	local rel = relOf(rec)
	if t < rec.blockUntil or rel < CFG.BLOCK_REL then
		if rel < CFG.BLOCK_REL and t >= rec.blockUntil then
			-- 인내심 0.35: fed up for a few minutes (60 + (1 - patience) * 240 s); the relation heals meanwhile
			rec.blockUntil = t + 60 + (1 - PERS.patience) * 240
			saveRec(player, d.id, rec)
		end
		return pickLine(L.blocked, rec)
	end
	if isCop(player) then
		return pickLine(L.cop_player, rec)
	end
	local danger = dangerAt(d.home, player)
	if danger then
		return dangerLine(danger, rec)
	end
	if armed(player) then
		if t - rec.gunT > 60 then
			rec.gunT = t
			relEvent(player, d.id, rec, "gun", 0.5)
		end
		return pickLine(L.armed, rec)
	end
	-- 사교성 낮음: the same face again and again within a minute (not friends / family)
	table.insert(rec.opens, t)
	while #rec.opens > 0 and t - rec.opens[1] > CFG.PESTER_S do
		table.remove(rec.opens, 1)
	end
	if #rec.opens > CFG.PESTER_N and not mafiaHint and rel < CFG.FRIEND_REL then
		relEvent(player, d.id, rec, "pester")
		rec.blockUntil = t + 45
		table.clear(rec.opens)
		return pickLine(L.pester, rec)
	end
	return nil
end

local function openTalk(player: Player, d: Dealer)
	local cur = dialogs[player]
	if cur and cur.dealer == d and not cur.closing then
		-- the sheet may be gone on the client (respawn, the phone): show it again as it was
		sendSheet(player, cur, cur.lastText or FIRST_LINE, cur.lastChoices)
		return
	end
	if d.state ~= "idle" then
		return
	end
	local pp = posOf(player)
	if not pp or flat(pp, curPos(d)) > CFG.TALK_R then
		return
	end
	if NPC and type(NPC.close) == "function" then
		pcall(NPC.close, player) -- (a stale NPC.luau dialog would close this sheet from its own tick)
	end
	if cur then
		closeSheet(player)
	end
	local rec = recOf(player, d.id)
	local dlg = { dealer = d, choices = { close = true }, opened = now(), step = "opening", lastSent = now() }
	dialogs[player] = dlg
	d.talkingWith = player
	faceTo(d, pp)
	setAct(d, "idle")
	-- the crime / job side's word on this player (may take a moment)
	local access = accessOf(player)
	if dialogs[player] ~= dlg then
		return
	end
	if d.state ~= "idle" then
		closeSheet(player)
		return
	end
	local mafia, src = mafiaOf(player, access)
	local refuse = gateLine(player, d, rec, mafia)
	if refuse then
		endWith(player, dlg, refuse, 3.4)
		return
	end
	if access and access.allowed == false then
		endWith(player, dlg, pickLine(L.reason[access.reason or "not_allowed"] or L.reason.not_allowed, rec), 3.4)
		return
	end
	local t = now()
	local prevTalk = rec.lastTalk
	rec.tk += 1
	rec.lastTalk = t
	if t - rec.visitT > CFG.GREET_COOLDOWN then
		rec.visitT = t
		relEvent(player, d.id, rec, "visit")
	else
		saveRec(player, d.id, rec)
	end
	dlg.access, dlg.mafia, dlg.mafiaSource = access, mafia, src
	local tier = tierOf(rec, mafia)
	dlg.tier = tier
	dlg.step = "greet"
	local text
	if rec.tk == 1 and tier == "stranger" then
		text = FIRST_LINE
	elseif tier == "friendly" and prevTalk > 0 and t - prevTalk > 1800 then
		text = pickLine(L.greet.friendly_long, rec)
	else
		text = pickLine(L.greet[tier] or L.greet.curt, rec)
	end
	dbg("open", player.Name, d.id, "tier", tier, "rel", relOf(rec), "mafia", mafia, src)
	sendSheet(player, dlg, text, TRADE_CHOICES)
end

-------------------------------------------------------------------------------------------------
-- The request to the crime session's WeaponShopSystem
-------------------------------------------------------------------------------------------------
local function systemReady(): boolean
	local w = shopSystem()
	if w and type(w.request) == "function" then
		return true
	end
	local f = shopFolder()
	if f and f:GetAttribute("Ready") == true then
		return true
	end
	return debugOn() and workspace:GetAttribute("GwangalliWeaponShopMock") == true
end

local function finishRequest(reqId: string, ok: boolean, reason: string?)
	local pr = pending[reqId]
	if not pr or pr.done then
		return
	end
	pr.done = true
	pending[reqId] = nil
	local player, d, dlg = pr.player, pr.dealer, pr.dlg
	local rec = recOf(player, d.id)
	dbg("result", player.Name, reqId, ok, reason)
	if dialogs[player] ~= dlg or dlg.closing or player.Parent ~= Players then
		if ok then
			cancelShop(player, d, "expired", reqId) -- (the talk is over: the shop must not stay open)
		end
		return
	end
	if ok then
		-- the scene once more: things change while the shop answers
		local danger = dangerAt(d.home, player)
		if danger or d.state ~= "idle" then
			cancelShop(player, d, danger or "busy", reqId)
			endWith(player, dlg, dangerLine(danger or "brawl", rec), 3)
			return
		end
		trading[player] = { dealer = d, t = now(), reqId = reqId }
		d.tradingWith = player
		relEvent(player, d.id, rec, "deal")
		say(d, dlg.offerLine or pickLine(L.ok_tail, rec), 3.2)
		-- the shop system's own UI takes over: our sheet goes, the dealer waits by the customer
		closeSheet(player, true)
	else
		local list = L.reason[reason or "default"] or L.reason.default
		endWith(player, dlg, pickLine(list, rec), 3.4)
	end
end

local function dispatch(player: Player, d: Dealer, dlg: any, req: any)
	local reqId = req.requestId
	local rec = recOf(player, d.id)
	if not stillOn(player, dlg, "wait") then
		if dialogs[player] == dlg and not dlg.closing then
			closeSheet(player)
		end
		return
	end
	local danger = dangerAt(d.home, player)
	if danger then
		endWith(player, dlg, dangerLine(danger, rec), 3)
		return
	end
	if not systemReady() then
		-- nobody listens: say so (no request goes out that nobody would answer)
		task.delay(0.6, function()
			if dialogs[player] == dlg and not dlg.closing then
				endWith(player, dlg, pickLine(L.none, rec), 3.4)
			end
		end)
		return
	end
	pending[reqId] = { player = player, dealer = d, dlg = dlg, t = now(), done = false }
	dlg.reqId = reqId
	local w = shopSystem()
	if w and type(w.request) == "function" then
		-- 1) the module API: a sync answer, or nil = it answers later through result()
		task.spawn(function()
			local okCall, a, b = pcall(w.request, player, req)
			if not okCall then
				warn("[GwangalliWeaponDealer] WeaponShopSystem.request failed: " .. tostring(a))
				finishRequest(reqId, false, "default")
				return
			end
			if type(a) == "table" then
				finishRequest(reqId, a.ok == true, a.reason)
			elseif a ~= nil then
				finishRequest(reqId, a == true, b)
			end
		end)
	else
		-- 2) the event (the answer comes back through WeaponShopResult / result())
		if requestEvent then
			requestEvent:Fire(player, req)
		end
		-- test mock (debug only): the shop answers yes (or GwangalliWeaponShopMockReason)
		if debugOn() and workspace:GetAttribute("GwangalliWeaponShopMock") == true then
			task.delay(0.4, function()
				local mockReason = workspace:GetAttribute("GwangalliWeaponShopMockReason")
				finishRequest(reqId, type(mockReason) ~= "string", if type(mockReason) == "string" then mockReason else nil)
			end)
		end
	end
	task.delay(CFG.REQUEST_TIMEOUT, function()
		local pr = pending[reqId]
		if pr and not pr.done then
			cancelShop(player, d, "timeout", reqId)
			if dialogs[player] == dlg and not dlg.closing then
				endWith(player, dlg, pickLine(L.timeout, rec), 3.2)
			end
		end
	end)
end

local function requestShop(player: Player, d: Dealer, dlg: any, offer: string)
	if dialogs[player] ~= dlg or dlg.closing then
		return
	end
	local rec = recOf(player, d.id)
	reqSeq += 1
	local reqId = string.format("%s-%d-%d", d.id, player.UserId, reqSeq)
	local req = {
		requestId = reqId,
		dealerId = d.id,
		dealerName = d.name,
		dealerPos = d.home,
		offer = offer,
		mafia = dlg.mafia == true,
		mafiaSource = dlg.mafiaSource or "none",
		rel = math.floor(relOf(rec) + 0.5),
		relLabel = (M and M.relBand(relOf(rec)).label) or "",
		mood = moodOf(d, rec),
		at = os.time(),
	}
	dlg.step = "wait"
	-- the offer line (normal / mafia) gets a moment on the sheet before the shop takes over
	local pool = (offer == "special" and L.special.mafia) or (L[offer] and L[offer][dlg.tier]) or L.basic.curt
	local line = pickLine(pool, rec)
	dlg.offerLine = line
	sendSheet(player, dlg, line, nil)
	say(d, line, 3)
	local beat = math.clamp(0.5 + (utf8.len(line) or 10) * 0.05, 0.9, 1.6)
	task.delay(beat, function()
		local ok, err = pcall(dispatch, player, d, dlg, req)
		if not ok then
			warn("[GwangalliWeaponDealer] request failed: " .. tostring(err))
		end
	end)
end

local function onChoice(player: Player, dlg: any, choiceId: string)
	local d = dlg.dealer
	local rec = recOf(player, d.id)
	if choiceId == "close" then
		closeSheet(player)
		return
	end
	if dlg.closing or (dlg.step ~= "greet" and dlg.step ~= "basic_offer") then
		return
	end
	if choiceId == "pass" then
		endWith(player, dlg, pickLine(L.pass[dlg.tier] or L.pass.curt, rec), 2.6)
		return
	end
	if choiceId ~= "show" and choiceId ~= "special" then
		return
	end
	-- a deal: lock the sheet while the crime side is asked (no double request), then everything again
	dlg.step = "checking"
	table.clear(dlg.choices)
	dlg.choices.close = true
	local access = accessOf(player)
	if not stillOn(player, dlg, "checking") then
		if dialogs[player] == dlg and not dlg.closing then
			if d.state ~= "idle" then
				endWith(player, dlg, pickLine(L.brawl, rec), 2.6)
			else
				closeSheet(player)
			end
		end
		return
	end
	local danger = dangerAt(d.home, player)
	if danger then
		endWith(player, dlg, dangerLine(danger, rec), 3.2)
		return
	end
	if armed(player) then
		endWith(player, dlg, pickLine(L.armed, rec), 3.4)
		return
	end
	if access then
		dlg.access = access
		if access.mafia ~= nil then
			dlg.mafia = access.mafia == true
			dlg.mafiaSource = "access"
		end
		if access.allowed == false then
			endWith(player, dlg, pickLine(L.reason[access.reason or "not_allowed"] or L.reason.not_allowed, rec), 3.4)
			return
		end
	end
	local tier = dlg.tier
	if choiceId == "special" then
		if tier == "rough" then
			endWith(player, dlg, pickLine(L.special_rough, rec), 3.2)
			return
		end
		if dlg.mafia then
			requestShop(player, d, dlg, "special")
			return
		end
		-- 일반 플레이어: the basic stock only
		dlg.step = "basic_offer"
		sendSheet(player, dlg, pickLine(L.special_no, rec), {
			{ id = "show", label = "그럼 기본 물건이라도 보여줘.", style = "primary" },
			{ id = "pass", label = "됐어. 그냥 갈게.", style = "ghost" },
		})
		return
	end
	-- show
	if tier == "rough" and rnd() < 0.5 then
		endWith(player, dlg, pickLine(L.rough_refuse, rec), 3.2)
		return
	end
	requestShop(player, d, dlg, "basic")
end

local function onPhoneAction(player: Player, action: any, payload: any)
	if action ~= "dialogChoice" or type(payload) ~= "table" then
		return
	end
	local dlg = dialogs[player]
	if not dlg then
		return
	end
	local Util = ctx.Util
	local rawChoice = payload.choiceId or payload.choice
	local id, choiceId
	if Util and type(Util.str) == "function" then
		id, choiceId = Util.str(payload.npcId, 40), Util.str(rawChoice, 60)
	else
		id = if type(payload.npcId) == "string" and #payload.npcId <= 40 then payload.npcId else nil
		choiceId = if type(rawChoice) == "string" and #rawChoice <= 60 then rawChoice else nil
	end
	if not id or not choiceId or id ~= dlg.dealer.id or not dlg.choices[choiceId] then
		return
	end
	if choiceId ~= "close" and Util and type(Util.cooldown) == "function" and not Util.cooldown(player, "weaponDealerChoice", 0.35) then
		return
	end
	local pp = posOf(player)
	if choiceId ~= "close" and (not pp or flat(pp, curPos(dlg.dealer)) > CFG.TALK_R) then
		closeSheet(player)
		return
	end
	local ok, err = pcall(onChoice, player, dlg, choiceId)
	if not ok then
		warn("[GwangalliWeaponDealer] choice failed: " .. tostring(err))
		closeSheet(player)
	end
end

-------------------------------------------------------------------------------------------------
-- Scare / hide / attacked
-------------------------------------------------------------------------------------------------
local function endTalksWith(d: Dealer, line: string?, reason: string)
	for player, dlg in dialogs do
		if dlg.dealer == d then
			if line then
				sendSheet(player, dlg, line, nil)
				dlg.closing = true
				local stamp = dlg.lastSent
				task.delay(1.2, function()
					if dialogs[player] == dlg and dlg.lastSent == stamp then
						closeSheet(player)
					end
				end)
			else
				closeSheet(player)
			end
		end
	end
	cancelAllOf(d, reason)
end

local function setPrompt(d: Dealer, on: boolean)
	if d.prompt then
		d.prompt.Enabled = on
	end
end

local function stopFight(d: Dealer)
	d.fightWith = nil
	d.fightUntil = 0
	d.fightSeq = (d.fightSeq or 0) + 1
end

local function hide(d: Dealer, why: string, from: Vector3?)
	local t = now()
	d.scaredAt = t
	d.scaredUntil = t + CFG.HIDE_QUIET_S
	if d.state == "hiding" or d.state == "fleeing" then
		return
	end
	stopFight(d)
	local line = pickLine(L.gunfire, d.amb)
	endTalksWith(d, line, "gunfire")
	say(d, line, 2.2)
	emote(d, "cb_flinchB")
	d.state = "hiding"
	setPrompt(d, false)
	local spot = nil
	if P and type(P.hiddenSpot) == "function" then
		local ok, s = pcall(P.hiddenSpot, d.home, CFG.HIDE_MIN, CFG.HIDE_MAX)
		spot = ok and s or nil
	end
	if not spot then
		local away = if from then (d.home - from) else Vector3.new(1, 0, 0)
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.1 then
			away = Vector3.new(1, 0, 0)
		end
		spot = d.home + away.Unit * 35
	end
	d.hideSpot = spot
	goTo(d, spot, CFG.RUN)
	dbg("hide", d.id, why)
end

local function flee(d: Dealer, from: Vector3?)
	stopFight(d)
	d.state = "fleeing"
	d.scaredAt = now()
	d.scaredUntil = now() + 35
	setPrompt(d, false)
	emote(d, "cb_flinchB")
	local spot = nil
	if P and type(P.hiddenSpot) == "function" then
		local ok, s = pcall(P.hiddenSpot, d.home, 30, 70)
		spot = ok and s or nil
	end
	if not spot then
		local away = if from then (d.home - from) else Vector3.new(0, 0, 1)
		away = Vector3.new(away.X, 0, away.Z)
		spot = d.home + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)) * 40
	end
	d.hideSpot = spot
	goTo(d, spot, CFG.RUN)
end

-- his own swings while he fights back (FightShared damage; never below PLAYER_MIN_HP)
local function fightBack(d: Dealer, player: Player)
	d.state = "fighting"
	d.fightWith = player
	d.fightUntil = now() + 6 + rnd() * 3
	d.fightSeq = (d.fightSeq or 0) + 1
	local seq = d.fightSeq
	setPrompt(d, false)
	local reach = (FS and FS.NPC_REACH) or 3.4
	local function still(): boolean
		return d.state == "fighting" and d.fightSeq == seq and d.fightWith == player and player.Parent ~= nil
	end
	task.spawn(function()
		local swings = 0
		while still() and now() < d.fightUntil and swings < 4 do
			task.wait(0.9 + rnd() * 0.5)
			if not still() then
				break
			end
			local pp = posOf(player)
			if not pp then
				break
			end
			local here = curPos(d)
			if flat(pp, here) > 9 then
				break -- the player ran: he does not chase far
			end
			faceTo(d, pp)
			if flat(pp, here) > reach + 1.2 then
				-- step in
				local dir = Vector3.new(pp.X - here.X, 0, pp.Z - here.Z)
				if dir.Magnitude > 0.1 then
					goTo(d, here + dir.Unit * math.max(0, dir.Magnitude - 2.6), 9)
				end
				task.wait(0.4)
				if not still() then
					break
				end
			end
			emote(d, if rnd() < 0.6 then "cb_jab" else "cb_hook")
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local pp2 = posOf(player)
			if hum and hum.Health > 0 and pp2 and flat(pp2, curPos(d)) < reach + 1.6 then
				local lo, hi = 6, 11
				if FS and FS.PLAYER_DMG then
					lo, hi = FS.PLAYER_DMG[1], FS.PLAYER_DMG[2]
				end
				local hp = math.max((FS and FS.PLAYER_MIN_HP) or 15, hum.Health - rng:NextInteger(lo, hi))
				if hp < hum.Health then
					hum.Health = hp
				end
			end
			swings += 1
		end
		if d.state == "fighting" and d.fightSeq == seq then
			if player.Parent then
				say(d, pickLine(L.after_fight, recOf(player, d.id)), 3)
			end
			stopFight(d)
			d.state = "returning"
			goTo(d, d.home, CFG.WALK)
		end
	end)
end

-- a hit on the dealer: returns the reaction ("fight" | "flee") and his line
local function onAttacked(player: Player, d: Dealer, info: any?): (string, string)
	local t = now()
	local rec = recOf(player, d.id)
	local shove = info and info.attack == "shove"
	rec.hits += 1
	rec.hitT = t
	relEvent(nil, nil, rec, "hit", if shove then 0.4 else 1)
	rec.tradeBlockUntil = math.max(rec.tradeBlockUntil, t + CFG.TRADE_BLOCK_S)
	saveRec(player, d.id, rec)
	-- word gets around: the other dealers are colder and refuse this player for a while
	for _, o in dealers do
		if o ~= d then
			local r2 = recOf(player, o.id)
			relEvent(nil, nil, r2, "provoke", if shove then 0.3 else 0.8)
			r2.rumourUntil = math.max(r2.rumourUntil, t + CFG.RUMOUR_BLOCK_S)
			saveRec(player, o.id, r2)
		end
	end
	-- the attacker's talk / shop with him ends
	if dialogs[player] and dialogs[player].dealer == d then
		closeSheet(player)
	end
	cancelShop(player, d, "attacked", nil)
	local pp = posOf(player)
	-- by personality: 공격성 0.5 / 겁 0.5 -> about 1 in 3 hits back (a shove: less); armed / hurt -> runs
	local p = (M and M.personality(C)) or PERS
	local hp = info and tonumber(info.hp)
	local max = info and tonumber(info.max)
	local hurt = hp and max and hp < max * 0.4
	local fightChance = (p.aggr or 0.5) * (1 - (p.fear or 0.5)) * 1.4 + (if rec.hits >= 2 then 0.15 else 0)
	if shove then
		fightChance *= 0.6
	end
	local react
	if armed(player) or hurt or d.state == "hiding" or d.state == "fleeing" or d.state == "returning" then
		react = "flee"
	elseif (d.state == "fighting" and d.fightWith == player) or rnd() < fightChance then
		react = "fight"
	else
		react = "flee"
	end
	local line
	if react == "fight" then
		line = pickLine(L.fight, rec)
		-- the other customers: business is over for now
		endTalksWith(d, pickLine(L.brawl, d.amb), "brawl")
		if d.state == "fighting" and d.fightWith == player then
			d.fightUntil = now() + 5
		else
			stopFight(d)
			fightBack(d, player)
		end
	else
		line = pickLine(L.flee, rec)
		endTalksWith(d, nil, "attacked")
		flee(d, pp)
	end
	say(d, line, 2.6)
	dbg("attacked", player.Name, d.id, react, "rel", relOf(rec))
	return react, line
end

-------------------------------------------------------------------------------------------------
-- Tick: life, danger, the open sheets / shops
-------------------------------------------------------------------------------------------------
local function tickDealer(d: Dealer, t: number)
	if d.state == "hiding" and arrived(d) and d.o.act ~= "cb_cower" then
		setAct(d, "cb_cower") -- crouched, arms over the head, until it is quiet
	end
	-- danger right here (also with nobody around: he hides from gunfire anyway)
	local danger, why = dangerAt(d.home, nil)
	if danger == "gunfire" then
		hide(d, why or "gunfire")
		return
	end
	if d.state == "hiding" or d.state == "fleeing" then
		if t > (d.scaredUntil or 0) and arrived(d) then
			d.state = "returning"
			goTo(d, d.home, CFG.WALK)
		end
		return
	end
	if d.state == "returning" then
		if arrived(d) then
			d.state = "idle"
			standHome(d)
			setPrompt(d, true)
			if now() - (d.lastSay or 0) > 20 then
				say(d, pickLine(L.back, d.amb), 2.6)
			end
		end
		return
	end
	if d.state == "fighting" then
		return
	end
	-- the law walks up / a fight starts: business is off (talks, requests in flight, open shops)
	if danger == "police" or danger == "brawl" then
		for player, dlg in dialogs do
			if dlg.dealer == d and not dlg.closing then
				endWith(player, dlg, dangerLine(danger, recOf(player, d.id)), 3)
			end
		end
		cancelAllOf(d, danger)
		if not d.lowUntil or t > d.lowUntil then
			d.lowUntil = t + 8
			setAct(d, "phone") -- nothing to see here
		end
	end
	-- open sheets: walked off / idle too long
	for player, dlg in dialogs do
		if dlg.dealer == d then
			local pp = posOf(player)
			local limit = if dlg.step == "wait" or dlg.step == "checking" or dlg.step == "opening" then CFG.WAIT_CLOSE_S else CFG.IDLE_CLOSE_S
			if player.Parent ~= Players or not pp or flat(pp, curPos(d)) > CFG.TALK_R then
				closeSheet(player)
			elseif t - (dlg.lastSent or dlg.opened) > limit then
				closeSheet(player)
			elseif pp and d.talkingWith == player then
				faceTo(d, pp)
			end
		end
	end
	-- the shop is open for somebody: he waits by them until they leave
	for player, tr in trading do
		if tr.dealer == d then
			local pp = posOf(player)
			if player.Parent ~= Players or not pp or flat(pp, d.home) > CFG.TRADE_LEAVE_R then
				cancelShop(player, d, "left", tr.reqId)
			elseif t - tr.t > CFG.TRADE_MAX_S then
				cancelShop(player, d, "timeout", tr.reqId)
			end
		end
	end
	-- life: idle acts, noticing people
	local talking = d.talkingWith ~= nil or d.tradingWith ~= nil
	if not talking and t >= (d.nextAct or 0) then
		d.nextAct = t + 14 + rnd() * 16
		d.idleAct = IDLE_ACTS[rng:NextInteger(1, #IDLE_ACTS)]
		d.o.yaw = d.yaw
		if d.o.model then
			d.o.model:SetAttribute("NpcYaw", d.yaw + (rnd() - 0.5) * 50)
		end
		setAct(d, d.idleAct)
		if rnd() < 0.2 and t - (d.lastSay or 0) > 25 then
			say(d, pickLine(L.mutter, d.amb), 2.6)
		end
	end
	if not talking then
		for _, pl in Players:GetPlayers() do
			local pp = posOf(pl)
			if pp and flat(pp, d.home) < CFG.NOTICE_R and math.abs(pp.Y - d.home.Y) < 8 then
				local rec = recOf(pl, d.id)
				if t - rec.noticeT > CFG.NOTICE_COOLDOWN and t - (d.lastSay or 0) > 6 then
					rec.noticeT = t
					local tier = tierOf(rec, (mafiaOf(pl, nil)))
					faceTo(d, pp)
					setAct(d, "idle")
					d.nextAct = t + 6
					say(d, pickLine(L.notice[tier] or L.notice.curt, rec), 2.8)
				end
				break
			end
		end
	end
end

local function tick()
	local t = now()
	-- old shots out
	while #gunfire > 0 and t - gunfire[1].t > 60 do
		table.remove(gunfire, 1)
	end
	for _, d in dealers do
		local ok, err = pcall(tickDealer, d, t)
		if not ok then
			warn("[GwangalliWeaponDealer] tick " .. d.id .. ": " .. tostring(err))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Spawn
-------------------------------------------------------------------------------------------------
local function spawnDealer(spot: any): Dealer?
	local feet, yaw = placeSpot(spot)
	local rig = buildRig(spot, feet, yaw)
	if not rig then
		return nil
	end
	local o = { id = spot.id, name = spot.name, model = rig.model, root = rig.root, ground = rig.ground, pos = feet, yaw = yaw, path = nil, speed = 0, cum = nil, t0 = now(), t0Server = serverNow(), act = "arms_crossed", role = "dealer", idleAct = "arms_crossed" }
	local d = { id = spot.id, name = spot.name, home = feet, yaw = yaw, o = o, state = "idle", nextAct = now() + rnd() * 10, idleAct = "arms_crossed", amb = { said = {} }, fightSeq = 0 }
	local root = rig.root
	if root and root:IsA("BasePart") then
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "DealerTalk"
		pr.ActionText = "말 걸기"
		pr.ObjectText = "총기상"
		pr.KeyboardKeyCode = Enum.KeyCode.E
		pr.HoldDuration = 0
		pr.MaxActivationDistance = CFG.PROMPT_R
		pr.RequiresLineOfSight = false
		pr.Parent = root
		pr.Triggered:Connect(function(player)
			local Util = ctx.Util
			if Util and type(Util.cooldown) == "function" and not Util.cooldown(player, "weaponDealerOpen", 0.5) then
				return
			end
			local ok, err = pcall(openTalk, player, d)
			if not ok then
				warn("[GwangalliWeaponDealer] talk failed: " .. tostring(err))
			end
		end)
		d.prompt = pr
	end
	table.insert(dealers, d)
	byId[d.id] = d
	return d
end

-------------------------------------------------------------------------------------------------
-- API (ctx.weaponDealer + ServerStorage.GwangalliWeaponDealerAPI)
-------------------------------------------------------------------------------------------------
function WeaponDealer.result(player: Player, requestId: string, ok: boolean, reason: string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(requestId) ~= "string" then
		return false
	end
	local pr = pending[requestId]
	if not pr or pr.player ~= player then
		if ok == true then
			-- an answer for a request that is over: the shop must close what it opened
			local dealerId = string.match(requestId, "^(dealer_%d+)%-")
			local d = dealerId and byId[dealerId]
			if d then
				cancelShop(player, d, "expired", requestId)
			end
		end
		return false
	end
	finishRequest(requestId, ok == true, if type(reason) == "string" then reason else nil)
	return true
end

function WeaponDealer.note(player: Player, dealerId: string, kind: string)
	local d = byId[dealerId]
	if not d or typeof(player) ~= "Instance" or type(kind) ~= "string" then
		return false
	end
	local rec = recOf(player, d.id)
	if kind == "trade" then
		rec.trades += 1
		rec.boughtT = now()
	end
	relEvent(player, d.id, rec, kind)
	return true
end

function WeaponDealer.closed(player: Player)
	local tr = trading[player]
	if tr then
		trading[player] = nil
		if tr.dealer.tradingWith == player then
			tr.dealer.tradingWith = nil
		end
		local rec = recOf(player, tr.dealer.id)
		say(tr.dealer, pickLine(if rec.boughtT >= tr.t then L.after_buy else L.after_look, rec), 2.8)
	end
	return true
end

function WeaponDealer.attacked(player: Player, dealerId: string, info: any?)
	local d = byId[dealerId]
	if not d or typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	local react, line = onAttacked(player, d, if type(info) == "table" then info else nil)
	return { react = react, line = line }
end

function WeaponDealer.gunfire(pos: Vector3, _shooter: Player?)
	if typeof(pos) ~= "Vector3" then
		return false
	end
	table.insert(gunfire, { pos = pos, t = now() })
	if #gunfire > 40 then
		table.remove(gunfire, 1)
	end
	return true
end

function WeaponDealer.relation(player: Player, dealerId: string): number?
	local d = byId[dealerId]
	if not d or typeof(player) ~= "Instance" then
		return nil
	end
	return relOf(recOf(player, d.id))
end

function WeaponDealer.dealers(): { any }
	local out = {}
	for _, d in dealers do
		table.insert(out, { id = d.id, name = d.name, pos = curPos(d), home = d.home, state = d.state, talking = d.talkingWith and d.talkingWith.Name or nil, trading = d.tradingWith and d.tradingWith.Name or nil })
	end
	return out
end

function WeaponDealer.isDealer(id: string): boolean
	return byId[id] ~= nil
end

-- test harness only (workspace.GwangalliStreetLifeDebug): drive a talk without the prompt / sheet
function WeaponDealer.debug(player: Player, p: any): any
	if not debugOn() or type(p) ~= "table" then
		return { ok = false, err = "off" }
	end
	local d = byId[p.id or "dealer_1"] or dealers[1]
	if not d then
		return { ok = false, err = "no dealer" }
	end
	local rec = recOf(player, d.id)
	if p.op == "open" then
		openTalk(player, d)
	elseif p.op == "choose" then
		local dlg = dialogs[player]
		if dlg and dlg.choices[p.choice] then
			onChoice(player, dlg, p.choice)
		end
	elseif p.op == "rel" then
		rec.rel = math.clamp(tonumber(p.rel) or 0, -100, 100)
		rec.relT = now()
		rec.blockUntil, rec.tradeBlockUntil, rec.rumourUntil = 0, 0, 0
		rec.hitT = nil
		rec.tk = tonumber(p.tk) or rec.tk
		table.clear(rec.opens)
		for _, o in dealers do
			local r2 = recOf(player, o.id)
			r2.rumourUntil = 0
		end
	elseif p.op == "hit" then
		onAttacked(player, d, { attack = "punch" })
	elseif p.op == "gunfire" then
		WeaponDealer.gunfire(d.home + Vector3.new(10, 0, 0))
	elseif p.op == "mock" then
		workspace:SetAttribute("GwangalliWeaponShopMock", p.on ~= false)
		workspace:SetAttribute("GwangalliWeaponShopMockReason", if type(p.reason) == "string" then p.reason else nil)
	elseif p.op == "attr" and type(p.name) == "string" then
		player:SetAttribute(p.name, p.value)
	elseif p.op == "closed" then
		WeaponDealer.closed(player)
	end
	local dlg = dialogs[player]
	local ch = {}
	if dlg then
		for k in dlg.choices do
			table.insert(ch, k)
		end
		table.sort(ch)
	end
	local pp = posOf(player)
	local front = d.home + Vector3.new(math.sin(math.rad(d.yaw)) * -4, 3, math.cos(math.rad(d.yaw)) * -4)
	return {
		ok = true,
		id = d.id,
		tx = front.X,
		ty = front.Y,
		tz = front.Z,
		hx = d.home.X,
		hy = d.home.Y,
		hz = d.home.Z,
		state = d.state,
		rel = math.floor(relOf(rec) * 10 + 0.5) / 10,
		tier = dlg and dlg.tier,
		step = dlg and dlg.step,
		text = dlg and dlg.lastText,
		choices = table.concat(ch, ","),
		trading = trading[player] ~= nil,
		say = d.bubble and d.bubble.Enabled and (d.bubble:FindFirstChild("Text") :: TextLabel).Text or nil,
		dist = pp and flat(pp, curPos(d)) or nil,
		mafia = (mafiaOf(player, nil)),
		danger = (dangerAt(d.home, player)),
		cancel = lastCancel,
		act = d.o.act,
	}
end

-------------------------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------------------------
function WeaponDealer.onCharacter(player: Player, _char: Model)
	-- a respawn hides the sheet without telling the server; an open shop ends
	local dlg = dialogs[player]
	if dlg then
		dialogs[player] = nil
		if dlg.dealer.talkingWith == player then
			dlg.dealer.talkingWith = nil
		end
		if dlg.reqId and pending[dlg.reqId] then
			cancelShop(player, dlg.dealer, "respawn", dlg.reqId)
		end
	end
	local tr = trading[player]
	if tr then
		cancelShop(player, tr.dealer, "respawn", tr.reqId)
	end
end

function WeaponDealer.onLeave(player: Player)
	local tr = trading[player]
	if tr then
		cancelShop(player, tr.dealer, "left", tr.reqId)
	end
	local mine = {}
	for id, pr in pending do
		if pr.player == player then
			table.insert(mine, { pr.dealer, id })
		end
	end
	for _, e in mine do
		cancelShop(player, e[1], "left", e[2])
	end
	dialogs[player] = nil
	trading[player] = nil
	for _, d in dealers do
		if d.talkingWith == player then
			d.talkingWith = nil
		end
		if d.tradingWith == player then
			d.tradingWith = nil
		end
		if d.fightWith == player then
			stopFight(d)
		end
	end
	-- save, then keep only the records worth remembering on this server (blocks, a bad relation)
	local u = recs[player.UserId]
	if u then
		local t = now()
		for id, r in u do
			saveRec(player, id, r)
		end
		local drop = {}
		for id, r in u do
			table.clear(r.opens)
			if math.abs(r.rel or 0) < 1 and r.blockUntil <= t and r.tradeBlockUntil <= t and r.rumourUntil <= t and r.hits == 0 then
				table.insert(drop, id)
			end
		end
		for _, id in drop do
			u[id] = nil
		end
		if next(u) == nil then
			recs[player.UserId] = nil
		end
	end
end

function WeaponDealer.init(context: any)
	ctx = context
	local function opt(name: string): any
		local m = ReplicatedStorage:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok then
				return res
			end
			warn("[GwangalliWeaponDealer] " .. name .. ": " .. tostring(res))
		end
		return nil
	end
	M = opt("GwangalliMindShared")
	LS = opt("GwangalliLawShared")
	FS = opt("GwangalliFightShared")
	Looks = opt("GwangalliNPCLooks")
	D = opt("GwangalliWeaponDealerShared")
	assert(D, "GwangalliWeaponDealerShared missing")
	local nm = script.Parent and script.Parent:FindFirstChild("NPC")
	if nm and nm:IsA("ModuleScript") then
		local ok, res = pcall(require, nm)
		NPC = if ok then res else nil
	end
	ctx.weaponDealer = WeaponDealer
	-- the contract instances (events are safe to own: firing one with no listener does nothing)
	local f = ServerStorage:FindFirstChild(D.FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = D.FOLDER
		f.Parent = ServerStorage
	end
	local function event(name: string): BindableEvent
		local e = f:FindFirstChild(name)
		if not e or not e:IsA("BindableEvent") then
			e = Instance.new("BindableEvent")
			e.Name = name
			e.Parent = f
		end
		return e :: BindableEvent
	end
	requestEvent = event(D.REQUEST_EVENT)
	cancelEvent = event(D.CANCEL_EVENT)
	local resultEvent = event(D.RESULT_EVENT)
	resultEvent.Event:Connect(function(player, requestId, ok, reason)
		pcall(WeaponDealer.result, player, requestId, ok, reason)
	end)
	local closedEvent = event(D.CLOSED_EVENT)
	closedEvent.Event:Connect(function(player)
		if typeof(player) == "Instance" and player:IsA("Player") then
			pcall(WeaponDealer.closed, player)
		end
	end)
	-- any gun system: a shot was fired here
	local ge = ServerStorage:FindFirstChild(D.GUNFIRE_EVENT)
	if not ge then
		ge = Instance.new("BindableEvent")
		ge.Name = D.GUNFIRE_EVENT
		ge.Parent = ServerStorage
	end
	if ge:IsA("BindableEvent") then
		ge.Event:Connect(function(pos, shooter)
			pcall(WeaponDealer.gunfire, pos, shooter)
		end)
	end
	-- the API BindableFunction (we own its handler, so an Invoke never hangs)
	local API_OPS = { result = true, note = true, closed = true, attacked = true, gunfire = true, relation = true, dealers = true, isDealer = true }
	local api = ServerStorage:FindFirstChild(D.API)
	if not api then
		api = Instance.new("BindableFunction")
		api.Name = D.API
		api.Parent = ServerStorage
	end
	if api:IsA("BindableFunction") then
		(api :: BindableFunction).OnInvoke = function(op: string, ...)
			if type(op) ~= "string" or not API_OPS[op] then
				return nil
			end
			local ok, a, b = pcall(WeaponDealer[op], ...)
			if ok then
				return a, b
			end
			return nil
		end
	end
	-- dialog choices come back through the overlay's PhoneAction "dialogChoice"
	local pa = ctx.remotes and ctx.remotes.PhoneAction
	if pa then
		pa.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
			if action == "dialogChoice" and dialogs[player] then
				onPhoneAction(player, action, payload)
			end
		end)
	end
	task.spawn(function()
		-- after the map / the nav graph are there (Law/Crimes waits the same)
		task.wait(8)
		local Law = ctx.law
		P = Law and Law.children and Law.children.Police or nil
		-- a hit on him (GwangalliGameplay/Fight: Fight.hitHooks by id prefix)
		local F = ctx.fight
		if F and type(F.hitHooks) == "table" then
			F.hitHooks["dealer_"] = function(player: Player, id: string, info: any)
				local d = byId[id]
				if not d then
					return nil
				end
				local react = onAttacked(player, d, info)
				-- he does not fall like a key NPC of NPC.luau: a stagger on the rig
				if d.o.model and info and (info.outcome == "stagger" or info.outcome == "knockdown") then
					d.o.model:SetAttribute("NpcKnock", string.format("%.2f|%.3f|%.3f|%s", serverNow(), info.dx or 0, info.dz or -1, "stagger"))
				end
				-- "" = no second bubble from Fight's client (his own bubble already shows the line)
				return react, ""
			end
		end
		-- 어깨빵 on him (the base Bump server only knows the roster: we take the dealer ids)
		local bf = ReplicatedStorage:FindFirstChild("GwangalliBump")
		local ba = bf and bf:FindFirstChild("BumpAction")
		if ba and ba:IsA("RemoteEvent") then
			(ba :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
				if kind ~= "bump" or type(payload) ~= "table" or payload.target ~= "npc" or type(payload.id) ~= "string" then
					return
				end
				local d = byId[payload.id]
				if not d or d.state == "fleeing" or d.state == "hiding" then
					return
				end
				local Util = ctx.Util
				if Util and type(Util.cooldown) == "function" and not Util.cooldown(player, "weaponDealerBump", 1.2) then
					return
				end
				local pp = posOf(player)
				if not pp or flat(pp, curPos(d)) > 7 then
					return
				end
				pcall(onAttacked, player, d, { attack = "shove" })
				if d.o.model then
					local c = curPos(d)
					local dir = Vector3.new(c.X - pp.X, 0, c.Z - pp.Z)
					dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, -1)
					d.o.model:SetAttribute("NpcKnock", string.format("%.2f|%.3f|%.3f|%s", serverNow(), dir.X, dir.Z, "stagger"))
				end
			end)
		end
		for _, spot in SPOTS do
			local ok, err = pcall(spawnDealer, spot)
			if not ok then
				warn("[GwangalliWeaponDealer] spawn " .. spot.id .. ": " .. tostring(err))
			end
		end
		print(string.format("[GwangalliWeaponDealer] ready: %d dealers (shop system %s)", #dealers, if systemReady() then "connected" else "not connected yet"))
		while true do
			task.wait(0.5)
			tick()
		end
	end)
end

return WeaponDealer
