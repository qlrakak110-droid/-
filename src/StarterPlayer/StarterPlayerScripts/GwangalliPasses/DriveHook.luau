-- GwangalliPasses/DriveHook (client): the place's "🚗 내 차 부르기" sheet (PlayerScripts.GwangalliDrive Folder:
-- Api + UI module tables) learns about the passes, without editing it:
--   * Api.callCar is wrapped: without 원격 차고 and outside the 정비소 zone (server attribute GwPassAtGarage), an
--     owned car is not requested; a lock dialog offers the pass / the route to the 정비소 instead. (The server
--     enforces the same rule on its own: GwangalliPasses/Garage wraps Spawn.callOwned.)
--   * UI.renderRows is wrapped: after the sheet draws its rows we add a banner on top (🔒 원격 차고 잠김 /
--     📍 정비소 구역 / 👑 원격 차고) and, for pass owners, a "✦ 프리미엄" section with the four premium cars
--     (부르기 = 바로 내 옆으로). The sheet's own rows are untouched except a 🔒 on their 부르기 buttons.
--   * the 정비소 차량 호출 kiosk (server Event "station") opens the sheet.
--   DriveHook.openSheet() / DriveHook.waypoint() / DriveHook.markCar(model)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DriveHook = {}

local ctx: any
local P: any, K: any, Lines: any, Cars: any
local Api: any = nil
local UI: any = nil
local GS: any = nil
local VS: any = nil
local subOriginal: string? = nil

local GOLD = Color3.fromRGB(255, 194, 71)

local function lp(): Player
	return Players.LocalPlayer
end

local function gateActive(): boolean
	local r = ctx.Net.ready()
	return P.Config.GARAGE.REMOTE_LOCK == true and P.available("PremiumGarage") and r.gate == true
end

local function hasPass(): boolean
	return P.has(lp(), "PremiumGarage")
end

local function atGarage(): boolean
	return lp():GetAttribute(P.Attr.AtGarage) == true
end

local function locked(): boolean
	return gateActive() and not hasPass() and not atGarage()
end

function DriveHook.openSheet()
	if Api and type(Api.open) == "function" then
		pcall(Api.open, "callcar")
	end
end

function DriveHook.waypoint()
	if Api and type(Api.garageWaypoint) == "function" then
		pcall(Api.garageWaypoint)
	end
end

-- the Drive module's own "this is my car" marker (Api.callCar does the same after a call)
function DriveHook.markCar(model: Instance)
	pcall(function()
		local folder = DriveHook.folder
		local d = folder and folder:FindFirstChild("Drive")
		if d and d:IsA("ModuleScript") then
			local Drive = require(d) :: any
			if type(Drive.markCar) == "function" then
				Drive.markCar(model)
			end
		end
	end)
end

local function lockDialog()
	local host = ctx.Hub.host()
	local function buy()
		ctx.Store.buy("PremiumGarage")
	end
	local pg = lp():FindFirstChildOfClass("PlayerGui")
	local sheet = pg and pg:FindFirstChild("GwangalliCallCar")
	local where = (sheet and sheet:FindFirstChild("Sheet")) or host
	if where and type(K.Modal) == "function" then
		-- K.Modal directly: tapping outside only closes it (K.confirm would treat that as the 길찾기 button)
		K.Modal(where, {
			title = Lines.t("gate_banner"),
			body = Lines.t("gate_banner_body") .. "\n" .. P.Config.PASSES.PremiumGarage.Perks[2],
			icon = "🔒",
			zIndex = 40,
			buttons = {
				{ text = "🧭 " .. Lines.t("gate_route"), style = "secondary", onClick = function()
					task.spawn(DriveHook.waypoint)
				end },
				{ text = "👑 " .. Lines.t("gate_buy"), style = "gold", onClick = buy },
			},
		})
	elseif where then
		K.confirm(where, {
			title = Lines.t("gate_banner"),
			body = Lines.t("gate_banner_body"),
			icon = "🔒",
			cancelText = "🧭 " .. Lines.t("gate_route"),
			confirmText = "👑 " .. Lines.t("gate_buy"),
			style = "gold",
			onConfirm = buy,
			onCancel = function()
				task.spawn(DriveHook.waypoint)
			end,
		})
	else
		K.toast({ kind = "warn", icon = "🔒", title = Lines.t("gate_banner"), body = Lines.t("gate_banner_body") })
	end
end

