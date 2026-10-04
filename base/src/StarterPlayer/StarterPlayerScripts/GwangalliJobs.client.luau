--!nocheck
-- GwangalliJobs (LocalScript, StarterPlayerScripts): the 알바 client (docs/JOBS.md).
-- Feedback stage rule: the CENTRE OF THE SCREEN STAYS CLEAR while working. The work happens in the
-- world (customers, props, the POS screen, shelves); the UI is only
--   Bar.luau       a slim status bar at the top-right edge (job · task · 오늘 +n원 · 🔥 · 퇴근)
--   Stage.luau     the round BOTTOM SHEET (<= 30 % of the screen height landscape, <= 38 % portrait)
--                  with a thin timer bar, small result pills, the shift summary (side rail / sheet)
--   Games.luau     one compact builder per round (sale / shelf / expiry / parcel / ask / drink / latte
--                  / pos / order)
--   World.luau     in-world props + interactions (counter items you tap to scan, POS SurfaceGui,
--                  scanner beeps, receipt, restock slots with prompts, glowing expiry items, the cup
--                  at the machine), camera framing of the station (TweenService), speech bubbles of
--                  the boss / customers, the door chime, the 택배 ring
--   Shop.luau      purchase sheet for EVERY player (drinks fridge / shelf / cafe counter) + the
--                  delivery office's 퀵 / 택배 dispatch cards
--   Delivery.luau  compact delivery chip ("<건물> <호수> - 배달요망", distance, timer, pay, 🚦)
-- The modules live in the sibling Folder "GwangalliJobs" (found by class). Server contract:
-- ReplicatedStorage.GwangalliRemotes.JobGame (GwangalliJobsShared header) + WorkState.
-- GwangalliUI kit only; official APIs only; one timer loop while a round is open, no per-frame work
-- otherwise (World uses tweens + one 0.25 s proximity loop while near a job place).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliJobs" and child:IsA("Folder") then
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
	warn("[GwangalliJobs] module folder missing next to the LocalScript")
	return
end

local function optional(name: string, timeout: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliJobs] " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

local K = optional("GwangalliUI", 20)
if not K then
	warn("[GwangalliJobs] GwangalliUI kit missing; job UI disabled")
	return
end
local JS = optional("GwangalliJobsShared", 20)
if not JS then
	warn("[GwangalliJobs] GwangalliJobsShared missing; job UI disabled")
	return
end
local Layout = K.Layout or optional("GwangalliLayout", 10)
local G = optional("GwangalliGameplayShared", 10)

local playerGui = player:WaitForChild("PlayerGui", 30)
if not playerGui then
	return
end

-------------------------------------------------------------------------------------------------
-- ScreenGui
-------------------------------------------------------------------------------------------------
local old = playerGui:FindFirstChild("GwangalliJobs")
if old then
	old:Destroy()
end
local gui = Instance.new("ScreenGui")
gui.Name = "GwangalliJobs"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 46 -- above the phone (30), dialog (35) and the feature flows (45)
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui:SetAttribute("HideGwangalliHUD", false)
gui.Parent = playerGui

-------------------------------------------------------------------------------------------------
-- Context shared by the modules
-------------------------------------------------------------------------------------------------
local J: any = { K = K, JS = JS, G = G, Layout = Layout, player = player, gui = gui, work = nil }

local function mod(name: string): any
	local m = folder:FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliJobs] module missing: " .. name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok or type(res) ~= "table" then
		warn("[GwangalliJobs] module " .. name .. " failed: " .. tostring(res))
		return nil
	end
	return res
end

-- remotes (the gameplay server may start late: keep waiting in the background)
local remotes: { [string]: Instance } = {}
local function remoteNow(name: string): any
	local r = remotes[name]
	if r and r.Parent then
		return r
	end
	local f = ReplicatedStorage:FindFirstChild("GwangalliRemotes")
	local inst = f and f:FindFirstChild(name)
	if inst then
		remotes[name] = inst
	end
	return inst
end

