local Stage = require("./Stage")
local now = 1000
local published = nil
local C = {
	S = { Config = { Stage = { Lead = 0.8, Gap = 0.5, MaxCues = 10, Ticker = 10 } }, Attr = { Stage = "Stage" } },
	now = function() return now end,
	publish = function(_, v) published = v end,
}
Stage.init(C)
-- an order intro block 1002..1009.5
Stage.block(1002, 1009.5, "order")
local pos1, at1 = Stage.push("donate", 8.5, 2, { n = "a" }, 1)
local pos2, at2 = Stage.push("donate", 6.5, 1, { n = "b" }, 2)
print("cue1", pos1, at1, "cue2", pos2, at2)
assert(at1 >= 1010, "cue1 must wait for the block")
assert(at2 >= at1 + 8.5 + 0.5, "cue2 after cue1")
-- cue1 running, a new block arrives in the middle -> hold
now = at1 + 2
Stage.tick(now)
Stage.block(now + 1, now + 5, "order")
local c1 = published.cues[1]
print("holds", #c1.holds, c1.holds[1] and c1.holds[1][1], c1.holds[1] and c1.holds[1][2])
assert(#c1.holds == 1)
local c2 = published.cues[2]
print("cue2 moved to", c2.at, "end of cue1", Stage.endOf({ at = c1.at, dur = c1.dur, holds = { { c1.holds[1][1], c1.holds[1][2] } } }))
assert(c2.at >= c1.at + c1.dur + 4 + 0.5 - 0.01)
-- finished cues are dropped
now = c2.at + 20
Stage.tick(now)
print("left", #published.cues)
assert(#published.cues == 0)
print("OK")
