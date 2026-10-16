-- GwangalliKaraokePlus/Bridge: every integration with the owner's existing systems, all optional.
-- A missing or failing system degrades its feature and never errors.
--
--   money    ServerStorage.GwangalliGameplayAPI (BindableFunction: balance / spend / earn / addStats)
--   venue    ServerScriptService.<GwangalliGameplay Folder>.VenueLife (the live table: capped,
--            setAct / clearAct (sing + mic hand prop), fire (Journey hooks), setBoard / submit,
--            ctx.notify, ctx.allowTeleport)
--   progress ServerStorage.GwangalliProgressAPI ("track", player, "karaoke_song", 1)
--   social   ServerStorage.GwangalliSocialAPI ("joint", player, "karaoke")
--   legacy   disables the legacy VenueKaraoke "방 잡기" prompts on the booth panels (kept off)
--   LED      the lobby LEDScreen "Messages" attribute (TOP 인기차트 · 오늘의 노래왕)

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local Bridge = {}

local S: any
local ctxK: any
local life: any = nil -- VenueLife once ready
local lifeTried = false
local inflight: { [Player]: boolean } = {}
local fallbackCaps: { [string]: { day: number, n: number } } = {}

local function log(...)
	if S and S.Config.Debug then
		print("[GwangalliKaraokePlus]", ...)
	end
end

local function bindable(name: string): BindableFunction?
	local f = ServerStorage:FindFirstChild(name)
	if f and f:IsA("BindableFunction") then
		return f
	end
	return nil
end

-- Invokes a BindableFunction in its own thread. Returns ("noapi" | "ok" | "error" | "timeout", value, value2).
-- timeout = nil waits until the call returns (money ops are never abandoned half way).
local function invoke(name: string, timeout: number?, ...: any): (string, any, any)
	local api = bindable(name)
	if not api then
		return "noapi", nil, nil
	end
	local args = table.pack(...)
	local box = { done = false, ok = false, a = nil :: any, b = nil :: any }
	task.spawn(function()
		local ok, a, b = pcall(function()
			return (api :: BindableFunction):Invoke(table.unpack(args, 1, args.n))
		end)
		box.ok, box.a, box.b = ok, a, b
		box.done = true
		if not ok then
			warn("[GwangalliKaraokePlus]", name, tostring(args[1]), "failed:", a)
		end
	end)
	local t0 = os.clock()
	while not box.done do
		if timeout and os.clock() - t0 > timeout then
			return "timeout", nil, nil
		end
		task.wait(0.03)
	end
	if not box.ok then
		return "error", nil, nil
	end
	return "ok", box.a, box.b
end
Bridge.invoke = invoke

-------------------------------------------------------------------------------------------------
-- VenueLife
-------------------------------------------------------------------------------------------------
local function findGameplayFolder(): Instance?
	for _, c in ServerScriptService:GetChildren() do
		if c.Name == "GwangalliGameplay" and c:IsA("Folder") then
			return c
		end
	end
	return nil
end

local function connectLife()
	if lifeTried then
		return
	end
	lifeTried = true
	task.spawn(function()
		local t0 = os.clock()
		local folder = findGameplayFolder()
		while not folder and os.clock() - t0 < 20 do
			task.wait(0.5)
			folder = findGameplayFolder()
		end
		if not folder then
			log("GwangalliGameplay folder not found; venue integration off")
			return
		end
		local mod = folder:WaitForChild("VenueLife", 20)
		if not (mod and mod:IsA("ModuleScript")) then
			log("VenueLife module not found")
			return
		end
		local ok, L = pcall(require, mod)
		if not ok or type(L) ~= "table" then
			warn("[GwangalliKaraokePlus] VenueLife require failed:", L)
			return
		end
		while os.clock() - t0 < 45 do
			if L.V ~= nil and L.ctx ~= nil then
				life = L
				log("VenueLife connected")
				return
			end
			task.wait(0.5)
		end
		log("VenueLife never became ready")
	end)
end

function Bridge.life(): any
	return life
end

function Bridge.hasEconomy(): boolean
	return bindable("GwangalliGameplayAPI") ~= nil
end

-------------------------------------------------------------------------------------------------
-- money (server-authoritative; one op in flight per player)
-------------------------------------------------------------------------------------------------
function Bridge.balance(player: Player): (number?, number?)
	local st, cash, bank = invoke("GwangalliGameplayAPI", 8, "balance", player)
	if st ~= "ok" then
		return nil, nil
	end
	return tonumber(cash) or 0, tonumber(bank) or 0
end

