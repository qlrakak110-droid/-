-- GwangalliClinic (client): 광안 메디컬 의원 "진료 보기". Renders the server's visit state machine:
-- kiosk · 접수 dialog + 문진표 · call banner + 딩동 · LED / TV / pharmacy screens · 진료실 (camera, doctor
-- dialogue, 진찰 minigames, 진단 카드, 치료 계획) · 처치 / 수액 · 수납 영수증 · 처방전 · 약국 복약 안내 ·
-- 건강검진 코스 · 진료 기록 · 입원실. Waits for GwangalliClinicShared.State.Active (the server boots after
-- the game's Health system); until then nothing of ours shows and the legacy hospital stays as it is.
--
-- ctx (shared by the modules): S, C, player, sharedModule, state, Ui, Net, visit (latest VisitView or nil),
-- health (latest health view), meds, call(op, payload) -> reply, anchor(name) -> BasePart?, flow (step token)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliClinicShared", 120)
if not (sharedModule and sharedModule:IsA("ModuleScript")) then
	return
end
local okS, S = pcall(require, sharedModule)
if not okS or type(S) ~= "table" or not S.Config.Enabled then
	return
end

-- the server publishes State.Active once it is fully up (it may never be, if the Health system is off)
local state = sharedModule:WaitForChild(S.NAMES.State, 180) :: Configuration?
if not state then
	return
end
while state:GetAttribute("Active") ~= true do
	state:GetAttributeChangedSignal("Active"):Wait()
end

local ctx: any = {
	S = S,
	C = S.Config,
	player = player,
	sharedModule = sharedModule,
	state = state,
	visit = nil,
	health = nil,
	meds = nil,
	flow = 0,
}

local function mod(name: string): any
	local m = require(script:WaitForChild(name))
	ctx[name] = m
	return m
end

local Ui = mod("Ui")
local Net = mod("Net")
local order = { "Screens", "Staff", "Prompts", "Tracker", "Desk", "Consult", "Treat", "Pharmacy", "Checkup", "Chart" }
local modules = {}
for _, n in order do
	table.insert(modules, mod(n))
end

Ui.init(ctx)
if not Net.init(ctx) then
	return
end

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local world = workspace:WaitForChild(S.NAMES.World, 60)
local anchorsModel = world and world:WaitForChild(S.NAMES.Anchors, 30)

function ctx.anchor(name: string): BasePart?
	local a = anchorsModel and anchorsModel:FindFirstChild(name)
	if a and a:IsA("BasePart") then
		return a
	end
	return nil
end

function ctx.anchors(): { BasePart }
	local out = {}
	if anchorsModel then
		for _, c in anchorsModel:GetChildren() do
			if c:IsA("BasePart") then
				table.insert(out, c)
			end
		end
	end
	return out
end

function ctx.rootPos(): Vector3?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else nil
end

local function forEach(fnName: string, ...: any)
	for _, m in modules do
		local fn = m[fnName]
		if type(fn) == "function" then
			local ok, err = pcall(fn, ...)
			if not ok then
				warn("[GwangalliClinic]", fnName, err)
			end
		end
	end
end

function ctx.setVisit(v: any?)
	local prev = ctx.visit
	ctx.visit = v
	if v and v.health then
		ctx.health = v.health
	end
	if (prev and prev.step) ~= (v and v.step) or (prev and prev.id) ~= (v and v.id) then
		ctx.flow += 1
	end
	forEach("onVisit", v, prev)
end

function ctx.setHealth(h: any?)
	if h then
		ctx.health = h
		if h.meds ~= nil then
			ctx.meds = h.meds
		end
		forEach("onHealth", h)
	end
end

-- request + Korean failure toast + visit refresh
function ctx.call(op: string, payload: any?, opts: any?): any
	local res = Net.call(op, payload)
	if type(res) ~= "table" then
		return { ok = false }
	end
	if res.visit ~= nil then
		ctx.setVisit(res.visit)
	end
	if res.health then
		ctx.setHealth(res.health)
	end
	if res.meds ~= nil then
		ctx.meds = res.meds
		forEach("onMeds", res.meds)
	end
	if res.ok ~= true and not (opts and opts.quiet) and res.message and res.code ~= "busy" then
		Ui.toast(res.message, nil, "warn")
	end
	return res
end

-------------------------------------------------------------------------------------------------
-- events
-------------------------------------------------------------------------------------------------
Net.on("visit", function(p)
	ctx.setVisit(p.visit)
end)
Net.on("health", function(p)
	ctx.setHealth(p.health)
end)
Net.on("toast", function(p)
	Ui.toast(p.title or "", p.body, p.tone)
end)
Net.on("line", function(p)
	if type(p.text) == "string" then
		Ui.say(p.who or "system", p.text, { name = p.name })
	end
end)
Net.on("done", function(p)
	ctx.setVisit(nil)
	if p.health then
		ctx.setHealth(p.health)
	end
	ctx.meds = p.meds
	forEach("onMeds", p.meds)
	forEach("onDone", p)
end)
Net.on("call", function(p)
	forEach("onCall", p)
end)
Net.on("report", function(p)
	forEach("onReport", p.report)
end)
Net.on("ward", function(p)
	if p.health then
		ctx.setHealth(p.health)
	end
	forEach("onWard", p)
end)

for _, m in modules do
	if type(m.init) == "function" then
		local ok, err = pcall(m.init, ctx)
		if not ok then
			warn("[GwangalliClinic] init failed:", err)
		end
	end
end

local function hello()
	local res = Net.call("hello", {})
	if type(res) == "table" and res.ok then
		ctx.fees = res.fees
		ctx.chart = res.chart
		ctx.report = res.report
		ctx.meds = res.meds
		ctx.ward = res.ward
		ctx.setHealth(res.health)
		forEach("onMeds", res.meds)
		ctx.setVisit(res.visit)
	end
end
task.spawn(hello)
player.CharacterAdded:Connect(function()
	task.wait(1.5)
	hello()
end)

-- the game's own health events (cure / vitamin / illness / collapse wake-up): refresh our cards
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("GwangalliRemotes", 60)
	local ev = remotes and remotes:WaitForChild("HealthEvent", 60)
	if ev and ev:IsA("RemoteEvent") then
		local pending = false
		ev.OnClientEvent:Connect(function(p)
			if type(p) ~= "table" then
				return
			end
			if p.kind == "cured" or p.kind == "vitamin" or p.kind == "ill" or p.kind == "woke" or p.kind == "checkup" then
				if not pending then
					pending = true
					task.delay(1.2, function()
						pending = false
						hello()
					end)
				end
			end
		end)
	end
end)
