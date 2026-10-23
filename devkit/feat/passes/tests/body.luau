-- offline logic tests for GwangalliPasses (mock runtime)
local fails, passes = 0, 0
local function check(name, cond, extra)
	if cond then
		passes += 1
	else
		fails += 1
		print("FAIL", name, extra ~= nil and tostring(extra) or "")
	end
end

local P = __req("P")
local Plates = P.mod("Plates")
local Neon = P.mod("Neon")
local Cars = P.mod("Cars")
local KoFx = P.mod("KoFx")
local Lines = P.Lines
local player = R.player

-- shared ------------------------------------------------------------------------------------------
check("key alias garage", P.key("garage") == "PremiumGarage")
check("key alias QOL", P.key("QOL") == "Convenience")
check("key full", P.key("Flex") == "Flex")
check("key bad", P.key("vip") == nil and P.key(5) == nil)
check("available Id0 live", P.available("garage") == false)
check("won", P.won(1234567) == "1,234,567원" and P.won(0) == "0원" and P.won(-5000) == "-5,000원", P.won(1234567))
check("dur", Lines.dur(150) == "2분 30초" and Lines.dur(60) == "1분" and Lines.dur(45) == "45초")
check("lines fmt", Lines.t("summon_cooldown", 3) == "잠시 후 다시 불러 주세요 (3초)")
check("lines unknown", Lines.t("nope") == "nope")
check("lines repair %%", string.find(Lines.t("repair_done", "12가 3456", "1,000원"), "100%", 1, true) ~= nil)

-- plates ------------------------------------------------------------------------------------------
local function v(t)
	local ok, code, clean = Plates.validate(t)
	return ok, code, clean
