-- GwangalliProgress/Fx: one-shot effects shared by the pops and the celebrations. Everything is pooled
-- and driven by TweenService (no per-frame code): confetti, expanding rings, coins flying into the
-- money chip, the short camera pull-back of a milestone.

local Players = game:GetService("Players")

local Fx = {}

local C: any = nil
local K: any = nil
local rng = Random.new()

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 194, 71),
	Color3.fromRGB(61, 214, 245),
	Color3.fromRGB(255, 79, 163),
	Color3.fromRGB(61, 220, 132),
	Color3.fromRGB(139, 108, 255),
	Color3.fromRGB(255, 255, 255),
}

local confettiPool: { Frame } = {}
local confettiFree: { Frame } = {}
local CONFETTI_MAX = 44
local ringPool: { Frame } = {}
local coinPool: { Frame } = {}

local function host(): Instance
	return C.fx
end

local function takeConfetti(): Frame?
	local f = table.remove(confettiFree)
	if f then
		return f
	end
	if #confettiPool >= CONFETTI_MAX then
		return nil
	end
	f = K.frame(host(), { Name = "Confetti", Size = UDim2.fromOffset(6, 10), BackgroundTransparency = 1, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 60, Visible = false })
	K.corner(f, 2)
	table.insert(confettiPool, f)
	return f
end

local function release(f: Frame)
	f.Visible = false
	table.insert(confettiFree, f)
end

-- Confetti burst from (x, y) in fx-gui pixels. count is reduced on struggling devices.
function Fx.confetti(x: number, y: number, count: number?, spread: number?)
	local n = count or 30
	if K.reduced() then
		n = math.min(n, 12)
	end
	local sp = spread or 160
	local met = C.Layout.metrics()
	local H = met.H or 400
	local W = met.W or 800
	for _ = 1, n do
		local f = takeConfetti()
		if not f then
			break
		end
		local w = rng:NextInteger(5, 8)
		f.Size = UDim2.fromOffset(w, rng:NextInteger(8, 13))
		f.BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)]
		f.BackgroundTransparency = 0
		f.Rotation = rng:NextNumber(0, 360)
		f.Position = UDim2.fromOffset(x + rng:NextNumber(-12, 12), y + rng:NextNumber(-6, 6))
		f.Visible = true
		local up = rng:NextNumber(30, 90)
		-- keep every piece on screen (8 px margin)
		local dx = math.clamp(rng:NextNumber(-sp, sp), 8 - x, W - 16 - x)
		local t1 = rng:NextNumber(0.28, 0.4)
		K.tween(f, t1, { Position = UDim2.fromOffset(x + dx * 0.55, y - up), Rotation = f.Rotation + rng:NextNumber(-180, 180) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fall = math.min(H * 0.42, rng:NextNumber(140, 260), math.max(20, H - 16 - (y - up)))
		local t2 = rng:NextNumber(1.0, 1.5)
		task.delay(t1, function()
			K.tween(f, t2, { Position = UDim2.fromOffset(x + dx, y - up + fall), Rotation = f.Rotation + rng:NextNumber(-360, 360), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(t2 + 0.05, release, f)
		end)
	end
end

-- 3 expanding rings at (x, y) in the given gui (default fx).
function Fx.rings(x: number, y: number, color: Color3?, parent: Instance?, size: number?)
	local col = color or K.Color.gold
	local maxS = size or 96
	for i = 1, 3 do
		local r = table.remove(ringPool)
		if not r then
			r = K.frame(nil, { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 59 })
			K.corner(r, UDim.new(0.5, 0))
			K.stroke(r, col, 2, 0.2)
		end
		r.Parent = parent or host()
		local st = r:FindFirstChildOfClass("UIStroke") :: UIStroke
		st.Color = col
		st.Transparency = 0.15
		r.Size = UDim2.fromOffset(12, 12)
		r.Position = UDim2.fromOffset(x, y)
		r.Visible = true
		local delay = (i - 1) * 0.09
		task.delay(delay, function()
			K.tween(r, 0.55, { Size = UDim2.fromOffset(maxS * (0.7 + i * 0.15), maxS * (0.7 + i * 0.15)) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			K.tween(st, 0.55, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.6, function()
				r.Visible = false
				table.insert(ringPool, r)
			end)
		end)
	end
end

-- n coins flying from (x0, y0) into (x1, y1) (the money chip's coin icon).
function Fx.coins(x0: number, y0: number, x1: number, y1: number, n: number?, parent: Instance?)
	local count = n or 6
	if K.reduced() then
		count = math.min(count, 3)
	end
	for i = 1, count do
		local c = table.remove(coinPool)
		if not c then
			c = K.frame(nil, { Name = "Coin", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 58 })
			K.corner(c, UDim.new(0.5, 0))
			K.gradient(c, K.Grad.gold, 120)
			K.stroke(c, Color3.fromRGB(255, 236, 170), 1, 0.3)
			K.text(c, { Name = "W", Size = UDim2.fromScale(1, 1), Text = "₩", TextSize = 11, Font = K.Font.heavy, TextColor3 = K.Color.onGold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 58 })
		end
		c.Parent = parent or host()
		c.Position = UDim2.fromOffset(x0 + rng:NextNumber(-20, 20), y0 + rng:NextNumber(-6, 6))
		c.BackgroundTransparency = 0
		c.Visible = true
		local midX = (x0 + x1) / 2 + rng:NextNumber(-30, 30)
		local midY = math.min(y0, y1) - rng:NextNumber(16, 40)
		local t0 = (i - 1) * 0.05
		task.delay(t0, function()
			K.tween(c, 0.22, { Position = UDim2.fromOffset(midX, midY) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.22, function()
				K.tween(c, 0.24, { Position = UDim2.fromOffset(x1, y1), BackgroundTransparency = 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.26, function()
					c.Visible = false
					table.insert(coinPool, c)
				end)
			end)
		end)
	end
end

-- Milestone camera pull-back: a short field-of-view widen and return (walking only; never while
-- driving or while another system scripts the camera).
local pulling = false
function Fx.pullBack()
	if pulling or K.reduced() then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		return
	end
	local fov0 = cam.FieldOfView
	if fov0 > 84 then
		return
	end
	pulling = true
	local wide = fov0 + 12
	K.tween(cam, 0.5, { FieldOfView = wide }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	task.delay(1.7, function()
		-- give the camera back only if nobody else changed it meanwhile
		if math.abs(cam.FieldOfView - wide) < 1 then
			K.tween(cam, 0.7, { FieldOfView = fov0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
		task.delay(0.75, function()
			pulling = false
		end)
	end)
end

function Fx.init(c: any)
	C = c
	K = c.K
end

return Fx