---------------------------------------------------------------------------------------------------
-- extra rows in the sheet
---------------------------------------------------------------------------------------------------
local function sheetList(): ScrollingFrame?
	local pg = lp():FindFirstChildOfClass("PlayerGui")
	local g = pg and pg:FindFirstChild("GwangalliCallCar")
	local panel = g and g:FindFirstChild("Sheet")
	local list = panel and panel:FindFirstChild("List")
	return if list and list:IsA("ScrollingFrame") then list else nil
end

local function banner(list: ScrollingFrame)
	local text, body, color
	if hasPass() and gateActive() then
		text, body, color = Lines.t("gate_owner"), nil, GOLD
	elseif not gateActive() then
		return
	elseif atGarage() then
		text, body, color = Lines.t("gate_open"), nil, Color3.fromRGB(90, 230, 140)
	else
		text, body, color = Lines.t("gate_banner"), Lines.t("gate_banner_body"), Color3.fromRGB(255, 150, 90)
	end
	local card = K.Card(list, { Name = "GwPassBanner", Size = UDim2.new(1, 0, 0, if body then 104 else 44), LayoutOrder = -100, ZIndex = 4 })
	K.stroke(card, color, 1, 0.5)
	K.text(card, { Text = text, Font = K.Font.bold, TextSize = K.Type.bodySm, TextColor3 = color, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 0, 44), TextWrapped = true, ZIndex = 5 })
	if body then
		K.text(card, { Text = body, TextSize = K.Type.micro, TextColor3 = K.Color.sub, TextWrapped = true, Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 26), ZIndex = 5 })
		K.Button(card, { name = "Route", text = Lines.t("gate_route"), icon = "🧭", style = "secondary", position = UDim2.new(0, 10, 1, -44), size = UDim2.new(0.5, -15, 0, 36), zIndex = 6, onClick = function()
			task.spawn(DriveHook.waypoint)
		end })
		K.Button(card, { name = "Buy", text = Lines.t("gate_buy"), icon = "👑", style = "gold", position = UDim2.new(0.5, 5, 1, -44), size = UDim2.new(0.5, -15, 0, 36), zIndex = 6, onClick = function()
			ctx.Store.buy("PremiumGarage")
		end })
	end
end

