-- GwangalliHome/Interior: the 인테리어 mode (owner) and 집 구경 (guests, 둘러보기 viewers).
--   * opened by the server (HomeState "interior" {mode = "edit" | "tour", rooms, slots, decor, ...})
--     after the 현관 wall panel prompt, the 🛠️ bar button, the phone 홈 app (Home.openInterior) or a
--     staged 둘러보기 unit; closed with ✕, Esc, leaving the home
--   * camera: scripted orbit around the selected room (or the selected piece), driven by tweened
--     NumberValues (TweenService) + one RenderStepped driver while open; drag = orbit, pinch / wheel =
--     zoom; the room is kept centred in the part of the screen the sheet leaves free
--   * furniture slots of the room light up (pooled Highlights); tap one (or its card) -> catalog by
--     category (소파 / 침대 / 테이블·의자 / 조명 / 러그 / 장식·식물 / 가전 / 커튼) with prices, a live
--     semi-transparent ghost in the slot, 90° rotation where the slot allows, buy from the bank
--     (HomeAction "placeFurniture" {slotId, variantId, rot, sellOld = true}: the replaced piece is
--     sold back at 50 %), or turn the current piece ("rotateSlot")
--   * 벽지 (6) / 바닥 (4) / 조명 (5) per room with a live local preview ("setTheme")
--   * tour mode: read-only room list, the pieces and finishes of each room, 칭찬하기 (guests) or
--     계약 문의 (둘러보기)
-- Built with ReplicatedStorage.GwangalliUI; touch targets >= 56 px; portrait = bottom sheet,
-- landscape = right panel. Everything here is cosmetic / local: the server validates every action.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Interior = {}

local C: any = nil
local K: any, G: any, HS: any = nil, nil, nil
local player = Players.LocalPlayer

local HALF = math.pi / 2
local TAP = 56 -- minimum touch target (px)

-- UI ------------------------------------------------------------------------------------------------
local gui: ScreenGui? = nil
local ui: any = {}
local cards: { GuiObject } = {}

