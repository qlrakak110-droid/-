local SS = require("./SS")
local shops = require("./shops")
local GW = { ["바다옷장"]="clothing", ["광안 서프 & SUP"]="surf", ["광안 떡볶이"]="snack", ["행복 돼지국밥"]="gukbap", ["광안 치킨"]="chicken", ["헤어살롱 물결"]="salon", ["바다약국"]="pharmacy" }
local byType, flows = {}, {}
for _, s in shops do
	local t, m
	if s.gw then local g = SS.GWSHOP[GW[s.name] or ""]; if g then t, m = g[1], g[2] end end
	if not t then t, m = SS.classify({ s.name }) end
	if not t then t, m = SS.classifyContents(s.props) end
	t = t or "-"
	local flow = SS.TYPES[t] and SS.TYPES[t].flow or "-"
	byType[t] = (byType[t] or 0) + 1
	flows[flow] = (flows[flow] or 0) + 1
	print(string.format("%-8s %-8s %-10s t=%d s=%d anc=%s clerk=%d %s", flow, t, tostring(m), s.tables, s.seats, tostring(s.anchor), s.clerks, s.name))
end
for k, v in byType do io.write(k, "=", v, " ") end print()
for k, v in flows do io.write(k, "=", v, " ") end print()