function J.send(payload: any): boolean
	local r = remoteNow(JS.Remote)
	if not r or not r:IsA("RemoteEvent") then
		K.toast({ kind = "error", title = "연결 중…", body = "잠시 후 다시 시도해 주세요" })
		return false
	end
	local ok, err = pcall(r.FireServer, r, payload)
	if not ok then
		warn("[GwangalliJobs] send failed: " .. tostring(err))
	end
	return ok
end

-- PhoneAction (endShift from the bar)
function J.phoneAction(action: string, payload: any?)
	local r = remoteNow("PhoneAction")
	if r and r:IsA("RemoteEvent") then
		pcall(r.FireServer, r, action, payload or {})
	end
end

function J.toast(t: any)
	pcall(K.toast, t)
end

-------------------------------------------------------------------------------------------------
-- Screen metrics (usable gui px) + containers
-------------------------------------------------------------------------------------------------
local TOPBAR = 58
function J.metrics(): any
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local cam = workspace.CurrentCamera
	local vx, vy = 390, 844
	if cam then
		local v = cam.ViewportSize
		if v.X > 50 and v.Y > 50 then
			vx, vy = v.X, v.Y
			W = if W > 50 then math.min(W, v.X) else v.X
			H = if H > 50 then math.min(H, v.Y - TOPBAR) else v.Y - TOPBAR
		end
	end
	if W < 50 or H < 50 then
		W, H = 390, 700
	end
	local landscape = W > H
	return {
		W = W,
		H = H,
		VW = vx,
		VH = vy,
		landscape = landscape,
		-- the bottom sheet may use this much height (gui px)
		sheetMax = math.floor((if landscape then 0.30 else 0.38) * vy),
	}
end

-------------------------------------------------------------------------------------------------
-- Character controls (refcounted): rounds at a station lock movement, the sheet covers the
-- thumbstick / jump zones then; always restored
-------------------------------------------------------------------------------------------------
local function getControls(): any
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not (pm and pm:IsA("ModuleScript")) then
		return nil
	end
	local ok, m = pcall(require, pm)
	if not ok or type(m) ~= "table" or type(m.GetControls) ~= "function" then
		return nil
	end
	local ok2, controls = pcall(m.GetControls, m)
	return if ok2 then controls else nil
end
local lockKeys: { [string]: boolean } = {}
local locked = false
function J.lockControls(on: boolean, key: string?)
	lockKeys[key or "default"] = if on then true else nil
	local want = next(lockKeys) ~= nil
	if want == locked then
		return
	end
	locked = want
	local c = getControls()
	if c then
		pcall(function()
			if want then
				c:Disable()
			else
				c:Enable()
			end
		end)
	end
	-- the always-on HUD (이동 / 달리기 / 폰 buttons) steps aside while the sheet covers the bottom
	gui:SetAttribute("HideGwangalliHUD", want and UserInputService.TouchEnabled)
end

-------------------------------------------------------------------------------------------------
-- Camera framing (TweenService). Only when the camera is ours to take (Custom), always given back.
-------------------------------------------------------------------------------------------------
local camFramed = false
local camTween: Tween? = nil
local camSerial = 0
function J.frameCamera(eye: Vector3, focus: Vector3, seconds: number?)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if not camFramed and cam.CameraType ~= Enum.CameraType.Custom then
		return -- another script owns the camera (dialog, car interior, cutscene)
	end
	if workspace:GetAttribute("GwangalliJobCam") == false or player:GetAttribute("GwangalliJobCam") == false then
		return
	end
	camSerial += 1
	camFramed = true
	cam.CameraType = Enum.CameraType.Scriptable
	if camTween then
		camTween:Cancel()
	end
	local goal = CFrame.lookAt(eye, focus)
	local ok, tw = pcall(function()
		return TweenService:Create(cam, TweenInfo.new(seconds or 0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = goal })
	end)
	if ok and tw then
		camTween = tw
		tw:Play()
	else
		cam.CFrame = goal
	end
end

function J.releaseCamera()
	if not camFramed then
		return
	end
	camFramed = false
	camSerial += 1
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

function J.cameraFramed(): boolean
	return camFramed
end

