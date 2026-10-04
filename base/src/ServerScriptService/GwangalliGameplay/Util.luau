-- GwangalliGameplay/Util: small server helpers shared by the gameplay modules.
--   * character access (alive humanoid + root), stand height, safe landing next to a part
--     (same probing approach as GwangalliTravel.server.luau: a floor within reach and ~5 studs
--     of free headroom, nearest first)
--   * per-player rate limits
--   * a server-driven screen fade (ScreenGui in PlayerGui, ResetOnSpawn = false)
--   * payload validation helpers for remote arguments

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Util = {}

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn(msg)
	end
end
Util.warnOnce = warnOnce

-------------------------------------------------------------------------------------------------
-- Remote argument validation
-------------------------------------------------------------------------------------------------
function Util.str(v: any, maxLen: number?): string?
	if type(v) ~= "string" then
		return nil
	end
	if #v == 0 or #v > (maxLen or 80) then
		return nil
	end
	if not utf8.len(v) then
		return nil -- invalid UTF-8
	end
	return v
end

function Util.int(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v % 1 ~= 0 or v < lo or v > hi then
		return nil
	end
	return v
end

-------------------------------------------------------------------------------------------------
-- Characters
-------------------------------------------------------------------------------------------------
function Util.alive(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function Util.rootPosition(player: Player): Vector3?
	local _, _, root = Util.alive(player)
	return root and root.Position or nil
end

-- Height of the root above the feet.
function Util.standHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3 -- R6: HipHeight is 0, the root sits 3 studs above the feet
end

function Util.flatLook(cf: CFrame): Vector3
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Lowest point of a (possibly rotated) part.
function Util.groundOf(part: BasePart): Vector3
	local cf, s = part.CFrame, part.Size
	local halfY = 0.5 * (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
	return part.Position - Vector3.new(0, halfY, 0)
end

local function standAt(feet: Vector3, look: Vector3, standHeight: number): CFrame
	local pos = feet + Vector3.new(0, standHeight + 0.5, 0)
	return CFrame.lookAt(pos, pos + look)
end

local PROBE_OFFSETS = { { 0, 0 }, { 0, 3 }, { 0, -3 }, { 3, 0 }, { -3, 0 }, { 0, 6 }, { 0, -6 }, { 4, 4 }, { -4, 4 }, { 4, -4 }, { -4, -4 }, { 0, 9 }, { 0, -9 } }

-- Root CFrame for a character standing safely near `ground` (probes a floor within 4 studs above /
-- 12 below with ~5 studs of headroom at nearby offsets, nearest first). Returns nil when no spot
-- was found (or a spatial query failed).
local function safeAtImpl(ground: Vector3, look: Vector3, standHeight: number, ignore: { Instance }): CFrame?
	local right = look:Cross(Vector3.yAxis)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	rayParams.IgnoreWater = true
	pcall(function()
		(rayParams :: any).RespectCanCollide = true
	end)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	pcall(function()
		(overlap :: any).RespectCanCollide = true
	end)
	for _, o in PROBE_OFFSETS do
		local probe = ground + right * o[1] + look * o[2]
		local hit = workspace:Raycast(probe + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), rayParams)
		if hit then
			local feet = Vector3.new(probe.X, hit.Position.Y, probe.Z)
			local room = workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 2.9, 0)), Vector3.new(2.2, 4.8, 2.2), overlap)
			local blocked = false
			for _, p in room do
				if p.CanCollide and not p:IsA("Terrain") then
					blocked = true
					break
				end
			end
			if not blocked then
				return standAt(feet, look, standHeight)
			end
		end
	end
	return nil
end

function Util.safeAt(ground: Vector3, look: Vector3, standHeight: number, ignore: { Instance }): CFrame?
	local ok, res = pcall(safeAtImpl, ground, look, standHeight, ignore)
	if ok then
		return res
	end
	warnOnce("safeAt", "[GwangalliGameplay] safe landing probe failed: " .. tostring(res))
	return nil
