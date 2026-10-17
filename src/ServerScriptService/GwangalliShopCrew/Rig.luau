-- GwangalliShopCrew/Rig: crew / diner rigs and the NPC attribute contract (GwangalliGameplay/NPC.luau).
-- The server never animates: it writes attributes and GwangalliNPCClient (tag GwShopStaff) does the rest.
--   Rig.build(spec) -> R?   spec = { id, name, persona, role, shop, pos, yaw, kind = "crew" | "diner", avatar?,
--                                    look?, prompt? (bool), folder? }
--   Rig.destroy(R)          Rig.alive(R) -> bool
--   Rig.place(R, pos, yaw?)                       standing still (static leg + root pivot)
--   Rig.walk(R, pts, speed) -> seconds            one polyline leg "P;t0;speed;x,y,z;..." (feet level)
--   Rig.arrive(R)                                 the root jumps to the leg's end (prompt + server position)
--   Rig.feet(R) -> Vector3                        where the rig is now (interpolated while walking)
--   Rig.face(R, pos) / Rig.setYaw(R, deg)   Rig.act(R, act)   Rig.emote(R, name)   Rig.look(R, uid) / Rig.talk(R, uid)
--   Rig.carry(R, str)   Rig.say(R, text, dur?, tone?)   Rig.sit(R, seatTop, faceTo)
-- R = { id, model, root, head, ground, role, persona, shop, kind, pos (feet), yaw, token, act, carry, walking? }

local CollectionService = game:GetService("CollectionService")

local Rig = {}

local Shared: any = nil
local Config: any = nil
local Bridge: any = nil
local Net: any = nil
local Util: any = nil

local serial = 0
local live: { [string]: any } = {}
local onTalk: ((Player, any) -> ())? = nil
local folders: { [string]: Folder } = {}

function Rig.init(S: any, B: any, N: any)
	Shared, Config, Bridge, Net, Util = S, S.Config, B, N, S.Util
end

-- the server calls this when a player presses a rig's 대화하기 prompt
function Rig.onTalk(fn: (Player, any) -> ())
	onTalk = fn
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function folder(name: string): Folder
	local f = folders[name]
	if f and f.Parent then
		return f
	end
	local w = workspace:FindFirstChild(Shared.WORLD)
	if not w then
		w = Instance.new("Folder")
		w.Name = Shared.WORLD
		w.Parent = workspace
	end
	local sub = w:FindFirstChild(name)
	if not sub then
		sub = Instance.new("Folder")
		sub.Name = name
		sub.Parent = w
	end
	folders[name] = sub :: Folder
	return sub :: Folder
end
Rig.folder = folder

local function fmtV(p: Vector3): string
	return string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z)
end

local function staticLeg(R: any, p: Vector3)
	R.model:SetAttribute("NpcLeg", string.format("%s,%s,%.2f,0", fmtV(p), fmtV(p), serverNow()))
end

local function pivot(R: any, p: Vector3, yaw: number)
	pcall(function()
		R.model:PivotTo(CFrame.new(p + Vector3.new(0, R.ground, 0)) * CFrame.Angles(0, math.rad(yaw), 0))
	end)
end

function Rig.alive(R: any?): boolean
	return R ~= nil and not R.dead and R.model ~= nil and R.model.Parent ~= nil
end

