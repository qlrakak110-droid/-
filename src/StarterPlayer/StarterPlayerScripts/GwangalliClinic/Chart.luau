-- GwangalliClinic/Chart (client): 진료 기록 sheet — 진료카드 (등록번호 · 첫 방문 · 방문 횟수), 지금 건강 상태
-- (원인 · 권장 조치), 복용 중인 약, 마지막 건강검진 결과지, 진료 기록 (날짜 · 상병 · 처치 · 진료비).

local Chart = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any

local sheet: any

function Chart.open()
	local res = ctx.call("chart", {})
	if not res.ok then
		return
	end
	sheet.clear()
	local b = sheet.body
	local chart = res.chart
	sheet.sub.Text = if chart then string.format("등록번호 %s", chart.no or "") else "아직 진료카드가 없어요 (첫 접수 때 만들어져요)"
	if chart then
		local card = Ui.card(b, { LayoutOrder = 1 })
		Ui.pad(card, 14, 10, 14, 10)
		Ui.list(card, "v", 2)
		Ui.row(card, "첫 방문", S.date(chart.first), { order = 1 })
		Ui.row(card, "방문 횟수", string.format("%d회", chart.visits or 0), { order = 2 })
		if (chart.last or 0) > 0 then
			Ui.row(card, "마지막 진료", S.dateTime(chart.last), { order = 3 })
		end
	end
	if res.health then
		Ui.healthCard(b, res.health, { order = 2 })
	end
	if res.meds then
		local m = res.meds
		local mc = Ui.card(b, { LayoutOrder = 3 })
		Ui.pad(mc, 14, 10, 14, 10)
		Ui.list(mc, "v", 2)
		Ui.text(mc, { Text = string.format("💊 %s · %d/%d회", m.name or "처방약", m.taken or 0, m.total or 3), Font = F.black, TextSize = 14, TextColor3 = Col.tealDD, LayoutOrder = 1 })
		Ui.text(mc, { Text = table.concat(m.items or {}, " · "), Font = F.med, TextSize = 12, TextColor3 = Col.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
		Ui.text(mc, { Text = if m.due then "지금 드실 시간이에요" else string.format("다음 복용까지 %s · %s", S.dur(m.nextIn or 0), m.times or ""), Font = F.med, TextSize = 12, LayoutOrder = 3 })
	end
	if res.report then
		local r = res.report
		local g = S.Medical.GRADES[r.grade or "A"] or S.Medical.GRADES.A
		Ui.btn(b, { text = string.format("📋 마지막 건강검진 · %s · %s (결과지 보기)", r.date or "", g.label), style = "secondary", size = UDim2.new(1, 0, 0, 46), order = 4, textSize = 14, onClick = function()
			sheet.close()
			ctx.Checkup.showReport(r)
		end })
	end
	Ui.text(b, { Text = "진료 기록", Font = F.black, TextSize = 15, LayoutOrder = 5 })
	local hist = res.history or {}
	if #hist == 0 then
		Ui.text(b, { Text = "아직 진료 기록이 없어요", Font = F.med, TextSize = 13, TextColor3 = Col.faint, LayoutOrder = 6 })
	end
	for i, e in hist do
		local row = Ui.card(b, { LayoutOrder = 10 + i })
		Ui.pad(row, 12, 8, 12, 8)
		Ui.list(row, "v", 2)
		local dept = C.Depts[e.dept] and C.Depts[e.dept].name or ""
		Ui.row(row, string.format("%s · %s", S.date(e.t), dept), S.won(e.paid or 0), { order = 1, size = 13 })
		Ui.text(row, { Text = string.format("%s%s", e.dx or "", if e.code and e.code ~= "" then " (" .. e.code .. ")" else ""), Font = F.bold, TextSize = 14, LayoutOrder = 2, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
		if e.plan and e.plan ~= "" then
			Ui.text(row, { Text = e.plan, Font = F.med, TextSize = 12, TextColor3 = Col.sub, LayoutOrder = 3, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
		end
	end
	sheet.open()
end

function Chart.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	sheet = Ui.sheet("GwClinic_Chart", { title = "📋 진료 기록 · " .. C.Venue.Name, w = 540, h = 660 })
end

return Chart