end

-- Root CFrame for a character standing safely at `part` (a Destination marker, an elevator stop).
function Util.safeTarget(part: BasePart, standHeight: number, ignore: { Instance }): CFrame
	local look = Util.flatLook(part.CFrame)
	local ground = Util.groundOf(part)
	return Util.safeAt(ground, look, standHeight, ignore) or standAt(ground, look, standHeight)
end

function Util.charactersIgnore(extra: { Instance }?): { Instance }
	local ignore: { Instance } = {}
	for _, inst in extra or {} do
		table.insert(ignore, inst)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	return ignore
end

-- Moves a live character so that its root lands on `target` (clears velocity and any seat).
function Util.placeCharacter(player: Player, target: CFrame): boolean
	local character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return false
	end
	if humanoid.SeatPart then
		humanoid.Sit = false
		local weld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

-- Teleports the player safely onto `part` (streams the area in first). Yields.
function Util.teleportTo(player: Player, part: BasePart, streamTimeout: number?): boolean
	local _, humanoid, root = Util.alive(player)
	if not humanoid or not root then
		return false
	end
	local rough = standAt(Util.groundOf(part), Util.flatLook(part.CFrame), Util.standHeight(humanoid, root))
	pcall(player.RequestStreamAroundAsync, player, rough.Position, streamTimeout or 6)
	if player.Parent ~= Players or not part:IsDescendantOf(workspace) then
		return false
	end
	local _, humanoid2, root2 = Util.alive(player)
	if not humanoid2 or not root2 then
		return false
	end
	local ok, target = pcall(Util.safeTarget, part, Util.standHeight(humanoid2, root2), Util.charactersIgnore({ part }))
	return Util.placeCharacter(player, if ok then target else rough)
end

-------------------------------------------------------------------------------------------------
-- Rate limits
-------------------------------------------------------------------------------------------------
local lastCall: { [Player]: { [string]: number } } = {}
local buckets: { [Player]: { tokens: number, t: number } } = {}
local fadeTokens: { [Player]: number } = {}

-- True when at least `interval` seconds passed since the last allowed call with this key.
function Util.cooldown(player: Player, key: string, interval: number): boolean
	local now = os.clock()
	local m = lastCall[player]
	if not m then
		m = {}
		lastCall[player] = m
	end
	local last = m[key]
	if last and now - last < interval then
		return false
	end
	m[key] = now
	return true
end

function Util.cooldownLeft(player: Player, key: string, interval: number): number
	local m = lastCall[player]
	local last = m and m[key]
	if not last then
		return 0
	end
	return math.max(0, interval - (os.clock() - last))
end

-- Token bucket: `rate` requests per second, bursts up to `burst`.
function Util.bucket(player: Player, rate: number, burst: number): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = burst, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.t) * rate)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Util.forget(player: Player)
	lastCall[player] = nil
	buckets[player] = nil
	fadeTokens[player] = nil
end

-------------------------------------------------------------------------------------------------
-- Screen fade (server-created GUI; the property tween replicates to that client)
-------------------------------------------------------------------------------------------------
local function fadeGui(player: Player): Frame?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gui = pg:FindFirstChild("GwangalliFade")
	if not gui then
		local sg = Instance.new("ScreenGui")
		sg.Name = "GwangalliFade"
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.DisplayOrder = 60
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.Enabled = false -- only enabled while a fade runs (never sits over the touch controls)
		local frame = Instance.new("Frame")
		frame.Name = "Black"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Parent = sg
		local label = Instance.new("TextLabel")
		label.Name = "Caption"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.new(0.8, 0, 0, 36)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(245, 245, 245)
		label.TextTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 22
		label.Text = ""
		label.Parent = frame
		sg.Parent = pg
		gui = sg
	end
	local frame = gui:FindFirstChild("Black")
	return if frame and frame:IsA("Frame") then frame else nil
end

