-- GwangalliGameplay/VenuePC (owner: venues_detail): 광안 PC방 seats, server side.
--   * PCStation models (PC_NN): the Keyboard prompt "PC 켜기" charges V.PC.feePerHour (one in-game
--     hour up front, then every in-game hour while seated), seats the player (the build's optimise
--     pass disables touch-sitting, so the seat is enabled only for Seat:Sit and disabled again when
--     the player stands up) and starts the client session (camera on the monitor, the racer game)
--   * racer scores: per-server top 10 (best per player), board "PC 레이서 랭킹", plausibility clamp
--     (score <= seconds x V.PC.maxScoreRate)
--   * VenueLife.pcOf(player) -> the PC model (food orders go to that desk)

local Players = game:GetService("Players")

local PC = {}

local L: any
local ctx: any
local G: any
local Util: any
local V: any
local hour = 60

type Session = { player: Player, model: Model, seat: Seat, humanoid: Humanoid, paidUntil: number, started: number, confirmed: boolean }
local sessions: { [Player]: Session } = {}
local byModel: { [Model]: Session } = {}
local recent: { [Player]: { started: number, ended: number } } = {}
local stations: { [Model]: { seat: Seat, prompt: ProximityPrompt, no: number } } = {}
local top: { any } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function boardRows()
	L.setBoard("pc", L.rowsOf(top, function(e, i)
		return string.format("%d. %s  %s점", i, e.name, V.commas(e.score))
	end))
end

local function endSession(s: Session, reason: string?)
	if sessions[s.player] ~= s then
		return
	end
	sessions[s.player] = nil
	byModel[s.model] = nil
	recent[s.player] = { started = s.started, ended = os.clock() }
	local st = stations[s.model]
	if st then
		st.prompt.Enabled = true
	end
	s.model:SetAttribute(V.Attr.PCUser, 0)
	if s.humanoid.Parent and s.seat.Occupant == s.humanoid then
		s.humanoid.Sit = false
	end
	task.delay(0.3, function()
		if not byModel[s.model] and s.seat.Parent then
			s.seat.Disabled = true
		end
	end)
	if s.player.Parent == Players then
		if s.player:GetAttribute(V.Attr.Act) == "pc" then
			L.clearAct(s.player)
		end
		L.fire(s.player, { kind = "pcEnd", reason = reason or "" })
	end
end

local function start(player: Player, model: Model)
	local st = stations[model]
	if not st then
		return
	end
	local other = byModel[model]
	if other and other.player ~= player and other.player.Parent == Players then
		ctx.notify(player, "info", string.format("PC %02d", st.no), "다른 손님이 사용 중인 자리예요")
		return
	end
	local mine = sessions[player]
	if mine then
		if mine.model == model then
			return
		end
		endSession(mine, "move")
	end
	local character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return
	end
	if ctx.isRiding(player) or ctx.venueBusy(player) then
		return
	end
	if (root.Position - st.seat.Position).Magnitude > 14 then
		return
	end
	local fee = V.PC.feePerHour
	if not L.pay(player, fee, string.format("광안 PC방 %02d번 (1시간)", st.no)) then
		return
	end
	local s: Session = { player = player, model = model, seat = st.seat, humanoid = humanoid, paidUntil = now() + hour, started = os.clock(), confirmed = false }
	sessions[player] = s
	byModel[model] = s
	model:SetAttribute(V.Attr.PCUser, player.UserId)
	st.prompt.Enabled = false
	st.seat.Disabled = false
	if humanoid.SeatPart then
		humanoid.Sit = false
	end
	pcall(function()
		st.seat:Sit(humanoid)
	end)
	L.setAct(player, "pc", nil, nil)
	L.fire(player, { kind = "pcStart", pc = model, no = st.no, paidUntil = s.paidUntil, fee = fee })
	-- the sit must take (a blocked seat / a jump at the same moment): otherwise refund
	task.delay(1.5, function()
		if sessions[player] ~= s then
			return
		end
		if s.seat.Occupant == s.humanoid then
			s.confirmed = true
		else
			endSession(s, "sit")
			ctx.ledger(player, "cash", fee, "광안 PC방 환불 (착석 실패)", true)
		end
	end)
end

