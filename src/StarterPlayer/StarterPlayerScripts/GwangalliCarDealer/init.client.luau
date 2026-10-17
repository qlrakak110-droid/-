-- GwangalliCarDealer (LocalScript, StarterPlayerScripts): the dealer's client — NPC life (NpcFx), the sales
-- conversation (Dialog), the full catalog (Catalog + Detail + Viewport), contracts (Contract), the 출고 ceremony
-- (Ceremony) and the test-drive HUD / report (TestHud). Our prompts carry attribute GwCarDealerNpc (the
-- garage's own prompts keep opening the garage panel). Other scripts (phone apps) open the catalog anywhere
-- with LocalPlayer.GwangalliCarDealerOpen:Fire({ cat?, entry? }) — read-only far from the store.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

if workspace:GetAttribute("GwangalliCarDealer") == false then
	return
end

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliCarDealerShared", 60)
if not sharedModule then
	warn("[GwangalliCarDealer] ReplicatedStorage.GwangalliCarDealerShared is missing: the dealer UI is off")
	return
end
local S = require(sharedModule) :: any

local function load(name: string): any
	local m = script:WaitForChild(name, 20)
	if not m then
		error("[GwangalliCarDealer] missing client module " .. name)
	end
	return require(m) :: any
end

local Ui = load("Ui")
local ctx: any = {
	S = S,
	C = S.Config,
	Ui = Ui,
}
ctx.Net = load("Net")
ctx.Viewport = load("Viewport")
ctx.NpcFx = load("NpcFx")
ctx.Dialog = load("Dialog")
ctx.Detail = load("Detail")
ctx.CatalogUI = load("Catalog")
ctx.Contract = load("Contract")
ctx.Ceremony = load("Ceremony")
ctx.TestHud = load("TestHud")

ctx.K = Ui.loadK()
Ui.init(ctx.K)
ctx.GS = S.GS(20)
ctx.VS = S.VS(10)
if not ctx.GS then
	warn("[GwangalliCarDealer] GwangalliGarageShared not found: the catalog stays empty")
end

ctx.Net.init(ctx)
ctx.Viewport.init(ctx)
ctx.Detail.init(ctx)
ctx.CatalogUI.init(ctx)
ctx.Contract.init(ctx)
ctx.Ceremony.init(ctx)
ctx.Dialog.init(ctx)
ctx.TestHud.init(ctx)
ctx.NpcFx.init(ctx)

local N = S.NAMES

-- Dealer info from a prompt: its NPC model / hook anchor carries the attributes.
local function dealerOf(prompt: ProximityPrompt): any?
	local id = prompt:GetAttribute(N.AttrNpc)
	if type(id) ~= "string" then
		return nil
	end
	local node: Instance? = prompt.Parent
	while node and node ~= workspace do
		if node:GetAttribute(N.AttrNpc) == id and node:GetAttribute(N.AttrName) ~= nil then
			return {
				id = id,
				name = node:GetAttribute(N.AttrName),
				role = node:GetAttribute(N.AttrRole),
				voice = node:GetAttribute(N.AttrVoice) or "consult",
				icon = node:GetAttribute(N.AttrIcon) or "🧑‍💼",
				ours = node:GetAttribute(N.AttrOurs) == true,
			}
		end
		node = node.Parent
	end
	return { id = id, name = "딜러", role = "영업 담당", voice = "consult", icon = "🧑‍💼" }
end

ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
	if who ~= player then
		return
	end
	local info = dealerOf(prompt)
	if not info then
		return
	end
	if ctx.Contract.isOpen() or ctx.Ceremony.isOpen() then
		return
	end
	-- other dealer configs may open a specific tab (e.g. a 중고차 desk)
	for _, cfg in S.Config.NPCS do
		if cfg.id == info.id and cfg.tab then
			info.tab = cfg.tab
		end
	end
	ctx.Dialog.open(info)
end)

-- public opener (phone apps, other scripts): read-only far from the store
local open = player:FindFirstChild(N.OpenEvent)
if not (open and open:IsA("BindableEvent")) then
	open = Instance.new("BindableEvent")
	open.Name = N.OpenEvent
	open.Parent = player
end
;(open :: BindableEvent).Event:Connect(function(opts: any)
	local o = if type(opts) == "table" then opts else {}
	ctx.CatalogUI.open({
		cat = if type(o.cat) == "string" then o.cat else "all",
		entry = if type(o.entry) == "string" then o.entry else nil,
	})
end)
