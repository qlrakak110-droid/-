-- GwangalliHealth (LocalScript, StarterPlayerScripts; owner: health): the client side of 피로도 / 질병 /
-- 병원. The server (GwangalliGameplay/Health.luau) decides everything; this script only renders:
--   * Chip     — the debuff chip ("😮‍💨 피로 -30%" / "🤧 감기 -80%") next to the phone's money chip,
--                animated in / out, driven by the Player attributes Fatigue / Illness (no remote traffic)
--   * Effects  — while ill: a soft desaturated grade (one ColorCorrectionEffect), thin edge vignette,
--                periodic cough / shiver emotes through GwangalliAnim; sparkles + "완치!" on a cure
--   * Clinic   — the hospital UI (kit BottomSheet): status card, 진료 받기 / 영양주사 / 건강검진 rows with
--                confirm dialogs (HealthRequest), the 건강검진 report modal
-- Modules live in the sibling Folder "GwangalliHealth" (same name as this script: found by class).
-- Remotes: GwangalliRemotes.HealthEvent (server -> client) and HealthRequest (RemoteFunction).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliHealth" and child:IsA("Folder") then
					return child
				end
			end
		end
		task.wait(0.1)
	end
	return nil
end

local folder = findFolder()
if not folder then
	warn("[GwangalliHealth] module folder missing next to the LocalScript")
	return
end

local function optional(name: string, timeout: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliHealth] " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

local K = optional("GwangalliUI", 20)
if not K then
	warn("[GwangalliHealth] GwangalliUI kit missing; health UI disabled")
	return
end
local Layout = K.Layout or optional("GwangalliLayout", 10)
local G = optional("GwangalliGameplayShared", 20)
local HS = optional("GwangalliHealthShared", 20)
if not G or not HS then
	warn("[GwangalliHealth] GwangalliGameplayShared / GwangalliHealthShared missing; health UI disabled")
	return
end
local Anim = optional("GwangalliAnim", 5)

local playerGui = player:WaitForChild("PlayerGui", 30) :: PlayerGui
if not playerGui then
	return
end

local old = playerGui:FindFirstChild("GwangalliHealth")
if old then
	old:Destroy()
end
local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliHealth"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 44
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui:SetAttribute("HideGwangalliHUD", false)
gui.Parent = playerGui

-------------------------------------------------------------------------------------------------
-- Context
-------------------------------------------------------------------------------------------------
local ctx: any = { K = K, Layout = Layout, G = G, HS = HS, Anim = Anim, player = player, gui = gui, playerGui = playerGui }

local remotesFolder: Instance? = nil
function ctx.remote(name: string, timeout: number?): Instance?
	local t0 = os.clock()
	local limit = timeout or 10
	while os.clock() - t0 < limit do
		remotesFolder = remotesFolder or ReplicatedStorage:FindFirstChild(G.RemotesFolder)
		if remotesFolder then
			local r = remotesFolder:FindFirstChild(name)
			if r then
				return r
			end
		end
		task.wait(0.25)
	end
	return nil
end

-- RemoteFunction call with a timeout -> result table ({ok = false, code = "timeout"} when it hangs)
function ctx.call(op: string, payload: any?, timeout: number?): any
	local rf = ctx.remote(G.Remote.HealthRequest, 5)
	if not rf or not rf:IsA("RemoteFunction") then
		return { ok = false, code = "offline", message = "서버와 연결되지 않았어요" }
	end
	local result: any = nil
	local done = false
	task.spawn(function()
		local ok, res = pcall(rf.InvokeServer, rf, op, payload)
		result = if ok then res else { ok = false, code = "error", message = tostring(res) }
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < (timeout or 8) do
		task.wait(0.05)
	end
	if not done then
		return { ok = false, code = "timeout", message = "응답이 없어요. 잠시 후 다시 시도해 주세요" }
	end
	if type(result) ~= "table" then
		return { ok = false, code = "bad", message = "잘못된 응답이에요" }
	end
	return result
end

function ctx.toast(t: any)
	K.toast(t)
end

-- character controls (touch: the clinic sheet covers the thumbstick / jump zones)
local function getControls(): any
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not (pm and pm:IsA("ModuleScript")) then
		return nil
	end
	local ok, mod = pcall(require, pm)
	if not ok or type(mod) ~= "table" or type(mod.GetControls) ~= "function" then
		return nil
	end
	local ok2, controls = pcall(mod.GetControls, mod)
	return if ok2 then controls else nil
end
local modalOn = false
function ctx.modal(on: boolean)
	if on == modalOn then
		return
	end
	modalOn = on
	gui:SetAttribute("HideGwangalliHUD", on)
	pcall(K.blur, on, "GwangalliHealth")
	local UIS = game:GetService("UserInputService")
	if UIS.TouchEnabled then
		local c = getControls()
		if c then
			pcall(function()
				if on then
					c:Disable()
				else
					c:Enable()
				end
			end)
		end
	end
end

-- event bus (modules talk through it)
local listeners: { [string]: { (...any) -> () } } = {}
function ctx.on(name: string, fn: (...any) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
end
function ctx.emit(name: string, ...: any)
	for _, fn in table.clone(listeners[name] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[GwangalliHealth] " .. name .. " listener: " .. tostring(err))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------------------------
local modules: { [string]: any } = {}
for _, name in { "Chip", "Effects", "Clinic" } do
	local m = folder:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			local okInit, err = pcall(res.init, ctx)
			if okInit then
				modules[name] = res
			else
				warn("[GwangalliHealth] " .. name .. " init failed: " .. tostring(err))
			end
		else
			warn("[GwangalliHealth] " .. name .. " failed to load: " .. tostring(res))
		end
	end
end
ctx.modules = modules

-------------------------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------------------------
task.spawn(function()
	local ev = ctx.remote(G.Remote.HealthEvent, 60)
	if not ev or not ev:IsA("RemoteEvent") then
		warn("[GwangalliHealth] HealthEvent remote missing; hospital UI disabled")
		return
	end
	ev.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.kind) ~= "string" then
			return
		end
		ctx.emit("event", payload)
		ctx.emit("event:" .. payload.kind, payload)
	end)
end)
