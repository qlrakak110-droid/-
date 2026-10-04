-- GwangalliLayout: the SCREEN SLOT CONTRACT shared by every HUD / phone / widget script, so nothing
-- overlaps and nothing lands in a Roblox reserved zone. Client only (on the server every call returns
-- a sane 1280x662 PC layout). Nothing yields; nothing is created at require time (a tiny transparent
-- probe ScreenGui is created on first use).
--
-- COORDINATES: every slot is in the pixel space of a ScreenGui that uses
--     IgnoreGuiInset = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- i.e. (0, 0) is the top-left of the usable area: below the Roblox top bar (58 px) and inside the
-- notch insets. Positions / sizes are offset-only UDim2s for the CURRENT screen, so re-apply them
-- whenever Layout.changed fires (viewport, insets, input type or the jump button moved).
--
--   local Layout = require(ReplicatedStorage.GwangalliLayout)
--   local pos, size, anchor = Layout.slot("topCenter")          -- deviceClass optional
--   Layout.apply(frame, "topCenter")                             -- sets Position / Size / AnchorPoint
--   local r = Layout.rect("rightColumn")                         -- {x, y, w, h} top-left gui px
--   Layout.onChanged(function() ... end)                         -- runs now + on every change
--   Layout.changed:Connect(fn)                                   -- RBXScriptSignal (deferred, coalesced)
--   Layout.deviceClass() -> "phoneL" | "phoneP" | "tablet" | "pc"
--   Layout.metrics(cls?) -> {class, W, H, s, margin, gap, chipH, btn, btnW, btnH, touch,
--                            thumb = {x,y,w,h}?, jump = {x,y,w,h,cx,cy,r}?, ox, oy, screenW, screenH}
--   Layout.zones(cls?) -> {thumb = rect?, jump = circle?}      reserved zones in gui px
--   Layout.refresh()                                             force a re-measure
--
-- SLOTS (name -> what goes there; AnchorPoint returned with the slot):
--   "topLeftChips"   money chip (+ small chips to its right). Top-left under the top bar (the Roblox
--                    menu / chat buttons sit above it, inside the bar). Anchor (0,0). Owner: ui_phone.
--   "topCenter"      clock / date / weather chip. Centred on the screen (clamped between the chips
--                    and the right column). MUST stay non-interactive or tolerate being covered: the
--                    toast stack may slide over it for a few seconds. Anchor (0.5,0). Owner: ui_hud.
--   "topRight"       shift / tracker card (max height = slot height; anchor (1,0), grows down).
--                    Landscape phones: left of the right column, below the toast row. Tablet/PC: the
--                    top-right corner. Owner: ui_phone.
--   "rightColumn"    vertical stack right above Roblox's jump button: 폰, 이동, 달리기 (top to
--                    bottom). Anchor (0.5,1) at the column's bottom centre. Item slots:
--                    "rightColumn.phone" (1), "rightColumn.travel" (2), "rightColumn.sprint" (3),
--                    each anchor (0.5,0.5), size = the button (touch: square btn px, >= 44).
--                    PC: bottom-right corner (no jump button). Owners: phone = ui_phone,
--                    travel / sprint = ui_hud.
--   "bottomCenter"   Now Playing / context banners: between the thumbstick zone and the jump button
--                    (landscape phones), above the thumbstick zone (portrait). Anchor (0.5,1).
--   "sheetRight"     the phone and full-height side sheets: landscape phones right ~42 % x full
--                    usable height (covers the right column + jump: a sheet here is modal, so
--                    disable the character controls while it is open and restore them on close);
--                    portrait: centred; tablet / PC: fixed 360 x 740 logical (x s) on the right.
--                    Anchor (1,0) (phoneL), (0.5,0) (phoneP), (1,0.5) (tablet / pc).
--   "toasts"         toast stack, top, below the top bar: between the money chip and the right column
--                    (landscape phones), full width (portrait), clear of topRight (tablet / PC).
--                    Height = front card + peek of the older cards. Anchor (0.5,0). Owner: ui_phone
--                    (GwangalliUI.Toaster; other scripts push through GwangalliUI.toast()).
--   "dialog"         NPC dialog sheet that keeps the controls usable: right of the thumbstick zone,
--                    above the jump button (landscape phones); top area (portrait); bottom band clear of
--                    both zones (tablet); bottom centre (PC). It covers the right column, so it carries
--                    HideGwangalliHUD while shown. Anchor (1,0) / (0.5,1). Owner: ui_phone.
--
-- Shared ScreenGui convention: a ScreenGui with the attribute HideGwangalliHUD = true that is Enabled
-- (and whose attribute is true) asks the always-on HUD layers (clock chip, 이동 / 달리기, 폰 button,
-- tracker, Now Playing) to step aside.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Layout = {}
Layout.VERSION = 1
Layout.TOPBAR = 58
Layout.MIN_TAP = 44
Layout.SLOTS = { "topLeftChips", "topCenter", "topRight", "rightColumn", "rightColumn.phone", "rightColumn.travel", "rightColumn.sprint", "bottomCenter", "sheetRight", "toasts", "dialog" }

