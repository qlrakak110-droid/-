-- TEMP facade smoke test (replaced by the Skyline module author)
local M = {}
function M.build(ctx)
	local F, P = ctx.Facade, ctx.Config.Palette
	F.tower(ctx.model, { style = "curtain", cf = CFrame.new(-200, 14, -800) * CFrame.Angles(0, math.rad(10), 0), w = 60, d = 50, h = 320, rng = ctx.rng, crown = "led", tiers = 2, glint = true })
	F.tower(ctx.model, { style = "round", cf = CFrame.new(-60, 14, -800), w = 50, d = 50, h = 260, rng = ctx.rng, crown = "spire" })
	F.tower(ctx.model, { style = "apartment", cf = CFrame.new(80, 14, -760), w = 84, d = 18, h = 90, rng = ctx.rng, label = "101", accent = P.LedBlue, crown = "frame" })
	F.tower(ctx.model, { style = "mid", cf = CFrame.new(200, 14, -800), w = 40, d = 40, h = 140, rng = ctx.rng, crown = "led" })
	F.tower(ctx.model, { style = "far", cf = CFrame.new(280, 14, -800), w = 40, d = 40, h = 100, rng = ctx.rng })
end
return M
