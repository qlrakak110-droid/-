-- GwangalliKaraokePlus (client): 팡팡노래방-style coin karaoke UI, TV, band and effects for the booths of
-- 광안 코인노래연습장. Waits until the add-on server is active (ReplicatedStorage.GwangalliKaraokeShared
-- attribute Active), so a place without the server Script keeps its legacy karaoke untouched.
-- One sequencer per client; everything is built locally (PlayerGui, SoundService.GwKP_Band,
-- Workspace.GwKaraokePlusLocal). The server is authoritative for money, rooms, queue, mics and scores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local shared = ReplicatedStorage:WaitForChild("GwangalliKaraokeShared", 120)
if not (shared and shared:IsA("ModuleScript")) then
	return
end
local okS, S = pcall(require, shared)
if not okS or type(S) ~= "table" or not S.Config.Enabled then
	return
end
while shared:GetAttribute("Active") ~= true do
	shared:GetAttributeChangedSignal("Active"):Wait()
end
local remotes = shared:WaitForChild(S.NAMES.Remotes, 60)
local stateFolder = shared:WaitForChild(S.NAMES.State, 60)
if not (remotes and stateFolder) then
	warn("[GwangalliKaraokePlus] remotes / state missing")
	return
end

local K: any = { S = S, shared = shared, remotes = remotes, stateFolder = stateFolder, me = nil, trial = false }
local function mod(name: string): any
	return require(script:WaitForChild(name))
end
K.Kit = mod("Kit")
K.Net = mod("Net")
K.Rooms = mod("Rooms")
K.Legacy = mod("Legacy")
K.Lyrics = mod("Lyrics")
K.Background = mod("Background")
K.Band = mod("Band")
K.Mic = mod("Mic")
K.Fx = mod("Fx")
K.TV = mod("TV")
K.Rhythm = mod("Rhythm")
K.Hud = mod("Hud")
K.Book = mod("Book")
K.Remote = mod("Remote")
K.Prompts = mod("Prompts")

-- applies my saved settings (volumes, lyric size)
function K.applySettings()
	local st = K.me and K.me.settings
	if type(st) ~= "table" then
		return
	end
	K.Band.setSettings(st)
	K.TV.setLyricSize(st.lyricSize or "M")
end

local order = { "Kit", "Net", "Rooms", "Legacy", "Band", "Mic", "Fx", "TV", "Rhythm", "Hud", "Book", "Remote", "Prompts" }
for _, name in order do
	local ok, err = pcall(K[name].init, K)
	if not ok then
		warn("[GwangalliKaraokePlus] init " .. name .. " failed:", err)
	end
end

task.spawn(function()
	for attempt = 1, 5 do
		local res = K.Net.request("hello", {})
		if res.ok then
			K.me = res.me
			K.trial = res.trial == true
			K.applySettings()
			return
		end
		task.wait(2 * attempt)
	end
end)

-- per-frame loop (each module throttles itself)
local updates = { K.Rooms, K.Band, K.Mic, K.Rhythm, K.TV, K.Fx, K.Hud }
local errors: { [any]: number } = {}
RunService.RenderStepped:Connect(function(dt)
	-- listeners hear the singer's echoed voice a little late: delay the band to match (setting 싱크)
	local v = K.Rooms.current()
	local sync = (K.me and K.me.settings and tonumber(K.me.settings.sync)) or 0
	K.Band.localDelay = if v and v.voiceRig and not K.Rooms.isSinger(v) then math.clamp(sync, 0, 0.8) else 0
	for _, m in updates do
		local ok, err = pcall(m.update, dt)
		if not ok then
			local n = (errors[m] or 0) + 1
			errors[m] = n
			if n <= 3 then
				warn("[GwangalliKaraokePlus] update failed:", err)
			end
		end
	end
end)

player.CharacterAdded:Connect(function()
	-- sheets stay usable after respawn (the ScreenGui does not reset); nothing else to rebuild
	K.Kit.closeAll()
end)