local changedEvent = Instance.new("BindableEvent")
Layout.changed = changedEvent.Event

type Rect = { x: number, y: number, w: number, h: number }
type Env = {
	W: number, -- usable gui area (CoreUISafeInsets)
	H: number,
	ox: number, -- gui origin on the screen (left notch inset, top bar)
	oy: number,
	screenW: number,
	screenH: number,
	touch: boolean,
	jump: Rect?, -- live jump button in gui px (nil -> TouchJump geometry)
}

---------------------------------------------------------------------------------------------------
-- Pure geometry
---------------------------------------------------------------------------------------------------
local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = math.max(0, math.floor(w + 0.5)), h = math.max(0, math.floor(h + 0.5)) }
end

function Layout.classFor(env: Env): string
	if not env.touch then
		return "pc"
	end
	if math.min(env.screenW, env.screenH) <= 500 then
		return if env.W >= env.H then "phoneL" else "phoneP"
	end
	return "tablet"
end

function Layout.scaleFor(cls: string, W: number, H: number): number
	if cls == "pc" then
		return math.clamp(math.min(W / 1280, H / 662), 0.85, 1.3)
	elseif cls == "phoneP" or (cls ~= "phoneL" and H > W) then
		return math.clamp(math.min(W / 360, H / 600), 1, 1.25)
	end
	return math.clamp(math.min(W / 740, H / 302), 1, 1.25)
end

