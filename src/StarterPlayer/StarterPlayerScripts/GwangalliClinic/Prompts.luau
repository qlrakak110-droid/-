-- GwangalliClinic/Prompts (client): LOCAL ProximityPrompts on the server's anchors
-- (Workspace.GwangalliClinic.Anchors), showing only the action that fits the patient's current step:
--   Kiosk "번호표 뽑기" · Win1/2 "접수하기" / "수납하기" / "결제하고 치료받기" / "퇴원 수속" · ConsultSeat "진료실
--   들어가기" · ExamBed "주사 맞기" · TreatBed "수액 맞기" · Pharmacy "처방전 내기" / "약 받기" · CheckDesk
--   "건강검진 접수" / "결과 상담" · stations "○○ 검사" · ward beds "병실 휴식" · call panels "간호사 호출" ·
--   the waiting room's magazine rack "잡지 보기"
-- The server re-checks step + distance for every action. The interior team's duplicate toy prompts
-- ("번호표 뽑기" always, the 2F checkup toys during our course) are disabled locally and kept off.

local Players = game:GetService("Players")

local Prompts = {}

local ctx: any
local S: any
local C: any
local player = Players.LocalPlayer

local prompts: { [string]: ProximityPrompt } = {}
local suppressed: { [ProximityPrompt]: boolean } = {}

local function stationDone(v: any, id: string): boolean
	if not v or not v.chk then
		return false
	end
	for _, st in v.chk.stations do
		if st.id == id then
			return st.done
		end
	end
	return false
end

-- returns { action, object, hold? } or nil (hidden)
local function config(name: string, a: BasePart, v: any?, hv: any?): any?
	local kind = a:GetAttribute(S.NAMES.AttrKind)
	local label = a:GetAttribute(S.NAMES.AttrLabel) or ""
	local step = v and v.step or nil
	if name == "Kiosk" then
		if not v then
			return { action = "번호표 뽑기", object = "무인 접수 키오스크" }
		end
		return nil
	elseif kind == "window" then
		local myWin = v and v.window and ("Win" .. v.window) or nil
		if step == "desk_called" and myWin == name then
			return { action = "접수하기", object = label .. " · 원무과" }
		elseif step == "desk" and myWin == name then
			return { action = "접수 이어하기", object = label }
		elseif step == "pay_go" then
			return { action = "수납하기", object = label .. " · 진료비 수납" }
		elseif step == "need_money" then
			return { action = "결제하고 치료받기", object = label }
		elseif not v and hv and (hv.debt or 0) > 0 then
			return { action = "퇴원 수속 · 미납금 정산", object = label }
		end
		return nil
	elseif name == "ConsultSeat" then
		if step == "consult_called" then
			return { action = "진료실 들어가기", object = C.Doctor.room }
		end
		return nil
	elseif name == "ExamBed" then
		if step == "treat_go" then
			local vac = v and v.plan and v.plan.vaccine
			return { action = if vac then "예방접종 받기" else "주사 맞기", object = "진찰대 · 간호사 박선생" }
		end
		return nil
	elseif name == "TreatBed1" or name == "TreatBed2" then
		if step == "iv_go" and (v.iv == nil) and (v.target == name) then
			return { action = "수액 맞기", object = label .. " · 간호사 최선생" }
		end
		return nil
	elseif name == "Pharmacy" then
		if step == "pharm_go" then
			return { action = "처방전 내기", object = "원내 약국 · 약사 정약사" }
		elseif step == "pharm_ready" then
			return { action = "약 받기", object = "원내 약국" }
		end
		return nil
	elseif name == "CheckDesk" then
		if not v then
			return { action = "건강검진 접수", object = "2층 건강검진센터" }
		elseif step == "chk_go" then
			return { action = "검진 접수하기", object = "건강검진센터" }
		elseif step == "chk_result" then
			return { action = "결과 상담 받기", object = "건강검진센터 · 한선생" }
		end
		return nil
	elseif kind == "station" then
		local id = a:GetAttribute(S.NAMES.AttrStation)
		if step == "chk_course" and type(id) == "string" and not stationDone(v, id) and not (v.chk.cur and v.chk.cur.station == id) then
			return { action = label .. " 검사", object = "건강검진 · " .. label }
		end
		return nil
	elseif kind == "ward" then
		if not v and C.Ward.RestEnabled then
			return { action = "병실 휴식", object = label, hold = 0.5 }
		end
		return nil
	elseif kind == "call" then
		return { action = "간호사 호출", object = label }
	elseif kind == "magazine" then
		return { action = "잡지 보기", object = label }
	end
	return nil
end

