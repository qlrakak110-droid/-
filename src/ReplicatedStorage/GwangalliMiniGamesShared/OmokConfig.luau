--!strict
-- OmokConfig: rules, timers and the pure board logic of 오목 (shared: the server judges, the client
-- previews forbidden points and draws the board from the station attributes).
--
-- Board: SIZE x SIZE cells, index i = (y - 1) * SIZE + x (x, y in 1..SIZE). Encoded as a SIZE*SIZE
-- character string: "0" empty, "1" black (흑, moves first), "2" white (백).
-- Rules (OmokConfig.RULE):
--   "free"   : five or more in a row wins for both colours (자유룰).
--   "korean" : white wins with five or more; black wins only with exactly five, and black may not
--              make an overline (장목), a double three (쌍삼 / 3-3) or a double four (4-4).
-- Forbidden-point detection is the usual practical approximation (no recursive forbidden checks of
-- the follow-up points), which is what casual 오목 apps use.

local OC = {}

OC.SIZE = 15
OC.RULE = "korean" -- "free" | "korean"
OC.MOVE_TIME = 30 -- seconds per move
OC.TIMEOUT_STRIKES = 2 -- the first timeout plays a random move for you, the second loses the game
OC.CELL = 0.22 -- studs between two lines on the 3D board (15 lines -> a 3.1-stud grid on the 4-stud table)
OC.BOARD_Y = 0.12 -- board slab thickness above the table top

local SIZE = OC.SIZE
local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

function OC.idx(x: number, y: number): number
	return (y - 1) * SIZE + x
end

function OC.xy(i: number): (number, number)
	local x = (i - 1) % SIZE + 1
	local y = (i - 1) // SIZE + 1
	return x, y
end

function OC.inside(x: number, y: number): boolean
	return x >= 1 and x <= SIZE and y >= 1 and y <= SIZE
end

function OC.empty(): { number }
	local b = table.create(SIZE * SIZE, 0)
	return b
end

