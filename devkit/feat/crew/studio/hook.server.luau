-- test-only hook (studio harness): ShopLife / Registry calls the eval context cannot make itself
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local HS = game:GetService("HttpService")
local GB = SSS:WaitForChild("GwangalliBuildings", 60)
local SL = require(GB:WaitForChild("ShopLife"))
local Reg = require(GB:WaitForChild("Registry"))
local f = Instance.new("BindableFunction")
f.Name = "GwCrewTestHook"
f.OnInvoke = function(op, a, b)
	local p = Players:GetPlayers()[1]
	local function V(v) return string.format("%.1f,%.1f,%.1f", v.X, v.Y, v.Z) end
	if op == "find" then
		for _, s in SL.shops() do
			if s.name == a then
				return s.key .. "|" .. V(s.center) .. "|" .. V(s.door) .. "|" .. tostring(s.floorY)
			end
		end
		return "none"
	elseif op == "sit" then
		return tostring(SL.sitAt(p, a, b))
	elseif op == "order" then
		local m = SS.GwangalliShopLife.Request:Invoke("menu", { shop = a })
		local id = m.items[1].id
		local r = Reg.handlers["life.order"](p, { shop = a, items = { { id = id, qty = 1 } } })
		return id .. " " .. HS:JSONEncode(r)
	elseif op == "pay" then
		return HS:JSONEncode(Reg.handlers["life.pay"](p, { shop = a }))
	elseif op == "stand" then
		return HS:JSONEncode(Reg.handlers["life.act"](p, { action = "stand" }))
	elseif op == "staff" then
		local s = SL.byKey(a)
		return tostring(s and s.staff and HS:JSONEncode(s.staff))
	elseif op == "session" then
		local s = SL.session(p)
		return tostring(s.shop and s.shop.key) .. " seat=" .. tostring(s.seat and s.seat.table and s.seat.table.id)
	end
	return "?"
end
f.Parent = SS
