-- GwangalliGarage/Net: the client side of the 정비소 remotes (ReplicatedStorage.GwangalliRemotes:
-- GarageRequest RemoteFunction + GarageEvent RemoteEvent, created by GwangalliGameplay/Garage.luau).
--   Net.request(op, payload?) -> result { ok, code, message, ... }   (never errors; yields)
--   Net.on(kind, fn)            GarageEvent handlers by payload.kind ("cars", "zone", "repair", "wash",
--                               "testdrive", "hit", "dead")
--   Net.cars                    last known d.cars views (GS.carView) - refreshed by "cars" events / status
--   Net.status()                -> the "status" result (cars, bank, cash, atGarage, zone, ...)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}
Net.cars = {}
Net.max = 3

local GS: any = nil
local fn: RemoteFunction? = nil
local ev: RemoteEvent? = nil
local handlers: { [string]: { (any) -> () } } = {}
local changed = Instance.new("BindableEvent")
Net.carsChanged = changed.Event

function Net.init(gs: any)
	GS = gs
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("GwangalliRemotes", 120)
		if not folder then
			warn("[GwangalliGarage] GwangalliRemotes missing")
			return
		end
		local f = folder:WaitForChild(GS.Remotes.Request, 120)
		local e = folder:WaitForChild(GS.Remotes.Event, 120)
		if f and f:IsA("RemoteFunction") then
			fn = f
		end
		if e and e:IsA("RemoteEvent") then
			ev = e
			e.OnClientEvent:Connect(function(payload: any)
				if type(payload) ~= "table" or type(payload.kind) ~= "string" then
					return
				end
				if payload.kind == "cars" and type(payload.cars) == "table" then
					Net.cars = payload.cars
					Net.max = payload.max or Net.max
					changed:Fire(Net.cars)
				end
				for _, h in handlers[payload.kind] or {} do
					task.spawn(h, payload)
				end
			end)
		end
	end)
end

function Net.ready(): boolean
	return fn ~= nil
end

function Net.on(kind: string, f: (any) -> ())
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], f)
end

function Net.request(op: string, payload: { [string]: any }?): { [string]: any }
	local f = fn
	if not f then
		return { ok = false, code = "offline", message = "정비소 서버에 연결하는 중이에요" }
	end
	local ok, res = pcall(function()
		return (f :: RemoteFunction):InvokeServer(op, payload)
	end)
	if ok and type(res) == "table" then
		if type(res.cars) == "table" then
			Net.cars = res.cars
			Net.max = res.max or Net.max
			changed:Fire(Net.cars)
		end
		return res
	end
	return { ok = false, code = "error", message = "서버에 연결할 수 없어요" }
end

function Net.status(): { [string]: any }
	return Net.request("status")
end

function Net.car(id: string?): any?
	for _, c in Net.cars do
		if c.id == id then
			return c
		end
	end
	return nil
end

return Net
