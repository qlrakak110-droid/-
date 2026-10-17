-- GwangalliKaraokePlus/Legacy (client): keeps the legacy GwangalliVenues karaoke UI out of the way once
-- the add-on server is active (it rents the rooms, so the old bar / strip / tap button / picker would
-- show next to ours, and the old TV would sit under our TV).
--   * PlayerGui.GwangalliVenues: KaraokeBar / KaraokeStrip / KaraokeTap / KaraokePicker are destroyed
--     (again whenever they reappear; the legacy code tolerates writes to destroyed objects).
--   * every booth KaraokeScreen: the legacy SurfaceGui "KaraokeTV" and the placeholder "SignGui" are
--     disabled and kept disabled (DetailLOD re-enables guis when a booth streams back in).
-- The legacy chiptune never starts: the add-on never writes the booth attribute KSong.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Legacy = {}

local K: any
local player = Players.LocalPlayer
local KILL = { KaraokeBar = true, KaraokeStrip = true, KaraokeTap = true, KaraokePicker = true }
local watchedTv: { [Instance]: boolean } = {}

local function keepTvOff(sg: Instance)
	if not sg:IsA("SurfaceGui") or watchedTv[sg] then
		return
	end
	watchedTv[sg] = true
	sg.Enabled = false
	sg:GetPropertyChangedSignal("Enabled"):Connect(function()
		if sg.Enabled then
			sg.Enabled = false
		end
	end)
	sg.Destroying:Connect(function()
		watchedTv[sg] = nil
	end)
end

-- the screen's own placeholder sign ("ROOM 01 / 문 옆 패널에서 …") sits under our TV: the legacy client
-- hid it while its TV existed, we keep doing that (local only; the panel's sign is left alone)
local HIDE = { KaraokeTV = true, SignGui = true }

local function watchScreen(scr: Instance)
	for _, c in scr:GetChildren() do
		if HIDE[c.Name] then
			keepTvOff(c)
		end
	end
	scr.ChildAdded:Connect(function(c)
		if HIDE[c.Name] then
			task.defer(keepTvOff, c)
		end
	end)
end

local function watchBooth(m: Instance)
	local scr = m:FindFirstChild("KaraokeScreen", true)
	if scr then
		watchScreen(scr)
	end
	m.DescendantAdded:Connect(function(d)
		if d.Name == "KaraokeScreen" and d:IsA("BasePart") then
			watchScreen(d)
		end
	end)
end

local function killIn(gui: Instance)
	for _, c in gui:GetDescendants() do
		if KILL[c.Name] and c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	gui.DescendantAdded:Connect(function(c)
		if not c:IsA("GuiObject") then
			return
		end
		if KILL[c.Name] then
			task.defer(function()
				if c.Parent then
					c:Destroy()
				end
			end)
		end
	end)
end

function Legacy.init(k: any)
	K = k
	local pg = player:WaitForChild("PlayerGui")
	local venues = pg:FindFirstChild("GwangalliVenues")
	if venues then
		killIn(venues)
	end
	pg.ChildAdded:Connect(function(c)
		if c.Name == "GwangalliVenues" then
			killIn(c)
		end
	end)
	for _, m in CollectionService:GetTagged(k.S.NAMES.Tag) do
		watchBooth(m)
	end
	CollectionService:GetInstanceAddedSignal(k.S.NAMES.Tag):Connect(watchBooth)
end

return Legacy
