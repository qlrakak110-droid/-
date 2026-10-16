-- GwangalliPassesShared/KoFx: KO 피니시 이펙트 definitions (pure data). Stylised only: no blood / gore.
-- Built-in content only (rbxasset:// particles and sounds, plus sound ids the place already uses).
--   KoFx.LIST / KoFx.get(id)

local KoFx = {}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

KoFx.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

-- sounds: { id, fb (fallback when the id fails), vol, speed }
KoFx.SND = {
	boom = { id = "rbxassetid://82235785832022", fb = "rbxasset://sounds/action_jump_land.mp3", vol = 0.9, speed = 0.7 },
	ping = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.6, speed = 0.8 },
	pingHi = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.55, speed = 1.5 },
	swoosh = { id = "rbxasset://sounds/swoosh.wav", vol = 0.6, speed = 0.8 },
	crack = { id = "rbxasset://sounds/clickfast.wav", vol = 0.9, speed = 0.4 },
	coins = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.5, speed = 1.4 },
	thud = { id = "rbxassetid://132504023010884", fb = "rbxasset://sounds/action_jump_land.mp3", vol = 0.7, speed = 0.8 },
}

KoFx.LIST = {
	{ id = "lightning", name = "번개", glyph = "⚡", desc = "하늘에서 번개가 내리꽂히고 푸른 충격파", color = c(120, 210, 255), color2 = c(255, 255, 255), dur = 1.4, sounds = { "crack", "boom" } },
	{ id = "fireworks", name = "불꽃놀이", glyph = "🎆", desc = "광안리 불꽃축제처럼 머리 위로 폭죽 세 발", color = c(255, 200, 70), color2 = c(255, 80, 170), dur = 2.2, sounds = { "swoosh", "pingHi", "boom" } },
	{ id = "skull", name = "해골 마크", glyph = "💀", desc = "만화풍 해골 마크가 떠올랐다 사라져요", color = c(235, 235, 245), color2 = c(150, 90, 255), dur = 1.8, sounds = { "thud", "ping" } },
	{ id = "stars", name = "별 폭발", glyph = "🌟", desc = "노란 별이 사방으로 터지고 머리 위를 빙글빙글", color = c(255, 226, 90), color2 = c(255, 255, 255), dur = 1.8, sounds = { "pingHi", "swoosh" } },
	{ id = "money", name = "돈다발 비", glyph = "💸", desc = "만원짜리가 비처럼 쏟아져요", color = c(110, 200, 120), color2 = c(255, 214, 110), dur = 2.2, sounds = { "coins", "swoosh" } },
	{ id = "stamp", name = "K.O. 스탬프", glyph = "🥊", desc = "큼직한 K.O.! 도장과 먼지 링", color = c(255, 79, 163), color2 = c(255, 194, 71), dur = 1.6, sounds = { "thud", "crack" } },
}
KoFx.BY_ID = {}
for _, d in KoFx.LIST do
	KoFx.BY_ID[d.id] = d
end

function KoFx.get(id: any): any
	return if type(id) == "string" then KoFx.BY_ID[id] else nil
end

-- the attacker's short 승리 포즈: Roblox's own default emotes (owned by Roblox, playable in any experience;
-- the same ids ReplicatedStorage.GwangalliAnim / the default Animate script use)
KoFx.EMOTES = {
	R15 = { cheer = "rbxassetid://507770677", point = "rbxassetid://507770453" },
	R6 = { cheer = "rbxassetid://129423030", point = "rbxassetid://128853357" },
}
KoFx.EMOTE_FOR = { lightning = "point", fireworks = "cheer", skull = "point", stars = "cheer", money = "cheer", stamp = "point" }

return KoFx
