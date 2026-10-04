-- GwangalliClubShow/Core (client): the shared context of the club show client modules.
--   * modules: GwangalliClubShowShared (S), ClubShared (Club), GwangalliAnim (Anim),
--     GwangalliNPCLooks (Looks), GwangalliCitizens, GwangalliQuality, GwangalliUI (K), GwangalliLayout,
--     ClubMusicShared (Beat / Drop), GwangalliNight - all optional except S / Club / Anim / Looks
--   * THE tween driver: one RunService.PreRender connection, connected only while a job is
--     registered (show staff, 합석 guests, the bouncer's procedural layers, spotlight follow). Every
--     job returns false when it is done; moves are batched into one BulkMoveTo per frame.
--   * pooled rigs (GwangalliNPCLooks block R15 + GwangalliAnim controller), released rigs are
--     parked outside the Workspace and re-dressed for the next show (Looks.restyle)
--   * small helpers: parts, speech bubbles, JSON, quality caps, anchors, toasts, sounds

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Core: any = {}
Core.player = Players.LocalPlayer

local function optional(name: string, timeout: number?): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m and timeout then
		m = ReplicatedStorage:WaitForChild(name, timeout)
	end
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliClubShow] " .. name .. " failed to load:", res)
	return nil
end

function Core.init(): boolean
	Core.S = optional("GwangalliClubShowShared", 30)
	Core.Club = optional("ClubShared", 30)
	Core.Anim = optional("GwangalliAnim", 20)
	Core.Looks = optional("GwangalliNPCLooks", 20)
	if not Core.S or not Core.Club or not Core.Anim or not Core.Looks then
		warn("[GwangalliClubShow] shared modules missing; club show client disabled")
		return false
	end
	Core.Citizens = optional("GwangalliCitizens", 10)
	Core.Quality = optional("GwangalliQuality")
	Core.K = optional("GwangalliUI", 10)
	Core.Layout = optional("GwangalliLayout")
	Core.Music = optional("ClubMusicShared")
	Core.Night = optional("GwangalliNight")
	Core.Bus = Core.Club.Bus or {}
	return true
end

function Core.now(): number
	return workspace:GetServerTimeNow()
end

function Core.tier(): string
	local Q = Core.Quality
	if not Q then
		return "mid"
	end
	local ok, saver = pcall(Q.isSaver)
	if ok and saver then
		return "saver"
	end
	local ok2, t = pcall(Q.get)
	return if ok2 and type(t) == "string" then t else "mid"
end

function Core.caps(): any
	local S = Core.S
	return S.Q[Core.tier()] or S.Q.mid
end

function Core.inside(): boolean
	return Core.Bus.state == "Inside"
end

function Core.nearClub(): boolean
	return Core.Bus.state == "Inside" or Core.Bus.state == "Near"
end

function Core.cameraPos(): Vector3
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

function Core.rootPart(): BasePart?
	local char = Core.player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function Core.isNight(): boolean
	local N = Core.Night
	if N then
		local ok, h = pcall(N.hype)
		if ok and type(h) == "number" then
			return h >= 0.12
		end
	end
	local c = game:GetService("Lighting").ClockTime
	return c >= 19 or c < 5
end

---------------------------------------------------------------------------------------------------
-- Anchors (club_front.luau: tag ClubShowAnchor; Persistent)
---------------------------------------------------------------------------------------------------
local anchorCache: { [string]: BasePart } = {}
function Core.anchor(name: string): BasePart?
	local a = anchorCache[name]
	if a and a.Parent then
		return a
	end
	for _, p in CollectionService:GetTagged(Core.S.Tags.Anchor) do
		if p:IsA("BasePart") then
			anchorCache[p.Name] = p
		end
	end
	return anchorCache[name]
end

---------------------------------------------------------------------------------------------------
-- The tween driver (single PreRender connection)
---------------------------------------------------------------------------------------------------
local jobs: { [string]: (number, number) -> boolean } = {}
local jobCount = 0
local conn: RBXScriptConnection? = nil
local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}
local steppers: { [any]: boolean } = {}

function Core.queueMove(part: BasePart, cf: CFrame)
	table.insert(moveParts, part)
	table.insert(moveCFs, cf)
end

-- a rig controller that should get ctl:step() this frame (procedural pose / emotes / look)
function Core.step(ctl: any)
	steppers[ctl] = true
