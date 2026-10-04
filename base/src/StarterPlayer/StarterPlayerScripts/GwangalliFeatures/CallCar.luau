-- GwangalliFeatures/CallCar: Features.open("callcar") -> the drive system's 차 부르기 sheet
-- (owner: driving + garage; docs/features_contract.md §1 module shape, docs/DRIVING.md, docs/GARAGE.md).
--   flows: "callcar" (aliases handled by the drive Api: "mycar" / "car") opens the sheet with the
--   player's OWN / rented cars (colour, plate, condition; 견인 for a dead car; "정비소에서 구매" when the
--   player owns nothing) and the called car's status. args (phone shortcuts):
--     args.id = d.cars record id     call that owned car right away
--     args.tow = id                  tow a dead car to the 정비소
--     args.garage = true             map waypoint to 광안정비소
--     args.kind = sedan|luxury|...   free spawn (the server refuses it unless admin / dev switch)
--     args.dismiss = true            send the called car back
-- The code lives in PlayerScripts.GwangalliDrive (Folder next to the GwangalliDrive LocalScript;
-- Api module). It is found by class + name, waited for up to 20 s in the background; before it is
-- there (or when the drive system is disabled) open() shows a toast instead of failing.

local Players = game:GetService("Players")

local M = {}
M.flows = { "callcar" }

local F: any
local api: any = nil

local function findApi(): any
	if api then
		return api
	end
	local ps = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	if not ps then
		return nil
	end
	for _, c in ps:GetChildren() do
		if c:IsA("Folder") and c.Name == "GwangalliDrive" then
			local m = c:FindFirstChild("Api")
			if m and m:IsA("ModuleScript") then
				local ok, res = pcall(require, m)
				if ok and type(res) == "table" and type(res.open) == "function" then
					api = res
					return api
				end
			end
		end
	end
	return nil
end

function M.init(ctx: any)
	F = ctx
	task.spawn(function()
		for _ = 1, 80 do
			if findApi() then
				return
			end
			task.wait(0.25)
		end
	end)
end

function M.open(_flowId: string, args: any?)
	local a = findApi()
	if not a then
		F.toast({ kind = "info", icon = "🚗", title = "차 부르기", body = "운전 시스템을 준비하는 중이에요. 잠시 후 다시 눌러 주세요" })
		return
	end
	if type(args) == "table" then
		if args.dismiss == true and type(a.dismiss) == "function" then
			task.spawn(a.dismiss)
			return
		end
		if type(args.id) == "string" and type(a.callCar) == "function" then
			task.spawn(a.callCar, args.id)
			return
		end
		if type(args.tow) == "string" and type(a.tow) == "function" then
			task.spawn(a.tow, args.tow)
			return
		end
		if args.garage == true and type(a.garageWaypoint) == "function" then
			task.spawn(a.garageWaypoint)
			return
		end
		if type(args.kind) == "string" and type(a.callCar) == "function" then
			task.spawn(a.callCar, args.kind)
			return
		end
	end
	a.open("callcar")
end

function M.close()
	local a = api
	if a and type(a.closeSheet) == "function" then
		pcall(a.closeSheet)
	end
end

function M.isOpen(): boolean
	local a = api
	if a and type(a.sheetOpen) == "function" then
		local ok, v = pcall(a.sheetOpen)
		return ok and v == true
	end
	return false
end

return M
