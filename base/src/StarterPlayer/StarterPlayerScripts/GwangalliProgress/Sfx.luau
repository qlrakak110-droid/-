-- GwangalliProgress/Sfx: tiny procedural jingles from built-in rbxasset samples only (no uploads).
-- One short "ping" sample played at musical playback speeds makes the coin "ka-ching", the gold chime,
-- the goal / badge stings and the level-up fanfare (1, 1.26, 1.5, 2 = root, major third, fifth,
-- octave). A pool of 6 Sound instances under SoundService is reused; nothing runs between sounds.

local SoundService = game:GetService("SoundService")

local Sfx = {}

local K: any = nil
local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local SWOOSH = "rbxasset://sounds/swoosh.wav"

local pool: { Sound } = {}
local nextIndex = 1
local POOL = 6
local folder: Folder? = nil
local lastTick = 0

local function enabled(): boolean
	return K == nil or K.settings == nil or K.settings.sound ~= false
end

local function voice(): Sound?
	if not folder or not folder.Parent then
		local f = SoundService:FindFirstChild("GwangalliProgressSfx")
		if not f then
			f = Instance.new("Folder")
			f.Name = "GwangalliProgressSfx"
			f.Parent = SoundService
		end
		folder = f :: Folder
		table.clear(pool)
	end
	if #pool < POOL then
		local s = Instance.new("Sound")
		s.Name = "Voice" .. (#pool + 1)
		s.Parent = folder
		table.insert(pool, s)
		return s
	end
	local s = pool[nextIndex]
	nextIndex = nextIndex % POOL + 1
	return s
end

local function play(id: string, speed: number, volume: number, delay: number?)
	if not enabled() then
		return
	end
	local function go()
		pcall(function()
			local s = voice()
			if not s then
				return
			end
			s:Stop()
			s.SoundId = id
			s.PlaybackSpeed = speed
			s.Volume = volume
			s:Play()
		end)
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

function Sfx.init(k: any)
	K = k
end

-- "ka-ching": two bright pings.
function Sfx.coin(amountScale: number?)
	local v = 0.32 + math.clamp(amountScale or 0, 0, 1) * 0.12
	play(PING, 1.9, v)
	play(PING, 2.5, v * 0.85, 0.07)
end

-- one soft tick of the count-up (rate limited)
function Sfx.tick()
	local t = os.clock()
	if t - lastTick < 0.06 then
		return
	end
	lastTick = t
	play(CLICK, 1.7, 0.1)
end

-- big pay: a quick major triad on top of the coin
function Sfx.gold()
	play(PING, 1.5, 0.34)
	play(PING, 1.89, 0.34, 0.08)
	play(PING, 2.25, 0.38, 0.16)
	play(PING, 3.0, 0.3, 0.26)
end

function Sfx.goal()
	play(PING, 1.26, 0.34)
	play(PING, 1.68, 0.36, 0.1)
end

function Sfx.badge()
	play(PING, 1.5, 0.32)
	play(PING, 2.0, 0.34, 0.09)
	play(PING, 2.52, 0.36, 0.18)
end

-- 인생 레벨 UP: rising arpeggio + held octave
function Sfx.fanfare()
	play(PING, 1.0, 0.36)
	play(PING, 1.26, 0.36, 0.11)
	play(PING, 1.5, 0.38, 0.22)
	play(PING, 2.0, 0.42, 0.33)
	play(PING, 1.5, 0.3, 0.5)
	play(PING, 2.0, 0.4, 0.5)
	play(SWOOSH, 1.25, 0.16, 0.05)
end

function Sfx.confetti()
	play(SWOOSH, 1.1, 0.22)
	play(SWOOSH, 1.5, 0.14, 0.12)
end

function Sfx.card()
	play(SWOOSH, 1.6, 0.1)
end

return Sfx