function Bridge.busy(player: Player): boolean
	return inflight[player] == true
end

-- returns "ok" | "money" | "noapi" | "error" | "busy"
function Bridge.spend(player: Player, amount: number, label: string): string
	if inflight[player] then
		return "busy"
	end
	if amount <= 0 then
		return "ok"
	end
	if not bindable("GwangalliGameplayAPI") then
		return "noapi"
	end
	inflight[player] = true
	local st, res = invoke("GwangalliGameplayAPI", nil, "spend", player, math.floor(amount), label)
	inflight[player] = nil
	if st == "ok" then
		return if res == true then "ok" else "money"
	end
	return if st == "noapi" then "noapi" else "error"
end

function Bridge.earn(player: Player, amount: number, label: string): boolean
	if amount <= 0 then
		return false
	end
	local st, res = invoke("GwangalliGameplayAPI", 15, "earn", player, math.floor(amount), label)
	return st == "ok" and res ~= false and res ~= nil
end

-------------------------------------------------------------------------------------------------
-- stats with daily caps (shared keys with the legacy karaoke so nobody double dips)
-------------------------------------------------------------------------------------------------
local function dayKey(): number
	return math.floor(os.time() / 86400)
end

function Bridge.capped(player: Player, key: string, limit: number, delta: { [string]: number }): boolean
	if life and type(life.capped) == "function" then
		local ok, applied, done = pcall(life.capped, player, key, limit, delta)
		if ok then
			return done == true or applied ~= nil
		end
	end
	-- fallback: in-memory daily cap + GameplayAPI addStats
	local k = tostring(player.UserId) .. ":" .. key
	local rec = fallbackCaps[k]
	local today = dayKey()
	if not rec or rec.day ~= today then
		rec = { day = today, n = 0 }
		fallbackCaps[k] = rec
	end
	if rec.n >= limit then
		return false
	end
	local st = invoke("GwangalliGameplayAPI", 8, "addStats", player, delta, "코인노래방")
	if st == "ok" then
		rec.n += 1
		return true
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- acts / hand props (sing + mic, tambourine) — visible to everyone through the game's act driver
-------------------------------------------------------------------------------------------------
local fallbackProps: { [Player]: { Instance } } = {}

local function clearFallbackProp(player: Player)
	for _, inst in fallbackProps[player] or {} do
		if inst.Parent then
			inst:Destroy()
		end
	end
	fallbackProps[player] = nil
end

-- a simple welded mic when VenueLife is not available
local function fallbackMic(player: Player)
	clearFallbackProp(player)
	local ch = player.Character
	local hand = ch and (ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm"))
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local body = Instance.new("Part")
	body.Name = "GwKP_HandMic"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(0.9, 0.22, 0.22)
	body.Color = Color3.fromRGB(30, 32, 36)
	body.Material = Enum.Material.SmoothPlastic
	body.CanCollide, body.CanQuery, body.CanTouch, body.Massless = false, false, false, true
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(0.34, 0.34, 0.34)
	head.Color = Color3.fromRGB(170, 172, 180)
	head.Material = Enum.Material.DiamondPlate
	head.CanCollide, head.CanQuery, head.CanTouch, head.Massless = false, false, false, true
	local yOff = if hand.Name == "RightHand" then -0.25 else -0.9
	body.CFrame = hand.CFrame * CFrame.new(0, yOff, -0.25) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(-20))
	head.CFrame = body.CFrame * CFrame.new(0.55, 0, 0)
	local w1 = Instance.new("WeldConstraint")
	w1.Part0, w1.Part1 = hand, body
	w1.Parent = body
	local w2 = Instance.new("WeldConstraint")
	w2.Part0, w2.Part1 = body, head
	w2.Parent = head
	body.Parent = ch
	head.Parent = ch
	fallbackProps[player] = { body, head }
end

function Bridge.setAct(player: Player, act: string, seconds: number?, prop: string?)
	if life and type(life.setAct) == "function" then
		local ok = pcall(life.setAct, player, act, seconds, prop)
		if ok then
			return
		end
	end
	if prop == "mic" then
		pcall(fallbackMic, player)
	end
end

function Bridge.clearAct(player: Player)
	clearFallbackProp(player)
	if life and type(life.clearAct) == "function" then
		pcall(life.clearAct, player)
	end
end

-------------------------------------------------------------------------------------------------
-- Journey / Progress / Social
-------------------------------------------------------------------------------------------------
-- VenueEvent payloads use room = 0 so the legacy client never opens its own picker.
function Bridge.journey(player: Player, payload: any)
	if life and type(life.fire) == "function" then
		pcall(life.fire, player, payload)
	end
