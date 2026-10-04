-- GwangalliStreetLife/SocialUI: the player's side of meeting people on the street.
--   * name + tier chip (BillboardGui on the head) for the few closest named citizens: "민수" and
--     "🤍 모르는 사이 · 대학생" (tier colour / icon from GwangalliSocialShared.TIERS; tiers from the
--     SocialState snapshot / affinity / tier events), plus a speech bubble for their lines.
--   * 말 걸기 ProximityPrompt on the closest named citizens -> SocialAction(id, "talk", {pos}) (the
--     server opens the conversation in the Dialog overlay); the citizen stops, turns to the player and
--     talks with the hands until the dialog closes (GwangalliRemotes.Dialog {close = true}) or the
--     player walks away. Anonymous passers-by get 인사하기: a wave and a short line, client-only.
--   * SocialState "line" events become bubbles + emotes on the citizen; a tier-up makes them cheer.
-- The UI kit (GwangalliUI) is only read for colour / font tokens, never modified. No per-frame work:
-- Crowd calls SocialUI.update at its tick rate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SocialUI = {}

local ctx: any
local player: Player
local Citizens: any
local Social: any
local Config: any
local tiers: { [string]: { a: number, tier: number, met: number } } = {}
local actionRemote: RemoteEvent? = nil
local talking: any = nil
local speaking: { [any]: number } = {} -- agent -> bubble end time

local C = {
	glass = Color3.fromRGB(15, 18, 31),
	text = Color3.fromRGB(245, 247, 251),
	sub = Color3.fromRGB(170, 177, 196),
	bubble = Color3.fromRGB(250, 250, 252),
	bubbleText = Color3.fromRGB(24, 26, 36),
	cyan = Color3.fromRGB(61, 214, 245),
}
local FONT_BOLD = Enum.Font.GothamBold
local FONT_MED = Enum.Font.GothamMedium

local LOCAL_HELLO = {
	"안녕하세요~ 😊",
	"네? 저요? ㅎㅎ 안녕하세요!",
	"광안리 좋죠? 즐거운 시간 보내세요!",
	"아 깜짝이야 ㅋㅋ 안녕하세요!",
	"오늘 바다 진짜 예쁘네요 🌊",
}
local LOCAL_HELLO_NIGHT = {
	"오늘 클럽 오션 가요? 🎶",
	"밤바다 최고죠? ㅎㅎ",
	"안녕하세요~ 좋은 밤 되세요!",
	"줄 서기 전에 빨리 가요! 🎧",
}

local function tierDef(t: number): any
	return Social and Social.TIERS and Social.TIERS[t] or { name = "모르는 사이", icon = "🤍", color = { 190, 190, 200 } }
end

function SocialUI.tier(id: string): number
	local rec = tiers[id]
	if rec then
		return rec.tier
	end
	local c = Citizens and Citizens.get(id)
	if c and Social and Social.tierOf then
		return (Social.tierOf(c.start or 0))
	end
	return 1
end

function SocialUI.met(id: string): boolean
	local rec = tiers[id]
	return rec ~= nil and (rec.met or 0) > 0
end

local function setTier(id: any, a: any, tier: any, met: any)
	if type(id) ~= "string" then
		return
	end
	local rec = tiers[id] or { a = 0, tier = 1, met = 0 }
	if type(a) == "number" then
		rec.a = a
	end
	if type(tier) == "number" then
		rec.tier = math.clamp(math.floor(tier), 1, 5)
	elseif type(a) == "number" and Social then
		rec.tier = (Social.tierOf(a))
	end
	if type(met) == "number" then
		rec.met = met
	end
	tiers[id] = rec
	local agent = ctx.Crowd.byId[id]
	if agent and agent.rig.chip then
		agent.rig.chipDirty = true
	end
end

