local M = require("./cat_mods")
local R = M.R
local s = R.Instance.new("Seat")
print(#s:GetTags(), s:HasTag("GwB_Screen"))
s:AddTag("GwB_Seat")
print(table.concat(s:GetTags(), ","), s:HasTag("GwB_Screen"))
local p = R.Instance.new("Part")
print(table.concat(p:GetTags(), ","))
