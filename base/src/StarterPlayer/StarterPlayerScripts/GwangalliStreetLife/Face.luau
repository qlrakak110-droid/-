-- GwangalliStreetLife/Face: facial expressions for the block-R15 pedestrian rigs (owner: npc_mind).
-- The rigs wear one face Decal (rbxasset://textures/face.png); an expression hides it and draws eyes,
-- brows, mouth and blush (no image uploads, no meshes) on a head-sized BillboardGui in front of the
-- face. The overlay is adorned to the rig's root (the root is what the street life moves; the head is
-- welded to it) at head height, pushed out of the face along the body's facing, and only shown while
-- the face looks toward the camera (from behind you see the back of the head). The default face comes
-- back when the expression times out.
--   Face.set(rig, expr, dur?)   expr: smile laugh angry annoyed shy scared sad wary smug surprised love
--                               drunk dizzy neutral (neutral / nil = the default face)
--   Face.clear(rig)
-- Cost: one BillboardGui per rig (kept with the pooled rig) and a per-frame offset update only for the
-- few faces that are showing an expression.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Face = {}

local INK = Color3.fromRGB(28, 22, 24)
local BLUSH = Color3.fromRGB(255, 120, 140)
local HEART = Color3.fromRGB(235, 40, 80)
local SKIN_T = 1 -- the overlay has no background: the head shows through

-- eyes: {w, h} frames or a glyph; brows: {angle L, angle R, y} or false; mouth glyph (+ size, angle)
local EXPR = {
	smile = { eye = "^", mouth = "◡", ms = 30 },
	laugh = { eyeL = ">", eyeR = "<", mouth = "▽", ms = 26, blush = 0.45 },
	angry = { eyes = { 11, 6 }, brows = { 24, -24, 33 }, mouth = "◠", ms = 28 },
	annoyed = { eyes = { 12, 5 }, brows = { 6, -6, 35 }, mouth = "~", ms = 30 },
	shy = { eye = "^", mouth = "ω", ms = 24, blush = 0.25 },
	scared = { eyes = { 13, 15 }, brows = { -20, 20, 25 }, mouth = "○", ms = 22 },
	sad = { eyes = { 8, 8 }, brows = { -18, 18, 31 }, mouth = "◠", ms = 26 },
	wary = { eyes = { 10, 7 }, browsLR = { { -12, 28 }, { 10, 34 } }, mouth = "—", ms = 22 },
	smug = { eyes = { 12, 5 }, mouth = "◡", ms = 22, ma = 14 },
	surprised = { eyes = { 12, 15 }, brows = { 0, 0, 22 }, mouth = "O", ms = 26 },
	love = { eye = "♥", eyeColor = HEART, mouth = "◡", ms = 30, blush = 0.3 },
	drunk = { eye = "~", mouth = "◡", ms = 26, blush = 0.1, ma = -8 },
	dizzy = { eye = "×", mouth = "o", ms = 24 },
}
Face.EXPR = EXPR

local active: { [any]: any } = {} -- rig -> face state while an expression shows
local loop: RBXScriptConnection? = nil

local function frame(parent: Instance, name: string, color: Color3, round: boolean): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Visible = false
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function glyph(parent: Instance, name: string): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Size = UDim2.fromScale(0.3, 0.3)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = INK
	t.Text = ""
	t.Visible = false
	t.Parent = parent
	return t
end

-- positions in the 0..1 face square
local function at(f: GuiObject, x: number, y: number)
	f.Position = UDim2.fromScale(x / 100, y / 100)
end
local function sized(f: GuiObject, w: number, h: number)
	f.Size = UDim2.fromScale(w / 100, h / 100)
end

local function headOf(rig: any): (number, number)
	-- head edge length and the head centre's height above the root (block R15: ~1.2 x scale, ~1.5 x scale)
	local s = rig.scale or 1
	local size = 1.2 * s
	pcall(function()
		size = rig.head.Size.X
	end)
	return size, 1.5 * s
end

local function build(rig: any): any?
	if not rig.root or not rig.head then
		return nil
	end
	local size, hy = headOf(rig)
	local bb = Instance.new("BillboardGui")
	bb.Name = "MindFace"
	bb.Size = UDim2.fromScale(size * 0.92, size * 0.92) -- studs: the face of the block head
	bb.LightInfluence = 0.5
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb.MaxDistance = 45
	bb.Enabled = false
	bb.Adornee = rig.root
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = SKIN_T
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Parent = bb
	local f = {
		gui = bb,
		canvas = canvas,
		eyeL = frame(canvas, "EyeL", INK, true),
		eyeR = frame(canvas, "EyeR", INK, true),
		browL = frame(canvas, "BrowL", INK, false),
		browR = frame(canvas, "BrowR", INK, false),
		blushL = frame(canvas, "BlushL", BLUSH, true),
		blushR = frame(canvas, "BlushR", BLUSH, true),
		gL = glyph(canvas, "GlyphL"),
		gR = glyph(canvas, "GlyphR"),
		mouth = glyph(canvas, "Mouth"),
		seq = 0,
		expr = nil,
		size = size,
		hy = hy,
		rig = rig,
	}
	at(f.eyeL, 34, 46)
	at(f.eyeR, 66, 46)
	at(f.gL, 34, 45)
	at(f.gR, 66, 45)
	sized(f.browL, 15, 3)
	sized(f.browR, 15, 3)
	sized(f.blushL, 13, 7)
	sized(f.blushR, 13, 7)
	at(f.blushL, 22, 60)
	at(f.blushR, 78, 60)
	at(f.mouth, 50, 72)
	sized(f.mouth, 44, 30)
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	bb.Parent = pg or rig.root
	rig.mindFace = f
	return f
