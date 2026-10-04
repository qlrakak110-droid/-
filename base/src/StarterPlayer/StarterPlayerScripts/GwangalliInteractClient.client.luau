-- The supplied v2.1 NPC mind owns city interactions. Prevent the previous NPC UI from starting twice.
if game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliMindShared") then return end
-- GwangalliInteractClient (LocalScript): the client of 광안리 GTA street life (contract:
-- ReplicatedStorage.GwangalliStreetCombatShared; server: ServerScriptService.GwangalliGameplay.Interact).
--   * picks the person in front of you (city NPCs, street pedestrians, key NPCs); ⇄ / Tab cycles
--     through everybody in front of you
--   * 👊 주먹 (F / button): punches with a 1-2-3 combo (the 3rd is a hook) — at a target or at the air
--   * 🗨 상호작용 (G / button): the wheel of 15 verbs (인사 대화 질문 농담 놀리기 사과 돈 음식 도움
--     신고 밀치기 때리기 삥 도망 시비), ordered for that person and that moment (keys 1-8)
--   * 📞 112 (J / button) right after something happened near you
--   * 🙌 항복 (H / button) when the police are close and you are wanted
--   * plays everything the server decides: hits (퍽! / damage numbers / sounds / falls), pedestrian
--     reactions (Peds, incl. how passers-by react to incidents they can see), the city NPC bodies
--     (Render), the wanted stars / HP / tickets / BUSTED / WASTED (Hud)
-- Children: Render, Peds, Hud.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

local function req(name: string, timeout: number?): any
	local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, timeout or 20)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			return res
		end
		warn("[GwangalliInteract] " .. name .. ": " .. tostring(res))
	end
	return nil
end

local C = req("GwangalliStreetCombatShared")
if not C then
	warn("[GwangalliInteract] GwangalliStreetCombatShared missing; street interactions off")
	return
end
local K = req("GwangalliUI", 10)
local Layout = req("GwangalliLayout", 10)
local BUMP = req("GwangalliBumpShared", 10)
local Anim = req("GwangalliAnim", 10)
local Social = req("GwangalliSocialShared", 10)
local SIM = workspace:GetAttribute("GwSimulator") == true

local function child(name: string): any
	local m = script:WaitForChild(name, 10)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			return res
		end
		warn("[GwangalliInteract] " .. name .. ": " .. tostring(res))
	end
	return nil
end
local Render = child("Render")
local Peds = child("Peds")
local Hud = child("Hud")
if not Render or not Peds or not Hud then
	warn("[GwangalliInteract] client modules missing")
	return
end

local folder = ReplicatedStorage:WaitForChild(C.Folder, 60)
if not folder then
	warn("[GwangalliInteract] remotes missing (server module not running?)")
	return
end
local Action = folder:WaitForChild(C.Remote.Action, 20) :: RemoteEvent
local Event = folder:WaitForChild(C.Remote.Event, 20) :: RemoteEvent
if not Action or not Event then
	return
end

local function fire(kind: string, payload: any)
	Action:FireServer(kind, payload)
end

---------------------------------------------------------------------------------------------------
-- local character helpers
---------------------------------------------------------------------------------------------------
local function character(): (Model?, Humanoid?, BasePart?)
	local ch = player.Character
	if not ch then
		return nil
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local root = ch:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") or hum.Health <= 0 then
		return nil
	end
	return ch, hum, root :: BasePart
end

local function myFeet(): Vector3?
	local _, hum, root = character()
	if not hum or not root then
		return nil
	end
	return root.Position - Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5, 0)
end

local function playerDown(): boolean
	return BUMP ~= nil and BUMP.isDown ~= nil and BUMP.isDown()
end

-- nobody fights while seated / driving / knocked over / arrested / knocked out
local function busy(): boolean
	local ch, hum = character()
	if not ch or not hum then
		return true
	end
	if hum.Sit or hum.SeatPart or hum.PlatformStand then
		return true
	end
	if player:GetAttribute(C.Attr.Arrested) == true or ch:GetAttribute(C.Attr.KO) == true then
		return true
	end
	if player:GetAttribute("InTaxi") == true then
		return true
	end
	return false
end

