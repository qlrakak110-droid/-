-- GwangalliKaraokePlus/Voice: the echo mic and the soundproofing, with Roblox's Audio API voice.
-- Works only when the place has VoiceChatService.UseAudioApi = Enabled: the engine then creates an
-- AudioDeviceInput under each voice-enabled Player. For each room we build one speaker rig in
-- Workspace.GwangalliKaraokePlus.Room_NN:
--     device(s) -> AudioFader -> AudioCompressor -> AudioEqualizer -> AudioEcho -> AudioReverb
--               -> AudioFader -> AudioEmitter (an invisible part in front of the TV)
-- with one Wire per mic holder (Config.EchoAllMembers: per member). 에코 0..5 sets echo / reverb.
-- Soundproofing (Config.Soundproof): while a player stands in a rented room, their device is only
-- audible to the room's members (AccessType Allow + the member list); the previous access settings
-- are restored when they leave. We never create devices and never touch other voice settings.
-- Every Audio API call is pcall-guarded: without the API nothing here does anything.

local Players = game:GetService("Players")

local Voice = {}

local K: any
local S: any
local C: any
local root: Folder? = nil
local rigs: { [number]: any } = {}
local saved: { [Player]: { access: any, list: { number }? } } = {}

local ECHO = {
	[0] = { delay = 0.05, fb = 0, wet = -80, rdecay = 0.3, rwet = -80 },
	[1] = { delay = 0.08, fb = 0.15, wet = -18, rdecay = 0.8, rwet = -18 },
	[2] = { delay = 0.12, fb = 0.25, wet = -14, rdecay = 1.2, rwet = -14 },
	[3] = { delay = 0.16, fb = 0.35, wet = -10, rdecay = 1.6, rwet = -11 },
	[4] = { delay = 0.22, fb = 0.45, wet = -7, rdecay = 2.2, rwet = -9 },
	[5] = { delay = 0.3, fb = 0.6, wet = -4, rdecay = 3.5, rwet = -6 },
}

local function device(p: Player): Instance?
	local ok, d = pcall(function()
		return p:FindFirstChildOfClass("AudioDeviceInput")
	end)
	return if ok then d else nil
end
Voice.device = device

local function new(class: string, props: { [string]: any }?, parent: Instance?): Instance?
	local ok, inst = pcall(Instance.new, class)
	if not ok or not inst then
		return nil
	end
	for k, v in props or {} do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function wire(a: Instance, b: Instance, parent: Instance): Instance?
	local w = new("Wire", nil, nil)
	if not w then
		return nil
	end
	local ok = pcall(function()
		(w :: any).SourceInstance = a;
		(w :: any).TargetInstance = b
	end)
	if not ok then
		w:Destroy()
		return nil
	end
	w.Parent = parent
	return w
end

local function folder(): Folder
	if root and root.Parent then
		return root
	end
	local f = workspace:FindFirstChild(S.NAMES.ServerFolder)
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = S.NAMES.ServerFolder
		f.Parent = workspace
	end
	root = f :: Folder
	return f :: Folder
end

local function applyEcho(rig: any, level: number)
	local e = ECHO[math.clamp(level, 0, 5)] or ECHO[3]
	pcall(function()
		rig.echo.DelayTime = e.delay
		rig.echo.Feedback = e.fb
		rig.echo.WetLevel = e.wet
		rig.echo.DryLevel = 0
	end)
	pcall(function()
		rig.reverb.DecayTime = e.rdecay
		rig.reverb.WetLevel = e.rwet
		rig.reverb.DryLevel = 0
	end)
end

local function buildRig(r: any): any?
	local f = folder()
	local holder = f:FindFirstChild(S.NAMES.RoomPrefix .. r.name)
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = S.NAMES.RoomPrefix .. r.name
		holder.Parent = f
	end
	-- the speaker sits just in front of the TV, inside the room
	local scr = r.screen :: BasePart
	local inward = (r.zone.Position - scr.Position) * Vector3.new(1, 0, 1)
	inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.new(-1, 0, 0)
	local part = Instance.new("Part")
	part.Name = "Speaker"
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(scr.Position + inward * 0.8)
	part.Parent = holder
	local inF = new("AudioFader", { Name = "In", Volume = 1.4 }, part)
	local comp = new("AudioCompressor", { Name = "Comp", Threshold = -20, Ratio = 4, Attack = 0.01, Release = 0.15, MakeupGain = 6 }, part)
	local eq = new("AudioEqualizer", { Name = "EQ", LowGain = -3, MidGain = 0, HighGain = 2 }, part)
	local echo = new("AudioEcho", { Name = "Echo" }, part)
	local reverb = new("AudioReverb", { Name = "Reverb" }, part)
	local outF = new("AudioFader", { Name = "Out", Volume = 1 }, part)
	local em = new("AudioEmitter", { Name = "Emitter" }, part)
	if not (inF and comp and eq and echo and reverb and outF and em) then
		part:Destroy()
		return nil
	end
	local chain = { inF, comp, eq, echo, reverb, outF, em }
	for i = 1, #chain - 1 do
		if not wire(chain[i] :: Instance, chain[i + 1] :: Instance, part) then
			part:Destroy()
			return nil
		end
	end
	pcall(function()
		(em :: any):SetDistanceAttenuation({ [0] = 1, [12] = 0.9, [24] = 0.45, [40] = 0 })
	end)
	local rig = { part = part, input = inF, echo = echo, reverb = reverb, wires = {} :: { [number]: Instance } }
	applyEcho(rig, r.echo)
	return rig
