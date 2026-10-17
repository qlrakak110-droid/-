--!strict
-- GwangalliBuildingInterior/Hosp_Portal: 숨은 방 관리 (직원 휴게실 · 창고 · 비상계단, 설계 §7.1 · §2.16).
--   방은 병원 바로 아래 (로컬 y -50, 월드 약 -43) 에 이 클라이언트에서만 짓습니다 (맵에 파트 0 개인 곳).
--   * 미리 짓기: 문 10 스터드 안에 오면
--   * go(방, 쪽): 이동 가능 확인 → 홀 문 살짝 열림 → 페이드 → 순간 이동(< 100 스터드) → 방 문 닫힘 → 페이드 아웃
--   * back(방, 쪽): 반대로. 방 안에 있는데 서버가 다른 곳으로 옮기면(쓰러짐 → 입원실 등) 감시가 정리
--   * 아무도 안 쓰는 방은 문에서 30 스터드 멀어지고 20 초 뒤 치움
-- API: new(env) → { registerDoor, unregisterDoors, go, back, inside, bail, clear, reset, tick, sec, status, buildRoom, destroy }

local Lib = require(script.Parent:WaitForChild("Hosp_Lib"))

local Portal = {}

local Geo = Lib.Geo
local SND = Geo.SND

function Portal.new(env: any): any
	local UI = env.UI
	local P: any = {}
	local doors: { [string]: { [string]: any } } = {} -- doors[room][side] = { pos (로컬), crack = fn(alpha) }
	local rooms: { [string]: any } = {} -- rooms[id] = { K, ready, building, farT }
	local inRoom: string? = nil
	local entrySide: string? = nil
	local busy = false
	local Rooms: any = nil
	local folder: Instance? = nil

	local function rooms_mod(): any
		if not Rooms then
			Rooms = require(script.Parent:WaitForChild("Hosp_Rooms"))
		end
		return Rooms
	end

	local function getFolder(): Instance
		if folder and folder.Parent then
			return folder
		end
		local f = Instance.new("Model")
		f.Name = "portal"
		f.Parent = env.folder
		folder = f
		return f
	end

	local function destroyRoom(id: string)
		local r = rooms[id]
		if not r then
			return
		end
		rooms[id] = nil
		if r.K then
			Lib.teardown(r.K)
		end
	end

	-- 방 짓기 (동기). 반환: K
	function P.buildRoom(id: string): any
		local r = rooms[id]
		if r and (r.ready or r.building) then
			return r.K
		end
		local q = env.quality
		local K = Lib.zone("room_" .. id, getFolder(), Geo.BUDGET.portal, q)
		K.hostPts = {} -- 서버 앵커와 겹칠 일 없음 (지하)
		r = { K = K, ready = false, building = true, farT = nil }
		rooms[id] = r
		local mod = rooms_mod()
		local ok, err = pcall(mod[id], K, env, P)
		K:finish()
		if not ok then
			warn("[HospitalPlus] room " .. id .. ": " .. tostring(err))
		end
		r.building = false
		if rooms[id] ~= r then
			Lib.teardown(K)
			return nil
		end
		r.ready = true
		return K
	end

	local function ensure(id: string, timeout: number): boolean
		local r = rooms[id]
		if not r then
			task.spawn(P.buildRoom, id)
		end
		local t0 = os.clock()
		while os.clock() - t0 < timeout do
			r = rooms[id]
			if r and r.ready then
				return true
			end
			task.wait(0.05)
		end
		r = rooms[id]
		return r ~= nil and r.ready
	end

	function P.registerDoor(room: string, side: string, pos: Vector3, crack: (number) -> ())
		doors[room] = doors[room] or {}
		doors[room][side] = { pos = pos, crack = crack }
	end
	function P.unregisterDoors()
		doors = {}
	end

	local function crack(room: string, side: string, a: number)
		local d = doors[room] and doors[room][side]
		if d then
			pcall(d.crack, a)
		end
	end
	local function roomDoor(id: string, side: string, a: number)
		local r = rooms[id]
		local fx = r and r.K and r.K.doorFx and r.K.doorFx[side]
		if fx then
			pcall(fx, a)
		end
	end

	function P.inside(): boolean
		return inRoom ~= nil
	end

	-- 방으로 들어가기. side = "hall" (1F/2F 문) | "roof" (옥상 문, 비상계단만)
	function P.go(id: string, side: string)
		if busy or inRoom then
			return
		end
		local ok, why = Lib.canTravel()
		if not ok then
			UI.toast(why or "지금은 이동할 수 없어요", 2.4)
			return
		end
		local spec = Geo.ROOMS[id]
		if not spec then
			return
		end
		busy = true
		task.spawn(function()
			crack(id, side, 1)
			Lib.sfx2d(SND.click, { vol = 0.3, speed = 0.7 })
			UI.fade(true, 0.22, spec.label)
			local ready = ensure(id, 3.0)
			local ok2 = Lib.canTravel()
			if not ready or not ok2 then
				crack(id, side, 0)
				UI.fade(false, 0.3)
				busy = false
				if not ready then
					UI.toast("문이 잠겨 있어요. 잠시 뒤에 다시 눌러 주세요", 2.4)
				end
				return
			end
			local dest = if id == "stair" and side == "roof" then spec.insideTop else spec.inside
			roomDoor(id, if side == "roof" then "roof" else "hall", 1)
			Lib.teleport(dest)
			inRoom = id
			entrySide = side
			crack(id, side, 0)
			task.wait(0.15)
			roomDoor(id, if side == "roof" then "roof" else "hall", 0)
			Lib.sfx2d(SND.thunk, { vol = 0.4, speed = 0.7 })
			UI.fade(false, 0.35)
			UI.toast(spec.label, 1.8)
			busy = false
		end)
	end

	-- 방에서 나가기. side = "hall" | "roof"
	function P.back(id: string, side: string)
		if busy or inRoom ~= id then
			return
		end
		local spec = Geo.ROOMS[id]
		busy = true
		task.spawn(function()
			roomDoor(id, side, 1)
			UI.fade(true, 0.22, if side == "roof" then "옥상" elseif id == "stair" then "2층 계단홀" else "1층 후면 홀")
			crack(id, side, 1)
			local dest = if id == "stair" then (if side == "roof" then spec.roof else spec.hall) else spec.hall
			Lib.teleport(dest)
			inRoom = nil
			entrySide = nil
			roomDoor(id, side, 0)
			task.wait(0.15)
			crack(id, side, 0)
			Lib.sfx2d(SND.thunk, { vol = 0.35, speed = 0.75 })
			UI.fade(false, 0.35)
			busy = false
			local r = rooms[id]
			if r then
				r.farT = nil
			end
		end)
	end

	-- 바로 밖으로 (멈출 때 · 비활성화)
	function P.bail()
		local id = inRoom
		if not id then
			return
		end
		local spec = Geo.ROOMS[id]
		local side = entrySide or "hall"
		local dest = if id == "stair" then (if side == "roof" then spec.roof else spec.hall) else spec.hall
		pcall(Lib.teleport, dest)
		inRoom = nil
		entrySide = nil
		busy = false
		UI.unfade()
	end

	function P.reset()
		inRoom = nil
		entrySide = nil
		busy = false
		UI.unfade()
	end

	function P.clear()
		if inRoom then
			return
		end
		for id in rooms do
			destroyRoom(id)
		end
	end

	local function boxDist(id: string, l: Vector3): number
		local b = Geo.ROOMS[id].box
		local dx = math.max(b.min.X - l.X, 0, l.X - b.max.X)
		local dy = math.max(b.min.Y - l.Y, 0, l.Y - b.max.Y)
		local dz = math.max(b.min.Z - l.Z, 0, l.Z - b.max.Z)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	-- 10 Hz: 미리 짓기 · 감시 · 방 애니메이션
	local lastWatch = 0
	function P.tick(t: number, dt: number)
		local me = Lib.me()
		-- 감시: 방에 있다고 했는데 멀리 있으면 (서버 이동 · 리스폰) 정리
		if inRoom and not busy and os.clock() - lastWatch > 0.25 then
			lastWatch = os.clock()
			if not me or boxDist(inRoom, me) > 25 then
				inRoom = nil
				entrySide = nil
				UI.unfade()
			end
		end
		if me and not busy then
			for id, sides in doors do
				for _, d in sides do
					if (me - d.pos).Magnitude < 10 and not rooms[id] then
						-- 한 번에 방 하나: 안 쓰는 다른 방은 치움
						for other in rooms do
							if other ~= id and other ~= inRoom then
								destroyRoom(other)
							end
						end
						task.spawn(P.buildRoom, id)
					end
				end
			end
		end
		for _, r in rooms do
			if r.ready and r.K then
				for _, fn in r.K.anims do
					local ok = pcall(fn, t, dt)
					if not ok then
						break
					end
				end
			end
		end
	end

	-- 1 Hz: 안 쓰는 방 치우기 + 방의 초 단위 작업
	function P.sec(t: number)
		local me = Lib.me()
		for id, r in rooms do
			if r.ready and r.K then
				for _, fn in r.K.secs do
					pcall(fn, t)
				end
			end
			if id ~= inRoom and r.ready then
				local near = false
				if me then
					if boxDist(id, me) < 30 then
						near = true
					end
					for _, d in doors[id] or {} do
						if (me - d.pos).Magnitude < 30 then
							near = true
						end
					end
				end
				if near then
					r.farT = nil
				else
					r.farT = r.farT or os.clock()
					if os.clock() - r.farT > 20 then
						destroyRoom(id)
					end
				end
			end
		end
	end

	function P.status(): string
		local n = 0
		local parts = 0
		for _, r in rooms do
			n += 1
			if r.K then
				parts += #r.K.parts
			end
		end
		return string.format("portal rooms=%d parts=%d in=%s", n, parts, tostring(inRoom))
	end

	function P.destroy()
		for id in rooms do
			destroyRoom(id)
		end
		if folder then
			folder:Destroy()
			folder = nil
		end
	end

	return P
end

return Portal
