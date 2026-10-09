-- GwangalliFightShared: the contract of 길거리 싸움 (street fights) on top of the NPC mind / 어깨빵 /
-- Law systems. Pure data + pure functions (server and client).
--
--   * HITS IN: no button / key of its own. A hit that LANDED reaches the NPC side through the receiver:
--     the player's combat system calls LocalPlayer.GwangalliNPCHitAPI:Invoke("hit", { model = <the
--     touched NPC Model or part>, attack = "punch" | "kick" | "shove" | "strong", power }) (client) or
--     ServerStorage.GwangalliNPCHitAPI:Invoke("hit", player, { model | kind, id, attack, power })
--     (server); 어깨빵, the talk card's 때리기 and car hits call the same server code. Targets: street
--     pedestrians (GwangalliStreetLife, client-side rigs, StreetId) and any server rig with an NpcId
--     (workspace.GwangalliNPCs, shop staff tagged GwShopStaff), except the jail's inmates and the rigs
--     of 알바 / minigames (F.foreign: they are not this system's). The SERVER (GwangalliGameplay/Fight)
--     keeps every NPC's HP, decides damage / outcome / reaction and records the crime with Law; a
--     combat system should not keep its own HP for these targets.
--   * HP: by NPC type (HP_BY_TYPE). Regenerates slowly when left alone (REGEN per second after
--     REGEN_DELAY). 0 HP = 쓰러짐 (KO): the person stays down (KO_DOWN s), witnesses call 119 / 112,
--     then they are taken away (fade out). A named citizen who went down is 입원 (in hospital) for
--     HOSPITAL_S seconds: not seen on the street until then. Key NPCs (shops, quests) never go below
--     KEY_MIN_HP: they are knocked down and report instead. Law units on foot (police / 특임대 / 119) do
--     go down at 0 HP (NpcDown on the rig: lying there until the ambulance / the time takes them).
--   * OUTCOME of a hit: "stagger" (a jolt, a step back) | "knockdown" (falls, gets up) | "thrown" (a
--     car at speed / a critical strong blow: knocked off the feet and slides a few studs, scripted, no
--     physics; key NPCs show it as a knockdown) | "ko".
--   * REACTION (server): fight (they fight back: a real brawl, several swings, BRAWL_S s), flee,
--     report (phone call: the police know at once), arrest (an officer), ko.
--   * NPC SWINGS (client -> server "npcHit"): only from an NPC the server put in a brawl with this
--     player, within NPC_REACH, at most every NPC_SWING_GAP s; the player loses PLAYER_DMG (never below
--     PLAYER_MIN_HP: a street fight knocks you down, it does not kill you).
--   * NPC vs NPC fights (client scenes) end with a report now and then ("npcFight" -> an officer walks
--     over and breaks it up); 취객 시비 (drunks picking a quarrel at night) is client behaviour with
--     lines from DRUNK_LINES.
--
-- REMOTES (ReplicatedStorage.GwangalliFight): Action (RemoteEvent, client -> server):
--   "punch"    { kind = "ped" | "npc", id, pos = {x,y,z}, ptype?, attack?, power?, sn? }   ptype = the
--              pedestrian's crowd type, sn = its spawn serial (a reused anonymous id is a new person)
--   "npcHit"   { id, pos, attack? }                                  a brawling NPC's swing landed on you
--              (attack = "punch" | "shove" | "kick": ATTACK[attack].dmg scales PLAYER_DMG)
--   "npcStart" { id, ptype, pos, why, secs }                         a street NPC picks a fight (secs = its
--              brawl window, BRAWL_S; refused -> "brawlEnd")
--   "npcFight" { pos, a, b }                                         an NPC fight seen (bystander report)
-- Event (RemoteEvent, server -> client):
--   "hit"   { kind, id, dmg, hp, max, outcome = "stagger" | "knockdown" | "thrown" | "ko", react, line?,
--             crit, dx, dz, brawl? }                                  brawl = the fight-back window (s)
--   "miss"  { reason }
--   "hurt"  { dmg, hp, by, attack?, dx?, dz?, outcome? }             you took a swing (outcome: a server
--             rig's swing, the client plays the fall)
--   "brawlEnd" { id }                                                 the server refused that NPC's fight
--   "say"   { id, line }                                              a key NPC's bubble (after its fight)
--   "down"  { ids = { id = untilUnix } }                             citizens in hospital (on join / change)

local F = {}

F.Folder = "GwangalliFight"
F.Remote = { Action = "Action", Event = "Event" }

F.RANGE = 5.6 -- studs, player root to the target's root (flat)
F.COOLDOWN = 0.55 -- s between punches
F.DMG = { 11, 19 }
F.CRIT_CHANCE = 0.12
F.CRIT_MULT = 1.7
F.KNOCKDOWN_CHANCE = 0.22 -- a normal hit; a crit always knocks down
F.REGEN_DELAY = 20
F.REGEN = 2 -- HP per second
F.KO_DOWN = 26 -- s lying there before they are taken away
F.HOSPITAL_S = 600 -- a named citizen is off the street this long after going down
F.KEY_MIN_HP = 12
F.BRAWL_S = { 9, 14 }
F.NPC_REACH = 3.4
F.NPC_SWING_GAP = 0.9
F.PLAYER_DMG = { 6, 11 }
F.PLAYER_MIN_HP = 15

-- crowd / citizen types -> max HP
F.HP_BY_TYPE = {
	plain = 100,
	violent = 140,
	thug = 140,
	punk = 120,
	hothead = 115,
	fool = 95,
	beggar = 70,
	drunk = 85,
	police = 170,
	swat = 320, -- 특임대 (GwangalliGameplay/Law/Swat)
	elder = 60,
	student = 85,
	rich = 90,
	tourist = 95,
	clerk = 100,
}
F.DEFAULT_HP = 100

-- the crowd types a client may claim for an anonymous pedestrian ("x12"); anything else = plain
F.PED_TYPES = { plain = true, violent = true, fool = true, beggar = true, drunk = true }

function F.maxHp(typeId: string?): number
	return F.HP_BY_TYPE[typeId or "plain"] or F.DEFAULT_HP
end

-- rigs of the systems this one must not drive (base 알바 JobWorld customers "shop_*" / JobDelivery
-- recipients "recipient_*", MiniGames hosts "mg_*" and their stations): no hit, no HP, no reaction
F.FOREIGN_PREFIX = { "shop_", "recipient_", "mg_" }
F.FOREIGN_ATTR = { "ShopCustomer", "DeliveryFor", "MiniGameHost", "StationId" }
function F.foreign(id: any, model: Instance?): boolean
	if type(id) == "string" then
		for _, p in F.FOREIGN_PREFIX do
			if string.sub(id, 1, #p) == p then
				return true
			end
		end
	end
	if model then
		for _, a in F.FOREIGN_ATTR do
			if model:GetAttribute(a) ~= nil then
				return true
			end
		end
	end
	return false
end

-- damage + outcome for one punch. r = a function returning 0..1 (math.random on the server)
function F.roll(r: () -> number, strength: number?): (number, boolean, string)
	local lo, hi = F.DMG[1], F.DMG[2]
	local dmg = lo + (hi - lo) * r()
	-- 근력 (0..100) adds up to +25%
	dmg *= 1 + math.clamp((strength or 0) / 100, 0, 1) * 0.25
	local crit = r() < F.CRIT_CHANCE
	if crit then
		dmg *= F.CRIT_MULT
	end
	local outcome = if crit or r() < F.KNOCKDOWN_CHANCE then "knockdown" else "stagger"
	return math.floor(dmg + 0.5), crit, outcome
end

-- attack kinds a combat system may report: damage factor, knock rule
F.ATTACK = {
	shove = { dmg = 0.35, noCrit = true, knock = "stagger" },
	punch = { dmg = 1 },
	kick = { dmg = 1.4 },
	strong = { dmg = 1.8, knock = "knockdown" },
	car = { dmg = 1, noCrit = true },
}

F.LINES = {
	hit = { "아악!", "왜 때려요!", "아파!!", "미쳤어요?!", "으윽…" },
	fight = { "너 오늘 제삿날이다!", "어쭈? 덤벼!", "한 판 붙자 이거지?", "가만 안 둬!", "맞고만 있을 줄 알았냐!" },
	flee = { "살려주세요!!", "도망쳐야 돼!", "저리 가요!!", "누가 좀 도와줘요!" },
	report = { "경찰 부를 거예요! 112죠?", "여보세요, 경찰이죠? 여기 사람이 때려요!", "신고했어요! 거기 있어요!" },
	arrest = { "경찰 폭행이다! 당장 체포한다!", "공무집행방해 현행범으로 체포합니다!" },
	ko = { "으…", "…", "끄응…" },
	warn = { "진짜 계속 할 거야?", "한 번 더 건드려 봐.", "뭐 하는 거예요?!", "그만하세요. 진짜로.", "어딜 감히…!" },
	cower = { "저, 저한테 왜 그러세요…", "제발 그만해요…", "항복! 항복이에요!", "잘못했어요, 그만…" },
	witness_ko = { "사람이 쓰러졌어요!!", "119 불러요, 119!", "괜찮으세요?! 정신 차려요!", "경찰! 경찰 불러!" },
	swing = { "받아라!", "이얍!", "어딜!", "퍽!" },
	brawl_end = { "다음엔 가만 안 둔다…", "오늘은 봐준다!", "헉헉… 됐다 됐어." },
	-- hit by the player's car (GwangalliFight "car": car_<react>, else car_hit; car_hurt = the client's
	-- line when they get up hurt)
	car_hit = { "아악! 차!!", "으윽… 다리…", "어어억…!", "쾅… 으으…" },
	car_warn = { "운전 똑바로 해요!", "사람 칠 뻔했잖아요!", "눈 감고 운전해요?!", "아 진짜, 사람 다니는 데서!", "차 세워 봐요!" },
	car_report = { "여보세요, 112죠? 차가 사람을 쳤어요!", "번호판 다 봤어요! 신고합니다!", "뺑소니예요! 경찰 불러요!" },
	car_flee = { "으악, 차다!!", "저 차 미쳤어!", "피해요!!" },
	car_cower = { "으윽… 움직일 수가 없어…", "다리가… 다리가…", "살려 주세요…" },
	car_hurt = { "아… 다리…", "으윽… 허리야…", "아야… 차 좀 보고 다녀요…", "절뚝… 아이고…" },
}

-- 취객 시비 (late at night a drunk picks a quarrel)
F.DRUNK_LINES = {
	start = { "어이~ 거기 너! 뭘 꼬나봐?", "야… 너 나 알아? 어? 딸꾹", "어이 친구~ 술 한잔 사 봐~", "너… 아까 나 쳐다봤지? 어?" },
	follow = { "어디 가~ 얘기 좀 하자니까~", "야 야 서 봐! 딸꾹", "내가 왕년에 말이야…", "왜 무시해 어?!" },
	shove = { "비켜 봐 이 자식아~!", "어딜 감히~!", "에잇!" },
	calm = { "에휴… 됐다 됐어. 딸꾹", "아 미안 미안~ 내가 취했나 봐…", "그래 너 좋은 놈이다~" },
}

-- NPC vs NPC fight: the officer who breaks it up
F.BREAKUP = { "거기! 그만하세요!", "싸우지 마세요, 경찰입니다!", "두 분 다 진정하세요!" }

return F
