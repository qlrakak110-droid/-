-- GwangalliClinicShared/Medical: 진료 내용 (순수 데이터 + 계산; 서버/클라이언트 공용, 아무것도 만들지 않음).
-- 질병 종류(kind)는 기존 Health 시스템의 G.HEALTH.KINDS 와 같은 id (cold · ache · gastritis · burnout)
-- 이고, 이름 · 아이콘 · 진료비 · "cure" 문구는 Health 에서 읽습니다. 여기는 실제 의원 느낌을 위한
-- 상병명 / KCD 코드 / 증상 / 진찰 순서 / 처방약 / 대사 / 활력징후 모델 / 원인 문장 / 검진 판정만 둡니다.
--
--   Medical.KINDS[kind]           { dx, code, symptoms, exams, treat ("inject" | "iv"), temp, meds, ... }
--   Medical.HEALTHY(fatigue)      건강한 방문자의 소견 (피로 누적 R53 / 이상 소견 없음 Z00.0)
--   Medical.SYMPTOMS[id]          증상 이름 (문진표 칩)
--   Medical.vitals(seed, fatigue, kind) -> { temp, sys, dia, pulse, spo2, lung, throat, belly }
--   Medical.bpClass(sys, dia)     "정상" | "주의 혈압" | "고혈압 전단계" | "고혈압 의심"
--   Medical.cause(info) -> string     진단 카드의 "원인" (실제 근무 기록 · 피로도에서)
--   Medical.advice(info) -> { string } 권장 조치 (Health 수치 그대로: 수면 -70, 식사 -6 ...)
--   Medical.grade(report) -> grade, label, notes   건강검진 판정 (A ~ D)
--   Medical.line(key, ...)        대사 (string.format)

local Medical = {}

-------------------------------------------------------------------------------------------------
-- 증상 (문진표)
-------------------------------------------------------------------------------------------------
Medical.SYMPTOMS = {
	runny = "콧물",
	cough = "기침",
	sore = "목 아픔",
	fever = "열이 나요",
	muscle = "온몸이 쑤셔요",
	chill = "오한",
	headache = "두통",
	heartburn = "속쓰림",
	nausea = "메스꺼움",
	belly = "배가 아파요",
	appetite = "입맛이 없어요",
	lethargy = "무기력",
	insomnia = "잠을 못 자요",
	focus = "집중이 안 돼요",
	tired = "계속 피곤해요",
	shoulder = "어깨 · 목 결림",
	eyes = "눈이 피로해요",
	none = "특별히 없어요",
}
Medical.SYMPTOM_ORDER = { "fever", "runny", "cough", "sore", "chill", "muscle", "headache", "heartburn", "nausea", "belly", "appetite", "lethargy", "insomnia", "focus", "tired", "shoulder", "eyes", "none" }

-- 방문 목적 (접수 창구)
Medical.PURPOSES = {
	{ id = "ill", label = "몸이 아파요", icon = "🤒" },
	{ id = "tired", label = "피곤해요 · 영양주사", icon = "🔋" },
	{ id = "general", label = "건강 상담", icon = "💬" },
	{ id = "vaccine", label = "예방접종", icon = "💉" },
}

