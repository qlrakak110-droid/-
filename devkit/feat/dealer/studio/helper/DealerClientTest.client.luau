-- test-only client helper (not part of the add-on): runs commands for the studio driver inside the client VM.
-- Cmd attribute = "<key>|<cmd>|<arg>"; the result is written to attribute <key> (string).
--   call  Module.fn|json   spawn Module.fn(decoded json) (json may be an array of args)
--   find  pattern          "x,y,insetY" of a visible TextButton of our ScreenGuis containing pattern
--   net   op|json          Net.call(op, payload) -> JSON reply
--   state                  JSON of the client state
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local root = script.Parent:WaitForChild("GwangalliCarDealer", 120)
local function M(n: string): any
	return require(root:WaitForChild(n, 30))
end
local function enc(v: any): string
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok then s else '{"err":"encode"}'
end
task.spawn(function()
	for _ = 1, 400 do
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg then
			for _, g in pg:GetChildren() do
				if g:IsA("ScreenGui") and g.Enabled and string.sub(g.Name, 1, 18) ~= "GwangalliCarDealer" then
					for _, d in g:GetDescendants() do
						if (d:IsA("TextLabel") or d:IsA("TextButton")) and string.find(d.Text, "출석", 1, true) and d.Visible then
							g.Enabled = false
							break
						end
					end
				end
			end
		end
		task.wait(1.5)
	end
end)
local function findBtn(pat: string): string
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local inset = GuiService:GetGuiInset()
	local guis = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and string.sub(g.Name, 1, 18) == "GwangalliCarDealer" then
			table.insert(guis, g)
		end
	end
	table.sort(guis, function(a, b)
		return a.DisplayOrder > b.DisplayOrder
	end)
	for _, g in guis do
		local function vis(o: Instance): boolean
			local x: Instance? = o
			while x and x ~= g do
				if x:IsA("GuiObject") and not x.Visible then
					return false
				end
				x = x.Parent
			end
			return true
		end
		for _, d in g:GetDescendants() do
			if d:IsA("TextButton") and vis(d) then
				local t = d.Text
				for _, c in d:GetDescendants() do
					if c:IsA("TextLabel") then
						t ..= " " .. c.Text
					end
				end
				if string.find(t, pat, 1, true) then
					local c = d.AbsolutePosition + d.AbsoluteSize / 2
					return string.format("%d,%d,%d", math.floor(c.X), math.floor(c.Y), math.floor(inset.Y))
				end
			end
		end
	end
	return "none"
end
script:GetAttributeChangedSignal("Cmd"):Connect(function()
	local raw = script:GetAttribute("Cmd")
	if type(raw) ~= "string" then
		return
	end
	local key, cmd, arg = string.match(raw, "^([^|]+)|([^|]+)|?(.*)$")
	if not key then
		return
	end
	task.spawn(function()
		local ok, res = pcall(function(): any
			if cmd == "call" then
				local modName, fnName, a = string.match(arg, "^(%w+)%.(%w+)|?(.*)$")
				local m = M(modName)
				local args = {}
				if a ~= "" then
					local v = HttpService:JSONDecode(a)
					args = if type(v) == "table" and v[1] ~= nil then v else { v }
				end
				task.spawn(function()
					local ok2, err = pcall(m[fnName], table.unpack(args))
					if not ok2 then
						warn("[DealerClientTest] " .. tostring(err))
					end
				end)
				return "spawned"
			elseif cmd == "find" then
				return findBtn(arg)
			elseif cmd == "net" then
				local op, js = string.match(arg, "^(%w+)|?(.*)$")
				local payload = if js ~= "" then HttpService:JSONDecode(js) else {}
				local r = M("Net").call(op, payload)
				if type(r) == "table" then
					local c = table.clone(r)
					if typeof(c.car) == "Instance" then
						c.car = c.car:GetFullName()
					end
					return enc(c)
				end
				return enc(r)
			elseif cmd == "state" then
				local Net = M("Net")
				local st = Net.state
				local pg = player:FindFirstChildOfClass("PlayerGui")
				local guis = {}
				for _, g in pg:GetChildren() do
					if g:IsA("ScreenGui") and string.sub(g.Name, 1, 18) == "GwangalliCarDealer" then
						guis[g.Name] = g.Enabled
					end
				end
				local tags = {}
				for _, x in game:GetService("CollectionService"):GetTagged("GwCarDealerNpc") do
					table.insert(tags, x:GetFullName())
				end
				return enc({ entries = #st.entries, loaded = st.loaded, near = st.snap and st.snap.near, owned = st.snap and st.snap.owned, guis = guis, npcs = tags, bank = player:GetAttribute("Bank"), cash = player:GetAttribute("Money") })
			end
			return "unknown"
		end)
		script:SetAttribute(key, if ok then tostring(res) else "ERR " .. tostring(res))
	end)
end)
script:SetAttribute("Ready", true)
