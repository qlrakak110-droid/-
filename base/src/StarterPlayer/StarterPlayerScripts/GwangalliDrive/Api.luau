-- GwangalliDrive/Api: public client API of the driving system (for the phone and other features).
--
--   local folder -- PlayerScripts' Folder "GwangalliDrive" (same name as the LocalScript: find it
--                -- by class, e.g. for _, c in PlayerScripts:GetChildren() do if c:IsA("Folder") ...)
--   local Drive = require(folder.Api)
--   Drive.open("callcar")        opens the 차 부르기 sheet (aliases "mycar", "car"): the player's OWN /
--                                rented cars (GwangalliGarageShared / server Garage.luau)
--   Drive.callCar(idOrKind?)     -> ok, message (yields). A d.cars record id calls that owned car (its
--                                colour + plate); a kind (sedan|luxury|compact|suv|van|truck) is the free
--                                spawn, refused by the server unless admin / dev switch. nil = the first
--                                callable owned car.
--   Drive.dismiss()              -> ok, message   (sends the called car away)
--   Drive.tow(id)                -> ok, message   (a dead car to the 정비소, fee GS.TOW.fee)
--   Drive.garageWaypoint()       map waypoint to 광안정비소 (buy / rent there)
--   Drive.status()               -> { hasCar, kind, label, meters, cooldown, free, cars = {views}, outId, max }
--   Drive.cars()                 -> { views } (owned + rented; GS.carView)
--   Drive.isDriving() / Drive.role() / Drive.car()
--   Drive.changed                RBXScriptSignal (role: "driver" | "passenger" | nil, car)
--   Drive.catalog()              VS.Catalog with specs (label, topKmh, drive, blurb, glyph)
--   Drive.closeSheet() / Drive.sheetOpen()   the 차 부르기 sheet
-- Features.open("callcar") (LocalPlayer.GwangalliFeaturesOpen:Fire("callcar", args)) reaches this
-- Api through GwangalliFeatures/CallCar.luau (listed in the features Registry). Chat: "/차" or
-- "/car" opens the sheet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Api = {}

local ctx: any = nil
local changedEvent = Instance.new("BindableEvent")
Api.changed = changedEvent.Event
local garageFn: RemoteFunction? = nil

function Api.init(c: any)
	ctx = c
	local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			ctx.GS = res
		end
	end
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("GwangalliRemotes", 60)
		local name = if ctx.GS then ctx.GS.Remotes.Request else "GarageRequest"
		local f = folder and folder:WaitForChild(name, 60)
		if f and f:IsA("RemoteFunction") then
			garageFn = f
		end
	end)
end

-- Garage server request (op, payload) -> result table (never errors).
function Api.garage(op: string, payload: { [string]: any }?): { [string]: any }
	local f = garageFn
	if not f then
		local folder = ReplicatedStorage:FindFirstChild("GwangalliRemotes")
		local r = folder and folder:FindFirstChild("GarageRequest")
		if r and r:IsA("RemoteFunction") then
			garageFn = r
			f = r
		end
	end
	if not f then
		return { ok = false, message = "정비소 서버에 연결하는 중이에요" }
	end
	local ok, res = pcall(function()
		return (f :: RemoteFunction):InvokeServer(op, payload)
	end)
	if ok and type(res) == "table" then
		return res
	end
	return { ok = false, message = "서버에 연결할 수 없어요" }
end

function Api.fireChanged(role: string?, car: Model?)
	if ctx.UI.setCar then
		pcall(ctx.UI.setCar, car)
	end
	changedEvent:Fire(role, car)
end

function Api.catalog(): { any }
	local out = {}
	for _, item in ctx.VS.Catalog do
		local spec = ctx.VS.spec(item.kind)
		table.insert(out, { kind = item.kind, glyph = item.glyph, blurb = item.blurb, label = spec.label, model = spec.model, topKmh = spec.topKmh, drive = spec.drive })
	end
	return out
end

function Api.isDriving(): boolean
	return ctx.Drive.role() == "driver"
end
function Api.role(): string?
	return ctx.Drive.role()
end
function Api.car(): Model?
	return ctx.Drive.car()
end

function Api.cars(): { any }
	local r = Api.garage("list")
	return if r.ok and type(r.cars) == "table" then r.cars else {}
end

-- Vehicles status (called car) merged with the garage's (owned cars).
function Api.status(): { [string]: any }
	local out: { [string]: any } = { hasCar = false }
	local fn = ctx.callFn
	if fn then
		local ok, res = pcall(function()
			return fn:InvokeServer("status")
		end)
		if ok and type(res) == "table" then
			out = res
		end
	end
	local g = Api.garage("status")
	if g.ok then
		out.cars = g.cars
		out.max = g.max
		out.outId = g.outId
		out.free = out.free or g.free
		out.loaded = g.loaded
	else
		out.cars = out.cars or {}
	end
	return out