-- All slots for one environment + device class. Returns { [slot] = {rect = Rect, anchor = Vector2} }
-- plus the metrics table.
function Layout.compute(env: Env, clsOverride: string?): ({ [string]: any }, { [string]: any })
	local cls = clsOverride or Layout.classFor(env)
	if cls == "phone" then
		cls = if env.W >= env.H then "phoneL" else "phoneP"
	end
	local W, H = math.max(env.W, 100), math.max(env.H, 100)
	local s = Layout.scaleFor(cls, W, H)
	local touchZones = cls ~= "pc"
	local m = if cls == "pc" then 16 else 8 -- screen margin
	local gap = if cls == "pc" then 10 else 8
	local chipH = math.floor(44 * s + 0.5)

	-- reserved zones (gui px) ---------------------------------------------------------------------
	local thumb: Rect? = nil
	local jump: { [string]: number }? = nil
	if touchZones then
		-- dynamic thumbstick: left 40 % x bottom 60 % of the whole screen
		local tr = env.screenW * 0.4 - env.ox
		local tt = (H + env.oy) * 0.4 - env.oy
		thumb = { x = 0, y = tt, w = tr, h = H - tt }
		local j = env.jump
		local jx, jy, jw, jh
		if j and j.w >= 30 then
			jx, jy, jw, jh = j.x, j.y, j.w, j.h
		else
			local small = math.min(env.screenW, env.screenH) <= 500
			local size = if small then 70 else 120
			jx = W - (size * 1.5 - 10)
			jy = if small then H - size - 20 else H - size * 1.75
			jw, jh = size, size
		end
		local r = math.max(jw, jh) / 2 + 10 -- 10 px finger margin
		jump = { x = jx, y = jy, w = jw, h = jh, cx = jx + jw / 2, cy = jy + jh / 2, r = r }
	end

	local slots: { [string]: any } = {}
	local function put(name: string, r: Rect, ax: number, ay: number)
		slots[name] = { rect = r, anchor = Vector2.new(ax, ay) }
	end

	-- right column (폰 / 이동 / 달리기) -------------------------------------------------------------
	local btn, btnW, btnH
	local colX, colBottom -- centre x, bottom y
	if cls == "pc" then
		btnW, btnH = math.floor(84 * s + 0.5), math.floor(60 * s + 0.5)
		btn = btnH
		colX = W - m - btnW / 2
		colBottom = H - m
	else
		assert(jump)
		local top = m + 4
		local bottom = jump.cy - jump.r - 6
		local avail = bottom - top
		local cap = math.floor(60 * s + 0.5)
		btn = math.clamp(math.floor((avail - 2 * gap) / 3), 44, cap)
		btnW, btnH = btn, btn
		colX = math.clamp(jump.cx, btn / 2 + m, W - btn / 2 - m)
		colBottom = bottom
		if cls == "phoneP" then
			-- tall screen: keep the column compact right above the jump button
			btn = math.min(btn, math.floor(56 * s + 0.5))
			btnW, btnH = btn, btn
		end
	end
	local colH = 3 * btnH + 2 * gap
	local colRect = rect(colX - btnW / 2, colBottom - colH, btnW, colH)
	put("rightColumn", colRect, 0.5, 1)
	for i, id in { "phone", "travel", "sprint" } do
		local cy = colRect.y + (i - 1) * (btnH + gap) + btnH / 2
		put("rightColumn." .. id, rect(colX - btnW / 2, cy - btnH / 2, btnW, btnH), 0.5, 0.5)
	end
	local colLeft = colRect.x

	-- top row --------------------------------------------------------------------------------------
	local centerW = math.floor((if cls == "pc" then 240 elseif cls == "tablet" then 220 else 200) * s + 0.5)
	local leftW = math.floor((if cls == "pc" then 230 else 200) * s + 0.5)
	local rightLimit = if cls == "phoneL" or cls == "phoneP" then colLeft - gap else W - m
	if cls == "phoneP" then
		rightLimit = W - m -- portrait: the column sits low, far below the top row
	end
	-- the chips must leave room for the centred clock
	leftW = math.max(120, math.min(leftW, math.floor(W / 2 - centerW / 2 - m - gap)))
	local leftRect = rect(m, m, leftW, chipH)
	put("topLeftChips", leftRect, 0, 0)
	local cx = math.clamp(W / 2, leftRect.x + leftRect.w + gap + centerW / 2, math.max(leftRect.x + leftRect.w + gap + centerW / 2, rightLimit - centerW / 2))
	local centerRect = rect(cx - centerW / 2, m, centerW, chipH)
	put("topCenter", centerRect, 0.5, 0)

	-- toasts ---------------------------------------------------------------------------------------
	local toastH = math.floor(52 * s + 0.5)
	local peek = 2 * math.floor(5 * s + 0.5)
	local toastRect: Rect
	local trackerRect: Rect
	local trackerW = math.floor((if cls == "pc" then 300 elseif cls == "tablet" then 280 else 260) * s + 0.5)
	if cls == "phoneL" then
		local x0 = leftRect.x + leftRect.w + gap
		local x1 = colLeft - gap
		local tw = math.min(math.floor(360 * s), x1 - x0)
		toastRect = rect(x0 + (x1 - x0 - tw) / 2, m, tw, toastH + peek)
		-- tracker: below the toast row, left of the column, right of the thumbstick zone
		local ty = m + toastH + peek + 4
		local tx0 = if thumb then thumb.x + thumb.w + gap else m
		local tw2 = math.min(trackerW, x1 - tx0)
		trackerRect = rect(x1 - tw2, ty, tw2, 0) -- height filled in below
	elseif cls == "phoneP" then
		toastRect = rect(m, m, W - 2 * m, toastH + peek)
		local ty = m + chipH + gap
		trackerRect = rect(W - m - math.min(trackerW, W - 2 * m), ty, math.min(trackerW, W - 2 * m), 0)
	else
		trackerRect = rect(W - m - trackerW, m, trackerW, 0)
		local x0 = leftRect.x + leftRect.w + gap
		local x1 = trackerRect.x - gap
		local tw = math.min(math.floor(380 * s), x1 - x0)
		local tcx = math.clamp(W / 2, x0 + tw / 2, x1 - tw / 2)
		toastRect = rect(tcx - tw / 2, m, tw, toastH + peek)
	end
	put("toasts", toastRect, 0.5, 0)

	-- bottom centre --------------------------------------------------------------------------------
	local bcH = math.floor(60 * s + 0.5)
	local bcRect: Rect
	if cls == "pc" then
		local w = math.min(math.floor(420 * s), W - 2 * m - 2 * (btnW + gap))
		bcRect = rect(W / 2 - w / 2, H - m - bcH, w, bcH)
	else
		assert(thumb and jump)
		local x0 = thumb.x + thumb.w + gap
		local x1 = math.min(jump.cx - jump.r, colLeft) - gap
		local cap = math.floor(380 * s)
		if x1 - x0 >= 220 then
			local w = math.min(cap, x1 - x0)
			bcRect = rect(x0 + (x1 - x0 - w) / 2, H - m - bcH, w, bcH)
		else
			-- narrow (portrait): above the thumbstick zone, left of the column
			local r1 = colLeft - gap
			local w = math.min(cap, r1 - m)
			bcRect = rect(m, thumb.y - gap - bcH, w, bcH)
		end
	end
	put("bottomCenter", bcRect, 0.5, 1)

	-- tracker height: down to the bottom-centre band (phones) / the column (tablet) --------------
	do
		local maxBottom
		if cls == "phoneL" then
			maxBottom = bcRect.y - gap
		elseif cls == "phoneP" then
			maxBottom = math.min((if thumb then thumb.y else H), bcRect.y) - gap
		elseif cls == "tablet" then
			maxBottom = math.min(colRect.y, bcRect.y) - gap
		else
			maxBottom = math.min(H * 0.6, colRect.y - gap)
		end
		trackerRect.h = math.max(0, math.floor(math.min(maxBottom - trackerRect.y, 200 * s)))
	end
	put("topRight", trackerRect, 1, 0)

	-- sheet right ----------------------------------------------------------------------------------
	local sheet: Rect
	if cls == "phoneL" then
		local w = math.clamp(math.floor(W * 0.42), 280, 440)
		w = math.min(w, W - 2 * m)
		sheet = rect(W - 6 - w, 6, w, H - 12)
		put("sheetRight", sheet, 1, 0)
	elseif cls == "phoneP" then
		local w = math.min(W - 24, 420)
		sheet = rect(W / 2 - w / 2, 6, w, H - 12)
		put("sheetRight", sheet, 0.5, 0)
	else
		local ps = if cls == "tablet" then math.clamp(H / 780, 1, 1.25) else math.clamp((H - 40) / 800, 0.8, 1.3)
		local lw = 360
		local lh = math.min(740, math.floor((H - 24) / ps))
		local w, h = lw * ps, lh * ps
		sheet = rect(W - 24 - w, H / 2 - h / 2, w, h)
		put("sheetRight", sheet, 1, 0.5)
	end

	-- dialog (controls stay usable) -------------------------------------------------------------
	local dlg: Rect
	if cls == "phoneL" then
		assert(thumb and jump)
		local x0 = thumb.x + thumb.w + gap
		local x1 = W - m
		local w = math.min(x1 - x0, math.floor(480 * s))
		local bottom = jump.cy - jump.r - gap
		dlg = rect(x1 - w, m, w, bottom - m)
		put("dialog", dlg, 1, 0)
	elseif cls == "phoneP" then
		assert(thumb)
		local top = m + chipH + gap
		dlg = rect(m, top, W - 2 * m, math.max(180, thumb.y - gap - top))
		put("dialog", dlg, 0.5, 0)
	elseif cls == "tablet" then
		assert(thumb and jump)
		local x0 = thumb.x + thumb.w + gap
		local x1 = jump.cx - jump.r - gap
		local w = math.min(x1 - x0, math.floor(560 * s))
		local h = math.floor(210 * s)
		dlg = rect(x0 + (x1 - x0 - w) / 2, bcRect.y - gap - h, w, h)
		put("dialog", dlg, 0.5, 1)
	else
		local w = math.min(math.floor(620 * s), W - 2 * m - 2 * (btnW + gap))
		local h = math.floor(200 * s)
		dlg = rect(W / 2 - w / 2, bcRect.y - gap - h, w, h)
		put("dialog", dlg, 0.5, 1)
	end

	local metrics = {
		class = cls,
		W = W,
		H = H,
		s = s,
		margin = m,
		gap = gap,
		chipH = chipH,
		toastH = toastH,
		btn = btn,
		btnW = btnW,
		btnH = btnH,
		touch = touchZones,
		thumb = thumb,
		jump = jump,
		ox = env.ox,
		oy = env.oy,
		screenW = env.screenW,
		screenH = env.screenH,
	}
	return slots, metrics
