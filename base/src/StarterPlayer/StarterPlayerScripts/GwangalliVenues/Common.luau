-- GwangalliVenues/Common: the shared client context of the venue interiors (owner: venues_detail).
--   C.K (GwangalliUI kit)  C.Layout  C.V (GwangalliVenuesShared)  C.G  C.Anim  C.player  C.gui
--   C.request(op, payload) -> result (yields; never errors)   C.on(kind, fn)   C.serverNow()
--   C.sound(kind, speed?, volume?)   C.note(semitones, volume?)  (chiptune: built-in rbxasset sounds)
--   C.controls(enabled)  C.hideHud(key, on)  C.root() / C.humanoid()  C.toast(kind, title, body)
--   C.poseOf(act) -> pose definition (used by Gym for the rep loops)
-- THE ACT DRIVER (one Heartbeat loop for the whole module set): every character whose Player carries
-- the attribute GwVenueAct (tambourine / sing / eat / drink / punch / pc / gym:<style>) gets the
-- matching procedural pose layers through GwangalliAnim's rig controller (C0 offsets on top of the
-- Animate tracks), so every client sees everyone's venue actions; VenueStaff rigs play their Act
-- (GwangalliAnim ACTS / poses / emotes), walk while Moving > 0 and glance at a nearby player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Common = {}