-------------------------------------------------------------------------------------------------
-- 질병별 진료 내용
-------------------------------------------------------------------------------------------------
Medical.KINDS = {
	cold = {
		dx = "급성 비인두염 (감기)",
		code = "J00",
		symptoms = { "runny", "cough", "sore", "fever" },
		exams = { "temp", "throat", "stetho", "bp" },
		treat = "inject", -- 진찰대에서 박선생이 주사 (Health 의 처치 연출)
		temp = 37.8,
		pulseAdd = 10,
		spo2 = 97,
		lung = "맑음 · 기관지 쪽 가래 소리 약간",
		throat = "인후 발적 (목이 빨갛게 부었어요)",
		belly = "압통 없음",
		meds = {
			{ name = "해열진통제", generic = "아세트아미노펜 500mg", dose = "1정" },
			{ name = "항히스타민제", generic = "클로르페니라민 2mg", dose = "1정" },
			{ name = "진해거담제", generic = "덱스트로메토르판 15mg", dose = "1정" },
		},
		times = "하루 3번 · 식후 30분",
		days = 3,
		caution = "졸릴 수 있어요. 오토바이 배달 · 택시 운전은 조심하세요.",
		lines = {
			find = "목이 많이 부었고 열도 있네요. 전형적인 감기예요.",
			treat = "해열 주사 한 대 맞고, 감기약 3일분 처방해 드릴게요.",
			after = "따뜻한 물 많이 드시고 오늘은 일찍 주무세요.",
		},
	},
	ache = {
		dx = "상세불명의 바이러스 감염 (몸살)",
		code = "B34.9",
		symptoms = { "muscle", "chill", "fever", "headache" },
		exams = { "temp", "bp", "stetho" },
		treat = "inject",
		temp = 38.6,
		pulseAdd = 14,
		spo2 = 98,
		lung = "맑음",
		throat = "약간 붉음",
		belly = "압통 없음",
		meds = {
			{ name = "소염진통제", generic = "이부프로펜 200mg", dose = "1정" },
			{ name = "근육이완제", generic = "에페리손 50mg", dose = "1정" },
			{ name = "위장보호제", generic = "레바미피드 100mg", dose = "1정" },
		},
		times = "하루 3번 · 식후 30분",
		days = 3,
		caution = "열이 내릴 때까지 무거운 짐 나르기 · 장시간 운전은 쉬세요.",
		lines = {
			find = "열이 38도 넘게 올랐어요. 온몸이 쑤시는 건 몸살 때문이에요.",
			treat = "해열 주사 놔 드리고 근육이완제 같이 처방할게요.",
			after = "땀 흘린 옷은 바로 갈아입고 푹 쉬세요.",
		},
	},
	gastritis = {
		dx = "급성 위염",
		code = "K29.1",
		symptoms = { "heartburn", "nausea", "belly", "appetite" },
		exams = { "bp", "palp", "stetho" },
		treat = "iv", -- 진찰대에서 수액 라인 → 주사실 침대에서 수액
		temp = 37.2,
		pulseAdd = 8,
		spo2 = 98,
		lung = "맑음",
		throat = "정상",
		belly = "명치 부위 압통 (눌렀을 때 아파요)",
		meds = {
			{ name = "위산분비억제제", generic = "파모티딘 20mg", dose = "1정" },
			{ name = "위점막보호제", generic = "알마게이트 1g", dose = "1포" },
			{ name = "진경제", generic = "부틸스코폴라민 10mg", dose = "1정" },
		},
		times = "하루 3번 · 식전 30분",
		days = 3,
		caution = "3일 동안 커피 · 술 · 맵고 짠 음식은 피하세요. 끼니는 꼭 챙기고요.",
		lines = {
			find = "명치를 누르면 아프시죠? 위벽이 헐어서 그래요. 급성 위염이에요.",
			treat = "수액으로 위를 좀 쉬게 하고, 위장약 처방해 드릴게요.",
			after = "오늘은 죽처럼 부드러운 걸로 드세요.",
		},
	},
	burnout = {
		dx = "탈진 (번아웃 증후군)",
		code = "Z73.0",
		symptoms = { "lethargy", "insomnia", "focus", "headache" },
		exams = { "bp", "stetho", "talk" },
		treat = "iv",
		temp = 36.8,
		pulseAdd = 16,
		spo2 = 97,
		lung = "맑음 · 호흡이 얕아요",
		throat = "정상",
		belly = "압통 없음",
		meds = {
			{ name = "비타민 B 복합제", generic = "벤포티아민 · B6 · B12", dose = "1정" },
			{ name = "마그네슘", generic = "산화마그네슘 250mg", dose = "1정" },
		},
		times = "하루 2번 · 아침 · 저녁 식후",
		days = 3,
		caution = "오늘은 알바 쉬세요. 7시간 이상 자는 게 제일 좋은 약이에요.",
		lines = {
			find = "맥박이 빠르고 몸이 완전히 지쳐 있어요. 번아웃이에요.",
			treat = "영양 수액 놔 드릴게요. 그리고 휴식이 꼭 필요해요. 휴식 처방이에요.",
			after = "몸도 마음도 쉬어야 회복돼요. 오늘은 일 생각 하지 마세요.",
		},
	},
}

