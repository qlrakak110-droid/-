-- GwangalliPasses/Plate (server): pass #4 과시 패스, 차량 커스텀 번호판.
--   setPlate: Shared/Plates.validate (length / charset) -> TextService FilterStringAsync ->
--   GetNonChatStringForBroadcastAsync (must come back unchanged; a failed filter call refuses) -> unique claim
--   (Data.claimPlate) -> saved + Player attributes GwVanityPlate / GwPlateStyle.
--   applyTo(model, owner): GS.applyPlate (both plates' TextLabels + DrivePlate, so the cop plate lookup reads it)
--   + the style (plate colour / text colour / font / optional frame bars welded to the plate).
--   Every owned car (DriveOwnedCar, DriveOwner = owner, not rental / 시승) that appears in
--   workspace.GwangalliPlayerCars gets it, premium cars included.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Plate = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any, Plates: any
local GS: any = nil
local lastSet: { [Player]: number } = {}

local function owns(player: Player): boolean
	return ctx.Ownership.owns(player, "Flex")
end

-- the text an owner's cars should carry (nil = keep the car's own plate)
function Plate.textFor(player: Player): string?
	if not owns(player) then
		return nil
	end
	local prof = ctx.Data.get(player)
	local t = prof.plate and prof.plate.text
	return if type(t) == "string" and t ~= "" then t else nil
end

function Plate.styleFor(player: Player): string?
	if not owns(player) then
		return nil
	end
	local prof = ctx.Data.get(player)
	return prof.plate and prof.plate.style or nil
end

local function clearFrames(plate: BasePart)
	for _, c in plate:GetChildren() do
		if c.Name == "GwPlateFrame" then
			c:Destroy()
		end
	end
	local model = plate:FindFirstAncestorOfClass("Model")
	if model then
		for _, d in model:GetDescendants() do
			if d.Name == "GwPlateFrame" and d:GetAttribute("GwFor") == plate.Name then
				d:Destroy()
			end
		end
	end
end

local function frameBars(plate: BasePart, style: any)
	local col = Plates.rgb(style.frame)
	local mat = if style.frameMat then (Enum.Material :: any)[style.frameMat] else Enum.Material.Metal
	local s = plate.Size
	local th, depth = 0.06, s.Z + 0.04
	local bars = {
		{ Vector3.new(s.X + th * 2, th, depth), Vector3.new(0, s.Y / 2 + th / 2, 0) },
		{ Vector3.new(s.X + th * 2, th, depth), Vector3.new(0, -s.Y / 2 - th / 2, 0) },
		{ Vector3.new(th, s.Y, depth), Vector3.new(s.X / 2 + th / 2, 0, 0) },
		{ Vector3.new(th, s.Y, depth), Vector3.new(-s.X / 2 - th / 2, 0, 0) },
	}
	for _, b in bars do
		local p = Instance.new("Part")
		p.Name = "GwPlateFrame"
		p:SetAttribute("GwFor", plate.Name)
		p.Size = b[1]
		p.CFrame = plate.CFrame * CFrame.new(b[2])
		p.Color = col
		p.Material = mat
		p.Reflectance = if mat == Enum.Material.Metal then 0.25 else 0
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = plate.Anchored
		local w = Instance.new("WeldConstraint")
		w.Part0 = plate
		w.Part1 = p
		w.Parent = p
		p.Parent = plate.Parent
	end
end

local function styleParts(model: Model, style: any)
	for _, name in { "PlateFront", "PlateRear" } do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			clearFrames(part)
			part.Color = Plates.rgb(style.bg)
			part.Material = Enum.Material.SmoothPlastic
			for _, d in part:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextColor3 = Plates.rgb(style.fg)
					d.Font = Plates.font(style.font)
					local grad = d.Parent and d.Parent:FindFirstChild("GwPlateBg")
					if grad then
						grad:Destroy()
					end
					if style.bg2 and d.Parent and d.Parent:IsA("SurfaceGui") then
						local bg = Instance.new("Frame")
						bg.Name = "GwPlateBg"
						bg.Size = UDim2.fromScale(1, 1)
						bg.BorderSizePixel = 0
						bg.BackgroundColor3 = Color3.new(1, 1, 1)
						bg.ZIndex = 0
						local g = Instance.new("UIGradient")
						g.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Plates.rgb(style.bg)),
							ColorSequenceKeypoint.new(0.16, Plates.rgb(style.bg)),
							ColorSequenceKeypoint.new(0.17, Plates.rgb(style.bg2)),
							ColorSequenceKeypoint.new(1, Plates.rgb(style.bg2)),
						})
						g.Parent = bg
						bg.Parent = d.Parent
						d.ZIndex = 2
					end
					local stroke = d:FindFirstChild("GwPlateGlow")
					if style.glow then
						if not stroke then
							stroke = Instance.new("UIStroke")
							stroke.Name = "GwPlateGlow"
							stroke.Parent = d
						end
						(stroke :: UIStroke).Color = Plates.rgb(style.fg);
						(stroke :: UIStroke).Transparency = 0.45;
						(stroke :: UIStroke).Thickness = 1.5
					elseif stroke then
						stroke:Destroy()
					end
				end
			end
			if style.frame then
				frameBars(part, style)
			end
		end
	end
	model:SetAttribute(P.Attr.PlateStyle, style.id)
