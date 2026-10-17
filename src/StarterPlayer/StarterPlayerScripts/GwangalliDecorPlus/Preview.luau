--!strict
-- GwangalliDecorPlus/Preview: 3D thumbnails of catalog pieces in ViewportFrames (same Spec builder as the
-- real pieces). Built lazily, at most Config.PREVIEW_CACHE live viewports; low-end devices
-- (GwangalliQuality.isLow) and failures fall back to the category icon tile.
--   Preview.fill(frame, id, look?) -> boolean   Preview.clear(frame)   Preview.low()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliDecorShared"))
local Config, Catalog, Spec = Shared.Config, Shared.Catalog, Shared.Spec

local Preview = {}

local live: { Frame } = {}
local isLow: boolean? = nil

function Preview.low(): boolean
	if isLow == nil then
		isLow = false
		local q = ReplicatedStorage:FindFirstChild("GwangalliQuality")
		if q and q:IsA("ModuleScript") then
			local ok, m = pcall(require, q)
			if ok and type(m) == "table" and type(m.isLow) == "function" then
				local ok2, v = pcall(m.isLow)
				isLow = ok2 and v == true
			end
		end
	end
	return isLow == true
end

function Preview.clear(frame: Frame)
	local vp = frame:FindFirstChild("DPViewport")
	if vp then
		vp:Destroy()
	end
	local i = table.find(live, frame)
	if i then
		table.remove(live, i)
	end
end

-- frame: the tile; look = { c, m } colours / materials
function Preview.fill(frame: Frame, id: string, look: any?): boolean
	if Preview.low() then
		return false
	end
	Preview.clear(frame)
	local spec = Catalog.spec(id, look and look.c, look and look.m)
	if not spec then
		return false
	end
	local ok = pcall(function()
		local vp = Instance.new("ViewportFrame")
		vp.Name = "DPViewport"
		vp.BackgroundTransparency = 1
		vp.Size = UDim2.new(1, 0, 1, 0)
		vp.Ambient = Color3.fromRGB(170, 172, 186)
		vp.LightColor = Color3.fromRGB(255, 248, 236)
		vp.LightDirection = Vector3.new(-0.6, -1, -0.8)
		local model = Spec.build(spec, CFrame.new(), nil, "Thumb", { thumb = true })
		model.Parent = vp
		local cf, half = Catalog.box(id)
		local centre = cf.Position
		local r = half.Magnitude
		local cam = Instance.new("Camera")
		cam.FieldOfView = 32
		local fov = math.rad(cam.FieldOfView)
		local d = r / math.sin(fov / 2) * 0.82
		local def = Catalog.get(id)
		local dir = if def and def.place == "wall" then Vector3.new(0.35, 0.18, -1).Unit elseif def and def.place == "ceiling" then Vector3.new(0.6, -0.25, -1).Unit else Vector3.new(0.7, 0.62, -1).Unit
		cam.CFrame = CFrame.lookAt(centre + dir * d, centre)
		cam.Parent = vp
		vp.CurrentCamera = cam
		vp.ZIndex = frame.ZIndex
		vp.Parent = frame
	end)
	if not ok then
		return false
	end
	table.insert(live, frame)
	while #live > Config.PREVIEW_CACHE do
		local old = table.remove(live, 1) :: Frame
		local vp = old:FindFirstChild("DPViewport")
		if vp then
			vp:Destroy()
		end
	end
	return true
end

return Preview