end
check("plate korean ok", (v("12가 3456")))
check("plate 3-digit", (v("123가 4567")))
check("plate free", (v("광안 1004")))
check("plate ascii upper", select(3, v("gw 7777")) == "GW 7777")
check("plate spaces collapse", select(3, v("  부산   VIP  ")) == "부산 VIP")
check("plate too short", select(2, v("가")) == "len")
check("plate too long", select(2, v("123456789가")) == "len")
check("plate emoji", select(2, v("광안😀1")) == "chars")
check("plate markup", select(2, v("<b>x</b>")) == "chars")
check("plate empty", select(2, v("   ")) == "empty")
check("plate digits", select(2, v("12345678")) == "digits")
check("plate dash", (v("GW-777")))
check("plate jamo refused", select(2, v("ㅋㅋㅋ")) == "chars")
check("plate korean helper", Plates.korean("12가3456") == "12가 3456" and Plates.korean("123가4567") == "123가 4567")
check("plate korean helper free", Plates.korean("광안1004") == "광안1004")
check("plate claim spacing", Plates.claimKey("12가 3456") == Plates.claimKey("12가3456"))
check("plate claim case", Plates.claimKey("gw 7") == Plates.claimKey("GW7"))
check("plate claim distinct", Plates.claimKey("12가 3456") ~= Plates.claimKey("12나 3456"))
check("plate claim len", #Plates.claimKey("가나다라마바사아") <= 50)
for i = 1, 30 do
	local r = Plates.random(Random.new(i))
	check("plate random valid " .. r, (v(r)))
end
check("plate style fallback", Plates.style("nope").id == P.Config.PLATE.DEFAULT_STYLE)

-- neon --------------------------------------------------------------------------------------------
local pal = Neon.get("bridge")
local rich = Neon.rich("A&B", pal, true)
check("neon rich escape", string.find(rich, "&amp;", 1, true) ~= nil and string.sub(rich, 1, 3) == "<b>", rich)
local n = 0
for _ in string.gmatch(Neon.rich("철수야", pal), "<font") do
	n += 1
end
check("neon rich per char", n == 3)
check("neon sample ends", Neon.sample(pal, 0) == pal.colors[1] and Neon.sample(pal, 1) == pal.colors[#pal.colors])
for _, p in Neon.LIST do
	local ok = pcall(Neon.sequence, p)
	check("neon sequence " .. p.id, ok)
end

-- cars / fx ---------------------------------------------------------------------------------------
check("car id round trip", Cars.keyOfId(Cars.carId("hyper")) == "hyper" and Cars.keyOfId("gwp_x") == nil and Cars.keyOfId("abc") == nil)
for _, car in Cars.LIST do
	check("car kind not job " .. car.key, car.kind ~= "police" and car.kind ~= "taxi" and car.kind ~= "ambulance")
	local plate = Cars.defaultPlate(123456789, car.key)
	check("car plate bytes " .. car.key, #plate <= 24, plate)
	check("car plate stable " .. car.key, plate == Cars.defaultPlate(123456789, car.key))
	check("car paint " .. car.key, Cars.PAINT_BY_ID[car.paint] ~= nil)
	check("car speed sane " .. car.key, car.spec.topKmh <= 220)
end
local VS = { Specs = { luxury = { label = "L", topKmh = 165, mass = 160, accel = 25 }, suv = { label = "S", topKmh = 128, E = 0.3 }, sedan = { topKmh = 135 } }, Drivable = { sedan = true } }
Cars.install(VS, true)
check("install specs", VS.Specs.gw_hyper and VS.Specs.gw_hyper.topKmh == 210 and VS.Specs.gw_hyper.mass == 168)
check("install keeps base", VS.Specs.gw_vip.mass == 160 and VS.Specs.gw_vip.topKmh == 178)
check("install drivable", VS.Drivable.gw_offroad == true and VS.Drivable.sedan == true)
check("install base untouched", VS.Specs.luxury.topKmh == 165)
local VS2 = { Specs = { luxury = { topKmh = 165 } }, Drivable = {} }
Cars.install(VS2, false)
check("install client not drivable", VS2.Drivable.gw_hyper == nil and VS2.Specs.gw_hyper ~= nil)
for _, d in KoFx.LIST do
	check("fx emote " .. d.id, KoFx.EMOTE_FOR[d.id] ~= nil)
	for _, s in d.sounds do
		check("fx sound " .. d.id .. "." .. s, KoFx.SND[s] ~= nil)
	end
	check("fx no gore word " .. d.id, not string.find(d.name .. d.desc, "처형", 1, true) and not string.find(d.name .. d.desc, "피", 1, true))
end

-- server Util ---------------------------------------------------------------------------------------
local Util = __req("Util")
local b = Util.bucket(3, 1)
check("bucket burst", b:take("x") and b:take("x") and b:take("x") and not b:take("x"))
check("bucket other key", b:take("y"))
local T = { f = function(a)
	return a + 1
end }
local orig1 = Util.wrap(T, "f", function(o)
	return function(a)
		return o(a) * 10
	end
end)
check("wrap returns orig", type(orig1) == "function")
check("wrap calls through", T.f(1) == 20)
local orig2 = Util.wrap(T, "f", function(o)
	return function(a)
		return o(a) * 100
	end
end)
check("wrap idempotent", orig2 == nil and T.f(1) == 20)
check("wrap missing", Util.wrap(T, "nope", function(o)
	return o
end) == nil)
check("isPlayer", Util.isPlayer(player) and not Util.isPlayer({}) and not Util.isPlayer(workspace))
check("shortString", Util.shortString("abc", 5) == "abc" and Util.shortString("abcdef", 5) == nil and Util.shortString(5, 5) == nil)

-- Waits: jail / koHelp wrappers ------------------------------------------------------------------------
local sent = {}
local owns = { [player] = true }
local ctx = {
	P = P,
	Config = P.Config,
	Util = Util,
	Net = { send = function(_p, payload)
		table.insert(sent, payload)
	end },
	Ownership = { owns = function(p, k)
		return owns[p] == true and k == "Convenience"
	end },
}
local A = { KO = { SELF_HELP_AFTER = 20, EMS_WAIT = 95, EMS_TOTAL = 150 } }
local Waits = __req("Waits")
Waits.bind(ctx, A)
local seen = nil
local jw = Waits.jailWrapper(function(_p, _s, ep, _i)
	seen = ep.seconds
	return "began"
end)
local ep = { seconds = 120, fine = 1 }
check("jail returns orig result", jw(player, {}, ep, {}) == "began")
check("jail halved", seen == 60, seen)
check("jail original episode untouched", ep.seconds == 120)
check("jail toast", #sent == 1 and sent[1].kind == "qol" and sent[1].after == 60, sent[1] and sent[1].text)
jw(player, {}, { seconds = 20 }, {})
check("jail min 15", seen == 15, seen)
jw(player, {}, { seconds = 12 }, {})
check("jail never longer", seen == 12, seen)
jw(player, {}, { seconds = 31 }, {})
check("jail rounds up", seen == 16, seen)
owns[player] = false
jw(player, {}, { seconds = 120 }, {})
check("jail non-owner", seen == 120)
jw({}, {}, { seconds = 120 }, {})
check("jail bad player passthrough", seen == 120)
owns[player] = true

local calls = 0
local function origHelp(victim)
	calls += 1
	-- KOSystem: refuses before SELF_HELP_AFTER (rec.t0 = down time)
	local rec = Waits.koRecord(victim)
	return os.clock() - rec.t0 >= A.KO.SELF_HELP_AFTER
end
local kw = Waits.koHelpWrapper(origHelp)
Waits.markDown(player)
check("ko early refused", kw(player) == false and A.KO.SELF_HELP_AFTER == 20)
Waits.koRecord(player).t0 = os.clock() - 11
check("ko owner after half", kw(player) == true)
check("ko constant restored", A.KO.SELF_HELP_AFTER == 20)
owns[player] = false
check("ko non-owner at 11s refused", kw(player) == false)
owns[player] = true
local kwErr = Waits.koHelpWrapper(function()
	error("boom")
end)
check("ko error safe", kwErr(player) == false and A.KO.SELF_HELP_AFTER == 20)

-- Net: payload copy + rate limits -----------------------------------------------------------------------
local Net = __req("Net")
Net.start(ctx)
local got = nil
Net.on("echo", 0, function(_p, payload)
	got = payload
	return { ok = true }
end)
Net.on("slow", 5, function()
	return { ok = true }
end)
Net.publish({ garage = true })
local folder = game:GetService("ReplicatedStorage"):FindFirstChild(P.REMOTES)
check("net folder", folder ~= nil and folder:FindFirstChild(P.REQUEST) ~= nil and folder:FindFirstChild(P.EVENT) ~= nil)
local rf = folder:FindFirstChild(P.REQUEST)
local invoke = rf.OnServerInvoke
local r1 = invoke(player, "echo", { a = "x", nested = { 1 }, long = string.rep("z", 300), num = 5, bad = 0 / 0, [1] = "arr", fn = print })
check("net ok", r1.ok == true)
check("net copy fields", got.a == "x" and got.num == 5 and got.nested == nil and got.long == nil and got.bad == nil and got[1] == nil and got.fn == nil)
check("net unknown op", invoke(player, "nope", nil).code == "bad")
check("net bad op type", invoke(player, 5, nil).code == "bad")
check("net cooldown", invoke(player, "slow", nil).ok == true and invoke(player, "slow", nil).code == "cooldown")
local limited = false
for _ = 1, 20 do
	if invoke(player, "echo", nil).code == "rate" then
		limited = true
	end
end
check("net rate limit", limited)

-- Plate.set: validation -> filter -> claim -----------------------------------------------------------
local TextService = game:GetService("TextService")
local filterMode = "same"
TextService.FilterStringAsync = function(_self, text, _uid, _ctx)
	if filterMode == "error" then
		error("filter down")
	end
	return { GetNonChatStringForBroadcastAsync = function()
		return if filterMode == "hash" then string.rep("#", utf8.len(text) or 1) else text
	end }
end
local prof = { plate = { text = nil, style = "classic" } }
local claimed = {}
local pctx = {
	P = P,
	Config = P.Config,
	Util = Util,
	Ownership = { owns = function(_p, k)
		return k == "Flex"
	end, onChanged = function() end },
	Data = {
		get = function()
			return prof
		end,
		update = function(_p, fn)
			fn(prof)
		end,
		onLoaded = function() end,
		claimPlate = function(_p, clean)
			if claimed[Plates.claimKey(clean)] == "other" then
				return false, "taken"
			end
			claimed[Plates.claimKey(clean)] = "me"
			return true
		end,
		releasePlate = function(_p, clean)
			claimed[Plates.claimKey(clean)] = nil
		end,
	},
	Net = ctx.Net,
}
-- the lookups Plate.start waits for (the mock task.wait does not yield)
local carsF = Instance.new("Folder")
carsF.Name = "GwangalliPlayerCars"
carsF.Parent = workspace
local gsM = Instance.new("ModuleScript")
gsM.Name = "GwangalliGarageShared"
gsM.Parent = game:GetService("ReplicatedStorage")
local Plate = __req("Plate")
Plate.start(pctx)
local res = Plate.set(player, "12가3456", "gold")
check("plate set ok", res.ok == true and res.plate == "12가3456" and prof.plate.style == "gold", res.message)
check("plate attr", player:GetAttribute(P.Attr.Plate) == "12가3456")
local res2 = Plate.set(player, "광안 1004", nil)
check("plate cooldown", res2.ok == false and res2.code == "cooldown", res2.code)
res2 = Plate.set(player, "12가3456", "neon")
check("plate style only", res2.ok == true and prof.plate.style == "neon", res2.code)
res2 = Plate.set(player, "<script>", nil)
check("plate bad chars", res2.ok == false and res2.code == "chars", res2.code)
check("plate textFor", Plate.textFor(player) == "12가3456")
res2 = Plate.clear(player)
check("plate clear", res2.ok == true and prof.plate.text == nil and Plate.textFor(player) == nil)

print(string.format("logic tests: %d passed, %d failed", passes, fails))
