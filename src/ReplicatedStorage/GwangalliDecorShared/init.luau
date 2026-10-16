--!strict
-- GwangalliDecorShared: shared modules of the 내 집 마련 자유 배치 인테리어 add-on (GwangalliDecorPlus).
--   Server: ServerScriptService.GwangalliDecorPlus (Script)   Client: StarterPlayerScripts.GwangalliDecorPlus
--   Shared.Config  tunables              Shared.Text     Korean strings / 원 / 초성
--   Shared.Palette colours, materials    Shared.Catalog  >= 150 pieces (14 categories), specs, bounds
--   Shared.Geometry OBB math              Shared.Space    pure spatial index (rays / box queries)
--   Shared.Unit    home model scan        Shared.Rules    placement validation (server = final)
--   Shared.Path    reachability raster    Shared.Codec    compact save format + sanitizer
--   Shared.Finish  벽지 · 바닥 · 조명      Shared.Score    인테리어 점수 / 뱃지 / 목표
--   Shared.Spec    spec -> Model builder (server pieces, client ghosts, thumbnails)
-- Nothing yields at require time except WaitForChild on the sibling modules.

local Shared = {}

local function child(name: string): any
	local m = script:FindFirstChild(name) or script:WaitForChild(name, 15)
	assert(m, "[GwangalliDecorShared] missing module " .. name)
	return require(m)
end

Shared.Config = child("Config")
Shared.Text = child("Text")
Shared.Palette = child("Palette")
Shared.Catalog = child("Catalog")
Shared.Geometry = child("Geometry")
Shared.Space = child("Space")
Shared.Unit = child("Unit")
Shared.Path = child("Path")
Shared.Rules = child("Rules")
Shared.Codec = child("Codec")
Shared.Finish = child("Finish")
Shared.Score = child("Score")
Shared.Spec = child("Spec")

Shared.VERSION = Shared.Config.VERSION

return Shared
