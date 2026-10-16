-- GwangalliKaraokeShared/Chart: the deterministic TIMELINE of a song. The server and every client compute
-- exactly the same chart from a Songs entry, so only a song id, a clock string and small numbers
-- ever cross the network.
--
--   local c = Chart.get(songOrId)          cached per song id
--   c = { id, bpm, beat, meter, bar, intro, duration, tonic (midi), minor, preset, genre,
--         lines = { { text, chars, part ("M" | "F" | "A"), sect ("verse" | "chorus"), src (song line),
--                     t0, e (last syllable end), due (voice result due), rest = {a, b},
--                     show, hide, slot (1 | 2), dots (countdown before it), block,
--                     syl = { {ci, t, e, p} }, sylT = { [ci] = t }, sylE = { [ci] = e } } },
--         mel = { {t, d, p, li} }          every guide-melody note (midi), sorted by t
--         taps = { {t, lane, li, ci} }     rhythm-game notes (subset of syllable onsets)
--         chords = { {t, d, root (pc), q ("M" | "m" | "dim" | "7" | "m7" | "M7"), bass (midi)} }  one per bar
--         sects = { {t, e, kind ("intro" | "verse" | "chorus" | "inter" | "outro")} },
--         stars (1..3) }
--   Chart.lineAt(c, st) -> index of the line being sung (or the next one)
--   Chart.sectAt(c, st) -> sect?    Chart.chordAt(c, st) -> chord?
--   Chart.validate(Songs) -> { problem strings }
-- All times are song seconds at the song's base tempo (S.songTime of the room clock). Original songs
-- get a melody COMPOSED here from the style's chord progression and the song seed; written-out melodies
-- (민요 / public-domain tunes) are parsed from their tokens and harmonised bar by bar.

local Chart = {}

Chart.MIN_GAP = 0.42 -- s between two rhythm notes (base tempo)
Chart.LANES = 3

local PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

local MAJOR = { 0, 2, 4, 5, 7, 9, 11 }
local MINOR = { 0, 2, 3, 5, 7, 8, 10 }
local ROMAN = { i = 1, ii = 2, iii = 3, iv = 4, v = 5, vi = 6, vii = 7 }

-- chord progressions per band preset: one chord per bar, 8 bars = 4 lyric lines
local PROG = {
	ballad = { verse = "I V vi iii IV I IV V", chorus = "IV V iii vi ii V I I", mverse = "i VI III VII iv i iv V", mchorus = "VI VII i i iv V i i" },
	acoustic = { verse = "I IV vi V I IV V V", chorus = "IV V I vi IV V I I", mverse = "i VI VII i iv VI V V", mchorus = "VI VII i i iv V i i" },
	rnb = { verse = "IVM7 iii7 vi7 V I IVM7 ii7 V", chorus = "IVM7 V iii7 vi7 ii7 V I I", mverse = "i7 iv7 VII III i7 iv7 VI V", mchorus = "VI VII i7 i7 iv7 V i7 i7" },
	pop = { verse = "I V vi IV I V vi IV", chorus = "IV V iii vi IV V I I", mverse = "i VI III VII i VI III VII", mchorus = "VI VII i i VI VII V V" },
	citypop = { verse = "IVM7 iii7 vi7 I7 IVM7 iii7 ii7 V", chorus = "ii7 V IM7 vi7 ii7 V IM7 IM7", mverse = "i7 iv7 VII III i7 iv7 VI V", mchorus = "iv7 VII III VI iv7 V i7 i7" },
	dance = { verse = "vi IV I V vi IV I V", chorus = "IV V iii vi IV V I I", mverse = "i VI III VII i VI III VII", mchorus = "VI VII i i VI VII i i" },
	edm = { verse = "vi IV I V vi IV I V", chorus = "vi IV I V vi IV V V", mverse = "i VI III VII i VI III VII", mchorus = "i VI III VII i VI VII VII" },
	trot = { verse = "I I IV I V V I I", chorus = "IV IV I I V V I I", mverse = "i i iv i V V i i", mchorus = "iv iv i i V V i i" },
	hiphop = { verse = "vi IV I V vi IV I V", chorus = "vi IV I V vi IV I V", mverse = "i VI III VII i VI III VII", mchorus = "i VI III VII i VI V V" },
	rock = { verse = "I V vi IV I V IV V", chorus = "IV I V vi IV I V V", mverse = "i VII VI VII i VII VI V", mchorus = "VI VII i i VI VII V V" },
	kids = { verse = "I IV V I I IV V I", chorus = "IV I V I IV I V I", mverse = "i iv V i i iv V i", mchorus = "iv i V i iv i V i" },
	folk = { verse = "I I V I I I V I", chorus = "I IV V I I IV V I", mverse = "i i v i i i v i", mchorus = "i iv v i i iv v i" },
	ost = { verse = "I V vi iii IV I ii V", chorus = "IV V iii vi IV V I I", mverse = "i VI III VII iv i iv V", mchorus = "VI VII i VI iv V i i" },
}
Chart.PROG = PROG

