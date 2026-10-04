-- GwangalliBuildingsShared: the shared half of 광안리 ENTERABLE BUILDINGS (건물 시스템).
--   local S = require(ReplicatedStorage.GwangalliBuildingsShared)
--   S.Config, S.Names, S.Util, S.Rng, S.Kit, S.Palette, S.Furniture, S.Menus, S.Homes, S.Billiards
-- Every submodule is a child ModuleScript of this one. Server: ServerScriptService.GwangalliBuildings.
-- Client: StarterPlayerScripts.GwangalliBuildingsClient. Contract: Names.

local Shared = {}

Shared.Config = require(script.Config)
Shared.Names = require(script.Names)
Shared.Util = require(script.Util)
Shared.Rng = require(script.Rng)
Shared.Kit = require(script.Kit)
Shared.Palette = require(script.Palette)
Shared.Furniture = require(script.Furniture)
Shared.Menus = require(script.Menus)
Shared.Homes = require(script.Homes)
Shared.Billiards = require(script.Billiards)

return Shared