-------------------------------------------------------------------------------------------------
-- chip + bubble
-------------------------------------------------------------------------------------------------
local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function buildChip(rig: any): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "StreetLifeChip"
	bb.Size = UDim2.fromOffset(190, 118)
	bb.SizeOffset = Vector2.new(0, 0.5)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.2 * rig.scale, 0)
	bb.MaxDistance = 60
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb.Enabled = false
	bb.Adornee = rig.head
	-- speech bubble (top)
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.new(0.5, 0, 1, -50)
	bubble.Size = UDim2.new(1, 0, 0, 0)
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.BackgroundColor3 = C.bubble
	bubble.BackgroundTransparency = 0.04
	bubble.Visible = false
	bubble.Parent = bb
	corner(bubble, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = bubble
	local bt = Instance.new("TextLabel")
	bt.Name = "Text"
	bt.BackgroundTransparency = 1
	bt.Size = UDim2.new(1, 0, 0, 0)
	bt.AutomaticSize = Enum.AutomaticSize.Y
	bt.Font = FONT_MED
	bt.TextSize = 13
	bt.TextWrapped = true
	bt.TextColor3 = C.bubbleText
	bt.Text = ""
	bt.Parent = bubble
	-- name card (bottom)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, 0)
	card.Size = UDim2.fromOffset(150, 42)
	card.BackgroundColor3 = C.glass
	card.BackgroundTransparency = 0.18
	card.Parent = bb
	corner(card, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.86
	stroke.Thickness = 1
	stroke.Parent = card
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(0, 3)
	name.Size = UDim2.new(1, 0, 0, 19)
	name.Font = FONT_BOLD
	name.TextSize = 15
	name.TextColor3 = C.text
	name.Text = ""
	name.Parent = card
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 22)
	sub.Size = UDim2.new(1, 0, 0, 16)
	sub.Font = FONT_MED
	sub.TextSize = 11
	sub.TextColor3 = C.sub
	sub.Text = ""
	sub.Parent = card
	bb.Parent = rig.head
	rig.chip = bb
	rig.chipCard = card
	rig.chipName = name
	rig.chipSub = sub
	rig.chipBubble = bubble
	rig.chipBubbleText = bt
	rig.chipDirty = true
	return bb
end

local function refreshChip(a: any)
	local rig = a.rig
	if not rig.chip then
		buildChip(rig)
	end
	if not rig.chipDirty and rig.chipFor == a.id then
		return
	end
	rig.chipDirty = false
	rig.chipFor = a.id
	if a.named and a.c then
		local t = SocialUI.tier(a.id)
		local def = tierDef(t)
		local col = def.color or { 190, 190, 200 }
		rig.chipName.Text = a.c.name or a.id
		local job = a.c.job or ""
		if #job > 24 then
			job = ""
		end
		local tdef = (a.type and a.type ~= "plain" and Social and Social.TYPES and Social.TYPES[a.type]) or nil
		if tdef then
			-- type hint instead of the job (성깔 / 동네바보 / 천원만 / 비틀) in the type's colour
			rig.chipSub.Text = string.format("%s %s · %s %s", def.icon or "", def.name or "", tdef.icon or "", tdef.short or tdef.label or "")
			local tc = tdef.color or col
			rig.chipSub.TextColor3 = Color3.fromRGB(tc[1], tc[2], tc[3])
		else
			rig.chipSub.Text = string.format("%s %s%s", def.icon or "", def.name or "", if job ~= "" then " · " .. job else "")
			rig.chipSub.TextColor3 = Color3.fromRGB(col[1], col[2], col[3])
		end
		rig.chipCard.Visible = true
	else
		rig.chipCard.Visible = false
	end
end

local function bubblePool(): any
	local B = ctx.BumpShared
	if not B or type(B.bubbles) ~= "function" then
		return nil
	end
	local ok, pool = pcall(B.bubbles, { types = Social and Social.TYPES })
	return if ok then pool else nil
end

function SocialUI.talkingNow(): boolean
	return talking ~= nil and not talking.gone and talking.mode == "talk"
end

function SocialUI.say(a: any, text: string, dur: number?)
	if not a or a.gone or type(text) ~= "string" or text == "" then
		return
	end
	local rig = a.rig
	if not rig.chip then
		buildChip(rig)
	end
	refreshChip(a)
	-- the pooled bubbles (GwangalliBumpShared: <= 10 visible, nearest first, type colours, tail);
	-- the chip's own bubble is the fallback
	local pool = bubblePool()
	local via = "chip"
	if pool and rig.root then
		-- adorned to the root (not the head): the offset is world-space, so the bubble stays above the
		-- person while they lean / lie on the ground, and the root is where the rig really is
		rig.chipBubble.Visible = false
		pool:say(rig.root, text, a.type or "plain", dur or 4, 2.1 * (rig.scale or 1) + 1.2)
		via = "pool"
	else
		rig.chipBubbleText.Text = text
		rig.chipBubble.Visible = true
	end
	rig.chip.Enabled = true
	speaking[a] = os.clock() + (dur or 4)
	if workspace:GetAttribute("GwangalliStreetLifeDebug") == true then
		print(string.format("[StreetLifeSay] %s (%s, %.0f studs, %s): %s", tostring(a.id), a.mode, a.dist or -1, via, text))
	end
end