local actSeq = 0
local function setAct(name: string?)
	local ch = player.Character
	if not ch then
		return
	end
	if name and (name == "punch" or name == "shove" or name == "kick" or name == "hurt") then
		actSeq += 1
		ch:SetAttribute("GwAct", name .. "#" .. actSeq)
	else
		ch:SetAttribute("GwAct", name or "")
	end
end

-- Roblox: the procedural punch on your own rig (GwangalliAnim controller, stepped while it plays)
local myCtl: any = nil
local ctlUntil = 0
local function ownMove(name: string)
	if SIM or not Anim or not Anim.rig then
		return
	end
	local ch = player.Character
	if not ch then
		return
	end
	local ok, ctl = pcall(Anim.rig, ch)
	if ok and ctl then
		myCtl = ctl
		local dur = 0
		pcall(function()
			dur = ctl:emote("gi_" .. name)
		end)
		ctlUntil = os.clock() + math.max(dur, 0.4) + 0.1
	end
end
local function ownPose(name: string?)
	if SIM or not Anim or not Anim.rig then
		return
	end
	local ch = player.Character
	if not ch then
		return
	end
	local ok, ctl = pcall(Anim.rig, ch)
	if ok and ctl then
		myCtl = ctl
		pcall(ctl.pose, ctl, if name then C.POSES[name] else nil, 0.2)
		ctlUntil = if name then math.huge else os.clock() + 0.6
	end
end