end

local busy = false
function Api.callCar(arg: string?): (boolean, string)
	if busy then
		return false, "차를 부르는 중이에요"
	end
	local VS, K = ctx.VS, ctx.K
	local id = arg
	if id == nil then
		for _, c in Api.cars() do
			if c.callable then
				id = c.id
				break
			end
		end
		if id == nil then
			K.toast({ kind = "info", icon = "🚗", title = "부를 수 있는 내 차가 없어요", body = "광안 오토 정비소에서 차를 사거나 렌트해 보세요" })
			return false, "no car"
		end
	end
	busy = true
	ctx.UI.setCallBusy(id, true)
	local okAll, label, meters, car, msg = false, nil, 0, nil, nil
	if VS.Drivable[id :: string] then
		local fn = ctx.callFn
		if fn then
			local ok, res = pcall(function()
				return fn:InvokeServer("call", id)
			end)
			if ok and type(res) == "table" then
				okAll, label, meters, car, msg = res.ok == true, res.label, res.meters, res.car, res.msg
			else
				msg = "서버에 연결할 수 없어요"
			end
		else
			msg = "서버에 연결할 수 없어요"
		end
	else
		local res = Api.garage("call", { id = id })
		okAll, label, meters, car, msg = res.ok == true, res.label, res.meters, res.car, res.message
		if okAll and res.plate then
			label = tostring(label or "내 차") .. " · " .. tostring(res.plate)
		end
	end
	ctx.UI.setCallBusy(nil, false)
	busy = false
	if okAll then
		local l = label or "내 차"
		K.toast({ kind = "success", icon = "🚗", title = l .. " 도착!", body = string.format("%dm 떨어진 도로에 세워 뒀어요", meters or 0) })
		ctx.UI.closeSheet()
		if typeof(car) == "Instance" then
			ctx.Drive.markCar(car)
		end
		return true, l
	end
	local m = tostring(msg or "차를 부르지 못했어요")
	K.toast({ kind = "warn", icon = "🚗", title = "차를 부르지 못했어요", body = m })
	return false, m
end

function Api.dismiss(): (boolean, string)
	local fn = ctx.callFn
	if not fn then
		return false, "서버에 연결할 수 없어요"
	end
	local ok, res = pcall(function()
		return fn:InvokeServer("dismiss")
	end)
	local good = ok and type(res) == "table" and res.ok == true
	local msg = if ok and type(res) == "table" then tostring(res.msg) else "서버에 연결할 수 없어요"
	ctx.K.toast({ kind = if good then "info" else "warn", icon = "🚗", title = msg })
	if ctx.UI.sheetOpen() then
		ctx.UI.setSheetStatus(Api.status())
	end
	return good, msg
end

function Api.tow(id: string): (boolean, string)
	local res = Api.garage("tow", { id = id })
	if not res.ok then
		ctx.K.toast({ kind = "warn", icon = "🚛", title = "견인할 수 없어요", body = tostring(res.message or "") })
	end
	if ctx.UI.sheetOpen() then
		ctx.UI.setSheetStatus(Api.status())
	end
	return res.ok == true, tostring(res.message or "")
end

function Api.garageWaypoint(): boolean
	local res = Api.garage("waypoint")
	return res.ok == true
end

function Api.open(id: string?): boolean
	local key = string.lower(tostring(id or "callcar"))
	if key == "callcar" or key == "mycar" or key == "car" then
		if ctx.Drive.role() == "driver" then
			ctx.K.toast({ kind = "info", icon = "🚗", title = "지금 운전 중이에요" })
			return false
		end
		ctx.UI.setSheetStatus(nil)
		ctx.UI.openSheet()
		task.spawn(function()
			ctx.UI.setSheetStatus(Api.status())
		end)
		return true
	end
	return false
end

function Api.closeSheet()
	ctx.UI.closeSheet()
end
function Api.sheetOpen(): boolean
	return ctx.UI.sheetOpen()
end

-- Chat command (the features registry entry is GwangalliFeatures/CallCar.luau) -------------------------
function Api.registerEntryPoints()
	pcall(function()
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "GwangalliCallCar"
		cmd.PrimaryAlias = "/차"
		cmd.SecondaryAlias = "/car"
		cmd.Triggered:Connect(function()
			Api.open("callcar")
		end)
		cmd.Parent = TextChatService
	end)
end

return Api
