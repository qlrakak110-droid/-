-- GwangalliPhone/AppKit: shared scaffolding for the phone apps, built only from the GwangalliUI kit.
--   AppKit.scroll(parent, top, opts?)  -> ScrollingFrame (vertical list, 12 px side padding)
--   AppKit.conn(parent, ctx, order?)   -> {frame, update() -> ready: boolean}
--       loading skeleton while the profile is on its way ("연결 중…"), an error state with a retry
--       button when the server is offline, hidden once Net.hasProfile.
--   AppKit.clear(container, keep?)     destroys GuiObject children (except the `keep` set)
--   AppKit.keyOf(list, fn)             cheap change key for a list (rebuild only when it changes)

local AppKit = {}

function AppKit.scroll(parent: Instance, top: number, opts: { [string]: any }?): ScrollingFrame
	local o = opts or {}
	local s = Instance.new("ScrollingFrame")
	s.Name = o.name or "Scroll"
	s.Position = UDim2.fromOffset(0, top)
	s.Size = UDim2.new(1, 0, 1, -(top + (o.bottom or 0)))
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ScrollBarThickness = 3
	s.ScrollBarImageColor3 = Color3.fromRGB(170, 177, 196)
	s.ScrollBarImageTransparency = 0.4
	s.ElasticBehavior = Enum.ElasticBehavior.Always
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, o.gap or 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = s
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, o.side or 12)
	pad.PaddingRight = UDim.new(0, o.side or 12)
	pad.PaddingTop = UDim.new(0, o.topPad or 4)
	pad.PaddingBottom = UDim.new(0, o.bottomPad or 16)
	pad.Parent = s
	s.Parent = parent
	return s
end

function AppKit.clear(container: Instance, keep: { [Instance]: boolean }?)
	for _, c in container:GetChildren() do
		if c:IsA("GuiObject") and not (keep and keep[c]) then
			c:Destroy()
		end
	end
end

function AppKit.keyOf(list: { any }, fn: (any) -> string): string
	local parts = table.create(#list)
	for i, v in list do
		parts[i] = fn(v)
	end
	return table.concat(parts, "\30")
end

-- Connection state block for server apps.
function AppKit.conn(parent: Instance, ctx: any, order: number?): any
	local K, Net = ctx.K, ctx.Net
	local holder = K.frame(parent, { Name = "ConnState", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0, Visible = false })
	K.list(holder, false, 8)
	local skel = K.Skeleton(holder, { rows = 3, rowHeight = 56, order = 1 })
	local err = K.EmptyState(holder, {
		order = 2,
		icon = "📡",
		title = "서버에 연결할 수 없어요",
		body = "잠시 후 다시 시도해 주세요. 게임 서버가 준비되는 중일 수 있어요.",
		actionText = "다시 시도",
		color = K.Color.orange,
		onAction = function()
			Net.refresh()
		end,
	})
	local api = { frame = holder }
	function api.update(): boolean
		local ready = Net.hasProfile
		holder.Visible = not ready
		if not ready then
			local offline = Net.status == "offline"
			skel.Visible = not offline
			err.frame.Visible = offline
		end
		return ready
	end
	api.update()
	return api
end

return AppKit
