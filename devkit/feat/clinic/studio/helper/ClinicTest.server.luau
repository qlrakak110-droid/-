-- test-only helper (not part of the add-on): async runner for the studio driver
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local f = Instance.new("BindableFunction")
f.Name = "ClinicTest"
f.Parent = SS
local function enc(v)
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok then s else '{"err":"encode"}'
end
local function anchors()
	local w = workspace:FindFirstChild("GwangalliClinic")
	return w and w:FindFirstChild("Anchors")
end
f.OnInvoke = function(kind, key, a, b, c)
	local P = Players:GetPlayers()[1]
	task.spawn(function()
		local ok, res = pcall(function()
			if kind == "clinic" then
				return SS.GwangalliClinicAPI:Invoke(a, P, b, c)
			elseif kind == "health" then
				return SS.GwangalliHealthAPI:Invoke(a, P, b, c)
			elseif kind == "gp" then
				return SS.GwangalliGameplayAPI:Invoke(a, P, b, c)
			elseif kind == "tp" then
				local an = anchors() and anchors():FindFirstChild(a)
				local ch = P.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if not an or not hrp then
					return { ok = false, err = "no anchor/hrp" }
				end
				if hum and hum.SeatPart then
					hum.Sit = false
					local w = hum.SeatPart:FindFirstChild("SeatWeld")
					if w then
						w:Destroy()
					end
				end
				-- the temp studio keeps a server-moved character only while its root is anchored
				hrp.Anchored = true
				hrp.CFrame = CFrame.new(an.Position + Vector3.new(0, 0.4, b or 0))
				return { ok = true, pos = tostring(hrp.Position) }
			elseif kind == "respawn" then
				-- the temp studio leaves a client-owned avatar at NaN after a server teleport + Seat:Sit
				-- (Health's own exam-bed choreography does exactly that): give the test a fresh body
				P:LoadCharacter()
				local t0 = os.clock()
				while os.clock() - t0 < 15 do
					local ch = P.Character
					local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
					if hrp and hrp.Position.X == hrp.Position.X then
						break
					end
					task.wait(0.3)
				end
				return { ok = true }
			elseif kind == "allow" then
				-- the game's anti-teleport detector (Jobs) would snap a long jump back
				local n = 0
				for _, c in game:GetService("ServerScriptService"):GetChildren() do
					if c.Name == "GwangalliGameplay" and c:IsA("Folder") then
						for _, nm in { "VenueLife", "Play" } do
							local m = c:FindFirstChild(nm)
							local okR, L = pcall(require, m)
							if okR and type(L) == "table" and type(L.ctx) == "table" and L.ctx.allowTeleport then
								L.ctx.allowTeleport(P, tonumber(a) or 900)
								n += 1
							end
						end
					end
				end
				return { ok = n > 0, n = n }
			elseif kind == "state" then
				local ch = P.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				return {
					fatigue = P:GetAttribute("Fatigue"),
					illness = P:GetAttribute("Illness"),
					bank = P:GetAttribute("Bank"),
					cash = P:GetAttribute("Money"),
					seat = hum and hum.SeatPart and hum.SeatPart:GetFullName() or "",
					anchored = hrp and hrp.Anchored,
					up = hrp and tostring(hrp.CFrame.UpVector) or "",
					pos = hrp and tostring(hrp.Position) or "",
					treating = ch and ch:GetAttribute("GwTreating"),
					pose = ch and ch:GetAttribute("GwClinicPose"),
					walk = hum and hum.WalkSpeed,
				}
			elseif kind == "world" then
				local w = workspace:FindFirstChild("GwangalliClinic")
				local n, m = 0, 0
				local list = {}
				if w then
					for _, x in w.Anchors:GetChildren() do
						n += 1
						table.insert(list, x.Name .. "@" .. string.format("%.1f,%.1f,%.1f", x.Position.X, x.Position.Y, x.Position.Z))
					end
					for _, s in w.Staff:GetChildren() do
						m += 1
					end
				end
				local legacy = {}
				for _, inst in game:GetService("CollectionService"):GetTagged("HospitalPrompt") do
					for _, d in inst:GetDescendants() do
						if d:IsA("ProximityPrompt") then
							table.insert(legacy, d.Name .. "=" .. tostring(d.Enabled))
						end
					end
				end
				local st = game:GetService("ReplicatedStorage").GwangalliClinicShared.State
				return { anchors = n, staff = m, legacy = legacy, list = list, board = st:GetAttribute("Board"), call = st:GetAttribute("Call") }
			end
			return { err = "kind?" }
		end)
		f:SetAttribute(key, enc(if ok then res else { err = tostring(res) }))
	end)
	return "spawned"
end