local function optional(name: string, timeout: number): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		warn("[GwangalliVenues] " .. name .. " failed to load: " .. tostring(res))
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- Pose library (degrees; GwangalliAnim conventions: limbs {pitch, yaw, roll}, pitch > 0 raises an
-- arm forward / bends an elbow, knees bend with pitch < 0, roll > 0 swings toward +X; Root / Waist /
-- Neck {pitch, yaw, roll, dx, dy, dz}). Each act: a = pose at phase 0, b = pose at phase 0.5,
-- period = seconds per cycle (the pose eases a -> b -> a). Offsets compose with the Animate track
-- (sit / idle / run), so seated styles only add the motion.
-------------------------------------------------------------------------------------------------
local POSES = {
	tambourine = {
		period = 0.24,
		a = { RightShoulder = { 150, 0, 20 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 30 }, LeftShoulder = { 20, 0, -10 }, Waist = { 0, 0, 3 } },
		b = { RightShoulder = { 144, 0, 26 }, RightElbow = { 36, 0, 0 }, RightWrist = { 0, 0, -30 }, LeftShoulder = { 26, 0, -14 }, Waist = { 0, 0, -3 } },
	},
	sing = {
		period = 1.3,
		a = { RightShoulder = { 62, 20, -15 }, RightElbow = { 118, 0, 0 }, Neck = { 8, 0, 0 }, LeftShoulder = { 30, 0, -25 }, LeftElbow = { 30, 0, 0 }, Waist = { 0, 0, 4 } },
		b = { RightShoulder = { 66, 20, -15 }, RightElbow = { 122, 0, 0 }, Neck = { 14, 4, 0 }, LeftShoulder = { 55, 0, -40 }, LeftElbow = { 20, 0, 0 }, Waist = { 0, 0, -4 } },
	},
	eat = {
		period = 1.0,
		a = { LeftShoulder = { 40, 0, -10 }, LeftElbow = { 85, 0, 0 }, RightShoulder = { 35, 0, -10 }, RightElbow = { 95, 0, 0 }, Neck = { -14, 0, 0 } },
		b = { LeftShoulder = { 42, 0, -10 }, LeftElbow = { 90, 0, 0 }, RightShoulder = { 46, 0, -24 }, RightElbow = { 126, 0, 0 }, Neck = { -6, 0, 0 } },
	},
	eat_hand = {
		period = 1.2,
		a = { RightShoulder = { 25, 0, 0 }, RightElbow = { 70, 0, 0 } },
		b = { RightShoulder = { 46, 0, -20 }, RightElbow = { 132, 0, 0 }, Neck = { 5, 0, 0 } },
	},
	drink = {
		period = 1.6,
		a = { RightShoulder = { 50, 0, -15 }, RightElbow = { 128, 0, 0 }, Neck = { 16, 0, 0 } },
		b = { RightShoulder = { 56, 0, -15 }, RightElbow = { 134, 0, 0 }, Neck = { 24, 0, 0 } },
	},
	punch = {
		period = 0.6,
		a = { RightShoulder = { 40, 0, -30 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 50, 0, 10 }, LeftElbow = { 100, 0, 0 }, Waist = { 0, -20, 0 } },
		b = { RightShoulder = { 90, 0, 0 }, RightElbow = { 2, 0, 0 }, LeftShoulder = { 40, 0, 20 }, LeftElbow = { 110, 0, 0 }, Waist = { 0, 18, 0 } },
	},
	pc = {
		period = 0.32,
		a = { RightShoulder = { 50, 0, -8 }, RightElbow = { 55, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 50, 0, 8 }, LeftElbow = { 55, 0, 0 }, LeftWrist = { 8, 0, 0 }, Neck = { -10, 0, 0 } },
		b = { RightShoulder = { 50, 0, -8 }, RightElbow = { 58, 0, 0 }, RightWrist = { 8, 0, 0 }, LeftShoulder = { 50, 0, 8 }, LeftElbow = { 52, 0, 0 }, LeftWrist = { -10, 0, 0 }, Neck = { -10, 0, 0 } },
	},
	-- gym styles (GwangalliVenuesShared.STYLE periods)
	["gym:run"] = { period = 0.42, a = {}, b = {} }, -- the run track (played by the owner, replicated) does the work
	["gym:cycle"] = {
		a = { RightHip = { 22, 0, 0 }, RightKnee = { 30, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightShoulder = { 52, 0, 0 }, LeftShoulder = { 52, 0, 0 }, Waist = { -14, 0, 0 } },
		b = { RightHip = { -22, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { 22, 0, 0 }, LeftKnee = { 30, 0, 0 }, RightShoulder = { 52, 0, 0 }, LeftShoulder = { 52, 0, 0 }, Waist = { -14, 0, 0 } },
	},
	["gym:row"] = {
		a = { RightShoulder = { 72, 0, 0 }, LeftShoulder = { 72, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftElbow = { 0, 0, 0 }, Waist = { -18, 0, 0 }, RightHip = { 35, 0, 0 }, LeftHip = { 35, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } },
		b = { RightShoulder = { 22, 0, 10 }, LeftShoulder = { 22, 0, -10 }, RightElbow = { 100, 0, 0 }, LeftElbow = { 100, 0, 0 }, Waist = { 12, 0, 0 }, RightHip = { -5, 0, 0 }, LeftHip = { -5, 0, 0 }, RightKnee = { 80, 0, 0 }, LeftKnee = { 80, 0, 0 } },
	},
	["gym:bench"] = {
		a = { RightShoulder = { 45, 0, 45 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { 45, 0, -45 }, LeftElbow = { 95, 0, 0 }, RightHip = { -40, 0, 8 }, LeftHip = { -40, 0, -8 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -70, 0, 0 } },
		b = { RightShoulder = { 90, 0, 12 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 90, 0, -12 }, LeftElbow = { 8, 0, 0 }, RightHip = { -40, 0, 8 }, LeftHip = { -40, 0, -8 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -70, 0, 0 } },
	},
	["gym:squat"] = {
		a = { RightShoulder = { 30, 0, 75 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 30, 0, -75 }, LeftElbow = { 100, 0, 0 } },
		b = { Root = { 0, 0, 0, 0, -1.1, 0 }, RightHip = { 108, 0, 6 }, LeftHip = { 108, 0, -6 }, RightKnee = { -126, 0, 0 }, LeftKnee = { -126, 0, 0 }, Waist = { -18, 0, 0 }, RightShoulder = { 30, 0, 75 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 30, 0, -75 }, LeftElbow = { 100, 0, 0 } },
	},
	["gym:curl"] = {
		a = { RightShoulder = { 8, 0, 4 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 14, 0, -4 }, LeftElbow = { 135, 0, 0 } },
		b = { RightShoulder = { 14, 0, 4 }, RightElbow = { 135, 0, 0 }, LeftShoulder = { 8, 0, -4 }, LeftElbow = { 10, 0, 0 } },
	},
	["gym:pullup"] = {
		a = { RightShoulder = { 170, 0, 15 }, LeftShoulder = { 170, 0, -15 }, RightElbow = { 5, 0, 0 }, LeftElbow = { 5, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -20, 0, 0 } },
		b = { Root = { 0, 0, 0, 0, 1.3, 0 }, RightShoulder = { 150, 0, 40 }, LeftShoulder = { 150, 0, -40 }, RightElbow = { 120, 0, 0 }, LeftElbow = { 120, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -45, 0, 0 }, LeftKnee = { -45, 0, 0 } },
	},
	["gym:cable"] = {
		a = { RightShoulder = { 70, 0, 70 }, LeftShoulder = { 70, 0, -70 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightHip = { 18, 0, 0 }, RightKnee = { -18, 0, 0 } },
		b = { RightShoulder = { 76, 0, 4 }, LeftShoulder = { 76, 0, -4 }, RightElbow = { 14, 0, 0 }, LeftElbow = { 14, 0, 0 }, RightHip = { 18, 0, 0 }, RightKnee = { -18, 0, 0 }, Waist = { -6, 0, 0 } },
	},
	["gym:legpress"] = {
		a = { RightHip = { 40, 0, 6 }, LeftHip = { 40, 0, -6 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightShoulder = { 20, 0, 12 }, LeftShoulder = { 20, 0, -12 } },
		b = { RightHip = { -10, 0, 6 }, LeftHip = { -10, 0, -6 }, RightKnee = { 84, 0, 0 }, LeftKnee = { 84, 0, 0 }, RightShoulder = { 20, 0, 12 }, LeftShoulder = { 20, 0, -12 } },
	},
	["gym:lat"] = {
		a = { RightShoulder = { 170, 0, 25 }, LeftShoulder = { 170, 0, -25 }, RightElbow = { 5, 0, 0 }, LeftElbow = { 5, 0, 0 } },
		b = { RightShoulder = { 120, 0, 60 }, LeftShoulder = { 120, 0, -60 }, RightElbow = { 110, 0, 0 }, LeftElbow = { 110, 0, 0 }, Waist = { 8, 0, 0 } },
	},
	["gym:scan"] = {
		a = { RightShoulder = { 30, 0, 30 }, LeftShoulder = { 30, 0, -30 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 } },
		b = { RightShoulder = { 30, 0, 30 }, LeftShoulder = { 30, 0, -30 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 } },
	},
}

local function lerpPose(a: any, b: any, s: number, out: any): any
	table.clear(out)
	for j, va in a do
		local vb = b[j] or va
		out[j] = { va[1] + ((vb[1] or 0) - va[1]) * s, (va[2] or 0) + ((vb[2] or 0) - (va[2] or 0)) * s, (va[3] or 0) + ((vb[3] or 0) - (va[3] or 0)) * s, (va[4] or 0) + ((vb[4] or 0) - (va[4] or 0)) * s, (va[5] or 0) + ((vb[5] or 0) - (va[5] or 0)) * s, (va[6] or 0) + ((vb[6] or 0) - (va[6] or 0)) * s }
	end
	for j, vb in b do
		if not a[j] then
			out[j] = { (vb[1] or 0) * s, (vb[2] or 0) * s, (vb[3] or 0) * s, (vb[4] or 0) * s, (vb[5] or 0) * s, (vb[6] or 0) * s }
		end
	end
	return out
end
Common.lerpPose = lerpPose

function Common.init(player: Player): any
	local K = optional("GwangalliUI", 20)
	local V = optional("GwangalliVenuesShared", 20)
	if not K or not V then
		warn("[GwangalliVenues] GwangalliUI / GwangalliVenuesShared missing; venue UI disabled")
		return nil
	end
	local G = optional("GwangalliGameplayShared", 10)
	local Anim = optional("GwangalliAnim", 10)
	local Layout = K.Layout or optional("GwangalliLayout", 10)
	local playerGui = player:WaitForChild("PlayerGui", 30) :: PlayerGui
	if not playerGui then
		return nil
	end
	local old = playerGui:FindFirstChild("GwangalliVenues")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliVenues"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 43
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	gui.Parent = playerGui

	local C: any = { K = K, V = V, G = G, Anim = Anim, Layout = Layout, player = player, gui = gui, modules = {} }
	local handlers: { [string]: { (any) -> () } } = {}

	function C.on(kind: string, fn: (any) -> ())
		local list = handlers[kind] or {}
		handlers[kind] = list
		table.insert(list, fn)
	end
	function C.dispatch(kind: string, payload: any)
		for _, fn in handlers[kind] or {} do
			local ok, err = pcall(fn, payload)
			if not ok then
				warn("[GwangalliVenues] " .. kind .. ": " .. tostring(err))
			end
		end
	end

	function C.serverNow(): number
		return workspace:GetServerTimeNow()
	end
	function C.humanoid(): Humanoid?
		local ch = player.Character
		return ch and ch:FindFirstChildOfClass("Humanoid") or nil
	end
	function C.root(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return if r and r:IsA("BasePart") then r else nil
	end
	function C.toast(kind: string, title: string, body: string?)
		pcall(K.toast, { kind = kind, title = title, body = body or "" })
	end

	-- remotes (created by the server's VenueLife at start)
	local reqRemote: RemoteFunction? = nil
	local evRemote: RemoteEvent? = nil
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("GwangalliRemotes", 60)
		if not folder then
			return
		end
		local r = folder:WaitForChild(V.Remote.Request, 60)
		if r and r:IsA("RemoteFunction") then
			reqRemote = r
		end
		local e = folder:WaitForChild(V.Remote.Event, 60)
		if e and e:IsA("RemoteEvent") then
			evRemote = e
			e.OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" and type(payload.kind) == "string" then
					C.dispatch(payload.kind, payload)
				end
			end)
		end
	end)
	function C.request(op: string, payload: any?): any
		if not reqRemote then
			return { ok = false, code = "offline", message = "잠시 후에 다시 시도해 주세요" }
		end
		local ok, res = pcall((reqRemote :: RemoteFunction).InvokeServer, reqRemote :: RemoteFunction, op, payload)
		if ok and type(res) == "table" then
			return res
		end
		return { ok = false, code = "error", message = "잠시 후에 다시 시도해 주세요" }
	end

	-- sounds: built-in client sounds only (pooled, 2D)
	local SOUND_IDS = { tap = "rbxasset://sounds/clickfast.wav", ping = "rbxasset://sounds/electronicpingshort.wav", swoosh = "rbxasset://sounds/swoosh.wav" }
	local pool: { Sound } = {}
	local poolIdx = 0
	for i = 1, 8 do
		local s = Instance.new("Sound")
		s.Name = "GwVenueSound" .. i
		s.Volume = 0.4
		s.Parent = SoundService
		pool[i] = s
	end
	function C.sound(kind: string, speed: number?, volume: number?)
		if K.settings and K.settings.sound == false then
			return
		end
		poolIdx = poolIdx % #pool + 1
		local s = pool[poolIdx]
		s.SoundId = SOUND_IDS[kind] or SOUND_IDS.tap
		s.PlaybackSpeed = speed or 1
		s.Volume = volume or 0.4
		pcall(function()
			s.TimePosition = 0
			s:Play()
		end)
	end
	-- a chiptune note: semitones above the base pitch (electronicpingshort, pitched)
	function C.note(semi: number, volume: number?)
		C.sound("ping", 0.62 * 2 ^ (semi / 12), volume or 0.22)
	end

	-- character controls (PlayerModule) for modal sessions (PC seat)
	local controlsOff = 0
	function C.controls(enabled: boolean)
		controlsOff += if enabled then -1 else 1
		controlsOff = math.max(0, controlsOff)
		pcall(function()
			local ps = player:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm then
				local controls = (require(pm) :: any):GetControls()
				if controlsOff > 0 then
					controls:Disable()
				else
					controls:Enable()
				end
			end
		end)
	end
	-- HideGwangalliHUD while any venue session overlay is up (refcounted by key)
	local hudKeys: { [string]: boolean } = {}
	function C.hideHud(key: string, on: boolean)
		hudKeys[key] = if on then true else nil
		gui:SetAttribute("HideGwangalliHUD", next(hudKeys) ~= nil or nil)
	end

	-- Sheets: kit BottomSheet (right side on landscape, bottom on portrait) with a scrolling list.
	function C.landscape(): boolean
		return gui.AbsoluteSize.X > gui.AbsoluteSize.Y * 1.25
	end
	function C.sheet(name: string, title: string, subtitle: string?, onClose: (() -> ())?): (any, ScrollingFrame)
		local side = if C.landscape() then "right" else "bottom"
		local sh = K.BottomSheet(gui, {
			name = name,
			title = title,
			subtitle = subtitle or "",
			side = side,
			width = if side == "right" then 0.44 else nil,
			height = if side == "bottom" then 0.62 else nil,
			zIndex = 40,
			onClose = onClose,
		})
		local scroll = K.make("ScrollingFrame", {
			Name = "Scroll",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageTransparency = 0.5,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 42,
		}, sh.content)
		K.list(scroll, false, 8)
		K.pad(scroll, 0, 6, 2, 8)
		return sh, scroll
	end
	function C.row(scroll: Instance, opts: any): any
		local r = K.ListRow(scroll, opts)
		r.row.ZIndex = 42
		for _, d in r.row:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = math.max(d.ZIndex, 43)
			end
		end
		return r
	end
	-- Compact floating label (score pops, PERFECT ...) that fades out; parent = any GuiObject / gui.
	function C.pop(parent: Instance, text: string, color: Color3, pos: UDim2, size: number?, seconds: number?)
		local l = K.text(parent, {
			Name = "Pop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(260, (size or 28) + 8),
			Text = text,
			TextColor3 = color,
			Font = K.Font.heavy,
			TextSize = size or 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.4,
			ZIndex = 60,
		})
		K.tween(l, seconds or 0.9, { Position = pos - UDim2.fromOffset(0, 26), TextTransparency = 1, TextStrokeTransparency = 1 })
		task.delay((seconds or 0.9) + 0.05, function()
			l:Destroy()
		end)
		return l
	end

	function C.poseOf(act: string): any
		local d = POSES[act]
		if d and not d.period then
			local style = string.sub(act, 5)
			d.period = (V.STYLE[style] and V.STYLE[style].period) or 1
		end
		return d
	end

	-------------------------------------------------------------------------------------------
	-- act driver
	-------------------------------------------------------------------------------------------
	type Rec = { model: Model, staff: boolean, player: Player?, act: string?, actT: number, ending: number?, ctl: any, flip: boolean, t1: any, t2: any, applied: string?, moving: number? }
	local recs: { [Model]: Rec } = {}

	local function recFor(model: Model, staff: boolean, pl: Player?): Rec?
		if not Anim then
			return nil
		end
		local r = recs[model]
		if r then
			return r
		end
		local ok, ctl = pcall(Anim.rig, model)
		if not ok or not ctl then
			return nil
		end
		r = { model = model, staff = staff, player = pl, act = nil, actT = 0, ending = nil, ctl = ctl, flip = false, t1 = {}, t2 = {}, applied = nil, moving = nil }
		recs[model] = r
		return r
	end

	local function readPlayerAct(pl: Player)
		local ch = pl.Character
		if not ch then
			return
		end
		local act = pl:GetAttribute(V.Attr.Act)
		if type(act) == "string" and act ~= "" then
			local r = recFor(ch, false, pl)
			if r then
				r.act = act
				r.actT = tonumber(pl:GetAttribute(V.Attr.ActT)) or C.serverNow()
				r.ending = nil
			end
		else
			local r = recs[ch]
			if r and r.act then
				r.act = nil
				r.ending = os.clock()
			end
		end
	end
	local function watchPlayer(pl: Player)
		pl:GetAttributeChangedSignal(V.Attr.Act):Connect(function()
			readPlayerAct(pl)
		end)
		pl:GetAttributeChangedSignal(V.Attr.ActT):Connect(function()
			readPlayerAct(pl)
		end)
		pl.CharacterAdded:Connect(function()
			task.defer(readPlayerAct, pl)
		end)
		readPlayerAct(pl)
	end
	for _, pl in Players:GetPlayers() do
		watchPlayer(pl)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	local function staffAdded(m: Instance)
		if m:IsA("Model") then
			recFor(m, true, nil)
		end
	end
	CollectionService:GetInstanceAddedSignal(V.Tags.Staff):Connect(staffAdded)
	CollectionService:GetInstanceRemovedSignal(V.Tags.Staff):Connect(function(m)
		local r = recs[m :: Model]
		if r then
			pcall(r.ctl.destroy, r.ctl)
			recs[m :: Model] = nil
		end
	end)
	for _, m in CollectionService:GetTagged(V.Tags.Staff) do
		staffAdded(m)
	end

	local function applyStaffAct(r: Rec, act: string)
		local ctl = r.ctl
		r.applied = act
		ctl:pose(nil, 0.3)
		ctl:gesture(nil)
		if string.sub(act, 1, 4) == "gym:" then
			ctl:setAct("idle")
		elseif act == "tray" then
			ctl:setAct("idle")
			ctl:pose("tray", 0.3)
		elseif act == "give" then
			ctl:emote("give")
		elseif act == "walk" then
			ctl:setAct("idle")
		elseif Anim.ACTS[act] then
			ctl:setAct(act)
		else
			ctl:setAct("idle")
		end
	end

	local acc = 0
	local cam = workspace.CurrentCamera
	local function driver(dt: number)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		acc = 0
		cam = workspace.CurrentCamera or cam
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local now = C.serverNow()
		local myRoot = C.root()
		for model, r in recs do
			if not model.Parent then
				if r.staff then
					continue -- streamed out: keep the record (tags re-add on stream-in)
				end
				recs[model] = nil
				continue
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				continue
			end
			local d = (root.Position - camPos).Magnitude
			if d > 110 then
				continue
			end
			local ctl = r.ctl
			if r.staff then
				local act = model:GetAttribute("Act")
				act = if type(act) == "string" then act else "idle"
				if act ~= r.applied then
					applyStaffAct(r, act)
				end
				local mv = model:GetAttribute("Moving")
				local moving = if type(mv) == "number" and mv > 0 then mv else nil
				if moving ~= r.moving then
					r.moving = moving
					ctl:setMoving(moving)
				end
				if string.sub(act, 1, 4) == "gym:" then
					local def = C.poseOf(act)
					if def then
						local ph = (os.clock() / def.period) % 1
						local s = 0.5 - 0.5 * math.cos(ph * 2 * math.pi)
						r.flip = not r.flip
						ctl:pose(lerpPose(def.a, def.b, s, if r.flip then r.t1 else r.t2), 0.05)
					end
				end
				if myRoot and d < 40 and (myRoot.Position - root.Position).Magnitude < 11 and not moving then
					local head = player.Character and player.Character:FindFirstChild("Head")
					ctl:look(if head and head:IsA("BasePart") then head.Position else myRoot.Position)
				else
					ctl:look(nil)
				end
				ctl:setDetail(if d < 45 then 2 else 1)
				ctl:step()
			else
				if r.act then
					local def = C.poseOf(r.act)
					if def then
						local ph = ((now - r.actT) / def.period) % 1
						local s = 0.5 - 0.5 * math.cos(ph * 2 * math.pi)
						r.flip = not r.flip
						ctl:pose(lerpPose(def.a, def.b, s, if r.flip then r.t1 else r.t2), 0.05)
					end
					ctl:step()
				elseif r.ending then
					if os.clock() - r.ending < 0.5 then
						ctl:pose(nil, 0.25)
						ctl:step()
					else
						pcall(ctl.relax, ctl)
						recs[model] = nil
					end
				end
			end
		end
	end

	function C.start()
		RunService.Heartbeat:Connect(function(dt)
			local ok, err = pcall(driver, dt)
			if not ok then
				warn("[GwangalliVenues] act driver: " .. tostring(err))
			end
		end)
	end

	return C
end

return Common
