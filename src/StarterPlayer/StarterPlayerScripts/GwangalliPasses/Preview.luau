-- GwangalliPasses/Preview (client): 3D car previews for the 차고 cards (ViewportFrame).
-- Source: the server's light copies in ReplicatedStorage.GwangalliPassesPreviews (exact templates incl. the
-- VIP / 오프로더 kits); for the two part-built bodies a local CarBodies build is the fallback; else a glyph tile.
--   Preview.mount(parent, car, paintId) -> api { setPaint(id), destroy() }
-- One RenderStepped turns every visible preview slowly (static with reduced motion).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Preview = {}

local ctx: any
local P: any, K: any, Cars: any, CarBodies: any, GS: any
local live: { [any]: any } = {}
local conn: RBXScriptConnection? = nil

local function sourceModel(car: any): Model?
	local f = ReplicatedStorage:FindFirstChild(P.PREVIEWS)
	local m = f and f:FindFirstChild(car.kind)
	if m and m:IsA("Model") then
		return m:Clone()
	end
	if car.body then
		local ok, built = pcall(CarBodies.build, car.body, Cars.paintColor(Cars.paint(car.paint)), car.glow)
		if ok then
			return built
		end
	end
	return nil
end

local function paint(model: Model, paintId: string)
	local p = Cars.paint(paintId)
	local col = Cars.paintColor(p)
	if GS and type(GS.paintParts) == "function" then
		local ok, parts = pcall(GS.paintParts, model)
		if ok and type(parts) == "table" then
			for _, part in parts do
				part.Color = col
				part.Reflectance = p.refl or 0.05
				if p.mat then
					part.Material = (Enum.Material :: any)[p.mat]
				end
			end
		end
	end
end

local function ensureLoop()
	if conn then
		return
	end
	conn = RunService.RenderStepped:Connect(function(dt: number)
		local any = false
		for k, rec in live do
			if not rec.vp:IsDescendantOf(game) then
				live[k] = nil -- its card was re-rendered
				continue
			end
			if rec.vp.Visible then
				any = true
				if not K.reduced() then
					rec.angle += dt * 0.35
				end
				local cf = CFrame.new(rec.center) * CFrame.Angles(0, rec.angle, 0) * CFrame.new(0, rec.dist * 0.32, rec.dist)
				rec.cam.CFrame = CFrame.lookAt(cf.Position, rec.center)
			end
		end
		if not any and next(live) == nil and conn then
			conn:Disconnect()
			conn = nil
		end
	end)
end

function Preview.mount(parent: Instance, car: any, paintId: string): any
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(150, 150, 165)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.4)
	vp.Parent = parent
	local model = sourceModel(car)
	if not model then
		vp:Destroy()
		local t = K.text(parent, { Name = "Preview", Text = car.glyph, TextSize = 44, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		return { setPaint = function() end, destroy = function()
			t:Destroy()
		end }
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Light") or d:IsA("Sound") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end
	paint(model, paintId)
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vp
	vp.CurrentCamera = cam
	local rec = { vp = vp, cam = cam, center = cf.Position, dist = math.max(size.X, size.Z) * 1.45, angle = math.rad(-35) }
	live[vp] = rec
	ensureLoop()
	return {
		setPaint = function(id: string)
			paint(model, id)
		end,
		destroy = function()
			live[vp] = nil
			vp:Destroy()
		end,
	}
end

function Preview.start(c: any)
	ctx = c
	P, K = c.P, c.K
	Cars, CarBodies = P.mod("Cars"), P.mod("CarBodies")
	local m = ReplicatedStorage:FindFirstChild("GwangalliGarageShared")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			GS = res
		end
	end
end

return Preview