end

---------------------------------------------------------------------------------------------------
-- Live environment (client)
---------------------------------------------------------------------------------------------------
local isClient = RunService:IsClient()
local probeGui: ScreenGui? = nil
local probe: Frame? = nil
local cache: { [string]: any } = {}
local cacheKey = ""
local lastEnv: Env? = nil
local watching = false
local pendingFire = false

local function playerGui(): Instance?
	local lp = Players.LocalPlayer
	return lp and lp:FindFirstChildOfClass("PlayerGui")
end

local function ensureProbe()
	if probe and probe.Parent and probeGui and probeGui.Parent then
		return
	end
	local pg = playerGui()
	if not pg then
		return
	end
	local g = pg:FindFirstChild("GwangalliLayoutProbe")
	if not (g and g:IsA("ScreenGui")) then
		g = Instance.new("ScreenGui")
		g.Name = "GwangalliLayoutProbe"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = false
		pcall(function()
			(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end)
		g.DisplayOrder = -100
		g.Parent = pg
	end
	local f = g:FindFirstChild("Probe")
	if not (f and f:IsA("Frame")) then
		f = Instance.new("Frame")
		f.Name = "Probe"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.Active = false
		f.Parent = g
	end
	probeGui = g :: ScreenGui
	probe = f :: Frame
end

local function wantTouch(): boolean
	local ok, v = pcall(function()
		local pref = (UserInputService :: any).PreferredInput
		if pref ~= nil then
			return pref == (Enum :: any).PreferredInput.Touch
		end
		return nil
	end)
	if ok and v ~= nil then
		return v
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function jumpButton(): GuiObject?
	local pg = playerGui()
	local tg = pg and pg:FindFirstChild("TouchGui")
	local fr = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = fr and fr:FindFirstChild("JumpButton")
	if jb and jb:IsA("GuiObject") then
		return jb
	end
	return nil
end

local function measure(): Env
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local insetY = Layout.TOPBAR
	pcall(function()
		insetY = GuiService:GetGuiInset().Y
	end)
	local W, H, ox = vp.X, math.max(1, vp.Y - insetY), 0
	ensureProbe()
	if probe then
		local size = probe.AbsoluteSize
		if size.X >= 50 and size.Y >= 50 then
			W, H = size.X, size.Y
			ox = math.max(0, probe.AbsolutePosition.X)
		end
	end
	local touch = wantTouch()
	local jump: Rect? = nil
	local jb = if touch then jumpButton() else nil
	if jb and probe then
		local s = jb.AbsoluteSize
		local p = jb.AbsolutePosition - probe.AbsolutePosition
		-- sanity: a real bottom-right button, not a zero-size / off-screen placeholder
		if jb.Visible and s.X >= 30 and s.Y >= 30 and p.X > W * 0.5 and p.Y > H * 0.3 and p.X + s.X <= W + 60 and p.Y + s.Y <= H + 60 then
			jump = { x = p.X, y = p.Y, w = s.X, h = s.Y }
		end
	end
	return {
		W = W,
		H = H,
		ox = ox,
		oy = insetY,
		screenW = math.max(vp.X, W + 2 * ox),
		screenH = math.max(vp.Y, H + insetY),
		touch = touch,
		jump = jump,
	}
end

local function envKey(e: Env): string
	local j = e.jump
	return string.format("%d,%d,%d,%d,%d,%d,%s,%s", e.W, e.H, e.ox, e.oy, e.screenW, e.screenH, tostring(e.touch), if j then string.format("%d,%d,%d,%d", j.x, j.y, j.w, j.h) else "-")
end

local function fireChanged()
	if pendingFire then
		return
	end
	pendingFire = true
	task.defer(function()
		pendingFire = false
		changedEvent:Fire()
	end)
end

local function refresh(): boolean
	local env: Env
	if isClient then
		env = measure()
	else
		env = { W = 1280, H = 662, ox = 0, oy = 58, screenW = 1280, screenH = 720, touch = false }
	end
	local key = envKey(env)
	lastEnv = env
	if key ~= cacheKey then
		cacheKey = key
		cache = {}
		return true
	end
	return false
end

local function watch()
	if watching or not isClient then
		return
	end
	watching = true
	local function check()
		if refresh() then
			fireChanged()
		end
	end
	local camConn: RBXScriptConnection? = nil
	local function hookCamera()
		if camConn then
			camConn:Disconnect()
		end
		local cam = workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(check)
		end
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCamera()
		check()
	end)
	pcall(function()
		UserInputService.LastInputTypeChanged:Connect(check)
	end)
	pcall(function()
		(UserInputService :: any):GetPropertyChangedSignal("PreferredInput"):Connect(check)
	end)
	ensureProbe()
	if probe then
		probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(check)
		probe:GetPropertyChangedSignal("AbsolutePosition"):Connect(check)
	end
	-- the TouchGui / jump button can appear or move after start-up: cheap 2 s fingerprint check
	task.spawn(function()
		local last = ""
		while true do
			task.wait(2)
			local jb = jumpButton()
			local fp = "none"
			if jb then
				local p, s = jb.AbsolutePosition, jb.AbsoluteSize
				fp = string.format("%d,%d,%d,%d,%s", p.X, p.Y, s.X, s.Y, tostring(jb.Visible))
			end
			if fp ~= last then
				last = fp
				check()
			end
		end
	end)