function Rig.build(spec: any): any?
	local Looks = Bridge.Looks
	if not Looks then
		return nil
	end
	local persona = spec.persona or {}
	local look = spec.look or persona.look or {}
	local okB, rig = pcall(function()
		local s = Looks.random(spec.seed or spec.id, { body = look.body, age = look.age, style = look.style, night = look.night })
		return Looks.build(s, { name = spec.name or spec.id, anchored = true, shadow = false, avatar = spec.avatar })
	end)
	if not okB or type(rig) ~= "table" or not rig.model then
		Bridge.warnOnce("rig", "rig build failed: " .. tostring(rig))
		return nil
	end
	local m: Model = rig.model
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local root = rig.root or m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	if not root then
		m:Destroy()
		return nil
	end
	local A = Shared.ATTR
	local yaw = spec.yaw or 0
	local ground = tonumber(rig.ground) or 3
	m:SetAttribute("NpcId", spec.id)
	m:SetAttribute("NpcKind", "shop")
	m:SetAttribute("NpcGround", ground)
	m:SetAttribute("NpcAct", spec.act or "idle")
	m:SetAttribute("NpcYaw", yaw)
	m:SetAttribute("NpcLook", 0)
	m:SetAttribute("NpcTalk", 0)
	m:SetAttribute("NpcEmote", "")
	m:SetAttribute(A.Shop, spec.shop or "")
	m:SetAttribute(A.Role, spec.role or "staff")
	m:SetAttribute(A.Carry, "")
	if spec.kind == "diner" then
		m:SetAttribute("ShopCustomer", true)
		m:SetAttribute("GwWaiter", "diner") -- (GwangalliShopService never picks a diner as its voice)
	else
		m:SetAttribute("ShopStaff", persona.title or "직원")
		m:SetAttribute(A.Name, persona.full or "")
		m:SetAttribute(A.Title, persona.title or "")
		m:SetAttribute(A.Icon, persona.icon or "")
		if spec.color then
			m:SetAttribute(A.Color, spec.color)
		end
	end
	-- a block rig without AvatarId would be dressed into a frozen statue by GwangalliStaticNpcSkins
	if m:GetAttribute("AvatarId") == nil then
		m:SetAttribute("AvatarId", "crew_block")
	end
	local R: any = {
		id = spec.id,
		model = m,
		root = root,
		head = rig.head or m:FindFirstChild("Head"),
		ground = ground,
		role = spec.role,
		persona = persona,
		shop = spec.shop,
		kind = spec.kind or "crew",
		pos = spec.pos,
		yaw = yaw,
		token = 0,
		act = spec.act or "idle",
		carry = "",
		avatar = rig.avatar == true,
		lastSay = 0,
	}
	staticLeg(R, spec.pos)
	pivot(R, spec.pos, yaw)
	if spec.prompt then
		local pr = Instance.new("ProximityPrompt")
		pr.Name = Shared.PROMPT
		pr.ActionText = "대화하기"
		pr.ObjectText = persona.title or "직원"
		pcall(function()
			pr.KeyboardKeyCode = (Enum.KeyCode :: any)[Config.TALK_KEY]
		end)
		pcall(function()
			pr.GamepadKeyCode = (Enum.KeyCode :: any)[Config.TALK_PAD]
		end)
		pr.HoldDuration = 0
		pr.MaxActivationDistance = Config.TALK_DIST
		pr.RequiresLineOfSight = false
		pcall(function()
			pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		end)
		pr.UIOffset = Vector2.new(0, 40)
		pr.Parent = root
		pr.Triggered:Connect(function(player)
			if onTalk then
				onTalk(player, R)
			end
		end)
		R.prompt = pr
	end
	CollectionService:AddTag(m, Shared.TAG)
	CollectionService:AddTag(m, Shared.NPC_TAG)
	m.Parent = folder(if spec.kind == "diner" then "Diners" else "Staff")
	-- tag last: GwangalliNPCClient picks the model up with every attribute in place
	CollectionService:AddTag(m, Shared.STAFF_TAG)
	live[spec.id] = R
	return R
end

function Rig.destroy(R: any?)
	if not R then
		return
	end
	R.dead = true
	R.token += 1
	live[R.id] = nil
	if R.proxy then
		pcall(function()
			R.proxy:Destroy()
		end)
		R.proxy = nil
	end
	if R.model then
		pcall(function()
			R.model:Destroy()
		end)
	end
end

function Rig.byId(id: string): any?
	return live[id]
end

function Rig.all(): { [string]: any }
	return live
end

