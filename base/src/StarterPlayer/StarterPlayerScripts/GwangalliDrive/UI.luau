-- GwangalliDrive/UI: driving HUD + "차 부르기" sheet, built only from ReplicatedStorage.GwangalliUI
-- (the kit) and placed with ReplicatedStorage.GwangalliLayout metrics.
--
-- Driving HUD (ScreenGui "GwangalliDriveUI", HideGwangalliHUD = true while shown, so the always-on
-- HUD steps aside; the character controls are disabled by Drive, which also hides Roblox's
-- thumbstick and jump button):
--   touch    steer pad bottom-left (drag or hold the ◀ ▶ ends), 브레이크 + 가속 pedals bottom-right
--            (big, where the jump button was), 사이드 (handbrake, hold) left of the pedals, 시점 and
--            경적 above the pedals, 라이트 + 라디오 + 내리기 top-right, speedometer bottom-centre
--            (model name, or the radio's now-playing while it is on), "차 뒤집기" in the centre when
--            the car lies on its side
--   PC       speedometer, key hint chip, 시점 / 라이트 / 라디오 / 내리기 buttons bottom-right
--   passenger 내리기 + 시점 + 라디오 + speedometer only
-- 차 부르기 sheet (ScreenGui "GwangalliCallCar", slot sheetRight): the player's OWN / rented cars
-- (colour tile, plate, condition bar, 부르기 / 견인 / 정비소), the called car's status and 돌려보내기,
-- "정비소에서 구매" when the player owns nothing; the six free kinds only for admins / dev switch.
-- Condition gauge: a chip on top of the speedometer for owned cars (DriveCondition), 견인 부르기 when the
-- engine is dead.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = {}

local player = Players.LocalPlayer
local K: any = nil
local Layout: any = nil
local VS: any = nil
local Input: any = nil
local Ctx: any = nil -- the drive client context (Api, GS when the garage module is present)

local handlers: { [string]: (...any) -> () } = {}
function UI.on(name: string, fn: (...any) -> ())
	handlers[name] = fn
end
local function emit(name: string, ...: any)
	local f = handlers[name]
	if f then
		task.spawn(f, ...)
	end
end

local E: any = {} -- elements
local S: any = { shown = false, role = "driver", lights = false, flip = false, camLabel = "3인칭", sheetOpen = false }
UI.elements = E
UI.state = S

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local function round(x: number): number
	return math.floor(x + 0.5)
end

local function place(g: GuiObject, r: { [string]: number })
	g.AnchorPoint = Vector2.zero
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

local function rect(x: number, y: number, w: number, h: number): { [string]: number }
	return { x = round(x), y = round(y), w = round(w), h = round(h) }
end

-- A hold button (pedal / handbrake / horn): calls onHold(true/false); multi-touch safe (each
-- button tracks its own InputObject and releases on the global end of that touch).
local held: { [InputObject]: (boolean) -> () } = {}
local function holdable(b: GuiButton, onHold: (boolean) -> ())
	local active: InputObject? = nil
	b.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			if active then
				return
			end
			active = input
			held[input] = function(on: boolean)
				if not on then
					active = nil
				end
				onHold(on)
			end
			onHold(true)
		end
	end)
	b.InputEnded:Connect(function(input: InputObject)
		local f = held[input]
		if f then
			held[input] = nil
			f(false)
		end
	end)
end
UserInputService.InputEnded:Connect(function(input: InputObject)
	local f = held[input]
	if f then
		held[input] = nil
		f(false)
	end
end)

local function caption(parent: Instance, text: string, glyph: string, size: number, color: Color3?)
	local g = K.text(parent, {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, 0, 0.5, 0),
		Text = glyph,
		TextSize = size,
		Font = K.Font.heavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color or K.Color.text,
		ZIndex = 4,
	})
	local c = K.text(parent, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -6, 0, 16),
		Text = text,
		TextSize = K.Type.caption,
		Font = K.Font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color or K.Color.text,
		ZIndex = 4,
	})
	return g, c
end

local function roundButton(parent: Instance, name: string, glyph: string, label: string): TextButton
	local b = K.Button(parent, { name = name, text = "", style = "glass", size = UDim2.fromOffset(50, 50), zIndex = 3 })
	K.corner(b, UDim.new(0.5, 0))
	local g, c = caption(b, label, glyph, 18)
	g.Position = UDim2.fromScale(0.5, 0.38)
	c.TextSize = K.Type.micro
	c.Position = UDim2.new(0.5, 0, 1, -4)
	return b
end