-- 건강한 방문자 (질병 없음): 피로도에 따른 소견
function Medical.HEALTHY(fatigue: number): any
	local f = tonumber(fatigue) or 0
	if f >= 50 then
		return {
			dx = "피로 누적 (만성 피로)",
			code = "R53",
			symptoms = { "tired", "shoulder", "eyes" },
			exams = { "bp", "temp" },
			tired = true,
			find = string.format("지금 피로도는 %d. 아직 병은 아니지만 이대로 계속 일하면 탈 나요.", math.floor(f + 0.5)),
		}
	elseif f >= 25 then
		return {
			dx = "가벼운 피로",
			code = "R53",
			symptoms = { "tired" },
			exams = { "bp", "temp" },
			tired = true,
			find = "가볍게 피곤한 정도예요. 잘 먹고 잘 자면 금방 회복돼요.",
		}
	end
	return {
		dx = "이상 소견 없음 (일반 건강진찰)",
		code = "Z00.0",
		symptoms = { "none" },
		exams = { "bp", "temp" },
		tired = false,
		find = "혈압 · 체온 다 정상이에요. 아주 건강하시네요!",
	}
end

-------------------------------------------------------------------------------------------------
-- 진찰 단계 (진료실 미니 시퀀스)
-------------------------------------------------------------------------------------------------
Medical.EXAMS = {
	temp = { label = "체온", icon = "🌡️", say = "체온부터 잴게요. 귀에 잠깐 댈게요~" },
	throat = { label = "인후 진찰", icon = "👄", say = "입 벌리고 '아~' 해 보세요." },
	stetho = { label = "청진", icon = "🩺", say = "숨 크게 들이쉬고… 천천히 내쉬세요." },
	bp = { label = "혈압", icon = "💓", say = "팔 걷어 주세요. 혈압 잴게요." },
	palp = { label = "복부 촉진", icon = "✋", say = "누워 계신다 생각하고… 여기 누르면 아프세요?" },
	talk = { label = "생활 문진", icon = "💬", say = "요즘 하루에 몇 시간 일하고, 몇 시간 주무세요?" },
}

-- 진료실 첫 질문 (진료과별)
Medical.GREET = {
	im = "어서 오세요. 어디가 불편해서 오셨어요?",
	fm = "어서 오세요. 요즘 컨디션은 좀 어떠세요?",
	ped = "어서 와요~ 학생, 어디가 아파서 왔어요?",
	vac = "예방접종 오셨죠? 접종 전에 예진 먼저 할게요.",
}

-------------------------------------------------------------------------------------------------
-- 활력징후 모델 (피로도 · 질병에서 계산; 방문마다 seed 로 조금씩 다름)
-------------------------------------------------------------------------------------------------
local function rng(seed: number): () -> number
	local s = math.floor(math.abs(seed or 1)) % 2147483646 + 1
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end
Medical.rng = rng

local function round1(x: number): number
	return math.floor(x * 10 + 0.5) / 10
end

function Medical.vitals(seed: number, fatigue: number, kindId: string?): any
	local r = rng(seed)
	local f = math.clamp(tonumber(fatigue) or 0, 0, 100)
	local k = kindId and Medical.KINDS[kindId] or nil
	local ill = k ~= nil
	local temp = if k then k.temp else 36.4 + f * 0.003
	temp += (r() - 0.5) * 0.3
	local sys = 110 + f * 0.16 + (if ill then 6 else 0) + (r() - 0.5) * 6
	local dia = 70 + f * 0.12 + (if ill then 3 else 0) + (r() - 0.5) * 4
	local pulse = 66 + f * 0.24 + (if k then k.pulseAdd else 0) + (r() - 0.5) * 6
	local spo2 = if k then k.spo2 else (if f >= 90 then 97 else 98)
	return {
		temp = round1(temp),
		sys = math.floor(sys + 0.5),
		dia = math.floor(dia + 0.5),
		pulse = math.floor(pulse + 0.5),
		spo2 = spo2,
		lung = if k then k.lung else "맑음",
		throat = if k then k.throat else "정상",
		belly = if k then k.belly else "압통 없음",
	}
