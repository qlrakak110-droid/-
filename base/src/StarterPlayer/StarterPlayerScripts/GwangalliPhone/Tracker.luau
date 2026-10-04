-- GwangalliPhone/Tracker: the tracked quest's HUD widget, the 3D objective marker and the
-- off-screen edge arrow.
--   * Tracked quest: profile.quests.tracked (server), else the first active quest, unless the player
--     turned tracking off in the 퀘스트 app (local; the next "추적" turns it back on).
--   * Target: the current step's Destination (Dest.position: live part > last seen > MapData, so it
--     works while the part is streamed out), or the nearest client-visible part with the step's tag.
--   * Marker: a BillboardGui (AlwaysOnTop) adorned to an Attachment in workspace.Terrain (client-local,
--     never streamed out) showing the place name and the distance in metres (1 stud = 0.3 m).
--   * Edge arrow when the target is off-screen or behind the camera.
-- The only per-frame work: a Heartbeat hook throttled to 10 Hz, connected only while a target exists.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Data = require(script.Parent:WaitForChild("Data"))
local Dest = require(script.Parent:WaitForChild("Dest"))
local Net = require(script.Parent:WaitForChild("Net"))

local C, F = UI.C, UI.F
local make, frame, label = UI.make, UI.frame, UI.label
local player = Players.LocalPlayer

local Tracker = {}

local ctx: any = nil
local probe: Frame
local widget: Frame
local widgetScale: UIScale
local wTitle: TextLabel
local wStep: TextLabel
local wDist: TextLabel
local wCancel: TextButton? = nil
local wTap: TextButton? = nil
local arrow: Frame
local arrowGlyph: TextLabel
local arrowDist: TextLabel
local billboard: BillboardGui
local anchor: Attachment
local bbName: TextLabel
local bbDist: TextLabel

local hiddenWidget, hiddenWorld = false, false
local manualOff = false
local target: any = nil -- { questId, title, stepText, name, pos, tag, attr, value }
local hb: RBXScriptConnection? = nil
local acc = 0
local lastDistText = ""
local tagRecheck = 0

local function markerEnabled(): boolean
	return ctx == nil or ctx.settings.marker ~= false
end

-- Tracked quest ----------------------------------------------------------------------------------------
function Tracker.trackedId(): string?
	if manualOff then
		return nil
	end
	local q = Net.profile.quests
	local active = Data.activeQuests(q)
	local tracked = type(q) == "table" and q.tracked or nil
	if type(tracked) == "string" and active[tracked] ~= nil then
		return tracked
	end
	-- fallback: first active quest in definition order
	local best, bestOrder = nil, math.huge
	for id in active do
		local def = Data.quest(id)
		local order = def and def.order or 1000
		if order < bestOrder or (order == bestOrder and best and id < best) then
			best, bestOrder = id, order
		end
	end
	return best
end

function Tracker.setManualOff(off: boolean)
	manualOff = off
	Tracker.refresh()
end

function Tracker.isManualOff(): boolean
	return manualOff
end

function Tracker.current(): any
	return target
end

-- Nearest visible instance with a tag (and attribute value) ---------------------------------------------
local function nearestTagged(tag: string, attr: string?, value: any, from: Vector3?): Vector3?
	local best, bestD = nil, math.huge
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(workspace) and (not attr or value == nil or inst:GetAttribute(attr) == value) then
			local p: Vector3? = nil
			if inst:IsA("BasePart") then
				p = inst.Position
			elseif inst:IsA("Model") then
				local ok, cf = pcall(inst.GetPivot, inst)
				p = if ok then cf.Position else nil
			elseif inst:IsA("Attachment") then
				p = inst.WorldPosition
			end
			if p then
				local d = if from then (p - from).Magnitude else 0
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	return best
end

local function rootPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.Focus.Position else nil
end

-- Life-game targets: the current work task (WorkState.task.target) beats the map waypoint (지도 길안내,
-- profile.waypoint), which beats a legacy quest.
local waypoint: any = nil -- Destination name (string) or Vector3, set locally by the 지도 app
local workTarget: any = nil -- { title, text, target }
local suppressWidget = false
local arrowSuppressed = false
local dismissedWp: any = nil -- a profile waypoint the player already reached (until the server clears it)

