--!strict
-- MiniGames/MatchmakingService: challenges between players (server only).
--   * direct challenge (친구에게 신청): the challenger sits at the table first (MiniGameManager
--     waiting state), the target gets "OOO님이 오목 대결을 신청했습니다. 참가비 ₩10,000 [수락][거절]".
--   * open call (상대 찾기): the same, sent to every free player in the server; the first to accept
--     takes the seat, everyone else sees it close.
--   * accepting near the table (MS.T.nearInvite) seats you at once; from further away the table is
--     reserved for you, you get a waypoint and MS.T.arriveTTL seconds to walk there (no teleport -
--     the minigames happen in the real 광안리). Arriving within MS.T.nearStation starts the match.
-- Every check (both players free, stakes affordable, the challenger still waiting at that table) is
-- repeated at accept time and again at match start (BetService.hold is the final word).

local Players = game:GetService("Players")

local MatchmakingService = {}

local M: any = nil
local MS: any = nil

type Invite = {
	id: number,
	from: Player,
	to: Player?, -- nil = open call
	station: any,
	stake: number,
	expires: number,
	open: boolean,
	sentTo: { [Player]: boolean },
	acceptedBy: Player?,
	arriveUntil: number,
}
local invites: { [number]: Invite } = {}
local nextId = 0

function MatchmakingService.init(m: any)
	M = m
	MS = m.MS
end

local function closeFor(inv: Invite, reason: string, except: Player?)
	for p in inv.sentTo do
		if p ~= except and p.Parent == Players then
			M.fire(p, MS.Kinds.inviteClosed, { id = inv.id, reason = reason })
		end
	end
end

local function remove(inv: Invite, reason: string, except: Player?)
	if invites[inv.id] ~= inv then
		return
	end
	invites[inv.id] = nil
	closeFor(inv, reason, except)
	if inv.acceptedBy then
		M.fire(inv.acceptedBy, MS.Kinds.waypoint, { station = inv.station.id, clear = true })
	end
end

local function payload(inv: Invite, to: Player): any
	local info = MS.GAMES[inv.station.game]
	return {
		id = inv.id,
		from = inv.from.DisplayName,
		fromId = inv.from.UserId,
		rank = inv.from:GetAttribute("MiniRank") or "브론즈",
		rankIcon = inv.from:GetAttribute("MiniRankIcon") or "🥉",
		game = inv.station.game,
		gameName = info.name,
		icon = info.icon,
		stake = inv.stake,
		station = inv.station.id,
		where = inv.station.seed.label,
		ttl = math.max(1, inv.expires - os.clock()),
		open = inv.open,
		dist = (function()
			local p = M.Anti.rootPos(to)
			return if p then math.floor((p - inv.station.frame.Position).Magnitude) else -1
		end)(),
	}
end

-- Direct challenge. The challenger must already be waiting at `station` (Manager.sit first).
function MatchmakingService.challenge(from: Player, to: Player, station: any, stake: number): (boolean, string?)
	if to == from or to.Parent ~= Players then
		return false, "신청할 수 없는 상대예요"
	end
	if M.Manager.isBusy(to) then
		return false, to.DisplayName .. "님은 지금 다른 게임 중이에요"
	end
	for _, inv in invites do
		if inv.from == from and inv.to == to then
			return false, "이미 신청했어요. 답을 기다려 주세요"
		end
	end
	nextId += 1
	local inv: Invite = { id = nextId, from = from, to = to, station = station, stake = stake, expires = os.clock() + MS.T.inviteTTL, open = false, sentTo = { [to] = true }, acceptedBy = nil, arriveUntil = 0 }
	invites[inv.id] = inv
	M.fire(to, MS.Kinds.invite, payload(inv, to))
	return true, nil
end

-- Open call to every free player (상대 찾기).
function MatchmakingService.openCall(from: Player, station: any, stake: number): number
	nextId += 1
	local inv: Invite = { id = nextId, from = from, to = nil, station = station, stake = stake, expires = os.clock() + MS.T.openTTL, open = true, sentTo = {}, acceptedBy = nil, arriveUntil = 0 }
	invites[inv.id] = inv
	local n = 0
	for _, p in Players:GetPlayers() do
		if p ~= from and not M.Manager.isBusy(p) then
			inv.sentTo[p] = true
			M.fire(p, MS.Kinds.invite, payload(inv, p))
			n += 1
		end
	end
	return n
