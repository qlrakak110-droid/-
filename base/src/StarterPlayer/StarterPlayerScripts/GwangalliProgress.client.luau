-- GwangalliProgress (client): 돈 버는 맛 + 인생 레벨 / 일일 목표 / 업적 / 마일스톤 UI (docs/ECONOMY.md).
-- Data comes only from the server (GwangalliRemotes.ProgressEvent / ProgressRequest, contract in
-- ReplicatedStorage.GwangalliProgressShared). Built with the GwangalliUI kit, placed with the
-- GwangalliLayout slot contract:
--   * money pops (+12,300원 with a count-up + coin sound) stacked under the phone's money chip, gold
--     flash for big pays; goal / badge cards in the same left column (never the centre of the screen)
--   * the 인생 레벨 chip (level ring + today's goals) right of the money chip (below it when the top row
--     is too narrow, e.g. portrait); tap -> the progress sheet (목표 / 업적 / 레벨 / 정산)
--   * payday card at the end of each in-game day (top-right slot), level-up banner and milestone
--     celebrations (top band, confetti, short camera pull-back)
-- Modules live in the Folder "GwangalliProgress" next to this script (found by class).
-- API for other client scripts: LocalPlayer.GwangalliProgressOpen (BindableEvent) :Fire(tab?)
-- tab = "goals" | "ach" | "level" | "pay". LocalPlayer attribute GwProgressPops = true (local only)
-- tells the phone HUD that money pops are shown here (it may skip its own +delta flash / money toasts).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function requireShared(name: string): any
	local m = ReplicatedStorage:WaitForChild(name, 30)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliProgress] ReplicatedStorage." .. name .. " missing; progress UI disabled")
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok then
		warn("[GwangalliProgress] " .. name .. " failed: " .. tostring(res))
		return nil
	end
	return res
end

local K = requireShared("GwangalliUI")
local Layout = requireShared("GwangalliLayout")
local P = requireShared("GwangalliProgressShared")
if not K or not Layout or not P then
	return
end

local folder: Instance? = nil
for _, c in script.Parent:GetChildren() do
	if c:IsA("Folder") and c.Name == "GwangalliProgress" then
		folder = c
		break
	end
end
if not folder then
	warn("[GwangalliProgress] module folder missing; progress UI disabled")
	return
end

local function mod(name: string): any
	local m = (folder :: Instance):FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliProgress] module missing: " .. name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok then
		warn("[GwangalliProgress] module " .. name .. " failed: " .. tostring(res))
		return nil
	end
	return res
end

local playerGui = player:WaitForChild("PlayerGui")

local function screenGui(name: string, order: number): ScreenGui
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	return K.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Enabled = true,
	})
end

-------------------------------------------------------------------------------------------------
-- Context shared by the modules
-------------------------------------------------------------------------------------------------
local C: any = {
	K = K,
	Layout = Layout,
	P = P,
	player = player,
	playerGui = playerGui,
	snap = nil, -- latest snapshot (ProgressRequest "snapshot", patched by "upd")
	-- above the phone HUD (6) so a pop covers the HUD's own small +delta flash; below the phone (30)
	hud = screenGui("GwangalliProgressHUD", 8),
	-- the sheet: above the phone (30), below the NPC dialog (35)
	panelGui = screenGui("GwangalliProgressPanel", 32),
	-- celebrations (short, top band): above the job / feature flows
	fx = screenGui("GwangalliProgressFX", 47),
}

local listeners: { [string]: { (...any) -> () } } = {}
function C.on(name: string, fn: (...any) -> ())
	local list = listeners[name] or {}
	listeners[name] = list
	table.insert(list, fn)