local controls: any = nil
local function setControls(on: boolean)
	if not controls then
		pcall(function()
			local ps = player:FindFirstChildOfClass("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm then
				controls = (require(pm) :: any):GetControls()
			end
		end)
	end
	if controls then
		pcall(function()
			if on then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
end

local function sound(name: string, parent: Instance?)
	if not parent then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Gw" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
	s.SoundId = C.SOUND_IDS[name] or ""
	s.Volume = 0.7
	s.RollOffMaxDistance = 90
	s.Parent = parent
	pcall(function()
		s:Play()
	end)
	task.delay(2, function()
		s:Destroy()
	end)
end

local bubbles: any = nil
local function bubble(adornee: Instance?, text: string?, typeId: string?, dur: number?, offsetY: number?)
	if not adornee or not text or text == "" or not BUMP or not BUMP.bubbles then
		return
	end
	if not bubbles then
		local ok, pool = pcall(BUMP.bubbles, { types = Social and Social.TYPES })
		if ok then
			bubbles = pool
		end
	end
	if bubbles then
		pcall(bubbles.say, bubbles, adornee, text, typeId or "plain", dur or 3, offsetY or 3.2)
	end
end

local function shake(strength: number, secs: number)
	if BUMP and BUMP.shakeCamera then
		pcall(BUMP.shakeCamera, strength, secs)
	end
end

---------------------------------------------------------------------------------------------------
-- targeting (8 Hz): the best person in front of you
---------------------------------------------------------------------------------------------------
type Target = { kind: string, id: string, name: string, sub: string, color: Color3?, part: BasePart, pos: Vector3, d: number, typeId: string, hp: number?, max: number? }
local target: Target? = nil

local function typeSub(typeId: string?): (string, Color3?)
	if typeId == "police" then
		return "경찰", Color3.fromRGB(120, 160, 255)
	elseif typeId == "key" then
		return "", nil
	end
	local def = Social and Social.TYPES and Social.TYPES[typeId or "plain"]
	if def and typeId ~= "plain" then
		local col = def.color
		return def.label or "", if type(col) == "table" then Color3.fromRGB(col[1], col[2], col[3]) else nil
	end
	return "", nil
end

local function npcName(m: Model): string
	local tag = m:FindFirstChild("NameTag", true)
	local l = tag and tag:FindFirstChild("Name")
	if l and l:IsA("TextLabel") and l.Text ~= "" then
		return l.Text
	end
	local id = m:GetAttribute("NpcId")
	return if type(id) == "string" then id else "시민"
end

local function consider(list: { Target }, cand: Target, look: Vector3, me: Vector3)
	local dv = Vector3.new(cand.pos.X - me.X, 0, cand.pos.Z - me.Z)
	local d = dv.Magnitude
	cand.d = d
	if d > C.PICK_RANGE or math.abs(cand.pos.Y - me.Y) > 7 then
		return
	end
	local dot = if d > 0.1 then look:Dot(dv.Unit) else 1
	if dot < 0.25 and d > 3.5 then
		return
	end
	(cand :: any).score = d - dot * 3
	table.insert(list, cand)
end

local MOOD_TEXT = { angry = "😠 화남", scared = "😨 겁먹음", embarrassed = "😳 민망함", drunk = "🍺 취함", happy = "🙂 기분 좋음", sad = "😢 우울함", hurt = "🤕 다침", surprised = "😮 놀람" }
local CONF_TEXT = { "😒 불만", "😤 말다툼", "😡 위협", "👊 싸우는 중" }

-- my quarrel level with a city NPC (GiConf "uid:level,...")
local function confWithMe(m: Instance): number
	local s = m:GetAttribute("GiConf")
	if type(s) ~= "string" or s == "" then
		return 0
	end
	for part in string.gmatch(s, "[^,]+") do
		local uid, lv = string.match(part, "^(%d+):(%d+)$")
		if tonumber(uid) == player.UserId then
			return tonumber(lv) or 0
		end
	end
	return 0
end

local function roleOf(m: Instance): string
	local tag = m:FindFirstChild("NameTag", true)
	local l = tag and tag:FindFirstChild("Role")
	return if l and l:IsA("TextLabel") then l.Text else ""
end

local candidates: { Target } = {}
local preferId: string? = nil

local function scan(): Target?
	table.clear(candidates)
	if busy() then
		return nil
	end
	local _, _, root = character()
	local me = myFeet()
	if not root or not me then
		return nil
	end
	local lv = root.CFrame.LookVector
	local look = Vector3.new(lv.X, 0, lv.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local list: { Target } = {}
	-- street pedestrians
	for _, e in Peds.near(C.PICK_RANGE + 1) do
		if not e.down and e.root and e.root.Parent then
			local sub, col = typeSub(e.typeId)
			local pos = e.root.Position - Vector3.new(0, 3, 0)
			local a = Peds.agentOf(e.id)
			if a and a.pos then
				pos = a.pos
			end
			if Peds.isFighting(e.id) then
				sub = "😡 싸우는 중"
				col = Color3.fromRGB(255, 90, 95)
			end
			consider(list, { kind = "ped", id = e.id, name = e.name or "행인", sub = sub, color = col, part = e.root, pos = pos, d = 0, typeId = e.typeId or "plain" }, look, me)
		end
	end
	-- key NPCs
	local npcs = workspace:FindFirstChild("GwangalliNPCs")
	if npcs then
		for _, m in npcs:GetChildren() do
			local id = m:GetAttribute("NpcId")
			local r = m:FindFirstChild("HumanoidRootPart") or (m:IsA("Model") and m.PrimaryPart)
			if type(id) == "string" and r and r:IsA("BasePart") then
				local g = tonumber(m:GetAttribute("NpcGround")) or 3
				local head = m:FindFirstChild("Head")
				consider(list, { kind = "npc", id = id, name = npcName(m :: Model), sub = "", part = if head and head:IsA("BasePart") then head else r, pos = r.Position - Vector3.new(0, g, 0), d = 0, typeId = "key" }, look, me)
			end
		end
	end
	-- city NPCs
	for m, rec in Render.recs do
		local fpos = Render.feetOf(m)
		if fpos and m.Parent and fpos.Y > -30 then
			local down = rec.down and rec.down.outcome ~= "stagger"
			local mode = m:GetAttribute("GiMode")
			if not down and mode ~= "custody" then
				local head = m:FindFirstChild("Head")
				local t = m:GetAttribute("GiType")
				local _, col = typeSub(t)
				local parts = {}
				local role = roleOf(m)
				if role ~= "" then
					table.insert(parts, role)
				end
				local lv2 = confWithMe(m)
				if lv2 > 0 then
					table.insert(parts, CONF_TEXT[math.clamp(lv2, 1, 4)])
					col = Color3.fromRGB(255, 90, 95)
				else
					local mood = MOOD_TEXT[m:GetAttribute("GiMood") or ""]
					if mood then
						table.insert(parts, mood)
					end
				end
				consider(list, {
					kind = "actor",
					id = rec.id,
					name = m:GetAttribute("GiName") or rec.id,
					sub = table.concat(parts, " · "),
					color = col,
					part = if head and head:IsA("BasePart") then head else rec.root,
					pos = fpos,
					d = 0,
					typeId = t or "plain",
					hp = m:GetAttribute("GiHP"),
					max = m:GetAttribute("GiMax"),
				}, look, me)
			end
		end
	end
	table.sort(list, function(a: any, b: any)
		return a.score < b.score
	end)
	for i = 1, math.min(4, #list) do
		candidates[i] = list[i]
	end
	if preferId then
		for _, c in candidates do
			if c.id == preferId then
				return c
			end
		end
		preferId = nil
	end
	return candidates[1]
end

-- ⇄ / Tab: the next person in front of you
local function switchTarget()
	if #candidates < 2 then
		return
	end
	local cur = preferId or (candidates[1] and candidates[1].id)
	local idx = 1
	for i, c in candidates do
		if c.id == cur then
			idx = i
		end
	end
	preferId = candidates[(idx % #candidates) + 1].id
end

-- the verbs in the order that makes sense for this person right now
local function verbsFor(t: Target): { string }
	local m: Instance? = nil
	if t.kind == "actor" then
		local rec = Render.byId(t.id)
		m = rec and rec.model
	end
	local arch = m and m:GetAttribute("GiKind") or nil
	local conf = if m then confWithMe(m) else 0
	local carry = player:GetAttribute("GwCarryFood")
	local order: { string }
	if conf >= 1 or (t.kind == "ped" and Peds.isFighting(t.id)) then
		order = { "apologize", "flee", "talk", "give", "help", "shove", "punch", "report", "greet", "ask", "joke", "tease", "provoke", "food", "rob" }
	elseif arch == "police" or t.typeId == "police" then
		order = { "greet", "talk", "report", "ask", "help", "apologize", "joke", "give", "tease", "provoke", "shove", "punch", "flee", "food" }
	elseif arch == "homeless" or t.typeId == "beggar" then
		order = { "give", "food", "greet", "talk", "ask", "help", "joke", "tease", "apologize", "provoke", "shove", "punch", "rob", "report", "flee" }
	elseif arch == "clerk" then
		order = { "greet", "talk", "ask", "joke", "help", "give", "food", "tease", "apologize", "report", "provoke", "shove", "punch", "rob", "flee" }
	elseif arch == "fool" or t.typeId == "fool" then
		order = { "greet", "talk", "joke", "tease", "give", "food", "ask", "help", "apologize", "provoke", "shove", "punch", "rob", "report", "flee" }
	elseif arch == "thug" or t.typeId == "violent" then
		order = { "greet", "talk", "apologize", "ask", "joke", "give", "tease", "provoke", "shove", "punch", "flee", "help", "report", "food", "rob" }
	elseif arch == "drunk" or t.typeId == "drunk" then
		order = { "talk", "greet", "help", "joke", "give", "food", "apologize", "ask", "tease", "provoke", "shove", "punch", "rob", "report", "flee" }
	else
		order = { "greet", "talk", "ask", "joke", "help", "give", "food", "report", "tease", "provoke", "apologize", "shove", "punch", "rob", "flee" }
	end
	-- food goes up front while you carry something
	if carry then
		local i = table.find(order, "food")
		if i and i > 2 then
			table.remove(order, i)
			table.insert(order, 2, "food")
		end
	end
	local out = {}
	for _, id in order do
		if C.VERB[id] then
			table.insert(out, id)
		end
	end
	return out
end

-- hit points the server told us (pedestrians / key NPCs keep them server-side)
local knownHp: { [string]: { hp: number, max: number, t: number } } = {}
local function withHp(t: Target?): Target?
	if t and t.kind ~= "actor" then
		local k = knownHp[t.kind .. ":" .. t.id]
		if k and os.clock() - k.t < 60 then
			t.hp, t.max = k.hp, k.max
		end
	end
	return t
end

---------------------------------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------------------------------
local lastPunch = -1e9
local seq = 0

local function payloadFor(t: Target, verb: string): any
	-- passers-by around (client-side pedestrians): the server counts them as possible witnesses
	local p = { verb = verb, target = t.kind, id = t.id, peds = #Peds.near(26) }
	if t.kind == "ped" then
		p.pos = C.packV(t.pos)
		p.ptype = t.typeId
	end
	return p
end

local function faceTarget(t: Target)
	local _, _, root = character()
	if not root then
		return
	end
	local d = Vector3.new(t.pos.X - root.Position.X, 0, t.pos.Z - root.Position.Z)
	if d.Magnitude < 0.5 then
		return
	end
	local look = root.CFrame.LookVector
	if Vector3.new(look.X, 0, look.Z).Unit:Dot(d.Unit) < 0.94 then
		pcall(function()
			root.CFrame = CFrame.lookAt(root.Position, root.Position + d.Unit)
		end)
	end
end

local function punch()
	if busy() or playerDown() then
		Hud.miss()
		return
	end
	local now = os.clock()
	if now - lastPunch < C.PUNCH_CD then
		return
	end
	seq = if now - lastPunch < C.COMBO_WINDOW then seq + 1 else 1
	lastPunch = now
	setAct("punch")
	ownMove("punch")
	Hud.punchFeedback()
	local t = target
	if t and t.d <= C.REACH then
		faceTarget(t)
		fire("act", payloadFor(t, "punch"))
	else
		fire("air", {})
	end
end

local function doVerb(verb: string)
	local t = Hud.wheelTarget() or target
	Hud.closeWheel()
	if not t or busy() then
		Hud.miss()
		return
	end
	if verb == "punch" then
		target = t
		punch()
		return
	end
	if verb == "shove" then
		local now = os.clock()
		if now - lastPunch < C.PUNCH_CD then
			return
		end
		lastPunch = now
		setAct("shove")
		ownMove("shove")
		faceTarget(t)
	end
	fire("act", payloadFor(t, verb))
end

local function toggleWheel()
	if Hud.wheelOpen() then
		Hud.closeWheel()
		return
	end
	if target and not busy() then
		Hud.openWheel(target, verbsFor(target))
	end
end

local function call112()
	fire("call112", {})
end

local function surrender()
	setAct("handsup")
	ownPose("handsup")
	fire("surrender", {})
	local ch = player.Character
	if ch then
		ch:SetAttribute(C.Attr.HandsUp, true)
	end
end

-- keys: F 주먹, G 상호작용, 1-7 wheel, H 항복 (never while typing or a prompt on the same key is shown)
local promptShown: { [ProximityPrompt]: boolean } = {}
ProximityPromptService.PromptShown:Connect(function(p)
	promptShown[p] = true
end)
ProximityPromptService.PromptHidden:Connect(function(p)
	promptShown[p] = nil
end)
local function promptOn(key: Enum.KeyCode): boolean
	for p in promptShown do
		if p.Parent and p.Enabled and p.KeyboardKeyCode == key then
			return true
		end
	end
	return false
end
local NUM = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight }
UserInputService.InputBegan:Connect(function(io, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	local kc = io.KeyCode
	if kc == Enum.KeyCode.F then
		if not promptOn(kc) then
			punch()
		end
	elseif kc == Enum.KeyCode.G then
		if not promptOn(kc) then
			toggleWheel()
		end
	elseif kc == Enum.KeyCode.H then
		if player:GetAttribute(C.Attr.Wanted) and (player:GetAttribute(C.Attr.Wanted) :: number) > 0 and not promptOn(kc) then
			surrender()
		end
	elseif kc == Enum.KeyCode.Tab then
		switchTarget()
	elseif kc == Enum.KeyCode.J then
		if not promptOn(kc) then
			call112()
		end
	elseif Hud.wheelOpen() then
		for i, k in NUM do
			if kc == k then
				local id = Hud.pick(i)
				if id then
					doVerb(id)
				end
				return
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- server events
---------------------------------------------------------------------------------------------------
local function partOf(kind: string?, id: string?): BasePart?
	if not id then
		return nil
	end
	if kind == "ped" then
		local a = Peds.agentOf(id)
		local r = a and a.rig and (a.rig.head or a.rig.root)
		return r
	elseif kind == "npc" then
		local npcs = workspace:FindFirstChild("GwangalliNPCs")
		if npcs then
			for _, m in npcs:GetChildren() do
				if m:GetAttribute("NpcId") == id then
					local h = m:FindFirstChild("Head")
					return (if h and h:IsA("BasePart") then h else (m:FindFirstChild("HumanoidRootPart") :: BasePart?))
				end
			end
		end
	elseif kind == "actor" then
		local rec = Render.byId(id)
		if rec then
			local h = rec.model:FindFirstChild("Head")
			return if h and h:IsA("BasePart") then h else rec.root
		end
	elseif kind == "player" then
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		local h = p and p.Character and p.Character:FindFirstChild("Head")
		return if h and h:IsA("BasePart") then h else nil
	end
	return nil
end

local wasBusy: string? = nil
local handlers = {}

function handlers.hit(e: any)
	local part = partOf(e.target, e.id)
	knownHp[e.target .. ":" .. e.id] = { hp = e.hp or 0, max = e.max or 100, t = os.clock() }
	if part then
		local word = if e.ko then "K.O.!" elseif e.crit then "빡!" elseif e.verb == "shove" then "툭!" else "퍽!"
		Hud.pop(part, word, if e.ko or e.crit then Color3.fromRGB(255, 194, 71) else Color3.new(1, 1, 1), e.ko or e.crit)
		if (e.dmg or 0) > 0 and e.verb ~= "shove" then
			task.delay(0.08, function()
				Hud.pop(part, "-" .. tostring(e.dmg), Color3.fromRGB(255, 120, 110), false)
			end)
		end
		sound("punch", part)
	end
	shake(if e.crit or e.ko then 0.22 else 0.1, 0.2)
	if e.target == "ped" then
		Peds.hit(e)
	end
	if target and target.id == e.id then
		target.hp, target.max = e.hp, e.max
		Hud.setTarget(target)
	end
end

function handlers.miss(e: any)
	if e.reason ~= "facing" then
		Hud.miss()
	end
end

function handlers.hurt(e: any)
	local ch, _, root = character()
	Hud.setHP(e.hp or 0, e.max or 100)
	local dmg = e.dmg or 0
	if dmg > 0 then
		Hud.hurtFlash(math.clamp(dmg / 18, 0.3, 0.8))
		local head = ch and ch:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			Hud.pop(head, "-" .. tostring(dmg), Color3.fromRGB(255, 70, 70), false)
			sound("punch", head)
		end
	end
	if ch and e.outcome and BUMP and BUMP.knockCharacter and (e.hp or 1) > 0 then
		pcall(BUMP.knockCharacter, ch, e.dx or 0, e.dz or 0, e.outcome, { anim = Anim })
		if e.outcome == "stagger" then
			setAct("hurt")
			ownMove("hurt")
		end
	end
	shake(if e.outcome == "knockdown" then 0.35 else 0.18, 0.35)
	-- who hit you says something
	if e.line then
		if e.actor then
			bubble(partOf("actor", e.actor), e.line, "police", 2.5, 1)
		elseif e.ped then
			Peds.say(e.ped, e.line, 2.5)
		end
	end
	local _ = root
end

function handlers.say(e: any)
	if e.actor then
		local part = partOf("actor", e.actor)
		bubble(part, e.text, e.typeId, e.dur, 1.2)
	elseif e.target == "ped" then
		Peds.say(e.id, e.text, e.dur)
	elseif e.target == "npc" then
		bubble(partOf("npc", e.id), e.text, e.typeId, e.dur, 1.2)
	elseif e.target == "player" then
		bubble(partOf("player", e.id), e.text, "plain", e.dur, 1.2)
	end
end

function handlers.crime(e: any)
	Hud.banner(C.starsText(e.stars or 1), (e.label or "범죄") .. (if e.witnessed then " · 👮 경찰이 목격!" else " · 📞 112 신고 접수"), Color3.new(1, 1, 1))
	local ch = player.Character
	local head = ch and ch:FindFirstChild("Head")
	if head then
		sound("whistle", head)
	end
end

function handlers.witness(_e: any)
	Hud.toast("목격자가 112에 신고하고 있어요…", "빨리 자리를 뜨면 수배를 피할 수도 있어요", "📞", "warn")
end

function handlers.radio(e: any)
	Hud.toast(e.text or "📻", nil, "📻", "info")
end

function handlers.busted(e: any)
	Hud.closeWheel()
	local why = if type(e.reasons) == "table" and #e.reasons > 0 then "사유: " .. table.concat(e.reasons, ", ") .. " · " else ""
	Hud.overlay("busted", string.format("%s벌금 %s%s%s", why, C.won(e.fine or 0), if e.half then " (항복해서 절반)" else "", if e.by then " · " .. e.by else ""))
	setControls(false)
	setAct("cuffed")
	ownPose("cuffed")
	local ch = player.Character
	local head = ch and ch:FindFirstChild("Head")
	if head then
		sound("cuff", head)
	end
	wasBusy = "busted"
end

function handlers.wasted(e: any)
	Hud.closeWheel()
	Hud.overlay("wasted", string.format("%s · 병원비 %s", if e.by then e.by .. "에게 당했어요" else "정신을 잃었어요", C.won(e.fee or 0)))
	setControls(false)
	setAct("ko")
	ownPose("ko")
	local _, hum = character()
	if hum then
		pcall(function()
			hum.PlatformStand = true
		end)
	end
	shake(0.5, 0.6)
	wasBusy = "wasted"
end

local function recover()
	Hud.clearOverlay()
	setControls(true)
	setAct(nil)
	ownPose(nil)
	local ch = player.Character
	if ch then
		ch:SetAttribute(C.Attr.HandsUp, nil)
	end
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if hum and wasBusy == "wasted" then
		pcall(function()
			hum.PlatformStand = false
		end)
	end
	wasBusy = nil
end
handlers.released = recover
handlers.revived = recover

function handlers.cleared(e: any)
	local ch = player.Character
	if ch and ch:GetAttribute(C.Attr.HandsUp) then
		ch:SetAttribute(C.Attr.HandsUp, nil)
		if not wasBusy then
			setAct(nil)
			ownPose(nil)
		end
	end
	if e.reason == "evaded" then
		Hud.banner("수배 해제", "경찰을 따돌렸어요 😎", Color3.fromRGB(61, 220, 132))
	elseif e.reason == "warned" then
		Hud.banner("훈방", "이번 한 번만 봐준대요", Color3.fromRGB(61, 220, 132))
	end
end

-- a ticket instead of an arrest (you stood still / put your hands up for a small thing)
function handlers.ticket(e: any)
	Hud.banner("범칙금 " .. C.won(e.fine or 0), (e.reason or "경범죄") .. (if e.by then " · " .. e.by else ""), Color3.fromRGB(255, 214, 90))
	local ch = player.Character
	local head = ch and ch:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		Hud.pop(head, "-" .. C.won(e.paid or e.fine or 0), Color3.fromRGB(255, 120, 110), true)
	end
end

-- something happened in the street: passers-by who can see it react; 📞 112 if it was near you
function handlers.incident(e: any)
	local pos = C.unpackV(e.pos)
	if not pos then
		return
	end
	Peds.onIncident(e, pos)
	local me = myFeet()
	if me and (e.sev or 0) >= 2 and (pos - me).Magnitude < 40 then
		Hud.showCall(25)
	end
end

function handlers.incidentEnd(e: any)
	Peds.onIncidentEnd(e)
end

function handlers.pedReact(e: any)
	if e.won and e.won > 0 then
		local ch = player.Character
		local head = ch and ch:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			Hud.pop(head, "+" .. C.won(e.won), Color3.fromRGB(255, 214, 90), true)
		end
	end
	if Peds.agentOf(e.id) then
		Peds.react(e.id, e.react, e.line, e)
	end
end

function handlers.sound(e: any)
	local pos = C.unpackV(e.pos)
	if not pos then
		return
	end
	-- a short-lived anchor for the sound
	local p = Instance.new("Part")
	p.Name = "GiSound"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	p.Parent = workspace
	sound(e.name or "cuff", p)
	task.delay(2.2, function()
		p:Destroy()
	end)
end

Event.OnClientEvent:Connect(function(e: any)
	if type(e) ~= "table" or type(e.kind) ~= "string" then
		return
	end
	local h = handlers[e.kind]
	if h then
		local ok, err = pcall(h, e)
		if not ok then
			warn("[GwangalliInteract] event " .. e.kind .. ": " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- attributes -> HUD
---------------------------------------------------------------------------------------------------
local function syncWanted()
	local w = player:GetAttribute(C.Attr.Wanted)
	Hud.setWanted(if type(w) == "number" then w else 0, player:GetAttribute(C.Attr.Seen) == true)
end
local function syncHP()
	local hp = player:GetAttribute(C.Attr.HP)
	local max = player:GetAttribute(C.Attr.Max)
	if type(hp) == "number" then
		Hud.setHP(hp, if type(max) == "number" then max else 100)
	end
end
player:GetAttributeChangedSignal(C.Attr.Wanted):Connect(syncWanted)
player:GetAttributeChangedSignal(C.Attr.Seen):Connect(syncWanted)
player:GetAttributeChangedSignal(C.Attr.HP):Connect(syncHP)

player.CharacterAdded:Connect(function()
	myCtl = nil
	if wasBusy then
		recover()
	end
end)

---------------------------------------------------------------------------------------------------
-- init + loops
---------------------------------------------------------------------------------------------------
Render.init({ C = C, Anim = Anim, BUMP = BUMP, SIM = SIM })
Peds.init({ C = C, R = Render, BUMP = BUMP, fire = fire })
Hud.init({
	C = C,
	K = K,
	Layout = Layout,
	callbacks = {
		punch = punch,
		interact = toggleWheel,
		surrender = surrender,
		verb = doVerb,
		switch = switchTarget,
		call112 = call112,
	},
})
syncWanted()
syncHP()

local function wanted(): number
	local w = player:GetAttribute(C.Attr.Wanted)
	return if type(w) == "number" then w else 0
end

local pedCtx = {
	busy = busy,
	playerDown = playerDown,
	wanted = wanted,
	foolRec = function()
		return Render.byId(C.FOOL.id)
	end,
}

local scanT = 0
RunService.Heartbeat:Connect(function(dt)
	local ok, err = pcall(Render.step, dt)
	if not ok then
		warn("[GwangalliInteract] render: " .. tostring(err))
	end
	ok, err = pcall(Peds.step, dt, pedCtx)
	if not ok then
		warn("[GwangalliInteract] peds: " .. tostring(err))
	end
	scanT -= dt
	if scanT <= 0 then
		scanT = 0.125
		local okS, t = pcall(scan)
		target = if okS then withHp(t) else nil
		Hud.setTarget(target, #candidates > 1)
		-- the wheel closes when its target walks off
		local wt = Hud.wheelTarget()
		if wt then
			local me = myFeet()
			local tp = wt.pos
			if wt.kind == "actor" then
				local rec = Render.byId(wt.id)
				tp = rec and Render.feetOf(rec.model) or tp
			end
			if not me or (Vector3.new(tp.X - me.X, 0, tp.Z - me.Z)).Magnitude > C.PICK_RANGE + 4 or busy() then
				Hud.closeWheel()
			end
		end
		-- 🙌 항복: wanted + a cop close by
		local showS = false
		if wanted() > 0 and not busy() then
			local me = myFeet()
			if me then
				for m, rec in Render.recs do
					if (rec.kind == "police" or rec.kind == "patrol") and m.Parent then
						local p = Render.feetOf(m)
						if p and (Vector3.new(p.X - me.X, 0, p.Z - me.Z)).Magnitude < 28 then
							showS = true
							break
						end
					end
				end
			end
		end
		Hud.setSurrender(showS)
	end
	Hud.step(dt, not busy())
	if myCtl and os.clock() < ctlUntil then
		pcall(myCtl.step, myCtl)
	elseif myCtl and ctlUntil ~= math.huge then
		pcall(myCtl.relax, myCtl)
		myCtl = nil
	end
end)

print("[GwangalliInteract] client ready (F 주먹 · G 상호작용 · H 항복)")
