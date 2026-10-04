-- GwangalliFeatures (LocalScript, StarterPlayerScripts): bootstrap for the small real-life feature
-- flows (docs/features_contract.md §1): 송금 / 송금 요청 / 거래내역 / ATM / 현금 주기 (money) and the
-- modules other owners append to GwangalliFeatures/Registry.luau.
--
-- The code lives in the sibling Folder "GwangalliFeatures" (same name as this script, so the folder is
-- found by class). Every module gets the shared context F (kit, layout, the ScreenGui, modal / controls
-- handling, remotes, cross-module open) and exposes flows opened with F.open(flowId, args).
--
-- Public API for other client scripts (the phone apps, the HUD):
--   LocalPlayer.GwangalliFeaturesOpen   BindableEvent   :Fire(flowId, args)
--   LocalPlayer.GwangalliFeaturesQuery  BindableFunction :Invoke("flows") -> {ids} | ("isOpen") -> bool

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliFeatures" and child:IsA("Folder") then
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
	warn("[GwangalliFeatures] module folder missing next to the LocalScript")
	return
end

local function optional(name: string, timeout: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliFeatures] " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

local K = optional("GwangalliUI", 20)
if not K then
	warn("[GwangalliFeatures] GwangalliUI kit missing; features disabled")
	return
end
local Layout = K.Layout or optional("GwangalliLayout", 10)
if not Layout then
	warn("[GwangalliFeatures] GwangalliLayout missing; features disabled")
	return
end
local G = optional("GwangalliGameplayShared", 20)

local playerGui = player:WaitForChild("PlayerGui", 30) :: PlayerGui
if not playerGui then
	warn("[GwangalliFeatures] PlayerGui missing")
	return
end

-------------------------------------------------------------------------------------------------
-- The shared ScreenGui
-------------------------------------------------------------------------------------------------
local old = playerGui:FindFirstChild("GwangalliFeatures")
if old then
	old:Destroy()
end
local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliFeatures"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 45
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui:SetAttribute("HideGwangalliHUD", false)
gui.Parent = playerGui

-------------------------------------------------------------------------------------------------
-- Context
-------------------------------------------------------------------------------------------------
local F: any = { K = K, Layout = Layout, G = G, player = player, gui = gui, folder = folder }

-- event bus
local listeners: { [string]: { (...any) -> () } } = {}
function F.on(name: string, fn: (...any) -> ()): () -> ()
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
	return function()
		local i = table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end