end
function C.emit(name: string, ...: any)
	for _, fn in table.clone(listeners[name] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[GwangalliProgress] " .. name .. ": " .. tostring(err))
		end
	end
end

-- HUD visibility mirrors the phone's always-on HUD (it already honours every HideGwangalliHUD flag:
-- the phone, job rounds, feature flows, our own sheet).
local phoneHud: ScreenGui? = nil
local visible = true
local function refreshVisible()
	local want = true
	if phoneHud and phoneHud.Parent then
		want = phoneHud.Enabled
	end
	if want ~= visible then
		visible = want
		C.hud.Enabled = want
		C.emit("visible", want)
	end
end
function C.visible(): boolean
	return visible
end

local phoneConn: RBXScriptConnection? = nil
local function watchPhoneHud(g: Instance)
	if g.Name ~= "GwangalliPhoneHUD" or not g:IsA("ScreenGui") then
		return
	end
	phoneHud = g
	if phoneConn then
		phoneConn:Disconnect()
	end
	phoneConn = g:GetPropertyChangedSignal("Enabled"):Connect(refreshVisible)
	C.emit("phonehud", g)
	refreshVisible()
end
for _, g in playerGui:GetChildren() do
	watchPhoneHud(g)
end
playerGui.ChildAdded:Connect(watchPhoneHud)
playerGui.ChildRemoved:Connect(function(g)
	if g == phoneHud then
		phoneHud = nil
		refreshVisible()
	end
end)

-- The phone's money chip (for placing the level chip and the pops next to it).
function C.moneyChip(): GuiObject?
	local g = phoneHud
	local chip = g and g:FindFirstChild("MoneyChip")
	if chip and chip:IsA("GuiObject") then
		return chip
	end
	return nil
end

-- Geometry of the top-left cluster in this gui's pixel space:
-- { s, chip = rect, level = rect (level chip), stackX, stackY (pops / cards start), stackW }
function C.geometry(): any
	local m = Layout.metrics()
	local s = m.s
	local slot = Layout.rect("topLeftChips")
	local center = Layout.rect("topCenter")
	local chip = C.moneyChip()
	local chipW = math.floor(150 * s)
	local chipH = slot.h
	if chip and chip.AbsoluteSize.X > 10 then
		chipW = math.floor(chip.AbsoluteSize.X + 0.5)
		chipH = math.floor(chip.AbsoluteSize.Y + 0.5)
	end
	local lvW = math.floor(56 * s + 0.5)
	local gap = m.gap
	local right = slot.x + chipW + gap
	local level: any
	local below = false
	local limit = math.max(slot.x + slot.w, center.x - gap)
	if m.class ~= "phoneP" and right + 44 <= limit then
		-- right of the money chip (a long cash amount squeezes it down to the 44 px minimum)
		level = { x = right, y = slot.y, w = math.min(lvW, limit - right), h = chipH }
	else
		-- portrait (the clock sits right next to the money chip): under it, aligned to its right edge so
		-- the left edge stays free (and clear of the thumbstick zone, which starts much lower)
		below = true
		level = { x = slot.x + math.max(0, chipW - lvW), y = slot.y + chipH + gap + 2, w = lvW, h = chipH }
	end
	local stackY = slot.y + chipH + 6
	if below then
		stackY = level.y + level.h + 6
	end
	return {
		s = s,
		class = m.class,
		chip = { x = slot.x, y = slot.y, w = chipW, h = chipH },
		level = level,
		levelBelow = below,
		stackX = slot.x,
		stackY = stackY,
		stackW = math.max(chipW, math.floor(200 * s)),
		W = m.W,
		H = m.H,
	}
end

-------------------------------------------------------------------------------------------------
-- Remotes
-------------------------------------------------------------------------------------------------
local requestRemote: RemoteFunction? = nil
function C.request(op: string, payload: any?): any
	local r = requestRemote
	if not r then
		return nil
	end
	local ok, res = pcall(function()
		return r:InvokeServer(op, payload)
	end)
	if ok then
		return res
	end
	return nil
end

