-- GwangalliGarage (LocalScript, StarterPlayerScripts): the 광안 오토 정비소 & 중고차 client (docs/GARAGE.md).
--
-- Modules in the sibling Folder "GwangalliGarage" (same name as this script: found by class):
--   Net    GarageRequest / GarageEvent (server: GwangalliGameplay/Garage.luau)
--   Sheet  구매 / 내 차 / 렌트 sheet + showroom camera + turntable spin + colour preview + receipt
--   Fx     repair / wash choreography, dirt / shine / smoke on owned cars, LED, staff idle animation
--   Hud    zone action chip (정비 받기 / 세차하기), 시승 countdown + route marker, hit feedback
-- World prompts (built by build/venues/garage*.luau, handled here on the client):
--   GaragePrompt (showroom price stand, attr GarageKind)  -> Sheet "구매" on that car
--   GarageDesk Kind = office                              -> Sheet "내 차"
--   GarageDesk Kind = service                             -> 정비: the car in the bay, else Sheet "내 차"
--   GarageDesk Kind = wash                                -> 세차 when my car is in the wash bay
-- Public: LocalPlayer.GwangalliGarageOpen (BindableEvent) :Fire({ tab, kind }) opens the sheet (phone apps).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliGarage" and child:IsA("Folder") then
					return child
				end
			end
		end
		task.wait(0.1)
	end
	return nil
end

local folder = findFolder()
if not folder then
	warn("[GwangalliGarage] module folder missing next to the LocalScript")
	return
end

local function load(name: string): any
	local m = (folder :: Instance):WaitForChild(name, 10)
	if not (m and m:IsA("ModuleScript")) then
		error("[GwangalliGarage] module missing: " .. name)
	end
	return require(m)
end

local ok, err = pcall(function()
	local GS = require(ReplicatedStorage:WaitForChild("GwangalliGarageShared", 30))
	local K = require(ReplicatedStorage:WaitForChild("GwangalliUI", 30))
	local VS = nil
	local vsm = ReplicatedStorage:WaitForChild("GwangalliVehiclesShared", 10)
	if vsm then
		local okVS, res = pcall(require, vsm)
		if okVS then
			VS = res
		end
	end
	local ctx: any = {
		GS = GS,
		K = K,
		VS = VS,
		Layout = K.Layout or require(ReplicatedStorage:WaitForChild("GwangalliLayout", 30)),
		Net = load("Net"),
		Sheet = load("Sheet"),
		Fx = load("Fx"),
		Hud = load("Hud"),
	}
	ctx.Net.init(GS)
	ctx.Sheet.build(ctx)
	ctx.Hud.build(ctx)
	ctx.Fx.start(ctx)

	-- the car seat cannot be used while the sheet is up; a finished test drive brings the sheet back
	ctx.Net.on("testdrive", function(p: any)
		if p.stage == "end" and p.why == "time" and type(p.carKind) == "string" then
			task.wait(1.2)
			ctx.Sheet.open({ tab = "buy", kind = p.carKind })
		end
	end)

	local function desk(prompt: ProximityPrompt): (Instance?, string?)
		local p = prompt.Parent
		if p and CollectionService:HasTag(p, GS.Tags.Prompt) then
			return p, "car"
		end
		if p and CollectionService:HasTag(p, GS.Tags.Desk) then
			return p, p:GetAttribute("Kind")
		end
		return nil, nil
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local part, kind = desk(prompt)
		if not part then
			return
		end
		if kind == "car" then
			ctx.Sheet.open({ tab = "buy", kind = part:GetAttribute("GarageKind") })
		elseif kind == "office" then
			ctx.Sheet.open({ tab = "mine" })
		elseif kind == "service" then
			local st = ctx.Net.status()
			if st.ok and st.zone == "service" then
				ctx.Hud.onZone({ zone = "service", quote = { repair = 0 } })
				ctx.Hud.zoneAction()
			else
				ctx.Sheet.open({ tab = "mine" })
				K.toast({ kind = "info", icon = "🔧", title = "정비 받을 차를 고르세요", body = "차를 '정비 대기 구역'에 세우면 리프트에서 바로 정비해요" })
			end
		elseif kind == "wash" then
			local st = ctx.Net.status()
			if st.ok and st.zone == "wash" then
				ctx.Hud.onZone({ zone = "wash" })
				ctx.Hud.zoneAction()
			else
				K.toast({ kind = "info", icon = "🫧", title = "내 차를 세차장 안에 세워 주세요", body = "초록 선 안 정지선까지 들어온 뒤 '세차하기'" })
			end
		end
	end)

	-- other scripts (phone apps) open the sheet through a BindableEvent on the LocalPlayer
	local open = player:FindFirstChild("GwangalliGarageOpen")
	if not (open and open:IsA("BindableEvent")) then
		open = Instance.new("BindableEvent")
		open.Name = "GwangalliGarageOpen"
		open.Parent = player
	end
	(open :: BindableEvent).Event:Connect(function(opts: any)
		ctx.Sheet.open(if type(opts) == "table" then opts else nil)
	end)
end)
if not ok then
	warn("[GwangalliGarage] failed to start: " .. tostring(err))
end