local cache: { [string]: any } = {}

-------------------------------------------------------------------------------------------------
-- small helpers
-------------------------------------------------------------------------------------------------
local function codepoints(s: string): { string }
	local out = {}
	for _, c in utf8.codes(s) do
		table.insert(out, utf8.char(c))
	end
	return out
end
Chart.codepoints = codepoints

-- deterministic generator (exact in doubles on every peer)
local function lcg(seed: number): () -> number
	local st = (math.floor(math.abs(seed)) * 7919 + 13) % 2147483647
	if st == 0 then
		st = 1
	end
	return function(): number
		st = (st * 48271) % 2147483647
		return st / 2147483647
	end
end

function Chart.noteName(p: number): string
	local m = math.floor(p + 0.5)
	return NAMES[m % 12 + 1] .. tostring(m // 12 - 1)
end

-- "C4" / "F#4" / "Bb3" -> midi
local function noteMidi(s: string): number?
	local l, acc, oct = string.match(s, "^([A-G])([#b]?)(%-?%d)$")
	if not l then
		return nil
	end
	local p = PC[l] + (if acc == "#" then 1 elseif acc == "b" then -1 else 0)
	return 12 * (tonumber(oct) :: number + 1) + p
end
Chart.noteMidi = noteMidi

-- key "C" / "Am" / "F#m" / "Bb" -> root pc, minor
local function keyInfo(key: string?): (number, boolean)
	local k = key or "C"
	local l, acc, m = string.match(k, "^([A-G])([#b]?)(m?)$")
	if not l then
		return 0, false
	end
	local pc = (PC[l] + (if acc == "#" then 1 elseif acc == "b" then -1 else 0)) % 12
	return pc, m == "m"
end
Chart.keyInfo = keyInfo

-- roman numeral -> { off (semitones from the key root), q }
local function parseRoman(tok: string, minor: boolean): any
	local core, suf = string.match(tok, "^([iIvV]+)(.*)$")
	if not core then
		return { off = 0, q = "M" }
	end
	local lower = string.lower(core)
	local deg = ROMAN[lower] or 1
	local scale = if minor then MINOR else MAJOR
	local off = scale[deg]
	local upper = core ~= lower
	local q = if upper then "M" else "m"
	if suf == "°" or suf == "o" then
		q = "dim"
	elseif suf == "7" then
		q = if upper then (if deg == 5 or (minor and deg == 7) or deg == 1 then "7" else "M7") else "m7"
	elseif suf == "M7" then
		q = "M7"
	end
	return { off = off, q = q }
end

local function progOf(preset: string, minor: boolean, kind: string): { any }
	local p = PROG[preset] or PROG.pop
	local src = if minor then (if kind == "chorus" then p.mchorus else p.mverse) else (if kind == "chorus" then p.chorus else p.verse)
	local out = {}
	for tok in string.gmatch(src, "%S+") do
		table.insert(out, parseRoman(tok, minor))
	end
	return out
end

local function chordTones(q: string): { number }
	if q == "m" then
		return { 0, 3, 7 }
	elseif q == "dim" then
		return { 0, 3, 6 }
	elseif q == "7" then
		return { 0, 4, 7, 10 }
	elseif q == "m7" then
		return { 0, 3, 7, 10 }
	elseif q == "M7" then
		return { 0, 4, 7, 11 }
	end
	return { 0, 4, 7 }
end
Chart.chordTones = chordTones

local function triadQ(minor: boolean, off: number): string
	local scale = if minor then MINOR else MAJOR
	local degIdx = 1
	for i, s in scale do
		if s == off then
			degIdx = i
		end
	end
	local function has(semi: number): boolean
		local pc = (off + semi) % 12
		for _, s in scale do
			if s == pc then
				return true
			end
		end
		return false
	end
	local _ = degIdx
	if has(4) and has(7) then
		return "M"
	elseif has(3) and has(7) then
		return "m"
	elseif has(3) and has(6) then
		return "dim"
	end
	return "M"
end

-------------------------------------------------------------------------------------------------
-- written-out melody tokens
-------------------------------------------------------------------------------------------------
-- "D4:0.5+E4:0.5" -> { notes = { {p, d} }, d, rest }
local function parseToken(tok: string): any?
	local rest = string.match(tok, "^r:?([%d%.]*)$")
	if rest then
		return { rest = true, d = tonumber(rest) or 1, notes = {} }
	end
	local notes = {}
	local total = 0
	for part in string.gmatch(tok, "[^+]+") do
		local nm, dur = string.match(part, "^([A-G][#b]?%-?%d):?([%d%.]*)$")
		if not nm then
			return nil
		end
		local p = noteMidi(nm)
		if not p then
			return nil
		end
		local d = tonumber(dur) or 1
		table.insert(notes, { p = p, d = d })
		total += d
	end
	if #notes == 0 then
		return nil
	end
	return { rest = false, d = total, notes = notes }
end
Chart.parseToken = parseToken

-------------------------------------------------------------------------------------------------
-- the composer (original songs)
-------------------------------------------------------------------------------------------------
-- syllable rhythm of one generated line: onsets / durations in beats from the line start
local function rhythm(chars: { string }, meter: number, preset: string, rnd: () -> number): ({ any }, number)
	local syl = {}
	for ci, ch in chars do
		if ch ~= " " then
			local wordStart = ci == 1 or chars[ci - 1] == " "
			local wordEnd = ci == #chars or chars[ci + 1] == " "
			table.insert(syl, { ci = ci, ws = wordStart, we = wordEnd })
		end
	end
	local n = #syl
	local L = meter * 2
	local S = if meter == 3 then 4.5 else 6
	local grid = if n > 12 then 0.25 else 0.5
	if preset == "hiphop" and n > 9 then
		S = if meter == 3 then 5 else 6.5
		grid = 0.25
	end
	if n > 14 then
		S = L - 1
	end
	local w = table.create(n, 1)
	local total = 0
	for k, s in syl do
		local v = 1
		if k == n then
			v = if preset == "hiphop" then 1.5 else 2.2
		elseif s.we then
			v = if preset == "hiphop" then 1.1 else 1.45 + rnd() * 0.25
		elseif preset == "trot" and s.ws and k > 1 then
			v = 1.15
		end
		w[k] = v
		total += v
	end
	local out = {}
	local cum = 0
	local last = -1
	for k = 1, n do
		local raw = S * cum / total
		local q = math.floor(raw / grid + 0.5) * grid
		if q <= last then
			q = last + grid
		end
		out[k] = { ci = syl[k].ci, o = q, ws = syl[k].ws }
		last = q
		cum += w[k]
	end
	-- squeeze if the grid pushed the last onsets too far
	local maxLast = L - 1.5
	if n > 0 and out[n].o > maxLast then
		local over = out[n].o - maxLast
		for k = n, 1, -1 do
			local cap = maxLast - (n - k) * grid
			if out[k].o > cap then
				out[k].o = math.max(0, cap)
			end
		end
		local _ = over
	end
	for k = 1, n do
		local nx = if k < n then out[k + 1].o else nil
		if nx then
			out[k].d = nx - out[k].o
		else
			out[k].d = math.clamp(L - 1 - out[k].o, grid, 3)
		end
	end
	return out, L
end

local function chordAtBeat(chords: { any }, b: number): any
	-- chords are in beats here (converted to seconds at the end)
	local found = chords[1]
	for _, c in chords do
		if c.b <= b + 1e-6 then
			found = c
		else
			break
		end
	end
	return found
end

-- pitch every syllable of a generated line
local function compose(rh: { any }, lineStart: number, chords: { any }, scalePcs: { number }, tonicMidi: number, meter: number, isChorus: boolean, endsSection: boolean, pairPos: number, rnd: () -> number, prevPitch: number?): { number }
	local n = #rh
	local pitches = table.create(n, tonicMidi)
	local lo, hi = tonicMidi - 5, tonicMidi + 14
	local function inScale(m: number): boolean
		local pc = (m - tonicMidi) % 12
		for _, s in scalePcs do
			if s == pc then
				return true
			end
		end
		return false
	end
	local base = tonicMidi + (if isChorus then 5 else 1) + math.floor(rnd() * 3) - 1
	local amp = (if isChorus then 5 else 4) + math.floor(rnd() * 3)
	local peak = 0.35 + rnd() * 0.35
	local fall = if pairPos == 2 then -2 else 1 -- the answering line of a pair settles lower
	local prev = prevPitch or (tonicMidi + (if isChorus then 4 else 0))
	for k = 1, n do
		local s = rh[k]
		local b = lineStart + s.o
		local inBar = s.o % meter
		local strong = math.abs(inBar - math.floor(inBar + 0.5)) < 1e-6 and (math.floor(inBar + 0.5) % 2 == 0 or meter == 3 and math.floor(inBar + 0.5) == 0)
		local u = if n > 1 then (k - 1) / (n - 1) else 0
		local shape = if u <= peak then math.sin(u / peak * math.pi / 2) else math.cos((u - peak) / (1 - peak) * math.pi / 2)
		local target = base + amp * shape + fall * u
		local ch = chordAtBeat(chords, b)
		local tones = chordTones(ch.q)
		local cands = {}
		local useChord = strong or k == 1 or k == n or s.d >= 1
		for m = lo, hi do
			local ok = false
			if useChord then
				local rel = (m - (tonicMidi + ch.off)) % 12
				for _, t in tones do
					if t == rel then
						ok = true
					end
				end
			else
				ok = inScale(m)
			end
			if ok then
				table.insert(cands, m)
			end
		end
		if k == n then
			-- line end: a phrase that closes a section lands on the tonic, the answering line of a pair
			-- on the chord root, the asking line on a chord tone above
			if endsSection then
				cands = {}
				for m = lo, hi do
					if (m - tonicMidi) % 12 == 0 then
						table.insert(cands, m)
					end
				end
			elseif pairPos == 2 then
				local root = (tonicMidi + ch.off) % 12
				local c2 = {}
				for _, m in cands do
					if m % 12 == root then
						table.insert(c2, m)
					end
				end
				if #c2 > 0 then
					cands = c2
				end
			end
		end
		local best, bestCost = prev, math.huge
		for _, m in cands do
			local jump = math.abs(m - prev)
			local cost = math.abs(m - target) + 0.55 * jump
			if jump > 7 then
				cost += 6
			end
			if jump == 0 then
				cost += if rnd() < 0.5 then -0.4 else 0.6
			end
			cost += rnd() * 0.35
			if cost < bestCost then
				best, bestCost = m, cost
			end
		end
		pitches[k] = best
		prev = best
	end
	return pitches
end

-------------------------------------------------------------------------------------------------
-- the harmoniser (written-out melodies): one diatonic chord per bar
-------------------------------------------------------------------------------------------------
local function harmonize(mel: { any }, barB: number, nBars: number, firstBar: number, lastBar: number, minor: boolean, tonicPc: number): { any }
	local cands
	if minor then
		cands = { { off = 0, q = "m" }, { off = 5, q = "m" }, { off = 7, q = "M" }, { off = 8, q = "M" }, { off = 3, q = "M" }, { off = 10, q = "M" } }
	else
		cands = { { off = 0, q = "M" }, { off = 7, q = "M" }, { off = 5, q = "M" }, { off = 9, q = "m" }, { off = 2, q = "m" }, { off = 4, q = "m" } }
	end
	local out = {}
	local prev = cands[1]
	local idx = 1
	for bar = 0, nBars - 1 do
		local bs, be = bar * barB, (bar + 1) * barB
		local weights: { [number]: number } = {}
		local total = 0
		while idx <= #mel and mel[idx].b + mel[idx].d <= bs + 1e-6 do
			idx += 1
		end
		local j = idx
		while j <= #mel and mel[j].b < be - 1e-6 do
			local m = mel[j]
			local a, z = math.max(bs, m.b), math.min(be, m.b + m.d)
			if z > a then
				local wgt = (z - a) * (if math.abs(m.b - bs) < 1e-6 then 1.6 else 1)
				local pc = (m.p - tonicPc) % 12
				weights[pc] = (weights[pc] or 0) + wgt
				total += wgt
			end
			j += 1
		end
		local pick = prev
		if total > 0 then
			local bestS = -math.huge
			for ci, c in cands do
				local tones = chordTones(c.q)
				local sc = 0
				for pc, wgt in weights do
					local rel = (pc - c.off) % 12
					local hit = false
					for _, t in tones do
						if t == rel then
							hit = true
						end
					end
					sc += if hit then wgt else -0.35 * wgt
				end
				sc -= ci * 0.01 * total -- order = tie break (I, V, IV, ...)
				if bar == firstBar and c.off == 0 then
					sc += 0.3 * total
				end
				if bar == lastBar and c.off == 0 then
					sc += 0.6 * total
				end
				if bar == lastBar - 1 and c.off == 7 then
					sc += 0.25 * total
				end
				if c == prev then
					sc += 0.05 * total
				end
				if sc > bestS then
					bestS, pick = sc, c
				end
			end
		elseif bar >= lastBar then
			pick = cands[1]
		end
		out[bar + 1] = pick
		prev = pick
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- build
-------------------------------------------------------------------------------------------------
local function defaultForm(song: any): { any }
	local n = #song.lines
	if song.form then
		return song.form
	end
	if song.explicit then
		local f = {}
		for i = 1, n do
			f[i] = i
		end
		return f
	end
	local ch = math.clamp(song.ch or 5, 2, n)
	local cEnd = math.min(ch + 3, n)
	local f = {}
	for i = 1, ch - 1 do
		table.insert(f, i)
	end
	for i = ch, cEnd do
		table.insert(f, i)
	end
	table.insert(f, "간주")
	for i = cEnd + 1, n do
		table.insert(f, i)
	end
	for i = ch, cEnd do
		table.insert(f, i)
	end
	return f
end

local function build(song: any): any
	local meter = song.meter or 4
	local bpm = math.clamp(tonumber(song.bpm) or 100, 50, 200)
	local beat = 60 / bpm
	local barS = beat * meter
	local tonicPc, minor = keyInfo(song.key)
	local tonic = 60 + tonicPc
	if tonic > 66 then
		tonic -= 12
	end
	local preset = song.preset or "pop"
	local scalePcs = if minor then MINOR else MAJOR
	if preset == "folk" then
		scalePcs = if minor then { 0, 3, 5, 7, 10 } else { 0, 2, 4, 7, 9 }
	end
	local introBars = song.intro or (if bpm >= 110 then 4 else 2)
	local interBars = if bpm >= 110 then 4 else 2
	local rnd = lcg(song.seed or song.no or 1)
	local form = defaultForm(song)
	local ch = math.clamp(song.ch or 5, 1, #song.lines)
	local cEnd = math.min(ch + 3, #song.lines)

	local lines = {}
	local mel = {} -- in beats first: {b, d, p, li}
	local sects = {}
	local barKinds: { [number]: any } = {} -- bar index -> { kind, j (bar of the section prog) }
	local cursor = introBars * meter -- beats
	table.insert(sects, { b = 0, eb = cursor, kind = "intro" })
	for bar = 0, introBars - 1 do
		barKinds[bar] = { kind = "intro", j = bar }
	end
	-- section position counters (for the progression) per generated section
	local sectPos = 0
	local lastKind = nil
	local lineCache: { [any]: any } = {} -- generated lines: same song line -> same rhythm / pitches
	local prevPitch: number? = nil

	for fi, item in form do
		if item == "간주" or (type(item) == "table" and item.inter) then
			local nb = if type(item) == "table" then (item.bars or interBars) else interBars
			-- explicit songs: an interlude starts on a bar line
			local startB = math.ceil(cursor / meter - 1e-6) * meter
			cursor = startB
			table.insert(sects, { b = cursor, eb = cursor + nb * meter, kind = "inter" })
			for k = 0, nb - 1 do
				barKinds[math.floor(cursor / meter + 0.5) + k] = { kind = "inter", j = k }
			end
			cursor += nb * meter
			lastKind = "inter"
			sectPos = 0
			continue
		end
		local li = tonumber(item)
		local L = li and song.lines[li]
		if not L then
			continue
		end
		local chars = codepoints(L.t)
		local isChorus = (not song.explicit) and li >= ch and li <= cEnd
		local kind = if isChorus then "chorus" else "verse"
		if kind ~= lastKind then
			sectPos = 0
			lastKind = kind
			table.insert(sects, { b = cursor, eb = cursor, kind = kind })
		end
		local line = { text = L.t, chars = chars, part = L.p or "A", sect = kind, src = li, syl = {}, sylT = {}, sylE = {} }
		local lineStart = cursor
		if L.m then
			-- written-out melody
			local k = 0
			local b = cursor
			local sylIdx = {}
			for ci, c in chars do
				if c ~= " " then
					table.insert(sylIdx, ci)
				end
			end
			for tok in string.gmatch(L.m, "%S+") do
				local t = parseToken(tok)
				if not t then
					continue
				end
				if t.rest then
					b += t.d
				else
					k += 1
					local ci = sylIdx[k]
					local nb = b
					for _, nt in t.notes do
						table.insert(mel, { b = nb, d = nt.d, p = nt.p, li = #lines + 1 })
						nb += nt.d
					end
					if ci then
						table.insert(line.syl, { ci = ci, b = b, eb = b + t.d, p = t.notes[1].p, ws = ci == 1 or chars[ci - 1] == " " })
					end
					b += t.d
				end
			end
			line.nTok = k
			line.nSyl = #sylIdx
			cursor = b
		else
			-- generated: 2 bars, composed against the section progression
			local key = li
			local cached = lineCache[key]
			local barIdx = math.floor(cursor / meter + 0.5)
			barKinds[barIdx] = { kind = kind, j = sectPos * 2 }
			barKinds[barIdx + 1] = { kind = kind, j = sectPos * 2 + 1 }
			if not cached then
				local lr = lcg((song.seed or 1) * 131 + li * 17)
				local rh, Lb = rhythm(chars, meter, preset, lr)
				-- the chords this line will sit on (beats relative to the line start)
				local prog = progOf(preset, minor, kind)
				local lc = {
					{ b = 0, off = prog[(sectPos * 2) % #prog + 1].off, q = prog[(sectPos * 2) % #prog + 1].q },
					{ b = meter, off = prog[(sectPos * 2 + 1) % #prog + 1].off, q = prog[(sectPos * 2 + 1) % #prog + 1].q },
				}
				local pairPos = (sectPos % 2) + 1
				local nextItem = form[fi + 1]
				local endsSection = nextItem == nil or nextItem == "간주" or (tonumber(nextItem) ~= nil and ((tonumber(nextItem) :: number) >= ch and (tonumber(nextItem) :: number) <= cEnd) ~= isChorus)
				local pitches = compose(rh, 0, lc, scalePcs, tonic, meter, isChorus, endsSection, pairPos, lr, prevPitch)
				cached = { rh = rh, L = Lb, pitches = pitches }
				lineCache[key] = cached
			end
			for k, s in cached.rh do
				local b = cursor + s.o
				table.insert(line.syl, { ci = s.ci, b = b, eb = b + s.d, p = cached.pitches[k], ws = s.ws })
				table.insert(mel, { b = b, d = s.d, p = cached.pitches[k], li = #lines + 1 })
			end
			prevPitch = cached.pitches[#cached.pitches]
			cursor += cached.L
			sectPos += 1
		end
		line.b0 = if line.syl[1] then line.syl[1].b else lineStart
		line.be = if #line.syl > 0 then line.syl[#line.syl].eb else lineStart
		table.insert(lines, line)
		sects[#sects].eb = cursor
	end
	-- outro: from the next bar line, 2 bars
	local endB = math.ceil(cursor / meter - 1e-6) * meter
	local outroBars = 2
	table.insert(sects, { b = endB, eb = endB + outroBars * meter, kind = "outro" })
	local totalBars = math.floor(endB / meter + 0.5) + outroBars
	for k = 0, outroBars - 1 do
		barKinds[math.floor(endB / meter + 0.5) + k] = { kind = "outro", j = k }
	end

	-- chords (one per bar)
	local chordsB = {}
	if song.explicit then
		table.sort(mel, function(a, b)
			return a.b < b.b
		end)
		local h = harmonize(mel, meter, totalBars, introBars, totalBars - outroBars - 1, minor, tonicPc)
		for bar = 0, totalBars - 1 do
			local kinfo = barKinds[bar]
			local c = h[bar + 1]
			if kinfo and kinfo.kind == "intro" then
				c = if bar == introBars - 1 then { off = 7, q = "M" } else { off = 0, q = if minor then "m" else "M" }
			elseif kinfo and kinfo.kind == "outro" then
				c = { off = 0, q = if minor then "m" else "M" }
			elseif kinfo and kinfo.kind == "inter" then
				local pat = { 0, 5, 7, 0 }
				local off = pat[(kinfo.j % 4) + 1]
				c = { off = off, q = if off == 7 then "M" else triadQ(minor, off) }
			end
			table.insert(chordsB, { b = bar * meter, off = c.off, q = c.q })
		end
	else
		local vprog = progOf(preset, minor, "verse")
		local cprog = progOf(preset, minor, "chorus")
		for bar = 0, totalBars - 1 do
			local kinfo = barKinds[bar] or { kind = "verse", j = 0 }
			local c
			if kinfo.kind == "intro" then
				c = cprog[(kinfo.j + (#cprog - introBars)) % #cprog + 1]
			elseif kinfo.kind == "inter" then
				c = cprog[kinfo.j % #cprog + 1]
			elseif kinfo.kind == "outro" then
				c = { off = 0, q = if minor then "m" else "M" }
			elseif kinfo.kind == "chorus" then
				c = cprog[kinfo.j % #cprog + 1]
			else
				c = vprog[kinfo.j % #vprog + 1]
			end
			table.insert(chordsB, { b = bar * meter, off = c.off, q = c.q })
		end
	end

	-- seconds
	local chart: any = {
		id = song.id,
		bpm = bpm,
		beat = beat,
		meter = meter,
		bar = barS,
		intro = introBars * barS,
		duration = totalBars * barS,
		tonic = tonic,
		minor = minor,
		preset = preset,
		genre = song.genre,
		lines = {},
		mel = {},
		taps = {},
		chords = {},
		sects = {},
	}
	for _, c in chordsB do
		local root = (tonicPc + c.off) % 12
		local bass = 36 + root
		if bass < 40 then
			bass += 12
		end
		table.insert(chart.chords, { t = c.b * beat, d = barS, root = root, off = c.off, q = c.q, bass = bass })
	end
	for _, s in sects do
		if s.eb > s.b then
			table.insert(chart.sects, { t = s.b * beat, e = s.eb * beat, kind = s.kind })
		end
	end
	table.sort(mel, function(a, b)
		return a.b < b.b
	end)
	for _, m in mel do
		table.insert(chart.mel, { t = m.b * beat, d = m.d * beat, p = m.p, li = m.li })
	end
	for li, l in lines do
		local out = { text = l.text, chars = l.chars, part = l.part, sect = l.sect, src = l.src, syl = {}, sylT = {}, sylE = {} }
		for _, s in l.syl do
			local t, e = s.b * beat, s.eb * beat
			table.insert(out.syl, { ci = s.ci, t = t, e = e, p = s.p, ws = s.ws })
			out.sylT[s.ci] = t
			out.sylE[s.ci] = e
		end
		out.t0 = l.b0 * beat
		out.e = l.be * beat
		out.nTok = l.nTok
		out.nSyl = l.nSyl
		chart.lines[li] = out
	end

	-- display schedule (TJ two-line alternate): blocks split at gaps >= 1.5 bars
	local nL = #chart.lines
	local block = 0
	local slotK = 0
	for li = 1, nL do
		local l = chart.lines[li]
		local prev = chart.lines[li - 1]
		local gap = if prev then l.t0 - prev.e else math.huge
		if gap >= 1.5 * barS then
			block += 1
			slotK = 0
			l.dots = true
		else
			l.dots = false
		end
		slotK += 1
		l.block = block
		l.slot = if slotK % 2 == 1 then 1 else 2
		l.k = slotK
	end
	for li = 1, nL do
		local l = chart.lines[li]
		local prev2 = chart.lines[li - 2]
		local first = li
		while first > 1 and chart.lines[first - 1].block == l.block do
			first -= 1
		end
		local lead = math.max(chart.lines[first].t0 - 4 * beat - barS, 0)
		if l.k <= 2 then
			l.show = lead
		else
			l.show = (prev2 :: any).e + 0.2 * beat
		end
		local nxt2 = chart.lines[li + 2]
		local nxt1 = chart.lines[li + 1]
		if nxt2 and nxt2.block == l.block then
			l.hide = l.e + 0.2 * beat
		elseif nxt1 and nxt1.block == l.block then
			-- the last but one line of a block stays until the last line ends
			l.hide = math.max(l.e + 0.2 * beat, nxt1.e + 0.6 * beat)
		else
			l.hide = l.e + 0.8 * beat
		end
		-- voice results: the sung part + the rest after it
		local nextT0 = if nxt1 then nxt1.t0 else chart.duration
		local restEnd = math.min(nextT0 - 0.05, l.e + 2 * beat)
		l.rest = { a = l.e + 0.15, b = restEnd }
		l.due = math.max(l.e + 0.2, restEnd)
	end

	-- rhythm-game notes: word starts, held syllables, line ends, some others; never closer than MIN_GAP
	local last = -math.huge
	for li, l in chart.lines do
		local pmin, pmax = math.huge, -math.huge
		for _, s in l.syl do
			pmin = math.min(pmin, s.p)
			pmax = math.max(pmax, s.p)
		end
		local span = math.max(1, pmax - pmin)
		for k, s in l.syl do
			local want = s.ws or k == #l.syl or (s.e - s.t) >= beat * 0.99 or rnd() < 0.3
			if want and s.t - last >= Chart.MIN_GAP - 1e-6 then
				local lane = math.clamp(math.floor((s.p - pmin) / span * 2.999) + 1, 1, 3)
				table.insert(chart.taps, { t = s.t, lane = lane, li = li, ci = s.ci })
				last = s.t
			end
		end
	end
	local playable = math.max(1, chart.duration - chart.intro)
	local nps = #chart.taps / playable
	chart.stars = if nps < 0.75 then 1 elseif nps < 1.05 then 2 else 3
	return chart
end

function Chart.get(song: any, Songs: any?): any?
	if type(song) == "string" then
		if not Songs then
			return cache[song]
		end
		song = Songs.byId[song]
	end
	if type(song) ~= "table" or not song.id then
		return nil
	end
	local c = cache[song.id]
	if c then
		return c
	end
	c = build(song)
	cache[song.id] = c
	return c
end

-- index of the line being sung at st (or the next one; #lines after the end)
function Chart.lineAt(c: any, st: number): number
	for i, l in c.lines do
		if st < l.e + 0.05 then
			return i
		end
	end
	return #c.lines
end

function Chart.sectAt(c: any, st: number): any?
	for _, s in c.sects do
		if st >= s.t and st < s.e then
			return s
		end
	end
	return nil
end

function Chart.chordAt(c: any, st: number): any?
	local k = math.floor(st / c.bar) + 1
	return c.chords[math.clamp(k, 1, #c.chords)]
end

-- self-check: every song charts sensibly
function Chart.validate(Songs: any): { string }
	local problems = {}
	local nos = {}
	for _, s in Songs.LIST do
		if nos[s.no] then
			table.insert(problems, string.format("%s: duplicate number %d", s.id, s.no))
		end
		nos[s.no] = true
		local ok, c = pcall(Chart.get, s)
		if not ok then
			table.insert(problems, string.format("%s: chart error %s", s.id, tostring(c)))
			continue
		end
		if c.duration < 20 or c.duration > 150 then
			table.insert(problems, string.format("%s: duration %.1f s", s.id, c.duration))
		end
		for li, l in c.lines do
			if l.nTok and l.nSyl and l.nTok ~= l.nSyl then
				table.insert(problems, string.format("%s line %d '%s': %d tokens for %d syllables", s.id, li, l.text, l.nTok, l.nSyl))
			end
			if #l.syl == 0 then
				table.insert(problems, string.format("%s line %d: no syllables", s.id, li))
			end
			for k = 2, #l.syl do
				if l.syl[k].t < l.syl[k - 1].t - 1e-6 then
					table.insert(problems, string.format("%s line %d: syllables out of order", s.id, li))
				end
			end
		end
		for i = 2, #c.taps do
			if c.taps[i].t - c.taps[i - 1].t < Chart.MIN_GAP - 1e-6 then
				table.insert(problems, string.format("%s: taps %d/%d too close", s.id, i - 1, i))
			end
		end
		if #c.taps < #c.lines * 2 then
			table.insert(problems, string.format("%s: only %d taps for %d lines", s.id, #c.taps, #c.lines))
		end
		if s.explicit and math.abs((c.duration / c.bar) - math.floor(c.duration / c.bar + 0.5)) > 1e-6 then
			table.insert(problems, string.format("%s: duration is not whole bars", s.id))
		end
	end
	return problems
end

return Chart
