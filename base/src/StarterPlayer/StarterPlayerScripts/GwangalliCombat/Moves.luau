-- GwangalliCombat/Moves (client): punching, and every character's combat motion on this client.
--   * INPUT: F / ButtonX, a left click on the world (PC: clicks on GUI arrive processed and are ignored) and the
--     HUD's 주먹 button (Moves.tryPunch). Never world taps: those move the camera, and a double tap is 어깨빵.
--     F is left to a visible F-key ProximityPrompt (the emulator delivers prompt keys to scripts too).
--   * COMBO: jab -> cross -> hook (resets after CONFIG.PUNCH.comboWindow idle). Each swing plays on the avatar
--     through a GwangalliAnim controller (pose cb_guard + one-shot emote cb_jab / cb_cross / cb_hook, stepped on
--     RenderStepped, relaxed after 1.2 s idle), a short forward lunge and a whoosh. One press is buffered while the
--     previous swing recovers.
--   * TARGET: the best one in front within CONFIG.PUNCH.range: street pedestrians (Street.candidates, standing or
--     staggering), key NPCs and police officers (workspace.GwangalliNPCs, NpcId; NpcKind "police"), other players
--     (only when both have BumpEnabled ~= false). FireServer("punch", {combo, target = {kind, id, pos}}); a swing
--     at nobody is sent too (kind "none") so the server keeps the cadence honest.
--   * OTHER CHARACTERS: GwCombatMove ("jab#seq#serverTime", server-set when a punch is accepted) plays on other
--     players' characters; GwCombatPose ("handsup" | "cuffed" | "kneel" | "ko") is applied to EVERY character,
--     the local one included. C0 offsets are local in Roblox, so every client animates everybody itself.
--   * NEVER TWO C0 WRITERS: while GwangalliBumpShared runs a knockdown (Bump.isDown / GwangalliKnocked) the local
--     controller is not stepped; a dead controller (GwangalliNPCClient's endMine destroys the shared one) is
--     fetched again. Rest C0s come from the R15 rig attachments when present, so avatar scaling never sticks.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Moves = {}

local ctx: any
local Combat: any
local CA: any
local Anim: any
local Bump: any
local CFG: any
local player: Player

local POSE_ATTR = "GwCombatPose"
local MOVE_ATTR = "GwCombatMove"
local KNOCKED_ATTR = "GwangalliKnocked"

-- local swing state
local combo = 0
local lastSwing = -1e9
local swingCooldown = 0.36
local queued = false
local queuedAt = 0
local fPrompts = 0

-------------------------------------------------------------------------------------------------
-- controllers (one per character model; the local one is shared with other GwangalliAnim users)
-------------------------------------------------------------------------------------------------
type Rec = { model: Model, ctl: any, untilT: number, pose: string?, relaxAt: number?, local_: boolean }
local recs: { [Model]: Rec } = {}

-- R15 rest C0 = Part0's "<Joint>RigAttachment" (how Roblox builds the rig): exact even right after a scale change
-- or while another script's tween is mid-way. Without attachments (R6, the emulator's rig) the controller keeps
-- the C0 it captured.
local function patchRest(ctl: any)
	pcall(function()
		for name, j in ctl.joints do
			local m = j.m
			local p0 = m and m.Part0
			local att = p0 and p0:FindFirstChild(name .. "RigAttachment")
			if att and att:IsA("Attachment") then
				local c0 = att.CFrame
				j.p = CFrame.new(c0.Position)
				j.r = c0 - c0.Position
			end
		end
	end)
end

local function ctlFor(model: Model): any?
	if not Anim or not model or not model.Parent then
		return nil
	end
	local rec = recs[model]
	if rec and rec.ctl and not rec.ctl.dead then
		return rec.ctl
	end
	local ok, ctl = pcall(Anim.rig, model)
	if not ok or not ctl then
		return nil
	end
	patchRest(ctl)
	if rec then
		rec.ctl = ctl
	else
		recs[model] = { model = model, ctl = ctl, untilT = 0, pose = nil, relaxAt = nil, local_ = model == player.Character }
	end
	return ctl
end

local function recOf(model: Model): Rec?
	local ctl = ctlFor(model)
	return if ctl then recs[model] else nil
end