local function wpKey(wp: any): string
	if type(wp) == "string" then
		return wp
	elseif typeof(wp) == "Vector3" then
		return tostring(wp)
	elseif type(wp) == "table" then
		return tostring(wp.name or wp.destination or wp[1]) .. tostring(wp[3] or "")
	end
	return tostring(wp)
end

function Tracker.setWaypoint(where: any)
	waypoint = where
	manualOff = false
	Tracker.refresh()
end

function Tracker.getWaypoint(): any
	return waypoint
end

function Tracker.setWorkTarget(t: any)
	workTarget = t
	Tracker.refresh()
end

-- the dialog sheet is up: the edge arrow steps aside
function Tracker.setArrowSuppressed(on: boolean)
	arrowSuppressed = on
	if on and arrow then
		arrow.Visible = false
	end
end

-- the shift card replaces the widget while on shift
function Tracker.setWidgetSuppressed(on: boolean)
	suppressWidget = on
	if widget then
		widget.Visible = target ~= nil and not hiddenWidget and not suppressWidget
	end
end

local function pointTarget(title: string, stepText: string, where: any): any
	local t: any = { title = title, stepText = stepText, kind = "point" }
	if typeof(where) == "Vector3" then
		t.pos = where
	elseif type(where) == "table" and tonumber(where[1]) and tonumber(where[3]) then
		t.pos = Vector3.new(tonumber(where[1]) or 0, tonumber(where[2]) or 0, tonumber(where[3]) or 0)
	elseif type(where) == "table" and (typeof(where.pos) == "Vector3" or type(where.name) == "string" or type(where.destination) == "string") then
		if typeof(where.pos) == "Vector3" then
			t.pos = where.pos
		end
		local n = where.name or where.destination
		if type(n) == "string" then
			t.name = Dest.resolve(n)
			t.pos = t.pos or Dest.position(t.name)
		end
	elseif type(where) == "string" and where ~= "" then
		t.name = Dest.resolve(where)
		t.pos = Dest.position(t.name)
		if not t.pos then
			-- a tagged object name (e.g. a counter) visible to the client
			t.tag = where
			t.pos = nearestTagged(where, nil, nil, rootPos())
		end
	end
	if not t.pos then
		return nil
	end
	return t
end

local function resolveTarget(): any
	if workTarget and workTarget.target ~= nil then
		local t = pointTarget(workTarget.title or "근무", workTarget.text or "", workTarget.target)
		if t then
			t.work = true
			return t
		end
	end
	local wp = waypoint
	local pw = Net.profile.waypoint
	if wp == nil and pw ~= nil and pw ~= false and pw ~= "" and wpKey(pw) ~= dismissedWp then
		wp = pw
	end
	if wp ~= nil then
		local label = if type(wp) == "string" then wp elseif type(wp) == "table" and type(wp.name or wp.destination) == "string" then (wp.name or wp.destination) else "목적지"
		local t = pointTarget("🧭 길안내", label, wp)
		if t then
			t.waypoint = true
			return t
		end
	end
	local id = Tracker.trackedId()
	if not id then
		return nil
	end
	local active = Data.activeQuests(Net.profile.quests)
	local prog = active[id]
	local def = Data.quest(id)
	if not def then
		local title = if type(prog) == "table" and type(prog.title) == "string" then prog.title else id
		def = { id = id, title = title, steps = {}, desc = "" }
	end
	local info = Data.progressInfo(def, prog)
	local t = {
		questId = id,
		title = def.title,
		stepText = info.text,
		stepIndex = info.index,
		stepCount = info.total,
	}
	local where = info.where
	-- an explicit Vector3 in the progress table wins
	if type(prog) == "table" and typeof(prog.target) == "Vector3" then
		where = { pos = prog.target }
	end
	if where then
		if where.pos then
			t.pos = where.pos
		end
		if where.tag then
			t.tag, t.attr, t.value = where.tag, where.attr, where.value
			if not where.name then
				t.pos = nearestTagged(where.tag, where.attr, where.value, rootPos())
			end
		end
		if where.name then
			t.name = Dest.resolve(where.name)
			if not t.pos then
				t.pos = Dest.position(t.name)
			end
			if where.tag then
				-- a tagged object near the destination (the counter, the ID check) is more precise
				local near = nearestTagged(where.tag, where.attr, where.value, t.pos or rootPos())
				if near and (not t.pos or (near - t.pos).Magnitude < 120) then
					t.pos = near
				end
			end
		end
	end
	return t