end

-- rewires the room's speaker to its current mic holders (or members)
function Voice.refresh(r: any)
	if C.Voice == "off" then
		return
	end
	local want: { [number]: Player } = {}
	if r.renter then
		if C.EchoAllMembers then
			for p in r.members do
				if p.Parent == Players and K.Rooms.allowed(r, p) == true then
					want[p.UserId] = p
				end
			end
		else
			for i = 1, 2 do
				local uid = r.mics[i]
				local p = uid ~= 0 and Players:GetPlayerByUserId(uid)
				if p and K.Rooms.of(p) == r then
					want[uid] = p
				end
			end
		end
	end
	local any = false
	for uid, p in want do
		if device(p) then
			any = true
			break
		end
	end
	local rig = rigs[r.no]
	if any and not rig then
		rig = buildRig(r)
		rigs[r.no] = rig
	end
	if rig then
		for uid, w in rig.wires do
			if not want[uid] or not w.Parent then
				w:Destroy()
				rig.wires[uid] = nil
			end
		end
		for uid, p in want do
			if not rig.wires[uid] then
				local d = device(p)
				if d then
					local w = wire(d, rig.input, rig.part)
					if w then
						rig.wires[uid] = w
					end
				end
			end
		end
	end
	local live = rig ~= nil and next(rig.wires) ~= nil
	r.voiceRig = live
end

function Voice.echo(r: any)
	local rig = rigs[r.no]
	if rig then
		applyEcho(rig, r.echo)
	end
end

-------------------------------------------------------------------------------------------------
-- soundproofing
-------------------------------------------------------------------------------------------------
local function restore(p: Player)
	local sv = saved[p]
	if not sv then
		return
	end
	saved[p] = nil
	local d = device(p)
	if not d then
		return
	end
	pcall(function()
		(d :: any).AccessType = sv.access
	end)
	pcall(function()
		(d :: any):SetUserIdAccessList(sv.list or {})
	end)
end

local function proof(p: Player, members: { number })
	local d = device(p)
	if not d then
		return
	end
	if not saved[p] then
		local ok1, access = pcall(function()
			return (d :: any).AccessType
		end)
		local ok2, lst = pcall(function()
			return (d :: any):GetUserIdAccessList()
		end)
		if not ok1 then
			return
		end
		saved[p] = { access = access, list = if ok2 and type(lst) == "table" then lst else {} }
	end
	-- narrow only: keep anyone the previous settings excluded excluded
	local sv = saved[p]
	local allow = {}
	local prevAllow = sv.access == Enum.AccessModifierType.Allow
	local prevSet = {}
	for _, u in sv.list or {} do
		prevSet[u] = true
	end
	for _, u in members do
		if prevAllow then
			if prevSet[u] then
				table.insert(allow, u)
			end
		elseif not prevSet[u] then
			table.insert(allow, u)
		end
	end
	pcall(function()
		(d :: any).AccessType = Enum.AccessModifierType.Allow
	end)
	pcall(function()
		(d :: any):SetUserIdAccessList(allow)
	end)
end

function Voice.membersChanged(r: any)
	if C.Voice == "off" then
		return
	end
	if C.Soundproof then
		local ids = {}
		local inside = {}
		if r.renter then
			for p in r.members do
				if p.Parent == Players then
					table.insert(ids, p.UserId)
					inside[p] = true
				end
			end
		end
		for p in r.members do
			if inside[p] then
				proof(p, ids)
			end
		end
		-- players proofed for this room who are no longer inside it
		for p in saved do
			if p.Parent ~= Players then
				saved[p] = nil
			elseif K.Rooms.of(p) == nil or not (K.Rooms.of(p) :: any).renter then
				restore(p)
			end
		end
	end
	Voice.refresh(r)
end

function Voice.release(r: any)
	local rig = rigs[r.no]
	rigs[r.no] = nil
	if rig and rig.part then
		rig.part:Destroy()
	end
	r.voiceRig = false
	for p in r.members do
		restore(p)
	end
end

function Voice.init(k: any)
	K = k
	S, C = k.S, k.S.Config
	Players.PlayerRemoving:Connect(function(p)
		saved[p] = nil
	end)
	-- a device can appear after the character (voice permission / join order)
	Players.PlayerAdded:Connect(function(p)
		p.ChildAdded:Connect(function(c)
			if c.ClassName == "AudioDeviceInput" then
				local r = K.Rooms.of(p)
				if r then
					Voice.membersChanged(r)
				end
			end
		end)
	end)
end

return Voice
