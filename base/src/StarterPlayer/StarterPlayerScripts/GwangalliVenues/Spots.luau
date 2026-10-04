-- GwangalliVenues/Spots: food menus (PC방 counter / seat, 볼링장 분식), order feedback, punch score pop.
--   Spots.openMenu(menuId)  (PC uses it from the seat overlay)
-- Events: menu {menu, items}, orderReady {item}, ate {item, applied}, punch {score, best, rank}.

local Spots = {}

local C: any
local K: any
local V: any
local sheet: any = nil
local sheetMenu: string? = nil

local MENU_TITLE = {
	pcbang = { "🍜 광안 PC방 메뉴", "주문하면 알바생이 자리로 가져다줘요 · 카운터 픽업도 OK" },
	bowling = { "🌶️ ROCK & BOWL 분식", "주문 후 픽업대에서 받아 가세요" },
}

local function effectText(def: any): string
	local parts = {}
	local names = { stamina = "체력", happiness = "행복", popularity = "인기", strength = "근력", appearance = "외모" }
	for k, v in def.effect or {} do
		table.insert(parts, string.format("%s +%s", names[k] or k, tostring(v)))
	end
	table.sort(parts)
	return table.concat(parts, " · ")
end

function Spots.close()
	if sheet then
		sheet.close()
	end
end

function Spots.openMenu(menuId: string)
	local items = V.MENUS[menuId]
	if not items then
		return
	end
	if sheet then
		sheet.close(true)
		sheet.frame:Destroy()
		sheet = nil
	end
	local t = MENU_TITLE[menuId] or { "메뉴", "" }
	local sh, scroll = C.sheet("VenueMenu", t[1], t[2], function()
		sheetMenu = nil
	end)
	for i, id in items do
		local def = V.FOOD[id]
		if def then
			local busy = false
			local r
			r = C.row(scroll, {
				name = "Food_" .. id,
				icon = def.icon,
				iconColor = K.Color.orange,
				title = def.name,
				subtitle = string.format("%s · %d초 조리", effectText(def), def.prep),
				trailing = V.won(def.price),
				trailingWidth = 84,
				height = 60,
				order = i,
				onClick = function()
					if busy then
						return
					end
					busy = true
					C.sound("tap")
					task.spawn(function()
						local res = C.request("order", { item = id })
						busy = false
						if res.ok then
							C.sound("ping", 1.2, 0.3)
							C.toast("success", def.icon .. " 주문 완료", res.message or def.name)
							Spots.close()
						else
							C.toast("warn", def.name, res.message or "주문할 수 없어요")
						end
					end)
				end,
			})
			local _ = r
		end
	end
	K.text(scroll, { Name = "Hint", Size = UDim2.new(1, 0, 0, 30), Text = "음식 효과는 하루에 몇 번만 받을 수 있어요 · 결제는 현금 먼저, 부족하면 체크카드", TextColor3 = K.Color.faint, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 20, ZIndex = 43 })
	sheet = sh
	sheetMenu = menuId
	sh.open()
end

function Spots.isOpen(): boolean
	return sheet ~= nil and sheet.isOpen()
end

function Spots.init(ctx: any)
	C = ctx
	K = ctx.K
	V = ctx.V
	C.openMenu = Spots.openMenu
	C.on("menu", function(p)
		if type(p.menu) == "string" then
			Spots.openMenu(p.menu)
		end
	end)
	C.on("ate", function(p)
		C.sound("ping", 1.4, 0.25)
		local def = V.FOOD[p.item]
		if def and p.applied and next(p.applied) then
			C.pop(C.gui, def.icon .. " 냠!", K.Color.gold, UDim2.new(0.5, 0, 0.22, 0), 26, 1.1)
		end
	end)
	C.on("punch", function(p)
		-- a quick count-up pop near the top of the screen (never over the centre for long)
		local score = tonumber(p.score) or 0
		local l = K.text(C.gui, {
			Name = "PunchScore",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 70),
			Size = UDim2.fromOffset(280, 64),
			Text = "🥊 0",
			TextColor3 = Color3.fromRGB(255, 96, 70),
			Font = K.Font.heavy,
			TextSize = 46,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			ZIndex = 55,
		})
		C.sound("swoosh", 0.8, 0.5)
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.7 do
				local u = (os.clock() - t0) / 0.7
				l.Text = string.format("🥊 %d", math.floor(score * (1 - (1 - u) ^ 3)))
				task.wait()
			end
			l.Text = string.format("🥊 %d", score)
			C.sound("ping", if score >= 800 then 1.6 else 1.1, 0.4)
			if p.rank == 1 then
				C.pop(C.gui, "👑 오늘의 펀치왕!", K.Color.gold, UDim2.new(0.5, 0, 0, 150), 24, 1.6)
			end
			task.wait(1.2)
			K.tween(l, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.wait(0.45)
			l:Destroy()
		end)
	end)
	local _ = sheetMenu
end

return Spots
