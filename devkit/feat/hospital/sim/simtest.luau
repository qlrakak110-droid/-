--!nocheck
-- simtest.luau: 엘리베이터 상태 기계 · 숨은 방 이동 · 문 감지 오프라인 확인 (가짜 시계)
local R = require("./lib/rbx")
local G = R.G
local V3, CF = G.Vector3, G.CFrame
print("same R?", R.env == require("../sim/lib/rbx").env)
local fxMain = require("../../../bprev/fx/hospital_backhall")(G.Vector3, G.Color3, G.CFrame)
local fxBld = require("./fx_bld")(G.Vector3, G.Color3, G.CFrame)
R.loadFixture(fxMain)
R.loadFixture(fxBld)
local req = require("./out/mods_t")
local HP = req("HospitalPlus")
local Geo = req("Hosp_Geo")
local root = R.Instance.new("Folder")
root.Name = "GwInteriorDetailLocal"
root.Parent = R.workspace
local ctx = { root = root, focus = function() return R.hrp.Position end, limits = function() return 3, 2600, 8 end, dbg = function() end, Scan = req("Scan") }
local zones = HP._buildAll(ctx)
local function L() return Geo.L(R.hrp.Position) end
local function run(sec)
	for _ = 1, math.floor(sec / 0.1) do
		R.advance(0.1)
		for _, K in zones do
			for _, f in K.anims do
				local ok, e = pcall(f, R.clock, 0.1)
				if not ok then print("anim err", e) end
			end
		end
	end
end
local function put(x, y, z) R.hrp.CFrame = CF.new(Geo.W(x, y + 3, z)) end
local function fmt(v) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end
-- 엘리베이터: 카 안에서 2 층 → 옥상 → 1 층
put(-32.09, 0, 36.1)
run(1)
print("lift0", HP.debug("lift"), fmt(L()))
HP.debug("call 2")
run(6)
print("lift->2", HP.debug("lift"), fmt(L()))
HP.debug("call 3")
run(7)
print("lift->R", HP.debug("lift"), fmt(L()))
HP.debug("call 1")
run(9)
print("lift->1", HP.debug("lift"), fmt(L()))
-- 카 밖에서 2 층 호출 (카만 감)
put(-32.09, 14.15, 30)
HP.debug("call 2")
run(7)
print("hallcall2", HP.debug("lift"), "me", fmt(L()))
-- 숨은 방
put(-12.09, 0, 35.6)
run(0.5)
HP.debug("go staff hall")
run(4)
print("staff in", fmt(L()), HP.status())
run(2)
HP.debug("back staff hall")
run(3)
print("staff out", fmt(L()), HP.status())
put(-5.95, 14.15, 36.0)
run(0.5)
HP.debug("go stair hall")
run(4)
print("stair in", fmt(L()))
HP.debug("back stair roof")
run(3)
print("stair roof", fmt(L()))
-- 서버가 방 안에서 다른 곳으로 옮긴 경우 (감시)
HP.debug("go stair roof")
run(4)
print("stair in2", fmt(L()), HP.status())
put(48, 0, 7)
run(2)
print("watchdog", HP.status())
-- 유리문 감지: 문 앞에 서면 열림
local doorLeaf
for _, d in zones.doors.folder:GetDescendants() do
	if d.Name == "GlassPane" and d.Parent and d.Parent.Name == "GlassDoor_consult" then doorLeaf = d break end
end
local before = Geo.L(doorLeaf.Position)
put(-20.1, 0, -4.0)
run(2)
print("glass door moved", fmt(before), "->", fmt(Geo.L(doorLeaf.Position)))
put(-20.1, 0, 10)
run(4)
print("glass door back", fmt(Geo.L(doorLeaf.Position)))