end

local function current(cls: string?): ({ [string]: any }, { [string]: any })
	if not lastEnv then
		refresh()
		watch()
	end
	local key = cls or "auto"
	local hit = cache[key]
	if not hit then
		local env = lastEnv :: Env
		local slots, metrics = Layout.compute(env, cls)
		hit = { slots = slots, metrics = metrics }
		cache[key] = hit
	end
	return hit.slots, hit.metrics
end

---------------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------------
function Layout.refresh()
	if refresh() then
		fireChanged()
	end
end

function Layout.deviceClass(): string
	local _, m = current(nil)
	return m.class
end

function Layout.metrics(cls: string?): { [string]: any }
	local _, m = current(cls)
	return m
end

function Layout.zones(cls: string?): { [string]: any }
	local _, m = current(cls)
	return { thumb = m.thumb, jump = m.jump }
end

function Layout.rect(name: string, cls: string?): Rect
	local slots = current(cls)
	local sl = slots[name]
	if not sl then
		warn("[GwangalliLayout] unknown slot " .. tostring(name))
		return { x = 0, y = 0, w = 0, h = 0 }
	end
	local r = sl.rect
	return { x = r.x, y = r.y, w = r.w, h = r.h }
end

-- -> Position, Size, AnchorPoint (offset-only, for the current screen)
function Layout.slot(name: string, cls: string?): (UDim2, UDim2, Vector2)
	local slots = current(cls)
	local sl = slots[name]
	if not sl then
		warn("[GwangalliLayout] unknown slot " .. tostring(name))
		return UDim2.new(), UDim2.new(), Vector2.zero
	end
	local r, a = sl.rect, sl.anchor
	return UDim2.fromOffset(r.x + r.w * a.X, r.y + r.h * a.Y), UDim2.fromOffset(r.w, r.h), a