-------------------------------------------------------------------------------------------------
-- Sounds (rbxasset built-ins only) and speech bubbles (the shared pool of GwangalliBumpShared,
-- else a small local BillboardGui)
-------------------------------------------------------------------------------------------------
local SFX = {
	beep = { "rbxasset://sounds/electronicpingshort.wav", 2.3, 0.32 },
	chime = { "rbxasset://sounds/electronicpingshort.wav", 1.0, 0.3 },
	chime2 = { "rbxasset://sounds/electronicpingshort.wav", 0.78, 0.3 },
	place = { "rbxasset://sounds/clickfast.wav", 0.9, 0.35 },
	printer = { "rbxasset://sounds/clickfast.wav", 1.6, 0.3 },
	pour = { "rbxasset://sounds/swoosh.wav", 0.7, 0.25 },
	coin = { "rbxasset://sounds/electronicpingshort.wav", 1.6, 0.28 },
	wrong = { "rbxasset://sounds/clickfast.wav", 0.55, 0.35 },
}
local sfxCache: { [string]: Sound } = {}
function J.sfx(name: string)
	if K.settings and K.settings.sound == false then
		return
	end
	local def = SFX[name]
	if not def then
		return
	end
	local s = sfxCache[name]
	if not (s and s.Parent) then
		s = Instance.new("Sound")
		s.Name = "GwJobSfx_" .. name
		s.SoundId = def[1]
		s.PlaybackSpeed = def[2]
		s.Volume = def[3]
		s.Parent = SoundService
		sfxCache[name] = s
	end
	pcall(function()
		s.TimePosition = 0
		s:Play()
	end)
end

local bubbles: any = nil
local bubblesTried = false
local function bubblePool(): any
	if bubblesTried then
		return bubbles
	end
	bubblesTried = true
	local m = ReplicatedStorage:FindFirstChild("GwangalliBumpShared")
	if m and m:IsA("ModuleScript") then
		local ok, B = pcall(require, m)
		if ok and type(B) == "table" and type(B.bubbles) == "function" then
			local ok2, pool = pcall(B.bubbles)
			if ok2 and pool and type(pool.say) == "function" then
				bubbles = pool
			end
		end
	end
	return bubbles
end

local localBubbles: { [Instance]: BillboardGui } = {}
function J.bubble(adornee: Instance?, text: string, dur: number?, kind: string?)
	if typeof(adornee) ~= "Instance" or not adornee:IsA("BasePart") or type(text) ~= "string" or text == "" then
		return false
	end
	local pool = bubblePool()
	if pool then
		local ok = pcall(function()
			pool:say(adornee, text, kind or "talk", dur or 3.5, 2.4)
		end)
		if ok then
			return true
		end
	end
	-- fallback: one small billboard per adornee
	local bb = localBubbles[adornee]
	if not (bb and bb.Parent) then
		bb = Instance.new("BillboardGui")
		bb.Name = "GwJobBubble"
		bb.Size = UDim2.fromOffset(200, 46)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		bb.MaxDistance = 45
		bb.AlwaysOnTop = false
		bb.LightInfluence = 0
		local box = Instance.new("TextLabel")
		box.Name = "Text"
		box.Size = UDim2.fromScale(1, 1)
		box.BackgroundColor3 = Color3.fromRGB(250, 250, 252)
		box.BackgroundTransparency = 0.05
		box.TextColor3 = Color3.fromRGB(24, 26, 36)
		box.Font = Enum.Font.GothamBold
		box.TextScaled = true
		box.TextWrapped = true
		box.Parent = bb
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = box
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = box
		bb.Adornee = adornee
		bb.Parent = gui
		localBubbles[adornee] = bb
	end
	local label = bb:FindFirstChild("Text") :: TextLabel
	label.Text = text
	bb.Enabled = true
	local stamp = os.clock()
	bb:SetAttribute("Stamp", stamp)
	task.delay(dur or 3.5, function()
		if bb.Parent and bb:GetAttribute("Stamp") == stamp then
			bb.Enabled = false
		end
	end)
	return true
end

-- Head (or root) of an NPC model in the workspace (nil when streamed out)
function J.headOf(model: Instance?): BasePart?
	if typeof(model) ~= "Instance" or not model.Parent then
		return nil
	end
	local h = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if h and h:IsA("BasePart") then
		return h
	end
	return nil