end

local function frame(dt: number)
	local now = Core.now()
	for key, fn in jobs do
		local ok, keep = pcall(fn, dt, now)
		if not ok then
			warn("[GwangalliClubShow] job", key, keep)
			keep = false
		end
		if not keep then
			jobs[key] = nil
			jobCount -= 1
		end
	end
	if #moveParts > 0 then
		local ok, err = pcall(function()
			workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			warn("[GwangalliClubShow] BulkMoveTo failed:", err)
		end
		table.clear(moveParts)
		table.clear(moveCFs)
	end
	for ctl in steppers do
		if not ctl.dead then
			pcall(ctl.step, ctl)
		end
	end
	table.clear(steppers)
	if jobCount <= 0 and conn then
		conn:Disconnect()
		conn = nil
		jobCount = 0
	end
end

function Core.addJob(key: string, fn: (number, number) -> boolean)
	if not jobs[key] then
		jobCount += 1
	end
	jobs[key] = fn
	if not conn then
		conn = RunService.PreRender:Connect(frame)
	end
end

function Core.removeJob(key: string)
	if jobs[key] then
		jobs[key] = nil
		jobCount -= 1
	end
end

function Core.hasJob(key: string): boolean
	return jobs[key] ~= nil
end

---------------------------------------------------------------------------------------------------
-- Parts / tweens / bubbles / sounds
---------------------------------------------------------------------------------------------------
local folder: Folder? = nil
function Core.folder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "GwangalliClubShowLocal"
	nf.Parent = workspace
	folder = nf
	return nf
end

function Core.part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, parent: Instance?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or Core.folder()
	return p
end

function Core.tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween?
	local ok, tw = pcall(function()
		local tween = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0), goals)
		tween:Play()
		return tween
	end)
	return if ok then tw else nil
end

function Core.decode(v: any): any?
	if type(v) ~= "string" or v == "" then
		return nil
	end
	local ok, res = pcall(HttpService.JSONDecode, HttpService, v)
	return if ok and type(res) == "table" then res else nil
end