-- the local character is in a 어깨빵 knockdown (BumpShared tweens own the C0s meanwhile)
local function localDown(): boolean
	local ch = player.Character
	if Bump and type(Bump.isDown) == "function" and Bump.isDown() then
		return true
	end
	return ch ~= nil and ch:GetAttribute(KNOCKED_ATTR) == true
end

local function dropRec(model: Model, relax: boolean)
	local rec = recs[model]
	recs[model] = nil
	if rec and rec.ctl and not rec.ctl.dead and relax then
		pcall(function()
			rec.ctl:relax()
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- combat poses (GwCombatPose) for any character
-------------------------------------------------------------------------------------------------
local function applyPose(model: Model)
	if not model or not model.Parent then
		return
	end
	local v = model:GetAttribute(POSE_ATTR)
	local name = if type(v) == "string" then CA.POSE_OF[v] else nil
	local rec = recs[model]
	if name then
		if model == player.Character and localDown() then
			-- a knockdown owns the joints right now: the pose is applied when it ends (step loop)
			local r = recOf(model)
			if r then
				r.pose = name
				r.untilT = math.huge
			end
			return
		end
		local r = recOf(model)
		if not r then
			return
		end
		r.pose = name
		r.untilT = math.huge
		r.relaxAt = nil
		pcall(function()
			r.ctl:pose(name, if v == "ko" then 0.35 else 0.25)
		end)
	elseif rec and rec.pose then
		rec.pose = nil
		pcall(function()
			rec.ctl:pose(nil, 0.3)
		end)
		rec.untilT = os.clock() + 0.6
	end
end

-- a pose blocks punching (hands up / cuffed / KO)
function Moves.posed(): boolean
	local ch = player.Character
	local v = ch and ch:GetAttribute(POSE_ATTR)
	return type(v) == "string" and v ~= ""
end

-------------------------------------------------------------------------------------------------
-- other players' punches (GwCombatMove)
-------------------------------------------------------------------------------------------------
local function playMove(model: Model)
	if model == player.Character then
		return -- the owner already played it locally
	end
	local name, _, t = Combat.decodeMove(model:GetAttribute(MOVE_ATTR))
	if not name then
		return
	end
	if t > 0 and math.abs(ctx.serverNow() - t) > 2 then
		return -- stale (streamed in late)
	end
	local emote = if string.sub(name, 1, 3) == "cb_" then name else "cb_" .. name
	if not Anim.EMOTES[emote] then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if root and root:IsA("BasePart") and cam and (root.Position - cam.CFrame.Position).Magnitude > 140 then
		return -- too far to see
	end
	local r = recOf(model)
	if not r then
		return
	end
	pcall(function()
		if not r.pose then
			r.ctl:pose("cb_guard", 0.08)
		end
		r.ctl:emote(emote)
	end)
	r.untilT = math.max(r.untilT, os.clock() + 1.3)
	r.relaxAt = nil
end

-------------------------------------------------------------------------------------------------
-- character watching (every player's character: pose for all, moves for others)
-------------------------------------------------------------------------------------------------
local watched: { [Model]: { RBXScriptConnection } } = {}

local function unwatch(model: Model)
	local conns = watched[model]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		watched[model] = nil
	end
	recs[model] = nil
end

local function watchCharacter(model: Model)
	if not model or watched[model] then
		return
	end
	local conns = {}
	watched[model] = conns
	table.insert(conns, model:GetAttributeChangedSignal(POSE_ATTR):Connect(function()
		applyPose(model)
	end))
	table.insert(conns, model:GetAttributeChangedSignal(MOVE_ATTR):Connect(function()
		playMove(model)
	end))
	table.insert(conns, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unwatch(model)
		end
	end))
	-- a pose that was set before we saw the character (streaming in / joining mid-arrest)
	task.defer(function()
		if model.Parent then
			applyPose(model)
		end
	end)
end

local function watchPlayer(p: Player)
	if p.Character then
		watchCharacter(p.Character)
	end
	p.CharacterAdded:Connect(function(ch)
		watchCharacter(ch)
	end)
end

-------------------------------------------------------------------------------------------------
-- targeting
-------------------------------------------------------------------------------------------------
type Target = { kind: string, id: any, part: BasePart, pos: Vector3, d: number, score: number }

local function npcDown(m: Model): boolean
	local t0, _, _, outcome = nil, 0, 0, nil
	if Bump and type(Bump.decodeKnock) == "function" then
		t0, _, _, outcome = Bump.decodeKnock(m:GetAttribute("NpcKnock"))
	end
	if not t0 then
		return false
	end
	local age = ctx.serverNow() - t0
	if outcome == "ko" then
		return age < (CFG.NPC_KO_TIME or 5) + 0.6
	elseif outcome == "knockdown" then
		return age < (Bump.KNOCK_DUR or 1.4) + 0.2
	end
	return false
end

local function pickTarget(root: BasePart): Target?
	local pp = root.Position
	local lv = root.CFrame.LookVector
	local fl = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
	if fl < 1e-3 then
		return nil
	end
	local lx, lz = lv.X / fl, lv.Z / fl
	local R = CFG.PUNCH.range or 4.6
	local dyMax = CFG.PUNCH.dyMax or 5.5
	local best: Target? = nil
	local function consider(kind: string, id: any, part: BasePart, pos: Vector3)
		local dx, dz = pos.X - pp.X, pos.Z - pp.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > R or math.abs(pos.Y - pp.Y) > dyMax then
			return
		end
		local dot = if d > 0.3 then (lx * dx + lz * dz) / d else 1
		if dot < 0.35 then
			return
		end
		local score = d * (1.7 - dot)
		if not best or score < best.score then
			best = { kind = kind, id = id, part = part, pos = pos, d = d, score = score }
		end
	end
	-- street pedestrians (client crowd)
	local street = ctx.Street
	if street and type(street.candidates) == "function" then
		local ok, list = pcall(street.candidates, R + 1.5)
		if ok and type(list) == "table" then
			for _, e in list do
				consider("street", e.id, e.part, e.part.Position)
			end
		end
	end
	-- key NPCs and police officers
	local f = workspace:FindFirstChild("GwangalliNPCs")
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") then
				local id = m:GetAttribute("NpcId")
				local r = m:FindFirstChild("HumanoidRootPart")
				if type(id) == "string" and r and r:IsA("BasePart") and (r.Position - pp).Magnitude < R + 3 and not npcDown(m) then
					consider(if m:GetAttribute("NpcKind") == Combat.POLICE_KIND then "police" else "npc", id, r, r.Position)
				end
			end
		end
	end
	-- other players (both must allow contact)
	if player:GetAttribute(Combat.Attr.BumpEnabled) ~= false then
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute(Combat.Attr.BumpEnabled) ~= false then
				local ch = other.Character
				local r = ch and ch:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") and (r.Position - pp).Magnitude < R + 3 and ch:GetAttribute(Combat.Attr.KO) ~= true then
					local hum = ch:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						consider("player", other.UserId, r, r.Position)
					end
				end
			end
		end
	end
	return best
end

-------------------------------------------------------------------------------------------------
-- punching
-------------------------------------------------------------------------------------------------
local lastTarget: Target? = nil

local function faceTarget(ch: Model, hum: Humanoid, root: BasePart, pos: Vector3)
	-- turn to the target when standing (a walking player's AutoRotate owns the facing)
	if hum.MoveDirection.Magnitude > 0.1 then
		return
	end
	local pp = root.Position
	local dx, dz = pos.X - pp.X, pos.Z - pp.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 0.5 then
		return
	end
	local lv = root.CFrame.LookVector
	local fl = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
	if fl < 1e-3 or (lv.X * dx + lv.Z * dz) / (fl * d) > 0.97 then
		return -- already facing it (within ~14 degrees)
	end
	pcall(function()
		ch:PivotTo(CFrame.lookAt(pp, Vector3.new(pos.X, pp.Y, pos.Z)))
	end)
end

local function lunge(root: BasePart, hum: Humanoid, c: number)
	-- a short step into the punch (real Roblox; the emulator's avatar ignores script velocity)
	if hum.MoveDirection.Magnitude > 0.1 or hum.FloorMaterial == Enum.Material.Air then
		return
	end
	pcall(function()
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z) + root.CFrame.LookVector * (if c == 3 then 11 else 7)
	end)
end

-- returns true when a swing started
function Moves.tryPunch(source: string?): boolean
	local now = os.clock()
	if now - lastSwing < swingCooldown then
		-- buffer one press made during the recovery of the previous swing
		if now - lastSwing > swingCooldown - 0.2 then
			queued = true
			queuedAt = now
		end
		return false
	end
	if ctx.blockReason() ~= nil or (ctx.Hud and ctx.Hud.hidden and ctx.Hud.hidden()) then
		return false
	end
	local ch, hum, root = ctx.character()
	if not ch or not hum or not root then
		return false
	end
	local c = if now - lastSwing <= (CFG.PUNCH.comboWindow or 0.9) then (combo % 3) + 1 else 1
	combo = c
	lastSwing = now
	queued = false
	local clipName = CA.CLIP_OF[c] or "cb_jab"
	local clip = CA.CLIPS[string.sub(clipName, 4)]
	swingCooldown = math.max((CFG.PUNCH.cooldown or 0.32) + 0.04, (clip and clip.dur or 0.4) * 0.8)
	local t = pickTarget(root)
	lastTarget = t
	if t then
		faceTarget(ch, hum, root, t.pos)
	end
	-- the motion (skipped while a knockdown owns the joints; blockReason covers that, kept defensive)
	if not localDown() then
		local r = recOf(ch)
		if r then
			pcall(function()
				r.ctl:pose("cb_guard", 0.08)
				r.ctl:emote(clipName)
			end)
			r.untilT = now + 1.25
			r.relaxAt = nil
		end
	end
	lunge(root, hum, c)
	if ctx.Fx then
		ctx.Fx.sound("swing", c)
	end
	local target: any
	if t then
		target = { kind = t.kind, id = t.id, pos = Combat.packV(t.pos) }
	else
		target = { kind = "none" }
	end
	ctx.fire("punch", { combo = c, target = target })
	if ctx.Hud and ctx.Hud.onSwing then
		ctx.Hud.onSwing(c, t ~= nil)
	end
	if ctx.debug then
		print(string.format("[GwangalliCombat] swing %d (%s) -> %s %s", c, tostring(source), target.kind, tostring(target.id)))
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- server events
-------------------------------------------------------------------------------------------------
-- our punch landed: impact feel + the number over the target
function Moves.onHit(p: any)
	local c = tonumber(p.combo) or combo
	local outcome = p.outcome
	if ctx.Fx then
		ctx.Fx.sound(if outcome == "knockdown" or outcome == "ko" then "knock" else "hit", c)
		ctx.Fx.hitStop(if outcome == "ko" then 3 else c)
		local part = ctx.targetPart(p.target, p.id)
		local col = if outcome == "ko" then ctx.K.Color.red elseif outcome == "knockdown" then ctx.K.Color.orange else ctx.K.Color.gold
		ctx.Fx.damageNumber(part, tonumber(p.dmg) or 0, col, outcome == "ko" or outcome == "knockdown")
	end
	pcall(ctx.K.haptic, "tap")
	-- key NPCs / police / players: a comic word (their motion comes from NpcKnock / their own client)
	if p.target == "npc" or p.target == "police" or p.target == "player" then
		local part = ctx.targetPart(p.target, p.id)
		local Social = ctx.Social
		local words = if outcome == "knockdown" or outcome == "ko" then (Social and Social.KNOCK_PUK) else (Social and Social.PUK)
		if part and type(words) == "table" and #words > 0 and (outcome ~= "hit" or math.random() < 0.5) then
			ctx.bubble(part, words[math.random(1, #words)], "plain", 1.1, 3.2)
		end
	end
end

-- the server refused the swing (too far / cooldown / not facing): nothing to undo, the button wiggles
function Moves.onMiss(p: any)
	if ctx.Hud and ctx.Hud.onMiss then
		ctx.Hud.onMiss(p and p.reason)
	end
end

-- we got hit: flinch, or a stagger / knockdown through the shared 어깨빵 motion
function Moves.onHurt(p: any)
	local ch, hum, root = ctx.character()
	if not ch or not hum or not root then
		return
	end
	local dx, dz = tonumber(p.dx) or 0, tonumber(p.dz) or 0
	local outcome = p.outcome
	if (outcome == "stagger" or outcome == "knockdown") and Bump and type(Bump.knockCharacter) == "function" and not Moves.posed() then
		if not localDown() then
			-- hand the joints over cleanly: Bump remembers the C0 at the start as the rest to return to
			local r = recs[ch]
			if r and r.ctl and not r.ctl.dead then
				pcall(function()
					r.ctl:relax()
				end)
				r.untilT = 0
			end
			pcall(Bump.knockCharacter, ch, dx, dz, outcome, { anim = Anim })
		end
		return
	end
	if localDown() or Moves.posed() then
		return
	end
	-- a plain hit: flinch away from it (dx, dz = the push direction, from the hitter to us)
	local lv = root.CFrame.LookVector
	local pushedForward = (lv.X * dx + lv.Z * dz) > 0
	local r = recOf(ch)
	if r then
		pcall(function()
			r.ctl:emote(if pushedForward then "cb_flinchB" else "cb_flinchF")
		end)
		r.untilT = math.max(r.untilT, os.clock() + 0.6)
		r.relaxAt = nil
	end
end

-------------------------------------------------------------------------------------------------
-- per-frame stepping (only characters that are moving / posed)
-------------------------------------------------------------------------------------------------
local wasDown = false
local function step()
	local now = os.clock()
	local myChar = player.Character
	local down = localDown()
	if wasDown and not down and myChar then
		-- the knockdown ended: back to the true rest (its tween returns to whatever C0 it found), then re-pose
		local r = recs[myChar]
		if r and r.ctl and not r.ctl.dead then
			pcall(function()
				r.ctl:relax()
			end)
		end
		applyPose(myChar)
	end
	wasDown = down
	if queued and now - lastSwing >= swingCooldown then
		queued = false
		if now - queuedAt < 0.5 then
			Moves.tryPunch("buffer")
		end
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for model, r in recs do
		if not model.Parent then
			recs[model] = nil
			continue
		end
		local ctl = r.ctl
		if not ctl or ctl.dead then
			-- destroyed by another user of the shared controller (GwangalliNPCClient endMine): fetch again if needed
			if r.pose or now < r.untilT then
				r.ctl = nil
				if not ctlFor(model) then
					recs[model] = nil
				elseif r.pose then
					pcall(function()
						(recs[model] :: Rec).ctl:pose(r.pose, 0.15)
					end)
				end
			else
				recs[model] = nil
			end
			continue
		end
		if model == myChar and down then
			continue -- never two C0 writers: the knockdown tweens own the joints
		end
		if not r.pose and now >= r.untilT then
			-- idle: relax once (joints back to rest) and stop stepping
			pcall(function()
				ctl:relax()
			end)
			recs[model] = nil
			continue
		end
		if model ~= myChar and camPos then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - camPos).Magnitude > 160 then
				continue
			end
		end
		pcall(ctl.step, ctl)
	end
end

-------------------------------------------------------------------------------------------------
-- init
-------------------------------------------------------------------------------------------------
function Moves.init(c: any)
	ctx = c
	Combat = ctx.Combat
	CA = ctx.CA
	Anim = ctx.Anim
	Bump = ctx.Bump
	CFG = Combat.CONFIG
	player = Players.LocalPlayer
	if not CA or not Anim then
		warn("[GwangalliCombat] GwangalliAnim / GwangalliCombatAnim missing: punches play without motion")
	end
	-- input --------------------------------------------------------------------------------------
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.KeyboardKeyCode == Enum.KeyCode.F then
			fPrompts += 1
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt.KeyboardKeyCode == Enum.KeyCode.F then
			fPrompts = math.max(0, fPrompts - 1)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.F or kc == Enum.KeyCode.ButtonX then
			if kc == Enum.KeyCode.F and fPrompts > 0 then
				return -- a door bell / prompt on F is up: the key is theirs
			end
			Moves.tryPunch("key")
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			Moves.tryPunch("click")
		end
	end)
	-- characters -----------------------------------------------------------------------------------
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	player.CharacterAdded:Connect(function()
		combo = 0
		queued = false
		wasDown = false
	end)
	if CA and Anim then
		RunService.RenderStepped:Connect(function()
			local ok, err = pcall(step)
			if not ok then
				ctx.warnOnce("moves-step", "[GwangalliCombat] step: " .. tostring(err))
			end
		end)
	end
end

-- test / debug: the last chosen target and the swing state
function Moves.state(): any
	local t = lastTarget
	return { combo = combo, lastSwing = lastSwing, target = t and { kind = t.kind, id = t.id, d = t.d } or nil, recs = (function()
		local n = 0
		for _ in recs do
			n += 1
		end
		return n
	end)() }
end

return Moves