end

-- Loop ---------------------------------------------------------------------------------------------------------
local function update()
	local t = target
	if not t or not t.pos then
		arrow.Visible = false
		return
	end
	local from = rootPos()
	local worldOn = markerEnabled() and not hiddenWorld
	if from then
		local d = (t.pos - from).Magnitude
		local text = if d < 25 then "도착!" else UI.meters(d)
		if d < 25 and t.waypoint then
			-- arrived at a map waypoint: clear it (a work target is cleared by the server's next task)
			if Net.profile.waypoint ~= nil then
				dismissedWp = wpKey(Net.profile.waypoint)
			end
			waypoint = nil
			t.waypoint = false
			task.defer(function()
				if ctx and ctx.Net then
					ctx.Net.send("setWaypoint", { destination = false })
				end
				Tracker.refresh()
			end)
		end
		if text ~= lastDistText then
			lastDistText = text
			wDist.Text = text
			bbDist.Text = text
			arrowDist.Text = text
			wDist.TextColor3 = if d < 25 then C.green else C.yellow
		end
	end
	-- edge arrow
	local cam = workspace.CurrentCamera
	if not worldOn or not cam then
		arrow.Visible = false
		return
	end
	local sp = cam:WorldToScreenPoint(t.pos + Vector3.new(0, 6, 0))
	local area, origin = probe.AbsoluteSize, probe.AbsolutePosition
	local x, y = sp.X - origin.X, sp.Y - origin.Y
	local inView = sp.Z > 0 and x >= 0 and x <= area.X and y >= 0 and y <= area.Y
	if inView then
		arrow.Visible = false
		return
	end
	local cx, cy = area.X / 2, area.Y / 2
	local dx, dy = x - cx, y - cy
	if sp.Z <= 0 then
		dx, dy = -dx, -dy
	end
	if math.abs(dx) + math.abs(dy) < 1e-3 then
		dy = 1
	end
	local margin = 40
	local hw, hh = math.max(1, cx - margin), math.max(1, cy - margin)
	local k = math.min(hw / math.max(math.abs(dx), 1e-6), hh / math.max(math.abs(dy), 1e-6))
	local ax, ay = cx + dx * k, cy + dy * k
	local Layout = ctx and ctx.Layout
	if Layout then
		local z = if UserInputService.TouchEnabled then Layout.zones() else {}
		local col = Layout.rect("rightColumn")
		local function clampZones()
			-- off the thumbstick zone (lower-left), the right column and the jump button
			if z.thumb and ax < z.thumb.x + z.thumb.w + 30 then
				ay = math.min(ay, math.max(margin, z.thumb.y - 34))
			end
			if ax > col.x - 40 then
				ax = col.x - 40
			end
			if z.jump and ay > z.jump.cy - z.jump.r - 40 and ax > z.jump.cx - z.jump.r - 40 then
				ay = z.jump.cy - z.jump.r - 40
			end
		end
		clampZones()
		-- stay off the HUD cards: money chip, clock chip, the tracker / shift card slot
		local avoid = { Layout.rect("topLeftChips"), Layout.rect("topCenter") }
		if (widget and widget.Visible) or suppressWidget then
			local r = Layout.rect("topRight")
			table.insert(avoid, { x = r.x, y = r.y, w = r.w, h = math.min(r.h, if suppressWidget then 110 else 60) })
		end
		for _, r in avoid do
			if ax > r.x - 32 and ax < r.x + r.w + 32 and ay > r.y - 34 and ay < r.y + r.h + 34 then
				local below = r.y + r.h + 36
				local okBelow = below < area.Y - 40 and not (z.jump and below > z.jump.cy - z.jump.r - 40 and ax > z.jump.cx - z.jump.r - 40) and not (z.thumb and ax < z.thumb.x + z.thumb.w + 30 and below > z.thumb.y - 34)
				if okBelow then
					ay = below
				else
					ax = r.x - 36
				end
			end
		end
	end
	arrow.Position = UDim2.fromOffset(math.floor(ax), math.floor(ay))
	arrowGlyph.Rotation = math.deg(math.atan2(dy, dx)) + 90
	arrow.Visible = not arrowSuppressed
end

local function setLoop(on: boolean)
	if on and not hb then
		acc = 1
		hb = RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc < 0.1 then
				return
			end
			acc = 0
			tagRecheck += 0.1
			if tagRecheck >= 5 and target and target.tag then
				tagRecheck = 0
				local home = if target.name then Dest.position(target.name) else nil
				local p = nearestTagged(target.tag, target.attr, target.value, home or rootPos())
				if p and (not home or (p - home).Magnitude < 120) then
					target.pos = p
					anchor.Position = p + Vector3.new(0, 3, 0)
				end
			end
			local ok, err = pcall(update)
			if not ok then
				warn("[GwangalliPhone] marker: " .. tostring(err))
			end
		end)
	elseif not on and hb then
		hb:Disconnect()
		hb = nil
		arrow.Visible = false
	end