end

function J.npcModel(npcId: string?): Model?
	if type(npcId) ~= "string" then
		return nil
	end
	local f = workspace:FindFirstChild("GwangalliNPCs")
	local m = f and f:FindFirstChild("NPC_" .. npcId)
	return if m and m:IsA("Model") then m else nil
end

function J.rootPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- the Overlay / phone may want to know
function J.publishState(open: boolean)
	player:SetAttribute("GwangalliJobGameOpen", open)
end

-------------------------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------------------------
local Bar = mod("Bar")
local Stage = mod("Stage")
local Games = mod("Games")
local World = mod("World")
local Shop = mod("Shop")
local Delivery = mod("Delivery")
if not Stage or not Games then
	warn("[GwangalliJobs] Stage / Games missing; job UI disabled")
	return
end
J.Games = Games
J.World = World
J.Stage = Stage
J.Bar = Bar
for _, m in { Bar, World, Stage, Shop, Delivery } do
	if m and type(m.init) == "function" then
		local ok, err = pcall(m.init, J)
		if not ok then
			warn("[GwangalliJobs] init failed: " .. tostring(err))
		end
	end
end

local function call(m: any, fn: string, ...: any)
	if m and type(m[fn]) == "function" then
		local ok, err = pcall(m[fn], ...)
		if not ok then
			warn("[GwangalliJobs] " .. fn .. ": " .. tostring(err))
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------------------------
local function onGame(p: any)
	if type(p) ~= "table" or type(p.op) ~= "string" then
		return
	end
	local op = p.op
	if op == "round" then
		call(World, "round", p)
		Stage.round(p)
	elseif op == "result" then
		call(World, "result", p)
		if p.game == "deliver" then
			call(Delivery, "result", p)
			call(Stage, "flashResult", p)
		else
			Stage.result(p)
		end
		call(Bar, "result", p)
	elseif op == "summary" then
		call(World, "clear")
		Stage.summary(p)
		call(Delivery, "hide")
	elseif op == "delivery" then
		call(Delivery, "update", p)
		call(World, "delivery", p)
	elseif op == "say" then
		call(World, "say", p)
	elseif op == "shop" or op == "bought" or op == "dispatch" then
		call(Shop, op, p)
	elseif op == "redlight" then
		call(Delivery, "redlight", p)
	elseif op == "close" then
		Stage.close()
		call(World, "clear")
		call(Delivery, "hide")
	end
end

local function onWork(data: any)
	if type(data) ~= "table" then
		return
	end
	J.work = data
	call(Bar, "update", data)
	call(World, "work", data)
	if data.onShift ~= true then
		Stage.closeRound()
		call(Delivery, "hide")
	else
		call(Delivery, "onWork", data)
	end
end

local bound: { [Instance]: boolean } = {}
local function bind(f: Instance)
	for _, r in f:GetChildren() do
		if bound[r] then
			continue
		end
		if r.Name == JS.Remote and r:IsA("RemoteEvent") then
			bound[r] = true
			remotes[JS.Remote] = r
			r.OnClientEvent:Connect(function(p: any)
				local ok, err = pcall(onGame, p)
				if not ok then
					warn("[GwangalliJobs] event failed: " .. tostring(err))
				end
			end)
		elseif r.Name == "WorkState" and r:IsA("RemoteEvent") then
			bound[r] = true
			remotes.WorkState = r
			r.OnClientEvent:Connect(function(p: any)
				local ok, err = pcall(onWork, p)
				if not ok then
					warn("[GwangalliJobs] work state failed: " .. tostring(err))
				end
			end)
		end
	end
end

task.spawn(function()
	local f = ReplicatedStorage:FindFirstChild("GwangalliRemotes") or ReplicatedStorage:WaitForChild("GwangalliRemotes", 120)
	if not f then
		warn("[GwangalliJobs] GwangalliRemotes never appeared; job UI offline")
		return
	end
	bind(f)
	f.ChildAdded:Connect(function()
		bind(f)
	end)
end)

-- a respawn never leaves the camera or the controls locked
player.CharacterAdded:Connect(function()
	J.releaseCamera()
	call(Stage, "closeRound")
end)
