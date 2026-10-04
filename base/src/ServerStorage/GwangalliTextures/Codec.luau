--!native
--!optimize 2
-- GwangalliTextures/Codec: decoder for the GTX1 texture data modules in this folder (written by
-- tools/assets/textures.py). Pure functions over the buffer library, no Roblox APIs, so the same
-- file also runs under Lune for offline verification (tools/assets/tex_check.luau).
--
--   Codec.base64(s, yield?) -> buffer              (standard alphabet, '=' padding)
--   Codec.decode(tex, pal, blocks, half, yield?) -> (pixels: buffer, width, height)
--       tex    = a data module table (width / height multiples of 4)
--       pal    = buffer of RGBA8 palette entries, blocks = buffer of 6-byte block records
--       half   = true: exact 2x2 box-filtered half-size image (low tier), straight from the blocks
--       pixels = RGBA8 rows top to bottom (EditableImage:WritePixelsBuffer layout)
--   yield(): called every few hundred blocks / characters; the caller decides whether to wait a
--   frame (time slicing). Pass nil to decode in one go.
--
-- GTX1 block record: byte 0 = palette index e0, byte 1 = e1, bytes 2..5 = rows 0..3 of the 4x4 block,
-- 2 bits per pixel (pixel c of a row = bits 2c..2c+1). Pixel = (pal[e0]*(3-w) + pal[e1]*w + 1) // 3.
-- Half size: s = sum of the 4 weights of a 2x2 quad (0..12), pixel = (pal[e0]*(12-s) + pal[e1]*s + 6) // 12.

local Codec = {}

local B64: { [number]: number } = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do
		B64[string.byte(alphabet, i)] = i - 1
	end
end

function Codec.base64(s: string, yield: (() -> ())?): buffer
	local n = #s
	assert(n % 4 == 0, "base64 length must be a multiple of 4")
	local pad = 0
	if n > 0 and string.byte(s, n) == 61 then
		pad += 1
		if string.byte(s, n - 1) == 61 then
			pad += 1
		end
	end
	local outLen = (n // 4) * 3 - pad
	local out = buffer.create(outLen)
	local full = if pad > 0 then n - 4 else n -- last quad handled separately when padded
	local o = 0
	local i = 1
	local CHUNK = 2048
	while i <= full do
		local stop = math.min(full, i + CHUNK - 1)
		while i <= stop do
			local a, b, c, d = string.byte(s, i, i + 3)
			local v = B64[a] * 262144 + B64[b] * 4096 + B64[c] * 64 + B64[d]
			buffer.writeu8(out, o, v // 65536)
			buffer.writeu8(out, o + 1, (v // 256) % 256)
			buffer.writeu8(out, o + 2, v % 256)
			o += 3
			i += 4
		end
		if yield then
			yield()
		end
	end
	if pad > 0 then
		local a, b, c = string.byte(s, n - 3, n - 1)
		local v = B64[a] * 262144 + B64[b] * 4096 + (if pad == 1 then B64[c] * 64 else 0)
		buffer.writeu8(out, o, v // 65536)
		if pad == 1 then
			buffer.writeu8(out, o + 1, (v // 256) % 256)
		end
	end
	return out
end

function Codec.decode(tex: any, pal: buffer, blocks: buffer, half: boolean, yield: (() -> ())?): (buffer, number, number)
	local w, h = tex.width, tex.height
	assert(w % 4 == 0 and h % 4 == 0, "GTX1 size must be a multiple of 4")
	local nbx, nby = w // 4, h // 4
	assert(buffer.len(blocks) >= nbx * nby * 6, "GTX1 block data too short")
	local np = buffer.len(pal) // 4
	assert(np >= 1, "GTX1 palette empty")
	-- palette channels, 1-based
	local PR, PG, PB, PA = table.create(np, 0), table.create(np, 0), table.create(np, 0), table.create(np, 0)
	for i = 0, np - 1 do
		PR[i + 1] = buffer.readu8(pal, i * 4)
		PG[i + 1] = buffer.readu8(pal, i * 4 + 1)
		PB[i + 1] = buffer.readu8(pal, i * 4 + 2)
		PA[i + 1] = buffer.readu8(pal, i * 4 + 3)
	end
	local ow = if half then w // 2 else w
	local oh = if half then h // 2 else h
	local out = buffer.create(ow * oh * 4)
	local stride = ow * 4
	local CC = table.create(4, 0) -- the 4 block colours as packed RGBA8 (little endian)
	local bo = 0
	for by = 0, nby - 1 do
		for bx = 0, nbx - 1 do
			local e0 = buffer.readu8(blocks, bo) + 1
			local e1 = buffer.readu8(blocks, bo + 1) + 1
			if e0 > np then
				e0 = 1
			end
			if e1 > np then
				e1 = 1
			end
			local r0, g0, b0, a0 = PR[e0], PG[e0], PB[e0], PA[e0]
			local r1, g1, b1, a1 = PR[e1], PG[e1], PB[e1], PA[e1]
			if not half then
				CC[1] = r0 + g0 * 256 + b0 * 65536 + a0 * 16777216
				CC[2] = (2 * r0 + r1 + 1) // 3 + ((2 * g0 + g1 + 1) // 3) * 256 + ((2 * b0 + b1 + 1) // 3) * 65536 + ((2 * a0 + a1 + 1) // 3) * 16777216
				CC[3] = (r0 + 2 * r1 + 1) // 3 + ((g0 + 2 * g1 + 1) // 3) * 256 + ((b0 + 2 * b1 + 1) // 3) * 65536 + ((a0 + 2 * a1 + 1) // 3) * 16777216
				CC[4] = r1 + g1 * 256 + b1 * 65536 + a1 * 16777216
				local o = (by * 4) * stride + bx * 16
				for r = 0, 3 do
					local byte = buffer.readu8(blocks, bo + 2 + r)
					buffer.writeu32(out, o, CC[byte % 4 + 1])
					buffer.writeu32(out, o + 4, CC[(byte // 4) % 4 + 1])
					buffer.writeu32(out, o + 8, CC[(byte // 16) % 4 + 1])
					buffer.writeu32(out, o + 12, CC[byte // 64 + 1])
					o += stride
				end
			else
				local o = (by * 2) * stride + bx * 8
				for oy = 0, 1 do
					local ra = buffer.readu8(blocks, bo + 2 + oy * 2)
					local rb = buffer.readu8(blocks, bo + 3 + oy * 2)
					-- quad weight sums (0..12) for the left and right 2x2 quads of this row pair
					local sl = ra % 4 + (ra // 4) % 4 + rb % 4 + (rb // 4) % 4
					local sr = (ra // 16) % 4 + ra // 64 + (rb // 16) % 4 + rb // 64
					local il, ir = 12 - sl, 12 - sr
					buffer.writeu32(out, o,
						(r0 * il + r1 * sl + 6) // 12
						+ ((g0 * il + g1 * sl + 6) // 12) * 256
						+ ((b0 * il + b1 * sl + 6) // 12) * 65536
						+ ((a0 * il + a1 * sl + 6) // 12) * 16777216)
					buffer.writeu32(out, o + 4,
						(r0 * ir + r1 * sr + 6) // 12
						+ ((g0 * ir + g1 * sr + 6) // 12) * 256
						+ ((b0 * ir + b1 * sr + 6) // 12) * 65536
						+ ((a0 * ir + a1 * sr + 6) // 12) * 16777216)
					o += stride
				end
			end
			bo += 6
			if yield and bx % 32 == 31 then
				yield()
			end
		end
	end
	return out, ow, oh
end

return Codec