function OC.encode(b: { number }): string
	local parts = table.create(#b)
	for i, v in b do
		parts[i] = if v == 1 then "1" elseif v == 2 then "2" else "0"
	end
	return table.concat(parts)
end

function OC.decode(s: any): { number }
	local b = OC.empty()
	if type(s) ~= "string" then
		return b
	end
	for i = 1, math.min(#s, SIZE * SIZE) do
		local c = string.byte(s, i)
		b[i] = if c == 49 then 1 elseif c == 50 then 2 else 0
	end
	return b
end

local function at(b: { number }, x: number, y: number): number
	if not OC.inside(x, y) then
		return -1
	end
	return b[(y - 1) * SIZE + x]
end
OC.at = at

-- Length of the run of `color` through (x, y) along (dx, dy), and the cells of the run.
local function run(b: { number }, x: number, y: number, dx: number, dy: number, color: number): (number, { number })
	local cells = { OC.idx(x, y) }
	local n = 1
	local cx, cy = x + dx, y + dy
	while at(b, cx, cy) == color do
		n += 1
		table.insert(cells, OC.idx(cx, cy))
		cx += dx
		cy += dy
	end
	cx, cy = x - dx, y - dy
	while at(b, cx, cy) == color do
		n += 1
		table.insert(cells, 1, OC.idx(cx, cy))
		cx -= dx
		cy -= dy
	end
	return n, cells
end

-- After `color` played (x, y) (already on the board): the winning line (5 cells) or nil.
function OC.winLine(b: { number }, x: number, y: number, color: number, rule: string?): { number }?
	local r = rule or OC.RULE
	for _, d in DIRS do
		local n, cells = run(b, x, y, d[1], d[2], color)
		local ok = if r == "korean" and color == 1 then n == 5 else n >= 5
		if ok then
			-- the five cells nearest to the played stone (an overline shows its first five)
			local out = {}
			for i = 1, math.min(5, #cells) do
				out[i] = cells[i]
			end
			return out
		end
	end
	return nil
end

-- Would `color` at (x, y) make exactly five (a win) for black under the korean rule / five+ else?
local function makesFive(b: { number }, x: number, y: number, color: number, rule: string): boolean
	if at(b, x, y) ~= 0 then
		return false
	end
	b[OC.idx(x, y)] = color
	local w = OC.winLine(b, x, y, color, rule) ~= nil
	b[OC.idx(x, y)] = 0
	return w
end

-- Count the directions where placing black at (x, y) makes a four (a line that one more stone
-- completes to exactly five) and an open three (a line that one more stone turns into an open
-- four: four in a row with both ends empty, the four itself not an overline).
local function fourAndThrees(b: { number }, x: number, y: number): (number, number)
	local fours, threes = 0, 0
	local i0 = OC.idx(x, y)
	b[i0] = 1
	for _, d in DIRS do
		local dx, dy = d[1], d[2]
		-- four: some empty cell on this line within 4 steps completes exactly five through (x, y)
		local isFour = false
		for k = -4, 4 do
			if k ~= 0 then
				local cx, cy = x + dx * k, y + dy * k
				if at(b, cx, cy) == 0 then
					b[OC.idx(cx, cy)] = 1
					local n = run(b, x, y, dx, dy, 1)
					b[OC.idx(cx, cy)] = 0
					if n == 5 then
						isFour = true
						break
					end
				end
			end
		end
		if isFour then
			fours += 1
		else
			-- open three: some empty cell makes an open (straight) four through (x, y)
			local isThree = false
			for k = -3, 3 do
				if k ~= 0 then
					local cx, cy = x + dx * k, y + dy * k
					if at(b, cx, cy) == 0 then
						b[OC.idx(cx, cy)] = 1
						local n, cells = run(b, x, y, dx, dy, 1)
						if n == 4 then
							local fx, fy = OC.xy(cells[1])
							local lx, ly = OC.xy(cells[#cells])
							local bx, by = fx - dx, fy - dy
							local ax, ay = lx + dx, ly + dy
							if at(b, bx, by) == 0 and at(b, ax, ay) == 0 then
								-- both completions must give exactly five (not an overline)
								if makesFive(b, bx, by, 1, "korean") and makesFive(b, ax, ay, 1, "korean") then
									isThree = true
								end
							end
						end
						b[OC.idx(cx, cy)] = 0
						if isThree then
							break
						end
					end
				end
			end
			if isThree then
				threes += 1
			end
		end
	end
	b[i0] = 0
	return fours, threes
end

-- Is (x, y) a forbidden point for `color`? Returns the reason ("33" | "44" | "6") or nil.
-- A move that makes exactly five is never forbidden (the win comes first).
function OC.forbidden(b: { number }, x: number, y: number, color: number, rule: string?): string?
	local r = rule or OC.RULE
	if r ~= "korean" or color ~= 1 or at(b, x, y) ~= 0 then
		return nil
	end
	local i0 = OC.idx(x, y)
	b[i0] = 1
	local five, over = false, false
	for _, d in DIRS do
		local n = run(b, x, y, d[1], d[2], 1)
		if n == 5 then
			five = true
		elseif n > 5 then
			over = true
		end
	end
	b[i0] = 0
	if five then
		return nil
	end
	if over then
		return "6"
	end
	local fours, threes = fourAndThrees(b, x, y)
	if fours >= 2 then
		return "44"
	end
	if threes >= 2 then
		return "33"
	end
	return nil
end

OC.FORBIDDEN_TEXT = { ["33"] = "쌍삼(3-3) 금지", ["44"] = "4-4 금지", ["6"] = "장목 금지" }

function OC.full(b: { number }): boolean
	for _, v in b do
		if v == 0 then
			return false
		end
	end
	return true
end

-- Board coordinates as players read them: columns A..O (left to right from black's side), rows 1..15.
local COLS = "ABCDEFGHJKLMNOP" -- no I, like Go boards
function OC.label(i: number): string
	local x, y = OC.xy(i)
	return string.sub(COLS, x, x) .. tostring(y)
end

return OC