end

local function apply()
	local t = target
	local hasQuest = t ~= nil
	widget.Visible = hasQuest and not hiddenWidget and not suppressWidget
	if t then
		UI.setText(wTitle, if t.kind == "point" then tostring(t.title) else "📋 " .. tostring(t.title))
		UI.setText(wStep, t.stepText or "")
		if not t.pos then
			lastDistText = ""
			wDist.Text = ""
		end
		if wCancel then
			wCancel.Visible = t.waypoint == true
			if wTap then
				wTap.Size = if t.waypoint then UDim2.new(1, -48, 1, 0) else UDim2.fromScale(1, 1)
			end
			wDist.Position = if t.waypoint then UDim2.new(1, -52, 0, 12) else UDim2.new(1, -12, 0, 12)
		end
	end
	local worldOn = hasQuest and t.pos ~= nil and markerEnabled() and not hiddenWorld
	if worldOn then
		anchor.Position = t.pos + Vector3.new(0, 3, 0)
		UI.setText(bbName, t.name or t.title or "목표")
	end
	billboard.Enabled = worldOn
	setLoop(hasQuest and t.pos ~= nil and (worldOn or not hiddenWidget))
	if not worldOn then
		arrow.Visible = false
	end
end

function Tracker.refresh()
	if not widget then
		return
	end
	local ok, res = pcall(resolveTarget)
	if not ok then
		warn("[GwangalliPhone] tracker: " .. tostring(res))
		res = nil
	end
	target = res
	lastDistText = ""
	apply()
end

function Tracker.setHidden(widgetHidden: boolean, worldHidden: boolean)
	hiddenWidget, hiddenWorld = widgetHidden, worldHidden
	if widget then
		apply()
	end
end

-- Layout (called by Phone.applyLayout): the widget lives in the GwangalliLayout "topRight" slot (the
-- shift card takes the same slot while on shift).
function Tracker.layout(mode: string, hs: number)
	if not widget or not ctx or not ctx.Layout then
		return
	end
	local Layout = ctx.Layout
	local s = Layout.metrics().s
	widgetScale.Scale = s
	local r = Layout.rect("topRight")
	widget.AnchorPoint = Vector2.new(1, 0)
	widget.Position = UDim2.fromOffset(r.x + r.w, r.y)
	widget.Size = UDim2.fromOffset(math.floor(r.w / s), 56)
	local _ = mode
	local _h = hs
end