-- patches the cached snapshot with a partial update
local function applyUpd(u: any)
	local s = C.snap
	if type(s) ~= "table" then
		return
	end
	if type(u.goals) == "table" then
		s.goals = u.goals
	end
	if u.weekly ~= nil then
		s.weekly = u.weekly
	end
	if type(u.level) == "number" then
		s.level = u.level
		s.title = P.titleFor(u.level)
	end
	if type(u.lp) == "number" then
		s.lp = u.lp
	end
	if type(u.earned) == "number" then
		s.earned = u.earned
	end
	if u.allDone ~= nil then
		s.allDone = u.allDone
	end
end

local refreshing = false
function C.refresh()
	if refreshing then
		return
	end
	refreshing = true
	task.spawn(function()
		local snap = C.request("snapshot")
		refreshing = false
		if type(snap) == "table" then
			C.snap = snap
			C.emit("snap", snap)
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------------------------
local Sfx = mod("Sfx")
if Sfx then
	Sfx.init(K)
end
C.Sfx = Sfx or setmetatable({}, {
	__index = function()
		return function() end
	end,
})
local names = { "Fx", "Pops", "Chip", "Payday", "Celebrate", "Panel" }
local mods: { [string]: any } = {}
for _, n in names do
	local m = mod(n)
	if m then
		mods[n] = m
		C[n] = m
	end
end
for _, n in names do
	local m = mods[n]
	if m and type(m.init) == "function" then
		local ok, err = pcall(m.init, C)
		if not ok then
			warn("[GwangalliProgress] " .. n .. ".init failed: " .. tostring(err))
		end
	end
end

C.hud.Parent = playerGui
C.panelGui.Parent = playerGui
C.fx.Parent = playerGui
pcall(function()
	player:SetAttribute("GwProgressPops", true)
end)

Layout.onChanged(function()
	C.emit("layout")
end)

-- Open API for the phone / other scripts
do
	local ev = player:FindFirstChild(P.OPEN_EVENT)
	if not (ev and ev:IsA("BindableEvent")) then
		if ev then
			ev:Destroy()
		end
		ev = Instance.new("BindableEvent")
		ev.Name = P.OPEN_EVENT
		ev.Parent = player
	end
	(ev :: BindableEvent).Event:Connect(function(tab: any)
		if C.Panel then
			C.Panel.open(if type(tab) == "string" then tab else nil)
		end
	end)
end

local function dispatch(msg: any)
	if type(msg) ~= "table" or type(msg.k) ~= "string" then
		return
	end
	local k = msg.k
	if k == "upd" then
		applyUpd(msg)
		C.emit("upd", msg)
	elseif k == "pop" then
		C.emit("pop", msg)
	elseif k == "goal" then
		C.emit("goal", msg)
		C.refreshSoon()
	elseif k == "ach" then
		C.emit("ach", msg)
		C.refreshSoon()
	elseif k == "level" then
		C.emit("level", msg)
		C.refreshSoon()
	elseif k == "ms" then
		C.emit("ms", msg)
	elseif k == "payday" then
		C.emit("payday", msg)
	elseif k == "newday" then
		C.emit("newday", msg)
		C.refreshSoon()
	end
end

local refreshPending = false
function C.refreshSoon()
	if refreshPending then
		return
	end
	refreshPending = true
	task.delay(1.5, function()
		refreshPending = false
		C.refresh()
	end)
end

task.spawn(function()
	local rf = ReplicatedStorage:WaitForChild("GwangalliRemotes", 60)
	if not rf then
		warn("[GwangalliProgress] GwangalliRemotes missing")
		return
	end
	local ev = rf:WaitForChild(P.Remotes.Event, 60)
	local req = rf:WaitForChild(P.Remotes.Request, 60)
	if req and req:IsA("RemoteFunction") then
		requestRemote = req
	end
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(function(msg)
			local ok, err = pcall(dispatch, msg)
			if not ok then
				warn("[GwangalliProgress] event failed: " .. tostring(err))
			end
		end)
	end
	C.refresh()
end)