end

-- applies the owner's custom plate / style to one car model. defaultStyle: used when the owner has no Flex style.
function Plate.applyTo(model: Model, owner: Player, defaultStyle: string?)
	if not model or not model.Parent or not GS then
		return
	end
	local text = Plate.textFor(owner)
	if text then
		pcall(GS.applyPlate, model, text)
	end
	local sid = Plate.styleFor(owner)
	if not sid and not defaultStyle then
		return
	end
	pcall(styleParts, model, Plates.style(sid or defaultStyle))
end

local function eligible(model: Instance): Player?
	if not model:IsA("Model") then
		return nil
	end
	if model:GetAttribute("DriveOwnedCar") ~= true or model:GetAttribute("DriveRental") == true or model:GetAttribute("DriveTestDrive") ~= nil then
		return nil
	end
	local uid = model:GetAttribute("DriveOwner")
	if type(uid) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(uid)
end

local function filter(text: string, userId: number): (string?, string?)
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(res) ~= "string" then
		return nil, "filter"
	end
	return res, nil
end

local function pushAttrs(player: Player)
	if owns(player) then
		player:SetAttribute(P.Attr.Plate, Plate.textFor(player))
		player:SetAttribute(P.Attr.PlateStyle, Plate.styleFor(player))
	else
		player:SetAttribute(P.Attr.Plate, nil)
		player:SetAttribute(P.Attr.PlateStyle, nil)
	end
end

-- -> { ok, code, message, plate }
function Plate.set(player: Player, text: any, styleId: any): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked", message = Lines.t("locked_tab", Config.PASSES.Flex.Title) }
	end
	local sid = if type(styleId) == "string" and Plates.BY_ID[styleId] then styleId else nil
	local prof = ctx.Data.get(player)
	local current = prof.plate and prof.plate.text
	local ok, code, clean = Plates.validate(text)
	-- style only (same text, or no text yet with an empty box)
	if (not ok and code == "empty") or (ok and clean == current) then
		if sid then
			ctx.Data.update(player, function(pr)
				pr.plate.style = sid
			end)
			pushAttrs(player)
			return { ok = true, message = Lines.t("plate_saved"), plate = current, style = sid }
		end
		if not ok then
			return { ok = false, code = "empty", message = Lines.t("plate_rule", Config.PLATE.MIN, Config.PLATE.MAX) }
		end
	end
	if not ok then
		return { ok = false, code = code, message = Lines.t("plate_rule", Config.PLATE.MIN, Config.PLATE.MAX) }
	end
	local t = os.clock()
	local cd = Config.PLATE.COOLDOWN - (t - (lastSet[player] or -1e9))
	if cd > 0 then
		return { ok = false, code = "cooldown", message = Lines.t("plate_cooldown", math.ceil(cd)) }
	end
	local filtered, ferr = filter(clean, player.UserId)
	if not filtered then
		return { ok = false, code = ferr or "filter", message = Lines.t("plate_filter") }
	end
	if filtered ~= clean then
		return { ok = false, code = "bad", message = Lines.t("plate_bad") }
	end
	local okC, why = ctx.Data.claimPlate(player, clean)
	if not okC then
		return { ok = false, code = why or "taken", message = Lines.t("plate_taken") }
	end
	lastSet[player] = t
	if type(current) == "string" and current ~= clean then
		ctx.Data.releasePlate(player, current)
	end
	ctx.Data.update(player, function(pr)
		pr.plate.text = clean
		if sid then
			pr.plate.style = sid
		end
	end)
	pushAttrs(player)
	return { ok = true, message = Lines.t("plate_saved"), plate = clean, style = sid or Plate.styleFor(player) }
end

function Plate.clear(player: Player): { [string]: any }
	if not owns(player) then
		return { ok = false, code = "locked" }
	end
	local prof = ctx.Data.get(player)
	local current = prof.plate and prof.plate.text
	if current then
		ctx.Data.releasePlate(player, current)
	end
	ctx.Data.update(player, function(pr)
		pr.plate.text = nil
		pr.plate.style = Config.PLATE.DEFAULT_STYLE
	end)
	pushAttrs(player)
	return { ok = true, message = Lines.t("plate_cleared") }
end

function Plate.start(c: any)
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	Plates = P.mod("Plates")
	GS = Util.requireShared(ReplicatedStorage, "GwangalliGarageShared", 90)
	c.Data.onLoaded(function(player: Player)
		pushAttrs(player)
		-- the saved plate is claimed again for this server (another player may not take it meanwhile)
		local text = c.Data.get(player).plate.text
		if type(text) == "string" and text ~= "" then
			task.spawn(c.Data.claimPlate, player, text)
		end
	end)
	c.Ownership.onChanged(function(player: Player, key: string)
		if key == "Flex" then
			pushAttrs(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		lastSet[p] = nil
	end)
	task.spawn(function()
		local f = Util.waitChild(workspace, "GwangalliPlayerCars", "Folder", 600)
		if not f then
			return
		end
		f.ChildAdded:Connect(function(m: Instance)
			task.defer(function()
				local owner = eligible(m)
				if owner and owns(owner) and m:GetAttribute(P.Attr.Premium) == nil then
					Plate.applyTo(m :: Model, owner)
				end
			end)
		end)
	end)
end

return Plate
