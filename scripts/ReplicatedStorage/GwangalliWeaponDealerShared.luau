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
-- HOW THE CRIME SESSION HOOKS IN (ONE path per request: the module API when it is there, else the events):
--   1) a module table on the shared server context: ctx.weaponShop = {
--        request = function(player, req) -> (ok: boolean?, reason: string?) | { ok, reason },
--            -- return nil to answer later through ctx.weaponDealer.result(player, req.requestId, ok, reason)
--        access = function(player) -> { mafia: boolean?, allowed: boolean?, reason: string? }?,  -- optional
--        cancel = function(player, info) -> (),  -- optional: close the shop / drop the request (see CANCEL)
--      }
--   2) instances in ServerStorage.GwangalliWeaponShop (Folder; the dealer makes the folder and the events):
--        RequestWeaponShop  BindableEvent    dealer -> shop: (player, req)
--        WeaponShopResult   BindableEvent    shop -> dealer: (player, requestId, ok, reason?)
--        WeaponShopCancel   BindableEvent    dealer -> shop: (player, { requestId?, dealerId, reason })
--        WeaponShopClosed   BindableEvent    shop -> dealer: (player)   the shop UI was closed by the player
--        Folder attribute   Ready = true     the shop system sets it once it listens (without it the dealer
--                                            says "물건이 없다" and sends NO request)
--        WeaponShopAccess   BindableFunction OPTIONAL, made by the shop system only: (player) -> access table
--
-- RULES for the shop system:
--   * open OpenWeaponShopUI only for a request it accepted (request() returned ok, or it called result(.., true));
--     an accepted request the dealer no longer wants (the talk closed meanwhile) comes back as a CANCEL
--     (reason "expired") — close the UI then.
--   * on CANCEL close the shop UI for that player at once. Reasons: "attacked" (the player hit the dealer),
--     "gunfire" (shots / SWAT / 총격전 nearby), "police" (an officer / police car / player cop right there),
--     "brawl", "left" (walked away / left the game), "respawn", "timeout", "closed", "expired", "busy".
--   * a CANCEL can arrive while request() is still running (timeout, danger, the talk closed): never open the
--     UI for a requestId you have seen cancelled; a late yes for it is answered with another CANCEL "expired".
--   * the mafia flag in the request is the dealer's best knowledge for its lines; decide the stock yourself.
--
-- REQUEST payload (req):
--   { requestId: string, dealerId: string, dealerName: string, dealerPos: Vector3,
--     offer: "basic" | "special",       -- "special" only for players the crime / job side calls mafia
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
--   attacked(player, dealerId, info?)       another combat / gun system hit the dealer -> { react, line }
--   gunfire(pos: Vector3, shooter?)         a shot was fired here (the dealer hides; trades stop)
--   relation(player, dealerId) -> number    the dealer's relation with this player
--   dealers() -> { { id, name, pos: Vector3, home: Vector3, state, talking: string?, trading: string? } }
--   isDealer(id) -> boolean
-- Any gun system may also fire ServerStorage.GwangalliGunfire (BindableEvent: pos: Vector3, shooter: Player?).

local D = {}

D.FOLDER = "GwangalliWeaponShop"
D.REQUEST_EVENT = "RequestWeaponShop"
D.RESULT_EVENT = "WeaponShopResult"
D.CANCEL_EVENT = "WeaponShopCancel"
D.CLOSED_EVENT = "WeaponShopClosed"
D.ACCESS_FUNCTION = "WeaponShopAccess"
D.OPEN_UI_REMOTE = "OpenWeaponShopUI" -- owned and fired by the crime session (the dealer never touches it)
D.API = "GwangalliWeaponDealerAPI"
D.GUNFIRE_EVENT = "GwangalliGunfire" -- ServerStorage BindableEvent (pos: Vector3, shooter: Player?) any gun system may fire

D.OFFER = { basic = "basic", special = "special" }

D.REASONS = { "denied", "not_allowed", "cooldown", "not_mafia", "closed", "no_stock", "wanted", "money", "busy", "level" }
D.CANCEL_REASONS = { "attacked", "gunfire", "police", "brawl", "left", "respawn", "timeout", "closed", "expired", "busy" }

-- 마피아 (read-only sources, in this order, after the shop system's access().mafia). The dealer never
-- grants or decides it; the shop system decides the stock.
D.MAFIA = {
	-- player attributes a job system may set
	attrs = { "GwMafia", "Mafia" },
	jobAttrs = { "GwJob", "Job", "JobId", "GwJobId" },
	jobIds = { mafia = true, ["마피아"] = true, gang = true, ["조직"] = true, ["조직원"] = true },
	-- the crime system's own rank (Law crime level >= LawShared.ORG_LEVEL = 조직 수습)
	useCrimeLevel = true,
}

return D