end

function Bridge.track(player: Player, key: string, n: number)
	task.spawn(invoke, "GwangalliProgressAPI", 10, "track", player, key, n)
end

function Bridge.joint(player: Player, kind: string)
	task.spawn(invoke, "GwangalliSocialAPI", 10, "joint", player, kind)
end

-------------------------------------------------------------------------------------------------
-- notify / teleport permission
-------------------------------------------------------------------------------------------------
-- returns true when the game's own toast was used
function Bridge.notify(player: Player, kind: string, title: string, body: string?): boolean
	local c = life and life.ctx
	if c and type(c.notify) == "function" then
		local ok = pcall(c.notify, player, kind, title, body)
		return ok
	end
	return false
end

function Bridge.allowTeleport(player: Player, seconds: number)
	local c = life and life.ctx
	if c and type(c.allowTeleport) == "function" then
		pcall(c.allowTeleport, player, seconds)
	end
end

-------------------------------------------------------------------------------------------------
-- 오늘의 노래왕 board (VenueBoard "karaoke") and the lobby LED
-------------------------------------------------------------------------------------------------
local king: { any } = {}

function Bridge.kingList(): { any }
	return king
end

-- returns the rank (1..5) or 0
function Bridge.submitKing(entry: any): number
	local rank = 0
	if life and type(life.submit) == "function" then
		local ok, r = pcall(life.submit, king, entry, 5)
		rank = if ok and type(r) == "number" then r else 0
	else
		for i, e in king do
			if e.userId == entry.userId then
				if entry.score <= e.score then
					return i
				end
				table.remove(king, i)
				break
			end
		end
		local pos = #king + 1
		for i, e in king do
			if entry.score > e.score then
				pos = i
				break
			end
		end
		table.insert(king, pos, entry)
		while #king > 5 do
			table.remove(king)
		end
		rank = if pos <= 5 then pos else 0
	end
	return rank
end

function Bridge.writeBoard()
	if not S.Config.WriteBoard then
		return
	end
	local rows = {}
	for i = 1, 5 do
		local e = king[i]
		if e then
			rows[i] = string.format("%d.  %s · %d점 · %s", i, e.name, e.score, e.title or "")
		else
			rows[i] = string.format("%d.  -", i)
		end
	end
	if life and type(life.setBoard) == "function" then
		pcall(life.setBoard, "karaoke", rows)
	end
end

local ledParts: { BasePart } = {}

function Bridge.findLED(venues: { Instance })
	table.clear(ledParts)
	for _, p in CollectionService:GetTagged("LEDScreen") do
		if not p:IsA("BasePart") then
			continue
		end
		for _, v in venues do
			if p:IsDescendantOf(v) then
				table.insert(ledParts, p)
				break
			end
		end
	end
end

local lastLED = ""
function Bridge.writeLED(msg: string)
	if not S.Config.WriteLED or msg == lastLED then
		return
	end
	lastLED = msg
	for _, p in ledParts do
		if p.Parent then
			pcall(p.SetAttribute, p, "Messages", msg)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- legacy takeover: keep the VenueKaraoke server prompts on the panels disabled
-------------------------------------------------------------------------------------------------
local watched: { [Instance]: boolean } = {}

local function keepOff(pr: ProximityPrompt)
	if watched[pr] then
		return
	end
	watched[pr] = true
	pr.Enabled = false
	pr:GetPropertyChangedSignal("Enabled"):Connect(function()
		if pr.Enabled then
			pr.Enabled = false
		end
	end)
	pr.Destroying:Connect(function()
		watched[pr] = nil
	end)
end

function Bridge.takeOver(panels: { BasePart })
	for _, panel in panels do
		for _, d in panel:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				keepOff(d)
			end
		end
		panel.DescendantAdded:Connect(function(d)
			if d:IsA("ProximityPrompt") then
				keepOff(d)
			end
		end)
	end
end

-- waits (yielding) until the legacy prompt exists on at least one panel, at most `timeout` s
function Bridge.waitLegacy(panels: { BasePart }, timeout: number): boolean
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		for _, panel in panels do
			if panel:FindFirstChild("GwangalliKaraokePrompt", true) then
				return true
			end
		end
		task.wait(0.5)
	end
	return false
end

function Bridge.init(k: any)
	ctxK = k
	S = k.S
	connectLife()
	Players.PlayerRemoving:Connect(function(p)
		inflight[p] = nil
		clearFallbackProp(p)
	end)
end

return Bridge