local function setup(inst: Instance)
	if not inst:IsA("Model") or stations[inst] then
		return
	end
	local no = inst:GetAttribute("PCNo")
	local seat = inst:FindFirstChild("Seat")
	if type(no) ~= "number" or not seat or not seat:IsA("Seat") then
		return
	end
	local host = inst:FindFirstChild("Keyboard", true) or inst:FindFirstChild("MonitorScreen", true)
	if not host or not host:IsA("BasePart") then
		return
	end
	host.CanQuery = true
	local pr = L.prompt(host, "PC 켜기", string.format("PC %02d · 1시간 %s", no, V.won(V.PC.feePerHour)), 0.3, 7, Enum.KeyCode.E)
	pr.Name = "GwangalliPCPrompt"
	stations[inst] = { seat = seat, prompt = pr, no = no }
	inst:SetAttribute(V.Attr.PCUser, 0)
	pr.Triggered:Connect(function(player: Player)
		if not Util.cooldown(player, "pcPrompt", 1) then
			return
		end
		start(player, inst)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local s = byModel[inst]
		if s and s.confirmed and seat.Occupant ~= s.humanoid then
			endSession(s, "stood")
		end
	end)
end

function PC.init(life: any)
	L = life
	ctx = life.ctx
	G = ctx.G
	Util = ctx.Util
	V = life.V
	local dl = 24
	pcall(function()
		local cfg = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliConfig", 5) :: any)
		if type(cfg) == "table" and type(cfg.DayLengthMinutes) == "number" then
			dl = cfg.DayLengthMinutes
		end
	end)
	hour = math.max(20, V.gameMinutes(V.PC.hourMinutes, dl))

	life.pcOf = function(player: Player): Model?
		local s = sessions[player]
		return s and s.model or nil
	end

	L.handle("pcLeave", function(player)
		local s = sessions[player]
		if s then
			endSession(s, "leave")
		end
		return { ok = true }
	end)
	L.handle("pcScore", function(player, p)
		if type(p) ~= "table" then
			return { ok = false }
		end
		local s = sessions[player]
		local started = if s then s.started else (recent[player] and os.clock() - recent[player].ended < 20 and recent[player].started or nil)
		if not started then
			return { ok = false, code = "session", message = "PC에 앉아서 플레이해 주세요" }
		end
		local seconds = tonumber(p.seconds)
		local score = tonumber(p.score)
		if not seconds or not score or seconds ~= seconds or score ~= score then
			return { ok = false, code = "bad" }
		end
		seconds = math.clamp(seconds, 0, os.clock() - started + 2)
		if seconds < V.PC.minSeconds then
			return { ok = false, code = "short" }
		end
		score = math.clamp(math.floor(score), 0, math.floor(seconds * V.PC.maxScoreRate))
		local rank = L.submit(top, { name = player.DisplayName, score = score, userId = player.UserId }, V.PC.boardSize)
		boardRows()
		local applied = L.capped(player, "venue_pcgame", 6, { happiness = 1 })
		local best = 0
		for _, e in top do
			if e.userId == player.UserId then
				best = e.score
			end
		end
		L.fire(player, { kind = "pcRank", rank = rank, score = score, best = best })
		if rank == 1 then
			ctx.notify(player, "stat", "🏆 PC방 레이서 1위!", string.format("%s점 · 서버 최고 기록", V.commas(score)) .. (if applied then " · " .. G.describeStats(applied) else ""))
		end
		return { ok = true, rank = rank, score = score, best = best }
	end)
	L.handle("pcBoard", function()
		local rows = {}
		for i, e in top do
			rows[i] = { name = e.name, score = e.score }
		end
		return { ok = true, rows = rows }
	end)

	L.watchTag(V.Tags.PCStation, setup)
	boardRows()

	L.onTick(function()
		local t = now()
		for _, s in table.clone(sessions) do
			if s.player.Parent ~= Players or not s.humanoid.Parent or s.humanoid.Health <= 0 then
				endSession(s, "gone")
			elseif t >= s.paidUntil then
				local st = stations[s.model]
				if L.pay(s.player, V.PC.feePerHour, string.format("광안 PC방 %02d번 (1시간 연장)", st and st.no or 0)) then
					s.paidUntil += hour
					L.fire(s.player, { kind = "pcStart", pc = s.model, no = st and st.no or 0, paidUntil = s.paidUntil, fee = V.PC.feePerHour, extended = true })
				else
					ctx.notify(s.player, "info", "광안 PC방", "잔액이 부족해서 PC가 꺼졌어요")
					endSession(s, "money")
				end
			end
		end
	end)

	L.onLeave(function(player: Player)
		local s = sessions[player]
		if s then
			endSession(s, "gone")
		end
		recent[player] = nil
	end)
end

function PC.isBusy(player: Player): boolean
	return sessions[player] ~= nil
end

return PC
