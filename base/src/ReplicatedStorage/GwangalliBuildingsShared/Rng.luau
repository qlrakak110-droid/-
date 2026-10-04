-- GwangalliBuildings/Rng: a small deterministic random generator (mulberry32 on bit32), so the same
-- building seed always produces the same building on every server and in every test, independent of
-- Random's implementation. Also string hashing for stable per-object seeds.
--
--   local r = Rng.new(Rng.hash("apt1"))
--   r:next() -> [0, 1)   r:range(a, b) -> number   r:int(a, b) -> integer   r:pick(list)   r:chance(p)

local Rng = {}
Rng.__index = Rng

local band, bxor, rshift, lshift = bit32.band, bit32.bxor, bit32.rshift, bit32.lshift

-- 32-bit multiply mod 2^32 (exact for any operands: split into 16-bit halves)
local function mul32(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	local lo = al * bl
	local mid = band(ah * bl + al * bh, 0xFFFF)
	return band(lo + lshift(mid, 16), 0xFFFFFFFF)
end

-- FNV-1a 32-bit hash of a string (or a number / any tostring-able value)
function Rng.hash(s: any): number
	local str = tostring(s)
	local h = 2166136261
	for i = 1, #str do
		h = bxor(h, string.byte(str, i))
		h = mul32(h, 16777619)
	end
	return h
end

function Rng.new(seed: number?): any
	local self = setmetatable({}, Rng)
	self.s = band(math.floor(tonumber(seed) or 1) % 4294967296, 0xFFFFFFFF)
	if self.s == 0 then
		self.s = 0x9E3779B9
	end
	return self
end

-- child generator for a sub-part (stable: does not depend on how much the parent was used)
function Rng.child(seed: number, key: any): any
	return Rng.new(bxor(seed, Rng.hash(key)))
end

function Rng:next(): number
	self.s = band(self.s + 0x6D2B79F5, 0xFFFFFFFF)
	local t = self.s
	t = mul32(bxor(t, rshift(t, 15)), bit32.bor(t, 1))
	t = bxor(t, band(t + mul32(bxor(t, rshift(t, 7)), bit32.bor(t, 61)), 0xFFFFFFFF))
	return bxor(t, rshift(t, 14)) / 4294967296
end

function Rng:range(a: number, b: number): number
	return a + (b - a) * self:next()
end

function Rng:int(a: number, b: number): number
	return math.min(b, a + math.floor(self:next() * (b - a + 1)))
end

function Rng:chance(p: number): boolean
	return self:next() < p
end

function Rng:pick<T>(list: { T }): T
	return list[self:int(1, #list)]
end

-- weighted pick: { {value, weight}, ... }
function Rng:weighted(list: { any }): any
	local total = 0
	for _, e in list do
		total += e[2]
	end
	local x = self:next() * total
	for _, e in list do
		x -= e[2]
		if x <= 0 then
			return e[1]
		end
	end
	return list[#list][1]
end

function Rng:shuffle(list: { any }): { any }
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng
