--!nocheck
-- simtest2.luau: 화장실 칸 잠금 · 입구 문 · 비상구 · 응급실 · 감시 · 망원경 · 남의 장식 숨김 (가짜 시계)
local R = require("./lib/rbx")
local G = R.G
local V3, CF = G.Vector3, G.CFrame
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
-- 다른 빌더(T_clinic)가 화장실 안에 매단 표지를 미리 둔 상황
local foreign = R.Instance.new("Model")
foreign.Name = "clinic#backhall"
foreign.Parent = root
local hang = R.Instance.new("Part")
hang.Name = "HangSign"
hang.Size = V3.new(6, 1, 0.1)
hang.CFrame = CF.new(Geo.W(-50.9, 8.3, 36.8))
hang.CanCollide = true
hang.Parent = foreign
local ctx = { root = root, focus = function() return R.hrp.Position end, limits = function() return 3, 2600, 8 end, dbg = function() end, Scan = req("Scan") }
local zones = HP._buildAll(ctx)
local hub = HP._hub()
local fails = 0
local function check(name, ok, info)
	if not ok then fails += 1 end
	print((if ok then "PASS " else "FAIL ") .. name .. " " .. tostring(info or ""))
end
local function L() return Geo.L(R.hrp.Position) end
local function run(sec)
	for _ = 1, math.floor(sec / 0.1 + 0.5) do
		R.advance(0.1)
		for _, K in zones do
			for _, f in K.anims do
				local ok, e = pcall(f, R.clock, 0.1)
				if not ok then print("anim err", e) end
			end
		end
		if hub and hub.portal then hub.portal.tick(R.clock, 0.1) end
		if math.floor(R.clock * 10 + 0.5) % 10 == 0 then
			for _, K in zones do
				for _, f in K.secs do pcall(f, R.clock) end
			end
			if hub and hub.portal then hub.portal.sec(R.clock) end
		end
	end
end
local function put(x, y, z) R.hrp.CFrame = CF.new(Geo.W(x, y + 3, z)) end
local function fmt(v) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end
local function find(K, name, parentName)
	for _, d in K.folder:GetDescendants() do
		if d.Name == name and (not parentName or (d.Parent and d.Parent.Name == parentName)) then return d end
	end
end
local function promptOf(K, action, object)
	for _, p in K.prompts do
		if p.ActionText == action and (not object or p.ObjectText == object) then return p end
	end
end

-- 0) 남의 장식 숨김
check("foreign_hidden", hang.Transparency == 1 and hang.CanCollide == false, "t=" .. hang.Transparency)
local late = R.Instance.new("Part")
late.Name = "LatePoster"
late.Size = V3.new(1, 1, 0.1)
late.CFrame = CF.new(Geo.W(-32.0, 5, 38.7))
late.Parent = foreign
run(0.2)
check("foreign_late_hidden", late.Transparency == 1, "t=" .. late.Transparency)

-- 1) 여자 화장실 입구 문: 다가가면 열리고 멀어지면 닫힘
local hall1 = zones.hall1
local wLeaf = find(hall1, "DoorLeaf", "EntranceDoor_W") or find(hall1, "DoorLeaf")
local base = wLeaf and wLeaf.CFrame
put(-49.9, 0, 25.0)
run(1.5)
local moved = wLeaf and (wLeaf.CFrame.Position - base.Position).Magnitude or 0
check("rr_door_opens", moved > 1.0, string.format("moved %.2f", moved))
put(-20, 0, 30)
run(3.5)
local back = wLeaf and (wLeaf.CFrame.Position - base.Position).Magnitude or 99
check("rr_door_closes", back < 0.05, string.format("off %.3f", back))

-- 2) 칸 잠금: 칸 밖에서는 프롬프트 꺼짐, 안에서 잠그면 사용중 + 문 닫힘 + 충돌
local lockP = promptOf(hall1, "잠그기", "넓은 칸")
put(-56.5, 0, 31.0) -- 칸 앞
run(0.5)
check("stall_prompt_hidden_outside", lockP and lockP.Enabled == false)
put(-56.5, 0, 35.5) -- 칸 안
run(1.0)
check("stall_prompt_inside", lockP and lockP.Enabled == true)
lockP.Triggered:Fire()
run(2.0)
local ind
for _, d in hall1.folder:GetDescendants() do
	if d:IsA("TextLabel") and (d.Text == "사용중") then ind = d end
