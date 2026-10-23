--!nocheck
local B = require("../out/bundle")
local Catalog = B.load("S", "Catalog")
local counts = {}
for _, id in Catalog.ORDER do
	local u = Catalog.uses(id)
	for k in u do counts[k] = (counts[k] or 0) + 1 end
end
for k, v in counts do print(k, v) end
for _, id in { "tc_tv_frame", "vr_firepit", "lv_fireplace", "hb_aquarium", "tc_speaker_tower", "st_wardrobe", "wl_curtain_linen", "lv_sofa_3seat", "bd_wood_queen", "lt_neon_wall", "kd_fishbowl", "kt_fridge_4door" } do
	local t = {}
	for k, v in Catalog.uses(id) do table.insert(t, k .. "=" .. tostring(v)) end
	table.sort(t)
	print(id, table.concat(t, " "))
end
