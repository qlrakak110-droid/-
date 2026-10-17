-- GwangalliClinic/Lounge (client): 대기실에서 기다리는 동안 — 잡지 꽂이의 "광안 헬스 매거진".
-- The articles are written from the patient's REAL state (Health system numbers: 피로도, 급여 배율 구간,
-- 질병 위험도, 수면 / 식사 / 휴식 회복량, the current illness' 증상 · 처방 · 생활 수칙) and the clinic's own
-- services (영양주사 · 예방접종 · 2층 건강검진 prices from the server). Pure flavour: no server op, no money.
-- While a visit is waiting, the sheet shows the live "내 순서" line at the top, and closes itself when the
-- patient is called (the call banner takes over).

local Lounge = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Col: any
local F: any

local sheet: any
local liveLine: TextLabel? = nil
local page = 1

local function H(): any
	return S.H() or {}
end

local function article(parent: Instance, order: number, kicker: string, title: string, lines: { string }, accent: Color3?)
	local card = Ui.paper(parent, { LayoutOrder = order })
	Ui.text(card, { Text = kicker, Font = F.black, TextSize = 12, TextColor3 = accent or Col.teal, LayoutOrder = 1 })
	Ui.text(card, { Text = title, Font = F.black, TextSize = 18, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	Ui.new("Frame", { BackgroundColor3 = accent or Col.teal, BorderSizePixel = 0, Size = UDim2.fromOffset(42, 3), LayoutOrder = 3 }, card)
	for i, line in lines do
		Ui.text(card, { Text = line, Font = F.med, TextSize = 14, TextColor3 = Col.ink, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 10 + i })
	end
	return card
end

-- 1) 나를 위한 기사: 지금 앓는 병 (Medical + Health kind data) 또는 피로 관리
local function pageForMe(b: Instance, hv: any)
	local fat = H().fatigue or {}
	local kind = S.kind(hv.kind)
	if kind then
		local med = kind.med
		local sym = {}
		for _, id in med.symptoms or {} do
			table.insert(sym, S.Medical.SYMPTOMS[id] or id)
		end
		article(b, 1, "이번 호 특집 · " .. kind.icon .. " " .. kind.name, string.format("%s, 이렇게 이겨내세요", med.dx), {
			"🩺 대표 증상 · " .. table.concat(sym, " · "),
			"💡 왜 걸릴까? · " .. (kind.desc ~= "" and kind.desc or "과로로 면역력이 떨어지면 잘 걸려요."),
			"💉 의원에서는 · " .. (kind.cure ~= "" and kind.cure or "주사 + 약 처방") .. string.format(" (치료하면 피로도 -%d)", fat.cured or 50),
			"💊 약은 · " .. med.times .. " · " .. (med.caution or ""),
			"🛏️ 집에서는 · " .. (med.lines and med.lines.after or "푹 쉬세요."),
		}, Col.red)
	else
		local f = tonumber(hv.fatigue) or 0
		-- the game's own pay tiers (G.HEALTH.tiers, checked top down) and illness risk start
		local tierBits = {}
		local tiers = H().tiers
		if type(tiers) == "table" then
			for i = #tiers, 1, -1 do
				local t = tiers[i]
				if type(t) == "table" and (t.min or 0) > 0 then
					table.insert(tierBits, string.format("%d 이상 x%.1f", t.min, t.mult or 1))
				end
			end
		end
		local tierLine = if #tierBits > 0 then "📉 피로도가 쌓이면 알바 급여가 깎여요 · " .. table.concat(tierBits, " · ") else "📉 피로도가 쌓일수록 알바 급여가 깎여요."
		local riskFrom = (H().risk and H().risk.from) or 80
		article(b, 1, "알바생 건강 · 피로 관리", if f >= 50 then string.format("피로도 %d, 지금 쉬어야 하는 이유", f) else "지금 컨디션 그대로 지키는 법", {
			tierLine,
			string.format("🦠 피로도 %d을 넘긴 채 일하면 질병 위험도가 쌓이고, 다 차면 감기 · 몸살 · 위염 · 번아웃이 와요.", riskFrom),
			string.format("🛏️ 집 침대에서 자면 피로도 -%d · 🍜 밥 한 끼 · 카페 -%d", fat.sleep or 70, fat.meal or 6),
			string.format("⏸️ 퇴근하고 쉬기만 해도 %d초마다 -1", fat.restSeconds or 90),
			string.format("💉 바쁘면 영양주사 (피로도 -%d) · 진료 접수 때 '피곤해요'를 고르세요", fat.vitamin or 40),
		}, Col.teal)
	end
end

-- 2) 의원 이용 안내 (실제 가격)
local function pageGuide(b: Instance)
	local fees = ctx.fees or {}
	local svc = H().services or {}
	local vit = fees.vitamin or (svc.vitamin and svc.vitamin.fee) or 30000
	local chk = fees.checkup or (svc.checkup and svc.checkup.fee) or 10000
	article(b, 2, "광안 메디컬 의원 이용 안내", "번호표부터 약국까지, 한 번에", {
		"① 무인 키오스크에서 번호표 → ② 창구에서 문진표 → ③ 진료실 1 김선생 진찰",
		"④ 진찰대 주사 · 주사실 수액 → ⑤ 접수 · 수납 창구 → ⑥ 원내 약국에서 약 받기",
		string.format("💉 영양주사 %s · 인플루엔자 예방접종 %s · 2층 건강검진 %s", S.won(vit), S.won(C.Fees.Vaccine), S.won(chk)),
		string.format("🌙 %02d시 ~ 다음 날 %02d시는 야간 당직 진료 (진찰료 %d%% 가산)", C.Fees.NightFrom, C.Fees.NightTo, math.floor(C.Fees.NightAddRate * 100)),
		"🧾 진료비는 체크카드(통장) · 현금 모두 돼요. 모자라면 미납으로 처리하고 다음에 내도 돼요.",
	}, Col.navy)