end

function MatchmakingService.respond(player: Player, id: number, accept: boolean)
	local inv = invites[id]
	if not inv or not inv.sentTo[player] then
		return
	end
	if not accept then
		inv.sentTo[player] = nil
		if not inv.open then
			remove(inv, "declined")
			M.toast(inv.from, "info", "대결 거절", player.DisplayName .. "님이 거절했어요")
		end
		return
	end
	if inv.acceptedBy then
		M.fire(player, MS.Kinds.inviteClosed, { id = id, reason = "taken" })
		return
	end
	-- the challenger must still be waiting at that table
	local w = inv.station.waiting
	if not w or w.player ~= inv.from or inv.station.match then
		remove(inv, "gone")
		M.toast(player, "warn", "신청 취소됨", "상대가 자리를 떠났어요")
		return
	end
	if M.Manager.isBusy(player) then
		M.toast(player, "warn", "지금은 안 돼요", "다른 게임을 먼저 끝내 주세요")
		return
	end
	if not M.Bet.canPay(player, inv.stake) then
		M.toast(player, "warn", "게임머니 부족", "참가비 " .. MS.won(inv.stake) .. "가 필요해요")
		return
	end
	inv.acceptedBy = player
	closeFor(inv, "taken", player)
	inv.sentTo = { [player] = true }
	if M.Anti.near(player, inv.station.frame.Position, MS.T.nearInvite) then
		invites[inv.id] = nil
		M.Manager.joinWaiting(inv.station, player)
	else
		inv.arriveUntil = os.clock() + MS.T.arriveTTL
		inv.station.waiting.reservedFor = player
		M.Manager.publishStation(inv.station)
		M.fire(player, MS.Kinds.waypoint, { station = inv.station.id, pos = inv.station.frame.Position, ttl = MS.T.arriveTTL, label = inv.station.seed.label })
		M.toast(inv.from, "success", "수락!", player.DisplayName .. "님이 오고 있어요")
	end
end

-- The waiting player stood up / left: close their calls.
function MatchmakingService.cancelFrom(player: Player, reason: string)
	for _, inv in invites do
		if inv.from == player then
			remove(inv, reason)
			if inv.acceptedBy and inv.acceptedBy ~= player then
				M.toast(inv.acceptedBy, "warn", "신청 취소됨", player.DisplayName .. "님이 자리를 떠났어요")
			end
		end
	end
end

function MatchmakingService.onLeave(player: Player)
	MatchmakingService.cancelFrom(player, "left")
	for _, inv in invites do
		inv.sentTo[player] = nil
		if inv.acceptedBy == player then
			inv.acceptedBy = nil
			if inv.station.waiting then
				inv.station.waiting.reservedFor = nil
			end
			if not inv.open then
				remove(inv, "left")
			end
		end
	end
end

function MatchmakingService.hasOpenCall(station: any): boolean
	for _, inv in invites do
		if inv.station == station and inv.open then
			return true
		end
	end
	return false
end

function MatchmakingService.tick(now: number)
	for _, inv in invites do
		if inv.acceptedBy then
			local p = inv.acceptedBy :: Player
			if p.Parent ~= Players or now > inv.arriveUntil then
				if inv.station.waiting then
					inv.station.waiting.reservedFor = nil
					M.Manager.publishStation(inv.station)
				end
				M.toast(inv.from, "info", "상대가 오지 않았어요", "다시 상대를 찾아보세요")
				remove(inv, "timeout")
			elseif M.Anti.near(p, inv.station.frame.Position, MS.T.nearStation) then
				invites[inv.id] = nil
				M.fire(p, MS.Kinds.waypoint, { station = inv.station.id, clear = true })
				M.Manager.joinWaiting(inv.station, p)
			end
		elseif now > inv.expires then
			if not inv.open then
				M.toast(inv.from, "info", "응답 없음", "신청이 만료됐어요")
			end
			remove(inv, "expired")
		end
	end
end

return MatchmakingService
