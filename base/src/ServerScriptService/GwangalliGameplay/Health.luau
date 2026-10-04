-- GwangalliGameplay/Health (owner: health): 피로도 (fatigue) -> pay debuff -> 질병 (illness) -> 병원
-- (광안 메디컬 의원). Everything is decided here on the server; the client only renders
-- (StarterPlayerScripts/GwangalliHealth.client.luau). Numbers: G.HEALTH (GwangalliGameplayShared),
-- curves: ReplicatedStorage.GwangalliHealthShared, tuning guide: docs/HEALTH.md.
--
--   * fatigue = the stat `fatigue` in d.stats (G.STATS, lower is better). Rises while on shift
--     (own 1 s tick: +1 per 32 s by day / 22 s at night, plus Health.onWork per finished task from the
--     jobs module), falls off shift (-1 per 90 s), drops a lot on sleep (Life.sleep -> ctx.health.rest).
--   * pay multiplier Health.payMultiplier(player): 1.0 < 50, 0.7 at 50-74, 0.4 at 75-89, 0.2 at 90+
--     and while ill. The jobs module multiplies every task pay / bonus by it.
--   * illness risk accrues only while working with fatigue >= 80 (persisted in d.health.risk); past the
--     threshold the player falls ill (d.health.illness = {kind, since, online}): pay 0.2, WalkSpeed
--     x0.7 (character attribute GwIll for the sprint HUD), 행복 -1/min, a friend's text, and after
--     G.HEALTH.collapseAfter seconds online: 쓰러짐 + ambulance to a ward bed with a higher fee.
--   * clinic: ProximityPrompt anchors tagged HospitalPrompt ("진료 받기" on the doctor, "접수" at the
--     desk) open the hospital UI (HealthEvent "clinic"); HealthRequest ops treat / vitamin / checkup
--     charge the fee bank first (cash fallback), then run the treatment choreography on the exam bed
--     (Seat tagged HospitalBed/BedKind=exam): nurse arm raise (Motor6D C0 tween) + syringe prop,
--     2.5 s, cure. Healthy visitors: 영양주사 (fatigue -40) / 건강검진 (status report).
--   * ctx.health = this module (ctx.health.payMultiplier / onWork / rest / isIll / status / fatigue).
--   * Owner / test hook: ServerStorage.GwangalliHealthAPI (BindableFunction, server only):
--     Invoke(op, userId, ...) ops status | setFatigue | setRisk | makeIll | cure | collapse | treat.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Health = {}

local G: any
local Util: any
local Profiles: any
local ctx: any
local HS: any -- GwangalliHealthShared
local Anim: any = nil -- GwangalliAnim (optional: idle tracks on the static rigs)
local remotes: { request: RemoteFunction?, event: RemoteEvent? } = { request = nil, event = nil }

type Sess = {
	fatAcc: number, -- fractional fatigue not yet applied
	happyAcc: number,
	friendSent: boolean,
	collapsing: boolean,
	treating: boolean,
	lastStatusPush: number,
	wasOnShift: boolean,
}
local sessions: { [Player]: Sess } = {}

local function S(player: Player): Sess
	local s = sessions[player]
	if not s then
		s = { fatAcc = 0, happyAcc = 0, friendSent = false, collapsing = false, treating = false, lastStatusPush = 0, wasOnShift = false }
		sessions[player] = s
	end
	return s
end

local function H(): any
	return HS.H()
end

local function won(n: number): string
	return G.format.won(n)
end

local BASE_WALK = 16
do
	local cfg = ReplicatedStorage:FindFirstChild("GwangalliConfig")
	if cfg and cfg:IsA("ModuleScript") then
		local ok, res = pcall(require, cfg)
		if ok and type(res) == "table" and type(res.Sprint) == "table" and tonumber(res.Sprint.WalkSpeed) then
			BASE_WALK = tonumber(res.Sprint.WalkSpeed) :: number
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Profile access
-------------------------------------------------------------------------------------------------
local function data(player: Player): (any?, any?)
	local d = Profiles.get(player)
	if not d then
		return nil, nil
	end
	if type(d.health) ~= "table" then
		d.health = HS.sanitizeHealth(d.health)
	end
	return d, d.health
end

local function fatigueOf(d: any): number
	return HS.clampFatigue(d.stats and d.stats.fatigue or 0)
end

local function illKind(d: any): string?
	local h = d and d.health
	return h and h.illness and h.illness.kind or nil
end

local function pushAttributes(player: Player, d: any)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(G.Attr.Fatigue, math.floor(fatigueOf(d) + 0.5))
	player:SetAttribute(G.Attr.Illness, illKind(d) or "")
end

