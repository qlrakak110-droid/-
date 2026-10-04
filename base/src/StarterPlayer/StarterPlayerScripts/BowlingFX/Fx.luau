--!strict
-- BowlingFX/Fx: bowling sounds (built-in rbxasset files only, see BowlingShared.Sfx) and the
-- camera-shake state used by BowlingFX/Cam.
--   * roll(ball, speed)        looped low rumble parented to the rolling ball (3D, follows it)
--   * rollStop()
--   * impact(pos, standing, speed)  the pin crash: a deep thud + a clatter of wooden knocks whose
--                                   count / spread grows with the pins standing and the ball speed
--   * chime(kind)              STRIKE / SPARE / SPLITMADE / TURKEY fanfare (2D UI sound arpeggio)
--   * ballReturn(pos)          the ball coming back up the return (3D)
--   * shake(amount, seconds) / shakeOffset() -> CFrame
-- One pooled emitter part (under the camera, client-only) carries the 3D one-shots; sounds are
-- created once and re-used; nothing runs per frame.

local SoundService = game:GetService("SoundService")

local Fx = {}

local Shared: any = nil
local emitter: BasePart? = nil
local pool: { [string]: { Sound } } = {}
local poolIdx: { [string]: number } = {}
local ui: { [string]: Sound } = {}
local rollSound: Sound? = nil
local shakeAmp, shakeT0, shakeDur = 0, 0, 0
local rng = Random.new()

function Fx.init(sharedModule: any)
	Shared = sharedModule
end

local function def(name: string): any
	return Shared and Shared.Sfx and Shared.Sfx[name]
end

local function ensureEmitter(): BasePart?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	if emitter and emitter.Parent == cam then
		return emitter
	end
	if emitter then
		emitter:Destroy()
	end
	table.clear(pool)
	table.clear(poolIdx)
	local p = Instance.new("Part")
	p.Name = "BowlingSfx"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = cam
	emitter = p
	return p
end

local function pooled(name: string, n: number): Sound?
	local e = ensureEmitter()
	local d = def(name)
	if not (e and d) then
		return nil
	end
	local list = pool[name]
	if not list then
		list = {}
		for i = 1, n do
			local s = Instance.new("Sound")
			s.Name = name .. i
			s.SoundId = d.id
			s.Volume = d.volume
			s.PlaybackSpeed = d.speed
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 140
			s.Parent = e
			list[i] = s
		end
		pool[name] = list
		poolIdx[name] = 0
	end
	local i = (poolIdx[name] or 0) % #list + 1
	poolIdx[name] = i
	return list[i]
end

local function uiSound(name: string): Sound?
	local s = ui[name]
	if s and s.Parent then
		return s
	end
	local d = def(name)
	if not d then
		return nil
	end
	local ns = Instance.new("Sound")
	ns.Name = "BowlingUI_" .. name
	ns.SoundId = d.id
	ns.Volume = d.volume
	ns.PlaybackSpeed = d.speed
	ns.Parent = SoundService
	ui[name] = ns
	return ns
end

function Fx.roll(ball: BasePart?, speed: number)
	Fx.rollStop()
	local d = def("roll")
	if not (ball and ball.Parent and d) then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "BowlingRoll"
	s.SoundId = d.id
	s.Looped = true
	s.Volume = d.volume * math.clamp(speed / 26, 0.6, 1.3)
	s.PlaybackSpeed = d.speed * math.clamp(0.85 + speed / 120, 0.9, 1.15)
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 120
	s.Parent = ball
	s:Play()
	rollSound = s
end

function Fx.rollStop()
	local s = rollSound
	rollSound = nil
	if s then
		s:Stop()
		s:Destroy()
	end
end

-- The ball meets the pins: a thud, then wooden knocks spread over ~0.5 s.
function Fx.impact(pos: Vector3, standing: number, speed: number)
	local e = ensureEmitter()
	if not e then
		return
	end
	e.CFrame = CFrame.new(pos)
	local thud = pooled("thud", 2)
	if thud then
		thud.PlaybackSpeed = def("thud").speed * rng:NextNumber(0.92, 1.08)
		thud.Volume = def("thud").volume * math.clamp(0.55 + speed / 60, 0.6, 1.2)
		thud:Play()
	end
	local n = math.clamp(math.floor(standing * 0.8 + speed / 12), 2, 10)
	for i = 1, n do
		task.delay(0.03 + (i - 1) * rng:NextNumber(0.03, 0.07), function()
			local s = pooled(if i % 3 == 0 then "tick" else "clack", 5)
			if s then
				local d = def(if i % 3 == 0 then "tick" else "clack")
				s.PlaybackSpeed = d.speed * rng:NextNumber(0.82, 1.22)
				s.Volume = d.volume * rng:NextNumber(0.6, 1.0) * (1 - (i - 1) / (n + 4))
				s:Play()
			end
		end)
	end
end

function Fx.ballReturn(pos: Vector3)
	local e = ensureEmitter()
	if not e then
		return
	end
	local s = pooled("ret", 1)
	if s then
		e.CFrame = CFrame.new(pos)
		s.TimePosition = 0
		s:Play()
		task.delay(1.3, function()
			s:Stop()
		end)
	end
end

-- Fanfare: rising pings (strike 3 notes, turkey / perfect 5, spare 2, split made 4).
function Fx.chime(kind: string)
	local notes = if kind == "TURKEY" or kind == "PERFECT" then { 1, 1.26, 1.5, 1.68, 2.0 } elseif kind == "STRIKE" then { 1, 1.26, 1.5 } elseif kind == "SPLITMADE" then { 1, 1.19, 1.5, 1.78 } elseif kind == "SPARE" then { 1.12, 1.5 } else { 0.8 }
	for i, sp in notes do
		task.delay((i - 1) * 0.085, function()
			local s = uiSound("chime")
			if s then
				local c = s:Clone()
				c.PlaybackSpeed = sp
				c.Volume = def("chime").volume * (if i == #notes then 1.1 else 0.85)
				c.Parent = SoundService
				c:Play()
				task.delay(1.2, function()
					c:Destroy()
				end)
			end
		end)
	end
end

function Fx.swoosh()
	local s = uiSound("swoosh")
	if s then
		s:Play()
	end
end

function Fx.shake(amount: number, seconds: number)
	shakeAmp = math.max(amount, shakeAmp * (1 - math.clamp((os.clock() - shakeT0) / math.max(shakeDur, 0.01), 0, 1)))
	shakeT0 = os.clock()
	shakeDur = seconds
end

-- Current shake offset (decaying noise); identity when idle.
function Fx.shakeOffset(): CFrame
	if shakeAmp <= 0 then
		return CFrame.identity
	end
	local t = os.clock() - shakeT0
	if t >= shakeDur then
		shakeAmp = 0
		return CFrame.identity
	end
	local k = shakeAmp * (1 - t / shakeDur) ^ 2
	local x = math.noise(t * 24, 1.7) * k
	local y = math.noise(t * 24, 9.1) * k
	local r = math.noise(t * 18, 4.3) * k * 0.05
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, r)
end

function Fx.clear()
	Fx.rollStop()
	if emitter then
		emitter:Destroy()
		emitter = nil
	end
	table.clear(pool)
	table.clear(poolIdx)
end

return Fx
