-- GwangalliRobShared (owner: npc_mind): the 강탈 (robbery) RULES of NPCs, as data other systems read.
-- This module only says WHO can be robbed, WHAT they carry and HOW MUCH it is worth in which state.
-- It does NOT pay money, raise the wanted level, call the police or judge success / failure: the
-- crime system that does the robbing reads these rules (and the live state below) and does that.
--
-- 배달 라이더 (delivery NPCs) are the special case: they carry the 배달가방 (food + the day's 배달비),
-- so a robbery is worth more than an ordinary pedestrian's wallet; but a rider who is down (KO /
-- "dead") has nothing to hand over: the bag is spilled / the cash is gone with the ambulance ->
-- reward 0. So keeping them alive (scared / surrendered) and robbing them pays; killing does not.
--
-- LIVE STATE (where to read it):
--   * client, street pedestrians (their rigs only exist on each client):
--       rig model attributes  GwRobbable (bool)  GwRobKind ("delivery" | "ped")  GwRobReward (number,
--       already 0 when down / robbed)  GwRobState ("ok" | "scared" | "surrender" | "fleeing" |
--       "reporting" | "robbed" | "dead")  GwRobDead (bool)  GwDelivery ("scooter" | "walk" | nil)
--       LocalPlayer.GwangalliNPCRobAPI (BindableFunction): ("info", model | streetId) -> info table
--         ("list") -> { info... } of the people around; ("threat", model | streetId, kind?) -> the NPC
--         reacts as threatened (for a gun / weapon system); ("robbed", model | streetId) -> marks
--         them robbed (the crime system calls this after its own success roll; reward -> 0 for a while)
--   * server: ServerStorage.GwangalliNPCRobAPI (BindableFunction): ("info", player, id) -> info
--     (HP / KO from GwangalliGameplay.Fight: the authority on "dead"); ("robbed", player, id).
-- info = { id, kind, robbable, reward, base, dead, state, carries, surrendered }
--
-- REWARD (Rob.rewardFor): base by kind (a stable roll per NPC id inside the kind's range) x the
-- state factor: surrender 1.15 (they hand it all over), scared / ok 1.0, fleeing 0.6 (some dropped
-- or got away with it), reporting 0.9, robbed 0 (cooldown ROBBED_COOLDOWN s), dead / KO 0.

local Rob = {}

Rob.VERSION = 1

Rob.KIND = {
	delivery = {
		robbable = true,
		label = "배달 라이더",
		carries = "배달가방 (음식 · 배달비 현금)",
		reward = { 45000, 90000 }, -- 원
	},
	ped = {
		robbable = true,
		label = "행인",
		carries = "지갑",
		reward = { 8000, 22000 },
	},
	police = { robbable = false, label = "경찰", carries = "", reward = { 0, 0 } },
	none = { robbable = false, label = "", carries = "", reward = { 0, 0 } },
}

Rob.STATE_MULT = { ok = 1, scared = 1, surrender = 1.15, fleeing = 0.6, reporting = 0.9, robbed = 0, dead = 0 }
Rob.ROBBED_COOLDOWN = 900 -- s: a robbed rider has nothing left until their next run
Rob.Attr = {
	Robbable = "GwRobbable",
	Kind = "GwRobKind",
	Reward = "GwRobReward",
	State = "GwRobState",
	Dead = "GwRobDead",
	Delivery = "GwDelivery",
}

local function hash01(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = (bit32.bxor(h, string.byte(s, i)) * 16777619) % 4294967296
	end
	return (h % 100000) / 100000
end

-- the kind of an NPC: a roster citizen (c.delivery / persona rider -> delivery, police -> police)
-- or a crowd type id
function Rob.kindOf(c: any?, typeId: string?): string
	if type(c) == "table" then
		if c.delivery or c.persona == "rider" then
			return "delivery"
		end
		if c.type == "police" or c.persona == "police" then
			return "police"
		end
		if c.key then
			return "none" -- shops / quest NPCs are not street robbery targets
		end
		return "ped"
	end
	if typeId == "police" then
		return "police"
	end
	if typeId == "delivery" or typeId == "rider" then
		return "delivery"
	end
	return "ped"
end

-- the stable base amount of this NPC (same id = same amount)
function Rob.baseFor(id: string, kind: string): number
	local K = Rob.KIND[kind] or Rob.KIND.none
	local lo, hi = K.reward[1], K.reward[2]
	local v = lo + (hi - lo) * hash01(id or "?")
	return math.floor(v / 1000 + 0.5) * 1000
end

-- state -> reward (0 when not robbable / dead / robbed)
function Rob.rewardFor(id: string, kind: string, state: string?, dead: boolean?): number
	local K = Rob.KIND[kind] or Rob.KIND.none
	if not K.robbable or dead then
		return 0
	end
	local m = Rob.STATE_MULT[state or "ok"] or 1
	return math.floor(Rob.baseFor(id, kind) * m / 1000 + 0.5) * 1000
end

function Rob.info(id: string, c: any?, typeId: string?, state: string?, dead: boolean?): any
	local kind = Rob.kindOf(c, typeId)
	local K = Rob.KIND[kind] or Rob.KIND.none
	local st = if dead then "dead" else (state or "ok")
	return {
		id = id,
		kind = kind,
		robbable = K.robbable and not dead and st ~= "robbed",
		reward = Rob.rewardFor(id, kind, st, dead),
		base = Rob.baseFor(id, kind),
		dead = dead == true,
		state = st,
		carries = K.carries,
		surrendered = st == "surrender",
	}
end

function Rob.selfTest(): { string }
	local bad = {}
	local a = Rob.info("rider_hoon", { persona = "rider" }, nil, "ok", false)
	local d = Rob.info("rider_hoon", { persona = "rider" }, nil, "ok", true)
	local p = Rob.info("x12", nil, "plain", "ok", false)
	if a.kind ~= "delivery" or not a.robbable or a.reward <= 0 then
		table.insert(bad, "delivery alive")
	end
	if d.reward ~= 0 or d.robbable then
		table.insert(bad, "delivery dead must be 0")
	end
	if p.reward >= Rob.KIND.delivery.reward[1] then
		table.insert(bad, "ped reward must be below delivery")
	end
	if Rob.info("rider_hoon", { persona = "rider" }, nil, "surrender", false).reward < a.reward then
		table.insert(bad, "surrender pays at least as much")
	end
	return bad
end

return Rob
