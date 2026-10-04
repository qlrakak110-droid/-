local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local folder
for _, c in SSS:GetChildren() do if c.Name == "GwangalliGameplay" and c:IsA("Folder") then folder = c end end
local MiniGames = require(folder.MiniGames)
local M = MiniGames._M
local plr = Players:GetPlayers()[1]
while not M.Manager or #M.Manager.stations() == 0 do task.wait(0.5) end
while not M.ctx.Profiles.get(plr) do task.wait(0.5) end
task.wait(3)
local function cash() return plr:GetAttribute("Money") end
local function check(name, cond, extra) print("FLOW", name, cond and "PASS" or "FAIL", extra or "") end
local st = M.Manager.station("omok_plaza")
M.ctx.allowTeleport(plr, 10)
plr.Character:PivotTo(st.frame * CFrame.new(0, 4, 6))
task.wait(1)
-- 1. leave during seating/countdown -> refund
local c0 = cash()
MiniGames.handle(plr, "practice", { station = st.id, stake = 1000 })
task.wait(0.2)
check("1 stake taken", cash() == c0 - 1000, cash())
MiniGames.handle(plr, "leave", {})
task.wait(0.5)
check("1 refunded before play", cash() == c0, cash())
check("1 free", not M.Manager.isBusy(plr) and st.model:GetAttribute("State") == "idle")
-- 2. forfeit during play
task.wait(1)
c0 = cash()
MiniGames.handle(plr, "practice", { station = st.id, stake = 1000 })
local ps = M.Manager.stateOf(plr)
local match = ps and ps.match
print("FLOW 2 started", match and match.state)
local tw = 0
while match and match.state ~= "playing" and match.state ~= "closed" and tw < 200 do task.wait(0.2) tw += 1 end
print("FLOW 2 state", match and match.state)
MiniGames.handle(plr, "forfeit", {})
task.wait(0.3)
check("2 forfeit loses stake", cash() == c0 - 1000 and match.result and match.result.winner == 2, tostring(cash()) .. " " .. tostring(match.result and match.result.reason))
-- double finish / settle cannot pay twice
local before = cash()
M.Manager.finish(match, 1, "five")
local again = M.Bet.settle(match, 1)
check("2 no double pay", cash() == before and again == nil)
MiniGames.handle(plr, "leave", {})
task.wait(0.5)
-- 3. direct escrow with two player sides (PvP money path)
c0 = cash()
local fake = { id = 999, gameId = "omok", stake = 5000, sides = { { kind = "player", player = plr, name = "A" }, { kind = "player", player = plr, name = "B" } } }
local ok = M.Bet.hold(fake)
check("3 hold both", ok and cash() == c0 - 10000, cash())
local holdAgain = M.Bet.hold(fake)
check("3 no double hold", holdAgain == false and cash() == c0 - 10000)
local net = M.Bet.settle(fake, 1)
check("3 winner takes pot", cash() == c0 and net and net[1] == 5000 and net[2] == -5000, cash())
M.Bet.refund(fake, "x")
check("3 refund after settle is no-op", cash() == c0)
-- 4. unaffordable stake rejected (server side)
local fake2 = { id = 998, gameId = "omok", stake = 10 ^ 9, sides = { { kind = "player", player = plr, name = "A" }, { kind = "npc", name = "N", difficulty = "hard" } } }
c0 = cash()
check("4 cannot afford", M.Bet.hold(fake2) == false and cash() == c0)
-- 5. invalid stake via remote path
MiniGames.handle(plr, "practice", { station = st.id, stake = 50000 }) -- not an NPC stake for normal
task.wait(0.2)
check("5 bad npc stake rejected", not M.Manager.isBusy(plr) and cash() == c0)
MiniGames.handle(plr, "sit", { station = st.id, stake = 777 })
task.wait(0.2)
check("5 bad stake rejected", not M.Manager.isBusy(plr))
-- 6. waiting seat then stand up
MiniGames.handle(plr, "sit", { station = st.id, stake = 1000 })
task.wait(0.3)
check("6 waiting", st.model:GetAttribute("State") == "waiting" and st.model:GetAttribute("WaitStake") == 1000 and cash() == c0)
MiniGames.handle(plr, "leave", {})
task.wait(0.3)
check("6 stood", st.model:GetAttribute("State") == "idle" and not M.Manager.isBusy(plr))
-- 7. NPC daily cap
local rec = M.Reward.get(plr)
rec.npcDay = { day = M.MS.kstDay(os.time()), net = M.MS.NPC_DAILY_PROFIT_CAP - 400 }
local fake3 = { id = 997, gameId = "omok", stake = 1000, sides = { { kind = "player", player = plr, name = "A" }, { kind = "npc", name = "N", difficulty = "normal" } } }
c0 = cash()
M.Bet.hold(fake3)
local n3 = M.Bet.settle(fake3, 1)
check("7 npc cap", n3[1] == 400 and cash() == c0 + 400 and fake3.capped == true, cash())
-- 8. payload junk
MiniGames.handle(plr, "move", { cell = 0/0 })
MiniGames.handle(plr, "practice", "string")
MiniGames.handle(plr, "nope", {})
check("8 junk ignored", not M.Manager.isBusy(plr))
print("FLOW DONE")