local function onTrigger(name: string, a: BasePart)
	local v = ctx.visit
	local kind = a:GetAttribute(S.NAMES.AttrKind)
	local step = v and v.step or nil
	if name == "Kiosk" then
		ctx.Desk.openKiosk()
	elseif kind == "window" then
		if step == "desk_called" or step == "desk" then
			ctx.Desk.beginRegister()
		elseif step == "pay_go" then
			ctx.Desk.openBill()
		elseif step == "need_money" then
			ctx.Desk.resume()
		elseif not v then
			ctx.Desk.openWardBill()
		end
	elseif name == "ConsultSeat" then
		ctx.Consult.enter()
	elseif name == "ExamBed" then
		ctx.Treat.start()
	elseif name == "TreatBed1" or name == "TreatBed2" then
		ctx.Treat.startIV()
	elseif name == "Pharmacy" then
		if step == "pharm_go" then
			ctx.Pharmacy.submit()
		else
			ctx.Pharmacy.collect()
		end
	elseif name == "CheckDesk" then
		ctx.Checkup.desk()
	elseif kind == "station" then
		ctx.Checkup.station(a:GetAttribute(S.NAMES.AttrStation))
	elseif kind == "ward" then
		local res = ctx.call("ward", { action = "rest" })
		if res.ok then
			ctx.Ui.toast("🛏️ 병실 휴식 중", string.format("누워 있으면 피로가 조금씩 풀려요 (최대 -%d) · 일어나면 끝", res.max or C.Ward.RestMaxPerStay), "info")
		end
	elseif kind == "call" then
		local res = ctx.call("ward", { action = "call" })
		if res.ok then
			ctx.Ui.ding()
		end
	elseif kind == "magazine" then
		ctx.Lounge.openMagazine()
	end
end

local function ensure(a: BasePart): ProximityPrompt
	local pr = prompts[a.Name]
	if pr and pr.Parent == a then
		return pr
	end
	pr = Instance.new("ProximityPrompt")
	pr.Name = "GwClinicPrompt"
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.GamepadKeyCode = Enum.KeyCode.ButtonX
	pr.RequiresLineOfSight = false
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pr.HoldDuration = 0.25
	local kind = a:GetAttribute(S.NAMES.AttrKind)
	local reach = C.Reach
	local dist = ({ kiosk = reach.Kiosk, window = reach.Window, consult = reach.Seat, bed = reach.Bed, pharmacy = reach.Pharmacy, checkdesk = reach.CheckDesk, station = reach.Station, ward = reach.Ward, call = reach.Ward, magazine = 9 })[kind] or 10
	pr.MaxActivationDistance = math.max(6, dist - 2.5)
	pr.Enabled = false
	pr.Parent = a
	local name = a.Name
	pr.Triggered:Connect(function(who)
		if who == player then
			onTrigger(name, a)
		end
	end)
	prompts[name] = pr
	return pr
end

function Prompts.refresh()
	local v = ctx.visit
	local hv = ctx.health
	for _, a in ctx.anchors() do
		local cfg = config(a.Name, a, v, hv)
		if cfg then
			local pr = ensure(a)
			pr.ActionText = cfg.action
			pr.ObjectText = cfg.object or ""
			pr.HoldDuration = cfg.hold or 0.25
			pr.Enabled = true
		else
			local pr = prompts[a.Name]
			if pr then
				pr.Enabled = false
			end
		end
	end
	-- interior toys during our checkup course
	local inCourse = v ~= nil and v.chk ~= nil
	for pr in suppressed do
		if pr.Parent then
			local always = table.find(C.Interior.SuppressAlways, pr.ActionText) ~= nil
			local course = table.find(C.Interior.SuppressDuringCheckup, pr.ActionText) ~= nil
			local off = always or (course and inCourse)
			pr:SetAttribute("GwClinicOff", off)
			if off then
				if pr.Enabled then
					pr:SetAttribute("GwClinicWasOff", true)
				end
				pr.Enabled = false
			elseif pr:GetAttribute("GwClinicWasOff") then
				pr:SetAttribute("GwClinicWasOff", nil)
				pr.Enabled = true
			end
		else
			suppressed[pr] = nil
		end
	end
end

local function considerInterior(d: Instance)
	if not d:IsA("ProximityPrompt") or d.Name ~= "GwInteriorPrompt" or suppressed[d] ~= nil then
		return
	end
	local listed = table.find(C.Interior.SuppressAlways, d.ActionText) ~= nil or table.find(C.Interior.SuppressDuringCheckup, d.ActionText) ~= nil
	if not listed then
		return
	end
	-- only this clinic's toys (the bank / 주민센터 interiors have their own "번호표 뽑기")
	if not S.inVenue(S.posOf(d.Parent)) then
		return
	end
	suppressed[d] = true
	d:GetPropertyChangedSignal("Enabled"):Connect(function()
		if d.Enabled and d:GetAttribute("GwClinicOff") then
			d.Enabled = false
			d:SetAttribute("GwClinicWasOff", true)
		end
	end)
	Prompts.refresh()
end

function Prompts.onVisit()
	Prompts.refresh()
end

function Prompts.onHealth()
	Prompts.refresh()
end

function Prompts.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	task.spawn(function()
		local f = workspace:WaitForChild(C.Interior.Folder, 600)
		if not f then
			return
		end
		for _, d in f:GetDescendants() do
			considerInterior(d)
		end
		f.DescendantAdded:Connect(function(d)
			task.defer(considerInterior, d)
		end)
	end)
	task.spawn(function()
		while true do
			pcall(Prompts.refresh)
			task.wait(1.5)
		end
	end)
end

return Prompts