-- state ---------------------------------------------------------------------------------------------
local isOpen = false
local data: any = nil
local mode = "edit"
local tab = "furniture"
local roomId: string? = nil
local selSlot: string? = nil
local pick: any = nil -- { id = variantId | false } (false = the template's default piece)
local pickRot = 0
local themeKind = "wall"
local themePick: string? = nil
local busy = false
local model: Model? = nil
local slotIdx: { [string]: Instance } = {}
local themeParts: { [string]: { wall: { BasePart }, floor: { BasePart }, light: { BasePart }, lights: { Light } } } = {}
local portrait = false
local cover = { right = 0, bottom = 0, top = 64 }
local lastPrice = 0
local conns: { RBXScriptConnection } = {}

-- small helpers --------------------------------------------------------------------------------------
local function color3(t: any, fallback: Color3?): Color3
	if type(t) == "table" and t[1] then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return fallback or Color3.new(1, 1, 1)
end

local function won(n: number): string
	local ok, s = pcall(K.won, n)
	return if ok then s else (tostring(n) .. "원")
end

local function reduced(): boolean
	local ok, r = pcall(C.motionReduced)
	return ok and r == true
end

local function tw(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	if reduced() or t <= 0 then
		for k, v in goals do
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
		return
	end
	pcall(function()
		TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals):Play()
	end)
end

local function slotData(id: string?): any?
	if not data or not id then
		return nil
	end
	for _, s in data.slots or {} do
		if s.slotId == id then
			return s
		end
	end
	return nil
end

local function roomData(id: string?): any?
	if not data or not id then
		return nil
	end
	for _, r in data.rooms or {} do
		if r.id == id then
			return r
		end
	end
	return nil
end

local function geometry(id: string): any?
	local cont = slotIdx[id]
	if not cont or not cont.Parent then
		return nil
	end
	local ok, geo = pcall(G.slotGeometry, cont)
	return if ok then geo else nil
end

-- room of a slot: the server's answer, else the room box that contains it, else the nearest room
local function roomOfSlot(s: any): string?
	if type(s.room) == "string" then
		return s.room
	end
	local geo = geometry(s.slotId)
	if not geo or not data then
		return nil
	end
	local p = geo.frame.Position
	local best, bestD = nil, math.huge
	for _, r in data.rooms or {} do
		if typeof(r.center) == "Vector3" and typeof(r.size) == "Vector3" then
			local d = Vector3.new(p.X - r.center.X, 0, p.Z - r.center.Z)
			local inside = math.abs(d.X) <= r.size.X / 2 + 0.5 and math.abs(d.Z) <= r.size.Z / 2 + 0.5 and p.Y >= r.center.Y - 2 and p.Y <= r.center.Y + r.size.Y
			local score = if inside then 0 else d.Magnitude
			if score < bestD then
				best, bestD = r.id, score
			end
		end
	end
	return best
end

local function slotsInRoom(room: string?): { any }
	local out = {}
	if not data then
		return out
	end
	for _, s in data.slots or {} do
		if roomOfSlot(s) == room then
			table.insert(out, s)
		end
	end
	return out
end

local function groupOfCategory(cat: string): any?
	return HS and HS.groupOf(cat) or nil
end

local function catInfo(cat: string): any
	return G.FURNITURE_CATEGORIES[cat] or { name = cat, icon = "🪑" }
end

local function variantName(id: any): string
	if id == false or id == nil then
		return "기본 가구"
	end
	local f = G.FURNITURE[id]
	return f and f.name or tostring(id)
end

local function storageCount(id: string): number
	local hv = data and data.housing
	local st = hv and hv.storage
	return if type(st) == "table" then (st[id] or 0) else 0
end

local function bank(): number
	local b = player:GetAttribute("Bank")
	if type(b) == "number" then
		return b
	end
	return data and data.bank or 0
end

-------------------------------------------------------------------------------------------------
-- Highlights (pooled) + ghost preview + theme preview
-------------------------------------------------------------------------------------------------
local hlPool: { Highlight } = {}
local ghost: Model? = nil
local ghostHl: Highlight? = nil
local hidden: { BasePart } = {}
local themeSaved: { [Instance]: any } = {}

local function camHolder(): Instance
	return workspace.CurrentCamera or workspace
end

local function visualOf(id: string): Instance?
	local cont = slotIdx[id]
	if not cont then
		return nil
	end
	local m = cont:FindFirstChild("Furniture_" .. id) or cont:FindFirstChild("Furniture") or cont:FindFirstChild("Default_" .. id)
	if m then
		return m
	end
	for _, c in cont:GetChildren() do
		if c:IsA("Model") then
			return c
		end
	end
	return nil
end

local function hideHighlights()
	for _, h in hlPool do
		h.Enabled = false
	end
end

local function drawHighlights()
	hideHighlights()
	if not isOpen or not data or tab ~= "furniture" then
		return
	end
	local list = slotsInRoom(roomId)
	local n = 0
	for _, s in list do
		if n >= 12 then
			break
		end
		local target = visualOf(s.slotId)
		if target then
			n += 1
			local h = hlPool[n]
			if not h then
				h = Instance.new("Highlight")
				h.Name = "InteriorSlotHL"
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				hlPool[n] = h
			end
			local sel = s.slotId == selSlot
			h.FillColor = if sel then K.Color.gold else K.Color.cyan
			h.OutlineColor = if sel then K.Color.gold else K.Color.cyan
			h.FillTransparency = if sel then 0.78 else 0.9
			h.OutlineTransparency = if sel then 0 else 0.35
			h.Adornee = target
			h.Parent = camHolder()
			h.Enabled = not (sel and ghost ~= nil)
		end
	end
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if ghostHl then
		ghostHl.Enabled = false
	end
	for _, p in hidden do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	hidden = {}
end

local function hideCurrent(id: string)
	local cont = slotIdx[id]
	if not cont then
		return
	end
	for _, d in cont:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.LocalTransparencyModifier = 1
			table.insert(hidden, d)
		end
	end
end

local function ghostify(m: Model)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.Transparency = 0.32 + 0.68 * p.Transparency
		elseif p:IsA("Light") or p:IsA("Seat") or p:IsA("ProximityPrompt") or p:IsA("Script") or p:IsA("LocalScript") then
			p:Destroy()
		end
	end
end

-- Live preview of `variantId` (false = the current default piece turned) at `rot` in a slot.
local function showGhost(id: string, variantId: any, rot: number)
	clearGhost()
	local geo = geometry(id)
	if not geo then
		return
	end
	local frame = geo.frame * CFrame.Angles(0, (rot % 4) * HALF, 0)
	local m: Model? = nil
	if variantId then
		local w, d = geo.w, geo.d
		if rot % 2 == 1 then
			w, d = d, w
		end
		local spec = G.furnitureSpec(variantId, w, geo.h, d)
		if not spec then
			return
		end
		m = Instance.new("Model")
		local mm = m :: Model
		mm.Name = "InteriorGhost"
		for _, p in spec.parts do
			local part = Instance.new("Part")
			part.Name = p.name
			if p.shape == "Cylinder" then
				part.Shape = Enum.PartType.Cylinder
			elseif p.shape == "Ball" then
				part.Shape = Enum.PartType.Ball
			end
			part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
			local cf = frame * CFrame.new(p.pos[1], p.pos[2], p.pos[3])
			if p.rot then
				cf = cf * CFrame.Angles(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
			end
			part.CFrame = cf
			part.Color = color3(p.color)
			local okM, mat = pcall(function()
				return (Enum.Material :: any)[p.material]
			end)
			part.Material = if okM and mat then mat else Enum.Material.SmoothPlastic
			part.Transparency = p.transparency or 0
			part.Parent = mm
		end
	else
		-- the current default piece, turned: clone what the slot shows now
		local cur = visualOf(id)
		if not cur or not cur:IsA("Model") then
			return
		end
		local okC, cl = pcall(function()
			return (cur :: Model):Clone()
		end)
		if not okC or not cl then
			return
		end
		m = cl
		local s = slotData(id)
		local curRot = s and s.rot or 0
		local base = geo.frame * CFrame.Angles(0, (curRot % 4) * HALF, 0)
		local rel = base:ToObjectSpace((cl :: Model):GetPivot())
		;(cl :: Model):PivotTo(frame * rel)
	end
	local mm = m :: Model
	ghostify(mm)
	hideCurrent(id)
	mm.Parent = camHolder()
	ghost = mm
	if not ghostHl then
		local h = Instance.new("Highlight")
		h.Name = "InteriorGhostHL"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillTransparency = 1
		h.OutlineTransparency = 0.1
		ghostHl = h
	end
	local gh = ghostHl :: Highlight
	gh.OutlineColor = K.Color.gold
	gh.Adornee = mm
	gh.Parent = camHolder()
	gh.Enabled = true
end

local function collectThemeParts()
	themeParts = {}
	local m = model
	if not m then
		return
	end
	local fallback = m:GetAttribute("Fallback") == true
	local view = m:FindFirstChild("Backdrop") or m:FindFirstChild("WindowView")
	local function entry(room: string): any
		local e = themeParts[room]
		if not e then
			e = { wall = {}, floor = {}, light = {}, lights = {} }
			themeParts[room] = e
		end
		return e
	end
	for _, d in m:GetDescendants() do
		if view and d:IsDescendantOf(view) then
			continue
		end
		if d:IsA("BasePart") then
			local room, surf = d:GetAttribute("Room"), d:GetAttribute("Surface")
			if type(room) == "string" and (surf == "wall" or surf == "floor" or surf == "light") then
				table.insert(entry(room)[surf], d)
			elseif fallback then
				if d.Name == "Wall" then
					table.insert(entry("main").wall, d)
				elseif d.Name == "Floor" then
					table.insert(entry("main").floor, d)
				elseif d.Name == "CeilingLight" then
					table.insert(entry("main").light, d)
				end
			end
		elseif d:IsA("Light") then
			local room = d:GetAttribute("Room")
			if type(room) == "string" then
				table.insert(entry(room).lights, d)
			elseif fallback and d.Parent and d.Parent.Name == "CeilingLight" then
				table.insert(entry("main").lights, d)
			end
		end
	end
end

local function clearThemePreview()
	for inst, v in themeSaved do
		pcall(function()
			if inst:IsA("Light") then
				(inst :: Light).Color = v.color
			else
				(inst :: BasePart).Color = v.color;
				(inst :: BasePart).Material = v.material
			end
		end)
	end
	themeSaved = {}
end

local function previewTheme(room: string, kind: string, id: string?)
	clearThemePreview()
	local def = id and id ~= "default" and HS.themeDef(kind, id) or nil
	local e = themeParts[room]
	if not def or not e then
		return
	end
	local col = color3(def.color)
	local okM, mat = pcall(function()
		return if def.material then (Enum.Material :: any)[def.material] else nil
	end)
	for _, p in (if kind == "wall" then e.wall elseif kind == "floor" then e.floor else e.light) do
		themeSaved[p] = { color = p.Color, material = p.Material }
		p.Color = col
		if kind ~= "light" and okM and mat then
			p.Material = mat
		end
	end
	if kind == "light" then
		for _, l in e.lights do
			themeSaved[l] = { color = l.Color }
			l.Color = col
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Camera: tweened orbit values + one driver
-------------------------------------------------------------------------------------------------
local cam: any = { vals = nil, conn = nil, saved = nil, spin = true, spinAfter = 0, drag = nil, bounds = nil, pitchOff = 0, yawOff = 0 }

local function camVals(): any
	if cam.vals then
		return cam.vals
	end
	local v = {}
	for _, n in { "tx", "ty", "tz", "r", "elev", "yaw" } do
		local x = Instance.new("NumberValue")
		x.Name = "InteriorCam_" .. n
		x.Parent = gui
		v[n] = x
	end
	v.r.Value = 10
	v.elev.Value = math.rad(28)
	cam.vals = v
	return v
end

local function focusTo(target: Vector3, radius: number, elev: number, yaw: number?, t: number)
	local v = camVals()
	tw(v.tx, t, { Value = target.X })
	tw(v.ty, t, { Value = target.Y })
	tw(v.tz, t, { Value = target.Z })
	tw(v.r, t, { Value = radius })
	tw(v.elev, t, { Value = elev })
	if yaw then
		-- shortest way round
		local cur = v.yaw.Value
		local d = (yaw - cur + math.pi) % (2 * math.pi) - math.pi
		tw(v.yaw, t, { Value = cur + d })
	end
	cam.spinAfter = os.clock() + t + 0.2
end

local function focusRoom(id: string?, instant: boolean?)
	local r = roomData(id)
	if not r or typeof(r.center) ~= "Vector3" or typeof(r.size) ~= "Vector3" then
		return
	end
	local size: Vector3 = r.size
	local eye = math.min(size.Y - 1.6, 4.2)
	local target = r.center + Vector3.new(0, math.max(2.2, eye * 0.6), 0)
	local radius = math.clamp(math.max(size.X, size.Z) * 0.42 + 1.5, 5, 18)
	cam.bounds = { center = r.center, size = size }
	cam.spin = true
	focusTo(target, radius, math.rad(if size.Y > 11 then 24 else 30), nil, if instant then 0 else 0.9)
end

local function focusSlot(id: string)
	local geo = geometry(id)
	if not geo then
		return
	end
	local h = math.min(geo.h, 6)
	local c = (geo.frame * CFrame.new(0, h * 0.45, 0)).Position
	local radius = math.clamp(math.max(geo.w, geo.d, h) * 1.05 + 4.5, 5.5, 14)
	local look = geo.frame.LookVector
	local yaw = math.atan2(look.X, look.Z)
	cam.spin = false
	focusTo(c, radius, math.rad(24), yaw, 0.7)
end

local function camStep(dt: number)
	local camObj = workspace.CurrentCamera
	local v = cam.vals
	if not camObj or not v then
		return
	end
	if camObj.CameraType ~= Enum.CameraType.Scriptable then
		camObj.CameraType = Enum.CameraType.Scriptable
	end
	if cam.spin and not cam.drag and os.clock() > cam.spinAfter and not reduced() then
		v.yaw.Value += dt * math.rad(5)
	end
	local target = Vector3.new(v.tx.Value, v.ty.Value, v.tz.Value)
	local e, y, r = v.elev.Value, v.yaw.Value, v.r.Value
	local pos = target + Vector3.new(math.sin(y) * math.cos(e), math.sin(e), math.cos(y) * math.cos(e)) * r
	local b = cam.bounds
	if b then
		-- stay inside the room (walls / ceiling never block the view)
		local hx, hz = math.max(0.4, b.size.X / 2 - 0.7), math.max(0.4, b.size.Z / 2 - 0.7)
		pos = Vector3.new(
			math.clamp(pos.X, b.center.X - hx, b.center.X + hx),
			math.clamp(pos.Y, b.center.Y + 1.2, b.center.Y + math.max(2, b.size.Y - 0.6)),
			math.clamp(pos.Z, b.center.Z - hz, b.center.Z + hz)
		)
	end
	if (pos - target).Magnitude < 0.5 then
		pos = target + Vector3.new(0, 0.6, 0.6)
	end
	camObj.CFrame = CFrame.lookAt(pos, target) * CFrame.Angles(cam.pitchOff, cam.yawOff, 0)
end

local function camStart()
	local camObj = workspace.CurrentCamera
	if not camObj then
		return
	end
	if not cam.saved then
		cam.saved = { type = camObj.CameraType, fov = camObj.FieldOfView, subject = camObj.CameraSubject, cf = camObj.CFrame }
	end
	local v = camVals()
	-- start from where the camera is (no jump)
	local p = camObj.CFrame.Position
	local look = camObj.CFrame.LookVector
	local t = p + look * 8
	v.tx.Value, v.ty.Value, v.tz.Value = t.X, t.Y, t.Z
	v.r.Value = 8
	v.yaw.Value = math.atan2(-look.X, -look.Z)
	v.elev.Value = math.asin(math.clamp(-look.Y, -0.9, 0.9))
	camObj.CameraType = Enum.CameraType.Scriptable
	tw(camObj, 0.5, { FieldOfView = 62 })
	if cam.conn then
		cam.conn:Disconnect()
	end
	cam.conn = RunService.RenderStepped:Connect(camStep)
end

local function camStop()
	if cam.conn then
		cam.conn:Disconnect()
		cam.conn = nil
	end
	local camObj = workspace.CurrentCamera
	local saved = cam.saved
	cam.saved = nil
	cam.drag = nil
	if camObj and saved then
		camObj.CameraType = if saved.type == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved.type
		camObj.FieldOfView = saved.fov or 70
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		camObj.CameraSubject = hum or saved.subject
	end
end

-------------------------------------------------------------------------------------------------
-- UI building blocks
-------------------------------------------------------------------------------------------------
local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function chip(parent: Instance, name: string, text: string, selected: boolean, enabled: boolean, onClick: () -> (), accent: Color3?): TextButton
	local w = math.max(TAP + 8, math.ceil(K.textWidth(text, 14)) + 34)
	local b = K.make("TextButton", { Name = name, Size = UDim2.fromOffset(w, TAP), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = nextOrder() })
	local pill = K.frame(b, { Name = "Pill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 0, BackgroundColor3 = if selected then (accent or K.Color.cyan) else K.Color.card })
	K.corner(pill, UDim.new(0.5, 0))
	K.stroke(pill, nil, 1, if selected then 1 else 0.86)
	K.text(pill, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = K.Font.bold,
		TextSize = 14,
		TextColor3 = if selected then K.Color.onAccent elseif enabled then K.Color.text else K.Color.faint,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	K.pressable(b, { veil = false, scale = 0.95, sound = "toggle" })
	b.Activated:Connect(function()
		if enabled then
			onClick()
		else
			pcall(K.feedback, "error")
		end
	end)
	b.Parent = parent
	return b
end

-- hover scale for mouse users (touch gets the press scale from K.pressable)
local function hoverScale(b: GuiButton, base: number)
	local sc = b:FindFirstChildOfClass("UIScale") or K.make("UIScale", { Scale = base }, b)
	sc:SetAttribute("BaseScale", base)
	sc.Scale = base
	b.MouseEnter:Connect(function()
		if not UserInputService.TouchEnabled then
			tw(sc, 0.14, { Scale = base * 1.04 }, Enum.EasingStyle.Quad)
		end
	end)
	b.MouseLeave:Connect(function()
		tw(sc, 0.16, { Scale = base }, Enum.EasingStyle.Quad)
	end)
end

local function swatch(parent: Instance, colors: { Color3 }, height: number, icon: string?): Frame
	local sw = K.frame(parent, { Name = "Swatch", Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 0, BackgroundColor3 = colors[1] })
	K.corner(sw, 10)
	if #colors >= 2 then
		K.gradient(sw, colors, 25)
	end
	if icon then
		K.text(sw, { Name = "Icon", Size = UDim2.fromScale(1, 1), Text = icon, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.6 })
	end
	return sw
end

local function pillLabel(parent: Instance, text: string, color: Color3, order2: number?): Frame
	local w = math.ceil(K.textWidth(text, 11)) + 16
	local p = K.frame(parent, { Name = "Pill", Size = UDim2.fromOffset(w, 20), BackgroundTransparency = 0.72, BackgroundColor3 = color, LayoutOrder = order2 or nextOrder() })
	K.corner(p, 10)
	K.text(p, { Size = UDim2.fromScale(1, 1), Text = text, Font = K.Font.bold, TextSize = 11, TextColor3 = K.Color.text, TextXAlignment = Enum.TextXAlignment.Center })
	return p
end

-------------------------------------------------------------------------------------------------
-- Layout (portrait: bottom sheet / landscape: right panel)
-------------------------------------------------------------------------------------------------
-- the usable area of the ScreenGui (CoreUISafeInsets: below the top bar, inside the notch insets),
-- measured with a full-size probe frame; before it is measured: the viewport minus the top inset
local function screenSize(): Vector2
	local probe = ui.probe
	local s = if probe then probe.AbsoluteSize else Vector2.zero
	if s.X < 50 or s.Y < 50 then
		local c = workspace.CurrentCamera
		local vp = if c then c.ViewportSize else Vector2.new(844, 390)
		local inset = 58
		pcall(function()
			inset = game:GetService("GuiService"):GetGuiInset().Y
		end)
		s = Vector2.new(vp.X, math.max(200, vp.Y - inset))
	end
	return s
end

local function layout()
	if not gui then
		return
	end
	local s = screenSize()
	local W, H = s.X, s.Y
	portrait = W < H
	local topH = 60
	ui.top.Position = UDim2.fromOffset(8, 4)
	if portrait then
		ui.top.Size = UDim2.new(1, -16, 0, topH - 6)
		local sheetH = math.clamp(math.floor(H * 0.45), 300, 440)
		ui.bodyW = W - 24 - 6
		ui.sheetRest = UDim2.fromOffset(0, H - sheetH)
		ui.sheetAway = UDim2.fromOffset(0, H + 20)
		ui.sheet.Size = UDim2.fromOffset(W, sheetH)
		ui.rooms.Position = UDim2.fromOffset(8, topH + 2)
		ui.rooms.Size = UDim2.new(1, -16, 0, TAP)
		cover = { right = 0, bottom = sheetH, top = topH + TAP }
	else
		-- landscape: the sheet takes the full height on the right, the top bar sits over the 3D view
		local sheetW = math.clamp(math.floor(W * 0.42), 330, 470)
		ui.bodyW = sheetW - 24 - 6
		ui.sheetRest = UDim2.fromOffset(W - sheetW - 8, 4)
		ui.sheetAway = UDim2.fromOffset(W + 20, 4)
		ui.sheet.Size = UDim2.fromOffset(sheetW, H - 8)
		ui.top.Size = UDim2.fromOffset(math.max(200, W - sheetW - 24), topH - 6)
		ui.rooms.Position = UDim2.fromOffset(8, topH + 2)
		ui.rooms.Size = UDim2.fromOffset(math.max(120, W - sheetW - 32), TAP)
		cover = { right = sheetW + 8, bottom = 0, top = topH + TAP }
	end
	if ui.sheetShown then
		ui.sheet.Position = ui.sheetRest
	end
	-- aim the orbit target at the centre of the free part of the screen
	local camObj = workspace.CurrentCamera
	local vfov = math.rad((camObj and camObj.FieldOfView) or 62)
	local t = math.tan(vfov / 2)
	cam.yawOff = -math.atan((cover.right / 2) / (H / 2) * t)
	cam.pitchOff = -math.atan(((cover.bottom - cover.top) / 2) / (H / 2) * t)
	if portrait then
		cam.pitchOff = -math.atan(((cover.bottom - cover.top * 0.6) / 2) / (H / 2) * t)
	end
end

-------------------------------------------------------------------------------------------------
-- Rendering the panels
-------------------------------------------------------------------------------------------------
local render: () -> ()

local function clearBody()
	for _, c in ui.body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	cards = {}
	order = 0
end

local function setTopBar()
	if not data then
		return
	end
	local r = roomData(roomId)
	local where = if r then (r.icon .. " " .. r.name) else ""
	-- the room is the selected chip; the title stays short so it never truncates on phones
	local _ = where
	if mode == "edit" then
		ui.title.Text = "🛠️ 인테리어"
		ui.sub.Text = data.homeName or ""
	elseif data.staged then
		ui.title.Text = "🔑 둘러보기"
		ui.sub.Text = data.homeName or ""
	else
		ui.title.Text = "👀 집 구경"
		ui.sub.Text = string.format("%s님의 %s", data.ownerName or "", data.homeName or "집")
	end
	ui.decor.Text = string.format("⭐ %d", data.decor or 0)
	ui.money.Visible = mode == "edit"
	ui.storage.Visible = mode == "edit"
	if mode == "edit" then
		if portrait then
			ui.moneyL.Text = "💳 " .. (if K.wonShort then K.wonShort(bank()) else won(bank()))
		else
			K.countUp(ui.moneyL, bank(), { from = tonumber(ui.moneyL:GetAttribute("Shown")) or bank(), format = K.commas, prefix = "💳 ", suffix = "원", duration = 0.5 })
		end
		ui.moneyL:SetAttribute("Shown", bank())
	end
end

local function renderRooms()
	for _, c in ui.roomsList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not data then
		return
	end
	for _, r in data.rooms or {} do
		chip(ui.roomsList, "Room_" .. r.id, r.icon .. " " .. r.name, r.id == roomId, true, function()
			if roomId ~= r.id then
				Interior.selectRoom(r.id)
			end
		end, K.Color.cyan)
	end
end

local function setAction(price: number?, priceText: string?, subText: string?, primaryText: string?, primaryStyle: string?, primaryEnabled: boolean, onPrimary: (() -> ())?, rot: any?)
	ui.priceL.Visible = price ~= nil or priceText ~= nil
	if price then
		K.countUp(ui.priceL, price, { from = lastPrice, format = K.commas, suffix = "원", duration = 0.45 })
		lastPrice = price
	elseif priceText then
		ui.priceL.Text = priceText
	end
	ui.subL.Text = subText or ""
	local style = primaryStyle or "primary"
	if ui.primary and ui.primary:GetAttribute("KitStyle") ~= style then
		ui.primary:Destroy()
		ui.primary = nil
	end
	if not ui.primary then
		ui.primary = K.Button(ui.actionButtons, { name = "ActionPrimary", text = "", style = style, size = UDim2.new(1, -TAP - 6, 0, TAP), textSize = 15, order = 2, onClick = function()
			if ui.primaryFn and ui.primary and not ui.primary:GetAttribute("Disabled") then
				ui.primaryFn()
			end
		end })
	end
	ui.primary.Visible = primaryText ~= nil
	ui.primary.Size = if rot ~= nil then UDim2.new(1, -TAP - 6, 0, TAP) else UDim2.new(1, 0, 0, TAP)
	if primaryText then
		ui.primary.Text = if busy then "처리 중…" else primaryText
		K.setButtonEnabled(ui.primary, primaryEnabled and not busy)
		ui.primaryFn = onPrimary
	end
	ui.rotate.Visible = rot ~= nil
	ui.rotateFn = rot
end

-- furniture tab: the slots of the room ------------------------------------------------------------
local function renderSlots()
	local list = slotsInRoom(roomId)
	K.text(ui.body, { Name = "Hint", Size = UDim2.new(1, 0, 0, 22), Text = if #list > 0 then "바꾸고 싶은 가구를 고르세요 · 화면의 빛나는 가구를 눌러도 돼요" else "이 방에는 가구 자리가 없어요. 다른 방을 골라 보세요", TextColor3 = K.Color.sub, TextSize = 12, TextWrapped = true, LayoutOrder = nextOrder() })
	local grid = K.frame(ui.body, { Name = "SlotGrid", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	local bw = ui.bodyW or (ui.body.AbsoluteSize.X - 24)
	local cols = math.max(2, math.floor(bw / 150))
	local cw = math.floor((bw - (cols - 1) * 8) / cols)
	K.make("UIGridLayout", { CellSize = UDim2.fromOffset(cw, 84), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for _, s in list do
		local ci = catInfo(s.category)
		local b = K.make("TextButton", { Name = "Slot_" .. s.slotId, BackgroundColor3 = K.Color.card, AutoButtonColor = false, Text = "", LayoutOrder = nextOrder() })
		K.corner(b, 14)
		K.stroke(b, nil, 1, 0.86)
		K.text(b, { Name = "Icon", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(40, 32), Text = ci.icon, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center })
		K.text(b, { Name = "Cat", Position = UDim2.fromOffset(46, 10), Size = UDim2.new(1, -54, 0, 18), Text = ci.name, Font = K.Font.bold, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd })
		K.text(b, { Name = "Item", Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -20, 0, 32), Text = variantName(s.variantId), TextSize = 12, TextColor3 = K.Color.sub, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		K.pressable(b, { scale = 0.96 })
		hoverScale(b, 1)
		b.Activated:Connect(function()
			Interior.selectSlot(s.slotId)
		end)
		b.Parent = grid
		table.insert(cards, b)
	end
	setAction(nil, nil, string.format("⭐ 인테리어 점수 %d · 편안함 +%d", data.decor or 0, data.comfort or 0), nil, nil, false, nil, nil)
	ui.priceL.Visible = true
	ui.priceL.Text = "가구 자리 " .. #list .. "곳"
end

-- the catalog of a slot ---------------------------------------------------------------------------
local function variantCard(parent: Instance, s: any, id: any, w: number, h: number, rowStyle: boolean?)
	local f = id and G.FURNITURE[id] or nil
	local selected = pick ~= nil and pick.id == id
	local placed = (id == false and not s.variantId) or (id ~= false and id == s.variantId)
	local b = K.make("TextButton", { Name = "Card_" .. (if id then tostring(id) else "default"), Size = if rowStyle then UDim2.new(1, 0, 0, h) else UDim2.fromOffset(w, h), BackgroundColor3 = K.Color.card, AutoButtonColor = false, Text = "", LayoutOrder = nextOrder() })
	K.corner(b, 14)
	local st = K.stroke(b, if selected then K.Color.gold else nil, if selected then 2 else 1, if selected then 0 else 0.86)
	local _ = st
	K.pad(b, 8, 8, 8, 8)
	local cols = if f then { color3(f.main), color3(f.accent), color3(f.detail or f.accent) } else { K.Color.card2, K.Color.card3 }
	local inner: Frame
	local row: Frame
	if rowStyle then
		-- compact row (landscape): swatch tile | name + pills | price
		local sw = swatch(b, cols, h - 16, catInfo(s.category).icon)
		sw.Size = UDim2.fromOffset(h - 16, h - 16)
		inner = K.frame(b, { Name = "Inner", Position = UDim2.fromOffset(h - 6, 0), Size = UDim2.new(1, -(h - 6), 1, 0) })
		K.list(inner, false, 2)
		K.text(inner, { Name = "Name", Size = UDim2.new(1, 0, 0, 20), Text = if f then f.name else "기본 가구 (옵션)", Font = K.Font.bold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })
		row = K.frame(inner, { Name = "Pills", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3 })
		K.list(row, true, 4)
	else
		inner = K.frame(b, { Name = "Inner", Size = UDim2.fromScale(1, 1) })
		K.list(inner, false, 4)
		local sw = swatch(inner, cols, math.floor(h * 0.34), catInfo(s.category).icon)
		sw.LayoutOrder = 1
		K.text(inner, { Name = "Name", Size = UDim2.new(1, 0, 0, 30), Text = if f then f.name else "기본 가구 (옵션)", Font = K.Font.bold, TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2 })
		row = K.frame(inner, { Name = "Pills", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3 })
		K.list(row, true, 4)
	end
	if f then
		local sty = G.FURNITURE_STYLES[f.style]
		pillLabel(row, sty and sty.name or f.style, color3(sty and sty.color, K.Color.cyan), 1)
		pillLabel(row, "⭐+" .. f.decor, K.Color.gold, 2)
	else
		pillLabel(row, "무료", K.Color.green, 1)
	end
	local price = K.text(inner, { Name = "Price", Size = UDim2.new(1, 0, 0, 18), Font = K.Font.bold, TextSize = 13, LayoutOrder = 4 })
	if placed then
		price.Text = "배치됨 ✓"
		price.TextColor3 = K.Color.green
	elseif f and storageCount(id) > 0 then
		price.Text = "창고 " .. storageCount(id) .. "개"
		price.TextColor3 = K.Color.green
	elseif f then
		price.Text = won(f.price)
		price.TextColor3 = K.Color.gold
	else
		price.Text = "되돌리기"
		price.TextColor3 = K.Color.sub
	end
	K.pressable(b, { scale = 0.96, veil = false })
	hoverScale(b, if selected then 1.03 else 1)
	b.Activated:Connect(function()
		if mode ~= "edit" then
			return
		end
		pick = { id = id }
		pickRot = if id == s.variantId or (id == false and not s.variantId) then (s.rot or 0) else 0
		render()
	end)
	b.Parent = parent
	table.insert(cards, b)
	return b
end

local function renderCatalog()
	local s = slotData(selSlot)
	if not s then
		selSlot = nil
		renderSlots()
		return
	end
	local ci = catInfo(s.category)
	-- header: back + slot title
	local head = K.frame(ui.body, { Name = "SlotHead", Size = UDim2.new(1, 0, 0, TAP), LayoutOrder = nextOrder() })
	local back = K.Button(head, { name = "BackToSlots", text = "◀", style = "secondary", size = UDim2.fromOffset(TAP, TAP - 4), onClick = function()
		Interior.selectSlot(nil)
	end })
	back.Position = UDim2.fromOffset(0, 2)
	K.text(head, { Name = "Title", Position = UDim2.fromOffset(TAP + 10, 4), Size = UDim2.new(1, -TAP - 12, 0, 24), Text = ci.icon .. " " .. ci.name, Font = K.Font.bold, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd })
	K.text(head, { Name = "Now", Position = UDim2.fromOffset(TAP + 10, 28), Size = UDim2.new(1, -TAP - 12, 0, 20), Text = "지금: " .. variantName(s.variantId), TextSize = 12, TextColor3 = K.Color.sub, TextTruncate = Enum.TextTruncate.AtEnd })
	-- category chips (8 groups): the slot's group selected; another group jumps to a slot that takes it
	local chips = Instance.new("ScrollingFrame")
	chips.Name = "Categories"
	chips.Size = UDim2.new(1, 0, 0, TAP)
	chips.BackgroundTransparency = 1
	chips.BorderSizePixel = 0
	chips.ScrollBarThickness = 0
	chips.ScrollingDirection = Enum.ScrollingDirection.X
	chips.AutomaticCanvasSize = Enum.AutomaticSize.X
	chips.CanvasSize = UDim2.new()
	chips.LayoutOrder = nextOrder()
	chips.Parent = ui.body
	K.list(chips, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local myGroup = groupOfCategory(s.category)
	for _, g in HS.CATEGORY_GROUPS do
		local has = false
		for _, other in data.slots or {} do
			local og = groupOfCategory(other.category)
			if og and og.id == g.id then
				has = true
				break
			end
		end
		chip(chips, "Cat_" .. g.id, g.icon .. " " .. g.name, myGroup ~= nil and myGroup.id == g.id, has, function()
			Interior.jumpToGroup(g.id)
		end, K.Color.gold)
	end
	if pick == nil then
		pick = { id = if s.variantId then s.variantId else false }
		pickRot = s.rot or 0
	end
	-- variant cards: a grid in portrait, compact rows in landscape (short screens)
	local grid = K.frame(ui.body, { Name = "Catalog", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	local bw = ui.bodyW or (ui.body.AbsoluteSize.X - 24)
	if portrait then
		local cols = math.max(2, math.floor(bw / 128))
		local cw = math.floor((bw - (cols - 1) * 8) / cols)
		local chH = math.max(168, math.floor(cw * 1.3))
		K.make("UIGridLayout", { CellSize = UDim2.fromOffset(cw, chH), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		variantCard(grid, s, false, cw, chH)
		for _, v in G.furnitureFor(s.category) do
			variantCard(grid, s, v.id, cw, chH)
		end
	else
		K.list(grid, false, 6)
		variantCard(grid, s, false, bw, 72, true)
		for _, v in G.furnitureFor(s.category) do
			variantCard(grid, s, v.id, bw, 72, true)
		end
	end
	-- action bar for the pick
	local canRot = s.canRotate == true
	local isCurrent = (pick.id == false and not s.variantId) or (pick.id ~= false and pick.id == s.variantId)
	local rotFn: any = nil
	if canRot then
		local isDefault = pick.id == false
		local nextR = HS.nextRotation(true, isDefault, s.w or 2, s.d or 2, pickRot)
		if nextR ~= pickRot then
			rotFn = function()
				pickRot = nextR
				render()
			end
		end
	end
	if isCurrent then
		local rotChanged = pickRot ~= (s.rot or 0)
		setAction(nil, if rotChanged then "회전 · 무료" else variantName(pick.id), if rotChanged then string.format("%d° 돌려서 놓아요", pickRot * 90) else "지금 놓여 있는 가구예요" .. (if canRot then " · ⟳로 돌려 보세요" else ""), if rotChanged then "회전 적용하기" else "배치됨 ✓", "secondary", rotChanged, function()
			busy = true
			C.act("rotateSlot", { slotId = s.slotId, rot = pickRot })
			render()
		end, rotFn)
		if rotChanged then
			showGhost(s.slotId, pick.id, pickRot)
		else
			clearGhost()
		end
	elseif pick.id == false then
		local refund = if s.variantId then G.furnitureResale(s.variantId) else 0
		setAction(nil, "기본 가구 · 무료", "지금 가구는 창고에 보관돼요" .. (if refund > 0 then string.format(" (팔면 +%s)", won(refund)) else ""), "기본 가구로 되돌리기", "secondary", true, function()
			busy = true
			C.act("resetSlot", { slotId = s.slotId })
			render()
		end, nil)
		clearGhost()
	else
		local f = G.FURNITURE[pick.id]
		local owned = storageCount(pick.id) > 0
		local refund = if s.variantId then G.furnitureResale(s.variantId) else 0
		local price = if owned then 0 else f.price
		local afford = owned or bank() + refund >= price
		local sub = string.format("%s · ⭐+%d", G.FURNITURE_STYLES[f.style] and G.FURNITURE_STYLES[f.style].name or "", f.decor)
		if refund > 0 then
			sub ..= string.format(" · 기존 가구 50%% 환불 +%s", won(refund))
		end
		if not afford then
			sub = string.format("통장 잔액이 부족해요 (통장 %s)", won(bank()))
		end
		setAction(price, nil, sub, if owned then "창고에서 꺼내 배치" else "구매하고 배치", if owned then "success" else "gold", afford, function()
			busy = true
			C.act("placeFurniture", { slotId = s.slotId, variantId = pick.id, rot = pickRot, sellOld = true })
			render()
		end, rotFn)
		showGhost(s.slotId, pick.id, pickRot)
	end
	drawHighlights()
end

-- theme tab ---------------------------------------------------------------------------------------------
local function renderThemes()
	local r = roomData(roomId)
	if not r then
		K.text(ui.body, { Size = UDim2.new(1, 0, 0, 40), Text = "꾸밀 수 있는 방이 없어요", TextColor3 = K.Color.sub, LayoutOrder = nextOrder() })
		setAction(nil, nil, "", nil, nil, false, nil, nil)
		return
	end
	local kinds = r.kinds or {}
	if not kinds[themeKind] then
		for _, k in HS.THEME_KINDS do
			if kinds[k] then
				themeKind = k
				break
			end
		end
	end
	local row = K.frame(ui.body, { Name = "Kinds", Size = UDim2.new(1, 0, 0, TAP), LayoutOrder = nextOrder() })
	K.list(row, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for _, k in HS.THEME_KINDS do
		local info = HS.THEME_KIND_NAMES[k]
		chip(row, "Kind_" .. k, info.icon .. " " .. info.name, themeKind == k, kinds[k] == true, function()
			themeKind = k
			themePick = nil
			clearThemePreview()
			render()
		end, K.Color.gold)
	end
	if not kinds[themeKind] then
		K.text(ui.body, { Size = UDim2.new(1, 0, 0, 40), Text = "이 방은 타일 마감이라 조명만 바꿀 수 있어요", TextColor3 = K.Color.sub, TextWrapped = true, LayoutOrder = nextOrder() })
		setAction(nil, nil, "", nil, nil, false, nil, nil)
		return
	end
	local current = (r.theme and r.theme[themeKind]) or false
	local orderIds, defs = HS.themeCatalog(themeKind)
	local grid = K.frame(ui.body, { Name = "Swatches", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	local bw = ui.bodyW or (ui.body.AbsoluteSize.X - 24)
	local cols = math.max(2, math.floor(bw / 120))
	local cw = math.floor((bw - (cols - 1) * 8) / cols)
	K.make("UIGridLayout", { CellSize = UDim2.fromOffset(cw, 132), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local ids = { "default" }
	for _, id in orderIds do
		table.insert(ids, id)
	end
	for _, id in ids do
		local def = defs[id]
		local isCur = (id == "default" and not current) or id == current
		local sel = themePick == id
		local b = K.make("TextButton", { Name = "Theme_" .. id, BackgroundColor3 = K.Color.card, AutoButtonColor = false, Text = "", LayoutOrder = nextOrder() })
		K.corner(b, 14)
		K.stroke(b, if sel then K.Color.gold else nil, if sel then 2 else 1, if sel then 0 else 0.86)
		K.pad(b, 8, 8, 8, 8)
		local inner = K.frame(b, { Size = UDim2.fromScale(1, 1) })
		K.list(inner, false, 4)
		local sw = swatch(inner, if def then { color3(def.color), color3(def.color):Lerp(Color3.new(0, 0, 0), 0.18) } else { K.Color.card2, K.Color.card3 }, 46, if def then nil else "↺")
		sw.LayoutOrder = 1
		if def and def.material then
			K.text(sw, { Position = UDim2.fromOffset(6, 28), Size = UDim2.new(1, -12, 0, 14), Text = def.material, TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Font = K.Font.bold })
		end
		K.text(inner, { Name = "Name", Size = UDim2.new(1, 0, 0, 30), Text = if def then def.name else "기본 디자인", Font = K.Font.bold, TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2 })
		local priceL = K.text(inner, { Name = "Price", Size = UDim2.new(1, 0, 0, 18), Font = K.Font.bold, TextSize = 12, LayoutOrder = 3 })
		if isCur then
			priceL.Text = "적용됨 ✓"
			priceL.TextColor3 = K.Color.green
		elseif def then
			priceL.Text = won(HS.themePrice(themeKind, id, data.tierKey, r.id))
			priceL.TextColor3 = K.Color.gold
		else
			priceL.Text = "무료"
			priceL.TextColor3 = K.Color.sub
		end
		K.pressable(b, { scale = 0.96, veil = false })
		hoverScale(b, if sel then 1.03 else 1)
		b.Activated:Connect(function()
			if mode ~= "edit" then
				return
			end
			themePick = id
			previewTheme(r.id, themeKind, id)
			render()
		end)
		b.Parent = grid
		table.insert(cards, b)
	end
	if themePick == nil then
		setAction(nil, nil, string.format("%s %s · 지금: %s", r.name, HS.THEME_KIND_NAMES[themeKind].name, if current then (defs[current] and defs[current].name or current) else "기본 디자인"), nil, nil, false, nil, nil)
		ui.priceL.Visible = true
		ui.priceL.Text = "디자인을 골라 미리 보세요"
		return
	end
	local isCur = (themePick == "default" and not current) or themePick == current
	local def = defs[themePick]
	local price = if themePick == "default" then 0 else HS.themePrice(themeKind, themePick, data.tierKey, r.id)
	local afford = bank() >= price
	local sub = if def then string.format("%s · ⭐+%d", def.desc or "", def.decor or 0) else "처음 디자인으로 되돌려요 (무료)"
	if not afford then
		sub = string.format("통장 잔액이 부족해요 (통장 %s)", won(bank()))
	end
	setAction(price, nil, sub, if isCur then "적용됨 ✓" elseif themePick == "default" then "기본으로 되돌리기" else "시공하기", if isCur then "secondary" else "gold", (not isCur) and afford, function()
		busy = true
		C.act("setTheme", { room = r.id, kind = themeKind, id = themePick })
		render()
	end, nil)
end

-- tour mode ------------------------------------------------------------------------------------------
local function renderTour()
	local r = roomData(roomId)
	local card = K.frame(ui.body, { Name = "TourCard", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, LayoutOrder = nextOrder() })
	K.corner(card, 14)
	K.pad(card, 12, 12, 10, 10)
	K.list(card, false, 4)
	local lines = {}
	if r and r.theme then
		for _, k in HS.THEME_KINDS do
			local id = r.theme[k]
			if id then
				local def = HS.themeDef(k, id)
				table.insert(lines, string.format("%s %s: %s", HS.THEME_KIND_NAMES[k].icon, HS.THEME_KIND_NAMES[k].name, def and def.name or id))
			end
		end
	end
	if #lines == 0 then
		table.insert(lines, if data.staged then "🏗️ 기본 마감 (입주 후 인테리어 가능)" else "🎨 기본 마감")
	end
	for i, line in lines do
		K.text(card, { Name = "Finish" .. i, Size = UDim2.new(1, 0, 0, 20), Text = line, TextSize = 13, LayoutOrder = i })
	end
	for _, s in slotsInRoom(roomId) do
		local ci = catInfo(s.category)
		local f = s.variantId and G.FURNITURE[s.variantId]
		local row = K.frame(ui.body, { Name = "Piece_" .. s.slotId, Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 0, BackgroundColor3 = K.Color.card, LayoutOrder = nextOrder() })
		K.corner(row, 12)
		K.text(row, { Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(42, 48), Text = ci.icon, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center })
		K.text(row, { Position = UDim2.fromOffset(46, 4), Size = UDim2.new(1, -56, 0, 20), Text = if f then f.name else (ci.name .. " (기본)"), Font = K.Font.bold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
		local sty = f and G.FURNITURE_STYLES[f.style]
		K.text(row, { Position = UDim2.fromOffset(46, 24), Size = UDim2.new(1, -56, 0, 18), Text = if f then string.format("%s · ⭐+%d", sty and sty.name or "", f.decor) else "집에 딸린 옵션 가구", TextSize = 11, TextColor3 = K.Color.sub })
		table.insert(cards, row)
	end
	if data.staged then
		local l = data.listing or {}
		local priceText = if l.kind == "rent" then string.format("월세 하루 %s", won(l.rentPerDay or 0)) else string.format("매매 %s", won(l.price or 0))
		setAction(nil, priceText, if l.kind == "rent" then string.format("보증금 %s", won(l.deposit or 0)) else string.format("관리비 하루 %s", won(l.upkeepPerDay or 0)), "📝 계약 문의", "primary", true, function()
			if C.listingCard then
				C.listingCard(data.listingId)
			end
		end, nil)
	else
		setAction(nil, string.format("⭐ 인테리어 %d점", data.decor or 0), string.format("%s님의 집 · 편안함 +%d", data.ownerName or "", data.comfort or 0), "👍 인테리어 칭찬하기", "gold", not busy, function()
			C.act("compliment", {})
			busy = true
			task.delay(2, function()
				busy = false
				if isOpen then
					render()
				end
			end)
			render()
		end, nil)
	end
end

render = function()
	if not isOpen or not gui or not data then
		return
	end
	setTopBar()
	clearBody()
	ui.tabs.Visible = mode == "edit"
	ui.bodyHolder.Position = UDim2.fromOffset(0, if mode == "edit" then TAP + 8 else 8)
	ui.bodyHolder.Size = UDim2.new(1, 0, 1, -(if mode == "edit" then TAP + 8 else 8) - 80)
	for name, b in ui.tabButtons do
		local sel = name == tab
		local pill = b:FindFirstChild("Pill")
		if pill then
			(pill :: Frame).BackgroundColor3 = if sel then K.Color.cyan else K.Color.card
			local lbl = pill:FindFirstChild("Label")
			if lbl then
				(lbl :: TextLabel).TextColor3 = if sel then K.Color.onAccent else K.Color.text
			end
		end
	end
	if mode ~= "edit" then
		clearGhost()
		renderTour()
		drawHighlights()
	elseif tab == "theme" then
		clearGhost()
		hideHighlights()
		renderThemes()
	elseif selSlot then
		renderCatalog()
	else
		clearGhost()
		renderSlots()
		drawHighlights()
	end
	if #cards > 0 and not ui.staggered then
		ui.staggered = true
		pcall(K.stagger, cards)
	end
end

-------------------------------------------------------------------------------------------------
-- Selection API
-------------------------------------------------------------------------------------------------
function Interior.selectRoom(id: string)
	if not roomData(id) then
		return
	end
	roomId = id
	selSlot = nil
	pick = nil
	themePick = nil
	clearGhost()
	clearThemePreview()
	ui.staggered = false
	focusRoom(id)
	renderRooms()
	render()
end

function Interior.selectSlot(id: string?)
	selSlot = id
	pick = nil
	pickRot = 0
	clearGhost()
	ui.staggered = false
	if id then
		local s = slotData(id)
		local r = s and roomOfSlot(s)
		if r and r ~= roomId then
			roomId = r
			renderRooms()
		end
		local rd = roomData(roomId)
		if rd and typeof(rd.center) == "Vector3" then
			cam.bounds = { center = rd.center, size = rd.size }
		end
		focusSlot(id)
	else
		focusRoom(roomId)
	end
	render()
end

-- A category chip of another group: the nearest slot that takes it (this room first).
function Interior.jumpToGroup(groupId: string)
	local best: any = nil
	for _, s in data.slots or {} do
		local g = groupOfCategory(s.category)
		if g and g.id == groupId then
			if roomOfSlot(s) == roomId then
				best = s
				break
			end
			best = best or s
		end
	end
	if best then
		Interior.selectSlot(best.slotId)
	else
		C.toast("info", "가구 자리", "이 집에는 그 가구를 둘 자리가 없어요")
	end
end

-- screen tap in the 3D view: the nearest slot of the room on screen
local function pickAt(pos: Vector2)
	if not data or mode ~= "edit" or tab ~= "furniture" then
		return
	end
	local camObj = workspace.CurrentCamera
	if not camObj then
		return
	end
	local best, bestD = nil, 90
	for _, s in data.slots or {} do
		local geo = geometry(s.slotId)
		if geo then
			local p, on = camObj:WorldToViewportPoint((geo.frame * CFrame.new(0, math.min(geo.h, 6) * 0.45, 0)).Position)
			if on and p.Z > 0 then
				local d = (Vector2.new(p.X, p.Y) - pos).Magnitude
				-- slots of the room win ties
				if roomOfSlot(s) ~= roomId then
					d += 30
				end
				if d < bestD then
					best, bestD = s.slotId, d
				end
			end
		end
	end
	if best and best ~= selSlot then
		pcall(K.feedback, "tap")
		Interior.selectSlot(best)
	end
end

local function overUI(pos: Vector2): boolean
	for _, f in { ui.top, ui.rooms, ui.sheet } do
		if f and f.Visible then
			local a, s = f.AbsolutePosition, f.AbsoluteSize
			if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
				return true
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- Building the GUI
-------------------------------------------------------------------------------------------------
local function build()
	local old = C.playerGui:FindFirstChild("GwangalliInterior")
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GwangalliInterior"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.DisplayOrder = 16
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false
	g:SetAttribute("HideGwangalliHUD", true)
	g.Parent = C.playerGui
	gui = g

	-- top bar
	local top = K.frame(g, { Name = "TopBar", BackgroundTransparency = 0.1, BackgroundColor3 = K.Color.glass })
	K.corner(top, 16)
	K.stroke(top, nil, 1, 0.84)
	ui.top = top
	local close = K.Button(top, { name = "InteriorClose", text = "✕", style = "secondary", size = UDim2.fromOffset(TAP, 46), onClick = function()
		Interior.close()
	end })
	close.AnchorPoint = Vector2.new(0, 0.5)
	close.Position = UDim2.new(0, 4, 0.5, 0)
	ui.title = K.text(top, { Name = "Title", Position = UDim2.fromOffset(TAP + 14, 6), Size = UDim2.new(1, -TAP - 180, 0, 22), Font = K.Font.bold, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd })
	ui.sub = K.text(top, { Name = "Sub", Position = UDim2.fromOffset(TAP + 14, 28), Size = UDim2.new(1, -TAP - 180, 0, 18), TextSize = 12, TextColor3 = K.Color.sub, TextTruncate = Enum.TextTruncate.AtEnd })
	local right = K.frame(top, { Name = "Right", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(170, 46) })
	K.list(right, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local decor = K.text(right, { Name = "Decor", Size = UDim2.fromOffset(64, 34), BackgroundTransparency = 0.3, BackgroundColor3 = Color3.fromRGB(70, 54, 14), Text = "⭐ 0", Font = K.Font.bold, TextSize = 13, TextColor3 = K.Color.gold, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
	K.corner(decor, 17)
	ui.decor = decor
	local money = K.frame(right, { Name = "Money", Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.3, BackgroundColor3 = K.Color.card2, LayoutOrder = 2 })
	K.corner(money, 17)
	K.pad(money, 10, 10, 0, 0)
	ui.money = money
	ui.moneyL = K.text(money, { Name = "Bank", Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = "0원", Font = K.Font.bold, TextSize = 13, TextColor3 = K.Color.text })

	-- room chips
	local rooms = Instance.new("ScrollingFrame")
	rooms.Name = "Rooms"
	rooms.BackgroundTransparency = 1
	rooms.BorderSizePixel = 0
	rooms.ScrollBarThickness = 0
	rooms.ScrollingDirection = Enum.ScrollingDirection.X
	rooms.AutomaticCanvasSize = Enum.AutomaticSize.X
	rooms.CanvasSize = UDim2.new()
	rooms.Parent = g
	ui.rooms = rooms
	ui.roomsList = rooms
	K.list(rooms, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

	-- sheet
	local sheet = K.frame(g, { Name = "Sheet", BackgroundTransparency = 0.06, BackgroundColor3 = K.Color.glass, ClipsDescendants = true })
	K.corner(sheet, 20)
	K.stroke(sheet, nil, 1, 0.84)
	ui.sheet = sheet
	local tabs = K.frame(sheet, { Name = "Tabs", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, TAP) })
	K.list(tabs, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	ui.tabs = tabs
	ui.tabButtons = {}
	ui.storage = chip(tabs, "Tab_storage", "📦", false, true, function()
		Interior.close()
		if C.openLegacy then
			C.openLegacy("storage")
		end
	end)
	ui.storage.LayoutOrder = 99
	for _, t in { { "furniture", "🛋️ 가구" }, { "theme", "🎨 벽지·바닥·조명" } } do
		ui.tabButtons[t[1]] = chip(tabs, "Tab_" .. t[1], t[2], false, true, function()
			if tab ~= t[1] then
				tab = t[1]
				pick = nil
				themePick = nil
				clearGhost()
				clearThemePreview()
				ui.staggered = false
				if tab == "furniture" and selSlot then
					focusSlot(selSlot)
				else
					focusRoom(roomId)
				end
				render()
			end
		end)
	end
	local holder = K.frame(sheet, { Name = "BodyHolder", Position = UDim2.fromOffset(0, TAP + 8), Size = UDim2.new(1, 0, 1, -TAP - 88) })
	ui.bodyHolder = holder
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = holder
	K.pad(body, 12, 12, 2, 12)
	K.list(body, false, 8)
	ui.body = body
	-- action bar
	local action = K.frame(sheet, { Name = "ActionBar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 80), BackgroundTransparency = 0, BackgroundColor3 = K.Color.glass2 })
	K.stroke(action, nil, 1, 0.9)
	ui.action = action
	ui.priceL = K.text(action, { Name = "Price", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(0.5, -14, 0, 26), Font = K.Font.bold, TextSize = 19, TextScaled = true, TextColor3 = K.Color.gold, Text = "" })
	K.make("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 12 }, ui.priceL)
	ui.subL = K.text(action, { Name = "Sub", Position = UDim2.fromOffset(14, 38), Size = UDim2.new(0.5, -14, 0, 32), TextSize = 11, TextColor3 = K.Color.sub, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	local btns = K.frame(action, { Name = "Buttons", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0.5, -6, 0, TAP) })
	K.list(btns, true, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	ui.actionButtons = btns
	ui.rotate = K.Button(btns, { name = "ActionRotate", text = "⟳", style = "secondary", size = UDim2.fromOffset(TAP, TAP), textSize = 22, order = 1, onClick = function()
		if ui.rotateFn then
			ui.rotateFn()
		end
	end })

	local probe = K.frame(g, { Name = "Probe", Size = UDim2.fromScale(1, 1), Active = false })
	ui.probe = probe
	local function relayout()
		if isOpen then
			layout()
			render()
		end
	end
	probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	local function watchCam()
		local c = workspace.CurrentCamera
		if c then
			c:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(relayout)
			end)
		end
	end
	watchCam()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCam)
	layout()
end

-------------------------------------------------------------------------------------------------
-- Input (connected while open)
-------------------------------------------------------------------------------------------------
local function connectInput()
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not isOpen then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			Interior.close()
			return
		end
		local t = input.UserInputType
		if processed or (t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1) then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if overUI(pos) then
			return
		end
		if cam.drag then
			cam.drag.multi = true
			return
		end
		cam.drag = { input = input, start = pos, last = pos, t0 = os.clock(), moved = 0 }
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not isOpen or not cam.vals then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			local v = cam.vals
			v.r.Value = math.clamp(v.r.Value - input.Position.Z * 0.8, 4, 22)
			return
		end
		local d = cam.drag
		if not d or d.multi then
			return
		end
		if (t == Enum.UserInputType.Touch and input == d.input) or t == Enum.UserInputType.MouseMovement then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - d.last
			d.last = pos
			d.moved += delta.Magnitude
			if d.moved > 10 then
				local v = cam.vals
				v.yaw.Value -= delta.X * 0.009
				v.elev.Value = math.clamp(v.elev.Value + delta.Y * 0.006, math.rad(6), math.rad(70))
				cam.spinAfter = os.clock() + 5
			end
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = cam.drag
		if not d then
			return
		end
		local t = input.UserInputType
		if input == d.input or t == Enum.UserInputType.MouseButton1 then
			cam.drag = nil
			if not d.multi and d.moved <= 12 and os.clock() - d.t0 < 0.5 then
				pickAt(d.start)
			end
		end
	end))
	table.insert(conns, UserInputService.TouchPinch:Connect(function(_touches: { Vector2 }, scale: number, _velocity: number, state: Enum.UserInputState, processed: boolean)
		if not isOpen or processed or not cam.vals then
			return
		end
		if state == Enum.UserInputState.Begin then
			cam.pinchR = cam.vals.r.Value
		elseif state == Enum.UserInputState.Change and cam.pinchR then
			cam.vals.r.Value = math.clamp(cam.pinchR / math.max(0.2, scale), 4, 22)
		end
	end))
	table.insert(conns, player:GetAttributeChangedSignal("Bank"):Connect(function()
		if isOpen and mode == "edit" then
			setTopBar()
		end
	end))
end

-------------------------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------------------------
local function indexModel()
	slotIdx = {}
	local m = model
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Model")) and d:HasTag(G.HomeTags.Slot) then
			local id = d:GetAttribute("SlotId")
			if type(id) == "string" and not slotIdx[id] then
				slotIdx[id] = d
			end
		end
	end
	collectThemeParts()
end

function Interior.init(ctx: any)
	C = ctx
	K, G = ctx.K, ctx.G
	HS = G.HOMES
end

function Interior.available(): boolean
	return C ~= nil and HS ~= nil
end

function Interior.isOpen(): boolean
	return isOpen
end

function Interior.mode(): string?
	return if isOpen then mode else nil
end

-- payload from HomeState "interior"
function Interior.open(payload: any)
	if not Interior.available() or type(payload) ~= "table" then
		return
	end
	if not gui then
		build()
	end
	local wasOpen = isOpen
	data = payload
	mode = if payload.mode == "edit" then "edit" else "tour"
	if not wasOpen then
		tab = "furniture"
		selSlot = nil
		pick = nil
		themePick = nil
		busy = false
	end
	-- model
	model = nil
	local m = C.state and C.state.model
	if m and m.Parent and m.Name == payload.modelName then
		model = m
	else
		local folder = workspace:FindFirstChild(G.HOME_INSTANCE_FOLDER)
		local found = folder and folder:FindFirstChild(payload.modelName or "")
		if found and found:IsA("Model") then
			model = found
		end
	end
	indexModel()
	-- the room the player stands in, else the first one
	if not roomId or not roomData(roomId) then
		roomId = nil
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local p = hrp and (hrp :: BasePart).Position
		if p then
			for _, r in payload.rooms or {} do
				if typeof(r.center) == "Vector3" and typeof(r.size) == "Vector3" and math.abs(p.X - r.center.X) <= r.size.X / 2 and math.abs(p.Z - r.center.Z) <= r.size.Z / 2 and p.Y >= r.center.Y - 3 and p.Y <= r.center.Y + r.size.Y then
					roomId = r.id
					break
				end
			end
		end
		if not roomId and payload.rooms and payload.rooms[1] then
			roomId = payload.rooms[1].id
			for _, r in payload.rooms do
				if r.id == "living" or r.id == "main" then
					roomId = r.id
					break
				end
			end
		end
	end
	local g = gui :: ScreenGui
	if not wasOpen then
		isOpen = true
		g.Enabled = true
		pcall(C.setControls, false)
		if C.hideBar then
			pcall(C.hideBar, true)
		end
		camStart()
		connectInput()
		layout()
		-- sheet slides in from its edge, the top bar drops in
		ui.sheetShown = true
		ui.sheet.Position = ui.sheetAway
		tw(ui.sheet, 0.42, { Position = ui.sheetRest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		-- the ScreenGui is measured once enabled: lay out again on the next frame
		task.defer(function()
			if isOpen then
				layout()
				render()
			end
		end)
		local topRest = ui.top.Position
		ui.top.Position = topRest - UDim2.fromOffset(0, 70)
		tw(ui.top, 0.36, { Position = topRest })
		pcall(K.sound, "open")
		ui.staggered = false
	end
	focusRoom(roomId, false)
	renderRooms()
	render()
end

function Interior.close()
	if not isOpen then
		return
	end
	isOpen = false
	clearGhost()
	clearThemePreview()
	hideHighlights()
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	camStop()
	busy = false
	local g = gui
	if g then
		local away = ui.sheetAway
		tw(ui.sheet, 0.22, { Position = away }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(if reduced() then 0 else 0.23, function()
			if not isOpen and g then
				g.Enabled = false
			end
		end)
	end
	ui.sheetShown = false
	pcall(C.setControls, true)
	if C.hideBar then
		pcall(C.hideBar, false)
	end
end

-- HomeState "furniture" {slots, housing?}
function Interior.onFurniture(payload: any)
	if not isOpen or not data or type(payload) ~= "table" then
		return
	end
	if type(payload.slots) == "table" then
		data.slots = payload.slots
	end
	if type(payload.housing) == "table" then
		data.housing = payload.housing
		data.decor = payload.housing.decor or data.decor
		data.comfort = payload.housing.comfort or data.comfort
	end
	-- the server rebuilt a piece: the ghost / highlights point at new parts
	task.defer(function()
		if isOpen then
			indexModel()
			render()
		end
	end)
end

-- HomeState "themes" {rooms, decor}
function Interior.onThemes(payload: any)
	if not isOpen or not data or type(payload) ~= "table" then
		return
	end
	if type(payload.rooms) == "table" then
		data.rooms = payload.rooms
	end
	if mode == "edit" and type(payload.decor) == "number" then
		data.decor = payload.decor
	end
	themeSaved = {} -- the server's colours replaced the preview
	render()
end

-- HomeState "interiorResult" {ok, action, ...}
function Interior.onResult(payload: any)
	busy = false
	if not isOpen or type(payload) ~= "table" then
		return
	end
	if payload.ok then
		pcall(K.feedback, "success")
		if payload.action == "place" or payload.action == "rotate" then
			pick = nil
			clearGhost()
		elseif payload.action == "theme" then
			themePick = nil
			themeSaved = {}
		end
		if ui.primary then
			pcall(K.sheen, ui.action)
		end
	else
		pcall(K.feedback, "error")
		if payload.action == "theme" then
			clearThemePreview()
		end
	end
	render()
end

return Interior