end

function Layout.apply(gui: GuiObject, name: string, cls: string?)
	local pos, size, anchor = Layout.slot(name, cls)
	gui.AnchorPoint = anchor
	gui.Position = pos
	gui.Size = size
end

-- Runs fn now and after every change. Returns the connection.
function Layout.onChanged(fn: () -> ()): RBXScriptConnection
	local conn = Layout.changed:Connect(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[GwangalliLayout] listener: " .. tostring(err))
		end
	end)
	current(nil)
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[GwangalliLayout] listener: " .. tostring(err))
		end
	end)
	return conn
end

-- Point-in-zone helpers (gui px) for scripts that place dynamic things (e.g. drag targets).
function Layout.inThumbZone(x: number, y: number, cls: string?): boolean
	local z = Layout.zones(cls).thumb
	return z ~= nil and x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h
end

function Layout.rectHitsZones(r: Rect, cls: string?): boolean
	local z = Layout.zones(cls)
	if z.thumb then
		local t = z.thumb
		if r.x < t.x + t.w and r.x + r.w > t.x and r.y < t.y + t.h and r.y + r.h > t.y then
			return true
		end
	end
	if z.jump then
		local j = z.jump
		local nx = math.clamp(j.cx, r.x, r.x + r.w)
		local ny = math.clamp(j.cy, r.y, r.y + r.h)
		if (j.cx - nx) ^ 2 + (j.cy - ny) ^ 2 < j.r * j.r then
			return true
		end
	end
	return false
end

return Layout