-- Humanoid speed / character attribute for the current illness state.
local function applyCharacter(player: Player)
	local d = Profiles.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not d or not character or not humanoid then
		return
	end
	local ill = illKind(d) ~= nil
	character:SetAttribute(G.Attr.Ill, ill)
	local illSpeed = math.floor(BASE_WALK * H().illWalkSpeed * 100 + 0.5) / 100
	if ill then
		-- only lower a normal walking speed (a seat / minigame speed stays as it is)
		if math.abs(humanoid.WalkSpeed - BASE_WALK) < 0.01 or humanoid.WalkSpeed > BASE_WALK then
			humanoid.WalkSpeed = illSpeed
		end
	elseif math.abs(humanoid.WalkSpeed - illSpeed) < 0.01 then
		humanoid.WalkSpeed = BASE_WALK
	end
end

local function fire(player: Player, payload: { [string]: any })
	local ev = remotes.event
	if ev and player.Parent == Players then
		ev:FireClient(player, payload)
	end
end

function Health.status(player: Player): any?
	local d = data(player)
	if not d then
		return nil
	end
	return HS.statusView(d, os.time())
end

local function pushStatus(player: Player)
	local st = Health.status(player)
	if st then
		fire(player, { kind = "status", status = st })
	end
end

-------------------------------------------------------------------------------------------------
-- Fatigue
-------------------------------------------------------------------------------------------------
-- Applies a fatigue delta (whole points are written to the profile through ctx.addStats; the rest
-- waits in the session accumulator so the profile / remote is touched about once per point).
local function addFatigue(player: Player, delta: number, flushAll: boolean?)
	local d = data(player)
	if not d then
		return
	end
	local s = S(player)
	s.fatAcc += delta
	local cur = fatigueOf(d)
	if (cur <= 0 and s.fatAcc < 0) or (cur >= 100 and s.fatAcc > 0) then
		s.fatAcc = 0 -- nothing to apply at the limits
		return
	end
	local whole = if s.fatAcc >= 0 then math.floor(s.fatAcc) else -math.floor(-s.fatAcc)
	if flushAll then
		whole = s.fatAcc
	end
	if whole ~= 0 then
		s.fatAcc -= whole
		ctx.addStats(player, { fatigue = whole }, nil, true)
		pushAttributes(player, d)
	end
end

function Health.fatigue(player: Player): number
	local d = Profiles.get(player)
	return d and fatigueOf(d) or 0
end

function Health.isIll(player: Player): string?
	local d = Profiles.get(player)
	return d and illKind(d) or nil
end

-- Why the pay is reduced right now ("🤧 감기 때문에 몸이 안 좋아요"), nil at full pay. The jobs module
-- appends it to its "+3,000원" toasts and the shift card (JS.describeMult).
function Health.payReason(player: Player): string?
	local d = Profiles.get(player)
	if not d then
		return nil
	end
	return HS.payReason(fatigueOf(d), illKind(d))
end

-- 1.0 / 0.7 / 0.4 / 0.2 (0.2 while ill), plus the reason as a second value. The jobs module
-- multiplies every task pay / tip / shift bonus by this.
function Health.payMultiplier(player: Player): (number, string?)
	local d = Profiles.get(player)
	if not d then
		return 1, nil
	end
	local kind = illKind(d)
	local f = fatigueOf(d)
	return HS.payMultiplier(f, kind ~= nil), HS.payReason(f, kind)
end

-- Fatigue relief (sleep, meals, 카페). Returns the fatigue after the change.
function Health.rest(player: Player, amount: number?, reason: string?): number
	local d = data(player)
	if not d then
		return 0
	end
	local amt = tonumber(amount) or H().fatigue.meal
	if amt > 0 then
		addFatigue(player, -amt, true)
	end
	local _ = reason
	return fatigueOf(d)
end

local fallIll -- forward

-- One work round finished. Two call shapes are accepted:
--   Health.onWork(player, seconds: number, jobId: string?)   -- Jobs.luau: a task took `seconds`
--   Health.onWork(player, kind: string?, info: any?)         -- "task" | "delivery" | "shiftStart" | "shiftEnd"
-- Shift TIME is already counted by the 1 s tick (ctx.onShift), so a finished task only adds the
-- per-task bonus (G.HEALTH.fatigue.taskBonus) and, in the danger zone, the per-task risk. Returns the
-- pay multiplier to apply to that round.
function Health.onWork(player: Player, kindOrSeconds: any?, _info: any?): number
	local d, h = data(player)
	if not d or not h then
		return 1
	end
	local env = ctx.env()
	local night = HS.isNightClock(env.clock)
	local mult = Health.payMultiplier(player)
	local kind = if type(kindOrSeconds) == "string" then kindOrSeconds else "task"
	if kind == "shiftEnd" or kind == "shiftStart" then
		return mult
	end
	if type(kindOrSeconds) == "number" and kindOrSeconds <= 0 then
		return mult -- nothing was worked (a cancelled / failed round)
	end
	addFatigue(player, HS.taskGain(night))
	local f = fatigueOf(d)
	if not h.illness and f >= H().risk.from then
		h.risk = math.min(100, (h.risk or 0) + H().risk.taskBonus)
		Profiles.markDirty(player)
		if h.risk >= H().risk.threshold then
			fallIll(player, d, h)
		end
	end
	return mult
