-- GwangalliQuality: one shared client quality tier for every runtime system.
--
--   local Quality = require(ReplicatedStorage.GwangalliQuality)
--   Quality.get()        -> "low" | "mid" | "high"
--   Quality.isMobile()   -> true on phones / tablets (touch-first device, see below)
--   Quality.isLow()      -> Quality.get() == "low"
--   Quality.pick({ low = a, mid = b, high = c })  -> the entry for the current tier
--                           (mid falls back to high, then low; low falls back to mid, then high)
--   Quality.changed:Connect(function(newTier, oldTier) ... end)   -- RBXScriptSignal (BindableEvent)
--   Quality.fps()        -> last measured client frame rate (0 until measured)
--   Quality.reason()     -> short text explaining the current tier (debug / dev console)
--   Quality.setOverride(tier?)  -> the player's own choice ("low" | "mid" | "high"; nil / "auto" = automatic;
--                           "saver" = low with the battery / weak-phone saver on),
--                           e.g. from the phone's settings app; applies immediately (fires changed)
--   Quality.getOverride()  -> the current setOverride choice or nil
--   Quality.isSaver()    -> true while the SAVER sub-level of "low" is on (see below)
--   Quality.saverChanged:Connect(function(on) ... end)  -- RBXScriptSignal (BindableEvent)
--   Quality.noteBusy(seconds)  -> a client system is still processing a burst (stream-in after a
--                           quick travel, the join): the next `seconds` are not measured for the
--                           automatic frame-rate demotions (GwangalliWorld's queues call it)
--
-- SAVER (a sub-level of "low" for phones that still struggle on low): switched on when the tier is
-- "low" (automatic or chosen) and the measured frame rate stayed below Config.Quality.SaverFps (22)
-- for SaverSeconds (8 s) after the warm-up; sticky for the session (cleared when the player picks a setting or moves the
-- graphics slider, then measured again). Forced with setOverride("saver") or the workspace
-- attribute GwangalliQualityForce = "saver". Quality.get() still returns "low" (every consumer keeps
-- working); systems that can go lighter read Quality.isSaver(), or put a `saver` entry in the maps
-- they pass to Quality.pick: pick({ low = 70, mid = 100, high = 150, saver = 48 }) returns 48 while
-- the saver is on (the low entry otherwise). saverChanged fires on every switch.
--
-- Tier rules (client), first match wins:
--   * setOverride(tier) (player's choice, this client only)
--   * forced: workspace attribute "GwangalliQualityForce" = "low" | "mid" | "high" (Studio / tests)
--   * low:  mobile, or the Roblox graphics slider set manually to 1-3, or the measured frame rate
--           stayed below Config.Quality.FpsLow (default 27: "< 30" with a margin so a device capped
--           at 30 fps is not demoted by rounding) for FpsLowSeconds (5 s)
--   * mid:  the slider set manually to 4-6, a phone with the slider set manually to 8-10, or a
--           desktop whose frame rate stayed below FpsMid (40) for FpsMidSeconds (10 s). A second
--           spent at a steady SteadyFps (30: Roblox's frame-rate cap, 30 Hz screens, laptops on
--           battery; within SteadyFpsTolerance and without a frame longer than SteadyMaxFrame x
--           the frame period) is smooth, not slow, and does not count toward this demotion.
--   * high: everything else (Automatic slider on a desktop / console)
--   Frame-rate demotions are sticky for the session (no flip-flopping as the cheaper settings
--   raise the frame rate); moving the graphics slider clears them and measures again.
--   The measurement starts WarmupSeconds after the game has loaded (join streaming burst) and
--   pauses while the window is unfocused, for BusyAfterTeleport seconds after the local character
--   jumped more than TeleportStuds between two samples (quick travel, respawn: the arrival burst
--   is not the phone's steady frame rate; the counters restart from zero), and while a system
--   reports a burst with Quality.noteBusy.
--
-- Mobile = TouchEnabled and not IsTenFootInterface() and (not KeyboardEnabled, or the short side
-- of the viewport is <= 500 px: a phone with a Bluetooth keyboard is still a phone).
--
-- On the server (or any non-client context) the tier is always "high" and never changes, so the
-- module is safe to require from anywhere. Plain module, no yields at require time.

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

export type Tier = "low" | "mid" | "high"

local Quality = {}

local changedEvent = Instance.new("BindableEvent")
changedEvent.Name = "GwangalliQualityChanged"
Quality.changed = changedEvent.Event

local saverEvent = Instance.new("BindableEvent")
saverEvent.Name = "GwangalliQualitySaverChanged"
Quality.saverChanged = saverEvent.Event

-- Tunables (GwangalliConfig.Quality overrides these when present) --------------------------------
local knobs = {
	FpsLow = 27,
	FpsLowSeconds = 5,
	FpsMid = 40,
	FpsMidSeconds = 10,
	WarmupSeconds = 20,
	SteadyFps = 30, -- 0 disables the steady-cap exception
	SteadyFpsTolerance = 2.5,
	SteadyMaxFrame = 1.5, -- longest frame of a steady second, in frame periods (1.5 / 30 = 50 ms)
	MobileSmallScreen = 500, -- viewport short side (px) at or below which a touch device is a phone
	ForceAttribute = "GwangalliQualityForce",
	SaverFps = 22, -- "low" still below this many fps ...
	SaverSeconds = 8, -- ... for this long: saver on (0 disables the automatic saver)
	TeleportStuds = 150, -- the character moved farther than this between two 1 s samples ...
	BusyAfterTeleport = 12, -- ... then this many seconds are not measured (arrival burst)
	BusyCreditSeconds = 24, -- at most this many unmeasured seconds in a row (refills at 0.5 s per s)
}
do
	local cfgModule = script.Parent and script.Parent:FindFirstChild("GwangalliConfig")
	if cfgModule and cfgModule:IsA("ModuleScript") then
		local ok, Config = pcall(require, cfgModule)
		if ok and type(Config) == "table" and type(Config.Quality) == "table" then
			for k, v in Config.Quality do
				if knobs[k] ~= nil and type(v) == type(knobs[k]) then
					knobs[k] = v
				end
			end
		end
	end
end

local isClient = RunService:IsClient()

-- State ---------------------------------------------------------------------------------------------
local tier: Tier = "high"
local mobile = false
local fpsCap: Tier? = nil -- sticky frame-rate demotion ("low" | "mid")
local override: Tier? = nil -- Quality.setOverride
local saverAuto = false -- sticky automatic saver (frame rate on "low")
local saverChosen = false -- setOverride("saver")
local saverOn = false -- effective (tier == "low" and (auto / chosen / forced))
local lastFps = 0
local busyUntil = -math.huge -- os.clock() until which the frame rate is not measured (noteBusy)
local why = "server"

local VALID: { [string]: boolean } = { low = true, mid = true, high = true }

local function gameSettings(): any
	local ok, gs = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	return if ok then gs else nil
end

-- 0 = Automatic, 1..10 = manual slider position (unknown -> 0).
local function savedLevel(): number
	local gs = gameSettings()
	if not gs then
		return 0
	end
	local ok, level = pcall(function()
		return gs.SavedQualityLevel.Value
	end)
	return if ok and type(level) == "number" then level else 0
end

local function computeMobile(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	local okTen, tenFoot = pcall(GuiService.IsTenFootInterface, GuiService)
	if okTen and tenFoot then
		return false
	end
	if not UserInputService.KeyboardEnabled then
		return true
	end
	local camera = workspace.CurrentCamera
	if camera then
		local vp = camera.ViewportSize
		local short = math.min(vp.X, vp.Y)
		if short >= 100 and short <= knobs.MobileSmallScreen then
			return true
		end
	end
	return false
end

local function forcedTier(): Tier?
	local f = workspace:GetAttribute(knobs.ForceAttribute)
	if type(f) == "string" then
		local l = string.lower(f)
		if VALID[l] then
			return l :: Tier
		elseif l == "saver" then
			return "low"
		end
	end
	return nil
end

local function forcedSaver(): boolean
	local f = workspace:GetAttribute(knobs.ForceAttribute)
	return type(f) == "string" and string.lower(f) == "saver"
end

local function computeTier(): (Tier, string)
	if override then
		return override, "chosen in settings"
	end
	local forced = forcedTier()
	if forced then
		return forced, "forced by workspace attribute " .. knobs.ForceAttribute
	end
	local level = savedLevel()
	local base: Tier
	local reason: string
	if level >= 1 and level <= 3 then
		base, reason = "low", "graphics slider " .. level
	elseif mobile then
		if level >= 8 then
			base, reason = "mid", "mobile, graphics slider " .. level
		else
			base, reason = "low", "mobile"
		end
	elseif level >= 4 and level <= 6 then
		base, reason = "mid", "graphics slider " .. level
	else
		base, reason = "high", if level == 0 then "desktop, automatic graphics" else "desktop, graphics slider " .. level
	end
	if fpsCap == "low" and base ~= "low" then
		return "low", reason .. "; frame rate below " .. knobs.FpsLow
	elseif fpsCap == "mid" and base == "high" then
		return "mid", reason .. "; frame rate below " .. knobs.FpsMid
	end
	return base, reason
end

local function refresh()
	local newTier, reason = computeTier()
	local newSaver = newTier == "low" and (saverChosen or forcedSaver() or (saverAuto and (override == nil or override == "low")))
	why = if newSaver then reason .. "; saver" else reason
	local tierChanged = newTier ~= tier
	local saverSwitched = newSaver ~= saverOn
	local old = tier
	tier = newTier
	saverOn = newSaver
	if tierChanged then
		changedEvent:Fire(newTier, old)
	end
	if saverSwitched then
		saverEvent:Fire(newSaver)
	end
end

-- Public API ----------------------------------------------------------------------------------------
function Quality.get(): Tier
	return tier
end

function Quality.isMobile(): boolean
	return mobile
end

function Quality.isLow(): boolean
	return tier == "low"
end

function Quality.isSaver(): boolean
	return saverOn
end

function Quality.pick<T>(map: { low: T?, mid: T?, high: T?, saver: T? }): T
	if saverOn and (map :: any).saver ~= nil then
		return (map :: any).saver
	end
	local v: T? = (map :: any)[tier]
	if v == nil then
		if tier == "mid" then
			v = if map.high ~= nil then map.high else map.low
		elseif tier == "low" then
			v = if map.mid ~= nil then map.mid else map.high
		else
			v = if map.mid ~= nil then map.mid else map.low
		end
	end
	return v :: T
end

-- The player's own choice; nil / "auto" returns to automatic; "saver" = low with the saver on.
-- Unknown values raise an error. Any choice clears the automatic saver (measured again).
function Quality.setOverride(choice: string?)
	local t: Tier? = nil
	local chooseSaver = false
	if choice ~= nil then
		local c = string.lower(tostring(choice))
		if c == "saver" then
			t, chooseSaver = "low", true
		elseif c ~= "auto" and c ~= "" then
			if not VALID[c] then
				error("GwangalliQuality.setOverride: expected low / mid / high / saver / auto / nil, got " .. tostring(choice), 2)
			end
			t = c :: Tier
		end
	end
	if t == override and chooseSaver == saverChosen then
		return
	end
	override = t
	saverChosen = chooseSaver
	saverAuto = false
	if t == nil then
		fpsCap = nil -- back to automatic: measure again from scratch
	end
	if isClient then
		refresh()
	end
end

function Quality.getOverride(): string?
	if saverChosen then
		return "saver"
	end
	return override
end

function Quality.fps(): number
	return lastFps
end

-- A burst of work is running on this client (e.g. hiding what streamed in after a quick travel):
-- do not count the next `seconds` toward the automatic low / saver demotions.
function Quality.noteBusy(seconds: number?)
	local s = tonumber(seconds) or 2
	busyUntil = math.max(busyUntil, os.clock() + math.clamp(s, 0, 30))
end

function Quality.reason(): string
	return why
end

-- Client wiring ---------------------------------------------------------------------------------------
if isClient then
	mobile = computeMobile()
	tier, why = computeTier()
	saverOn = tier == "low" and forcedSaver()
	if saverOn then
		why ..= "; saver"
	end

	workspace:GetAttributeChangedSignal(knobs.ForceAttribute):Connect(refresh)

	local gs = gameSettings()
	if gs then
		pcall(function()
			gs:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
				fpsCap = nil -- the player chose a setting: measure again from scratch
				saverAuto = false
				refresh()
			end)
		end)
	end

	local focused = true
	pcall(function()
		UserInputService.WindowFocusReleased:Connect(function()
			focused = false
		end)
		UserInputService.WindowFocused:Connect(function()
			focused = true
		end)
	end)

	-- Frame counter (one increment per frame, plus the longest frame) + a 1 s evaluation loop.
	local frames = 0
	local longest = 0
	RunService.Heartbeat:Connect(function(dt: number)
		frames += 1
		if dt > longest then
			longest = dt
		end
	end)

	-- A second at a steady, capped rate (e.g. 30 fps with even frame times) runs smoothly.
	local function steadyCap(fps: number, worst: number): boolean
		local cap = knobs.SteadyFps
		if cap <= 0 then
			return false
		end
		return math.abs(fps - cap) <= knobs.SteadyFpsTolerance and worst <= knobs.SteadyMaxFrame / cap
	end

	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		local warm = 0
		local lowFor, midFor, saverFor = 0, 0, 0
		local last = os.clock()
		local lastPos: Vector3? = nil
		local busyCredit = knobs.BusyCreditSeconds
		local Players = game:GetService("Players")
		local function characterPos(): Vector3?
			local lp = Players.LocalPlayer
			local ch = lp and lp.Character
			local root = ch and (ch.PrimaryPart or ch:FindFirstChild("HumanoidRootPart"))
			if root and root:IsA("BasePart") then
				return root.Position
			end
			return nil
		end
		frames = 0
		longest = 0
		while true do
			task.wait(1)
			local now = os.clock()
			local span = now - last
			last = now
			local counted = frames
			local worst = longest
			frames = 0
			longest = 0
			-- the input devices can change (keyboard attached, window resized)
			local m = computeMobile()
			if m ~= mobile then
				mobile = m
				refresh()
			end
			if span > 0 then
				lastFps = counted / span
			end
			if not focused or span <= 0 or span > 3 then
				lowFor, midFor, saverFor = 0, 0, 0 -- unfocused, or the loop itself stalled (loading / teleport)
				continue
			end
			-- quick travel / respawn: the arrival burst (stream-in, hiding far detail) is not the
			-- phone's steady frame rate; start counting again once it is over
			local pos = characterPos()
			if pos and lastPos and (pos - lastPos).Magnitude > knobs.TeleportStuds then
				busyUntil = math.max(busyUntil, now + knobs.BusyAfterTeleport)
				lowFor, midFor, saverFor = 0, 0, 0
			end
			lastPos = pos
			-- paused (the counters keep their values), within a credit: a phone that is busy all the
			-- time (constant stream-in while walking) is still measured half of the time
			if now < busyUntil and busyCredit > 0 then
				busyCredit -= span
				continue
			end
			busyCredit = math.min(knobs.BusyCreditSeconds, busyCredit + span * 0.5)
			if warm < knobs.WarmupSeconds then
				warm += span
				continue
			end
			if lastFps < knobs.FpsLow then
				lowFor += span
			else
				lowFor = 0
			end
			if lastFps < knobs.FpsMid and not steadyCap(lastFps, worst) then
				midFor += span
			else
				midFor = 0
			end
			-- saver: already "low" (automatic, or chosen as "low") and still well under 30 fps
			if tier == "low" and (override == nil or override == "low") and not saverAuto and knobs.SaverSeconds > 0 and lastFps < knobs.SaverFps then
				saverFor += span
			else
				saverFor = 0
			end
			if fpsCap ~= "low" and lowFor >= knobs.FpsLowSeconds then
				fpsCap = "low"
				local before = tier
				refresh()
				if tier ~= before then
					saverFor = 0 -- demoted to low just now: the low settings get their own chance first
				end
			elseif fpsCap == nil and not mobile and midFor >= knobs.FpsMidSeconds then
				fpsCap = "mid"
				refresh()
			elseif saverFor >= knobs.SaverSeconds then
				saverAuto = true
				saverFor = 0
				refresh()
			end
		end
	end)
end

return Quality
