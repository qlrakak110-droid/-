-- test helper (scratch only): set attribute Cmd = "key|cmd|arg" on this LocalScript; result in attribute key
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local PS = script.Parent
local root = PS:WaitForChild("GwangalliDecorPlus")
local Editor = require(root:WaitForChild("Editor"))
local Panels = require(root:WaitForChild("Panels"))
local Camera = require(root:WaitForChild("Camera"))

local function run(cmd, arg)
	if cmd == "open" then
		player:WaitForChild("GwangalliDecorPlusOpen"):Fire("editor")
		for _ = 1, 60 do
			if Editor.isOpen() then
				return "open"
			end
			task.wait(0.25)
		end
		return "not open"
	elseif cmd == "pick" then
		Editor.pick(arg, "buy", nil)
		task.wait(0.4)
		local S = Editor.S
		return "mode=" .. tostring(S.mode) .. " valid=" .. tostring(S.valid) .. " code=" .. tostring(S.code)
	elseif cmd == "cancel" then
		Editor.cancel()
		return "ok"
	elseif cmd == "finish" then
		Panels.finish()
		return "ok"
	elseif cmd == "goals" then
		Panels.goals()
		return "ok"
	elseif cmd == "presets" then
		Panels.presets()
		return "ok"
	elseif cmd == "closeModal" then
		local g = Panels.gui()
		local n = 0
		if g then
			for _, c in g:GetChildren() do
				if c.Name == "DPModal" then
					c:Destroy()
					n += 1
				end
			end
		end
		return "closed " .. n
	elseif cmd == "select" then
		local u = nil
		for k in Editor.S.recs do
			u = k
			break
		end
		if u then
			Editor.select(u, false)
		end
		return "sel " .. tostring(u)
	elseif cmd == "close" then
		player.GwangalliDecorPlusOpen:Fire("close")
		return "ok"
	elseif cmd == "photo" then
		player.GwangalliDecorPlusOpen:Fire("photo")
		return "ok"
	elseif cmd == "orbit" then
		local a = string.split(arg, ",")
		Camera.orbit(tonumber(a[1]) or 0, tonumber(a[2]) or 0)
		Camera.zoom(tonumber(a[3]) or 1)
		return "ok"
	elseif cmd == "hideHost" then
		local n = 0
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and string.sub(g.Name, 1, 18) ~= "GwangalliDecorPlus" then
				g.Enabled = false
				n += 1
			end
		end
		return "hidden " .. n
	elseif cmd == "ghost" then
		local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
		local S = Editor.S
		Editor.pick(arg, "buy", nil)
		task.wait(0.3)
		local U = S.U
		for _, r in U.rooms do
			for gx = -3, 3 do
				for gz = -3, 3 do
					local x, z = r.centre.X + gx * r.size.X / 8, r.centre.Z + gz * r.size.Z / 8
					local ok = Shared.Rules.check(U, S.idx, { i = arg, x = x, y = r.floorY, z = z, r = 30 }, { isNew = true, caps = S.caps, counts = Editor.counts() })
					if ok then
						S.anchor = { i = arg, x = x, y = r.floorY, z = z, r = 30 }
						S.yaw = 30
						Editor.rotate(0)
						task.wait(0.5)
						return "ghost valid=" .. tostring(S.valid) .. " code=" .. tostring(S.code)
					end
				end
			end
		end
		return "no spot"
	elseif cmd == "guis" then
		local pg = player.PlayerGui
		local t = {}
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled then
				table.insert(t, g.Name)
			end
		end
		return table.concat(t, ",")
	end
	return "?"
end

script:GetAttributeChangedSignal("Cmd"):Connect(function()
	local v = script:GetAttribute("Cmd")
	if type(v) ~= "string" then
		return
	end
	local parts = string.split(v, "|")
	local key, cmd, arg = parts[1], parts[2], parts[3]
	task.spawn(function()
		local ok, r = pcall(run, cmd, arg)
		script:SetAttribute(key, if ok then tostring(r) else ("ERR " .. tostring(r)))
	end)
end)
