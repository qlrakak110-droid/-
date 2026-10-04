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
local st = M.Manager.station(_G.VISIT or "omok_plaza")
local f = st.frame
M.ctx.allowTeleport(plr, 10)
plr.Character:PivotTo(CFrame.lookAt((f * CFrame.new(0, 3.5, 9)).Position, f.Position + Vector3.new(0, 2, 0)))
print("VIS teleported", f.Position)
task.wait(12)
print("VIS practice")
MiniGames.handle(plr, "practice", { station = st.id, stake = 1000 })
task.wait(1)
local ps = M.Manager.stateOf(plr)
print("VIS state", ps and ps.match and ps.match.state)
local moves = 0
while ps and ps.match and ps.match.state ~= "result" and moves < 4 do
  task.wait(0.3)
  local gs = ps.match.gs
  if ps.match.state == "playing" and gs.turn == ps.side then
    MiniGames.handle(plr, "move", { cell = M.games.omok._choose(gs, gs.colorOf[ps.side], "normal", Random.new()) })
    moves += 1
    print("VIS moved", moves)
  end
end