end

-------------------------------------------------------------------------------------------------
-- Illness
-------------------------------------------------------------------------------------------------
fallIll = function(player: Player, d: any, h: any, forceKind: string?)
	if h.illness then
		return
	end
	local env = ctx.env()
	local kindId = forceKind or HS.pickKind(fatigueOf(d), env.clock, d.job and d.job.id or nil, d.lifeDay or 1)
	local kind = HS.kind(kindId)
	if not kind then
		kindId = "cold"
		kind = HS.kind(kindId)
	end
	h.illness = { kind = kindId, since = os.time(), online = 0 }
	h.risk = 0
	local s = S(player)
	s.friendSent = false
	s.happyAcc = 0
	Profiles.markDirty(player)
	pushAttributes(player, d)
	applyCharacter(player)
	ctx.changed(player, "stats")
	ctx.notify(player, "warn", string.format("%s %s에 걸렸어요", kind.icon, kind.name), string.format("%s 급여 -%d%% · 걸음도 느려져요. %s에서 치료받아요 🏥", kind.desc, math.floor((1 - H().illMult) * 100 + 0.5), H().name), { sound = "notify" })
	pcall(ctx.setWaypoint, player, H().place)
	fire(player, { kind = "ill", illness = kindId, name = kind.name, icon = kind.icon, status = Health.status(player) })
end

local function cure(player: Player, d: any, h: any, how: string)
	local had = h.illness
	h.illness = nil
	h.risk = 0
	if had then
		h.cured = (h.cured or 0) + 1
	end
	Profiles.markDirty(player)
	pushAttributes(player, d)
	applyCharacter(player)
	ctx.changed(player, "stats")
	local _ = how
end

-- 쓰러짐: the character falls (PlatformStand) for 3 s, fades out, wakes on a ward bed, pays the
-- ambulance fee (bank, then cash, the rest becomes hospital debt) and is cured.
local function collapse(player: Player)
	local d, h = data(player)
	local s = S(player)
	if not d or not h or not h.illness or s.collapsing or s.treating then
		return
	end
	s.collapsing = true
	local kindId = h.illness.kind
	local kind = HS.kind(kindId)
	player:SetAttribute(G.Attr.Collapse, true)
	local character, humanoid = Util.alive(player)
	if humanoid then
		pcall(function()
			humanoid.PlatformStand = true
		end)
	end
	if ctx.onShift(player) then
		pcall(ctx.endShift, player)
	end
	ctx.notify(player, "warn", "쓰러졌어요… 😵", H().messages.ambulance, { sound = "notify" })
	fire(player, { kind = "collapse", illness = kindId, name = kind and kind.name or "" })
	task.spawn(function()
		task.wait(3)
		if player.Parent ~= Players then
			s.collapsing = false
			return
		end
		Util.fade(player, true, 0.8, "🚑 구급차 이동 중…")
		local d2, h2 = data(player)
		if not d2 or not h2 then
			s.collapsing = false
			return
		end
		-- fee: bank first, then cash, the rest is debt
		local fee = HS.ambulanceFee(kindId) + (h2.debt or 0)
		local paid = 0
		if ctx.spend(player, fee, "광안메디컬 응급 진료 (구급차)", true, "bank") then
			paid = fee
		else
			-- not enough in either account alone: bank first, then cash, capped at the fee; the rest is debt
			local remaining = fee
			local takeBank = math.min(remaining, math.max(0, d2.bank or 0))
			if takeBank > 0 and ctx.ledger(player, "bank", -takeBank, "광안메디컬 응급 진료 (일부)", true) then
				remaining -= takeBank
			end
			local takeCash = math.min(remaining, math.max(0, d2.cash or 0))
			if takeCash > 0 and ctx.ledger(player, "cash", -takeCash, "광안메디컬 응급 진료 (일부)", true) then
				remaining -= takeCash
			end
			paid = fee - remaining
		end
		h2.debt = math.max(0, fee - paid)
		h2.collapses = (h2.collapses or 0) + 1
		h2.visits = (h2.visits or 0) + 1
		cure(player, d2, h2, "ambulance")
		addFatigue(player, -H().fatigue.collapse, true)
		ctx.addStats(player, { happiness = -8 }, nil, true)
		-- wake up on a ward bed
		local bed = Health.findBed("ward", nil)
		local _, humanoid2 = Util.alive(player)
		if humanoid2 then
			pcall(function()
				humanoid2.PlatformStand = false
			end)
		end
		if bed then
			ctx.allowTeleport(player, 10)
			pcall(ctx.jobsResetPosition, player)
			local ok = pcall(Util.teleportTo, player, bed, 6)
			local _, humanoid3 = Util.alive(player)
			if ok and humanoid3 then
				pcall(function()
					(bed :: any):Sit(humanoid3)
				end)
			end
		end
		task.wait(0.6)
		Util.fade(player, false, 0.8)
		player:SetAttribute(G.Attr.Collapse, false)
		s.collapsing = false
		local body = string.format("응급 진료비 %s%s · %s 완치 · 피로도 -%d", won(paid), if h2.debt > 0 then string.format(" (미납 %s)", won(h2.debt)) else "", kind and kind.name or "질병", H().fatigue.collapse)
		ctx.notify(player, "home", "광안메디컬 입원실에서 눈을 떴어요 🏥", body, { sound = "complete" })
		fire(player, { kind = "woke", fee = paid, debt = h2.debt, status = Health.status(player) })
		pushStatus(player)
	end)
