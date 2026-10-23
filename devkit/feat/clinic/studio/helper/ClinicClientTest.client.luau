-- test-only client helper (not part of the add-on): runs commands for the studio driver inside the client VM.
-- Cmd attribute = "<key>|<cmd>|<arg>"; the result is written to attribute <key> (string).
--   call  Module.fn[|arg]    spawn Module.fn(arg) (prompt handlers that wait on dialogs)
--   find  pattern            "x,y,insetY" of a visible TextButton of our ScreenGui containing pattern
--   net   op|json            Net.call(op, payload) -> JSON reply
--   close                    Ui.closeAll()
--   visit                    JSON of ctx-like view: the Tracker's last visit is not exposed; returns Net.call("hello")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local root = script.Parent:WaitForChild("GwangalliClinic", 120)
local function M(n: string): any
	return require(root:WaitForChild(n, 30))
end
local function enc(v: any): string
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok then s else '{"err":"encode"}'
end
-- hide the game's own popups (출석 체크 ...) that cover screenshots
task.spawn(function()
	for _ = 1, 400 do
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg then
			for _, g in pg:GetChildren() do
				if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "GwangalliClinic" then
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
	local g = pg and pg:FindFirstChild("GwangalliClinic")
	if not g then
		return "nogui"
	end
	local inset = GuiService:GetGuiInset()
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
	local function txt(o: Instance): string
		local t = (o :: any).Text or ""
		for _, d in o:GetDescendants() do
			if d:IsA("TextLabel") then
				t = t .. " " .. d.Text
			end
		end
		return t
	end
	-- the temp studio's AbsolutePosition ignores AnchorPoint on AutomaticSize frames: pin the staff dialog
	-- (and its auto-width choice buttons) to fixed sizes so the computed centre matches what is drawn
	local dlg = g:FindFirstChild("Dialog")
	if dlg and dlg:IsA("Frame") and dlg.Visible then
		dlg.AutomaticSize = Enum.AutomaticSize.None
		dlg.AnchorPoint = Vector2.new(0.5, 0)
		dlg.Size = UDim2.fromOffset(720, 170)
		dlg.Position = UDim2.new(0.5, 0, 1, -186)
		for _, d in dlg:GetDescendants() do
			if d:IsA("GuiObject") and d.AutomaticSize ~= Enum.AutomaticSize.None then
				d.AutomaticSize = Enum.AutomaticSize.None
				if d:IsA("TextButton") then
					d.Size = UDim2.fromOffset(230, 44)
				elseif d.Name == "Stack" then
					d.Size = UDim2.new(1, -74, 0, 130)
				elseif d.Name == "Text" then
					d.Size = UDim2.new(1, 0, 0, 60)
				elseif d.Name == "Choices" then
					d.Size = UDim2.new(1, 0, 0, 50)
				end
			end
		end
	end
	for _, d in g:GetDescendants() do
		if d:IsA("TextButton") and vis(d) and string.find(txt(d), pat, 1, true) then
			local c = d.AbsolutePosition + d.AbsoluteSize / 2
			return string.format("%d,%d,%d", math.floor(c.X), math.floor(c.Y), math.floor(inset.Y))
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
				task.spawn(function()
					local ok2, err = pcall(m[fnName], if a ~= "" then a else nil)
					if not ok2 then
						warn("[ClinicClientTest] " .. tostring(err))
					end
				end)
				return "spawned"
			elseif cmd == "find" then
				return findBtn(arg)
			elseif cmd == "net" then
				local op, js = string.match(arg, "^(%w+)|?(.*)$")
				local payload = if js ~= "" then HttpService:JSONDecode(js) else {}
				return enc(M("Net").call(op, payload))
			elseif cmd == "close" then
				M("Ui").closeAll()
				M("Ui").hideDialog()
				return "closed"
			end
			return "unknown"
		end)
		script:SetAttribute(key, if ok then tostring(res) else "ERR " .. tostring(res))
	end)
end)
script:SetAttribute("Ready", true)