-- Fades the player's screen to black (toBlack = true) or back. Yields `seconds`. A newer fade
-- supersedes an older one still running.
function Util.fade(player: Player, toBlack: boolean, seconds: number, caption: string?)
	local frame = fadeGui(player)
	if not frame then
		return
	end
	local token = (fadeTokens[player] or 0) + 1
	fadeTokens[player] = token
	local label = frame:FindFirstChild("Caption")
	if label and label:IsA("TextLabel") and caption then
		label.Text = caption
	end
	local gui = frame.Parent
	if toBlack and gui and gui:IsA("ScreenGui") then
		gui.Enabled = true
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local goal = if toBlack then 0 else 1
	local ok = pcall(function()
		TweenService:Create(frame, info, { BackgroundTransparency = goal }):Play()
		if label and label:IsA("TextLabel") then
			TweenService:Create(label, info, { TextTransparency = goal }):Play()
		end
	end)
	if not ok then
		frame.BackgroundTransparency = goal
	end
	task.wait(seconds)
	if frame.Parent and fadeTokens[player] == token then
		frame.BackgroundTransparency = goal
		if label and label:IsA("TextLabel") then
			label.TextTransparency = goal
		end
		if not toBlack and gui and gui:IsA("ScreenGui") then
			gui.Enabled = false
		end
	end
end

-- Instantly clears a fade (death / cleanup).
function Util.clearFade(player: Player)
	fadeTokens[player] = (fadeTokens[player] or 0) + 1
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("GwangalliFade")
	local frame = gui and gui:FindFirstChild("Black")
	if frame and frame:IsA("Frame") then
		frame.BackgroundTransparency = 1
		local label = frame:FindFirstChild("Caption")
		if label and label:IsA("TextLabel") then
			label.TextTransparency = 1
		end
	end
	if gui and gui:IsA("ScreenGui") then
		gui.Enabled = false
	end
end

-------------------------------------------------------------------------------------------------
-- Misc
-------------------------------------------------------------------------------------------------
function Util.deepCopy(v: any, depth: number?): any
	if type(v) ~= "table" then
		return v
	end
	local d = depth or 0
	if d > 12 then
		return nil
	end
	local out = {}
	for k, x in v do
		out[k] = Util.deepCopy(x, d + 1)
	end
	return out
end

-- Tags of `inst` and its ancestors (up to `levels`): { [tag] = attributes of that instance }.
function Util.tagsUp(inst: Instance?, levels: number): { [string]: { [string]: any } }
	local out: { [string]: { [string]: any } } = {}
	local cur = inst
	local n = 0
	while cur and cur ~= workspace and cur ~= game and n <= levels do
		local tags = cur:GetTags()
		if #tags > 0 then
			local attrs = cur:GetAttributes()
			for _, t in tags do
				if not out[t] then
					out[t] = attrs
				end
			end
		end
		cur = cur.Parent
		n += 1
	end
	return out
end

-- First BasePart of a tagged instance (the part itself, a Model's PrimaryPart, or a child part).
function Util.partOf(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart
		end
		local p = inst:FindFirstChildWhichIsA("BasePart", true)
		return p
	end
	if inst:IsA("Attachment") and inst.Parent and inst.Parent:IsA("BasePart") then
		return inst.Parent
	end
	return nil
end

-- Attribute from the instance or (when missing) its nearest ancestor that has it (3 levels).
function Util.attrUp(inst: Instance, name: string): any
	local cur: Instance? = inst
	local n = 0
	while cur and cur ~= workspace and n <= 3 do
		local v = cur:GetAttribute(name)
		if v ~= nil then
			return v
		end
		cur = cur.Parent
		n += 1
	end
	return nil
end

function Util.color(rgb: { number }?, fallback: Color3?): Color3
	if type(rgb) == "table" and type(rgb[1]) == "number" and type(rgb[2]) == "number" and type(rgb[3]) == "number" then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return fallback or Color3.new(1, 1, 1)
end

return Util
