-- 카메라: photo mode. Hides every game overlay (phone button, money chip, tracker, GwangalliHUD via
-- HideGwangalliHUD) so the player can take a clean screenshot of Gwangalli; a single
-- "사진 모드 끝내기" button stays in the top-left corner. The character keeps moving.
-- Built with the GwangalliUI kit (also reachable from 설정 -> 사진 모드).

return function(ctx: any)
	local K, AppKit = ctx.K, ctx.AppKit

	local app = {}

	function app.build(body: Frame)
		local L = ctx.phone.layout()
		ctx.phone.header(body, "카메라")
		local content = AppKit.scroll(body, L.headerH, { name = "Content", gap = 10, topPad = 4 })
		local viewfinder = K.frame(content, { Name = "Viewfinder", Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
		K.corner(viewfinder, K.Radius.lg)
		K.gradient(viewfinder, { Color3.fromRGB(20, 24, 70), Color3.fromRGB(130, 60, 140), Color3.fromRGB(20, 30, 60) }, 90)
		local deck = K.frame(viewfinder, { Name = "Bridge", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.62), Size = UDim2.new(1, 0, 0, 3), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
		K.gradient(deck, K.Grad.bridge, 0)
		K.text(viewfinder, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "📷", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center })
		for _, pos in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
			local corner = K.frame(viewfinder, { Name = "Corner", AnchorPoint = Vector2.new(pos[1], pos[2]), Position = UDim2.new(pos[1], if pos[1] == 0 then 10 else -10, pos[2], if pos[2] == 0 then 10 else -10), Size = UDim2.fromOffset(16, 16) })
			K.stroke(corner, Color3.new(1, 1, 1), 2, 0.2)
		end
		K.text(content, { Name = "Info", Size = UDim2.new(1, 0, 0, 34), Text = "사진 모드에서는 화면의 버튼이 모두 숨겨져요.\n기기의 스크린샷 기능으로 광안리 야경을 찍어 보세요!", TextColor3 = K.Color.sub, TextSize = K.Type.micro, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
		K.Button(content, { name = "Start", text = "📸  사진 모드 시작", style = "bridge", size = UDim2.new(1, 0, 0, 44), order = 3, onClick = function()
			ctx.phone.home()
			ctx.phone.setPhotoMode(true)
		end })
		ctx.phone.onLayout(function()
			local l = ctx.phone.layout()
			content.Position = UDim2.fromOffset(0, l.headerH)
			content.Size = UDim2.new(1, 0, 1, -l.headerH)
		end)
	end

	function app.show() end
	function app.hide() end

	return app
end
