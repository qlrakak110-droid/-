--!strict
-- GwangalliWeaponDealerShared: the CONTRACT between the 총기상 NPC (GwangalliGameplay/WeaponDealer, NPC session)
-- and the crime session's WeaponShopSystem. Read-only data: no prices, no stats, no purchase here.
--
--   WeaponDealerNPC --RequestWeaponShop--> WeaponShopSystem (crime session) --checks--> OpenWeaponShopUI
--
-- The dealer NEVER sells, never takes money and never gives a gun. It only: notices the player, talks,
-- asks the WeaponShopSystem whether this player may trade right now, and passes the request on. The shop
-- system decides everything after that (access, what is on the shelf, prices, money, the gun) and opens its
-- own UI (its own RemoteEvent OpenWeaponShopUI).
--
-- HOW THE CRIME SESSION HOOKS IN (any ONE of these; checked in this order):
--   1) a module table on the shared server context: ctx.weaponShop = {
--        request = function(player, req) -> (ok: boolean?, reason: string?) | { ok, reason },
--            -- return nil to answer later through ctx.weaponDealer.result(player, req.requestId, ok, reason)
--        access = function(player) -> { mafia: boolean?, allowed: boolean?, reason: string? }?,  -- optional
--      }
--   2) instances in ServerStorage.GwangalliWeaponShop (Folder, made by the dealer if missing):
--        RequestWeaponShop  BindableEvent    (dealer fires (player, req); the shop system connects)
--        WeaponShopResult   BindableEvent    (the shop system fires (player, requestId, ok, reason))
--        Folder attribute   Ready = true     (the shop system sets it once it listens; without it the dealer
--                                             says "물건이 없다" at once instead of waiting)
--        WeaponShopAccess   BindableFunction (OPTIONAL, made by the shop system only: (player) -> access table)
--   The mafia flag comes from access().mafia (the crime / job system). Without an access source the dealer
--   reads the job / crime state read-only (see MAFIA below) for its LINES only; the shop system re-checks.
--
-- REQUEST payload (req):
--   { requestId: string, dealerId: string, dealerName: string, dealerPos: {x,y,z},
--     offer: "basic" | "special",       -- "special" only for players the crime/job side calls mafia
--     mafia: boolean, mafiaSource: string ("access" | "job" | "crime" | "none"),
--     rel: number (-100..100), relLabel: string, mood: string, at: number (os.time) }
--
-- ANSWER reasons the dealer has lines for (anything else -> a generic refusal):
--   "denied" "not_allowed" "cooldown" "not_mafia" "closed" "no_stock" "wanted" "money" "busy" "level"
--
-- The dealer's server API for the shop system (ctx.weaponDealer, or the BindableFunction
-- ServerStorage.GwangalliWeaponDealerAPI with the same op names):
--   result(player, requestId, ok, reason)   the answer to an async request
--   note(player, dealerId, kind)            "trade" (a sale went through: the dealer warms up), "haggle", "scam"
--   closed(player)                          the shop UI was closed (the dealer goes back to idle)
--   attacked(player, dealerId, info?)       another combat / gun system hit the dealer
--   gunfire(pos, shooter?)                  a shot was fired here (the dealer hides; trades stop)
--   relation(player, dealerId) -> number    read the dealer's relation with this player
--   dealers() -> { {id, name, pos, state} }

local D = {}

D.FOLDER = "GwangalliWeaponShop"
D.REQUEST_EVENT = "RequestWeaponShop"
D.RESULT_EVENT = "WeaponShopResult"
D.ACCESS_FUNCTION = "WeaponShopAccess"
D.OPEN_UI_REMOTE = "OpenWeaponShopUI" -- owned and fired by the crime session (the dealer never touches it)
D.API = "GwangalliWeaponDealerAPI"
D.GUNFIRE_EVENT = "GwangalliGunfire" -- ServerStorage BindableEvent (pos: Vector3, shooter: Player?) any gun system may fire

D.OFFER = { basic = "basic", special = "special" }

D.REASONS = { "denied", "not_allowed", "cooldown", "not_mafia", "closed", "no_stock", "wanted", "money", "busy", "level" }

-- 마피아 (read-only sources, in this order). The dealer never grants or decides it.
D.MAFIA = {
	-- player attributes a job system may set
	attrs = { "GwMafia", "Mafia" },
	jobAttrs = { "GwJob", "Job", "JobId", "GwJobId" },
	jobIds = { mafia = true, ["마피아"] = true, gang = true, ["조직"] = true, ["조직원"] = true },
	-- the crime system's own rank (Law crime level >= LawShared.ORG_LEVEL = 조직 수습): lines only
	useCrimeLevel = true,
}

return D