end

function Medical.bpClass(sys: number, dia: number): (string, string)
	if sys >= 140 or dia >= 90 then
		return "고혈압 의심", "bad"
	elseif sys >= 130 or dia >= 80 then
		return "고혈압 전단계", "warn"
	elseif sys >= 120 then
		return "주의 혈압", "warn"
	end
	return "정상", "ok"
end

function Medical.tempClass(t: number): (string, string)
	if t >= 38.0 then
		return "고열", "bad"
	elseif t >= 37.5 then
		return "미열", "warn"
	end
	return "정상", "ok"
end

-------------------------------------------------------------------------------------------------
-- 원인 · 권장 조치 (실제 상태에서)
-------------------------------------------------------------------------------------------------
-- Korean particle by the last syllable's final consonant (받침): josa("감기", "이에요", "예요") -> "감기예요"
function Medical.josa(word: string, withBatchim: string, without: string): string
	local last = nil
	for _, c in utf8.codes(word) do
		last = c
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 then
		return word .. (if (last - 0xAC00) % 28 ~= 0 then withBatchim else without)
	end
	return word .. without
end
local josa = Medical.josa

local function dur(sec: number): string
	local m = math.floor((tonumber(sec) or 0) / 60)
	if m < 1 then
		return "잠깐"
	elseif m < 60 then
		return string.format("%d분", m)
	end
	local h = math.floor(m / 60)
	local mm = m % 60
	if mm == 0 then
		return string.format("%d시간", h)
	end
	return string.format("%d시간 %d분", h, mm)
end
Medical.dur = dur

-- info = { kind?, fatigue, riskPct, jobTitle?, jobPlace?, workSec, nightSec, onShift, illMinutes, collapseIn? }
function Medical.cause(info: any): string
	local f = math.floor((tonumber(info.fatigue) or 0) + 0.5)
	local work = tonumber(info.workSec) or 0
	local night = tonumber(info.nightSec) or 0
	local job = info.jobTitle
	local where = if info.jobPlace and info.jobPlace ~= "" then info.jobPlace .. " " else ""
	local workLine
	if job and work >= 60 then
		if night >= 60 then
			workLine = string.format("최근 %s%s 쉬지 않고 %s (그중 밤샘 %s) 하셨어요.", where, josa(job, "을", "를"), dur(work), dur(night))
		else
			workLine = string.format("최근 %s%s 쉬지 않고 %s 하셨어요.", where, josa(job, "을", "를"), dur(work))
		end
	elseif work >= 60 then
		workLine = string.format("최근 쉬지 않고 %s 일하셨어요.", dur(work))
	else
		workLine = nil
	end
	local k = info.kind
	if k then
		local tail = ({
			cold = "피로도 80이 넘은 채로 계속 일해서 면역력이 떨어졌고, 그 틈에 감기가 왔어요.",
			ache = "몸을 쓰는 일을 과로 상태로 계속해서 근육과 면역이 같이 무너졌어요.",
			gastritis = "끼니를 거르고 일만 하면서 스트레스까지 겹쳐 위가 헐었어요.",
			burnout = "피로도가 한계까지 차서 몸도 마음도 다 타 버린 상태예요.",
		})[k] or "과로로 면역력이 떨어진 상태예요."
		local head = string.format("과로로 인한 %s. 피로도가 %d까지 쌓였어요.", josa(info.kindName or "질병", "이에요", "예요"), f)
		if workLine then
			return string.format("알바를 너무 오래 하셨네요… %s %s %s", workLine, head, tail)
		end
		return string.format("%s %s", head, tail)
	end
	if f >= 75 then
		return string.format("%s지금 피로도는 %d. 80을 넘긴 채로 일하면 질병 위험(지금 %d%%)이 빠르게 쌓여요.", if workLine then workLine .. " " else "", f, math.floor(tonumber(info.riskPct) or 0))
	elseif f >= 50 then
		return string.format("%s피로도 %d. 급여가 30%% 깎이는 구간이에요. 쉬어 가며 일하세요.", if workLine then workLine .. " " else "", f)
	elseif f >= 25 then
		return string.format("피로도 %d. 가벼운 피로예요.", f)
	end
	return string.format("피로도 %d. 아주 좋은 컨디션이에요.", f)
end

-- H = HS.H() (G.HEALTH). Returns up to 5 short lines, most important first.
function Medical.advice(info: any, H: any): { string }
	local out = {}
	local f = tonumber(info.fatigue) or 0
	local fat = (H and H.fatigue) or { sleep = 70, meal = 6, restSeconds = 90, cured = 50, vitamin = 40 }
	if info.kind then
		table.insert(out, string.format("🏥 오늘 바로 치료받기 · %s 완치 + 피로도 -%d", info.kindName or "질병", fat.cured or 50))
		if info.collapseIn and info.collapseIn < 240 then
			table.insert(out, string.format("⚠️ %d분 안에 치료받지 않으면 쓰러질 수 있어요", math.max(1, math.ceil(info.collapseIn / 60))))
		end
		table.insert(out, "💊 처방약은 끝까지 (3회) 드세요 · 회당 피로도도 조금씩 회복")
	end
	if f >= 90 then
		table.insert(out, "🛑 오늘 알바는 그만! 지금은 급여가 20%만 나와요")
	elseif f >= 75 then
		table.insert(out, "⚠️ 피로도 80 이상에서 일하면 질병 위험이 쌓여요")
	end
	table.insert(out, string.format("🛏️ 집 침대에서 자기 · 피로도 -%d", fat.sleep or 70))
	table.insert(out, string.format("🍜 밥 먹기 · 카페 · 피로도 -%d", fat.meal or 6))
	table.insert(out, string.format("⏸️ 퇴근하고 쉬기 · %d초마다 -1", fat.restSeconds or 90))
	while #out > 5 do
		table.remove(out)
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- 건강검진 판정
-------------------------------------------------------------------------------------------------
Medical.GRADES = {
	A = { label = "정상 A", sub = "건강해요! 지금처럼만 관리하세요", color = { 46, 184, 114 } },
	B = { label = "정상 B (경계)", sub = "작은 경고 신호가 있어요", color = { 15, 163, 163 } },
	C = { label = "주의", sub = "생활습관 개선이 필요해요", color = { 242, 153, 74 } },
	D = { label = "질환 의심", sub = "1층 내과 진료를 받으세요", color = { 229, 72, 77 } },
}

function Medical.bmi(heightCm: number, weightKg: number): number
	local m = math.max(0.5, heightCm / 100)
	return math.floor(weightKg / (m * m) * 10 + 0.5) / 10
end

function Medical.bmiClass(bmi: number): (string, string)
	if bmi < 18.5 then
		return "저체중", "warn"
	elseif bmi < 23 then
		return "정상", "ok"
	elseif bmi < 25 then
		return "비만 전단계", "warn"
	end
	return "비만", "bad"
end

-- report = { ill?, fatigue, riskPct, bp = {s, d, p}, bmi, vision = {l, r}, hearing = {l, r}, ecg }
function Medical.grade(report: any): (string, { string })
	local notes = {}
	local grade = "A"
	local function bump(g: string, note: string)
		local order = { A = 1, B = 2, C = 3, D = 4 }
		if order[g] > order[grade] then
			grade = g
		end
		table.insert(notes, note)
	end
	if report.ill then
		bump("D", string.format("%s 소견 · 1층 내과 진료 필요", report.illName or "질병"))
	end
	local f = tonumber(report.fatigue) or 0
	if f >= 75 then
		bump("C", string.format("피로 누적 (피로도 %d) · 휴식 필요", math.floor(f)))
	elseif f >= 50 then
		bump("B", string.format("피로 경계 (피로도 %d)", math.floor(f)))
	end
	local risk = tonumber(report.riskPct) or 0
	if risk >= 50 then
		bump("C", string.format("질병 위험도 %d%%", math.floor(risk)))
	end
	local bp = report.bp or {}
	if bp.s then
		local cls = Medical.bpClass(bp.s, bp.d)
		if cls == "고혈압 의심" then
			bump("C", string.format("혈압 %d/%d · 고혈압 의심", bp.s, bp.d))
		elseif cls ~= "정상" then
			bump("B", string.format("혈압 %d/%d · %s", bp.s, bp.d, cls))
		end
	end
	if report.bmi then
		local cls = Medical.bmiClass(report.bmi)
		if cls == "비만" then
			bump("C", string.format("BMI %.1f · 비만", report.bmi))
		elseif cls ~= "정상" then
			bump("B", string.format("BMI %.1f · %s", report.bmi, cls))
		end
	end
	local v = report.vision or {}
	if (v.l and v.l < 0.6) or (v.r and v.r < 0.6) then
		bump("B", "시력 저하 · 안과 검진 권장")
	end
	local h = report.hearing or {}
	if h.l == false or h.r == false then
		bump("B", "청력 경도 저하 · 재검 권장")
	end
	if report.ecg and report.ecg ~= "정상 동리듬" then
		bump(if report.ill then "D" else "B", "심전도 · " .. report.ecg)
	end
	if #notes == 0 then
		table.insert(notes, "모든 항목 정상이에요")
	end
	return grade, notes
end

-------------------------------------------------------------------------------------------------
-- 대사 (직원별)
-------------------------------------------------------------------------------------------------
Medical.LINES = {
	desk_hello = "안녕하세요, %03d번 고객님. 신분증 확인할게요.",
	desk_first = "처음 오셨네요. 등록번호 %s 로 진료카드 만들어 드렸어요.",
	desk_revisit = "재진이시네요. 지난번 진료 기록 불러올게요.",
	desk_purpose = "오늘은 어떻게 오셨어요?",
	desk_symptoms = "문진표 체크해 주세요. 지금 몸 상태 기준으로 미리 표시해 뒀어요.",
	desk_shift = "아, 지금 근무 중이시네요. 일하면서 기다리면 피로가 계속 쌓여요.",
	desk_debt = "지난번 미납 진료비 %s 이 있어요. 오늘 수납 때 같이 정산돼요.",
	desk_done = "%s %s로 접수됐어요. 진료실 앞에서 잠시만 기다려 주세요.",
	desk_pay = "진료비 계산해 드릴게요. 결제는 카드로 하시겠어요?",
	desk_paid = "결제됐습니다. 영수증이랑 처방전 드릴게요. 약국은 오른쪽 복도 끝이에요.",
	desk_paid_norx = "결제됐습니다. 영수증 드릴게요. 안녕히 가세요, 몸조리 잘 하세요!",
	nurse_inject = "엉덩이 주사예요~ 힘 빼세요. 따끔합니다!",
	nurse_press = "5분 정도 꾹 눌러 주세요. 문지르지 마시고요.",
	nurse_iv = "수액 바늘 잡을게요. %d초 정도 걸려요. 불편하면 말씀하세요.",
	nurse_iv_half = "절반 들어갔어요. 팔 너무 움직이지 마세요~",
	nurse_iv_done = "수액 다 들어갔어요. 바늘 뺄게요. 지혈 잠깐 하세요.",
	nurse_vac = "왼쪽 팔에 맞을게요. 힘 빼세요~ 따끔!",
	pharm_submit = "처방전 받았어요. %03d번, 조제하는 동안 잠시만 기다려 주세요.",
	pharm_ready = "%03d번 환자분, 약 나왔습니다~",
	pharm_guide = "%s. 3일 동안 꼭 챙겨 드세요.",
	pharm_rest = "그리고 무엇보다… 충분히 쉬세요. 약보다 잠이 먼저예요.",
	check_hello = "건강검진센터예요. 신장·체중부터 심전도까지 다섯 가지 검사를 하실 거예요.",
	check_done = "검사 다 끝나셨어요! 결과 상담 해 드릴게요.",
}

function Medical.line(key: string, ...: any): string
	local t = Medical.LINES[key] or key
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, t, ...)
		if ok then
			return s
		end
	end
	return t
end

return Medical
