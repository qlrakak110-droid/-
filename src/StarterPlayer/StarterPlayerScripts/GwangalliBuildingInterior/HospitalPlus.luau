--!strict
-- GwangalliBuildingInterior/HospitalPlus: 광안 메디컬 의원 시설 레이어 (이 클라이언트에서만).
--   "드나들 수 있는 문" 전부 + 실제로 쓰는 시설: 남/여 화장실 (잠기는 칸 · 소변기 · 세면대 · 핸드드라이어 ·
--   기저귀 교환대 · 동작 감지 조명), 진짜 엘리베이터 1F / 2F / R, 응급실 출입구, 비상구, 2F 계단홀 통로,
--   직원 휴게실 · 창고 · 비상계단 (숨은 방), 유리 자동문 + 진료 중 표시등, 옥상 정원 + 광안대교 망원경, 안내 표지.
-- init.client.luau 가 시작할 때 require 하고 start(ctx) 를 부름. ctx = { root, focus, limits, dbg, script, Scan }.
-- 맵은 읽기 전용: 맵 파트는 로컬에서만 숨기거나 충돌을 끄고, 멀어지거나 멈추면 되돌림.
-- 서버 · 다른 플레이어 · 게임 판정(돈 · 저장 · NPC 걷기 격자)에는 영향 없음.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 다른 방 빌더(T_clinic 등)가 비워 둘 공간: yield 전에 바로 등록 (Scan · Hosp_Geo 는 같은 폴더에 이미 있음)
local Scan = require(script.Parent:WaitForChild("Scan")) :: any
local Geo = require(script.Parent:WaitForChild("Hosp_Geo")) :: any
for _, k in Geo.KEEPS do
	Scan.addWorldKeep(k.min, k.max, k.kind)
end

local M = {}

-- 구역 순서 (거리에서 보이는 것부터)
local ORDER = { "exits", "lift", "hall1", "doors", "level2", "roof" }
local MODS = { exits = "Hosp_Exits", lift = "Hosp_Elevator", hall1 = "Hosp_Restroom", doors = "Hosp_Doors", level2 = "Hosp_Signs", roof = "Hosp_Roof" }

local state: any = nil

local function log(...)
	if state and state.ctx and state.ctx.dbg then
		pcall(state.ctx.dbg, "[HospitalPlus]", ...)
	end
end

local function qualityOf(ctx: any): string
	local ok, _, mp = pcall(function()
		return ctx.limits()
	end)
	local maxParts = if ok and type(mp) == "number" then mp else 2600
	return if maxParts < 1500 then "low" elseif maxParts < 2300 then "mid" else "high"
end

-- 맵 위치 검증: GroundBack 이 기대 위치에서 0.5 이상 벗어나 있으면 HF 를 실제 파트 기준으로
local function validateFrame(Lib: any): boolean
	local gb = Lib.find(Geo.PARTS.groundBack, 6)
	if not gb then
		return false
	end
	local expW = Geo.W(Geo.GB_LOCAL.X, Geo.GB_LOCAL.Y, Geo.GB_LOCAL.Z)
	if (gb.Position - expW).Magnitude > 0.5 then
		local expected = Geo.HF * CFrame.new(Geo.GB_LOCAL) * CFrame.Angles(0, math.pi, 0)
		Geo.HF = gb.CFrame * (expected:Inverse() * Geo.HF)
		log("frame adjusted from GroundBack", tostring(gb.Position))
	end
	return true
end

-- 형제 모듈 (정적 require: Rojo · 미리보기 번들러 모두 같은 규약)
local LOADERS: { [string]: () -> any } = {
	Hosp_Lib = function()
		return require(script.Parent:WaitForChild("Hosp_Lib"))
	end,
	Hosp_UI = function()
		return require(script.Parent:WaitForChild("Hosp_UI"))
	end,
	Hosp_Portal = function()
		return require(script.Parent:WaitForChild("Hosp_Portal"))
	end,
	Hosp_Exits = function()
		return require(script.Parent:WaitForChild("Hosp_Exits"))
	end,
	Hosp_Elevator = function()
		return require(script.Parent:WaitForChild("Hosp_Elevator"))
	end,
	Hosp_Restroom = function()
		return require(script.Parent:WaitForChild("Hosp_Restroom"))
	end,
	Hosp_Doors = function()
		return require(script.Parent:WaitForChild("Hosp_Doors"))
	end,
	Hosp_Signs = function()
		return require(script.Parent:WaitForChild("Hosp_Signs"))
	end,
	Hosp_Roof = function()
		return require(script.Parent:WaitForChild("Hosp_Roof"))
	end,
}
local function req(name: string): any
	return LOADERS[name]()