-- Init -------------------------------------------------------------------------------------------------------------
function Tracker.init(c: any, hudGui: ScreenGui, hudProbe: Frame)
	ctx = c
	probe = hudProbe
	local K = c.K
	widget = K.frame(hudGui, { Name = "QuestTracker", Size = UDim2.fromOffset(260, 56), BackgroundTransparency = K.GLASS_T, BackgroundColor3 = K.Color.glass, Visible = false, Active = true, ZIndex = 2 })
	widgetScale = make("UIScale", { Scale = 1 }, widget)
	K.corner(widget, K.Radius.md)
	K.stroke(widget, K.Color.cyan, 1, 0.65)
	K.shadow(widget, K.Radius.md, 4, "soft")
	local tap = make("TextButton", { Name = "Tap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3 }, widget)
	wTap = tap
	local icon = K.iconTile(widget, 32, "🧭", K.Color.cyan, true)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.ZIndex = 3
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 3
		end
	end
	wTitle = K.text(widget, { Name = "Title", Position = UDim2.fromOffset(52, 10), Size = UDim2.new(1, -120, 0, 18), Font = K.Font.bold, TextSize = K.Type.caption + 1, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	wStep = K.text(widget, { Name = "Step", Position = UDim2.fromOffset(52, 29), Size = UDim2.new(1, -120, 0, 16), TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	wDist = K.text(widget, { Name = "Distance", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(60, 18), Font = K.Font.bold, TextColor3 = K.Color.cyan, TextSize = K.Type.caption + 1, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
	K.mono(wDist)
	wCancel = make("TextButton", { Name = "CancelGuide", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Text = "✕", TextColor3 = K.Color.sub, TextSize = 13, Font = K.Font.bold, Visible = false, ZIndex = 4 }, widget)
	K.pressable(tap, { scale = 0.98 })
	K.pressable(wCancel, { veil = false, scale = 0.9 })
	tap.Activated:Connect(function()
		local t = target
		if t and t.name then
			c.phone.open("map", { focus = t.name })
		else
			c.phone.open("map")
		end
	end)
	wCancel.Activated:Connect(function()
		waypoint = nil
		if Net.profile.waypoint ~= nil and Net.profile.waypoint ~= false then
			dismissedWp = wpKey(Net.profile.waypoint)
		end
		Net.send("setWaypoint", { destination = false })
		c.K.toast({ kind = "travel", title = "길안내를 종료했어요", silent = true, duration = 2 })
		Tracker.refresh()
	end)

	arrow = frame(hudGui, { Name = "ObjectiveArrow", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(56, 60), Visible = false, ZIndex = 2 })
	local disc = frame(arrow, { Name = "Disc", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 0.35, BackgroundColor3 = C.hud })
	UI.corner(disc, UDim.new(0.5, 0))
	UI.stroke(disc, C.yellow, 1.5, 0.2)
	arrowGlyph = label(disc, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "▲", TextColor3 = C.yellow, TextSize = 18, Font = F.bold, TextXAlignment = Enum.TextXAlignment.Center })
	arrowDist = label(arrow, { Name = "Distance", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(64, 18), Text = "", TextSize = 12, Font = F.bold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4 })

	-- 3D marker
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local old = pg and pg:FindFirstChild("GwangalliQuestMarker")
	if old then
		old:Destroy()
	end
	local oldAnchor = workspace.Terrain:FindFirstChild("GwangalliQuestMarkerAnchor")
	if oldAnchor then
		oldAnchor:Destroy()
	end
	anchor = make("Attachment", { Name = "GwangalliQuestMarkerAnchor" }, workspace.Terrain)
	billboard = make("BillboardGui", {
		Name = "GwangalliQuestMarker",
		Adornee = anchor,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(150, 74),
		StudsOffset = Vector3.new(0, 4, 0),
		MaxDistance = 100000,
		ResetOnSpawn = false,
		Enabled = false,
	})
	local pin = frame(billboard, { Name = "Pin", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 0, BackgroundColor3 = C.yellow })
	UI.corner(pin, UDim.new(0.5, 0))
	UI.stroke(pin, Color3.new(0, 0, 0), 2, 0.3)
	label(pin, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "★", TextColor3 = C.yellowText, TextSize = 18, Font = F.heavy, TextXAlignment = Enum.TextXAlignment.Center })
	bbName = label(billboard, { Name = "Place", Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 20), Text = "", Font = F.bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, TextTruncate = Enum.TextTruncate.AtEnd })
	bbDist = label(billboard, { Name = "Distance", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 18), Text = "", Font = F.bold, TextColor3 = C.yellow, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 })
	billboard.Parent = pg or hudGui

	Net.on("profile", function(changed: any)
		if changed.quests or changed.waypoint then
			Tracker.refresh()
		end
	end)
	Dest.onChanged(Tracker.refresh)
	Data.onLoaded(Tracker.refresh)
	player.CharacterAdded:Connect(function()
		task.delay(1, Tracker.refresh)
	end)
	Tracker.refresh()
end

return Tracker
