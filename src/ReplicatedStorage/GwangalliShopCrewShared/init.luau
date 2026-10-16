-- GwangalliShopCrewShared (ModuleScript, ReplicatedStorage): the shared half of GwangalliShopCrew, the shop
-- staff add-on ("크루"): staff that greet, take orders, cook in view, carry the tray to your table, clear it,
-- answer questions, remember regulars, plus NPC diners and an optional 일손 돕기 mini shift.
--   Server: ServerScriptService.GwangalliShopCrew (Script)   Client: StarterPlayerScripts.GwangalliShopCrew
--   local CS = require(ReplicatedStorage.GwangalliShopCrewShared)
--   CS.Config   tunables (Script / workspace attributes override a few, see Config.luau)
--   CS.Util     hashing, KST day key, 원 formatting, Korean particles (이/가 ...), yaw, compass words
--   CS.Lines    the Korean line bank (std / 부산 사투리), Lines.get(key, ctx)
--   CS.Personas who works where: roles per shop type, deterministic names / titles / looks
--   CS.NavGrid  the pure grid planner the waiters walk with (A* + string pulling)
--   CS.Menus    per-kind counter menus for staff counters that ShopLife does not run
-- Pure modules: no instances at require time, nothing yields. Safe on server and client.

local Shared = {}

Shared.VERSION = 1

-- instance names (the contract other systems may read)
Shared.NET = "GwangalliShopCrewNet" -- ReplicatedStorage folder: Request (RemoteFunction), Event (RemoteEvent)
Shared.API = "GwangalliShopCrew" -- ServerStorage folder: API (BindableFunction), Event (BindableEvent), attribute Ready
Shared.WORLD = "GwShopCrew" -- Workspace folder: <shopKey>/Spots, door-opener proxies, helper props
Shared.RIG_FOLDER = "GwangalliShopStaff" -- Workspace folder of every staff rig (shared with ShopStaff: see Config)
Shared.TAG = "GwShopCrew" -- our rigs (crew + diners)
Shared.NPC_TAG = "GwShopNpc" -- every NPC model this add-on owns (crew, diners)
Shared.STAFF_TAG = "GwShopStaff" -- GwangalliNPCClient animates models with this tag
Shared.SPOT_TAG = "GwCrewSpot" -- invisible spot parts (home / cook / cashier / service / approach)
Shared.PROMPT = "CrewTalk" -- our talk prompt (on crew rigs and on augmented staff)

-- model attributes written on our rigs (besides the NPC.luau contract: NpcId, NpcKind, NpcAct ...)
Shared.ATTR = {
	Shop = "CrewShop", -- shop key
	Role = "CrewRole", -- cook | waiter | cashier | barista | floor | stocker | diner
	Name = "CrewName",
	Title = "CrewTitle",
	Carry = "CrewCarry", -- "" | "dish|<menuKey>|<itemId>|<qty>[;...]" | "water" | "menu" | "empty" | "box" | "broom" | "cup"
	Icon = "CrewIcon",
	Color = "CrewColor",
	Mood = "CrewMood", -- 0..100 (shop mood, shown as the name tag's face)
	Helper = "CrewHelper", -- ProximityPrompt attribute: only this UserId sees the prompt (일손 돕기)
}

Shared.Config = require(script:WaitForChild("Config"))
Shared.Util = require(script:WaitForChild("Util"))
Shared.Lines = require(script:WaitForChild("Lines"))
Shared.Personas = require(script:WaitForChild("Personas"))
Shared.NavGrid = require(script:WaitForChild("NavGrid"))
Shared.Menus = require(script:WaitForChild("Menus"))

return Shared
