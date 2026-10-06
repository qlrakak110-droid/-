-- GwangalliFriendAvatars (Script, ServerScriptService; owner: npc_mind): the Friend Avatar NPC
-- System ("친구 퍼레이드"): a few of a player's Roblox friends, in their real current avatars, show
-- up as street-life NPCs for THAT player only (GwangalliStreetLife/Friends puts them in the
-- evening plaza / the club-night parade: walking, dancing, waving — positive, neutral roles only).
--
--   * Players:GetFriendsAsync(userId) -> up to PICK friends (a stable shuffle per player and day,
--     online friends first), Players:GetHumanoidDescriptionFromUserIdAsync(friendId) (cached per
--     friend id: two players with the same friend cost one request), then
--     Players:CreateHumanoidModelFromDescription(desc, R15) (server-only API).
--   * The models go to the player's own PlayerGui.GwangalliFriendAvatars (replicates to that
--     client only, never into the Workspace); the client clones them locally near a parade spot.
--   * Rules kept on purpose (Roblox community standards): the friend's avatar is used as it is (no
--     edits), never in a negative role (no crime target, no fights, no police, no robbery: the
--     client tags them GwFriendAvatar / GwRobbable = false and they are not crowd agents), at most
--     PICK per player, loaded once per session, requests spaced out.
--   * workspace attribute GwangalliFriendAvatars = false turns it off. In the 임시 스튜디오
--     emulator the friend APIs do not exist: workspace attribute GwangalliFriendAvatarTest = true
--     adds placeholder entries (names only; the client dresses them with roster looks) for tests.

local Players = game:GetService("Players")

local PICK = 8 -- loaded per player (the client shows at most 6 at once)
local GAP = 0.35 -- s between avatar requests
local FOLDER = "GwangalliFriendAvatars"

local descCache: { [number]: any } = {}
local loading: { [Player]: boolean } = {}

local function folderOf(player: Player): Folder?
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 20)
	if not pg then
		return nil
	end
	local f = pg:FindFirstChild(FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = pg
	end
	return f :: Folder
end

local function friendsOf(player: Player): { any }
	local out = {}
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(player.UserId)
	end)
	if not ok or not pages then
		return out
	end
	for _ = 1, 4 do
		local okP, items = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not okP or type(items) ~= "table" then
			break
		end
		for _, it in items do
			if type(it) == "table" and type(it.Id) == "number" then
				table.insert(out, { id = it.Id, name = it.DisplayName or it.Username or "친구", online = it.IsOnline == true })
			end
		end
		if #out >= 200 or pages.IsFinished then
			break
		end
		local okN = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not okN then
			break
		end
	end
	return out
end

-- a stable order per player and day: online friends first, then the rest shuffled
local function choose(player: Player, list: { any }): { any }
	local day = os.time() // 86400
	local rng = Random.new(player.UserId % 1000003 + day * 7919)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	table.sort(list, function(a, b)
		return (a.online and 1 or 0) > (b.online and 1 or 0)
	end)
	local out = {}
	for i = 1, math.min(PICK, #list) do
		table.insert(out, list[i])
	end
	return out
end

local function modelFor(fid: number): Model?
	local desc = descCache[fid]
	if not desc then
		local ok, d = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(fid)
		end)
		if not ok or not d then
			return nil
		end
		desc = d
		descCache[fid] = d
	end
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not m then
		return nil
	end
	-- no scripts (the client animates them), no name over the head (the client shows its own tag)
	for _, d in m:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return m
end

local function load(player: Player)
	if loading[player] or workspace:GetAttribute("GwangalliFriendAvatars") == false then
		return
	end
	loading[player] = true
	local f = folderOf(player)
	if not f then
		return
	end
	if workspace:GetAttribute("GwangalliFriendAvatarTest") == true then
		for i, nm in { "민수", "지훈", "서연", "현우", "유진", "준호" } do
			local e = Instance.new("Configuration")
			e.Name = "Friend_test" .. i
			e:SetAttribute("FriendUserId", -i)
			e:SetAttribute("FriendName", nm)
			e.Parent = f
		end
		return
	end
	local picked = choose(player, friendsOf(player))
	for _, fr in picked do
		if not player.Parent then
			return
		end
		local m = modelFor(fr.id)
		if m then
			m.Name = "Friend_" .. tostring(fr.id)
			m:SetAttribute("FriendUserId", fr.id)
			m:SetAttribute("FriendName", fr.name)
			m.Parent = f
		end
		task.wait(GAP)
	end
end

Players.PlayerAdded:Connect(function(p)
	task.spawn(load, p)
end)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(p)
	loading[p] = nil
end)
-- (tests) placeholder friends when the emulator flag is switched on later
workspace:GetAttributeChangedSignal("GwangalliFriendAvatarTest"):Connect(function()
	if workspace:GetAttribute("GwangalliFriendAvatarTest") == true then
		for _, p in Players:GetPlayers() do
			loading[p] = nil
			task.spawn(load, p)
		end
	end
end)