end

local function buildZone(z: string)
	local s = state
	local mod = s.mods[z]
	local Lib = s.Lib
	if not mod then
		return
	end
	if type(mod.ready) == "function" then
		local ok, r = pcall(mod.ready, s.env)
		if not ok or not r then
			return -- 맵 부품이 아직 스트리밍 안 됨: 다음에 다시
		end
	end
	local K = Lib.zone(z, s.folder, Geo.BUDGET[z], s.quality)
	s.zones[z] = K
	local t0 = os.clock()
	local ok, err = pcall(mod.build, K, s.env)
	K:finish()
	if not ok then
		warn("[HospitalPlus] build " .. z .. ": " .. tostring(err))
	end
	if s.zones[z] ~= K then
		Lib.teardown(K) -- 짓는 동안 정리 요청
		return
	end
	log(string.format("built %s: %d parts, %d lights, %d prompts, %d blocked, %d hidden, %.0f ms", z, #K.parts, #K.lights, #K.prompts, K.blocked, (function()
		local n = 0
		for _ in K.hidden do
			n += 1
		end
		return n
	end)(), (os.clock() - t0) * 1000))
	for _, l in K.log do
		log("  " .. l)
	end
end

local function tearZone(z: string)
	local s = state
	local K = s.zones[z]
	if not K then
		return
	end
	s.zones[z] = nil
	local mod = s.mods[z]
	if mod and type(mod.unbuild) == "function" then
		pcall(mod.unbuild, K, s.env)
	end
	s.Lib.teardown(K)
	log("tore down", z)
end

local function tearAll()
	local s = state
	for i = #ORDER, 1, -1 do
		tearZone(ORDER[i])
	end
	if s.hub.portal then
		s.hub.portal.clear()
	end
end

local function want(z: string, d: number, pos: Vector3, inPortal: boolean): boolean
	if z == "roof" then
		return d < Geo.ROOF_R or pos.Y > Geo.W(0, 18, 0).Y or inPortal
	end
	return true
end

local function directorTick()
	local s = state
	local ctx = s.ctx
	if ctx.script and (ctx.script:GetAttribute("Enabled") == false or ctx.script:GetAttribute("HospitalPlus") == false) then
		if next(s.zones) then
			if s.hub.portal and s.hub.portal.inside() then
				s.hub.portal.bail()
			end
			tearAll()
		end
		return
	end
	local okP, pos = pcall(ctx.focus)
	if not okP or typeof(pos) ~= "Vector3" then
		return
	end
	local p: Vector3 = pos
	local d = Vector3.new(p.X - Geo.CENTER.X, 0, p.Z - Geo.CENTER.Z).Magnitude
	local inPortal = s.hub.portal ~= nil and s.hub.portal.inside()
	if d < Geo.BUILD_R or inPortal then
		if not s.frameOk then
			if not s.Lib.hospital() then
				return
			end
			s.frameOk = validateFrame(s.Lib)
			if not s.frameOk then
				return
			end
		end
		if s.building then
			return
		end
		for _, z in ORDER do
			if not s.zones[z] and want(z, d, p, inPortal) then
				s.building = true
				task.spawn(function()
					buildZone(z)
					s.building = false
				end)
				return
			end
		end
		-- 옥상은 멀어지면 먼저 치움 (부품이 가장 많음)
		if s.zones.roof and not want("roof", d - 30, p, inPortal) and p.Y < Geo.W(0, 12, 0).Y then
			tearZone("roof")
		end
	elseif d > Geo.TEAR_R and not inPortal then
		if next(s.zones) then
			tearAll()
		end
	end
end

