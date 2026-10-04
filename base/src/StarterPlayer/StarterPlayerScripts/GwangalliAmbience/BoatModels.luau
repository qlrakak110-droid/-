-- GwangalliAmbience/BoatModels (client): part-built boats for the cruising traffic on the bay.
-- Local frame: origin on the waterline at mid-hull, LookVector (-Z) = bow, +Y up, +X starboard.
-- Each builder returns a record:
--   parts   { BasePart }       every part (moved together with one BulkMoveTo)
--   offsets { CFrame }         part CFrame relative to the boat origin
--   lights  { { part, day: Color3, night: Color3 } }  navigation / deck / fishing lamps (Neon at night)
--   leds    { BasePart }       colour-cycling LED strips (tour boat, night)
--   wakes   { { part, base: number } }  foam parts whose transparency follows the speed (base = at full speed)
--   paddle  { part, offset, side } (SUP / kayak) animated strokes
--   length  hull length (studs)
-- Scale: 1 stud = 0.3 m (fishing boat ~12 m, yacht ~10 m, tour boat ~45 m, jet boat ~4 m).

local M = {}

local rgb = Color3.fromRGB
local SP = Enum.Material.SmoothPlastic
local FOAM = rgb(240, 245, 244)

type Rec = {
	parts: { BasePart },
	offsets: { CFrame },
	lights: { any },
	leds: { BasePart },
	wakes: { any },
	paddle: any?,
	length: number,
}

local function newRec(len: number): Rec
	return { parts = {}, offsets = {}, lights = {}, leds = {}, wakes = {}, paddle = nil, length = len }
end

