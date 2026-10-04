--!strict
-- MiniGames/BetService: the ONLY money path of the minigames (server only).
--
-- In-game 원 only (MS.VIRTUAL_CURRENCY_ONLY): stakes come out of the life game's profile cash / bank
-- through ctx.spend and prizes go back through ctx.ledger (the one place GwangalliGameplay changes
-- money). Nothing here can create Robux, and nothing reads a money value from a client.
--
-- Flow (MiniGameManager calls these):
--   hold(match)              both stakes are checked first (ctx.canAfford), then taken one after the
--                            other; if the second payment fails the first is refunded at once. The
--                            money is now held by the match (escrow) - it is in nobody's wallet.
--   settle(match, winner)    exactly once per escrow (the `settled` flag is set BEFORE any ledger
--                            write and nothing between check and set yields), winner 1 | 2, 0 = draw
--                            (both stakes back). Returns the per-side net result for the result card.
--   refund(match, reason)    every stake back (cancelled before play, server shutdown, a bug).
-- NPC opponents: the house matches the player's stake. A win pays the stake back plus the house's
-- stake, limited by the player's remaining NPC allowance for the KST day (RewardService.npcRoom), so
-- the NPCs cannot be farmed for money. A loss to an NPC simply keeps the stake (it is removed from
-- the game economy, like any shop purchase).

local BetService = {}

local M: any = nil
local nextId = 0
local open: { [number]: any } = {} -- escrow id -> escrow (diagnostics + shutdown refunds)

function BetService.init(m: any)
	M = m
end

local function gameName(match: any): string
	local info = M.MS.GAMES[match.gameId]
	return if info then info.name else "미니게임"
end

local function label(match: any, what: string): string
	return "광안리 미니게임 · " .. gameName(match) .. " " .. what
end

local function isPlayer(side: any): boolean
	return side ~= nil and side.kind == "player" and side.player ~= nil
end

-- Pre-check without taking money (UI / invites): can every player side pay `stake`?
function BetService.canPay(player: Player, stake: number): boolean
	if stake <= 0 then
		return true
	end
	return M.ctx.canAfford(player, stake) == true
end

-- -> ok, failedSide?
function BetService.hold(match: any): (boolean, number?)
	if match.escrow then
		return false, nil -- never hold twice for one match
	end
	nextId += 1
	local e = { id = nextId, matchId = match.id, entries = {} :: { [number]: number }, settled = false, stake = match.stake }
	if match.stake > 0 then
		for i, side in match.sides do
			if isPlayer(side) and not BetService.canPay(side.player, match.stake) then
				return false, i
			end
		end
		for i, side in match.sides do
			if isPlayer(side) then
				local ok = M.ctx.spend(side.player, match.stake, label(match, "참가비"), false)
				if not ok then
					-- roll back what was already taken
					for j, amount in e.entries do
						local s = match.sides[j]
						M.ctx.ledger(s.player, "cash", amount, label(match, "참가비 환불"), false)
					end
					return false, i
				end
				e.entries[i] = match.stake
			end
		end
	end
	match.escrow = e
	open[e.id] = match
	return true, nil
end

-- -> { [side] = net } (0 for free games), or nil when it was already settled
function BetService.settle(match: any, winner: number): { [number]: number }?
	local e = match.escrow
	if not e or e.settled then
		return nil
	end
	e.settled = true -- first, so a second call (double finish / leave race) can never pay again
	open[e.id] = nil
	local net = { [1] = 0, [2] = 0 }
	if e.stake <= 0 then
		return net
	end
	local stake = e.stake
	if winner == 0 then
		for i, amount in e.entries do
			M.ctx.ledger(match.sides[i].player, "cash", amount, label(match, "무승부 · 참가비 반환"), false)
		end
		return net
	end
	local loser = if winner == 1 then 2 else 1
	local ws, ls = match.sides[winner], match.sides[loser]
	if isPlayer(ws) and isPlayer(ls) then
		-- PvP: the winner takes the pot (minus the configured cut, 0 by default)
		local pot = (e.entries[winner] or 0) + (e.entries[loser] or 0)
		local prize = math.floor(pot * (1 - M.MS.HOUSE_CUT) + 0.5)
		M.ctx.ledger(ws.player, "cash", prize, label(match, "상금"), false)
		net[winner] = prize - (e.entries[winner] or 0)
		net[loser] = -(e.entries[loser] or 0)
	elseif isPlayer(ws) then
		-- beat an NPC: stake back + the house's stake, capped by today's NPC allowance
		local paid = e.entries[winner] or 0
		local room = M.Reward.npcRoom(ws.player)
		local gain = math.clamp(math.min(paid, room), 0, paid)
		M.ctx.ledger(ws.player, "cash", paid + gain, label(match, "상금 (NPC)"), false)
		M.Reward.addNpcNet(ws.player, gain)
		net[winner] = gain
		match.capped = gain < paid
	elseif isPlayer(ls) then
		-- lost to an NPC: the stake stays with the house
		local paid = e.entries[loser] or 0
		M.Reward.addNpcNet(ls.player, -paid)
		net[loser] = -paid
	end
	return net
end

function BetService.refund(match: any, reason: string?)
	local e = match.escrow
	if not e or e.settled then
		return
	end
	e.settled = true
	open[e.id] = nil
	for i, amount in e.entries do
		local side = match.sides[i]
		if isPlayer(side) and amount > 0 then
			M.ctx.ledger(side.player, "cash", amount, label(match, "참가비 반환" .. (if reason then " (" .. reason .. ")" else "")), false)
		end
	end
end

-- Server shutdown: every open escrow goes back to its players before profiles are saved.
function BetService.refundAll(reason: string)
	for _, match in open do
		BetService.refund(match, reason)
	end
	table.clear(open)
end

function BetService.openCount(): number
	local n = 0
	for _ in open do
		n += 1
	end
	return n
end

return BetService
