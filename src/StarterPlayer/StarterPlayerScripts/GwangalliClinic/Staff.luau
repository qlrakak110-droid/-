-- GwangalliClinic/Staff (client): animates the clinic staff from the shared State ("Act_<id>" =
-- "act|userId|t", written by the server) with GwangalliAnim's rig controller (local Motor6D layers):
--   our rigs (Workspace.GwangalliClinic.Staff): 원무과 김주임 / 이주임 (desk1 / desk2), 간호사 최선생 (nurse2),
--     약사 정약사 (pharm), 검진센터 한선생 (check) — base act + talk / listen / beckon / give / cook, head turned
--     toward the patient
--   the map's 의사 김선생 (doctor): head turn + nod only (Health posed him seated; we never touch his limbs)
--   the map's 간호사 박선생: left alone (Health's own injection choreography moves her arm)
-- Name tags are BillboardGuis in PlayerGui (Adornee = the rig's head).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Staff = {}

local ctx: any
local S: any
local C: any
local Ui: any
local Anim: any = nil
local player = Players.LocalPlayer

local rigs: { [string]: { model: Model, ctl: any, base: string, tag: BillboardGui?, revertAt: number? } } = {}
local tagFolder: Folder

local BASE = { desk1 = "teller", desk2 = "teller", nurse2 = "clipboard", pharm = "teller", check = "teller", doctor = nil }

local function headOf(uid: number): Vector3?
	if uid == 0 then
		return nil
	end
	local p = Players:GetPlayerByUserId(uid)
	local ch = p and p.Character
	local head = ch and ch:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

local function parseAct(s: any): (string, number, number)
	if type(s) ~= "string" then
		return "idle", 0, 0
	end
	local a, u, t = string.match(s, "^([%w_]+)|(%d+)|([%d%.]+)$")
	return a or "idle", tonumber(u) or 0, tonumber(t) or 0
end

local function applyAct(id: string)
	local r = rigs[id]
	if not r or not r.ctl then
		return
	end
	local act, uid = parseAct(ctx.state:GetAttribute("Act_" .. id))
	local ctl = r.ctl
	local look = headOf(uid)
	if id == "doctor" then
		pcall(function()
			ctl:look(look)
			if act == "talk" or act == "listen" then
				ctl:emote("nod")
			end
		end)
		return
	end
	pcall(function()
		if act == "talk" then
			ctl:setAct(r.base)
			ctl:gesture("talk")
			ctl:look(look)
		elseif act == "listen" then
			ctl:setAct(r.base)
			ctl:gesture("listen")
			ctl:look(look)
		elseif act == "beckon" then
			ctl:setAct(r.base)
			ctl:look(look)
			ctl:emote("beckon")
			r.revertAt = os.clock() + 3
		elseif act == "give" then
			ctl:setAct(r.base)
			ctl:look(look)
			ctl:emote("give")
			r.revertAt = os.clock() + 3.5
		elseif act == "cook" then
			ctl:setAct("typing")
			ctl:look(nil)
		elseif act == "iv" or act == "inject" then
			ctl:setAct(r.base)
			ctl:look(look)
			ctl:emote("nod")
		else
			ctl:setAct(if act ~= "idle" and Anim.ACTS and Anim.ACTS[act] then act else r.base)
			ctl:gesture(nil)
			ctl:look(nil)
		end
	end)
end

local function makeTag(model: Model, text: string): BillboardGui?
	local head = model:FindFirstChild("Head")
	if not head then
		return nil
	end
	local bb = Ui.new("BillboardGui", {
		Name = "Tag_" .. model.Name,
		Adornee = head,
		Size = UDim2.fromOffset(150, 26),
		StudsOffset = Vector3.new(0, 1.6, 0),
		AlwaysOnTop = false,
		MaxDistance = 36,
		LightInfluence = 0,
		ResetOnSpawn = false,
	}, tagFolder)
	local l = Ui.new("TextLabel", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.12,
		Size = UDim2.fromScale(1, 1),
		Font = Ui.F.bold,
		TextSize = 13,
		TextColor3 = Ui.C.tealDD,
		Text = text,
	}, bb)
	Ui.corner(l, 13)
	return bb
end

local function addRig(id: string, model: Model, tagText: string?)
	if rigs[id] and rigs[id].model == model then
		return
	end
	if rigs[id] and rigs[id].tag then
		(rigs[id].tag :: BillboardGui):Destroy()
	end
	local ok, ctl = pcall(Anim.rig, model)
	if not ok then
		return
	end
	local base = BASE[id] or "idle"
	rigs[id] = { model = model, ctl = ctl, base = base, tag = if tagText then makeTag(model, tagText) else nil }
	if id ~= "doctor" then
		pcall(function()
			ctl:setAct(base)
		end)
	end
	applyAct(id)
	model.Destroying:Connect(function()
		local r = rigs[id]
		if r and r.model == model then
			if r.tag then
				r.tag:Destroy()
			end
			rigs[id] = nil
		end
	end)
end

local function scan()
	local world = workspace:FindFirstChild(S.NAMES.World)
	local staffFolder = world and world:FindFirstChild(S.NAMES.Staff)
	if staffFolder then
		for _, m in staffFolder:GetChildren() do
			if m:IsA("Model") then
				local id = m:GetAttribute(S.NAMES.AttrStaff)
				if type(id) == "string" and (not rigs[id] or rigs[id].model ~= m) and m:FindFirstChild("Head") then
					addRig(id, m, m:GetAttribute("NpcName") or m.Name)
				end
			end
		end
	end
	if not rigs.doctor then
		local cur: Instance? = workspace
		for _, n in C.Venue.Path do
			cur = cur and cur:FindFirstChild(n)
		end
		local staff = cur and cur:FindFirstChild("Staff")
		local doc = staff and staff:FindFirstChild("의사 김선생")
		if doc and doc:IsA("Model") and doc:FindFirstChild("Head") then
			addRig("doctor", doc, nil)
		end
	end
end

function Staff.init(c: any)
	ctx = c
	S = c.S
	C = c.C
	Ui = c.Ui
	local m = ReplicatedStorage:FindFirstChild("GwangalliAnim")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" and type(res.rig) == "function" then
			Anim = res
		end
	end
	if not Anim then
		return
	end
	local pg = player:WaitForChild("PlayerGui")
	tagFolder = Instance.new("Folder")
	tagFolder.Name = "GwangalliClinicTags"
	tagFolder.Parent = pg
	ctx.state.AttributeChanged:Connect(function(attr: string)
		local id = string.match(attr, "^Act_(.+)$")
		if id and rigs[id] then
			applyAct(id)
		end
	end)
	task.spawn(function()
		while true do
			pcall(scan)
			if not tagFolder.Parent then
				tagFolder = Instance.new("Folder")
				tagFolder.Name = "GwangalliClinicTags"
				tagFolder.Parent = pg
				for id, r in rigs do
					if r.tag then
						r.tag = makeTag(r.model, r.model:GetAttribute("NpcName") or r.model.Name)
					end
					local _ = id
				end
			end
			task.wait(3)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		local cp = cam and cam.CFrame.Position
		for id, r in rigs do
			local head = r.model:FindFirstChild("Head")
			if head and head:IsA("BasePart") and cp then
				local d = (head.Position - cp).Magnitude
				if d < 75 then
					if r.revertAt and os.clock() >= r.revertAt then
						r.revertAt = nil
						applyAct(id)
					end
					pcall(function()
						r.ctl:setDetail(if d < 40 then 2 else 1)
						r.ctl:step()
					end)
				end
			end
		end
	end)
end

return Staff
