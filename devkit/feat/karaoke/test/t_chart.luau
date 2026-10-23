local SH = "./sh/"
local Songs = require(SH .. "Songs")
local Chart = require(SH .. "Chart")
local probs = Chart.validate(Songs)
print("songs", Songs.COUNT, "problems", #probs)
for _, p in probs do print(p) end
local tot = 0
for _, s in Songs.LIST do
  local c = Chart.get(s)
  tot += c.duration
  print(string.format("%s %d %-16s %s bpm%d dur=%.1f lines=%d taps=%d mel=%d stars=%d", s.id, s.no, s.title, s.genre, s.bpm, c.duration, #c.lines, #c.taps, #c.mel, c.stars))
end
print("avg", tot / Songs.COUNT)
