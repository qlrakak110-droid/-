local Songs = require("./sh/Songs")
local Search = require("./sh/Search")
local Score = require("./sh/Score")
local function show(q)
  local r = Search.find(Songs, q, 4)
  local t = {}
  for _, s in r do table.insert(t, s.no .. " " .. s.title) end
  print(q, "->", table.concat(t, " | "))
end
for _, q in { "ㄱㅇㄷㄱ", "38262", "치킨", "광안ㄷ", "아리랑", "김부산", "ㅇㄹㄹ", "트로트", "2호선", "4", "pc" } do show(q) end
print(Search.choseong("광안대교 불빛 아래"))
print("tap all P", Score.tapScore(50, 0, 50, 50), "half", Score.tapScore(25, 0, 50, 10), "none", Score.tapScore(0,0,50,0), "goods", Score.tapScore(0, 50, 50, 50))
print("voice", Score.voiceScore(0.8*12, 12), Score.voiceScore(0.5*12, 12), Score.voiceScore(0, 12))
print("judge", Score.judge(0.05), Score.judge(-0.15), Score.judge(0.3), Score.judge(0.5))
print("grade", Score.grade(100).id, Score.grade(93).id, Score.grade(55).id, Score.comment(100, 1), Score.comment(72, 3))
print("beatOff", Score.beatOffset(0.5, 1.26), Score.beatOffset(0.5, 1.12))