-------------------------------------------------------------------------------------------------
-- motion
-------------------------------------------------------------------------------------------------
function Rig.feet(R: any): Vector3
	local w = R.walking
	if not w then
		return R.pos
	end
	local t = serverNow() - w.t0
	if t <= 0 then
		return w.pts[1]
	end
	local d = t * w.speed
	for i = 2, #w.pts do
		local seg = (w.pts[i] - w.pts[i - 1]).Magnitude
		if d <= seg then
			return w.pts[i - 1]:Lerp(w.pts[i], if seg > 0 then d / seg else 1)
		end
		d -= seg
	end
	return w.pts[#w.pts]
end

function Rig.setYaw(R: any, yaw: number)
	R.yaw = yaw
	R.model:SetAttribute("NpcYaw", yaw)
end

function Rig.face(R: any, pos: Vector3?)
	if not pos or not Rig.alive(R) then
		return
	end
	local f = Rig.feet(R)
	local d = Vector3.new(pos.X - f.X, 0, pos.Z - f.Z)
	if d.Magnitude > 0.2 then
		Rig.setYaw(R, Util.yaw(d.X, d.Z))
	end
end

function Rig.place(R: any, pos: Vector3, yaw: number?)
	if not Rig.alive(R) then
		return
	end
	R.walking = nil
	R.pos = pos
	if yaw then
		R.yaw = yaw
		R.model:SetAttribute("NpcYaw", yaw)
	end
	staticLeg(R, pos)
	pivot(R, pos, R.yaw)
	if R.prompt then
		R.prompt.Enabled = true
	end
end

-- start a walk along pts (feet level); returns the walk time. The rig keeps its old root until Rig.arrive.
function Rig.walk(R: any, pts: { Vector3 }, speed: number): number
	if not Rig.alive(R) or #pts == 0 then
		return 0
	end
	local clean = {}
	for _, p in pts do
		local q = Vector3.new(math.round(p.X * 20) / 20, math.round(p.Y * 100) / 100, math.round(p.Z * 20) / 20)
		if #clean == 0 or (q - clean[#clean]).Magnitude > 0.05 then
			table.insert(clean, q)
		end
	end
	if #clean < 2 then
		Rig.place(R, clean[1] or R.pos, nil)
		return 0
	end
	local total = 0
	for i = 2, #clean do
		total += (clean[i] - clean[i - 1]).Magnitude
	end
	local t0 = math.round((serverNow() + 0.15) * 100) / 100
	local buf = { "P", string.format("%.2f", t0), string.format("%.3f", speed) }
	for _, p in clean do
		table.insert(buf, fmtV(p))
	end
	local s = table.concat(buf, ";")
	if #s > 3800 then
		-- (attribute strings stay small: a shop path is a handful of corners, this never happens in practice)
		clean = { clean[1], clean[#clean] }
		s = string.format("P;%.2f;%.3f;%s;%s", t0, speed, fmtV(clean[1]), fmtV(clean[2]))
		total = (clean[2] - clean[1]).Magnitude
	end
	local d = clean[2] - clean[1]
	if Vector3.new(d.X, 0, d.Z).Magnitude > 0.05 then
		R.yaw = Util.yaw(d.X, d.Z)
		R.model:SetAttribute("NpcYaw", R.yaw)
	end
	R.model:SetAttribute("NpcLeg", s)
	R.walking = { pts = clean, t0 = t0, speed = speed, total = total }
	R.target = clean[#clean]
	if R.prompt then
		R.prompt.Enabled = false
	end
	return total / speed + 0.2
end

-- the walk is over: the server position follows (prompt, distance checks, the next leg's start)
function Rig.arrive(R: any, yaw: number?)
	if not Rig.alive(R) then
		return
	end
	local at = R.target or Rig.feet(R)
	R.walking = nil
	R.target = nil
	R.pos = at
	if yaw then
		R.yaw = yaw
		R.model:SetAttribute("NpcYaw", yaw)
	end
	staticLeg(R, at)
	pivot(R, at, R.yaw)
	if R.prompt then
		R.prompt.Enabled = true
	end
end

-- stop where the rig is now (an interrupted walk)
function Rig.halt(R: any)
	if not Rig.alive(R) then
		return
	end
	local here = Rig.feet(R)
	R.walking = nil
	R.target = nil
	Rig.place(R, here, nil)
end

-- seated diner: feet just below the seat top (GwangalliGameplay Play/Actors numbers), facing the table
function Rig.sit(R: any, seatTop: Vector3, faceTo: Vector3?)
	if not Rig.alive(R) then
		return
	end
	local yaw = R.yaw
	if faceTo then
		local d = Vector3.new(faceTo.X - seatTop.X, 0, faceTo.Z - seatTop.Z)
		if d.Magnitude > 0.1 then
			yaw = Util.yaw(d.X, d.Z)
		end
	end
	local feet = seatTop - Vector3.new(0, Config.SIT_DROP, 0)
	Rig.place(R, feet, yaw)
	Rig.act(R, "sit")
end

-------------------------------------------------------------------------------------------------
-- body language / props / voice
-------------------------------------------------------------------------------------------------
function Rig.act(R: any, act: string)
	if not Rig.alive(R) then
		return
	end
	R.act = act
	R.model:SetAttribute("NpcAct", act)
end

function Rig.emote(R: any, name: string)
	if not Rig.alive(R) then
		return
	end
	serial += 1
	R.model:SetAttribute("NpcEmote", string.format("%s#%d#%.2f", name, serial, serverNow()))
end

function Rig.look(R: any, uid: number?)
	if Rig.alive(R) then
		R.model:SetAttribute("NpcLook", uid or 0)
	end
end

function Rig.talk(R: any, uid: number?)
	if Rig.alive(R) then
		R.model:SetAttribute("NpcTalk", uid or 0)
	end
end

function Rig.carry(R: any, s: string?)
	if not Rig.alive(R) then
		return
	end
	R.carry = s or ""
	R.model:SetAttribute(Shared.ATTR.Carry, R.carry)
end

-- a speech bubble over the rig for the players near it (client: GwangalliBubble pool, own fallback)
function Rig.say(R: any, text: string?, dur: number?, tone: string?)
	if not Rig.alive(R) or type(text) ~= "string" or text == "" then
		return
	end
	local t = os.clock()
	if t - R.lastSay < 0.9 then
		-- two lines in a row: the second one waits a moment instead of overwriting the first
		local wait = 0.9 - (t - R.lastSay)
		R.lastSay = t + wait
		task.delay(wait, function()
			if Rig.alive(R) then
				Net.fireNear(Rig.feet(R), Config.SAY_R, "say", { id = R.id, text = text, dur = dur or 3.6, tone = tone or "plain" })
			end
		end)
		return
	end
	R.lastSay = t
	Net.fireNear(Rig.feet(R), Config.SAY_R, "say", { id = R.id, text = text, dur = dur or 3.6, tone = tone or "plain" })
end

-- an invisible part that opens the shop's auto door while a diner walks through it (GwangalliDoors:
-- anything tagged AutoDoorOpener opens the doors near it)
function Rig.doorProxy(R: any, at: Vector3, from: number, untilT: number)
	task.delay(math.max(0, from), function()
		if not Rig.alive(R) then
			return
		end
		local p = Instance.new("Part")
		p.Name = "CrewDoorOpener"
		p.Size = Vector3.new(1, 4, 1)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(at + Vector3.new(0, 2.5, 0))
		CollectionService:AddTag(p, "AutoDoorOpener")
		p.Parent = folder("Fx")
		R.proxy = p
		task.delay(math.max(0.5, untilT - from), function()
			if p.Parent then
				p:Destroy()
			end
			if R.proxy == p then
				R.proxy = nil
			end
		end)
	end)
end

return Rig