end

-------------------------------------------------------------------------------------------------
-- Clinic world objects (tags built by venues/hospital.luau)
-------------------------------------------------------------------------------------------------
local anchors: { [Instance]: boolean } = {}
local staff: { doctor: Model?, nurse: Model? } = { doctor = nil, nurse = nil }
local nurseRest: { shoulder: CFrame?, elbow: CFrame? } = { shoulder = nil, elbow = nil }

local function anchorPart(inst: Instance): BasePart?
	return Util.partOf(inst)
end

function Health.findBed(kindWanted: string, near: Vector3?): BasePart?
	local best: BasePart? = nil
	local bestD = math.huge
	for _, inst in CollectionService:GetTagged(G.Tags.HospitalBed) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local bk = inst:GetAttribute("BedKind")
			if bk == kindWanted or (kindWanted == "any") then
				local occupied = inst:IsA("Seat") and (inst :: Seat).Occupant ~= nil
				local dist = if near then (inst.Position - near).Magnitude else 0
				if occupied then
					dist += 1000
				end
				if dist < bestD then
					bestD = dist
					best = inst
				end
			end
		end
	end
	return best
end

local function nearClinic(player: Player, radius: number): boolean
	local pos = Util.rootPosition(player)
	if not pos then
		return false
	end
	for inst in anchors do
		local p = anchorPart(inst)
		if p and p:IsDescendantOf(workspace) and (p.Position - pos).Magnitude <= radius then
			return true
		end
	end
	local dest = ctx.dest(H().place)
	if dest and (dest.Position - pos).Magnitude <= radius + 20 then
		return true
	end
	return false
end

local function openClinic(player: Player, inst: Instance)
	local d = data(player)
	if not d then
		ctx.notify(player, "info", "잠시만요", "프로필을 불러오는 중이에요")
		return
	end
	if not Util.cooldown(player, "clinicOpen", 0.8) then
		return
	end
	local p = anchorPart(inst)
	local pos = Util.rootPosition(player)
	if not p or not pos or (p.Position - pos).Magnitude > H().reach + 6 then
		return
	end
	if S(player).treating then
		return
	end
	fire(player, { kind = "clinic", anchor = inst:GetAttribute("Kind") or "doctor", status = Health.status(player), hospital = H().name })
end

local function registerAnchor(inst: Instance)
	if anchors[inst] or not inst:IsDescendantOf(workspace) then
		return
	end
	local part = anchorPart(inst)
	if not part then
		return
	end
	anchors[inst] = true
	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or inst:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HospitalPrompt"
		prompt.ActionText = if inst:GetAttribute("Kind") == "desk" then "접수하기" else "진료 받기"
		prompt.ObjectText = if inst:GetAttribute("Kind") == "desk" then "접수 데스크" else "의사 선생님"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = part
	end
	local pp = prompt :: ProximityPrompt
	pp.Triggered:Connect(function(player: Player)
		local ok, err = pcall(openClinic, player, inst)
		if not ok then
			warn("[GwangalliGameplay] hospital prompt failed: " .. tostring(err))
		end
	end)
end

local function unregisterAnchor(inst: Instance)
	anchors[inst] = nil
end

local function motorOf(model: Model, name: string): Motor6D?
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == name then
			return d
		end
	end
	return nil