-------------------------------------------------------------------------------------------------
-- prompts
-------------------------------------------------------------------------------------------------
local function interact(a: any)
	if not a or a.gone then
		return
	end
	local now = os.clock()
	if talking and talking ~= a and not talking.gone then
		talking:endTalk(now)
	end
	if a.named then
		talking = a
		a:beginTalk(now, 30)
		if actionRemote then
			actionRemote:FireServer(a.id, "talk", { pos = a.pos })
		else
			local ok, line = pcall(Citizens.smallTalk, a.id, SocialUI.tier(a.id), ctx.clock(), nil, { name = player.DisplayName })
			if ok and type(line) == "string" then
				SocialUI.say(a, line, 5)
			end
			a.talkUntil = now + 5
		end
	else
		a:beginTalk(now, 4)
		local night = ctx.Night.hype(ctx.clock()) > 0.3
		local list = if night then LOCAL_HELLO_NIGHT else LOCAL_HELLO
		SocialUI.say(a, list[math.random(1, #list)], 3.5)
		a:emote("greet")
	end
end

local function ensurePrompt(a: any): ProximityPrompt
	local rig = a.rig
	local pp = rig.prompt
	if not pp then
		pp = Instance.new("ProximityPrompt")
		pp.Name = "StreetLifeTalk"
		pp.HoldDuration = 0
		pp.MaxActivationDistance = Config.PromptDist
		pp.RequiresLineOfSight = false
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.GamepadKeyCode = Enum.KeyCode.ButtonX
		pp.UIOffset = Vector2.new(0, 0)
		pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		pp.Enabled = false
		pp.Parent = rig.root
		rig.prompt = pp
		pp.Triggered:Connect(function(who)
			if who == player and rig.agent then
				interact(rig.agent)
			end
		end)
	end
	if rig.promptFor ~= a.id then
		rig.promptFor = a.id
		pp.ActionText = if a.named then "말 걸기" else "인사하기"
		pp.ObjectText = if a.named and a.c then a.c.name else ""
	end
	return pp
end

function SocialUI.attach(a: any)
	a.rig.agent = a
	if a.rig.chip then
		a.rig.chipDirty = true
	end
end

function SocialUI.detach(a: any)
	speaking[a] = nil
	if talking == a then
		talking = nil
	end
	local rig = a.rig
	if rig.agent == a then
		rig.agent = nil
	end
	if rig.chip then
		rig.chip.Enabled = false
		rig.chipBubble.Visible = false
	end
	if rig.prompt then
		rig.prompt.Enabled = false
	end
end

-- chips / prompts for the closest people (called from the crowd tick)
local chipSel: { any } = {}
function SocialUI.update(now: number)
	local agents = ctx.Crowd.agents
	local chipMax = if ctx.Crowd.tierVal then ctx.Crowd.tierVal(Config.ChipMax) else (Config.ChipMax[ctx.Quality and ctx.Quality.get() or "low"] or 2)
	table.clear(chipSel)
	for _, a in agents do
		if a.dist <= Config.ChipDist and a.onScreen and (a.named or a.dist <= Config.PromptDist + 2) then
			table.insert(chipSel, a)
		end
	end
	table.sort(chipSel, function(x, y)
		return x.dist < y.dist
	end)
	local chipN, promptN = 0, 0
	local want: { [any]: boolean } = {}
	local wantPrompt: { [any]: boolean } = {}
	for _, a in chipSel do
		if a.named and chipN < chipMax then
			chipN += 1
			want[a] = true
		end
		if promptN < Config.PromptMax and a.dist <= Config.PromptDist + 3 and not a.lying then
			promptN += 1
			wantPrompt[a] = true
		end
	end
	for _, a in agents do
		local rig = a.rig
		local talkingNow = a == talking and a.mode == "talk"
		local sp = speaking[a]
		if sp and now >= sp then
			speaking[a] = nil
			sp = nil
			if rig.chipBubble then
				rig.chipBubble.Visible = false
			end
		end
		local show = want[a] or sp ~= nil or talkingNow
		if show then
			refreshChip(a)
			if not rig.chip.Enabled then
				rig.chip.Enabled = true
			end
		elseif rig.chip and rig.chip.Enabled then
			rig.chip.Enabled = false
		end
		if wantPrompt[a] then
			local pp = ensurePrompt(a)
			if not pp.Enabled then
				pp.Enabled = true
			end
			a.promptSince = a.promptSince or now -- the agent pauses for the player (Agent.react)
		else
			if rig.prompt and rig.prompt.Enabled then
				rig.prompt.Enabled = false
			end
			a.promptSince = nil
			a.heyPaused = nil
		end
	end
	-- the conversation ends when the player walks away
	if talking and not talking.gone and talking.mode == "talk" and talking.dist > 34 then
		talking:endTalk(now)
		talking = nil
	end
end

-------------------------------------------------------------------------------------------------
-- remotes
-------------------------------------------------------------------------------------------------
local function onState(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local kind = msg.kind
	if kind == "snapshot" then
		if type(msg.npcs) == "table" then
			for id, rec in msg.npcs do
				if type(rec) == "table" then
					setTier(id, rec.a, rec.tier, rec.met)
				end
			end
		end
	elseif kind == "affinity" then
		setTier(msg.id, msg.a, msg.tier, nil)
		local rec = type(msg.id) == "string" and tiers[msg.id]
		if rec then
			rec.met = math.max(rec.met or 0, 1)
		end
	elseif kind == "tier" then
		setTier(msg.id, nil, msg.to, nil)
		local a = type(msg.id) == "string" and ctx.Crowd.byId[msg.id]
		if a and msg.up then
			a:emote("cheer")
			if type(msg.text) == "string" then
				SocialUI.say(a, msg.text, 4)
			end
		end
	elseif kind == "line" then
		if type(msg.id) == "string" then
			setTier(msg.id, msg.a, msg.tier, nil)
			local rec = tiers[msg.id]
			if rec then
				rec.met = math.max(rec.met or 0, 1)
			end
			local a = ctx.Crowd.byId[msg.id]
			if a and type(msg.text) == "string" then
				SocialUI.say(a, msg.text, 5)
				a:emote(msg.emote)
			end
		end
	end
end

local function onDialog(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local now = os.clock()
	if payload.close then
		if talking and not talking.gone then
			talking:endTalk(now)
		end
		talking = nil
		return
	end
	local id = payload.npcId
	if type(id) == "string" then
		local a = ctx.Crowd.byId[id]
		if a and not a.gone then
			if a.mode ~= "talk" then
				talking = a
				a:beginTalk(now, 40)
			else
				a.talkUntil = now + 40
			end
			if type(payload.emote) == "string" then
				a:emote(payload.emote)
			end
			if type(payload.tier) == "number" or type(payload.affinity) == "number" then
				setTier(id, payload.affinity, payload.tier, 1)
			end
		end
	end
end

function SocialUI.init(context: any)
	ctx = context
	player = ctx.player
	Citizens = ctx.Citizens
	Social = ctx.Social
	Config = ctx.Config
	local UIK = ctx.UIKit
	if type(UIK) == "table" then
		pcall(function()
			local c = UIK.Color or {}
			C.glass = c.glass or C.glass
			C.text = c.text or C.text
			C.sub = c.sub or C.sub
			C.cyan = c.cyan or C.cyan
			local f = UIK.Font or {}
			if typeof(f.bold) == "EnumItem" then
				FONT_BOLD = f.bold
			end
			if typeof(f.medium) == "EnumItem" then
				FONT_MED = f.medium
			end
		end)
	end
	task.spawn(function()
		local folderName = (Social and Social.Folder) or "GwangalliSocial"
		local folder = ReplicatedStorage:WaitForChild(folderName, 60)
		if not folder then
			return
		end
		local names = (Social and Social.Remote) or { Action = "SocialAction", State = "SocialState", Get = "GetSocial" }
		local act = folder:WaitForChild(names.Action, 20)
		if act and act:IsA("RemoteEvent") then
			actionRemote = act
		end
		local st = folder:WaitForChild(names.State, 20)
		if st and st:IsA("RemoteEvent") then
			st.OnClientEvent:Connect(function(msg)
				local ok, err = pcall(onState, msg)
				if not ok then
					warn("[GwangalliStreetLife] SocialState: " .. tostring(err))
				end
			end)
		end
		local get = folder:WaitForChild(names.Get, 20)
		if get and get:IsA("RemoteFunction") then
			for _ = 1, 5 do
				local ok, snap = pcall(function()
					return get:InvokeServer()
				end)
				if ok and type(snap) == "table" then
					pcall(onState, snap)
					break
				end
				task.wait(3)
			end
		end
	end)
	task.spawn(function()
		local rf = ReplicatedStorage:WaitForChild("GwangalliRemotes", 60)
		local d = rf and rf:WaitForChild("Dialog", 30)
		if d and d:IsA("RemoteEvent") then
			d.OnClientEvent:Connect(function(payload)
				pcall(onDialog, payload)
			end)
		end
	end)
	local _ = Players
end

return SocialUI