end

local function decalOf(rig: any): Decal?
	local head = rig.head
	local d = head and head:FindFirstChild("face")
	return if d and d:IsA("Decal") then d else nil
end

-- per frame: out in front of the face, shown only when the face looks at the camera
local function step()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	for rig, f in active do
		local root = rig.root
		if not root or not root.Parent or not f.gui.Parent then
			active[rig] = nil
		else
			local cf = root.CFrame
			local look = cf.LookVector
			local head = cf.Position + Vector3.new(0, f.hy, 0)
			f.gui.StudsOffsetWorldSpace = Vector3.new(0, f.hy, 0) + look * (f.size * 0.5 + 0.06)
			local to = cp - head
			local m = to.Magnitude
			local facing = m > 0.01 and (to.X * look.X + to.Y * look.Y + to.Z * look.Z) / m > 0.2
			if f.gui.Enabled ~= facing then
				f.gui.Enabled = facing
				local d = decalOf(rig)
				if d then
					-- the default face shows from the side / behind, the expression from the front
					d.Transparency = if facing then 1 else 0
				end
			end
		end
	end
	if next(active) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

function Face.clear(rig: any)
	local f = rig and rig.mindFace
	if f then
		f.seq += 1
		f.expr = nil
		f.gui.Enabled = false
	end
	if rig then
		active[rig] = nil
	end
	local d = rig and decalOf(rig)
	if d and d.Transparency ~= 0 then
		d.Transparency = 0
	end
end

function Face.set(rig: any, expr: string?, dur: number?)
	if not rig or not rig.head or not rig.root then
		return
	end
	local def = expr and EXPR[expr]
	if not def then
		Face.clear(rig)
		return
	end
	local f = rig.mindFace
	if not f or not f.gui.Parent or f.rig ~= rig or f.gui.Adornee ~= rig.root then
		if f and f.gui then
			f.gui:Destroy()
		end
		f = build(rig)
		if not f then
			return
		end
	end
	f.size, f.hy = headOf(rig)
	f.gui.Size = UDim2.fromScale(f.size * 0.92, f.size * 0.92)
	f.seq += 1
	local seq = f.seq
	f.expr = expr
	-- eyes
	local glyphL = def.eyeL or def.eye
	local glyphR = def.eyeR or def.eye
	if glyphL then
		f.eyeL.Visible, f.eyeR.Visible = false, false
		f.gL.Visible, f.gR.Visible = true, true
		f.gL.Text, f.gR.Text = glyphL, glyphR
		local col = def.eyeColor or INK
		f.gL.TextColor3, f.gR.TextColor3 = col, col
		local gs = if glyphL == "♥" then 0.22 else 0.3
		f.gL.Size, f.gR.Size = UDim2.fromScale(gs, gs), UDim2.fromScale(gs, gs)
	else
		f.gL.Visible, f.gR.Visible = false, false
		local e = def.eyes or { 9, 11 }
		sized(f.eyeL, e[1], e[2])
		sized(f.eyeR, e[1], e[2])
		f.eyeL.Visible, f.eyeR.Visible = true, true
	end
	-- brows
	if def.brows then
		local b = def.brows
		f.browL.Visible, f.browR.Visible = true, true
		f.browL.Rotation, f.browR.Rotation = b[1], b[2]
		at(f.browL, 34, b[3])
		at(f.browR, 66, b[3])
	elseif def.browsLR then
		local l, r = def.browsLR[1], def.browsLR[2]
		f.browL.Visible, f.browR.Visible = true, true
		f.browL.Rotation, f.browR.Rotation = l[1], r[1]
		at(f.browL, 34, l[2])
		at(f.browR, 66, r[2])
	else
		f.browL.Visible, f.browR.Visible = false, false
	end
	-- blush
	local bl = def.blush
	f.blushL.Visible, f.blushR.Visible = bl ~= nil, bl ~= nil
	if bl then
		f.blushL.BackgroundTransparency, f.blushR.BackgroundTransparency = bl, bl
	end
	-- mouth
	f.mouth.Visible = true
	f.mouth.Text = def.mouth or "—"
	local ms = (def.ms or 24) / 100
	sized(f.mouth, 44 * ms / 0.26, 30 * ms / 0.26)
	f.mouth.Rotation = def.ma or 0
	active[rig] = f
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
	step()
	local t = math.clamp(tonumber(dur) or 4, 0.5, 30)
	task.delay(t, function()
		if f.seq == seq then
			Face.clear(rig)
		end
	end)
end

return Face
