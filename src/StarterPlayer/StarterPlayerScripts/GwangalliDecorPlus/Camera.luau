--!strict
-- GwangalliDecorPlus/Camera: the editor's dollhouse camera (orbit / zoom / pan around a focus in the home)
-- and the cutaway (벽 가리기): the ceiling, camera-side walls (+ the fixtures on them) and every level
-- above the focused one fade out via LocalTransparencyModifier (local only, restored on stop).
--   Camera.start(U, focusUnit?) / Camera.stop() / Camera.orbit(dyaw, dpitch) / Camera.zoom(k) / Camera.pan(dx, dz)
--   Camera.focusRoom(room) / Camera.focusOn(unitPos, dist?) / Camera.setLevel(i) / Camera.setCut(on)
--   Camera.ray(screen: Vector2) -> (origin, direction) / Camera.free(on) (photo mode limits)

local RunService = game:GetService("RunService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Config, Geometry = Shared.Config, Shared.Geometry

local Camera = {}

local U: any = nil
local active = false
local conn: RBXScriptConnection? = nil
local saved: any = nil
local focus = Vector3.zero -- unit frame
local yaw, pitch, dist = 30, Config.CAMERA.pitch, 30
local cur = { focus = Vector3.zero, yaw = 30, pitch = 50, dist = 30 }
local cutOn = true
local level = 1
local freeMode = false
local touched: { [BasePart]: boolean } = {}
local wallNear: { [BasePart]: { BasePart } } = {}
local lastCut = 0
local maxLevel = 1
Camera.level = 1

local function minPitch(): number
	return if freeMode then 4 else 18
end

local function clampAll()
	pitch = math.clamp(pitch, minPitch(), 86)
	dist = math.clamp(dist, if freeMode then 3 else Config.CAMERA.minDist, Config.CAMERA.maxDist)
	if U then
		local lo, hi = U.lo, U.hi
		focus = Vector3.new(math.clamp(focus.X, lo.X - 4, hi.X + 4), math.clamp(focus.Y, lo.Y - 2, hi.Y + 12), math.clamp(focus.Z, lo.Z - 4, hi.Z + 4))
	end
end

local function camCF(): CFrame
	local ry, rp = math.rad(cur.yaw), math.rad(cur.pitch)
	local off = Vector3.new(math.sin(ry) * math.cos(rp), math.sin(rp), math.cos(ry) * math.cos(rp)) * cur.dist
	local f = U.F:PointToWorldSpace(cur.focus)
	local eye = U.F:PointToWorldSpace(cur.focus + off)
	return CFrame.lookAt(eye, f)
end

local function setLTM(p: BasePart, v: number)
	if p.Parent then
		p.LocalTransparencyModifier = v
		if v > 0 then
			touched[p] = true
		end
	end
end

local function precomputeNear()
	wallNear = {}
	if not U then
		return
	end
	for _, w in U.walls do
		local list = {}
		local box = Geometry.inflate(w.box, 0.6, 0.2, 0.6)
		for _, p in U.cut.all do
			if p ~= w.part and p:IsA("BasePart") and p.Size.Magnitude < 14 then
				local q = U.F:PointToObjectSpace(p.Position)
				if Geometry.pointIn(box, q, 0) then
					table.insert(list, p)
				end
			end
		end
		wallNear[w.part] = list
	end
end

local function applyCut()
	if not U then
		return
	end
	local want: { [BasePart]: number } = {}
	if cutOn then
		for _, c in U.cut.ceilings do
			want[c] = 1
		end
		local ry = math.rad(cur.yaw)
		local camDir = Vector3.new(math.sin(ry), 0, math.cos(ry))
		for _, w in U.walls do
			if not w.window then
				local c = w.box.cf.Position
				local rel = Vector3.new(c.X - cur.focus.X, 0, c.Z - cur.focus.Z)
				local along = rel:Dot(camDir)
				-- only walls that stand between the camera and the focus, on this level
				local lvlY = U.levels[level] and U.levels[level].y or 0
				if along > 1.2 and w.box.lo.Y < lvlY + 6 and w.box.hi.Y > lvlY + 0.5 then
					want[w.part] = 0.86
					for _, p in wallNear[w.part] or {} do
						want[p] = 0.86
					end
				end
			else
				local c = w.box.cf.Position
				local rel = Vector3.new(c.X - cur.focus.X, 0, c.Z - cur.focus.Z)
				if rel:Dot(camDir) > 1.2 then
					want[w.part] = 0.9
				end
			end
		end
		-- upper levels
		if level < maxLevel then
			local top = U.levels[level + 1].y - 0.4
			for _, p in U.cut.all do
				if p:IsA("BasePart") then
					local q = U.F:PointToObjectSpace(p.Position)
					if q.Y - p.Size.Y / 2 > top - 0.6 then
						want[p] = 1
					end
				end
			end
			for _, f in U.floors do
				if f.level > level then
					want[f.part] = 1
				end
			end
			for _, c in U.ceilings do
				if c.bottom > top - 1 then
					want[c.part] = 1
				end
			end
			local decor = U.model:FindFirstChild(Config.FOLDER_NAME)
			if decor then
				for _, d in decor:GetDescendants() do
					if d:IsA("BasePart") then
						local q = U.F:PointToObjectSpace(d.Position)
						if q.Y > top then
							want[d] = 1
						end
					end
				end
			end
		end
	end
	for p in touched do
		if not want[p] then
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
			touched[p] = nil
		end
	end
	for p, v in want do
		setLTM(p, v)
	end
end

local function step(dt: number)
	if not active or not U then
		return
	end
	local a = 1 - math.exp(-dt * 12)
	cur.focus = cur.focus:Lerp(focus, a)
	local dy = ((yaw - cur.yaw + 180) % 360) - 180
	cur.yaw += dy * a
	cur.pitch += (pitch - cur.pitch) * a
	cur.dist += (dist - cur.dist) * a
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCF()
	end
	local now = os.clock()
	if now - lastCut > 1 / Config.CUTAWAY_HZ then
		lastCut = now
		applyCut()
	end
end

function Camera.start(unit: any, at: Vector3?)
	U = unit
	local cam = workspace.CurrentCamera
	if not active and cam then
		saved = { type = cam.CameraType, fov = cam.FieldOfView, subject = cam.CameraSubject }
	end
	active = true
	maxLevel = #U.levels
	precomputeNear()
	if at then
		focus = at
		level = Shared.Unit.levelAt(U, at.Y)
	else
		local r = U.rooms[1]
		focus = if r then r.centre else Vector3.zero
		level = 1
	end
	Camera.level = level
	dist = 26
	pitch = Config.CAMERA.pitch
	cur = { focus = focus, yaw = yaw, pitch = pitch, dist = dist + 8 }
	if cam then
		cam.FieldOfView = Config.CAMERA.fov
	end
	if conn then
		conn:Disconnect()
	end
	conn = RunService.RenderStepped:Connect(step)
end

function Camera.stop()
	active = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	for p in touched do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	touched = {}
	local cam = workspace.CurrentCamera
	if cam and saved then
		cam.CameraType = saved.type == Enum.CameraType.Scriptable and Enum.CameraType.Custom or saved.type
		cam.FieldOfView = saved.fov
		local ch = game:GetService("Players").LocalPlayer.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = hum or saved.subject
	end
	saved = nil
	freeMode = false
end

function Camera.active(): boolean
	return active
end

function Camera.orbit(dyaw: number, dpitch: number)
	yaw = (yaw + dyaw) % 360
	pitch += dpitch
	clampAll()
end

function Camera.zoom(k: number)
	dist *= k
	clampAll()
end

-- pan in screen-relative directions (dx right, dz forward), studs
function Camera.pan(dx: number, dz: number)
	local ry = math.rad(yaw)
	local fwd = Vector3.new(-math.sin(ry), 0, -math.cos(ry))
	local right = Vector3.new(math.cos(ry), 0, -math.sin(ry))
	focus += right * dx + fwd * dz
	clampAll()
end

function Camera.focusOn(p: Vector3, d: number?)
	focus = p
	if d then
		dist = d
	end
	level = Shared.Unit.levelAt(U, p.Y + 0.3)
	Camera.level = level
	clampAll()
end

function Camera.focusRoom(room: any)
	local sz = room.size
	local fov = math.rad(Config.CAMERA.fov)
	local need = math.max(sz.X, sz.Z) * 0.62 / math.tan(fov / 2)
	focus = room.centre
	dist = math.clamp(need, Config.CAMERA.minDist, Config.CAMERA.maxDist)
	level = room.level or 1
	Camera.level = level
	clampAll()
end

function Camera.setLevel(i: number)
	if not U or not U.levels[i] then
		return
	end
	level = i
	Camera.level = i
	focus = Vector3.new(focus.X, U.levels[i].y, focus.Z)
	clampAll()
	lastCut = 0
end

function Camera.setCut(on: boolean)
	cutOn = on
	lastCut = 0
end

function Camera.free(on: boolean)
	freeMode = on
	clampAll()
end

function Camera.focus(): Vector3
	return focus
end

function Camera.yaw(): number
	return yaw
end

function Camera.ray(screen: Vector2): (Vector3, Vector3)
	local cam = workspace.CurrentCamera :: Camera
	local r = cam:ViewportPointToRay(screen.X, screen.Y)
	return r.Origin, r.Direction
end

return Camera
