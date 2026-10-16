-- GwangalliClinic (server): 광안 메디컬 의원 "진료 보기" — a full Korean 의원 visit built ON the game's
-- 피로도 → 질병 → 병원 system (GwangalliGameplay/Health): 번호표 → 접수 → 대기·호출 → 진료실 (의사 상담 ·
-- 진찰 · 진단) → 처치 (Health's own treat / vitamin op: fee, nurse choreography, cure, fatigue) → 주사실 수액
-- → 수납 (영수증) → 원내 약국 (복약 지도 · 3회 복약) + 2층 건강검진 코스 (Health checkup op) + 입원실.
-- Drop-in add-on: this Script + ReplicatedStorage.GwangalliClinicShared + StarterPlayerScripts.GwangalliClinic.
-- No existing script needs editing. The legacy HospitalPrompt prompts are switched off at runtime
-- (Config.TakeOverLegacy) only after everything below booted; any failure before that leaves the old
-- hospital sheet working.
--
-- Boot: shared contract -> Health system ready (<= 90 s) -> store -> site (anchors, staff) -> remotes ->
-- patient / queue / visit / checkup / ward -> legacy takeover -> State.Active = true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliClinicShared", 60)
if not (sharedModule and sharedModule:IsA("ModuleScript")) then
	warn("[GwangalliClinic] ReplicatedStorage.GwangalliClinicShared is missing; the add-on is off")
	return
end
local okS, S = pcall(require, sharedModule)
if not okS or type(S) ~= "table" then
	warn("[GwangalliClinic] shared module failed:", S)
	return
end
local C = S.Config
if not C.Enabled then
	return
end

local K: any = { S = S, sharedModule = sharedModule }
K.Bridge = require(script:WaitForChild("Bridge"))
K.Store = require(script:WaitForChild("Store"))
K.Site = require(script:WaitForChild("Site"))
K.Net = require(script:WaitForChild("Net"))
K.Patient = require(script:WaitForChild("Patient"))
K.Queue = require(script:WaitForChild("Queue"))
K.Visit = require(script:WaitForChild("Visit"))
K.Checkup = require(script:WaitForChild("Checkup"))
K.Ward = require(script:WaitForChild("Ward"))

local function boot(): (boolean, string?)
	K.Bridge.init(K)
	local ok, why = K.Bridge.waitReady(90)
	if not ok then
		return false, why
	end
	-- shared state (replicated to every client)
	local old = sharedModule:FindFirstChild(S.NAMES.State)
	if old then
		old:Destroy()
	end
	local state = Instance.new("Configuration")
	state.Name = S.NAMES.State
	state:SetAttribute("Active", false)
	state.Parent = sharedModule
	K.state = state

	K.Store.init(K)
	K.Site.init(K)
	K.Site.build()
	K.Net.create(K)
	K.Patient.init(K)
	K.Queue.init(K)
	K.Visit.init(K)
	K.Checkup.init(K)
	K.Ward.init(K)

	K.Patient.start()
	K.Queue.start()
	K.Visit.start()
	K.Checkup.start()
	K.Ward.start()
	return true, nil
end

local ok, res, why = pcall(boot)
if not ok or res ~= true then
	warn("[GwangalliClinic] boot failed, the legacy hospital stays as it is:", if ok then why else res)
	if K.state then
		K.state:SetAttribute("Active", false)
	end
	return
end

-- everything is up: switch the legacy prompts off and tell the clients
local okT, errT = pcall(K.Bridge.takeOverLegacy, K.Site.venue)
if not okT then
	warn("[GwangalliClinic] legacy takeover failed:", errT)
end
K.state:SetAttribute("Active", true)
K.state:SetAttribute("Legacy", not C.TakeOverLegacy)
if C.Debug then
	print("[GwangalliClinic] ready ·", #Players:GetPlayers(), "players")
end
