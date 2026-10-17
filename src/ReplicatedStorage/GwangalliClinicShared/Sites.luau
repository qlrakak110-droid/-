-- GwangalliClinicShared/Sites: where things are in the map clinic (광안 메디컬 의원, Workspace.Gwangalli.hospital).
-- Paths are relative to the venue model ("1F/Lobby/TicketKiosk"); `at` = world offset from that part's
-- position (the venue is rotated ~178° about Y, so offsets are given in WORLD axes, read from the place);
-- `fallback` = world position used when the part is missing (streamed out / renamed). Y values that say
-- "F1"/"F2" are put on the 1st / 2nd floor height (Config.Venue.Floor1 / Floor2).
--
--   Sites.ANCHORS[name] = { path, at?, floor?, y?, seat? ("self" | "near"), fallback, label, kind }
--   Sites.STAFF[id]     = { at = Vector3 (feet), look = Vector3 (direction), floor }
--   Sites.SCREENS       = { { path, kind, viewer = Vector3 } }  (client overlays)
--   Sites.WARDS         = { { bed = path, panel = path } }

local Sites = {}

local V = Vector3.new

Sites.ANCHORS = {
	Kiosk = { path = "1F/Lobby/KioskScreen", at = V(0, 0, -1.7), floor = 1, y = 2.6, fallback = V(-500.5, 9.5, 279.7), label = "무인 접수 키오스크", kind = "kiosk" },
	Win1 = { path = "1F/Lobby/ReceptionDesk/FrontPanel", at = V(5, 0, -2.3), floor = 1, y = 2.6, fallback = V(-509.6, 9.5, 281.8), label = "1번 창구", kind = "window" },
	Win2 = { path = "1F/Lobby/ReceptionDesk/FrontPanel", at = V(-5, 0, -2.3), floor = 1, y = 2.6, fallback = V(-519.6, 9.5, 281.5), label = "2번 창구", kind = "window" },
	ConsultSeat = { path = "1F/ConsultRoom/Seat", seat = "self", at = V(0, 2, 0), fallback = V(-554.5, 10.4, 280.9), label = "진료실 1 · 내과", kind = "consult" },
	ExamBed = { path = "1F/ConsultRoom/ExamBed/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-569.6, 10.8, 283.2), label = "진찰대", kind = "bed" },
	TreatBed1 = { path = "1F/TreatmentRoom/TreatBed1/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-465.3, 10.8, 308.6), label = "주사실 1번 침대", kind = "bed" },
	TreatBed2 = { path = "1F/TreatmentRoom/TreatBed2/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-479.3, 10.8, 308.2), label = "주사실 2번 침대", kind = "bed" },
	Pharmacy = { path = "1F/PharmacyCorner/PharmSign", at = V(0, 0, -2.2), floor = 1, y = 2.6, fallback = V(-545.0, 9.5, 294.3), label = "원내 약국", kind = "pharmacy" },
	WaitArea = { path = "1F/WaitingRoom/LEDScreen", at = V(0, 0, -12), floor = 1, y = 2.6, fallback = V(-468.8, 9.5, 281.0), label = "대기실", kind = "wait" },
	CheckDesk = { path = "2F/CheckupCenter/DeskTop", at = V(0, 0, -3.3), floor = 2, y = 2.6, fallback = V(-535.1, 23.6, 297.3), label = "건강검진센터 접수", kind = "checkdesk" },
	CheckScale = { path = "2F/CheckupCenter/Scale", at = V(0, 0, 0), floor = 2, y = 2.6, fallback = V(-548.6, 23.6, 300.0), label = "신장 · 체중계", kind = "station", station = "height" },
	CheckBP = { path = "2F/CheckupCenter/BPMachine", seat = "near", at = V(0, 2, 0), fallback = V(-555.9, 24.6, 293.8), label = "자동 혈압계", kind = "station", station = "bp" },
	CheckEye = { path = "2F/CheckupCenter/EyeLine", at = V(0, 0, 0), floor = 2, y = 2.6, fallback = V(-564.6, 23.6, 308.0), label = "시력 검사선", kind = "station", station = "eye" },
	CheckEar = { path = "2F/CheckupCenter/HearingBooth", at = V(0, 0, -5.6), floor = 2, y = 2.6, fallback = V(-532.0, 23.6, 323.4), label = "청력 검사 부스", kind = "station", station = "ear" },
	CheckECG = { path = "2F/CheckupCenter/CheckupBed/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-566.1, 24.9, 329.3), label = "심전도 검사대", kind = "station", station = "ecg" },
	Ward1A = { path = "2F/Ward_201/WardBed_A/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-466.5, 24.9, 279.1), label = "201호 A 침대", kind = "ward" },
	Ward1B = { path = "2F/Ward_201/WardBed_B/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-488.5, 24.9, 278.3), label = "201호 B 침대", kind = "ward" },
	Ward2A = { path = "2F/Ward_202/WardBed_A/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-540.2, 24.9, 276.6), label = "202호 A 침대", kind = "ward" },
	Ward2B = { path = "2F/Ward_202/WardBed_B/BedSeat", seat = "self", at = V(0, 2, 0), fallback = V(-562.2, 24.9, 275.9), label = "202호 B 침대", kind = "ward" },
	Call1A = { path = "2F/Ward_201", panelNear = V(-464.67, 26.55, 291.09), at = V(0, 0, -0.8), fallback = V(-464.7, 26.0, 290.3), label = "201호 간호사 호출", kind = "call", ward = "Ward1A" },
	Call1B = { path = "2F/Ward_201", panelNear = V(-486.66, 26.55, 290.37), at = V(0, 0, -0.8), fallback = V(-486.7, 26.0, 289.6), label = "201호 간호사 호출", kind = "call", ward = "Ward1B" },
	Call2A = { path = "2F/Ward_202", panelNear = V(-538.43, 26.55, 288.68), at = V(0, 0, -0.8), fallback = V(-538.4, 26.0, 287.9), label = "202호 간호사 호출", kind = "call", ward = "Ward2A" },
	Call2B = { path = "2F/Ward_202", panelNear = V(-560.42, 26.55, 287.96), at = V(0, 0, -0.8), fallback = V(-560.4, 26.0, 287.2), label = "202호 간호사 호출", kind = "call", ward = "Ward2B" },
}

-- map parts whose positions help the client (IV bags for the drip, staff props)
Sites.PARTS = {
	IVBag1 = { path = "1F/TreatmentRoom/TreatBed1/IVBag", fallback = V(-467.76, 12.4, 312.13) },
	IVBag2 = { path = "1F/TreatmentRoom/TreatBed2/IVBag", fallback = V(-481.75, 12.4, 311.67) },
	Mattress1 = { path = "1F/TreatmentRoom/TreatBed1/Mattress", fallback = V(-465.36, 8.35, 309.2) },
	Mattress2 = { path = "1F/TreatmentRoom/TreatBed2/Mattress", fallback = V(-479.36, 8.35, 308.75) },
	MattressECG = { path = "2F/CheckupCenter/CheckupBed/Mattress", fallback = V(-566.1, 22.5, 329.9) },
	PillowECG = { path = "2F/CheckupCenter/CheckupBed/Pillow", fallback = V(-566.2, 23.05, 332.1) },
	Pillow1 = { path = "1F/TreatmentRoom/TreatBed1/Pillow", fallback = V(-465.43, 8.9, 311.4) },
	Pillow2 = { path = "1F/TreatmentRoom/TreatBed2/Pillow", fallback = V(-479.43, 8.9, 310.95) },
	Doctor = { path = "Staff/의사 김선생", fallback = V(-554.21, 8.95, 272.48) },
	Nurse = { path = "Staff/간호사 박선생", fallback = V(-565.79, 9.75, 283.9) },
	DoctorMonitor = { path = "1F/ConsultRoom/DoctorDesk/Monitor", fallback = V(-557.93, 11.15, 276.11) },
	Dispenser = { path = "1F/PharmacyCorner/DispensingMachine", fallback = V(-564.68, 10.6, 317.21) },
}

-- where our staff stand (feet position, facing)
Sites.STAFF = {
	desk1 = { at = V(-509.6, 0, 287.0), floor = 1, look = V(0, 0, -1), act = "teller", window = 1 },
	desk2 = { at = V(-519.6, 0, 286.8), floor = 1, look = V(0, 0, -1), act = "teller", window = 2 },
	nurse2 = { at = V(-472.3, 0, 311.6), floor = 1, look = V(0, 0, -1), act = "clipboard" },
	pharm = { at = V(-545.0, 0, 300.2), floor = 1, look = V(0, 0, -1), act = "teller" },
	check = { at = V(-535.1, 0, 302.9), floor = 2, look = V(0, 0, -1), act = "teller" },
}

-- world displays the client draws on (SurfaceGui in PlayerGui, Adornee = the part)
-- (at / size: our own local screen when the map part does not exist at all)
Sites.SCREENS = {
	{ path = "1F/Lobby/LEDScreen", kind = "call", viewer = V(-508, 10, 272), at = V(-510.81, 15.3, 291.6), size = V(13, 3, 0.2) },
	{ path = "1F/WaitingRoom/LEDScreen", kind = "wait", viewer = V(-462, 10, 278), at = V(-468.84, 14.5, 292.95), size = V(10, 5.6, 0.2) },
	{ path = "1F/PharmacyCorner/PrescriptionScreen", kind = "rx", viewer = V(-538, 10, 291), at = V(-535.48, 11.75, 299.25), size = V(4.4, 2.3, 0.1) },
	{ path = "2F/Lounge/LEDScreen", kind = "wait", viewer = V(-494, 24, 300) },
}

-- the clinic's centre and the doctor's side of the consult room (camera framing)
Sites.CONSULT_CAM = { eye = V(-551.6, 12.6, 284.6), focus = V(-554.3, 10.2, 276.4) }

return Sites