function M.new(Env: any)
	local B = {}

	local function add(rec: Rec, parent: Instance, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, tr: number?, name: string?, shape: string?): BasePart
		local p = Env.part(parent, size, color, material or SP, tr or 0, name or "BoatPart", shape)
		table.insert(rec.parts, p)
		table.insert(rec.offsets, offset)
		return p
	end
	local function light(rec: Rec, parent: Instance, d: number, offset: CFrame, night: Color3, name: string)
		local p = add(rec, parent, Vector3.new(d, d, d), offset, rgb(200, 200, 196), SP, 0, name, "Ball")
		table.insert(rec.lights, { part = p, day = rgb(200, 200, 196), night = night })
		return p
	end
	-- hull box + flipped bow wedge (flat deck, keel rising to the stem)
	local function hull(rec: Rec, parent: Instance, W: number, H: number, L: number, bowL: number, draft: number, color: Color3)
		local yc = -draft + H / 2
		add(rec, parent, Vector3.new(W, H, L), CFrame.new(0, yc, 0), color, SP, 0, "Hull")
		add(rec, parent, Vector3.new(W, H, bowL), CFrame.new(0, yc, -(L + bowL) / 2 + 0.02) * CFrame.Angles(0, 0, math.pi), color, SP, 0, "Bow", "Wedge")
		return -draft + H -- deck height
	end
	-- stern V wake (Kelvin angle ~19.5 deg), prop wash and bow wave; `s` scales them
	local function wakes(rec: Rec, parent: Instance, W: number, L: number, bowL: number, s: number)
		local a = math.rad(19.5)
		local armL = 26 * s + L * 0.7
		for _, sgn in { -1, 1 } do
			local start = Vector3.new(sgn * W * 0.45, 0.13, L / 2)
			local dir = Vector3.new(sgn * math.sin(a), 0, math.cos(a))
			local c = start + dir * (armL / 2)
			local p = add(rec, parent, Vector3.new(2.2 * s + 1.2, 0.05, armL), CFrame.new(c) * CFrame.Angles(0, sgn * a, 0), FOAM, SP, 0.6, "WakeArm")
			table.insert(rec.wakes, { part = p, base = 0.6 })
		end
		local wash = add(rec, parent, Vector3.new(W * 0.8, 0.05, 18 * s + L * 0.35), CFrame.new(0, 0.12, L / 2 + 9 * s + L * 0.17), FOAM, SP, 0.45, "PropWash")
		table.insert(rec.wakes, { part = wash, base = 0.45 })
		local bow = add(rec, parent, Vector3.new(W * 1.15, 0.05, 3.5 * s + 1.5), CFrame.new(0, 0.12, -(L / 2 + bowL) + 1), FOAM, SP, 0.5, "BowWave")
		table.insert(rec.wakes, { part = bow, base = 0.5 })
	end

	-- 연안어선: white hull, blue sheer stripe and roof, wheelhouse aft, mast with a boom of fishing lamps.
	function B.fishing(parent: Instance, hullColor: Color3?, stripe: Color3?): Rec
		local rec = newRec(37)
		local W, H, L, bowL, draft = 9, 4.2, 28, 9, 1.8
		local deck = hull(rec, parent, W, H, L, bowL, draft, hullColor or rgb(236, 238, 234))
		local st = stripe or rgb(28, 70, 150)
		for _, sx in { -1, 1 } do
			add(rec, parent, Vector3.new(0.1, 0.7, L + bowL * 0.6), CFrame.new(sx * (W / 2 + 0.05), deck - 0.9, -bowL * 0.3), st, SP, 0, "Stripe")
		end
		add(rec, parent, Vector3.new(W - 0.6, 0.25, L + 2), CFrame.new(0, deck + 0.1, -1), rgb(150, 150, 146), SP, 0, "Deck")
		add(rec, parent, Vector3.new(6.2, 5, 7), CFrame.new(0, deck + 2.6, 5), rgb(240, 240, 236), SP, 0, "Wheelhouse")
		local win = add(rec, parent, Vector3.new(6.3, 1.3, 7.1), CFrame.new(0, deck + 3.7, 5), rgb(34, 42, 50), SP, 0, "Windows")
		win.Reflectance = 0.25
		add(rec, parent, Vector3.new(7, 0.45, 8), CFrame.new(0, deck + 5.3, 5), st, SP, 0, "Roof")
		add(rec, parent, Vector3.new(0.4, 9, 0.4), CFrame.new(0, deck + 9.9, 3.5), rgb(150, 154, 156), Enum.Material.Metal, 0, "Mast")
		add(rec, parent, Vector3.new(0.18, 0.18, 19), CFrame.new(0, deck + 11.5, -6), rgb(60, 62, 64), Enum.Material.Metal, 0, "LampBoom")
		-- 집어등 (fishing lamps): two rows under the boom, bright at night
		for _, sx in { -0.5, 0.5 } do
			local lamp = add(rec, parent, Vector3.new(0.5, 0.5, 15), CFrame.new(sx, deck + 10.9, -6.5), rgb(210, 212, 206), SP, 0, "FishingLamps")
			table.insert(rec.lights, { part = lamp, day = rgb(210, 212, 206), night = rgb(214, 255, 226) })
		end
		add(rec, parent, Vector3.new(0.08, 1.2, 2), CFrame.new(0, deck + 13.6, 4.6), rgb(210, 40, 40), Enum.Material.Fabric, 0, "Flag")
		light(rec, parent, 0.6, CFrame.new(-3.2, deck + 4.4, 1.4), rgb(255, 40, 30), "PortLight")
		light(rec, parent, 0.6, CFrame.new(3.2, deck + 4.4, 1.4), rgb(40, 255, 90), "StarboardLight")
		light(rec, parent, 0.7, CFrame.new(0, deck + 14.6, 3.5), rgb(255, 250, 235), "MastheadLight")
		wakes(rec, parent, W, L, bowL, 1)
		return rec
	end

	-- 요트 (sailing): white hull, teak deck, cabin, tall mast, main and jib. `heel` is applied by Boats.
	function B.yacht(parent: Instance): Rec
		local rec = newRec(28)
		local W, H, L, bowL, draft = 7, 2.6, 20, 8, 1.2
		local deck = hull(rec, parent, W, H, L, bowL, draft, rgb(244, 244, 242))
		add(rec, parent, Vector3.new(0.1, 0.35, L + bowL * 0.5), CFrame.new(-(W / 2 + 0.05), deck - 0.5, -bowL * 0.25), rgb(20, 40, 90), SP, 0, "Stripe")
		add(rec, parent, Vector3.new(0.1, 0.35, L + bowL * 0.5), CFrame.new(W / 2 + 0.05, deck - 0.5, -bowL * 0.25), rgb(20, 40, 90), SP, 0, "Stripe")
		add(rec, parent, Vector3.new(W - 0.5, 0.2, L), CFrame.new(0, deck + 0.08, 0), rgb(176, 136, 96), Enum.Material.WoodPlanks, 0, "Deck")
		add(rec, parent, Vector3.new(4.4, 1.6, 8), CFrame.new(0, deck + 0.9, 1.5), rgb(246, 246, 244), SP, 0, "Cabin")
		local cw = add(rec, parent, Vector3.new(4.5, 0.5, 6), CFrame.new(0, deck + 1.1, 1.5), rgb(30, 38, 46), SP, 0, "CabinWindows")
		cw.Reflectance = 0.3
		add(rec, parent, Vector3.new(0.45, 34, 0.45), CFrame.new(0, deck + 17, -2.5), rgb(200, 204, 206), Enum.Material.Metal, 0, "Mast")
		add(rec, parent, Vector3.new(0.3, 0.3, 11), CFrame.new(0, deck + 4.2, 3), rgb(190, 194, 196), Enum.Material.Metal, 0, "Boom")
		-- mainsail: luff on the mast (tall edge forward), foot on the boom
		add(rec, parent, Vector3.new(0.12, 28, 10.5), CFrame.new(0, deck + 18.4, 2.8) * CFrame.Angles(0, math.pi, 0), rgb(246, 246, 240), Enum.Material.Fabric, 0, "Mainsail", "Wedge")
		-- jib: tall edge at the mast, sloping down to the bow
		add(rec, parent, Vector3.new(0.1, 24, 9.5), CFrame.new(0, deck + 12.2, -7.4), rgb(236, 236, 230), Enum.Material.Fabric, 0, "Jib", "Wedge")
		light(rec, parent, 0.55, CFrame.new(0, deck + 34.4, -2.5), rgb(255, 250, 235), "MastheadLight")
		light(rec, parent, 0.45, CFrame.new(-2.9, deck + 0.4, -9), rgb(255, 40, 30), "PortLight")
		light(rec, parent, 0.45, CFrame.new(2.9, deck + 0.4, -9), rgb(40, 255, 90), "StarboardLight")
		wakes(rec, parent, W, L, bowL, 0.55)
		return rec
	end

	-- 유람선 (harbour cruise boat): two enclosed decks with window bands, wheelhouse, funnel, and
	-- LED strips along the hull and the roof edge that colour-cycle at night.
	function B.tour(parent: Instance): Rec
		local rec = newRec(140)
		local W, H, L, bowL, draft = 26, 8, 110, 30, 3
		local deck = hull(rec, parent, W, H, L, bowL, draft, rgb(244, 246, 246))
		add(rec, parent, Vector3.new(W + 0.1, 1.2, L + bowL * 0.4), CFrame.new(0, 0.2, -bowL * 0.2), rgb(26, 50, 110), SP, 0, "Boottop")
		add(rec, parent, Vector3.new(22, 8, 92), CFrame.new(0, deck + 4, 2), rgb(242, 244, 244), SP, 0, "MainCabin")
		local w1 = add(rec, parent, Vector3.new(22.2, 3.2, 88), CFrame.new(0, deck + 4.6, 2), rgb(22, 38, 70), SP, 0, "MainWindows")
		w1.Reflectance = 0.35
		add(rec, parent, Vector3.new(18, 6, 54), CFrame.new(0, deck + 11, 12), rgb(242, 244, 244), SP, 0, "UpperCabin")
		local w2 = add(rec, parent, Vector3.new(18.2, 2.6, 50), CFrame.new(0, deck + 11.4, 12), rgb(22, 38, 70), SP, 0, "UpperWindows")
		w2.Reflectance = 0.35
		add(rec, parent, Vector3.new(19, 0.6, 56), CFrame.new(0, deck + 14.3, 12), rgb(230, 232, 232), SP, 0, "Roof")
		add(rec, parent, Vector3.new(14, 4.5, 9), CFrame.new(0, deck + 10.2, -20), rgb(244, 246, 246), SP, 0, "Wheelhouse")
		local w3 = add(rec, parent, Vector3.new(14.2, 1.6, 9.2), CFrame.new(0, deck + 11, -20), rgb(22, 38, 70), SP, 0, "BridgeWindows")
		w3.Reflectance = 0.35
		add(rec, parent, Vector3.new(6, 6, 9), CFrame.new(0, deck + 17.5, 30), rgb(28, 62, 140), SP, 0, "Funnel")
		add(rec, parent, Vector3.new(0.8, 14, 0.8), CFrame.new(0, deck + 19.5, -18), rgb(210, 212, 214), Enum.Material.Metal, 0, "Mast")
		add(rec, parent, Vector3.new(0.1, 2, 3.2), CFrame.new(0, deck + 25, -16.4), rgb(200, 30, 40), Enum.Material.Fabric, 0, "Flag")
		for _, sx in { -1, 1 } do
			local led = add(rec, parent, Vector3.new(0.3, 0.5, L + bowL * 0.5), CFrame.new(sx * (W / 2 + 0.16), deck - 0.8, -bowL * 0.25), rgb(200, 204, 206), SP, 0, "HullLED")
			table.insert(rec.leds, led)
		end
		local roofLed = add(rec, parent, Vector3.new(19.4, 0.3, 0.3), CFrame.new(0, deck + 14.7, -16), rgb(200, 204, 206), SP, 0, "RoofLED")
		table.insert(rec.leds, roofLed)
		local deckLed = add(rec, parent, Vector3.new(22.4, 0.3, 0.3), CFrame.new(0, deck + 8.1, -44), rgb(200, 204, 206), SP, 0, "DeckLED")
		table.insert(rec.leds, deckLed)
		light(rec, parent, 1.1, CFrame.new(0, deck + 26.6, -18), rgb(255, 250, 235), "MastheadLight")
		light(rec, parent, 0.9, CFrame.new(-7.2, deck + 11, -24.6), rgb(255, 40, 30), "PortLight")
		light(rec, parent, 0.9, CFrame.new(7.2, deck + 11, -24.6), rgb(40, 255, 90), "StarboardLight")
		wakes(rec, parent, W, L, bowL, 2.2)
		return rec
	end

	-- 제트보트 (leports): small, fast, big rooster tail.
	function B.jet(parent: Instance): Rec
		local rec = newRec(16)
		local W, H, L, bowL, draft = 5.6, 2.2, 11, 5, 0.8
		local deck = hull(rec, parent, W, H, L, bowL, draft, rgb(240, 240, 238))
		for _, sx in { -1, 1 } do
			add(rec, parent, Vector3.new(0.08, 0.5, L), CFrame.new(sx * (W / 2 + 0.04), deck - 0.5, 0), rgb(214, 40, 40), SP, 0, "Stripe")
		end
		add(rec, parent, Vector3.new(3.6, 1.6, 1.8), CFrame.new(0, deck + 0.8, -1.2), rgb(40, 42, 46), SP, 0, "Console")
		add(rec, parent, Vector3.new(4.2, 1.1, 5), CFrame.new(0, deck + 0.55, 2.4), rgb(214, 40, 40), Enum.Material.Fabric, 0, "Seats")
		-- rooster tail (spray plume behind the jet)
		local plume = add(rec, parent, Vector3.new(3.2, 3.6, 14), CFrame.new(0, 1.6, L / 2 + 7.2) * CFrame.Angles(0, math.pi, 0), FOAM, SP, 0.55, "RoosterTail", "Wedge")
		table.insert(rec.wakes, { part = plume, base = 0.55 })
		wakes(rec, parent, W, L, bowL, 0.8)
		return rec
	end

	local SKIN = { rgb(236, 196, 164), rgb(224, 180, 146), rgb(206, 160, 124) }
	local TOPS = { rgb(30, 30, 34), rgb(20, 90, 170), rgb(230, 70, 60), rgb(250, 250, 246), rgb(0, 150, 150) }
	-- SUP paddler standing on a board, paddle strokes alternate sides.
	function B.sup(parent: Instance, seed: number): Rec
		local rec = newRec(10.5)
		local r = Random.new(seed)
		local boardC = ({ rgb(250, 250, 246), rgb(0, 164, 214), rgb(255, 200, 40), rgb(255, 120, 150) })[r:NextInteger(1, 4)]
		add(rec, parent, Vector3.new(2.6, 0.36, 10.5), CFrame.new(0, 0.1, 0), boardC, SP, 0, "Board", "Ellipsoid")
		local skin = SKIN[r:NextInteger(1, #SKIN)]
		local top = TOPS[r:NextInteger(1, #TOPS)]
		add(rec, parent, Vector3.new(1.3, 2.7, 0.7), CFrame.new(0, 1.65, 0.2), rgb(30, 32, 40), Enum.Material.Fabric, 0, "Legs")
		add(rec, parent, Vector3.new(1.7, 2.2, 0.9), CFrame.new(0, 4.1, 0.1) * CFrame.Angles(-0.15, 0, 0), top, Enum.Material.Fabric, 0, "Torso")
		add(rec, parent, Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 5.8, 0), skin, SP, 0, "Head", "Ball")
		local paddle = add(rec, parent, Vector3.new(0.18, 6.8, 0.18), CFrame.new(1.2, 3.2, -0.8) * CFrame.Angles(-0.35, 0, 0.12), rgb(30, 30, 32), SP, 0, "Paddle")
		rec.paddle = { part = paddle, index = #rec.parts, kind = "sup" }
		return rec
	end

	-- Sit-on-top kayak, double-bladed paddle swinging side to side.
	function B.kayak(parent: Instance, seed: number): Rec
		local rec = newRec(12)
		local r = Random.new(seed)
		add(rec, parent, Vector3.new(2.3, 1.1, 12), CFrame.new(0, 0.2, 0), ({ rgb(255, 200, 30), rgb(220, 50, 40), rgb(0, 150, 200) })[r:NextInteger(1, 3)], SP, 0, "Hull", "Ellipsoid")
		add(rec, parent, Vector3.new(1.6, 2, 0.9), CFrame.new(0, 1.7, 0.6), TOPS[r:NextInteger(1, #TOPS)], Enum.Material.Fabric, 0, "Torso")
		add(rec, parent, Vector3.new(1, 1, 1), CFrame.new(0, 3.2, 0.6), SKIN[r:NextInteger(1, #SKIN)], SP, 0, "Head", "Ball")
		add(rec, parent, Vector3.new(1.7, 1.2, 1.9), CFrame.new(0, 1.1, 0.7), rgb(240, 110, 30), Enum.Material.Fabric, 0, "LifeVest")
		local paddle = add(rec, parent, Vector3.new(7.6, 0.16, 0.5), CFrame.new(0, 2.2, -0.3), rgb(40, 40, 44), SP, 0, "Paddle")
		rec.paddle = { part = paddle, index = #rec.parts, kind = "kayak" }
		return rec
	end

	return B
end

return M
