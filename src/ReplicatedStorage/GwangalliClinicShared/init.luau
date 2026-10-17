-- GwangalliClinicShared: the contract of GwangalliClinic (광안 메디컬 의원 "진료 보기": 번호표 → 접수 →
-- 대기·호출 → 진료실 → 처치 → 수납 → 약국, + 2층 건강검진 코스 · 입원실 휴식 / 퇴원 수속). Required by the
-- server Script ServerScriptService.GwangalliClinic and the LocalScript StarterPlayerScripts.GwangalliClinic.
-- Pure data + helpers: nothing is created at require time and nothing yields.
--
--   S.Config S.Medical S.Billing S.Sites       child modules
--   S.NAMES                                     instance / remote / attribute names
--   S.STEPS[step] = { label, stage, hint }      visit steps (server state machine), S.STAGES (tracker dots)
--   S.HS() -> GwangalliHealthShared?            the game's health curves / kinds (lazy, pcall)
--   S.kind(id) -> { id, name, icon, fee, desc, cure, med = Medical.KINDS[id] }?
--   S.clock() -> game hour (0..24)              S.isNight(clock?) (진료비 야간 가산 시간대)
--   S.now()                                     workspace:GetServerTimeNow()
--   S.won(n) S.ticket(n) S.mask(name) S.dur(sec) S.date(unix)
--   S.int / S.num / S.str / S.oneOf             remote input validation
--   S.encode(t) / S.decode(s)                   JSON (HttpService, pcall-guarded)
--   S.err(code, ...) -> Korean message          S.ERR
--
-- REMOTES (created by the server inside this module, folder "Remotes"):
--   ClinicRequest RemoteFunction (op, payload) -> { ok, code?, message?, ... }
--     hello · ticket · register · enter · exam · answer · plan · treat · pay · pharmacy · dose · cancel ·
--     checkup · chart · ward
--   ClinicEvent RemoteEvent server -> client { kind = "visit" | "call" | "line" | "toast" | "done" |
--     "report" | "meds" | "ward" | "fx" | "health", ... }
-- SHARED STATE (Configuration "State" in this module, attributes, replicated to everyone):
--   Active (bool) · Board (JSON call board) · Call (JSON last call, seq) · Rx (JSON pharmacy board) ·
--   Act_<staffId> ("act|userId|t") · Bed_<anchor> ("userId|what|t0|seconds" or "") · Lamp_<anchor> (t)
-- CHARACTER ATTRIBUTES we set: GwTreating (bool, the interior's "진료 중" lamp reads it; same meaning as
--   Health's), GwClinicPose ("lie" | "" while lying on an IV / ECG bed).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = {}
S.VERSION = 1

S.Config = require(script:WaitForChild("Config"))
S.Medical = require(script:WaitForChild("Medical"))
S.Billing = require(script:WaitForChild("Billing"))
S.Sites = require(script:WaitForChild("Sites"))

S.NAMES = {
	Remotes = "Remotes",
	Request = "ClinicRequest",
	Event = "ClinicEvent",
	State = "State",
	World = "GwangalliClinic", -- Workspace folder (server): Anchors, Staff
	Anchors = "Anchors",
	Staff = "Staff",
	Local = "GwClinicLocal", -- Workspace folder (client-only props)
	Gui = "GwangalliClinic", -- PlayerGui ScreenGui
	Screens = "GwangalliClinicScreens", -- PlayerGui folder of SurfaceGuis (world displays)
	Store = "GwangalliClinic_v1",
	AttrTreating = "GwTreating",
	AttrPose = "GwClinicPose",
	AttrKind = "ClinicKind", -- on anchors
	AttrLabel = "ClinicLabel",
	AttrStation = "ClinicStation",
	AttrStaff = "ClinicStaff", -- on staff rigs (id)
}

-------------------------------------------------------------------------------------------------
-- steps (server state machine). stage = 1 접수 · 2 진료 · 3 처치 · 4 수납 · 5 약국 · 6 완료
-------------------------------------------------------------------------------------------------
S.STAGES = { "접수", "진료", "처치", "수납", "약국" }
S.STEPS = {
	desk_wait = { label = "접수 대기", stage = 1, hint = "번호를 부를 때까지 대기실에서 기다려 주세요" },
	desk_called = { label = "창구로 오세요", stage = 1, hint = "호출된 창구로 가서 접수하세요" },
	desk = { label = "접수 중", stage = 1, hint = "창구에서 문진표를 작성해요" },
	consult_wait = { label = "진료 대기", stage = 2, hint = "진료실 앞에서 호출을 기다려요" },
	consult_called = { label = "진료실로 들어오세요", stage = 2, hint = "진료실 1 · 내과 의자에 앉으세요" },
	consult = { label = "진료 중", stage = 2, hint = "김선생님과 상담 중" },
	need_money = { label = "진료비 준비", stage = 3, hint = "진료비가 부족해요 · ATM에서 찾아 와서 창구에서 이어서" },
	treat_go = { label = "진찰대로", stage = 3, hint = "진찰대(침대)로 가세요" },
	treat = { label = "처치 중", stage = 3, hint = "주사 맞는 중" },
	iv_go = { label = "주사실로", stage = 3, hint = "주사실 침대로 가세요" },
	iv = { label = "수액 맞는 중", stage = 3, hint = "편하게 누워 계세요" },
	pay_go = { label = "수납하기", stage = 4, hint = "1층 접수 · 수납 창구로 가세요" },
	pharm_go = { label = "약국으로", stage = 5, hint = "원내 약국에 처방전을 내세요" },
	pharm_wait = { label = "조제 중", stage = 5, hint = "약을 조제하고 있어요" },
	pharm_ready = { label = "약 나왔어요", stage = 5, hint = "약국에서 약을 받으세요" },
	done = { label = "진료 완료", stage = 6, hint = "몸조리 잘 하세요" },
	chk_go = { label = "2층 검진센터로", stage = 1, hint = "2층 건강검진센터 접수대로 가세요", checkup = true },
	chk_course = { label = "건강검진 중", stage = 2, hint = "남은 검사를 받아요", checkup = true },
	chk_result = { label = "결과 상담", stage = 4, hint = "검진센터 접수대에서 결과를 들어요", checkup = true },
}

-------------------------------------------------------------------------------------------------
-- Health system (read-only data)
-------------------------------------------------------------------------------------------------
local HS: any = nil
local HStried = false
function S.HS(): any
	if HS or HStried then
		return HS
	end
	local m = ReplicatedStorage:FindFirstChild("GwangalliHealthShared")
	if not m then
		return nil
	end
	HStried = true
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		HS = res
	end
	return HS
end

-- G.HEALTH (or nil when the game's health system is missing)
function S.H(): any
	local hs = S.HS()
	if hs and type(hs.H) == "function" then
		local ok, h = pcall(hs.H)
		if ok and type(h) == "table" then
			return h
		end
	end
	return nil
end

function S.kind(id: any): any?
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local H = S.H()
	local k = H and H.KINDS and H.KINDS[id]
	local med = S.Medical.KINDS[id]
	if not k or not med then
		return nil
	end
	return { id = id, name = k.name, icon = k.icon, fee = k.fee, desc = k.desc or "", cure = k.cure or "", emote = k.emote, med = med }
end

-------------------------------------------------------------------------------------------------
-- time
-------------------------------------------------------------------------------------------------
local clockMod: any = nil
local clockTried = false
function S.clock(): number
	if not clockTried then
		clockTried = true
		local m = ReplicatedStorage:FindFirstChild("GwangalliShared")
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" and type(res.clockNow) == "function" then
				clockMod = res
			end
		end
	end
	if clockMod then
		local ok, c = pcall(clockMod.clockNow)
		if ok and type(c) == "number" and c == c then
			return c % 24
		end
	end
	return game:GetService("Lighting").ClockTime
end

function S.isNight(clock: number?): boolean
	local c = clock or S.clock()
	local F = S.Config.Fees
	return c >= F.NightFrom or c < F.NightTo
end

function S.now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok then t else os.time()
end

-------------------------------------------------------------------------------------------------
-- formatting
-------------------------------------------------------------------------------------------------
S.won = S.Billing.won
S.dur = S.Medical.dur

function S.ticket(n: number?): string
	return string.format("%03d", math.floor(tonumber(n) or 0) % 1000)
end

-- "홍길동" -> "홍*동", "Kim" -> "K*m", "AB" -> "A*"
function S.mask(name: string?): string
	local s = tostring(name or "")
	if s == "" then
		return "*"
	end
	local chars = {}
	for _, c in utf8.codes(s) do
		table.insert(chars, utf8.char(c))
		if #chars > 24 then
			break
		end
	end
	if #chars <= 1 then
		return chars[1] .. "*"
	elseif #chars == 2 then
		return chars[1] .. "*"
	end
	return chars[1] .. "*" .. chars[#chars]
end

function S.date(unix: number?): string
	local t = os.date("!*t", math.floor((tonumber(unix) or os.time()) + 9 * 3600)) -- KST
	return string.format("%04d.%02d.%02d", t.year, t.month, t.day)
end

function S.dateTime(unix: number?): string
	local t = os.date("!*t", math.floor((tonumber(unix) or os.time()) + 9 * 3600))
	return string.format("%04d.%02d.%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
end

function S.clockText(c: number?): string
	local v = (tonumber(c) or 12) % 24
	local h = math.floor(v)
	local m = math.floor((v - h) * 60)
	return string.format("%02d:%02d", h, m)
end

-------------------------------------------------------------------------------------------------
-- validation (remote input)
-------------------------------------------------------------------------------------------------
function S.int(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	local n = math.floor(v)
	if n < lo or n > hi then
		return nil
	end
	return n
end

function S.num(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return math.clamp(v, lo, hi)
end

function S.str(v: any, maxLen: number): string?
	if type(v) ~= "string" or #v == 0 or #v > maxLen then
		return nil
	end
	return v
end

function S.oneOf(v: any, list: { string }): string?
	if type(v) ~= "string" then
		return nil
	end
	for _, x in list do
		if x == v then
			return v
		end
	end
	return nil
end

function S.encode(t: any): string
	local ok, s = pcall(HttpService.JSONEncode, HttpService, t)
	return if ok then s else "{}"
end

function S.decode(s: any): any
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, s)
	return if ok then t else nil
end

-------------------------------------------------------------------------------------------------
-- Korean error messages
-------------------------------------------------------------------------------------------------
S.ERR = {
	bad = "잘못된 요청이에요",
	rate = "너무 빨라요. 잠시 후 다시 해 주세요",
	error = "잠시 후 다시 시도해 주세요",
	loading = "프로필을 불러오는 중이에요",
	off = "지금은 진료 접수를 받지 않아요",
	far = "%s 가까이에서 해 주세요",
	step = "지금 단계에서는 할 수 없어요",
	busy = "처리 중이에요… 잠시만요",
	hasVisit = "이미 접수된 진료가 있어요 (%s번)",
	noVisit = "접수된 진료가 없어요",
	riding = "차에서 내린 뒤 이용해 주세요",
	collapse = "응급 상황이라 진료를 이어갈 수 없어요",
	seatTaken = "자리에 다른 분이 계세요. 잠시만 기다려 주세요",
	bedTaken = "침대가 모두 사용 중이에요. 잠시 후 다시 와 주세요",
	money = "잔액이 부족해요 (필요 %s · 통장 %s · 현금 %s)",
	noMoney = "결제 시스템을 찾을 수 없어요",
	paid = "이미 결제된 영수증이에요",
	tooSoon = "선생님 말씀을 조금 더 들어 주세요",
	order = "순서대로 진찰해요",
	healthy = "지금은 치료할 병이 없어요 😊",
	noVitamin = "지금은 피로가 거의 없어서 영양주사가 필요 없어요",
	health = "병원 시스템과 연결이 안 돼요. 잠시 후 다시 해 주세요",
	noMeds = "지금 먹을 약이 없어요",
	notDue = "다음 복용까지 %s 남았어요",
	station = "이미 받은 검사예요",
	stationBusy = "다른 분이 검사 중이에요",
	stations = "아직 남은 검사가 있어요 (%d개)",
	checkupCool = "건강검진은 하루에 한 번만 받을 수 있어요",
	ward = "입원실 침대에서 해 주세요",
	wardCool = "조금 전에 쉬었어요. %s 뒤에 다시 쉴 수 있어요",
	shift = "근무 중에는 누워 쉴 수 없어요. 먼저 퇴근해 주세요",
	cooldown = "잠시 후 다시 눌러 주세요",
}

function S.err(code: string, ...: any): string
	local t = S.ERR[code] or S.ERR.error
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, t, ...)
		if ok then
			return s
		end
	end
	return (string.gsub(t, "%%s", ""))
end

return S