local function premiumRows(list: ScrollingFrame, st: any)
	if not hasPass() or not P.available("PremiumGarage") then
		return
	end
	local head = K.text(list, { Name = "GwPremiumSection", Text = "✦ 프리미엄 차고 (패스 전용)", Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 500, ZIndex = 4 })
	local _ = head
	local outKey = nil
	if st and st.hasCar then
		-- the called car's kind tells whether a premium car is out
		local car = Cars.BY_KIND[st.kind or ""]
		outKey = car and car.key
	end
	for i, car in Cars.LIST do
		local row = K.Card(list, { Name = "GwPremium_" .. car.key, Size = UDim2.new(1, 0, 0, 68), LayoutOrder = 500 + i, ZIndex = 4 })
		K.stroke(row, GOLD, 1, 0.75)
		local tile = K.frame(row, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
		K.corner(tile, 14)
		K.gradient(tile, { GOLD, Color3.fromRGB(255, 79, 163) }, 120)
		K.text(tile, { Text = car.glyph, TextSize = 24, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
		K.text(row, { Text = "✦ " .. car.label, Font = K.Font.bold, TextSize = K.Type.body, Position = UDim2.fromOffset(70, 12), Size = UDim2.new(1, -184, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		K.text(row, { Text = string.format("%s · 최고 %dkm/h", car.class, car.spec.topKmh), TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(70, 34), Size = UDim2.new(1, -184, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		local isOut = outKey == car.key
		K.Button(row, { name = "Act", text = if isOut then "타는 중" else "부르기", style = if isOut then "tonal" else "gold", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -10, 0.5, 0), size = UDim2.fromOffset(96, 52), zIndex = 6, onClick = function()
			if isOut then
				return
			end
			task.spawn(function()
				local res = ctx.Net.request("summon", { car = car.key, mode = "here" })
				K.toast({ kind = if res.ok then "success" else "warn", icon = car.glyph, title = res.title or res.message or Lines.t("summon_fail"), body = if res.title then res.message else nil })
				if res.ok then
					if UI and type(UI.closeSheet) == "function" then
						pcall(UI.closeSheet)
					end
					if typeof(res.car) == "Instance" then
						DriveHook.markCar(res.car)
					end
				end
			end)
		end })
	end
end

local function decorate(st: any)
	local list = sheetList()
	if not list or st == nil then
		return
	end
	pcall(banner, list)
	pcall(premiumRows, list, st)
	-- 🔒 on the sheet's own 부르기 buttons while locked; the sheet's subtitle says why
	local isLocked = locked()
	for _, row in list:GetChildren() do
		if string.sub(row.Name, 1, 4) == "Car_" then
			local act = row:FindFirstChild("Act")
			if act and act:IsA("TextButton") and isLocked and act.Text == "부르기" then
				act.Text = "🔒 부르기"
			end
		end
	end
	local panel = list.Parent
	local sub = panel and panel:FindFirstChild("Sub")
	if sub and sub:IsA("TextLabel") then
		if subOriginal == nil then
			subOriginal = sub.Text
		end
		sub.Text = if isLocked then "🔒 정비소에서만 부를 수 있어요 · 원격 차고 패스로 어디서든" elseif hasPass() and gateActive() then "👑 원격 차고 · 어디서든 내 차를 바로 불러요" else (subOriginal or sub.Text)
	end
end

---------------------------------------------------------------------------------------------------
-- hooks
---------------------------------------------------------------------------------------------------
local function wrapOnce(tbl: any, name: string, make: (any) -> any)
	if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then
		return
	end
	local key = "__gwPasses_" .. name
	if rawget(tbl, key) then
		return
	end
	local orig = tbl[name]
	tbl[name] = make(orig)
	rawset(tbl, key, orig)
end

local function hook(folder: Instance)
	DriveHook.folder = folder
	local apiM = folder:WaitForChild("Api", 30)
	local uiM = folder:WaitForChild("UI", 30)
	if apiM and apiM:IsA("ModuleScript") then
		local ok, res = pcall(require, apiM)
		if ok and type(res) == "table" then
			Api = res
		end
	end
	if uiM and uiM:IsA("ModuleScript") then
		local ok, res = pcall(require, uiM)
		if ok and type(res) == "table" then
			UI = res
		end
	end
	wrapOnce(Api, "callCar", function(orig)
		return function(arg: any, ...: any)
			-- a premium car id ("gwp_<key>") never goes to the Garage
			local key = Cars.keyOfId(arg)
			if key then
				local res = ctx.Net.request("summon", { car = key, mode = "here" })
				K.toast({ kind = if res.ok then "success" else "warn", icon = "🏎️", title = res.title or res.message or Lines.t("summon_fail"), body = if res.title then res.message else nil })
				return res.ok == true, tostring(res.message or "")
			end
			-- free-spawn kinds (dev switch / admin) are not owned cars: not locked
			local isKind = type(arg) == "string" and VS ~= nil and VS.Drivable[arg] == true
			if not isKind and locked() then
				lockDialog()
				return false, Lines.t("gate_refuse")
			end
			return orig(arg, ...)
		end
	end)
	wrapOnce(UI, "renderRows", function(orig)
		return function(st: any, ...: any)
			local r = table.pack(orig(st, ...))
			pcall(decorate, st)
			return table.unpack(r, 1, r.n)
		end
	end)
end

function DriveHook.start(c: any)
	ctx = c
	P, K, Lines = c.P, c.K, c.P.Lines
	Cars = P.mod("Cars")
	local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			GS = res
		end
	end
	local _ = GS
	local vm = ReplicatedStorage:FindFirstChild("GwangalliVehiclesShared")
	if vm and vm:IsA("ModuleScript") then
		local ok, res = pcall(require, vm)
		if ok then
			VS = res
		end
	end
	task.spawn(function()
		local ps = lp():WaitForChild("PlayerScripts", 30)
		if not ps then
			return
		end
		local deadline = os.clock() + 60
		while os.clock() < deadline do
			for _, ch in ps:GetChildren() do
				if ch.Name == "GwangalliDrive" and ch:IsA("Folder") then
					hook(ch)
					return
				end
			end
			task.wait(0.5)
		end
	end)
	-- the 정비소 kiosk
	c.Net.on("station", function()
		DriveHook.openSheet()
	end)
	-- the server refused a call on the lock (e.g. through another UI): show the same dialog
	c.Net.on("gate", function()
		lockDialog()
	end)
	-- zone / ownership changes while the sheet is open
	local function rerender()
		if UI and type(UI.sheetOpen) == "function" and UI.sheetOpen() and Api and type(Api.status) == "function" then
			task.spawn(function()
				local st = Api.status()
				if type(UI.setSheetStatus) == "function" then
					UI.setSheetStatus(st)
				end
			end)
		end
	end
	lp():GetAttributeChangedSignal(P.Attr.AtGarage):Connect(rerender)
	c.Store.changed(function(key: string)
		if key == "PremiumGarage" then
			rerender()
		end
	end)
end

return DriveHook
