--!strict
-- BowlingFX/Guide: the aim guide painted on the lane (client-only parts under the camera).
--   * ghost ball at the release point (the bowler's ball colour)
--   * the predicted path (BowlingShared.predict: the same hook rule the server applies): a dashed
--     cyan line through the oil, then a solid magenta -> gold curve after the break point
--   * a diamond on the target arrow the line crosses, a ring at the break point
--   * an entry ring at the head pin with a label: "1-3 포켓 ✓", "헤드핀 정면", "거터 위험!"
-- Parts are created once, moved with workspace:BulkMoveTo and only when an aim value changes.

local Guide = {}

local Shared: any = nil
local N = 26
local folder: Folder? = nil
local ghost: BasePart? = nil
local segs: { BasePart } = {}
local breakRing: BasePart? = nil
local target: BasePart? = nil
local entry: BasePart? = nil
local entryText: TextLabel? = nil

local CYAN = Color3.fromRGB(61, 214, 245)
local MAGENTA = Color3.fromRGB(255, 79, 163)
local GOLD = Color3.fromRGB(255, 194, 71)
local RED = Color3.fromRGB(255, 90, 95)
local GREEN = Color3.fromRGB(61, 220, 132)

function Guide.init(sharedModule: any)
	Shared = sharedModule
end

local function part(name: string, shape: Enum.PartType?, color: Color3, transparency: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(0.1, 0.02, 0.5)
	return p
end

local function ensure(): boolean
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end
	if folder and ghost then
		if folder.Parent ~= cam then
			folder.Parent = cam
		end
		return true
	end
	local f = Instance.new("Folder")
	f.Name = "BowlingAimGuide"
	local g = part("Ghost", Enum.PartType.Ball, CYAN, 0.4)
	g.Size = Vector3.new(0.72, 0.72, 0.72)
	g.Material = Enum.Material.SmoothPlastic
	g.Parent = f
	segs = {}
	for i = 1, N do
		local s = part("Seg", nil, CYAN, 0.3)
		s.Parent = f
		segs[i] = s
	end
	local br = part("Break", Enum.PartType.Cylinder, GOLD, 0.25)
	br.Size = Vector3.new(0.03, 0.55, 0.55)
	br.Parent = f
	local tg = part("Target", nil, CYAN, 0.1)
	tg.Size = Vector3.new(0.26, 0.03, 0.26)
	tg.Parent = f
	local en = part("Entry", Enum.PartType.Cylinder, GREEN, 0.3)
	en.Size = Vector3.new(0.03, 0.75, 0.75)
	en.Parent = f
	local bb = Instance.new("BillboardGui")
	bb.Name = "EntryLabel"
	bb.Size = UDim2.fromOffset(150, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Parent = en
	local bg = Instance.new("Frame")
	bg.Name = "Pill"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(15, 18, 31)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = bg
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 15
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = ""
	t.Parent = bg
	entryText = t
	f.Parent = cam
	folder, ghost, breakRing, target, entry = f, g, br, tg, en
	return true
end

-- o = { offset, angle, spin, lb, laneLength, laneWidth, ballR, bumpers, color }
function Guide.show(lf: CFrame, o: { [string]: any })
	if not Shared or not ensure() then
		return
	end
	local L = o.laneLength or 60.96
	local W = o.laneWidth or 3.5
	local pts, gutterAt = Shared.predict(o.offset, o.angle, o.spin, o.lb, 0.75, L, W, o.bumpers, N)
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local y = 0.03
	local hs = Shared.HookStart
	for i = 1, N do
		local s = segs[i]
		local a, b = pts[i], pts[i + 1]
		if not (a and b) then
			s.Transparency = 1
			continue
		end
		local A = (lf * CFrame.new(a[1], y, -a[2])).Position
		local B = (lf * CFrame.new(b[1], y, -b[2])).Position
		local mid = (A + B) / 2
		local l = (B - A).Magnitude
		if l < 1e-3 then
			s.Transparency = 1
			continue
		end
		s.Size = Vector3.new(0.12, 0.02, l + 0.04)
		local d = (a[2] + b[2]) / 2
		if gutterAt and d >= gutterAt then
			s.Color = RED
			s.Transparency = 0.25
		elseif d < hs then
			s.Color = CYAN
			s.Transparency = if i % 2 == 0 then 0.25 else 0.8 -- dashes through the oil
		else
			local u = math.clamp((d - hs) / math.max(L - hs, 1), 0, 1)
			s.Color = MAGENTA:Lerp(GOLD, u)
			s.Transparency = 0.2
		end
		table.insert(parts, s)
		table.insert(cfs, CFrame.lookAt(mid, B))
	end
	local g = ghost :: BasePart
	g.Color = o.color or CYAN
	g.Size = Vector3.new((o.ballR or 0.36) * 2, (o.ballR or 0.36) * 2, (o.ballR or 0.36) * 2)
	table.insert(parts, g)
	table.insert(cfs, lf * CFrame.new(o.offset, (o.ballR or 0.36) + 0.02, -0.9))
	-- break point (where the hook starts) on the predicted path
	local bx = o.offset
	for _, p in pts do
		if p[2] >= hs then
			bx = p[1]
			break
		end
	end
	local br = breakRing :: BasePart
	br.Transparency = if math.abs(o.spin) > 0.04 and not (gutterAt and gutterAt < hs) then 0.25 else 1
	table.insert(parts, br)
	table.insert(cfs, lf * CFrame.new(bx, y + 0.005, -hs) * CFrame.Angles(0, 0, math.pi / 2))
	-- target arrow crossing (diamond)
	local ax = Shared.arrowX(o.offset, o.angle)
	local tg = target :: BasePart
	table.insert(parts, tg)
	table.insert(cfs, lf * CFrame.new(ax, y + 0.01, -Shared.ArrowDist) * CFrame.Angles(0, math.pi / 4, 0))
	-- entry at the head pin
	local ex = Shared.entryX(pts, L)
	local pocket = Shared.pocket(ex, o.spin)
	local en = entry :: BasePart
	local txt = entryText :: TextLabel
	if gutterAt and gutterAt < L then
		en.Color = RED
		txt.Text = "거터 위험!"
		txt.TextColor3 = RED
	elseif pocket and string.find(pocket, "포켓", 1, true) then
		en.Color = GREEN
		txt.Text = pocket .. " ✓"
		txt.TextColor3 = GREEN
	elseif pocket then
		en.Color = GOLD
		txt.Text = pocket
		txt.TextColor3 = GOLD
	else
		en.Color = Color3.fromRGB(255, 176, 32)
		txt.Text = if ex > 0 then "오른쪽으로 빠짐" else "왼쪽으로 빠짐"
		txt.TextColor3 = Color3.fromRGB(255, 176, 32)
	end
	table.insert(parts, en)
	table.insert(cfs, lf * CFrame.new(math.clamp(ex, -W / 2, W / 2), y + 0.01, -L + 0.4) * CFrame.Angles(0, 0, math.pi / 2))
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	local f = folder :: Folder
	if f.Parent ~= workspace.CurrentCamera then
		f.Parent = workspace.CurrentCamera
	end
end

function Guide.hide()
	if folder then
		folder.Parent = nil
	end
end

function Guide.destroy()
	if folder then
		folder:Destroy()
	end
	folder, ghost, breakRing, target, entry, entryText = nil, nil, nil, nil, nil, nil
	segs = {}
end

return Guide