-- speech bubble over a part (kit colours); returns a cleanup function
function Core.bubble(adornee: BasePart, text: string, seconds: number, accent: Color3?): () -> ()
	local K = Core.K
	local bb = Instance.new("BillboardGui")
	bb.Name = "ClubShowBubble"
	bb.Size = UDim2.fromOffset(220, 64)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 70
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb.Adornee = adornee
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.fromScale(0.5, 1)
	card.Size = UDim2.fromScale(1, 0.8)
	card.BackgroundColor3 = if K then K.Color.glass else Color3.fromRGB(15, 18, 31)
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = card
	local st = Instance.new("UIStroke")
	st.Color = accent or (if K then K.Color.magenta else Color3.fromRGB(255, 79, 163))
	st.Transparency = 0.25
	st.Thickness = 1.5
	st.Parent = card
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.BackgroundTransparency = 1
	tl.Position = UDim2.fromOffset(8, 4)
	tl.Size = UDim2.new(1, -16, 1, -8)
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextWrapped = true
	tl.TextColor3 = Color3.fromRGB(245, 247, 251)
	tl.Text = text
	tl.Parent = card
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 17
	tsc.MinTextSize = 9
	tsc.Parent = tl
	local sc = Instance.new("UIScale")
	sc.Scale = 0.6
	sc.Parent = card
	bb.Parent = Core.folder()
	Core.tween(sc, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	local alive = true
	local function kill()
		if not alive then
			return
		end
		alive = false
		Core.tween(sc, 0.18, { Scale = 0.01 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			bb:Destroy()
		end)
	end
	task.delay(seconds, kill)
	return kill
end

function Core.sound(id: string, volume: number, speed: number?, parent: Instance?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 120
	s.Parent = parent or workspace.CurrentCamera or workspace
	pcall(function()
		s:Play()
	end)
	task.delay(4, function()
		s:Destroy()
	end)
end

function Core.toast(title: string, body: string?, icon: string?, kind: string?)
	local K = Core.K
	if K and type(K.toast) == "function" then
		pcall(K.toast, { kind = kind or "club", title = title, body = body or "", icon = icon })
	end
end

function Core.won(n: number): string
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s .. "원"
end

-- the next music beat (or `maxWait` seconds, whichever first), then fn() once
function Core.onBeat(maxWait: number, fn: () -> ())
	local done = false
	local c: any = nil
	local function fire()
		if done then
			return
		end
		done = true
		if c then
			pcall(function()
				c:Disconnect()
			end)
		end
		task.spawn(fn)
	end
	local M = Core.Music
	if M and M.Beat and type(M.Beat.Connect) == "function" then
		local ok, res = pcall(function()
			return M.Beat:Connect(function()
				fire()
			end)
		end)
		if ok then
			c = res
		end
	end
	task.delay(maxWait, fire)
end

-- current music tempo (for strut timing)
function Core.bpm(): number
	local M = Core.Music
	if M and type(M.bpm) == "function" then
		local ok, b = pcall(M.bpm)
		if ok and type(b) == "number" and b > 60 and b < 200 then
			return b
		end
	end
	return 126
end

---------------------------------------------------------------------------------------------------
-- Rig pool
---------------------------------------------------------------------------------------------------
local pool: { any } = {}
local POOL_MAX = 8

-- rec = { rig, model, root, ctl, props = {} }
function Core.rig(spec: any, name: string): any
	local Looks, Anim = Core.Looks, Core.Anim
	local rig: any = nil
	local rec = table.remove(pool)
	if rec then
		rig = rec.rig
		-- the old controller cached the old body's joint rests: a fresh one reads the new ones
		if rec.ctl then
			pcall(rec.ctl.destroy, rec.ctl)
		end
		local ok = pcall(Looks.restyle, rig, spec, name)
		if not ok then
			pcall(function()
				rig.model:Destroy()
			end)
			rig = nil
		end
	end
	if not rig then
		local ok, res = pcall(Looks.build, spec, { name = name, shadow = false })
		if not ok then
			warn("[GwangalliClubShow] rig build failed:", res)
			return nil
		end
		rig = res
	end
	rig.model.Name = name
	rig.model.Parent = Core.folder()
	local ctl = Anim.rig(rig.model)
	pcall(function()
		ctl:setAnimated(true)
		ctl:setDetail(2)
		ctl:relax()
		ctl:setAct("idle")
	end)
	return { rig = rig, model = rig.model, root = rig.root, ctl = ctl, props = {}, ground = rig.ground or 3 }
end

function Core.release(rec: any)
	if not rec or rec.released then
		return
	end
	rec.released = true
	for _, p in rec.props do
		pcall(function()
			p:Destroy()
		end)
	end
	table.clear(rec.props)
	local ctl = rec.ctl
	pcall(function()
		ctl:setMoving(nil)
		ctl:pose(nil, 0.05)
		ctl:relax()
		Core.Anim.stopAll(rec.model, 0)
	end)
	rec.model.Parent = nil
	if #pool < POOL_MAX then
		table.insert(pool, { rig = rec.rig, ctl = ctl })
	else
		pcall(function()
			ctl:destroy()
		end)
		rec.model:Destroy()
	end
end

-- prop welded to a rig part (moves with the hand); offset in that part's space
function Core.attach(rec: any, partName: string, prop: BasePart, offset: CFrame)
	local host = rec.rig.parts and rec.rig.parts[partName]
	if not host then
		prop:Destroy()
		return
	end
	prop.Anchored = false
	prop.Massless = true
	prop.CFrame = host.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = host
	w.Part1 = prop
	w.Parent = prop
	prop.Parent = rec.model
	table.insert(rec.props, prop)
end

-- rig root CFrame for a floor point (HRP height = the path's y) facing dir
function Core.rootCF(pos: Vector3, dir: Vector3): CFrame
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		d = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(pos, pos + d.Unit)
end

-- night outfit for a roster person (club look: sparkle / jacket / sunglasses)
function Core.guestSpec(id: string, g: string?): any
	local Looks = Core.Looks
	local c = Core.Citizens and Core.Citizens.byId and Core.Citizens.byId[id]
	local look = table.clone((c and c.look) or {})
	look.body = look.body or (if g == "m" then "m" else "f")
	if look.night == nil then
		look.night = if look.body == "f" then "sparkle" else "jacket"
	end
	local spec = Looks.resolve(look, look.seed or Looks.hash(id), true)
	local h = Looks.hash(id .. "#club") % 3
	if h == 0 then
		table.insert(spec.acc, "sunglasses")
	end
	return spec
end

return Core
