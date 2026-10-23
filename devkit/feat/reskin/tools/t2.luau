local M = require("./cat_mods")
local R, F = M.R, M.Furniture
local m = F.build("sofa3", R.workspace, R.G.CFrame.new(), 1, {})
local CS = R.game:GetService("CollectionService")
for _, d in m:GetDescendants() do
	if d.Name == "Seat" then
		print(d.ClassName, table.concat(d:GetTags(), ","), CS:HasTag(d, "GwB_Screen"), d:HasTag("GwB_Screen"))
	end
end