end

-- 3) 2층 건강검진 · 예방접종
local function pagePrevent(b: Instance, hv: any)
	local lines = {
		"📏 신장·체중 · 💓 혈압 · 👁️ 시력 · 🎧 청력 · 📈 심전도 — 2층 건강검진센터에서 15분이면 끝나요.",
		"📋 결과지는 A (정상) ~ D (질환 의심) 판정 · 진료 기록에 남아요.",
		string.format("💉 예방접종 후 %d시간 동안은 일해도 질병 위험도가 %d%% 덜 쌓여요.", C.Treat.VaccineHours, math.floor(C.Treat.VaccineRiskDamp * 100)),
	}
	if (hv.riskPct or 0) > 0 then
		table.insert(lines, string.format("⚠️ 지금 내 질병 위험도는 %d%% · 건강 상담만 받아도 절반으로 줄어요.", hv.riskPct))
	end
	article(b, 3, "예방이 최고의 치료", "아프기 전에 한 번, 건강검진", lines, Col.green)
end

local function render()
	if not sheet then
		return
	end
	sheet.clear()
	local b = sheet.body
	local hv = ctx.health or {}
	local v = ctx.visit
	liveLine = nil
	if v and (v.step == "desk_wait" or v.step == "consult_wait") then
		local bar = Ui.card(b, { BackgroundColor3 = Col.mint, LayoutOrder = 0 })
		Ui.pad(bar, 12, 8, 12, 8)
		liveLine = Ui.text(bar, { Text = "", Font = F.bold, TextSize = 14, TextColor3 = Col.tealDD, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y })
	end
	local tabs = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 }, b)
	local names = { "나를 위한 기사", "이용 안내", "예방 · 검진" }
	for i, nm in names do
		Ui.btn(tabs, {
			text = nm,
			style = if i == page then "primary" else "ghost",
			size = UDim2.new(1 / 3, -6, 1, 0),
			pos = UDim2.new((i - 1) / 3, 3, 0, 0),
			textSize = 14,
			onClick = function()
				page = i
				render()
			end,
		})
	end
	local holder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, b)
	Ui.list(holder, "v", 10)
	if page == 1 then
		pageForMe(holder, hv)
	elseif page == 2 then
		pageGuide(holder)
	else
		pagePrevent(holder, hv)
	end
	Ui.text(b, { Text = "광안 헬스 매거진 · 대기실 비치용 · 가져가지 마세요 🙏", Font = F.med, TextSize = 11, TextColor3 = Col.faint, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 9 })
	Lounge.refreshLive()
end

function Lounge.refreshLive()
	local l = liveLine
	local v = ctx.visit
	if not l or not l.Parent or not v then
		return
	end
	if (v.place or 0) > 1 then
		l.Text = string.format("🎫 %s번 · %s · 내 앞에 %d명 · 약 %d초 · 부르면 알려 드려요", S.ticket(v.ticket), v.stepLabel or "", v.place - 1, v.eta or 0)
	else
		l.Text = string.format("🎫 %s번 · %s · 곧 불러요", S.ticket(v.ticket), v.stepLabel or "")
	end
end

function Lounge.openMagazine()
	page = 1
	render()
	sheet.open()
	Ui.sound("swoosh")
end

function Lounge.onVisit(v: any, prev: any)
	if not sheet or not sheet.isOpen then
		return
	end
	-- called to a window / the consult room: put the magazine back
	local step = v and v.step
	if step and prev and step ~= prev.step and (step == "desk_called" or step == "consult_called") then
		sheet.close()
		return
	end
	Lounge.refreshLive()
end

function Lounge.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	Col = Ui.C
	F = Ui.F
	sheet = Ui.sheet("GwClinic_Magazine", { title = "📰 광안 헬스 매거진", sub = "대기실 잡지 · 이번 달 호", w = 540, h = 640 })
end

return Lounge