end

-- Mirrors GwangalliAnim's pose composition: C0 = rest position * offset * rotation * rest rotation.
local function poseJoint(model: Model, joint: string, p: number, y: number, r: number, dy: number?)
	local m = motorOf(model, joint)
	if not m then
		return
	end
	local rest = m:GetAttribute("GwRestC0")
	if typeof(rest) ~= "CFrame" then
		rest = m.C0
		m:SetAttribute("GwRestC0", rest)
	end
	local c0 = rest :: CFrame
	local pos = CFrame.new(c0.Position)
	local rot = c0 - c0.Position
	m.C0 = pos * CFrame.new(0, dy or 0, 0) * CFrame.Angles(math.rad(p), math.rad(y), math.rad(r)) * rot
end

local function setupStaff(model: Instance)
	if not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	local role = model:GetAttribute("Role")
	if role == "doctor" then
		staff.doctor = model
		-- seated at the desk (GwangalliAnim "sit" pose values), written once
		poseJoint(model, "RightHip", 90, 0, 0)
		poseJoint(model, "LeftHip", 90, 0, 0)
		poseJoint(model, "RightKnee", -88, 0, 0)
		poseJoint(model, "LeftKnee", -88, 0, 0)
		poseJoint(model, "RightShoulder", 30, 0, -12)
		poseJoint(model, "RightElbow", 70, 0, 0)
		poseJoint(model, "LeftShoulder", 30, 0, 12)
		poseJoint(model, "LeftElbow", 70, 0, 0)
		poseJoint(model, "Neck", -8, 0, 0)
	elseif role == "nurse" then
		staff.nurse = model
		local sh = motorOf(model, "RightShoulder")
		local el = motorOf(model, "RightElbow")
		nurseRest.shoulder = sh and sh.C0 or nil
		nurseRest.elbow = el and el.C0 or nil
		poseJoint(model, "LeftShoulder", 30, -90, 0)
		poseJoint(model, "LeftElbow", 70, 0, 0)
	end
	if Anim then
		task.spawn(function()
			pcall(Anim.play, model, "idle", { looped = true, fade = 0.3, offset = true })
		end)
	end
end

local function syringe(visible: boolean)
	local nurse = staff.nurse
	if not nurse then
		return
	end
	for _, d in nurse:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("GwProp") == "syringe" then
			d.Transparency = if visible then 0 else 1
		end
	end
end