function F.emit(name: string, ...: any)
	for _, fn in table.clone(listeners[name] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[GwangalliFeatures] " .. name .. " listener: " .. tostring(err))
		end
	end
end

-- character controls (touch: a modal flow covers the thumbstick / jump zones)
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
local function setControls(enabled: boolean)
	local c = getControls()
	if c then
		pcall(function()
			if enabled then
				c:Enable()
			else
				c:Disable()
			end
		end)
	end
end

-- refcounted modal state: HideGwangalliHUD (the phone / HUD step aside), controls off on touch, blur
local modalKeys: { [string]: boolean } = {}
local modalOn = false
local controlsOff = false
function F.modal(on: boolean, key: string?)
	modalKeys[key or "default"] = if on then true else nil
	local want = next(modalKeys) ~= nil
	if want == modalOn then
		return
	end
	modalOn = want
	gui:SetAttribute("HideGwangalliHUD", want)
	K.blur(want, "GwangalliFeatures")
	if want and UserInputService.TouchEnabled then
		controlsOff = true
		setControls(false)
	elseif not want and controlsOff then
		controlsOff = false
		setControls(true)
	end
	F.emit("modal", want)
end
function F.isModal(): boolean
	return modalOn
end

-- remotes (GwangalliRemotes is created by the server; wait in the background)
local remotesFolder: Instance? = nil
function F.remote(name: string, timeout: number?): Instance?
	local t0 = os.clock()
	local limit = timeout or 10
	while os.clock() - t0 < limit do
		remotesFolder = remotesFolder or ReplicatedStorage:FindFirstChild("GwangalliRemotes")
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

function F.toast(t: any)
	K.toast(t)
end

-- ask the phone to open an app (the phone creates LocalPlayer.GwangalliPhoneOpen when it supports it)
local APP_NAMES = { bank = "통장", messages = "메시지", call = "전화", taxi = "택시", map = "지도" }
function F.phone(app: string, args: any?)
	local ev = player:FindFirstChild("GwangalliPhoneOpen")
	if ev and ev:IsA("BindableEvent") then
		ev:Fire(app, args)
		return true
	end
	K.toast({ kind = "info", title = "📱 폰 → " .. (APP_NAMES[app] or app), body = "폰을 열어 '" .. (APP_NAMES[app] or app) .. "' 앱을 확인해요" })
	return false
end

-------------------------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------------------------
local flows: { [string]: any } = {}
local modules: { any } = {}

function F.open(flowId: string, args: any?): boolean
	local m = flows[flowId]
	if not m then
		warn("[GwangalliFeatures] unknown flow " .. tostring(flowId))
		return false
	end
	local ok, err = pcall(m.open, flowId, args or {})
	if not ok then
		warn("[GwangalliFeatures] open " .. flowId .. " failed: " .. tostring(err))
		return false
	end
	return true
end

function F.closeAll()
	for _, m in modules do
		if type(m.close) == "function" then
			pcall(m.close)
		end
	end
end

local registry: { string } = {}
do
	local reg = folder:FindFirstChild("Registry")
	if reg and reg:IsA("ModuleScript") then
		local ok, res = pcall(require, reg)
		if ok and type(res) == "table" then
			registry = res
		else
			warn("[GwangalliFeatures] Registry failed: " .. tostring(res))
		end
	end
end

for _, name in registry do
	if type(name) ~= "string" then
		continue
	end
	local ms = folder:FindFirstChild(name)
	if not (ms and ms:IsA("ModuleScript")) then
		warn("[GwangalliFeatures] module " .. name .. " listed in the Registry is missing")
		continue
	end
	local ok, m = pcall(require, ms)
	if not ok or type(m) ~= "table" then
		warn("[GwangalliFeatures] module " .. name .. " failed to load: " .. tostring(m))
		continue
	end
	local okInit, err = pcall(function()
		if type(m.init) == "function" then
			m.init(F)
		end
	end)
	if not okInit then
		warn("[GwangalliFeatures] module " .. name .. " init failed: " .. tostring(err))
		continue
	end
	table.insert(modules, m)
	for _, flowId in (if type(m.flows) == "table" then m.flows else {}) do
		if flows[flowId] then
			warn("[GwangalliFeatures] flow " .. flowId .. " registered twice (" .. name .. ")")
		else
			flows[flowId] = m
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------------------------
do
	local oldOpen = player:FindFirstChild("GwangalliFeaturesOpen")
	if oldOpen then
		oldOpen:Destroy()
	end
	local oldQuery = player:FindFirstChild("GwangalliFeaturesQuery")
	if oldQuery then
		oldQuery:Destroy()
	end
	local openEv = Instance.new("BindableEvent")
	openEv.Name = "GwangalliFeaturesOpen"
	openEv.Event:Connect(function(flowId: any, args: any)
		if type(flowId) == "string" then
			F.open(flowId, if type(args) == "table" then args else nil)
		end
	end)
	openEv.Parent = player
	local query = Instance.new("BindableFunction")
	query.Name = "GwangalliFeaturesQuery"
	query.OnInvoke = function(what: any): any
		if what == "flows" then
			local out = {}
			for id in flows do
				table.insert(out, id)
			end
			table.sort(out)
			return out
		elseif what == "isOpen" then
			for _, m in modules do
				if type(m.isOpen) == "function" then
					local ok, res = pcall(m.isOpen)
					if ok and res then
						return true
					end
				end
			end
			return false
		end
		return nil
	end
	query.Parent = player
end

-- respawn safety: never leave the controls disabled by a flow that was closed while dead
player.CharacterAdded:Connect(function()
	if not modalOn and controlsOff then
		controlsOff = false
		setControls(true)
	end
end)

local names = {}
for id in flows do
	table.insert(names, id)
end
table.sort(names)
print("[GwangalliFeatures] ready: " .. table.concat(names, ", "))