local function animStep(dt: number)
	local s = state
	s.animAcc += dt
	s.secAcc += dt
	s.t += dt
	if s.animAcc >= 0.1 then
		local step = s.animAcc
		s.animAcc = 0
		for _, z in ORDER do
			local K = s.zones[z]
			if K then
				for _, fn in K.anims do
					local ok, err = pcall(fn, s.t, step)
					if not ok then
						log("anim", z, err)
					end
				end
			end
		end
		if s.hub.portal then
			local ok, err = pcall(s.hub.portal.tick, s.t, step)
			if not ok then
				log("portal tick", err)
			end
		end
	end
	if s.secAcc >= 1 then
		s.secAcc = 0
		for _, z in ORDER do
			local K = s.zones[z]
			if K then
				for _, fn in K.secs do
					local ok, err = pcall(fn, s.t)
					if not ok then
						log("sec", z, err)
					end
				end
			end
		end
		if s.hub.portal then
			pcall(s.hub.portal.sec, s.t)
		end
	end
end

local function makeState(ctx: any): any
	local Lib = req("Hosp_Lib")
	local UI = req("Hosp_UI")
	local s: any = {
		ctx = ctx,
		Lib = Lib,
		UI = UI,
		zones = {},
		mods = {},
		building = false,
		frameOk = false,
		animAcc = 0,
		secAcc = 0,
		t = 0,
		conns = {},
		quality = qualityOf(ctx),
		hub = {},
	}
	local folder = Instance.new("Model")
	folder.Name = "HospitalPlus"
	folder:SetAttribute("LOD", "near")
	folder.Parent = ctx.root
	s.folder = folder
	s.env = { Lib = Lib, Geo = Geo, UI = UI, ctx = ctx, hub = s.hub, quality = s.quality, folder = folder }
	for z, name in MODS do
		local ok, mod = pcall(req, name)
		if ok and type(mod) == "table" then
			s.mods[z] = mod
		else
			warn("[HospitalPlus] module " .. name .. ": " .. tostring(mod))
		end
	end
	local okP, Portal = pcall(req, "Hosp_Portal")
	if okP and type(Portal) == "table" then
		s.hub.portal = Portal.new(s.env)
	else
		warn("[HospitalPlus] Hosp_Portal: " .. tostring(Portal))
	end
	return s
end

function M.start(ctx: any)
	if state then
		return
	end
	state = makeState(ctx)
	local s = state
	table.insert(s.conns, RunService.Heartbeat:Connect(function(dt)
		if state == s then
			animStep(dt)
		end
	end))
	if ctx.script then
		table.insert(s.conns, ctx.script.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				M.stop()
			end
		end))
	end
	local pl = Players.LocalPlayer
	if pl then
		table.insert(s.conns, pl.CharacterAdded:Connect(function()
			if state ~= s then
				return
			end
			if s.hub.portal then
				s.hub.portal.reset()
			end
			if s.hub.lift then
				pcall(s.hub.lift.reset)
			end
		end))
	end
	task.spawn(function()
		while state == s do
			local ok, err = pcall(directorTick)
			if not ok then
				warn("[HospitalPlus] " .. tostring(err))
			end
			task.wait(0.25)
		end
	end)
	log("started, quality", s.quality)
end

function M.stop()
	local s = state
	if not s then
		return
	end
	if s.hub.portal and s.hub.portal.inside() then
		pcall(s.hub.portal.bail)
	end
	tearAll()
	if s.hub.portal then
		pcall(s.hub.portal.destroy)
	end
	for _, c in s.conns do
		c:Disconnect()
	end
	s.UI.destroy()
	if s.folder then
		s.folder:Destroy()
	end
	state = nil
end

function M.status(): string
	local s = state
	if not s then
		return "HospitalPlus: stopped"
	end
	local out = { "HospitalPlus [" .. s.quality .. "]" }
	local total = 0
	for _, z in ORDER do
		local K = s.zones[z]
		if K then
			total += #K.parts
			table.insert(out, string.format("%s=%d/%dL", z, #K.parts, #K.lights))
		end
	end
	if s.hub.portal then
		table.insert(out, s.hub.portal.status())
	end
	table.insert(out, "total=" .. total)
	return table.concat(out, " ")
end

-- 오프라인 미리보기: 모든 구역 + 숨은 방 3 개를 한 번에 (UI · 루프 없음). 반환: { [zone] = K }
function M._buildAll(ctx: any): any
	state = makeState(ctx)
	local s = state
	s.frameOk = validateFrame(s.Lib)
	for _, z in ORDER do
		buildZone(z)
	end
	if s.hub.portal then
		for _, id in { "staff", "store", "stair" } do
			local K = s.hub.portal.buildRoom(id)
			if K then
				s.zones["portal_" .. id] = K
			end
		end
	end
	return s.zones
end

return M