local function nurseArm(raise: boolean)
	local nurse = staff.nurse
	if not nurse then
		return
	end
	local sh = motorOf(nurse, "RightShoulder")
	local el = motorOf(nurse, "RightElbow")
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if sh and nurseRest.shoulder then
		local rest = nurseRest.shoulder :: CFrame
		local pos, rot = CFrame.new(rest.Position), rest - rest.Position
		local goal = if raise then pos * CFrame.Angles(math.rad(62), 0, math.rad(-18)) * rot else rest
		pcall(function()
			TweenService:Create(sh, info, { C0 = goal }):Play()
		end)
	end
	if el and nurseRest.elbow then
		local rest = nurseRest.elbow :: CFrame
		local pos, rot = CFrame.new(rest.Position), rest - rest.Position
		local goal = if raise then pos * CFrame.Angles(math.rad(40), 0, 0) * rot else rest
		pcall(function()
			TweenService:Create(el, info, { C0 = goal }):Play()
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- Treatment choreography (server-driven; the client adds sparkles + toast on "cured" / "vitamin")
-------------------------------------------------------------------------------------------------
local function seatOnExamBed(player: Player): BasePart?
	local pos = Util.rootPosition(player)
	local bed = Health.findBed("exam", pos)
	local character, humanoid, root = Util.alive(player)
	if not bed or not character or not humanoid or not root then
		return nil
	end
	ctx.allowTeleport(player, 8)
	pcall(ctx.jobsResetPosition, player)
	-- stand beside the bed, then sit (Seat:Sit welds the humanoid)
	local side = bed.CFrame * CFrame.new(0, 2.6, 0)
	Util.placeCharacter(player, CFrame.new(side.Position) * (bed.CFrame - bed.CFrame.Position))
	pcall(function()
		(bed :: any):Sit(humanoid)
	end)
	return bed
end

local function unseat(player: Player)
	local _, humanoid = Util.alive(player)
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
		local weld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

-- what = "treat" | "vitamin"
local function choreography(player: Player, what: string, fee: number)
	local s = S(player)
	s.treating = true
	local character = player.Character
	if character then
		character:SetAttribute(G.Attr.Treating, true)
	end
	task.spawn(function()
		local bed = seatOnExamBed(player)
		task.wait(0.4)
		if player.Parent ~= Players then
			s.treating = false
			return
		end
		nurseArm(true)
		task.wait(0.5)
		syringe(true)
		fire(player, { kind = "treating", what = what, seconds = 2.5 })
		task.wait(2.5)
		local d, h = data(player)
		if player.Parent == Players and d and h then
			if what == "treat" then
				local kind = HS.kind(h.illness and h.illness.kind) or { name = "질병", icon = "🩹" }
				cure(player, d, h, "clinic")
				addFatigue(player, -H().fatigue.cured, true)
				ctx.addStats(player, { happiness = 5 }, nil, true)
				ctx.notify(player, "success", string.format("완치! %s", kind.icon), string.format("%s 치료 완료 · 피로도 -%d · 행복 +5 (진료비 %s)", kind.name, H().fatigue.cured, won(fee)), { sound = "complete" })
				fire(player, { kind = "cured", illness = kind.name, fee = fee, status = Health.status(player) })
			else
				addFatigue(player, -H().fatigue.vitamin, true)
				ctx.addStats(player, { happiness = 2, stamina = 10 }, nil, true)
				ctx.notify(player, "success", "영양주사 완료 💉", string.format("피로도 -%d · 체력 +10 · 행복 +2 (%s)", H().fatigue.vitamin, won(fee)), { sound = "complete" })
				fire(player, { kind = "vitamin", fee = fee, status = Health.status(player) })
			end
		end
		syringe(false)
		nurseArm(false)
		task.wait(0.9)
		if player.Parent == Players then
			unseat(player)
			local ch = player.Character
			if ch then
				ch:SetAttribute(G.Attr.Treating, false)
			end
			pushStatus(player)
		end
		local _ = bed
		s.treating = false
	end)
end

-- Charges `fee` bank first, cash second. Returns ok, message.
local function charge(player: Player, fee: number, label: string): (boolean, string?)
	if fee <= 0 then
		return true, nil
	end
	if ctx.spend(player, fee, label, true, "bank") then
		return true, nil
	end
	local d = Profiles.get(player)
	return false, string.format("잔액이 부족해요 (진료비 %s · 통장 %s · 현금 %s)", won(fee), won(d and d.bank or 0), won(d and d.cash or 0))
end

local function handle(player: Player, op: any, payload: any): any
	if type(op) ~= "string" then
		return { ok = false, code = "bad", message = "잘못된 요청이에요" }
	end
	if not Util.bucket(player, 4, 8) then
		return { ok = false, code = "busy", message = "잠시 후 다시 시도해 주세요" }
	end
	local d, h = data(player)
	if not d or not h then
		return { ok = false, code = "loading", message = "프로필을 불러오는 중이에요" }
	end
	local s = S(player)
	if op == "status" then
		return { ok = true, status = Health.status(player) }
	end
	if s.treating or s.collapsing then
		return { ok = false, code = "treating", message = "치료 중이에요" }
	end
	if not nearClinic(player, H().reach + 26) then
		return { ok = false, code = "far", message = string.format("%s 안에서만 가능해요", H().name) }
	end
	if ctx.isRiding(player) then
		return { ok = false, code = "riding", message = "택시에서 내린 뒤 이용해 주세요" }
	end
	if not Util.cooldown(player, "clinicOp", 1.5) then
		return { ok = false, code = "busy", message = "잠시만요…" }
	end
	local _ = payload
	if op == "treat" then
		local kind = HS.kind(h.illness and h.illness.kind)
		if not kind then
			return { ok = false, code = "healthy", message = "건강하신데요? 치료할 병이 없어요 😊" }
		end
		local fee = kind.fee + (h.debt or 0)
		local ok, msg = charge(player, fee, string.format("광안메디컬 진료 · %s%s", kind.name, if (h.debt or 0) > 0 then " + 미납금" else ""))
		if not ok then
			return { ok = false, code = "insufficient", message = msg }
		end
		h.debt = 0
		h.visits = (h.visits or 0) + 1
		Profiles.markDirty(player)
		choreography(player, "treat", fee)
		return { ok = true, code = "treating", fee = fee, seconds = 4, name = kind.name }
	elseif op == "vitamin" then
		local svc = H().services.vitamin
		if fatigueOf(d) < 5 then
			return { ok = false, code = "notNeeded", message = "지금은 피로가 거의 없어요. 다음에 맞아요 😊" }
		end
		local fee = svc.fee + (h.debt or 0)
		local ok, msg = charge(player, fee, "광안메디컬 영양주사" .. (if (h.debt or 0) > 0 then " + 미납금" else ""))
		if not ok then
			return { ok = false, code = "insufficient", message = msg }
		end
		h.debt = 0
		h.visits = (h.visits or 0) + 1
		h.lastVitamin = os.time()
		Profiles.markDirty(player)
		choreography(player, "vitamin", fee)
		return { ok = true, code = "treating", fee = fee, seconds = 4, name = svc.name }
	elseif op == "checkup" then
		local svc = H().services.checkup
		local fee = svc.fee + (h.debt or 0)
		local ok, msg = charge(player, fee, "광안메디컬 건강검진" .. (if (h.debt or 0) > 0 then " + 미납금" else ""))
		if not ok then
			return { ok = false, code = "insufficient", message = msg }
		end
		h.debt = 0
		h.visits = (h.visits or 0) + 1
		h.lastCheckup = os.time()
		Profiles.markDirty(player)
		local st = Health.status(player)
		ctx.notify(player, "stat", "건강검진 완료 🩺", HS.adviceFor(st), { sound = "complete" })
		fire(player, { kind = "checkup", status = st, advice = HS.adviceFor(st), fee = fee })
		return { ok = true, code = "checkup", status = st, advice = HS.adviceFor(st), fee = fee }
	end
	return { ok = false, code = "bad", message = "알 수 없는 요청이에요" }
end

-------------------------------------------------------------------------------------------------
-- Tick (1 s, one loop for every player)
-------------------------------------------------------------------------------------------------
local function tickPlayer(player: Player, s: Sess)
	local d, h = data(player)
	if not d or not h then
		return
	end
	local env = ctx.env()
	local night = HS.isNightClock(env.clock)
	local onShift = ctx.onShift(player) == true
	local f = fatigueOf(d)
	local Hh = H()
	if onShift and not s.treating and not s.collapsing then
		addFatigue(player, HS.workGain(1, night))
		if not h.illness and f >= Hh.risk.from then
			h.risk = math.min(100, (h.risk or 0) + HS.riskGain(f, 1))
			if h.risk >= Hh.risk.threshold then
				fallIll(player, d, h)
			end
		end
	else
		if f > 0 then
			addFatigue(player, -HS.restLoss(1))
		end
		if (h.risk or 0) > 0 and f < Hh.risk.from then
			h.risk = math.max(0, h.risk - HS.riskDecay(1))
		end
	end
	if onShift ~= s.wasOnShift then
		s.wasOnShift = onShift
		Profiles.markDirty(player)
	end
	if h.illness then
		h.illness.online = (h.illness.online or 0) + 1
		s.happyAcc += 1
		if s.happyAcc >= Hh.illHappinessEvery then
			s.happyAcc = 0
			ctx.addStats(player, { happiness = -1 }, nil, true)
		end
		if not s.friendSent and h.illness.online >= Hh.friendMessageAfter then
			s.friendSent = true
			pcall(ctx.sendMessage, player, "minji", Hh.messages.friend)
		end
		if h.illness.online >= Hh.collapseAfter and not s.collapsing and not s.treating then
			collapse(player)
		end
		-- the hospital UI keeps its "ill for N minutes" line fresh
		if os.clock() - s.lastStatusPush > 30 then
			s.lastStatusPush = os.clock()
			pushStatus(player)
		end
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		local s = sessions[player]
		if s then
			local ok, err = pcall(tickPlayer, player, s)
			if not ok then
				warn("[GwangalliGameplay] health tick failed: " .. tostring(err))
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Owner / test API (server only)
-------------------------------------------------------------------------------------------------
local function playerById(userId: any): Player?
	if typeof(userId) == "Instance" then
		return userId :: any
	end
	for _, p in Players:GetPlayers() do
		if p.UserId == userId or p.Name == userId then
			return p
		end
	end
	return Players:GetPlayers()[1]
end

local function api(op: string, userId: any, a: any, b: any): any
	local player = playerById(userId)
	if not player then
		return { ok = false, message = "no player" }
	end
	local d, h = data(player)
	if not d or not h then
		return { ok = false, message = "no profile" }
	end
	if op == "status" then
		return { ok = true, status = Health.status(player), mult = Health.payMultiplier(player) }
	elseif op == "setFatigue" then
		local target = HS.clampFatigue(a)
		S(player).fatAcc = 0
		ctx.addStats(player, { fatigue = target - fatigueOf(d) }, nil, true)
		pushAttributes(player, d)
		pushStatus(player)
		return { ok = true, fatigue = fatigueOf(d), mult = Health.payMultiplier(player) }
	elseif op == "setRisk" then
		h.risk = math.clamp(tonumber(a) or 0, 0, 100)
		return { ok = true, risk = h.risk }
	elseif op == "makeIll" then
		fallIll(player, d, h, if type(a) == "string" then a else nil)
		return { ok = true, illness = illKind(d) }
	elseif op == "cure" then
		cure(player, d, h, "api")
		pushStatus(player)
		return { ok = true }
	elseif op == "collapse" then
		if not h.illness then
			fallIll(player, d, h, if type(a) == "string" then a else nil)
		end
		collapse(player)
		return { ok = true }
	elseif op == "treat" or op == "vitamin" or op == "checkup" then
		return handle(player, op, { force = true })
	elseif op == "onWork" then
		return { ok = true, mult = Health.onWork(player, a, b) }
	end
	return { ok = false, message = "unknown op " .. tostring(op) }
end

-------------------------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------------------------
function Health.onLoaded(player: Player)
	local d, h = data(player)
	if not d or not h then
		return
	end
	S(player)
	pushAttributes(player, d)
	applyCharacter(player)
	task.delay(1, function()
		if player.Parent == Players then
			pushStatus(player)
		end
	end)
end

function Health.onCharacter(player: Player, character: Model)
	local s = S(player)
	s.treating = false
	s.collapsing = false
	player:SetAttribute(G.Attr.Collapse, false)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and player.Character == character and Profiles.get(player) then
			applyCharacter(player)
		end
	end)
