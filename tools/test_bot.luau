-- plays one practice match per game against the NPC host through MiniGames.handle (the remote path)
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
local GAMES = string.split(_G.TEST_GAMES or "omok,wordchain,rps,reaction,memory,numberguess,timing,quiz", ",")
local function money() return (plr:GetAttribute("Money") or 0), (plr:GetAttribute("Bank") or 0) end
local oldToast = M.toast
M.toast = function(p, k, t, b) print("TOAST", k, t, b) return oldToast(p, k, t, b) end
local OC = M.OC
local WR = M.WR
for _, gid in GAMES do
  local st
  for _, s in M.Manager.stations() do if s.game == gid and s.npc then st = s break end end
  if not st then print("TEST", gid, "no npc station") continue end
  M.ctx.allowTeleport(plr, 10)
  plr.Character:PivotTo(st.frame * CFrame.new(0, 4, 6))
  task.wait(0.5)
  local c0, b0 = money()
  local stake = M.MS.NPC_STAKES[st.npc.difficulty][2]
  MiniGames.handle(plr, "practice", { station = st.id, stake = stake })
  task.wait(0.3)
  local ps = M.Manager.stateOf(plr)
  if not ps then print("TEST", gid, "FAILED to start") continue end
  local match = ps.match
  local side = ps.side
  print("TEST", gid, "started match", match.id, "stake", stake, "money", c0, "->", money())
  local t0 = os.clock()
  local lastRound = -1
  while match.state ~= "result" and match.state ~= "closed" and os.clock() - t0 < 240 do
    task.wait(0.15)
    local gs = match.gs
    if match.state == "playing" then
      if gid == "omok" and gs.turn == side then
        local cell = M.games.omok._choose(gs, gs.colorOf[side], "hard", Random.new())
        MiniGames.handle(plr, "move", { cell = cell })
      elseif gid == "wordchain" and gs.turn == side and not gs.busy[side] then
        local opts = M.games.wordchain.Dict.starting(WR.starts(gs.current))
        local pick
        for _, w in opts do if not gs.used[w] then pick = w break end end
        if pick and (gs.lastTry ~= gs.current) then gs.lastTry = gs.current MiniGames.handle(plr, "move", { word = pick }) end
      elseif gid == "rps" and gs.phase == "count" and not gs.choice[side] then
        MiniGames.handle(plr, "move", { hand = math.random(1, 3) })
      elseif gid == "reaction" and gs.phase == "go" and not gs.press[side] then
        task.wait(0.25)
        MiniGames.handle(plr, "move", { round = gs.round, rt = 0.25 })
      elseif gid == "memory" and gs.phase == "input" and not gs.answers[side] then
        MiniGames.handle(plr, "move", { round = gs.round, answer = gs.seq })
      elseif gid == "numberguess" and gs.turn == side then
        MiniGames.handle(plr, "move", { n = (gs.lo + gs.hi) // 2 })
        task.wait(0.3)
      elseif gid == "timing" and gs.phase == "run" and not gs.press[side] then
        local per = gs.period
        local t = os.clock() - gs.startAt
        -- press at the next centre crossing
        local k = math.ceil((t / per - 0.5))
        local target = (k + 0.5) * per
        if target - t < 0.05 then target += per end
        task.wait(target - t)
        MiniGames.handle(plr, "move", { round = gs.round, t = os.clock() - gs.startAt })
      elseif gid == "quiz" and gs.phase == "q" and not gs.answers[side] then
        local q = gs.list[gs.qi]
        MiniGames.handle(plr, "move", { q = gs.qi, choice = q.a, t = os.clock() - gs.startAt })
      end
    end
  end
  local r = match.result
  print("TEST", gid, "state", match.state, "winner", r and r.winner, "reason", r and r.reason, "net", r and r.net[side], "money", money(), "rec", r and r.records[side] and (r.records[side].rating .. " " .. r.records[side].rank))
  MiniGames.handle(plr, "leave", {})
  task.wait(0.5)
  print("TEST", gid, "after leave busy", M.Manager.isBusy(plr), "station", st.model:GetAttribute("State"), "escrows open", M.Bet.openCount())
end
print("TEST DONE")