end
check("stall_locked_indicator", ind ~= nil, ind and ind.Text)
local sLeaf = find(hall1, "StallLeaf", "StallDoor_W1")
check("stall_leaf_collides", sLeaf and sLeaf.CanCollide == true, sLeaf and tostring(sLeaf.CanCollide))
check("stall_prompt_text", lockP.ActionText == "잠금 해제", lockP.ActionText)
put(-20, 0, 30) -- 나가면 자동 해제
run(0.5)
check("stall_auto_unlock", lockP.ActionText == "잠그기", lockP.ActionText)

-- 3) 비상구: 안에서 문 쪽으로 걸으면 밀려 열림 → 멀어지면 닫히고 충돌
local exits = zones.exits
local feLeaf = find(exits, "FELeaf")
local feBase = feLeaf.CFrame
put(58.3, 0, 29.6)
R.humanoid = R.humanoid or R.character:FindFirstChildOfClass("Humanoid")
local hum = R.character:FindFirstChildOfClass("Humanoid")
rawget(hum, "_p").MoveDirection = Geo.HF.XVector
run(1.2)
rawget(hum, "_p").MoveDirection = V3.new(0, 0, 0)
local feMoved = (feLeaf.CFrame.Position - feBase.Position).Magnitude
check("fire_exit_push_opens", feMoved > 1.5 and feLeaf.CanCollide == false, string.format("moved %.2f cc=%s", feMoved, tostring(feLeaf.CanCollide)))
put(80, -0.34, 29.6)
run(7)
local feBack = (feLeaf.CFrame.Position - feBase.Position).Magnitude
check("fire_exit_closes", feBack < 0.05 and feLeaf.CanCollide == true, string.format("off %.3f cc=%s", feBack, tostring(feLeaf.CanCollide)))
local leverP = promptOf(exits, "문 열기", "비상구")
put(61.0, -0.34, 28.6)
leverP.Triggered:Fire()
run(1.0)
check("fire_exit_outside_lever", (feLeaf.CFrame.Position - feBase.Position).Magnitude > 1.5)
put(80, -0.34, 29.6)
run(7)

-- 4) 응급실: 밖에서 다가가면 안 · 밖 문 둘 다 열림
local erLeaf = find(exits, "ERGlass")
local erBase = erLeaf.CFrame
put(63.0, -0.34, 14.5)
run(1.2)
local erMoved = (erLeaf.CFrame.Position - erBase.Position).Magnitude
check("er_opens", erMoved > 2.0, string.format("moved %.2f", erMoved))
put(80, -0.34, 0)
run(3.5)
check("er_closes", (erLeaf.CFrame.Position - erBase.Position).Magnitude < 0.05)

-- 5) 숨은 방 감시: 방 안에서 서버가 다른 곳으로 옮기면 상태 정리
put(-12.09, 0, 35.6)
run(0.5)
HP.debug("go staff hall")
run(4)
check("portal_in", hub.portal.inside() and L().Y < -40, fmt(L()))
put(48, 0, 7) -- 서버 순간 이동 (쓰러짐 → 처치실)
run(1.0)
check("watchdog_clears", not hub.portal.inside(), hub.portal.status())
run(25)
check("room_cleanup", string.find(hub.portal.status(), "rooms=0") ~= nil or string.find(hub.portal.status(), "rooms=2") ~= nil, hub.portal.status())

-- 6) 엘리베이터: 카 밖에서 R 호출 → 카만 감, 탄 사람 없음
put(-32.09, 0, 30)
HP.debug("call 3")
run(8)
check("lift_hall_call_R", hub.lift.state().floor == 3, HP.debug("lift"))
check("lift_not_dragging_outsider", math.abs(L().Y - 3) < 0.2, fmt(L()))
-- 문 열린 동안 문간에 서 있으면 안 닫힘
put(-32.09, 25.2, 33.6)
run(6)
check("lift_doorway_hold", hub.lift.state().mode == "open", HP.debug("lift"))
put(-20, 25.2, 20)
run(7)
check("lift_closes_after", hub.lift.state().mode == "idle", HP.debug("lift"))

print(string.format("#DONE fails=%d", fails))
