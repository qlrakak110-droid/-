-- GwangalliCarDealer/NpcFx (client): life for the dealer NPCs.
--   * our own consultant rigs (attribute DealerOwnRig = true): idle animation + GwangalliAnim rig controller
--     (look at the player within C.UI.lookRadius, a small wave + "어서 오세요" bubble the first time the player
--     comes close, talk / listen gestures during the dialog, give / bow / clap emotes at the delivery)
--   * hooked map staff (박사장): never animated or moved (their pose is the map's); bubbles only
--   * name tags and speech bubbles are BillboardGuis in PlayerGui with Adornee (never under map parts)
--   NpcFx.say(id, text, seconds?)   NpcFx.talk(id, "talk" | "listen" | nil)   NpcFx.emote(id, name)
--   NpcFx.focus(id | nil)           (the NPC keeps looking at the player while the dialog is open)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcFx = {}

local player = Players.LocalPlayer
local ctx: any
local Ui: any
local N: any
local C: any
local Anim: any = nil

type Rig = { inst: Instance, id: string, ours: boolean, head: BasePart?, root: BasePart?, ctl: any, tag: BillboardGui?, bubble: BillboardGui?, bubbleText: TextLabel?, greetedAt: number, near: boolean }
local rigs: { [Instance]: Rig } = {}
local focusId: string? = nil

local function pgui(): Instance
	return player:WaitForChild("PlayerGui")
end

local function myRoot(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function myHead(): Vector3?
	local ch = player.Character
	local h = ch and ch:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h.Position
	end
	local r = myRoot()
	return r and (r.Position + Vector3.new(0, 1.5, 0)) or nil
end

local function adorneeOf(inst: Instance): (BasePart?, BasePart?)
	if inst:IsA("BasePart") then
		-- a hook anchor: its rig's head when the rig is streamed in
		local ref = inst:FindFirstChild("Rig")
		local rig = ref and ref:IsA("ObjectValue") and ref.Value
		local head = rig and rig:FindFirstChild("Head", true)
		if head and head:IsA("BasePart") then
			return head, inst
		end
		return inst, inst
	end
	local head = inst:FindFirstChild("Head")
	local root = inst:FindFirstChild("HumanoidRootPart")
	return (if head and head:IsA("BasePart") then head else nil), (if root and root:IsA("BasePart") then root else nil)
end

local function makeTag(r: Rig)
	if not r.ours or not r.head then
		return -- map staff carry their own name tags
	end
	local name = r.inst:GetAttribute(N.AttrName) or "딜러"
	local role = r.inst:GetAttribute(N.AttrRole) or "차량 상담"
	local bb = Ui.make("BillboardGui", {
		Name = "GwDealerTag_" .. r.id,
		Adornee = r.head,
		Size = UDim2.fromOffset(200, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0),
		AlwaysOnTop = false,
		MaxDistance = 36,
		LightInfluence = 0,
		ResetOnSpawn = false,
	}, pgui())
	local box = Ui.frame(bb, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(170, 40), BackgroundTransparency = 0.12, BackgroundColor3 = Ui.C.bg2 })
	Ui.corner(box, 12)
	Ui.stroke(box, Ui.C.accent, 1, 0.45)
	Ui.label(box, { Text = "💬 " .. tostring(name), Font = Ui.F.bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 2), TextXAlignment = Enum.TextXAlignment.Center })
	Ui.label(box, { Text = tostring(role) .. " · 차량 상담", Font = Ui.F.med, TextSize = 11, TextColor3 = Ui.C.sub, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	r.tag = bb
end

local function makeBubble(r: Rig)
	if r.bubble or not r.head then
		return
	end
	local bb = Ui.make("BillboardGui", {
		Name = "GwDealerBubble_" .. r.id,
		Adornee = r.head,
		Size = UDim2.fromOffset(260, 70),
		StudsOffsetWorldSpace = Vector3.new(0, if r.ours then 3.6 else 2.6, 0),
		AlwaysOnTop = true,
		MaxDistance = 40,
		LightInfluence = 0,
		Enabled = false,
		ResetOnSpawn = false,
	}, pgui())
	local box = Ui.frame(bb, { Name = "Box", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(240, 44), BackgroundTransparency = 0.04, BackgroundColor3 = Ui.C.white })
	Ui.corner(box, 14)
	Ui.pad(box, 10, 10, 6, 6)
	local t = Ui.label(box, { Name = "Text", Size = UDim2.fromScale(1, 1), Font = Ui.F.bold, TextSize = 13, TextColor3 = Color3.fromRGB(24, 28, 38), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
	r.bubble = bb
	r.bubbleText = t
end

-- Our "딜러와 상담하기" prompts hide (locally) while a dealer screen is up, so they never float over it.
local hideKeys: { [string]: boolean } = {}
local function applyPrompts(inst: Instance)
	local hidden = next(hideKeys) ~= nil
	for _, d in inst:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute(N.AttrNpc) ~= nil then
			d.Enabled = not hidden
		end
	end
end

local function register(inst: Instance)
	if rigs[inst] then
		return
	end
	local id = inst:GetAttribute(N.AttrNpc)
	if type(id) ~= "string" then
		return
	end
	local head, root = adorneeOf(inst)
	local r: Rig = { inst = inst, id = id, ours = inst:GetAttribute(N.AttrOurs) == true, head = head, root = root, ctl = nil, greetedAt = -1e9, near = false }
	rigs[inst] = r
	if r.ours and Anim and inst:IsA("Model") then
		pcall(function()
			Anim.play(inst, "idle", { offset = true })
			r.ctl = Anim.rig(inst)
		end)
	end
	makeTag(r)
	applyPrompts(inst)
	inst.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(applyPrompts, inst)
		end
	end)
	inst.AncestryChanged:Connect(function()
		if not inst:IsDescendantOf(workspace) then
			local rr = rigs[inst]
			if rr then
				if rr.tag then
					rr.tag:Destroy()
				end
				if rr.bubble then
					rr.bubble:Destroy()
				end
				rigs[inst] = nil
			end
		end
	end)
end

local function byId(id: string): Rig?
	for _, r in rigs do
		if r.id == id then
			return r
		end
	end
	return nil
end

function NpcFx.find(id: string): Instance?
	local r = byId(id)
	return r and r.inst or nil
end

-- Position of a dealer (for the dialog's walk-away check).
function NpcFx.position(id: string): Vector3?
	local r = byId(id)
	if not r then
		return nil
	end
	local p = r.root or r.head
	if p and p.Parent then
		return p.Position
	end
	if r.inst:IsA("BasePart") then
		return r.inst.Position
	end
	return nil
end

function NpcFx.say(id: string, text: string, seconds: number?)
	local r = byId(id)
	if not r then
		return
	end
	makeBubble(r)
	local bb, t = r.bubble, r.bubbleText
	if not bb or not t then
		return
	end
	t.Text = text
	local w = math.clamp(Ui.textWidth(text, 13, Ui.F.bold) + 28, 90, 240)
	local lines = math.ceil((Ui.textWidth(text, 13, Ui.F.bold) + 28) / 240)
	local box = bb:FindFirstChild("Box") :: Frame
	box.Size = UDim2.fromOffset(w, 26 + lines * 16)
	bb.Enabled = true
	local stampT = os.clock()
	bb:SetAttribute("At", stampT)
	task.delay(seconds or 3.5, function()
		if bb.Parent and bb:GetAttribute("At") == stampT then
			bb.Enabled = false
		end
	end)
end

function NpcFx.talk(id: string, mode: string?)
	local r = byId(id)
	if r and r.ctl then
		pcall(function()
			r.ctl:gesture(mode)
		end)
	end
end

function NpcFx.emote(id: string, name: string)
	local r = byId(id)
	if r and r.ctl then
		pcall(function()
			r.ctl:emote(name)
		end)
	end
end

function NpcFx.hidePrompts(key: string, on: boolean)
	hideKeys[key] = if on then true else nil
	for inst in rigs do
		applyPrompts(inst)
	end
end

function NpcFx.focus(id: string?)
	focusId = id
	if not id then
		for _, r in rigs do
			if r.ctl then
				pcall(function()
					r.ctl:gesture(nil)
				end)
			end
		end
	end
end

function NpcFx.init(c: any)
	ctx = c
	Ui = c.Ui
	N = c.S.NAMES
	C = c.C
	local am = ReplicatedStorage:FindFirstChild("GwangalliAnim")
	if am and am:IsA("ModuleScript") then
		local ok, A = pcall(require, am)
		if ok and type(A) == "table" then
			Anim = A
		end
	end
	for _, inst in CollectionService:GetTagged(N.TagNpc) do
		task.spawn(register, inst)
	end
	CollectionService:GetInstanceAddedSignal(N.TagNpc):Connect(function(inst)
		task.defer(register, inst)
	end)
	RunService.RenderStepped:Connect(function()
		local root = myRoot()
		local head = myHead()
		if not root or not head then
			return
		end
		local now = os.clock()
		for inst, r in rigs do
			local at = r.root or r.head
			if not at or not at.Parent then
				-- re-resolve after streaming
				r.head, r.root = adorneeOf(inst)
				at = r.root or r.head
				if r.tag and r.head then
					r.tag.Adornee = r.head
				end
				if r.bubble and r.head then
					r.bubble.Adornee = r.head
				end
			end
			if at then
				local d = (at.Position - root.Position).Magnitude
				local wasNear = r.near
				r.near = d <= C.UI.greetRadius
				if r.near and not wasNear and now - r.greetedAt > C.UI.bubbleCooldown and focusId ~= r.id then
					r.greetedAt = now
					local voice = inst:GetAttribute(N.AttrVoice)
					NpcFx.say(r.id, if voice == "boss" then "어서 오이소! 차 보러 왔능교? 🚗" else "어서 오세요! 광안 오토입니다 😊", 3.2)
					if r.ctl then
						pcall(function()
							r.ctl:emote("wave_small")
						end)
					end
				end
				if r.ctl and d <= 60 then
					pcall(function()
						if focusId == r.id or d <= C.UI.lookRadius then
							r.ctl:look(head)
						else
							r.ctl:look(nil)
						end
						r.ctl:step()
					end)
				end
			end
		end
	end)
end

return NpcFx
