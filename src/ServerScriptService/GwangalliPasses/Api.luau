-- GwangalliPasses/Api (server): ServerStorage.GwangalliPassesAPI (BindableFunction) for other add-ons.
--   Invoke("has", player, "garage" | "qol" | "flex" | "PremiumGarage" | ...) -> boolean
--   Invoke("owned", player) -> { PremiumGarage = bool, Convenience = bool, Flex = bool }
--   Invoke("available", key) -> boolean          (Id configured, or Studio)
--   Invoke("catalog") -> { {key, kind, label, class, glyph, topKmh, blurb} }   the pass-only premium cars
--   Invoke("summon", player, carKey, "here" | "road"?) -> ok, message
--   Invoke("plateOf", player) -> string?         the custom plate (Flex) or nil
--   Invoke("canCallAnywhere", player) -> boolean (원격 차고: pass owned, or the lock is off)
--   Invoke("atGarage", player) -> boolean        inside the 정비소 call zone
-- ServerStorage.GwangalliPassesChanged (BindableEvent): Event (player, key, owned) on every change.
-- GwangalliCarDealer: gate a pass-only tier with Invoke("has", player, "garage"); vehicles it spawns through
-- GwangalliVehiclesAPI "spawnOwned" away from the 정비소 should pass opts.gwAnywhere = true (delivery / 시승).

local ServerStorage = game:GetService("ServerStorage")

local Api = {}

function Api.start(ctx: any)
	local P, Util = ctx.P, ctx.Util
	local Cars = P.mod("Cars")
	local f = ServerStorage:FindFirstChild(P.API)
	if f and not f:IsA("BindableFunction") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = P.API
		f.Parent = ServerStorage
	end
	(f :: BindableFunction).OnInvoke = function(op: any, a: any, b: any, c: any): ...any
		if op == "has" then
			return Util.isPlayer(a) and ctx.Ownership.owns(a, b)
		elseif op == "owned" then
			return if Util.isPlayer(a) then ctx.Ownership.map(a) else {}
		elseif op == "available" then
			return P.available(a)
		elseif op == "catalog" then
			local out = {}
			for _, car in Cars.LIST do
				table.insert(out, { key = car.key, kind = car.kind, label = car.label, class = car.class, glyph = car.glyph, topKmh = car.spec.topKmh, blurb = car.blurb, pass = "garage" })
			end
			return out
		elseif op == "summon" then
			if not Util.isPlayer(a) then
				return false, "bad"
			end
			local r = ctx.Garage.summon(a, b, c)
			return r.ok == true, r.message
		elseif op == "plateOf" then
			return if Util.isPlayer(a) and ctx.Plate then ctx.Plate.textFor(a) else nil
		elseif op == "canCallAnywhere" then
			return Util.isPlayer(a) and ctx.Garage.canCallAnywhere(a)
		elseif op == "atGarage" then
			return Util.isPlayer(a) and ctx.Garage.inZone(a)
		end
		return nil
	end
end

return Api