---------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------
function UI.build(ctx: any)
	K, Layout, VS, Input = ctx.K, ctx.Layout, ctx.VS, ctx.Input
	Ctx = ctx
	local pg = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "GwangalliDriveUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 12
	gui.Enabled = false
	gui:SetAttribute("HideGwangalliHUD", false)
	E.gui = gui

	-- steer pad ---------------------------------------------------------------------------------------
	local pad = K.frame(gui, { Name = "SteerPad", Active = true, BackgroundTransparency = K.GLASS_T, BackgroundColor3 = K.Color.glass, ZIndex = 2 })
	K.corner(pad, UDim.new(0.5, 0))
	K.stroke(pad, nil, 1, 0.8)
	local left = K.text(pad, { Name = "Left", Text = "◀", Font = K.Font.heavy, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0.28, 0, 1, 0), TextColor3 = K.Color.sub, ZIndex = 3 })
	local right = K.text(pad, { Name = "Right", Text = "▶", Font = K.Font.heavy, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.28, 0, 1, 0), TextColor3 = K.Color.sub, ZIndex = 3 })
	K.text(pad, { Name = "Hint", Text = "핸들", Font = K.Font.bold, TextSize = K.Type.micro, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0.4, 0, 0, 14), TextColor3 = K.Color.faint, ZIndex = 3 })
	local knob = K.frame(pad, { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 0.08, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4 })
	K.corner(knob, UDim.new(0.5, 0))
	K.gradient(knob, K.Grad.primary, 90)
	E.pad, E.knob, E.padLeft, E.padRight = pad, knob, left, right
	local steerInput: InputObject? = nil
	local function steerFrom(pos: Vector3)
		local ax, aw = pad.AbsolutePosition.X, pad.AbsoluteSize.X
		local half = math.max(1, aw / 2)
		local dx = (pos.X - (ax + half)) / (half * 0.72)
		local v = math.clamp(dx, -1, 1)
		if math.abs(v) < 0.08 then
			v = 0
		end
		Input.touch.steer = v
		knob.Position = UDim2.new(0.5 + v * 0.36, 0, 0.56, 0)
		left.TextColor3 = if v < -0.05 then K.Color.cyan else K.Color.sub
		right.TextColor3 = if v > 0.05 then K.Color.cyan else K.Color.sub
	end
	local function steerRelease()
		steerInput = nil
		Input.touch.steer = 0
		knob.Position = UDim2.fromScale(0.5, 0.56)
		left.TextColor3 = K.Color.sub
		right.TextColor3 = K.Color.sub
	end
	pad.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) and not steerInput then
			steerInput = input
			steerFrom(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local si = steerInput
		if si and (input == si or (si.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
			steerFrom(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local si = steerInput
		if si and (input == si or (si.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			steerRelease()
		end
	end)
	E.steerRelease = steerRelease

	-- pedals ----------------------------------------------------------------------------------------------
	local gas = K.Button(gui, { name = "Gas", text = "", style = "success", size = UDim2.fromOffset(74, 112), zIndex = 3, sound = false, radius = K.Radius.lg })
	caption(gas, "가속", "▲", 26, K.Color.onAccent)
	holdable(gas, function(on)
		Input.touch.throttle = if on then 1 else 0
	end)
	local brake = K.Button(gui, { name = "Brake", text = "", style = "destructive", size = UDim2.fromOffset(74, 112), zIndex = 3, sound = false, radius = K.Radius.lg })
	caption(brake, "브레이크", "▼", 26)
	holdable(brake, function(on)
		Input.touch.brake = if on then 1 else 0
	end)
	local hb = K.Button(gui, { name = "Handbrake", text = "", style = "secondary", size = UDim2.fromOffset(60, 76), zIndex = 3, sound = false, radius = K.Radius.md })
	caption(hb, "사이드", "P", 22, K.Color.gold)
	holdable(hb, function(on)
		Input.touch.handbrake = on
		hb.BackgroundColor3 = if on then Color3.fromRGB(70, 56, 20) else K.Color.card2
	end)
	E.gas, E.brake, E.handbrake = gas, brake, hb

	local horn = roundButton(gui, "Horn", "📯", "경적")
	holdable(horn, function(on)
		Input.touch.horn = on
	end)
	local cam = roundButton(gui, "Camera", "🎥", "시점")
	cam.Activated:Connect(function()
		emit("camera")
	end)
	local lights = roundButton(gui, "Lights", "💡", "라이트")
	lights.Activated:Connect(function()
		emit("lights")
	end)
	local radio = roundButton(gui, "Radio", "📻", "라디오")
	radio.Activated:Connect(function()
		emit("radio")
	end)
	E.horn, E.camera, E.lights, E.radio = horn, cam, lights, radio

	local exit = K.Button(gui, { name = "Exit", text = "내리기", icon = "🚪", style = "glass", size = UDim2.fromOffset(108, 44), zIndex = 3, radius = K.Radius.pill })
	exit.Activated:Connect(function()
		emit("exit")
	end)
	E.exit = exit

	local flip = K.Button(gui, { name = "Flip", text = "차 뒤집기", icon = "↻", style = "gold", size = UDim2.fromOffset(150, 46), zIndex = 5, radius = K.Radius.pill })
	flip.Visible = false
	flip.Activated:Connect(function()
		emit("flip")
	end)
	E.flip = flip

	-- speedometer --------------------------------------------------------------------------------------
	local sp = K.Panel(gui, { Name = "Speedo", Size = UDim2.fromOffset(150, 62), Radius = K.Radius.lg })
	sp.Active = false
	local value = K.text(sp, { Name = "Speed", Text = "0", Font = K.Font.heavy, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(0.5, -8, 0, 36), ZIndex = 3 })
	K.mono(value)
	local unit = K.text(sp, { Name = "Unit", Text = "km/h", TextSize = K.Type.micro, Font = K.Font.bold, TextColor3 = K.Color.sub, Position = UDim2.new(0.5, 4, 0, 18), Size = UDim2.new(0, 30, 0, 14), ZIndex = 3 })
	local gear = K.text(sp, { Name = "Gear", Text = "P", Font = K.Font.heavy, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 9), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card2, ZIndex = 3 })
	K.corner(gear, UDim.new(0.5, 0))
	local bar = K.ProgressBar(sp, { height = 4, color = K.Color.cyan })
	bar.frame.AnchorPoint = Vector2.new(0.5, 1)
	bar.frame.Position = UDim2.new(0.5, 0, 1, -8)
	bar.frame.Size = UDim2.new(1, -20, 0, 4)
	bar.frame.ZIndex = 3
	local model = K.text(sp, { Name = "Model", Text = "", TextSize = K.Type.micro, Font = K.Font.medium, TextColor3 = K.Color.faint, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.5, 4, 0, 34), Size = UDim2.new(0.5, -14, 0, 13), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	E.speedo, E.speedValue, E.speedUnit, E.gear, E.bar, E.model = sp, value, unit, gear, bar, model

	-- condition gauge: a slim chip riding on top of the speedometer (owned cars only)
	local cond = K.frame(sp, { Name = "Condition", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -4), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = K.GLASS_T, BackgroundColor3 = K.Color.glass, ZIndex = 3, Visible = false })
	K.corner(cond, UDim.new(0.5, 0))
	K.stroke(cond, nil, 1, 0.86)
	local condText = K.text(cond, { Name = "Text", Text = "", Font = K.Font.bold, TextSize = K.Type.micro, Position = UDim2.fromOffset(10, 1), Size = UDim2.new(1, -20, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local condTrack = K.frame(cond, { Name = "Track", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -20, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, ZIndex = 4 })
	K.corner(condTrack, UDim.new(0.5, 0))
	local condFill = K.frame(condTrack, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = K.Color.green, ZIndex = 5 })
	K.corner(condFill, UDim.new(0.5, 0))
	E.cond, E.condText, E.condFill = cond, condText, condFill
	-- engine dead: tow straight from the driver's seat
	local tow = K.Button(gui, { name = "Tow", text = "견인 부르기", icon = "🚛", style = "gold", size = UDim2.fromOffset(150, 56), zIndex = 5, radius = K.Radius.pill })
	tow.Visible = false
	tow.Activated:Connect(function()
		local id = S.car and S.car:GetAttribute(VS.Attr.CarId)
		if Ctx and Ctx.Api and type(id) == "string" then
			task.spawn(Ctx.Api.tow, id)
		end
	end)
	E.tow = tow

	-- PC key hint ------------------------------------------------------------------------------------------
	local hint = K.Panel(gui, { Name = "KeyHint", Size = UDim2.fromOffset(420, 44), Radius = K.Radius.pill })
	hint.Active = false
	K.text(hint, { Name = "Text", Text = "W/S 가속·브레이크   A/D 핸들   Space 사이드   H 경적   V 시점   L 라이트   T 라디오   F 내리기", TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	E.hint = hint

	gui.Parent = pg
	UI.buildSheet(pg)
	Layout.onChanged(function()
		UI.layout()
		UI.layoutSheet()
	end)
end

---------------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------------
-- Pure: element rects for a device class / usable size / scale.
function UI.compute(cls: string, W: number, H: number, s: number, role: string): { [string]: any }
	local r: { [string]: any } = {}
	local m = if cls == "pc" then 16 else 10
	local gap = 8
	if cls == "pc" then
		local bw, bh = round(118 * s), 44
		r.exit = rect(W - m - bw, H - m - bh, bw, bh)
		r.radio = rect(r.exit.x - gap - bw, r.exit.y, bw, bh)
		r.lights = rect(r.radio.x - gap - bw, r.exit.y, bw, bh)
		r.camera = rect(r.lights.x - gap - bw, r.exit.y, bw, bh)
		local sw, sh = round(176 * s), round(66 * s)
		r.speedo = rect(W / 2 - sw / 2, H - m - sh, sw, sh)
		local hw = math.min(round(560 * s), r.speedo.x - 2 * m)
		r.hint = rect(m, H - m - 44, hw, 44)
		r.flip = rect(W / 2 - 90, H * 0.42, 180, 48)
		r.tow = rect(W - m - 170, r.exit.y - gap - 56, 170, 56)
		return r
	end
	local portrait = H > W
	local bs = math.max(46, round(50 * s))
	local eh = math.max(44, round(44 * s))
	r.exit = rect(W - m - round(108 * s), m, round(108 * s), eh)
	r.lights = rect(r.exit.x - gap - eh, m, eh, eh)
	r.radio = rect(r.lights.x - gap - eh, m, eh, eh)
	r.flip = rect(W / 2 - round(75 * s), H * 0.42, round(150 * s), math.max(44, round(46 * s)))
	r.tow = rect(r.radio.x - gap - 150, m, 150, 56)
	local sw, sh = round(148 * s), round(62 * s)
	if role ~= "driver" then
		r.camera = rect(W - m - bs, H - m - bs, bs, bs)
		r.speedo = rect(W / 2 - sw / 2, H - m - sh, sw, sh)
		return r
	end
	local pw, ph = round((if portrait then 68 else 74) * s), round(112 * s)
	r.gas = rect(W - m - pw, H - m - ph, pw, ph)
	r.brake = rect(r.gas.x - gap - pw, r.gas.y, pw, ph)
	local hw, hh = round((if portrait then 54 else 60) * s), round(76 * s)
	r.handbrake = rect(r.brake.x - gap - hw, H - m - hh, hw, hh)
	r.camera = rect(r.brake.x + (pw - bs) / 2, r.gas.y - gap - bs, bs, bs)
	r.horn = rect(r.gas.x + (pw - bs) / 2, r.gas.y - gap - bs, bs, bs)
	local padH = round(92 * s)
	-- the steer pad takes what is left of the bottom row (never under the handbrake)
	local padMax = r.handbrake.x - gap - m
	local padW = if portrait then math.min(round(W * 0.42), round(250 * s), padMax) else math.min(round(250 * s), round(W * 0.34), padMax)
	padW = math.max(96, padW)
	r.pad = rect(m, H - m - padH, padW, padH)
	if portrait then
		r.speedo = rect(m, r.pad.y - gap - sh, sw, sh)
	else
		local x0, x1 = r.pad.x + r.pad.w, r.handbrake.x
		r.speedo = rect((x0 + x1) / 2 - sw / 2, H - m - sh, sw, sh)
	end
	return r
end

function UI.layout()
	if not E.gui then
		return
	end
	local mt = Layout.metrics()
	local cls = mt.class
	local r = UI.compute(cls, mt.W, mt.H, mt.s, S.role)
	S.cls = cls
	local touch = cls ~= "pc"
	local driver = S.role == "driver"
	local function put(name: string, g: GuiObject?, visible: boolean?)
		if not g then
			return
		end
		local rr = r[name]
		if rr and visible ~= false then
			place(g, rr)
			g.Visible = true
		else
			g.Visible = false
		end
	end
	put("pad", E.pad, touch and driver)
	put("gas", E.gas, touch and driver)
	put("brake", E.brake, touch and driver)
	put("handbrake", E.handbrake, touch and driver)
	put("horn", E.horn, touch and driver)
	put("camera", E.camera)
	put("lights", E.lights, driver)
	put("radio", E.radio)
	put("exit", E.exit)
	put("speedo", E.speedo)
	put("hint", E.hint, not touch and driver)
	if E.flip then
		place(E.flip, r.flip)
		E.flip.Visible = S.flip and driver
	end
	if E.tow and r.tow then
		place(E.tow, r.tow)
	end
	-- text sizes follow the scale
	local s = mt.s
	E.speedValue.TextSize = round(30 * s)
	E.knob.Size = UDim2.fromOffset(round(46 * s), round(46 * s))
	for _, b in { E.gas, E.brake } do
		local g = b:FindFirstChild("Glyph")
		if g then
			g.TextSize = round(26 * s)
		end
	end
	for _, pair in { { E.camera, "🎥", "시점 (V)" }, { E.lights, "💡", "라이트 (L)" }, { E.radio, "📻", "라디오 (T)" } } do
		local b, glyph, pcText = pair[1], pair[2], pair[3]
		local gl = b:FindFirstChild("Glyph") :: TextLabel
		local cap = b:FindFirstChild("Caption") :: TextLabel
		if not touch then
			-- PC: the round buttons become labelled pills
			gl.Text = glyph .. "  " .. pcText
			gl.TextSize = K.Type.bodySm
			gl.Font = K.Font.bold
			gl.Position = UDim2.fromScale(0.5, 0.5)
			gl.Size = UDim2.fromScale(1, 1)
			cap.Visible = false
		else
			gl.Text = glyph
			gl.TextSize = 18
			gl.Font = K.Font.heavy
			gl.Position = UDim2.fromScale(0.5, 0.38)
			gl.Size = UDim2.new(1, 0, 0.5, 0)
			cap.Visible = true
		end
	end
	E.exit.Text = if touch then "🚪  내리기" else "🚪  내리기 (F)"
	for _, b in { E.camera, E.lights, E.radio } do
		K.corner(b, if touch then UDim.new(0.5, 0) else UDim.new(0, K.Radius.sm))
	end
end

-- Radio state on the HUD: the button's ring lights up, the speedo's model line shows the track.
function UI.setRadio(on: boolean, title: string?)
	S.radioOn = on
	S.radioTitle = title
	if E.radio then
		local st = E.radio:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = if on then K.Color.cyan else K.Color.line
			st.Transparency = if on then 0.1 else 0.84
		end
	end
	if E.model then
		if on then
			E.model.Text = "📻 " .. (title or "방송 준비 중…")
		else
			E.model.Text = S.label or ""
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Show / hide / update
---------------------------------------------------------------------------------------------------
function UI.show(role: string, label: string?)
	S.role = role
	S.shown = true
	S.flip = false
	S.label = label or ""
	E.model.Text = if S.radioOn then "📻 " .. (S.radioTitle or "방송 준비 중…") else (label or "")
	UI.layout()
	E.gui.Enabled = true
	E.gui:SetAttribute("HideGwangalliHUD", true)
	UI.closeSheet()
	K.pop(E.speedo, 0.9)
	if UI.refreshCond then
		UI.refreshCond()
	end
end

function UI.hide()
	S.shown = false
	if E.cond then
		E.cond.Visible = false
	end
	if E.tow then
		E.tow.Visible = false
	end
	if E.gui then
		E.gui.Enabled = false
		E.gui:SetAttribute("HideGwangalliHUD", false)
	end
	if E.steerRelease then
		E.steerRelease()
	end
	for input, f in held do
		held[input] = nil
		f(false)
	end
end

local lastSpeed = -1
local lastGear = ""
-- info = { kmh, gear, frac (0..1), lights (bool), flipped (bool), camLabel }
function UI.update(info: { [string]: any })
	if not S.shown then
		return
	end
	local kmh = math.floor(math.abs(info.kmh or 0) + 0.5)
	if kmh ~= lastSpeed then
		lastSpeed = kmh
		E.speedValue.Text = tostring(kmh)
		E.bar.set(math.clamp(info.frac or 0, 0, 1), true)
	end
	local g = info.gear or "P"
	if g ~= lastGear then
		lastGear = g
		E.gear.Text = g
		E.gear.BackgroundColor3 = if g == "R" then Color3.fromRGB(120, 36, 44) elseif g == "D" then Color3.fromRGB(22, 70, 90) else K.Color.card2
		E.gear.TextColor3 = if g == "R" then Color3.fromRGB(255, 150, 150) elseif g == "D" then K.Color.cyan else K.Color.sub
	end
	local lightsOn = info.lights == true
	if lightsOn ~= S.lights then
		S.lights = lightsOn
		local st = E.lights:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = if lightsOn then K.Color.gold else K.Color.line
			st.Transparency = if lightsOn then 0.1 else 0.84
		end
	end
	local flipped = info.flipped == true and S.role == "driver"
	if flipped ~= S.flip then
		S.flip = flipped
		E.flip.Visible = flipped
		if flipped then
			K.pop(E.flip, 0.85)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 차 부르기 sheet: the player's OWN cars (d.cars via the garage) + the called car's status; the six
-- free kinds only for admins / with the dev switch (status.free)
---------------------------------------------------------------------------------------------------
local sheet: any = {}
UI.sheet = sheet

local ROW_H, BTN_H = 84, 56

local function bandColor(band: string?): Color3
	if band == "dead" then
		return K.Color.red
	elseif band == "bad" then
		return Color3.fromRGB(255, 110, 60)
	elseif band == "worn" then
		return K.Color.orange
	end
	return K.Color.green
end
UI.bandColor = bandColor

local BAND_LABEL = { good = "양호", worn = "점검 필요", bad = "고장 직전", dead = "엔진 정지" }

local function paintOf(colorId: string?): Color3
	local GS = Ctx and Ctx.GS
	if GS then
		local ok, c = pcall(GS.color3, colorId)
		if ok then
			return c
		end
	end
	return Color3.fromRGB(220, 222, 224)
end

function UI.buildSheet(pg: Instance)
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliCallCar"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = 30
	g.Enabled = false
	g:SetAttribute("HideGwangalliHUD", false)
	sheet.gui = g
	local dim = K.frame(g, { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.55, BackgroundColor3 = Color3.new(0, 0, 0), Active = true, ZIndex = 1 })
	sheet.dim = dim
	local dimBtn = Instance.new("TextButton")
	dimBtn.Name = "DimClose"
	dimBtn.Text = ""
	dimBtn.BackgroundTransparency = 1
	dimBtn.Size = UDim2.fromScale(1, 1)
	dimBtn.ZIndex = 1
	dimBtn.Parent = dim
	dimBtn.Activated:Connect(function()
		UI.closeSheet()
	end)
	local panel = K.Panel(g, { Name = "Sheet", Radius = K.Radius.xl, ZIndex = 2 })
	panel.BackgroundTransparency = 0.06
	panel.ClipsDescendants = true
	sheet.panel = panel
	K.text(panel, { Name = "Title", Text = "🚗  내 차 부르기", Font = K.Font.bold, TextSize = K.Type.title2, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -80, 0, 26), ZIndex = 3 })
	sheet.sub = K.text(panel, { Name = "Sub", Text = "내 차 · 렌트 차를 가장 가까운 도로에 세워 드려요", TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -80, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	local close = K.IconButton(panel, { name = "Close", icon = "✕", anchor = Vector2.new(1, 0), position = UDim2.new(1, -8, 0, 8), size = UDim2.fromOffset(48, 48), zIndex = 4, onClick = function()
		UI.closeSheet()
	end })
	sheet.close = close
	-- status card (the called car)
	local status = K.Card(panel, { Name = "Status", Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 0, 64), ZIndex = 3 })
	status.Visible = false
	local stText = K.text(status, { Name = "Text", Text = "", TextSize = K.Type.bodySm, Font = K.Font.medium, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -132, 1, 0), TextWrapped = true, ZIndex = 4 })
	local dismiss = K.Button(status, { name = "Dismiss", text = "돌려보내기", style = "danger", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -6, 0.5, 0), size = UDim2.fromOffset(112, BTN_H - 4), zIndex = 5, onClick = function()
		emit("dismiss")
	end })
	sheet.status, sheet.statusText, sheet.dismiss = status, stText, dismiss
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = K.Color.sub
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = 3
	list.Parent = panel
	K.list(list, false, 8)
	K.pad(list, 12, 12, 4, 16)
	sheet.list = list
	sheet.rows = {}
	g.Parent = pg
	UI.renderRows(nil)
end

local function clearRows()
	for _, c in sheet.list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	sheet.rows = {}
end

local function sectionLabel(text: string, order: number)
	K.text(sheet.list, { Name = "Section", Text = text, Font = K.Font.bold, TextSize = K.Type.caption, TextColor3 = K.Color.faint, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, ZIndex = 4 })
end

-- One owned-car row: colour tile, name + plate, condition bar, action button.
local function carRow(car: any, order: number, outId: string?)
	local row = K.Card(sheet.list, { Name = "Car_" .. tostring(car.id), Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = order, ZIndex = 4 })
	local tile = K.frame(row, { Name = "Paint", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 0, BackgroundColor3 = paintOf(car.color), ZIndex = 5 })
	K.corner(tile, UDim.new(0, 14))
	K.stroke(tile, nil, 1, 0.7)
	K.gradient(tile, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160) }, 90)
	K.text(tile, { Name = "Glyph", Text = car.glyph or "🚗", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 6 })
	local nameText = tostring(car.label or "내 차") .. (if car.rental then "  🔑 렌트" else "") .. (if car.loan then "  · 할부" else "")
	K.text(row, { Name = "Name", Text = nameText, Font = K.Font.bold, TextSize = K.Type.body, Position = UDim2.fromOffset(72, 10), Size = UDim2.new(1, -184, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	local plate = K.text(row, { Name = "Plate", Text = tostring(car.plate or ""), TextSize = K.Type.caption, Font = K.Font.bold, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(72, 31), Size = UDim2.new(1, -184, 0, 16), ZIndex = 5 })
	K.mono(plate)
	local cond = math.clamp(tonumber(car.cond) or 100, 0, 100)
	local band = car.band or "good"
	local barBg = K.frame(row, { Name = "CondTrack", Position = UDim2.fromOffset(72, 56), Size = UDim2.new(1, -250, 0, 6), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card3, ZIndex = 5 })
	K.corner(barBg, UDim.new(0.5, 0))
	local fill = K.frame(barBg, { Name = "Fill", Size = UDim2.fromScale(cond / 100, 1), BackgroundTransparency = 0, BackgroundColor3 = bandColor(band), ZIndex = 6 })
	K.corner(fill, UDim.new(0.5, 0))
	local rentalLeft = if car.rental and car.rentalLeft then string.format(" · 렌트 %d분 남음", math.ceil(car.rentalLeft / 60)) else ""
	K.text(row, { Name = "Cond", Text = string.format("%d%% %s%s", cond, BAND_LABEL[band] or "", rentalLeft), TextSize = K.Type.micro, Font = K.Font.bold, TextColor3 = bandColor(band), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, -172, 0, 59), Size = UDim2.fromOffset(100, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
	local text, style, action = "부르기", "primary", "call"
	if outId == car.id then
		text, style, action = "타는 중", "tonal", "call"
	elseif band == "dead" and car.towed then
		text, style, action = "정비소", "secondary", "waypoint"
	elseif band == "dead" then
		text, style, action = "🚛 견인", "gold", "tow"
	end
	local b = K.Button(row, { name = "Act", text = text, style = style, anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -10, 0.5, 0), size = UDim2.fromOffset(96, BTN_H), zIndex = 6, onClick = function()
		if action == "call" then
			emit("call", car.id)
		elseif action == "tow" then
			if Ctx and Ctx.Api then
				task.spawn(Ctx.Api.tow, car.id)
			end
		elseif action == "waypoint" then
			if Ctx and Ctx.Api then
				task.spawn(Ctx.Api.garageWaypoint)
			end
		end
	end })
	sheet.rows[car.id] = { row = row, button = b }
end

local function emptyCard(order: number)
	local card = K.Card(sheet.list, { Name = "Empty", Size = UDim2.new(1, 0, 0, 190), LayoutOrder = order, ZIndex = 4 })
	K.text(card, { Name = "Glyph", Text = "🚗", TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 40), ZIndex = 5 })
	K.text(card, { Name = "Title", Text = "아직 내 차가 없어요", Font = K.Font.bold, TextSize = K.Type.body, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 0, 20), ZIndex = 5 })
	K.text(card, { Name = "Body", Text = "광안 오토 정비소에서 차를 사거나, 하루 렌트(2만원)로 바로 타 보세요", TextSize = K.Type.caption, TextColor3 = K.Color.sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 0, 34), ZIndex = 5 })
	K.Button(card, { name = "GoGarage", text = "정비소에서 구매", icon = "🧭", style = "primary", anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 1, -12), size = UDim2.new(1, -24, 0, BTN_H), zIndex = 6, onClick = function()
		if Ctx and Ctx.Api then
			task.spawn(Ctx.Api.garageWaypoint)
		end
		UI.closeSheet()
	end })
end

local function freeRows(order: number)
	sectionLabel("개발자 모드 · 모든 차종 (소유 안 해도 부르기)", order)
	for i, item in VS.Catalog do
		local spec = VS.spec(item.kind)
		local row = K.Card(sheet.list, { Name = "Row_" .. item.kind, Size = UDim2.new(1, 0, 0, 68), LayoutOrder = order + i, ZIndex = 4 })
		local tile = K.iconTile(row, 40, item.glyph, K.Color.violet, false)
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, 10, 0.5, 0)
		tile.ZIndex = 5
		K.text(row, { Name = "Name", Text = spec.label, Font = K.Font.bold, TextSize = K.Type.body, Position = UDim2.fromOffset(60, 12), Size = UDim2.new(1, -170, 0, 20), ZIndex = 5 })
		K.text(row, { Name = "Info", Text = string.format("최고 %d km/h · %s", spec.topKmh, item.blurb), TextSize = K.Type.caption, TextColor3 = K.Color.sub, Position = UDim2.fromOffset(60, 34), Size = UDim2.new(1, -170, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		local b = K.Button(row, { name = "Call", text = "부르기", style = "secondary", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -8, 0.5, 0), size = UDim2.fromOffset(96, BTN_H - 4), zIndex = 6, onClick = function()
			emit("call", item.kind)
		end })
		sheet.rows[item.kind] = { row = row, button = b }
	end
end

-- st = merged status { hasCar, label, meters, cooldown, free, cars = { views }, outId, max, loaded }
function UI.renderRows(st: { [string]: any }?)
	if not sheet.list then
		return
	end
	clearRows()
	local cars = (st and st.cars) or {}
	local order = 1
	if st == nil then
		local sk = K.text(sheet.list, { Name = "Loading", Text = "내 차를 불러오는 중…", TextSize = K.Type.bodySm, TextColor3 = K.Color.sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1, ZIndex = 4 })
		local _ = sk
		return
	end
	local owned = 0
	for _, c in cars do
		if not c.rental then
			owned += 1
		end
	end
	if #cars > 0 then
		sectionLabel(string.format("내 차 %d / %d%s", owned, st.max or 3, if owned < #cars then " · 렌트 1" else ""), order)
		order += 1
		for _, c in cars do
			carRow(c, order, st.outId)
			order += 1
		end
		if owned < (st.max or 3) then
			local more = K.Button(sheet.list, { name = "More", text = "정비소에서 차 더 보기", icon = "🔧", style = "secondary", size = UDim2.new(1, 0, 0, BTN_H), order = order, zIndex = 5, onClick = function()
				if Ctx and Ctx.Api then
					task.spawn(Ctx.Api.garageWaypoint)
				end
				UI.closeSheet()
			end })
			local _ = more
			order += 1
		end
	else
		emptyCard(order)
		order += 1
	end
	if st.free then
		freeRows(order + 1)
	end
	if S.sheetOpen then
		local rows = {}
		for _, c in sheet.list:GetChildren() do
			if c:IsA("GuiObject") then
				table.insert(rows, c)
			end
		end
		K.stagger(rows)
	end
end

function UI.layoutSheet()
	if not sheet.panel then
		return
	end
	local r = Layout.rect("sheetRight")
	sheet.panel.AnchorPoint = Vector2.zero
	sheet.panel.Position = UDim2.fromOffset(r.x, r.y)
	sheet.panel.Size = UDim2.fromOffset(r.w, r.h)
	local statusH = if sheet.status.Visible then 72 else 0
	sheet.list.Position = UDim2.fromOffset(0, 64 + statusH)
	sheet.list.Size = UDim2.new(1, 0, 1, -(64 + statusH))
end

-- st = merged status (see renderRows); nil = loading
function UI.setSheetStatus(st: { [string]: any }?)
	if not sheet.status then
		return
	end
	if st and st.hasCar then
		sheet.status.Visible = true
		local cond = if type(st.cond) == "number" then string.format(" · 상태 %d%%", st.cond) else ""
		sheet.statusText.Text = string.format("부른 차: %s%s%s", tostring(st.label or "내 차"), if st.meters then string.format(" · %dm", st.meters) else "", cond)
	else
		sheet.status.Visible = false
	end
	UI.renderRows(st)
	UI.layoutSheet()
end

function UI.setCallBusy(key: string?, busy: boolean)
	for k, r in sheet.rows or {} do
		if r.button.Parent then
			if busy and k == key then
				K.setButtonLoading(r.button, true, "…")
			elseif not busy then
				K.setButtonLoading(r.button, false)
			end
			K.setButtonEnabled(r.button, not busy or k == key)
		end
	end
end

function UI.openSheet()
	if not sheet.gui then
		return
	end
	S.sheetOpen = true
	UI.layoutSheet()
	sheet.gui.Enabled = true
	sheet.gui:SetAttribute("HideGwangalliHUD", true)
	sheet.dim.BackgroundTransparency = 1
	K.tween(sheet.dim, 0.2, { BackgroundTransparency = 0.55 })
	K.pop(sheet.panel, 0.94)
	K.feedback("open")
end

function UI.closeSheet()
	if not sheet.gui or not S.sheetOpen then
		return
	end
	S.sheetOpen = false
	sheet.gui.Enabled = false
	sheet.gui:SetAttribute("HideGwangalliHUD", false)
end

function UI.sheetOpen(): boolean
	return S.sheetOpen
end

---------------------------------------------------------------------------------------------------
-- Condition gauge (speedometer cluster) + tow button for owned cars
---------------------------------------------------------------------------------------------------
local carConn: { RBXScriptConnection } = {}
function UI.setCar(car: Model?)
	for _, c in carConn do
		c:Disconnect()
	end
	table.clear(carConn)
	S.car = car
	local function refresh()
		if not E.cond then
			return
		end
		local c = car and car:GetAttribute(VS.Attr.Condition)
		if type(c) ~= "number" or not S.shown then
			E.cond.Visible = false
			if E.tow then
				E.tow.Visible = false
			end
			return
		end
		local cond = math.clamp(math.floor(c + 0.5), 0, 100)
		local band = if cond <= 0 then "dead" elseif cond < VS.Condition.bad then "bad" elseif cond < VS.Condition.worn then "worn" else "good"
		local col = bandColor(band)
		E.cond.Visible = true
		E.condText.Text = string.format("🔧 %d%%  %s", cond, BAND_LABEL[band])
		E.condText.TextColor3 = col
		K.tween(E.condFill, 0.22, { Size = UDim2.fromScale(cond / 100, 1), BackgroundColor3 = col })
		if E.tow then
			local show = band == "dead" and S.role == "driver"
			if show and not E.tow.Visible then
				E.tow.Visible = true
				K.pop(E.tow, 0.85)
			elseif not show then
				E.tow.Visible = false
			end
		end
	end
	if car then
		table.insert(carConn, car:GetAttributeChangedSignal(VS.Attr.Condition):Connect(refresh))
	end
	refresh()
	UI.refreshCond = refresh
end

return UI