end

function Health.onLeave(player: Player)
	-- flush the fractional fatigue into the profile before it is saved
	local s = sessions[player]
	if s and math.abs(s.fatAcc) >= 0.5 then
		pcall(addFatigue, player, 0, true)
	end
	sessions[player] = nil
end

function Health.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	do
		local m = ReplicatedStorage:WaitForChild("GwangalliHealthShared", 10)
		assert(m and m:IsA("ModuleScript"), "GwangalliHealthShared missing")
		HS = require(m :: ModuleScript)
	end
	do
		local m = ReplicatedStorage:FindFirstChild("GwangalliAnim")
		if m and m:IsA("ModuleScript") then
			local ok, res = pcall(require, m)
			if ok and type(res) == "table" then
				Anim = res
			end
		end
	end
	ctx.health = Health

	-- remotes
	local folder = ReplicatedStorage:FindFirstChild(G.RemotesFolder) or ReplicatedStorage:WaitForChild(G.RemotesFolder, 10)
	if folder then
		local function remote(name: string, className: string): any
			local r = folder:FindFirstChild(name)
			if r and r.ClassName ~= className then
				r:Destroy()
				r = nil
			end
			if not r then
				r = Instance.new(className)
				r.Name = name
				r.Parent = folder
			end
			return r
		end
		remotes.request = remote(G.Remote.HealthRequest, "RemoteFunction")
		remotes.event = remote(G.Remote.HealthEvent, "RemoteEvent")
		local rf = remotes.request :: RemoteFunction
		rf.OnServerInvoke = function(player: Player, op: any, payload: any)
			if payload ~= nil and type(payload) ~= "table" then
				return { ok = false, code = "bad", message = "잘못된 요청이에요" }
			end
			local ok, res = pcall(handle, player, op, payload)
			if not ok then
				warn("[GwangalliGameplay] health request failed: " .. tostring(res))
				return { ok = false, code = "error", message = "잠시 후 다시 시도해 주세요" }
			end
			return res
		end
	end

	-- world objects
	for _, inst in CollectionService:GetTagged(G.Tags.HospitalPrompt) do
		pcall(registerAnchor, inst)
	end
	CollectionService:GetInstanceAddedSignal(G.Tags.HospitalPrompt):Connect(function(inst)
		pcall(registerAnchor, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(G.Tags.HospitalPrompt):Connect(unregisterAnchor)
	for _, inst in CollectionService:GetTagged(G.Tags.HospitalStaff) do
		pcall(setupStaff, inst)
	end
	CollectionService:GetInstanceAddedSignal(G.Tags.HospitalStaff):Connect(function(inst)
		pcall(setupStaff, inst)
	end)

	-- owner / test hook
	local bf = ServerStorage:FindFirstChild("GwangalliHealthAPI")
	if not bf or not bf:IsA("BindableFunction") then
		bf = Instance.new("BindableFunction")
		bf.Name = "GwangalliHealthAPI"
		bf.Parent = ServerStorage
	end
	local bfn = bf :: BindableFunction
	bfn.OnInvoke = function(op: any, userId: any, a: any, b: any)
		local ok, res = pcall(api, tostring(op), userId, a, b)
		if not ok then
			return { ok = false, message = tostring(res) }
		end
		return res
	end

	for _, player in Players:GetPlayers() do
		if Profiles.get(player) then
			Health.onLoaded(player)
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliGameplay] health loop failed: " .. tostring(err))
			end
		end
	end)
end

return Health
